$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Set-Location -LiteralPath $PSScriptRoot
$form = New-Object Windows.Forms.Form
$form.Text = 'OTCv8 Headless - Teste de login'
$form.ClientSize = New-Object Drawing.Size(540,470)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$fields = @{}
$labels = @('Servidor do jogo','Porta do jogo','Conta','Senha','Personagem','Arquivo Tibia.dat')
$keys = @('host','port','account','password','character','dat')
for ($i=0; $i -lt $keys.Count; $i++) {
  $y = 18 + $i*48
  $label = New-Object Windows.Forms.Label
  $label.Text = $labels[$i]
  $label.Location = New-Object Drawing.Point(15,$y)
  $label.Size = New-Object Drawing.Size(155,24)
  $form.Controls.Add($label)
  $inputBox = New-Object Windows.Forms.TextBox
  $inputBox.Location = New-Object Drawing.Point(175,$y)
  $inputBox.Size = New-Object Drawing.Size(345,24)
  $form.Controls.Add($inputBox)
  $fields[$keys[$i]] = $inputBox
}
$fields.port.Text = '7172'
$fields.password.UseSystemPasswordChar = $true
$fields.dat.Width = 245
$browse = New-Object Windows.Forms.Button
$browse.Text = 'Selecionar'
$browse.Location = New-Object Drawing.Point(425,258)
$browse.Size = New-Object Drawing.Size(95,28)
$browse.Add_Click({
  $dialog = New-Object Windows.Forms.OpenFileDialog
  $dialog.Filter = 'Tibia DAT (*.dat)|*.dat'
  if ($dialog.ShowDialog() -eq 'OK') { $fields.dat.Text = $dialog.FileName }
  $dialog.Dispose()
})
$form.Controls.Add($browse)
$flags = @{}
$i=0
foreach($key in @('extended','frameGroups','frameDurations')) {
  $check = New-Object Windows.Forms.CheckBox
  $check.Text = $key
  $check.Location = New-Object Drawing.Point((15+$i*175),310)
  $check.Size = New-Object Drawing.Size(170,25)
  $check.Checked = ($key -ne 'frameDurations')
  $form.Controls.Add($check)
  $flags[$key]=$check
  $i++
}
$status = New-Object Windows.Forms.Label
$status.Location = New-Object Drawing.Point(15,345)
$status.Size = New-Object Drawing.Size(510,58)
$status.Text = 'Teste de um personagem. Movimento desativado. Informe o endereco real do servidor de jogo, nao o site.'
$form.Controls.Add($status)
function LuaString([string]$s) {
  $encoded = [System.Text.Encoding]::UTF8.GetBytes($s) | ForEach-Object { '\' + $_.ToString('D3') }
  return '"' + ($encoded -join '') + '"'
}
$start = New-Object Windows.Forms.Button
$start.Text = 'Iniciar login'
$start.Location = New-Object Drawing.Point(15,415)
$start.Size = New-Object Drawing.Size(145,36)
$start.Add_Click({
  try {
    $port = 0
    if (-not [int]::TryParse($fields.port.Text,[ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'Porta invalida.' }
    foreach($key in @('host','account','password','character')) {
      if ([string]::IsNullOrWhiteSpace($fields[$key].Text)) { throw "Preencha: $key" }
    }
    if (-not (Test-Path -LiteralPath $fields.dat.Text -PathType Leaf)) { throw 'Selecione o Tibia.dat.' }
    if (Get-Process -Name otclient_headless -ErrorAction SilentlyContinue) { throw 'Ja existe um cliente Headless aberto. Encerre o teste anterior.' }
    $dir = Join-Path $PSScriptRoot 'data\things\860'
    New-Item -ItemType Directory -Force $dir | Out-Null
    $dest = Join-Path $dir 'Tibia.dat'
    if ([IO.Path]::GetFullPath($fields.dat.Text) -ne [IO.Path]::GetFullPath($dest)) {
      Copy-Item -LiteralPath $fields.dat.Text -Destination $dest -Force
    }
    $lines = @('return {')
    foreach($key in @('host','account','character')) { $lines += "  $key = $(LuaString $fields[$key].Text.Trim())," }
    $lines += "  port = $port,"
    $lines += '  dat = "/data/things/860/Tibia.dat",'
    foreach($key in $flags.Keys) { $lines += "  $key = $($flags[$key].Checked.ToString().ToLowerInvariant())," }
    $lines += '  enableRoute = false,'
    $lines += '}'
    $cfg = Join-Path $PSScriptRoot 'headless-local.lua'
    if (Test-Path $cfg) {
      $answer = [Windows.Forms.MessageBox]::Show('Substituir a configuracao local anterior?','Configuracao','YesNo','Question')
      if ($answer -ne 'Yes') { return }
    }
    [IO.File]::WriteAllLines($cfg,[string[]]$lines,(New-Object Text.UTF8Encoding($false)))
    $env:OTC_HEADLESS_PASSWORD = $fields.password.Text
    try {
      $p = Start-Process -FilePath (Join-Path $PSScriptRoot 'otclient_headless.exe') -WorkingDirectory $PSScriptRoot -PassThru
    } finally {
      Remove-Item Env:OTC_HEADLESS_PASSWORD -ErrorAction SilentlyContinue
      $fields.password.Clear()
    }
    $status.Text = "Processo iniciado: $($p.Id). Consulte o log para confirmar a conexao."
  } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Erro') | Out-Null }
})
$form.Controls.Add($start)
$logButton = New-Object Windows.Forms.Button
$logButton.Text = 'Abrir log'
$logButton.Location = New-Object Drawing.Point(175,415)
$logButton.Size = New-Object Drawing.Size(145,36)
$logButton.Add_Click({
  $path = Join-Path $PSScriptRoot 'otclient-headless.log'
  if (Test-Path $path) { Start-Process notepad.exe -ArgumentList ('"'+$path+'"') }
  else { $status.Text = 'Log ainda nao encontrado.' }
})
$form.Controls.Add($logButton)
$stop = New-Object Windows.Forms.Button
$stop.Text = 'Encerrar teste'
$stop.Location = New-Object Drawing.Point(335,415)
$stop.Size = New-Object Drawing.Size(185,36)
$stop.Add_Click({
  Get-Process -Name otclient_headless -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq (Join-Path $PSScriptRoot 'otclient_headless.exe') } | Stop-Process
  $status.Text = 'Processo encerrado localmente.'
})
$form.Controls.Add($stop)
[void]$form.ShowDialog()
$form.Dispose()
