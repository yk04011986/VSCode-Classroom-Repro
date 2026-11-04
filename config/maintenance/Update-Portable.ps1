param(
    [string]$InstallRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) '@@INSTALL_ROOT_LEAF@@')
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$utf8 = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$global:OutputEncoding = $utf8
Write-Host 'Starting portable tool update (Git, uv, Python; VS Code is updated separately).'

$ProgressPreference = 'SilentlyContinue'
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$ToolsRoot = Join-Path $InstallRoot 'portable-tools'
$StageRoot = Join-Path $ToolsRoot '.download-stage'
$BackupParent = Join-Path $ToolsRoot '.update-backups'
$LockPath = Join-Path $ToolsRoot '.update.lock'
$RunId = '{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([Guid]::NewGuid().ToString('N').Substring(0, 8))
$RunStageRoot = Join-Path $StageRoot $RunId
$BackupRoot = Join-Path (Join-Path $ToolsRoot '.update-backups') $RunId
$GitRoot = Join-Path $ToolsRoot 'Git'
$UvRoot = Join-Path $ToolsRoot 'uv'
$PythonRoot = Join-Path $ToolsRoot 'Python'
$EnvNames = @('UV_PYTHON_INSTALL_DIR', 'UV_PYTHON_BIN_DIR', 'UV_CACHE_DIR')
$OldEnvironment = @{}
foreach ($name in $EnvNames) {
    $OldEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

$GitStage = Join-Path $RunStageRoot 'Git'
$UvStage = Join-Path $RunStageRoot 'uv'
$PythonStage = Join-Path $RunStageRoot 'Python'
$WrapperStage = Join-Path $RunStageRoot 'wrappers'
$UpdateSucceeded = $false
$LockStream = $null

if (-not (Test-Path (Join-Path $InstallRoot 'Code.exe'))) {
    throw "Code.exe was not found in InstallRoot: $InstallRoot"
}

function Get-LatestReleaseAsset([string]$ApiUrl, [string]$NamePattern) {
    $release = Invoke-RestMethod -Uri $ApiUrl -Headers @{ 'User-Agent' = 'Portable-VSCode-Updater' } -TimeoutSec 60
    $asset = $release.assets | Where-Object { $_.name -match $NamePattern } | Select-Object -First 1
    if (-not $asset) { throw "No release asset matching $NamePattern at $ApiUrl" }
    return [pscustomobject]@{ Release = $release; Asset = $asset }
}

function Save-VerifiedAsset($Asset, [string]$Destination) {
    $partial = "$Destination.partial"
    Write-Host ("Downloading {0} ({1:N1} MB)..." -f $Asset.name, ($Asset.size / 1MB))
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        & $curl.Source --fail --location --retry 2 --connect-timeout 30 --max-time 900 --output $partial $Asset.browser_download_url
        if ($LASTEXITCODE -ne 0) { throw "Download failed for $($Asset.name), curl exit code $LASTEXITCODE. Partial file: $partial" }
    }
    else {
        Invoke-WebRequest -UseBasicParsing -Uri $Asset.browser_download_url -OutFile $partial -TimeoutSec 900
    }
    Write-Host "Verifying $($Asset.name)..."


    $actualSize = (Get-Item -LiteralPath $partial).Length
    if ($Asset.size -and $actualSize -ne [int64]$Asset.size) {
        throw "Downloaded size mismatch for $($Asset.name): expected $($Asset.size), received $actualSize bytes."
    }

    $hash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Asset.digest) {
        if ($Asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') {
            throw "Unsupported GitHub asset digest format for $($Asset.name): $($Asset.digest)"
        }
        if ($hash -ne $Matches[1].ToLowerInvariant()) {
            throw "SHA-256 mismatch for downloaded asset $($Asset.name)."
        }
    }
    else {
        Write-Warning "GitHub did not publish a digest for $($Asset.name); only the HTTPS transfer and advertised size were checked."
    }

    Move-Item -LiteralPath $partial -Destination $Destination
    return [pscustomobject]@{ Path = $Destination; Sha256 = $hash; Size = $actualSize }
}

