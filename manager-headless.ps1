param([switch]$NoUi,[switch]$StartSaved,[switch]$SelfTest)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$script:root = $PSScriptRoot
$script:profileDir = Join-Path $root 'profiles'
$script:store = Join-Path $profileDir 'manager.json'
$script:processes = @{}
$script:profiles = @()
$script:utf8 = New-Object Text.UTF8Encoding($false)
function LuaString([string]$s) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($s)
    return '"' + (($bytes | ForEach-Object { '\' + $_.ToString('D3') }) -join '') + '"'
}
function Read-Route([string]$value) {
    $result = @()
    foreach ($line in ($value -split '\r?\n')) {
        $line = $line.Trim()
        if (!$line -or $line -eq '[Waypoints]') { continue }
        if ($line -notmatch '^(?:N\s+)?(\d+)[,\s]+(\d+)[,\s]+(\d+)$') { throw "Waypoint invalido: $line" }
        $x = [int]$Matches[1]; $y = [int]$Matches[2]; $z = [int]$Matches[3]
        if ($x -gt 65534 -or $y -gt 65534 -or $z -gt 15) { throw 'Coordenada fora do mapa.' }
        $result += @{x=$x;y=$y;z=$z}
    }
    return $result
}
function LuaPos($p) { return "{x=$($p.x),y=$($p.y),z=$($p.z)}" }
function One-Pos([string]$s) {
    $p = @(Read-Route $s)
    if ($p.Count -ne 1) { throw 'Informe uma coordenada x y z.' }
    return $p[0]
}
function Protect-Secret([string]$s) {
    if (!$s) { return '' }
    return (ConvertTo-SecureString $s -AsPlainText -Force | ConvertFrom-SecureString)
}
function Open-Secret([string]$s) {
    if (!$s) { return '' }
    $sec = ConvertTo-SecureString $s
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $sec.Dispose() }
}
function Write-Profile($p) {
    if ($p.id -notmatch '^[0-9a-f]{32}$') { throw 'Invalid profile identifier' }
    $lines = @('return {')
    foreach($key in @('host','account','character')) { $lines += "  $key = $(LuaString $p.$key)," }
    $port = [int]$p.port
    if ($port -lt 1 -or $port -gt 65535) { throw 'Porta invalida' }
    $lines += "  port = $port,"
    $lines += '  dat = "/data/things/860/Tibia.dat",'
    foreach ($k in @('extended','frameGroups','frameDurations','enableRoute')) {
        $lines += "  $k = $(([bool]$p.$k).ToString().ToLowerInvariant()),"
    }
    if ($p.enableRoute) {
        $lines += "  target = $(LuaPos (One-Pos $p.target)),"
        $lines += "  approach = { $((@(Read-Route $p.approach) | ForEach-Object { LuaPos $_ }) -join ',') },"
        if ($p.cart) {
            $id = [int]$p.cartId
            if ($id -lt 1 -or $id -gt 65535) { throw 'ID de objeto invalido' }
            $lines += "  usePosition = $(LuaPos (One-Pos $p.cart)), useItemId = $id,"
        }
    }
    $lines += '}'
    [IO.File]::WriteAllLines((Join-Path $profileDir ($p.id+'.lua')),[string[]]$lines,$utf8)
}
function Save-Profiles {
    New-Item -ItemType Directory -Force $profileDir | Out-Null
    $json = ConvertTo-Json -InputObject @($script:profiles) -Depth 6
    [IO.File]::WriteAllText($store,$json,$utf8)
}
function Start-Profile($p) {
    if ($script:processes.ContainsKey($p.id) -and !$script:processes[$p.id].HasExited) { return }
    if (!(Test-Path (Join-Path $root 'data\things\860\Tibia.dat'))) { throw 'Importe primeiro o Tibia.dat.' }
    Write-Profile $p
    $log = Join-Path $profileDir ($p.id+'.log')
    Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $root 'otclient_headless.exe'
    $psi.WorkingDirectory = $root
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['OTC_HEADLESS_PROFILE'] = $p.id
    $psi.EnvironmentVariables['OTC_HEADLESS_PASSWORD'] = Open-Secret $p.secret
    foreach($key in @('OTC_SOCKS_HOST','OTC_SOCKS_PORT','OTC_SOCKS_USER','OTC_SOCKS_PASSWORD')) {
        $psi.EnvironmentVariables.Remove($key)
    }
    if ($p.proxyHost) {
        $port = [int]$p.proxyPort
        if ($port -lt 1 -or $port -gt 65535) { throw 'Porta SOCKS5 invalida' }
        $psi.EnvironmentVariables['OTC_SOCKS_HOST'] = $p.proxyHost
        $psi.EnvironmentVariables['OTC_SOCKS_PORT'] = [string]$port
        $psi.EnvironmentVariables['OTC_SOCKS_USER'] = [string]$p.proxyUser
        $psi.EnvironmentVariables['OTC_SOCKS_PASSWORD'] = Open-Secret $p.proxySecret
    }
    try { $script:processes[$p.id] = [Diagnostics.Process]::Start($psi) }
    finally { $psi.EnvironmentVariables.Remove('OTC_HEADLESS_PASSWORD'); $psi.EnvironmentVariables.Remove('OTC_SOCKS_PASSWORD') }
}
function Stop-Profile($p) {
    if ($script:processes.ContainsKey($p.id)) {
        $proc = $script:processes[$p.id]
        if (!$proc.HasExited) { $proc.Kill(); $proc.WaitForExit(3000) | Out-Null }
    }
}
function Get-Status($p) {
    $state = 'Parado'; $position = ''; $ram = 0; $cpu = 0
    if ($script:processes.ContainsKey($p.id)) {
        $proc = $script:processes[$p.id]
        $proc.Refresh()
        if (!$proc.HasExited) {
            $state = 'Conectando'; $ram = [math]::Round($proc.WorkingSet64/1MB,1); $cpu = [math]::Round($proc.TotalProcessorTime.TotalSeconds,2)
        } else { $state = 'Encerrado' }
    }
    $log = Join-Path $profileDir ($p.id+'.log')
    if (Test-Path -LiteralPath $log) {
        $tail = (Get-Content -LiteralPath $log -Tail 100 -ErrorAction SilentlyContinue) -join "\n"
        $matchesPos = [regex]::Matches($tail,'Player position: ([\d,]+)')
        if ($matchesPos.Count) { $position = $matchesPos[$matchesPos.Count-1].Groups[1].Value }
        if ($state -eq 'Conectando' -and $tail -match 'Game started') { $state = 'Online' }
        if ($tail -match 'Login rejected|Connection error|Startup failed|Login timeout|FATAL ERROR') { $state = 'Falha' }
        elseif ($tail -match 'Disconnected\.') { $state = 'Desconectado' }
    }
    return @{State=$state;Position=$position;Ram=$ram;Cpu=$cpu}
}
if ($SelfTest) {
    if ((LuaString 'ab') -ne '"\097\098"') { throw 'Lua escaping failed' }
    $p = One-Pos '160 48 8'
    if ($p.z -ne 8 -or $p.x -ne 160) { throw 'Coordinate parser failed' }
    $s = Protect-Secret 'test-password'
    if ((Open-Secret $s) -ne 'test-password') { throw 'Secret storage failed' }
    Write-Output 'MANAGER_SELFTEST_OK'
    return
}
New-Item -ItemType Directory -Force $profileDir | Out-Null
if (Test-Path $store) { $script:profiles = @(Get-Content -Raw -LiteralPath $store | ConvertFrom-Json) }
if ($NoUi) {
    if (!$StartSaved) { throw 'Use -NoUi -StartSaved to launch saved profiles.' }
    try {
        foreach($p in $script:profiles) { Start-Profile $p; Start-Sleep -Milliseconds 250 }
        while (@($script:processes.Values | Where-Object { !$_.HasExited }).Count) {
            foreach($p in $script:profiles) {
                $s=Get-Status $p
                Write-Output ("{0}: {1} {2} RAM={3}MB CPU={4}s" -f $p.character,$s.State,$s.Position,$s.Ram,$s.Cpu)
            }
            Start-Sleep -Seconds 5
        }
    } finally { foreach($p in $script:profiles) { Stop-Profile $p } }
    return
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$form = New-Object Windows.Forms.Form
$form.Text = 'OTCv8 Headless - Gerenciador'
$form.Size = New-Object Drawing.Size(1160,790)
$form.MinimumSize = New-Object Drawing.Size(1160,790)
$form.StartPosition = 'CenterScreen'
$form.BackColor = [Drawing.Color]::FromArgb(25,25,28)
$form.ForeColor = [Drawing.Color]::White
$grid = New-Object Windows.Forms.DataGridView
$grid.Location = New-Object Drawing.Point(12,12)
$grid.Size = New-Object Drawing.Size(1115,245)
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.MultiSelect = $true
$grid.SelectionMode = 'FullRowSelect'
$grid.AutoSizeColumnsMode = 'Fill'
foreach($col in @('Personagem','Servidor','Estado','Posicao','RAM MB','CPU s')) { [void]$grid.Columns.Add($col,$col) }
$form.Controls.Add($grid)
$fields=@{}
$spec=@(
    @('character','Personagem',12,270,250),@('account','Conta',285,270,250),@('password','Senha',558,270,250),
    @('host','Servidor de jogo',12,325,250),@('port','Porta',285,325,100),@('proxyHost','SOCKS5 host (opcional)',405,325,250),@('proxyPort','Porta SOCKS5',675,325,120),
    @('proxyUser','Usuario SOCKS5',12,380,250),@('proxyPassword','Senha SOCKS5',285,380,250),
    @('target','Destino x y z',12,435,250),@('cart','Objeto x y z (opcional)',285,435,250),@('cartId','ID objeto',558,435,100),
    @('approach','Waypoints de aproximacao (um por linha)',12,490,650)
)
foreach($item in $spec) {
    $label=New-Object Windows.Forms.Label
    $label.Text=$item[1];$label.Location=New-Object Drawing.Point($item[2],$item[3]);$label.Size=New-Object Drawing.Size($item[4],20)
    $form.Controls.Add($label)
    $field=New-Object Windows.Forms.TextBox
    $field.Location=New-Object Drawing.Point($item[2],($item[3]+20))
    $field.Size=New-Object Drawing.Size($item[4],24)
    if($item[0] -eq 'approach') {$field.Multiline=$true;$field.ScrollBars='Vertical';$field.Height=90}
    if($item[0] -in @('password','proxyPassword')) {$field.UseSystemPasswordChar=$true}
    $fields[$item[0]]=$field;$form.Controls.Add($field)
}
$fields.port.Text='7172';$fields.target.Text='160 48 8'
$flags=@{};$i=0
foreach($k in @('extended','frameGroups','frameDurations','enableRoute')) {
    $check=New-Object Windows.Forms.CheckBox
    $check.Text=$k;$check.Location=New-Object Drawing.Point(835,(280+$i*35));$check.Size=New-Object Drawing.Size(250,28)
    $check.Checked=($k -in @('extended','frameGroups'))
    $flags[$k]=$check;$form.Controls.Add($check);$i++
}
$status=New-Object Windows.Forms.Label
$status.Location=New-Object Drawing.Point(12,620);$status.Size=New-Object Drawing.Size(1100,28)
$status.Text='Importe o DAT. Cadastre os perfis. O login depende do servidor de jogo correto.'
$form.Controls.Add($status)
function Refresh-Grid {
    $selected=@($grid.SelectedRows | ForEach-Object {$_.Tag})
    $grid.Rows.Clear()
    foreach($p in $script:profiles) {
        $s=Get-Status $p
        $i=$grid.Rows.Add($p.character,$p.host,$s.State,$s.Position,$s.Ram,$s.Cpu)
        $grid.Rows[$i].Tag=$p.id
        $grid.Rows[$i].Selected=($p.id -in $selected)
    }
}
function Selected-Profiles { $ids=@($grid.SelectedRows | ForEach-Object {$_.Tag}); return @($script:profiles | Where-Object {$_.id -in $ids}) }
function Add-Button($title,$x,$action) {
    $b=New-Object Windows.Forms.Button
    $b.Text=$title;$b.Location=New-Object Drawing.Point($x,660);$b.Size=New-Object Drawing.Size(150,36)
    $b.BackColor=[Drawing.Color]::FromArgb(125,30,38);$b.ForeColor=[Drawing.Color]::White
    $b.Add_Click($action);$form.Controls.Add($b)
}
Add-Button 'Importar DAT' 12 {
    try {
        if (@($script:processes.Values | Where-Object {!$_.HasExited}).Count) {throw 'Encerre os clientes antes de importar.'}
        $d=New-Object Windows.Forms.OpenFileDialog;$d.Filter='Tibia DAT (*.dat)|*.dat'
        if($d.ShowDialog() -eq 'OK'){
            $dir=Join-Path $root 'data\things\860';New-Item -ItemType Directory -Force $dir|Out-Null
            $dest=Join-Path $dir 'Tibia.dat'
            if([IO.Path]::GetFullPath($d.FileName) -ne [IO.Path]::GetFullPath($dest)){Copy-Item -LiteralPath $d.FileName -Destination $dest -Force}
            $status.Text='DAT importado.'
        };$d.Dispose()
    }catch{$status.Text=$_.Exception.Message}
}
Add-Button 'Adicionar perfil' 170 {
    try {
        foreach($k in @('character','account','password','host')){if([string]::IsNullOrWhiteSpace($fields[$k].Text)){throw "Preencha $k"}}
        $p=[ordered]@{id=[guid]::NewGuid().ToString('N');secret=(Protect-Secret $fields.password.Text);proxySecret=(Protect-Secret $fields.proxyPassword.Text)}
        foreach($k in @('character','account','host','port','proxyHost','proxyPort','proxyUser','target','cart','cartId','approach')){$p[$k]=$fields[$k].Text.Trim()}
        foreach($k in $flags.Keys){$p[$k]=$flags[$k].Checked}
        if(@($script:profiles|Where-Object {$_.character -eq $p.character -and $_.host -eq $p.host}).Count){throw 'Personagem ja cadastrado neste servidor.'}
        Write-Profile $p;$script:profiles+=([pscustomobject]$p);Save-Profiles
        $fields.password.Clear();$fields.proxyPassword.Clear();Refresh-Grid;$status.Text='Perfil cadastrado.'
    }catch{$status.Text=$_.Exception.Message}
}
Add-Button 'Iniciar selecionados' 328 {
    foreach($p in (Selected-Profiles)){try{Start-Profile $p}catch{$status.Text=$_.Exception.Message;break}}
    Refresh-Grid
}
Add-Button 'Iniciar todos' 486 {
    foreach($p in $script:profiles){try{Start-Profile $p}catch{$status.Text=$_.Exception.Message;break}}
    Refresh-Grid
}
Add-Button 'Parar selecionados' 644 {foreach($p in (Selected-Profiles)){Stop-Profile $p};Refresh-Grid}
Add-Button 'Abrir log' 802 {
    $p=@(Selected-Profiles)|Select-Object -First 1
    if($p){$path=Join-Path $profileDir ($p.id+'.log');if(Test-Path $path){Start-Process notepad.exe -ArgumentList ('"'+$path+'"')}}
}
Add-Button 'Excluir perfil' 960 {
    $selected=@(Selected-Profiles)
    if(!$selected.Count){return}
    if([Windows.Forms.MessageBox]::Show('Excluir os perfis selecionados?','Confirmar','YesNo','Question') -ne 'Yes'){return}
    foreach($p in $selected){Stop-Profile $p;Remove-Item -LiteralPath (Join-Path $profileDir ($p.id+'.lua')) -ErrorAction SilentlyContinue}
    $ids=@($selected|ForEach-Object {$_.id});$script:profiles=@($script:profiles|Where-Object {$_.id -notin $ids});Save-Profiles;Refresh-Grid
}
$timer=New-Object Windows.Forms.Timer;$timer.Interval=2000;$timer.Add_Tick({try{Refresh-Grid}catch{$status.Text=$_.Exception.Message}})
$form.Add_FormClosing({
    if(@($script:processes.Values|Where-Object {!$_.HasExited}).Count){
        if([Windows.Forms.MessageBox]::Show('Encerrar os clientes deste gerenciador?','Fechar','YesNo','Question') -ne 'Yes'){$_.Cancel=$true;return}
        foreach($p in $script:profiles){Stop-Profile $p}
    }
    $timer.Stop()
})
Refresh-Grid;$timer.Start();[void]$form.ShowDialog();$timer.Dispose();$form.Dispose()
