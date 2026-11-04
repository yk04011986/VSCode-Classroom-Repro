param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$target = Join-Path $root '@@INSTALL_ROOT_LEAF@@'
$stage = Join-Path $root 'maintenance\vscode-stage\1.144.1'
$run = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $root "maintenance\vscode-backups\$run"
$logRoot = Join-Path $root 'maintenance\vscode-logs'
$logStarted = $false
$result = 0
$movedOld = @()
$movedNew = @()
$lock = $null

function Assert-Child([string]$Path, [string]$Parent) {
    $full = [IO.Path]::GetFullPath($Path)
    $boundary = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    if (-not $full.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) {throw "Unsafe path: $full"}
}
function Write-State([string]$Status) {
    [IO.File]::WriteAllText((Join-Path $backup 'state.json'), (@{status=$Status;target=$target;stage=$stage;movedOld=$movedOld;movedNew=$movedNew} | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($true))
}
function Get-PortableCodeProcesses {
    @(Get-Process -Name Code -ErrorAction SilentlyContinue | Where-Object {
        try {$_.Path -eq (Join-Path $target 'Code.exe')} catch {$false}
    })
}
function Close-PortableCode {
    $processes = @(Get-PortableCodeProcesses)
    if (-not $processes.Count) {return}
    Write-Host "Portable VS Code still has $($processes.Count) processes, including background processes."
    Write-Host 'Save all work first. Typing UPDATE authorizes closing this portable VS Code, including force-stopping remaining processes. Unsaved work may be lost.' -ForegroundColor Yellow
    $answer = Read-Host 'Type UPDATE to close it and continue, or press Enter to cancel'
    if ($answer -cne 'UPDATE') {throw 'Update cancelled; no processes were stopped.'}
    foreach ($process in $processes) {
        try {if ($process.MainWindowHandle -ne 0) {[void]$process.CloseMainWindow()}} catch {}
    }
    $deadline = (Get-Date).AddSeconds(10)
    while (@(Get-PortableCodeProcesses).Count -and (Get-Date) -lt $deadline) {Start-Sleep -Milliseconds 500}
    foreach ($process in @(Get-PortableCodeProcesses)) {
        # Recheck executable and start time to avoid stopping a reused process ID.
        $current = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
        if ($current -and $current.Path -eq (Join-Path $target 'Code.exe') -and $current.StartTime -eq $process.StartTime) {
            Stop-Process -InputObject $current -Force -ErrorAction Stop
        }
    }
    $deadline = (Get-Date).AddSeconds(10)
    while (@(Get-PortableCodeProcesses).Count -and (Get-Date) -lt $deadline) {Start-Sleep -Milliseconds 500}
    if (@(Get-PortableCodeProcesses).Count) {throw 'Portable VS Code processes are still running; no program files were changed.'}
    Write-Host 'Portable VS Code processes exited. Continuing update...'
}
try {
    $utf8 = [Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = $utf8
    $OutputEncoding = $utf8
    New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
    Start-Transcript -LiteralPath (Join-Path $logRoot "update-$run-$PID.log") | Out-Null
    $logStarted = $true
    $lock = [IO.File]::Open((Join-Path $root 'maintenance\vscode-update.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    foreach ($prior in @(Get-ChildItem -LiteralPath (Join-Path $root 'maintenance\vscode-backups') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $stateFile = Join-Path $_.FullName 'state.json'; if (Test-Path -LiteralPath $stateFile) {Get-Item -LiteralPath $stateFile} })) {
        $state = Get-Content -LiteralPath $prior.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($state.status -in @('in-progress','needs-recovery')) {throw "Prior update needs recovery: $($prior.FullName)"}
    }
    $installedExe = Join-Path $target 'Code.exe'
    if ((Test-Path -LiteralPath $installedExe) -and (Get-Item -LiteralPath $installedExe).VersionInfo.ProductVersion -eq '1.144.1') {
        Write-Host 'VS Code 1.144.1 is already installed. No update is needed.'
        return
    }
    if (-not (Test-Path -LiteralPath $stage -PathType Container)) {throw "Verified VS Code 1.144.1 stage payload is missing: $stage. No network download will be attempted."}
    $exe = Join-Path $stage 'Code.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {throw "Staged Code.exe is missing: $exe"}
    $sig = Get-AuthenticodeSignature -LiteralPath $exe
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {throw 'Staged Code.exe signature is invalid.'}
    if ((Get-Item -LiteralPath $exe).VersionInfo.ProductVersion -ne '1.144.1') {throw 'Unexpected staged version.'}
    $payload = @(Get-ChildItem -LiteralPath $stage -Force | Where-Object {$_.Name -ne 'debug.log'})
    $allowed = @('261c84cb1e','appx','bin','policies','tools','Code.exe','Code.VisualElementsManifest.xml')
    if ($payload.Count -ne $allowed.Count -or @($payload | Where-Object {$_.Name -notin $allowed}).Count) {throw 'Unexpected staged payload.'}
    $package = Get-Content -LiteralPath (Join-Path $stage '261c84cb1e\resources\app\package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($package.version -ne '1.144.1') {throw 'Staged package version mismatch.'}
    if ($CheckOnly) {Write-Host 'PASS: VS Code 1.144.1 payload, Microsoft signature and package validated.'; return}
    Close-PortableCode
    New-Item -ItemType Directory -Path $backup | Out-Null
    Write-State 'in-progress'
    $oldNames = @($allowed) + @(Get-ChildItem -LiteralPath $target -Directory | Where-Object {$_.Name -match '^[0-9a-f]{10}$'} | ForEach-Object {$_.Name})
    try {
        foreach ($name in @($oldNames | Select-Object -Unique)) {
            $old = Join-Path $target $name
            Assert-Child $old $target
            $saved = Join-Path $backup $name
            Assert-Child $saved $backup
            if (Test-Path -LiteralPath $old) {
                Move-Item -LiteralPath $old -Destination $saved
                $movedOld += $name
                Write-State 'in-progress'
            }
        }
        foreach ($item in $payload) {
            $destination = Join-Path $target $item.Name
            Assert-Child $item.FullName $stage
            Assert-Child $destination $target
            Move-Item -LiteralPath $item.FullName -Destination $destination
            $movedNew += $item.Name
            Write-State 'in-progress'
        }
        if ((Get-Item -LiteralPath (Join-Path $target 'Code.exe')).VersionInfo.ProductVersion -ne '1.144.1') {throw 'Installed version validation failed.'}
        foreach ($preserved in @('data','portable-tools','Launch-VSCode.cmd')) {
            if (-not (Test-Path -LiteralPath (Join-Path $target $preserved))) {throw "Missing portable configuration: $preserved"}
        }
        Write-State 'completed'
        Write-Host "VS Code updated successfully to 1.144.1. Previous program files: $backup"
    }
    catch {
        $failure = $_
        $restoreErrors = @()
        $restoreNew = @($movedNew)
        [array]::Reverse($restoreNew)
        foreach ($name in $restoreNew) {
            try {
                $current = Join-Path $target $name
                $staged = Join-Path $stage $name
                Assert-Child $current $target
                Assert-Child $staged $stage
                Move-Item -LiteralPath $current -Destination $staged
            } catch {$restoreErrors += $_.Exception.Message}
        }
        foreach ($name in $movedOld) {
            try {
                $saved = Join-Path $backup $name
                $original = Join-Path $target $name
                Assert-Child $saved $backup
                Assert-Child $original $target
                Move-Item -LiteralPath $saved -Destination $original
            } catch {$restoreErrors += $_.Exception.Message}
        }
        if ($restoreErrors.Count) {Write-State 'needs-recovery'; throw "Update failed; recovery needed in $backup. $($restoreErrors -join '; ')"}
        Write-State 'rolled-back'
        throw $failure
    }
}
catch {
    Write-Host ('UPDATE FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    $result = 1
}
finally {
    if ($lock) {$lock.Dispose()}
    if ($logStarted) {Stop-Transcript | Out-Null}
}
exit $result