function Get-CommandVersion([string]$Executable, [string[]]$Arguments, [string]$Label) {
    $output = & $Executable @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "$Label validation failed with exit code $code." }
    $version = ($output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($version)) { throw "$Label returned no version information." }
    return $version
}

function Write-StagedText([string]$Path, [string]$Content) {
    $windowsContent = $Content -replace "`r?`n", "`r`n"
    [IO.File]::WriteAllText($Path, $windowsContent, [Text.Encoding]::ASCII)
}

function Write-TransactionState([string]$Path, $State) {
    $json = $State | ConvertTo-Json -Depth 6
    $temporaryPath = "$Path.tmp"
    [IO.File]::WriteAllText($temporaryPath, $json, [Text.UTF8Encoding]::new($true))
    if (Test-Path -LiteralPath $Path) {
        [IO.File]::Replace($temporaryPath, $Path, [NullString]::Value)
    }
    else {
        Move-Item -LiteralPath $temporaryPath -Destination $Path
    }
}

$backedUpRoots = @()
$installedRoots = @()
$changedWrappers = @()
$rootMoves = @(
    [pscustomobject]@{ Name = 'Git'; Stage = $GitStage; Target = $GitRoot },
    [pscustomobject]@{ Name = 'uv'; Stage = $UvStage; Target = $UvRoot },
    [pscustomobject]@{ Name = 'Python'; Stage = $PythonStage; Target = $PythonRoot }
)
$wrapperMoves = @()
$wrapperBackupRoot = Join-Path $BackupRoot 'wrappers'
$manifestPath = Join-Path $ToolsRoot 'versions.json'
$manifestStage = Join-Path $WrapperStage 'versions.json'

New-Item -ItemType Directory -Force -Path $ToolsRoot | Out-Null

