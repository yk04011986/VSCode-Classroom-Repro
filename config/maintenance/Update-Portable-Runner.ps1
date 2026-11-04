param([string]$InstallRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) '@@INSTALL_ROOT_LEAF@@'))
$ErrorActionPreference = 'Stop'
. (Join-Path $InstallRoot 'portable-tools\Initialize-Terminal.ps1')
$logRoot = Join-Path $InstallRoot 'portable-tools\update-logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$log = Join-Path $logRoot ('update-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID + '.log')
$result = 0
$transcribing = $false
try {
    Start-Transcript -LiteralPath $log | Out-Null
    $transcribing = $true
    Write-Host "Log: $log"
    & (Join-Path $PSScriptRoot 'Update-Portable.ps1') -InstallRoot $InstallRoot
}
catch {
    Write-Host ('UPDATE FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    $result = 1
}
finally {
    if ($transcribing) { Stop-Transcript | Out-Null }
}
Write-Host "Log saved: $log"
exit $result
