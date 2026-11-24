$ErrorActionPreference='Stop'
$PSScriptRootParent = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $PSScriptRootParent
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName=Join-Path $PSScriptRootParent 'otclient_headless.exe'
$psi.WorkingDirectory=$PSScriptRootParent
$psi.UseShellExecute=$false
$psi.CreateNoWindow=$true
$psi.Arguments='--headless-smoke'
$psi.EnvironmentVariables['OTC_HEADLESS_SMOKE_MS']='2500'
$p=[Diagnostics.Process]::Start($psi)
try {
    $session=$p.SessionId
    if(!$p.WaitForExit(20000)){throw 'Session 0 process timed out'}
    if($p.ExitCode -ne 0 -or $session -ne 0){throw "Session=$session exit=$($p.ExitCode)"}
    if(!(Select-String -Path otclient-headless.log -Pattern 'SMOKE_OK' -Quiet)){throw 'Missing smoke marker'}
    Set-Content session0-result.txt "SESSION0_OK session=$session"
} catch {
    Set-Content session0-result.txt $_.Exception.Message
    exit 1
} finally {if(!$p.HasExited){$p.Kill()}}
