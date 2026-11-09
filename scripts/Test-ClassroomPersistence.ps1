[CmdletBinding()]
param(
    [string]$InstallRoot,
    [string]$CacheRoot,
    [string]$ReportPath,
    [switch]$ConversationRestartConfirmed
)
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$outer=Split-Path (Split-Path $project -Parent) -Parent
$manifest=Get-Content -LiteralPath (Join-Path $project 'manifests\versions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $InstallRoot) {
    $existing=Join-Path $outer 'Portable-VSCode-1.142.0'
    $InstallRoot=if (Test-Path -LiteralPath $existing) {$existing} else {Join-Path $outer "Portable-VSCode-$($manifest.vscode.version)"}
}
$InstallRoot=[IO.Path]::GetFullPath($InstallRoot)
$outer=Split-Path $InstallRoot -Parent
if (-not $CacheRoot) {$CacheRoot=Join-Path $outer $manifest.downloadCacheRelativePath}
$checks=New-Object 'System.Collections.Generic.List[object]'
function Record([string]$Name,[string]$Status,[string]$Detail) {
    $checks.Add([pscustomobject]@{name=$Name;status=$Status;detail=$Detail})
    Write-Host "[$Status] ${Name}: $Detail"
}
$systemDrive=$env:SystemDrive
if ([IO.Path]::GetPathRoot($InstallRoot).TrimEnd('\') -ieq $systemDrive) {Record 'Persistent installation' 'FAIL' 'InstallRoot is on the restored system drive.'}
else {Record 'Persistent installation' 'PASS' 'InstallRoot is outside the system drive; storage retention must still be confirmed by the classroom administrator.'}
$exe=Join-Path $InstallRoot 'Code.exe'
if (Test-Path -LiteralPath $exe) {
    $version=(Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
    Record 'VS Code' $(if ($version -eq $manifest.vscode.version) {'PASS'} else {'WARN'}) "Installed $version; manifest $($manifest.vscode.version)."
} else {Record 'VS Code' 'FAIL' 'Code.exe is missing.'}
foreach ($relative in @('data\user-data\User\settings.json','data\extensions','data\home','.gitconfig')) {
    if ($relative -eq '.gitconfig') {$path=Join-Path $InstallRoot 'data\home\.gitconfig'} else {$path=Join-Path $InstallRoot $relative}
    Record $relative $(if(Test-Path -LiteralPath $path){'PASS'}else{'WARN'}) $(if(Test-Path -LiteralPath $path){'Retained under InstallRoot.'}else{'Not present; configure or restore from a private backup.'})
}
$launchPath=Join-Path $InstallRoot 'Launch-VSCode.cmd'
if (Test-Path -LiteralPath $launchPath) {
    $launch=Get-Content -LiteralPath $launchPath -Raw -Encoding ASCII
    foreach ($required in @('set "CODEX_HOME=%ROOT%data\home\.codex"','set "HOME=%ROOT%data\home"','set "USERPROFILE=%ROOT%data\home"','set "GIT_CONFIG_GLOBAL=%ROOT%data\home\.gitconfig"','chcp 65001 >nul','set "ELECTRON_RUN_AS_NODE="')) {
        Record 'Portable launcher' $(if($launch.Contains($required)){'PASS'}else{'FAIL'}) $required
    }
} else {Record 'Portable launcher' 'FAIL' 'Launch-VSCode.cmd missing.'}
$initCandidates=@((Join-Path $InstallRoot 'scripts\Initialize-PortableTerminal.ps1'),(Join-Path $InstallRoot 'portable-tools\Initialize-Terminal.ps1'))
$initializer=$initCandidates | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
if ($initializer) {
    $probe=@'
$ErrorActionPreference='Stop'
& '__INITIALIZER__'
@{input=[Console]::InputEncoding.CodePage;output=[Console]::OutputEncoding.CodePage;pipeline=$OutputEncoding.CodePage} | ConvertTo-Json -Compress
'@
    $probe=$probe.Replace('__INITIALIZER__',$initializer.Replace("'","''"))
    $json=& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command $probe
    if ($LASTEXITCODE -ne 0) {Record 'UTF-8 clean PowerShell' 'FAIL' 'Initializer failed without user profiles.'}
    else {
        $encoding=$json | ConvertFrom-Json
        Record 'UTF-8 clean PowerShell' $(if($encoding.input -eq 65001 -and $encoding.output -eq 65001 -and $encoding.pipeline -eq 65001){'PASS'}else{'FAIL'}) "Input=$($encoding.input); output=$($encoding.output); pipeline=$($encoding.pipeline)."
    }
} else {Record 'UTF-8 clean PowerShell' 'FAIL' 'Portable initializer missing.'}
foreach ($relative in @('portable-tools\Git\cmd\git.exe','portable-tools\uv\uv.exe','portable-tools\Python\bin\python.exe','portable-tools\Node\node.exe')) {
    Record $relative $(if(Test-Path -LiteralPath (Join-Path $InstallRoot $relative)){'PASS'}else{'WARN'}) 'Presence check; pinned versions are checked separately by Verify-Classroom.ps1.'
}
$codex=Join-Path $InstallRoot 'data\home\.codex'
$sessions=@(Get-ChildItem -LiteralPath (Join-Path $codex 'sessions') -File -Recurse -ErrorAction SilentlyContinue)
Record 'Codex D-drive storage' $(if(Test-Path -LiteralPath $codex){'PASS'}else{'WARN'}) "Storage location configured under InstallRoot; session files: $($sessions.Count). Private conversation content was not read."
if ($ConversationRestartConfirmed) {
    Record 'Codex restart retention' 'PASS' 'User confirmed the saved conversation remained accessible after restarting. This does not independently prove a C-drive restore.'
}
Record 'Codex restore limit' 'MANUAL' 'Conversation access after an actual C-drive restore, SQLite rollout paths and dual-store merges require separate validation.'
$cache=Join-Path $CacheRoot "vscode\VSCode-$($manifest.vscode.version)-win32-x64.zip"
if (Test-Path -LiteralPath $cache) {
    $match=(Get-FileHash -LiteralPath $cache -Algorithm SHA256).Hash -ieq $manifest.vscode.sha256
    Record 'Persistent VS Code ZIP' $(if($match){'PASS'}else{'FAIL'}) 'Cached archive compared to manifest SHA-256.'
} else {Record 'Persistent VS Code ZIP' 'WARN' 'No verified persistent ZIP cache; C: Downloads is not a durable source.'}
Record 'Authentication after reset' 'MANUAL' 'GitHub, VS Code sync and MCP services may require login again. Windows Credential Manager and DPAPI state may be reset with C:. No credentials are exported.'
Record 'Actual C-drive reset' 'MANUAL' 'This checks current files and a clean PowerShell subprocess. It does not simulate restoring C: or prove D: retention.'
$report=[ordered]@{checkedAt=(Get-Date -Format o);installRoot=$InstallRoot;checks=@($checks.ToArray());failures=@($checks | Where-Object {$_.status -eq 'FAIL'}).Count;warnings=@($checks | Where-Object {$_.status -eq 'WARN'}).Count}
if ($ReportPath) {
    $full=[IO.Path]::GetFullPath($ReportPath)
    New-Item -ItemType Directory -Force -Path (Split-Path $full -Parent) | Out-Null
    [IO.File]::WriteAllText($full,($report | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}
if ($report.failures) {exit 1}