try {
    # FileShare.None is released by Windows if PowerShell exits unexpectedly.
    try {
        $LockStream = [IO.File]::Open($LockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
    catch {
        throw "Could not acquire the portable-tools update lock at $LockPath. Another updater may be running, or the lock path is unavailable."
    }
    $lockInfo = [Text.Encoding]::UTF8.GetBytes("PID=$PID RunId=$RunId`r`n")
    $LockStream.SetLength(0)
    $LockStream.Write($lockInfo, 0, $lockInfo.Length)
    $LockStream.Flush()

    if (Test-Path -LiteralPath $BackupParent) {
        foreach ($priorRun in (Get-ChildItem -LiteralPath $BackupParent -Directory -ErrorAction SilentlyContinue)) {
            $priorStatePath = Join-Path $priorRun.FullName 'transaction.json'
            if (Test-Path -LiteralPath $priorStatePath) {
                $priorState = Get-Content -LiteralPath $priorStatePath -Raw | ConvertFrom-Json
                if ($priorState.status -in @('in-progress', 'needs-recovery')) {
                    throw "An interrupted update needs recovery before starting another: $($priorRun.FullName). Restore the previous tool folders from this backup or inspect transaction.json."
                }
            }
        }
    }

    New-Item -ItemType Directory -Force -Path $RunStageRoot, $PythonStage, $WrapperStage | Out-Null

    Write-Host '[1/6] Checking Git release...'
    $gitRelease = Get-LatestReleaseAsset 'https://api.github.com/repos/git-for-windows/git/releases/latest' '^PortableGit-.*-64-bit\.7z\.exe$'
    $gitAssetFile = Join-Path $RunStageRoot $gitRelease.Asset.name
    $gitDownload = Save-VerifiedAsset $gitRelease.Asset $gitAssetFile

    Write-Host '[2/6] Extracting and validating Git...'
    $gitExtract = Join-Path $RunStageRoot 'git-extract'
    New-Item -ItemType Directory -Force -Path $gitExtract | Out-Null
    & $gitDownload.Path "-o$gitExtract" -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract PortableGit.' }
    $stagedGitExe = Join-Path $gitExtract 'cmd\git.exe'
    if (-not (Test-Path -LiteralPath $stagedGitExe)) { throw 'PortableGit archive did not contain cmd\git.exe.' }
    $gitVersion = Get-CommandVersion $stagedGitExe @('--version') 'Staged PortableGit'
    Move-Item -LiteralPath $gitExtract -Destination $GitStage

    Write-Host '[3/6] Checking uv release...'
    $uvRelease = Get-LatestReleaseAsset 'https://api.github.com/repos/astral-sh/uv/releases/latest' '^uv-x86_64-pc-windows-msvc\.zip$'
    $uvAssetFile = Join-Path $RunStageRoot $uvRelease.Asset.name
    $uvDownload = Save-VerifiedAsset $uvRelease.Asset $uvAssetFile

    $uvExtract = Join-Path $RunStageRoot 'uv-extract'
    Expand-Archive -LiteralPath $uvDownload.Path -DestinationPath $uvExtract -Force
    $stagedUv = Get-ChildItem -LiteralPath $uvExtract -Filter 'uv.exe' -File -Recurse | Select-Object -First 1
    if (-not $stagedUv) { throw 'uv.exe was not found in its downloaded archive.' }
    $uvVersion = Get-CommandVersion $stagedUv.FullName @('--version') 'Staged uv'
    Move-Item -LiteralPath $stagedUv.DirectoryName -Destination $UvStage
    $stagedUvExe = Join-Path $UvStage 'uv.exe'
    if (-not (Test-Path -LiteralPath $stagedUvExe)) { throw 'Could not stage uv.exe.' }

    $pythonStageRuntimes = Join-Path $PythonStage 'runtimes'
    $pythonStageBin = Join-Path $PythonStage 'bin'
    $pythonStageCache = Join-Path $PythonStage 'cache'
    $env:UV_PYTHON_INSTALL_DIR = $pythonStageRuntimes
    $env:UV_PYTHON_BIN_DIR = $pythonStageBin
    $env:UV_CACHE_DIR = $pythonStageCache
    New-Item -ItemType Directory -Force -Path $pythonStageRuntimes, $pythonStageBin, $pythonStageCache | Out-Null
    Write-Host '[4/6] Installing Python into staging...'
    & $stagedUvExe python install 3.14 --default
    if ($LASTEXITCODE -ne 0) { throw 'uv could not stage the managed Python 3.14 runtime.' }
    $stagedPythonExe = Get-ChildItem -LiteralPath $pythonStageRuntimes -Filter 'python.exe' -File -Recurse | Select-Object -First 1
    if (-not $stagedPythonExe) { throw 'Staged Python runtime did not contain python.exe.' }
    $pythonVersion = Get-CommandVersion $stagedPythonExe.FullName @('--version') 'Staged Python runtime'

    $innerLaunch = @'
@echo off
setlocal
chcp 65001 >nul
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
set "ELECTRON_RUN_AS_NODE="
set "ROOT=%~dp0"
set "VSCODE_PORTABLE_ROOT=%ROOT%"
set "PATH=%ROOT%portable-tools\Git\cmd;%ROOT%portable-tools\Python\bin;%ROOT%portable-tools\uv;%ROOT%portable-tools\Node;%PATH%"
set "HOME=%ROOT%data\home"
set "USERPROFILE=%ROOT%data\home"
set "CODEX_HOME=%ROOT%data\home\.codex"
set "GIT_CONFIG_GLOBAL=%ROOT%data\home\.gitconfig"
set "UV_PYTHON_INSTALL_DIR=%ROOT%portable-tools\Python\runtimes"
set "UV_PYTHON_BIN_DIR=%ROOT%portable-tools\Python\bin"
set "UV_CACHE_DIR=%ROOT%portable-tools\Python\cache"
"%ROOT%Code.exe" %*
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
'@
    $pythonWrapper = @'
@echo off
setlocal
set "ROOT=%~dp0..\"
set "PATH=%ROOT%portable-tools\Python\bin;%PATH%"
set "UV_PYTHON_INSTALL_DIR=%ROOT%portable-tools\Python\runtimes"
set "UV_PYTHON_BIN_DIR=%ROOT%portable-tools\Python\bin"
set "UV_CACHE_DIR=%ROOT%portable-tools\Python\cache"
"%ROOT%portable-tools\uv\uv.exe" run --python 3.14 --no-project python %*
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
'@
    $gitWrapper = @'
@echo off
setlocal
set "ROOT=%~dp0..\"
set "PATH=%ROOT%portable-tools\Git\cmd;%PATH%"
set "HOME=%ROOT%data\home"
set "USERPROFILE=%ROOT%data\home"
set "GIT_CONFIG_GLOBAL=%ROOT%data\home\.gitconfig"
"%ROOT%portable-tools\Git\cmd\git.exe" %*
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
'@

    $innerLaunchStage = Join-Path $WrapperStage 'Launch-VSCode.cmd'
    $gitWrapperStage = Join-Path $WrapperStage 'git.cmd'
    $pythonWrapperStage = Join-Path $WrapperStage 'python.cmd'
    Write-StagedText $innerLaunchStage $innerLaunch
    Write-StagedText $gitWrapperStage $gitWrapper
    Write-StagedText $pythonWrapperStage $pythonWrapper
    $wrapperMoves = @(
        [pscustomobject]@{ Name = 'Launch-VSCode.cmd'; Stage = $innerLaunchStage; Target = (Join-Path $InstallRoot 'Launch-VSCode.cmd') },
        [pscustomobject]@{ Name = 'git.cmd'; Stage = $gitWrapperStage; Target = (Join-Path $ToolsRoot 'git.cmd') },
        [pscustomobject]@{ Name = 'python.cmd'; Stage = $pythonWrapperStage; Target = (Join-Path $ToolsRoot 'python.cmd') }
    )

    $manifest = [ordered]@{
        updatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        git = [ordered]@{ release = $gitRelease.Release.tag_name; version = $gitVersion; sha256 = $gitDownload.Sha256; size = $gitDownload.Size }
        uv = [ordered]@{ release = $uvRelease.Release.tag_name; version = $uvVersion; sha256 = $uvDownload.Sha256; size = $uvDownload.Size }
        python = [ordered]@{ version = $pythonVersion; managedVersion = '3.14' }
    }
    [IO.File]::WriteAllText($manifestStage, ($manifest | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($true))
    $wrapperMoves += [pscustomobject]@{ Name = 'versions.json'; Stage = $manifestStage; Target = $manifestPath }

    Write-Host '[5/6] Backing up and replacing tools...'
    New-Item -ItemType Directory -Force -Path $BackupRoot, $wrapperBackupRoot | Out-Null
    $transactionPath = Join-Path $BackupRoot 'transaction.json'
    $transactionState = [ordered]@{
        runId = $RunId
        startedUtc = (Get-Date).ToUniversalTime().ToString('o')
        status = 'in-progress'
        phase = 'backing-up'
        rootNames = @($rootMoves | ForEach-Object { $_.Name })
        rootsPresentBefore = @($rootMoves | Where-Object { Test-Path -LiteralPath $_.Target } | ForEach-Object { $_.Name })
        wrappersPresentBefore = @($wrapperMoves | Where-Object { Test-Path -LiteralPath $_.Target } | ForEach-Object { $_.Name })
    }
    Write-TransactionState $transactionPath $transactionState
    try {
        foreach ($wrapper in $wrapperMoves) {
            if (Test-Path -LiteralPath $wrapper.Target) {
                Copy-Item -LiteralPath $wrapper.Target -Destination (Join-Path $wrapperBackupRoot $wrapper.Name) -Force
            }
        }
        foreach ($root in $rootMoves) {
            if (Test-Path -LiteralPath $root.Target) {
                try {
                    Move-Item -LiteralPath $root.Target -Destination (Join-Path $BackupRoot $root.Name)
                }
                catch {
                    throw "Cannot back up $($root.Name): $($_.Exception.Message) Close portable VS Code and its terminals, then run Update-Portable.cmd from File Explorer. If this persists after closing VS Code, check folder permissions. Existing tools will be restored."
                }
                $backedUpRoots += $root.Name
            }
        }
        $transactionState.phase = 'installing'
        Write-TransactionState $transactionPath $transactionState
        foreach ($root in $rootMoves) {
            # Every prior root has already been backed up before this loop starts.
            $installedRoots += $root.Name
            Move-Item -LiteralPath $root.Stage -Destination $root.Target
        }

        # uv's Windows launcher embeds the runtime path. Rebuild it after the staged
        # runtime has reached its permanent location so it cannot point into staging.
        $env:UV_PYTHON_INSTALL_DIR = Join-Path $PythonRoot 'runtimes'
        $env:UV_PYTHON_BIN_DIR = Join-Path $PythonRoot 'bin'
        $env:UV_CACHE_DIR = Join-Path $PythonRoot 'cache'
        & (Join-Path $UvRoot 'uv.exe') python install 3.14 --default --force
        if ($LASTEXITCODE -ne 0) { throw 'uv could not create Python launchers in the installed location.' }

        foreach ($wrapper in $wrapperMoves) {
            # Register before moving so rollback also handles a partially failed move.
            $changedWrappers += $wrapper.Name
            Move-Item -LiteralPath $wrapper.Stage -Destination $wrapper.Target -Force
        }

        Write-Host '[6/6] Validating installed tools...'
        $transactionState.phase = 'validating'
        Write-TransactionState $transactionPath $transactionState

        Get-CommandVersion (Join-Path $GitRoot 'cmd\git.exe') @('--version') 'Installed PortableGit' | Out-Null
        Get-CommandVersion (Join-Path $UvRoot 'uv.exe') @('--version') 'Installed uv' | Out-Null
        Get-CommandVersion (Join-Path $PythonRoot 'bin\python.exe') @('--version') 'Installed Python' | Out-Null
        $transactionState.status = 'completed'
        $transactionState.completedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Write-TransactionState $transactionPath $transactionState
    }
    catch {
        $updateError = $_
        $rollbackErrors = @()

        foreach ($name in @('versions.json', 'python.cmd', 'git.cmd', 'Launch-VSCode.cmd')) {
            if ($changedWrappers -contains $name) {
                $target = ($wrapperMoves | Where-Object { $_.Name -eq $name } | Select-Object -First 1).Target
                $oldWrapper = Join-Path $wrapperBackupRoot $name
                try {
                    if (Test-Path -LiteralPath $oldWrapper) { Copy-Item -LiteralPath $oldWrapper -Destination $target -Force }
                    elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
                }
                catch { $rollbackErrors += "Could not restore ${name}: $($_.Exception.Message)" }
            }
        }

        $rootsToRestore = @($rootMoves)
        [array]::Reverse($rootsToRestore)
        foreach ($root in $rootsToRestore) {
            try {
                $oldRoot = Join-Path $BackupRoot $root.Name
                if ($installedRoots -contains $root.Name -and (Test-Path -LiteralPath $root.Target)) {
                    Remove-Item -LiteralPath $root.Target -Recurse -Force
                }
                if ($backedUpRoots -contains $root.Name -and (Test-Path -LiteralPath $oldRoot)) {
                    Move-Item -LiteralPath $oldRoot -Destination $root.Target
                }
            }
            catch { $rollbackErrors += "Could not restore $($root.Name): $($_.Exception.Message)" }
        }

        if ($rollbackErrors.Count -gt 0) {
            $transactionState.status = 'needs-recovery'
            $transactionState.error = $updateError.Exception.Message
            $transactionState.rollbackErrors = @($rollbackErrors)
            try { Write-TransactionState $transactionPath $transactionState } catch { }
            throw "Update failed: $($updateError.Exception.Message) Rollback also reported: $($rollbackErrors -join '; '). Backup retained at $BackupRoot; staging retained at $RunStageRoot."
        }
        $transactionState.status = 'rolled-back'
        $transactionState.error = $updateError.Exception.Message
        Write-TransactionState $transactionPath $transactionState
        throw $updateError
    }

    $UpdateSucceeded = $true
    Write-Host "Portable Git, uv, and Python updated successfully. Previous tools are backed up at $BackupRoot"
    Write-Host "Versions and download hashes recorded in $manifestPath"
}
finally {
    try {
        foreach ($name in $EnvNames) {
            [Environment]::SetEnvironmentVariable($name, $OldEnvironment[$name], 'Process')
        }
        if ($UpdateSucceeded -and (Test-Path -LiteralPath $RunStageRoot)) {
            try { Remove-Item -LiteralPath $RunStageRoot -Recurse -Force }
            catch { Write-Warning "Update succeeded, but staging cleanup failed at ${RunStageRoot}: $($_.Exception.Message)" }
        }
    }
    finally {
        if ($LockStream) { $LockStream.Dispose() }
    }
}
