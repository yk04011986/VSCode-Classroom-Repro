[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [Parameter(Mandatory = $true)][string]$CacheRoot
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PSScriptRoot '..\manifests\versions.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
$toolsRoot = Join-Path $InstallRoot 'portable-tools'
$gitRoot = Join-Path $toolsRoot 'Git'
$uvRoot = Join-Path $toolsRoot 'uv'
$nodeRoot = Join-Path $toolsRoot 'Node'
$pythonRoot = Join-Path $toolsRoot 'Python'
$envNames = @('UV_PYTHON_INSTALL_DIR', 'UV_PYTHON_BIN_DIR', 'UV_CACHE_DIR')
$oldEnvironment = @{}
foreach ($name in $envNames) { $oldEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$runId = '{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$stageRoot = Join-Path $CacheRoot ".portable-tools-stage-$runId"

function Get-VersionOutput([string]$Executable, [string[]]$Arguments) {
    $result = & $Executable @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "$Executable returned exit code $code." }
    return (($result | Out-String).Trim())
}

function Get-GitHubAsset([string]$Repository, [string]$Tag, [string]$Pattern) {
    $encodedTag = [uri]::EscapeDataString($Tag)
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/tags/$encodedTag" -Headers @{ 'User-Agent' = 'VSCode-Classroom-Repro' } -TimeoutSec 60
    if ($release.tag_name -ne $Tag) { throw "GitHub returned the wrong release tag for ${Repository}: $($release.tag_name)" }
    $asset = $release.assets | Where-Object { $_.name -match $Pattern } | Select-Object -First 1
    if (-not $asset) { throw "No release asset matching $Pattern in ${Repository}@${Tag}." }
    return $asset
}

function Save-ReleaseAsset($Asset, [string]$Destination) {
    $partial = "$Destination.$PID.partial"
    try {
        if (Test-Path -LiteralPath $Destination) {
            $actualSize = (Get-Item -LiteralPath $Destination).Length
            if ($Asset.size -and $actualSize -ne [int64]$Asset.size) { throw "Cached asset size mismatch: $Destination" }
        }
        else {
            Invoke-WebRequest -UseBasicParsing -Uri $Asset.browser_download_url -OutFile $partial -TimeoutSec 1800
            $actualSize = (Get-Item -LiteralPath $partial).Length
            if ($Asset.size -and $actualSize -ne [int64]$Asset.size) { throw "Downloaded size mismatch for $($Asset.name)." }
            Move-Item -LiteralPath $partial -Destination $Destination
        }

        $hash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
        $sidecar = "$Destination.sha256"
        if (Test-Path -LiteralPath $sidecar) {
            $storedHash = (Get-Content -LiteralPath $sidecar -Raw -Encoding ascii).Trim().ToLowerInvariant()
            if ($storedHash -ne $hash) { throw "Cached asset SHA-256 mismatch for $Destination." }
        }
        if ($Asset.digest) {
            if ($Asset.digest -notmatch '^sha256:([0-9a-fA-F]{64})$') { throw "Unsupported GitHub digest for $($Asset.name): $($Asset.digest)" }
            if ($Matches[1].ToLowerInvariant() -ne $hash) { throw "GitHub SHA-256 digest mismatch for $($Asset.name)." }
        }
        else {
            Write-Warning "GitHub has no published SHA-256 digest for $($Asset.name); using HTTPS, size and embedded-version checks, and recording a local SHA-256 sidecar."
        }
        [IO.File]::WriteAllText($sidecar, $hash, [Text.Encoding]::ASCII)
        return $Destination
    }
    finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
    }
}

function Assert-ExactVersion([string]$Executable, [string[]]$Arguments, [string]$Expected, [string]$Label) {
    $actual = Get-VersionOutput $Executable $Arguments
    if ($actual -notmatch [regex]::Escape($Expected)) { throw "$Label version mismatch: expected $Expected; got '$actual'." }
    return $actual
}

function Write-BatchFile([string]$Path, [string]$Content) {
    $windowsContent = $Content -replace "`r?`n", "`r`n"
    [IO.File]::WriteAllText($Path, $windowsContent, [Text.Encoding]::ASCII)
}

try {
    if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot 'Code.exe'))) { throw "VS Code must be bootstrapped before tools: $InstallRoot" }
    New-Item -ItemType Directory -Force -Path $toolsRoot, $CacheRoot | Out-Null
    New-Item -ItemType Directory -Path $stageRoot | Out-Null

    $gitExe = Join-Path $gitRoot 'cmd\git.exe'
    if (Test-Path -LiteralPath $gitExe) {
        Assert-ExactVersion $gitExe @('--version') $manifest.portableTools.git.version 'Git' | Out-Null
    }
    elseif (Test-Path -LiteralPath $gitRoot) {
        throw "Git directory exists but has no verified executable; inspect it before continuing: $gitRoot"
    }
    else {
        $gitSpec = $manifest.portableTools.git
        $gitAsset = Get-GitHubAsset $gitSpec.githubRepository $gitSpec.releaseTag $gitSpec.assetPattern
        $gitCache = Join-Path (Join-Path $CacheRoot 'Git') $gitAsset.name
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $gitCache) | Out-Null
        $gitArchive = Save-ReleaseAsset $gitAsset $gitCache
        $gitStage = Join-Path $stageRoot 'Git'
        New-Item -ItemType Directory -Path $gitStage | Out-Null
        & $gitArchive "-o$gitStage" -y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'PortableGit extraction failed.' }
        $stagedGitExe = Join-Path $gitStage 'cmd\git.exe'
        Assert-ExactVersion $stagedGitExe @('--version') $gitSpec.version 'Staged Git' | Out-Null
        Move-Item -LiteralPath $gitStage -Destination $gitRoot
    }

    $uvExe = Join-Path $uvRoot 'uv.exe'
    if (Test-Path -LiteralPath $uvExe) {
        Assert-ExactVersion $uvExe @('--version') $manifest.portableTools.uv.version 'uv' | Out-Null
    }
    elseif (Test-Path -LiteralPath $uvRoot) {
        throw "uv directory exists but has no verified executable; inspect it before continuing: $uvRoot"
    }
    else {
        $uvSpec = $manifest.portableTools.uv
        $uvAsset = Get-GitHubAsset $uvSpec.githubRepository $uvSpec.releaseTag ('^' + [regex]::Escape($uvSpec.assetName) + '$')
        $uvCache = Join-Path (Join-Path $CacheRoot 'uv') $uvAsset.name
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $uvCache) | Out-Null
        $uvArchive = Save-ReleaseAsset $uvAsset $uvCache
        $uvExtract = Join-Path $stageRoot 'uv-extract'
        Expand-Archive -LiteralPath $uvArchive -DestinationPath $uvExtract -Force
        $stagedUv = Get-ChildItem -LiteralPath $uvExtract -Filter 'uv.exe' -File -Recurse | Select-Object -First 1
        if (-not $stagedUv) { throw 'uv.exe was not found in the pinned uv archive.' }
        $uvStage = Join-Path $stageRoot 'uv'
        Move-Item -LiteralPath $stagedUv.DirectoryName -Destination $uvStage
        $stagedUvExe = Join-Path $uvStage 'uv.exe'
        Assert-ExactVersion $stagedUvExe @('--version') $uvSpec.version 'Staged uv' | Out-Null
        Move-Item -LiteralPath $uvStage -Destination $uvRoot
    }

    $nodeSpec = $manifest.portableTools.node
    $nodeExe = Join-Path $nodeRoot 'node.exe'
    if (Test-Path -LiteralPath $nodeExe) {
        $nodeVersion = (& $nodeExe --version | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $nodeVersion -ne "v$($nodeSpec.version)") { throw "Node version mismatch: expected v$($nodeSpec.version), found '$nodeVersion'." }
        if (-not (Test-Path -LiteralPath (Join-Path $nodeRoot 'npm.cmd')) -or -not (Test-Path -LiteralPath (Join-Path $nodeRoot 'npx.cmd'))) { throw "npm.cmd or npx.cmd is missing from $nodeRoot." }
    }
    elseif (Test-Path -LiteralPath $nodeRoot) {
        throw "Node directory exists but has no verified executable; inspect it before continuing: $nodeRoot"
    }
    else {
        $nodeCache = Join-Path $CacheRoot 'node'
        New-Item -ItemType Directory -Force -Path $nodeCache | Out-Null
        $nodeArchiveName = "node-v$($nodeSpec.version)-win-x64.zip"
        $nodeArchive = Join-Path $nodeCache $nodeArchiveName
        if (-not (Test-Path -LiteralPath $nodeArchive)) {
            $nodePartial = "$nodeArchive.$PID.partial"
            try {
                Invoke-WebRequest -UseBasicParsing -Uri $nodeSpec.downloadUrlTemplate.Replace('{version}', $nodeSpec.version) -OutFile $nodePartial -TimeoutSec 1800
                Move-Item -LiteralPath $nodePartial -Destination $nodeArchive
            }
            finally {
                if (Test-Path -LiteralPath $nodePartial) { Remove-Item -LiteralPath $nodePartial -Force -ErrorAction SilentlyContinue }
            }
        }
        $expectedNodeHash = ([string]$nodeSpec.sha256).ToLowerInvariant()
        $actualNodeHash = (Get-FileHash -LiteralPath $nodeArchive -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expectedNodeHash -notmatch '^[0-9a-f]{64}$' -or $actualNodeHash -ne $expectedNodeHash) { throw "Node.js SHA-256 mismatch for $nodeArchiveName." }
        $nodeExtract = Join-Path $stageRoot 'node-extract'
        Expand-Archive -LiteralPath $nodeArchive -DestinationPath $nodeExtract -Force
        $stagedNodeExe = Get-ChildItem -LiteralPath $nodeExtract -Filter 'node.exe' -File -Recurse | Select-Object -First 1
        if (-not $stagedNodeExe) { throw 'node.exe was not found in the official Node.js ZIP.' }
        $nodeStage = Join-Path $stageRoot 'Node'
        Move-Item -LiteralPath $stagedNodeExe.DirectoryName -Destination $nodeStage
        $stagedNodeVersion = (& (Join-Path $nodeStage 'node.exe') --version | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $stagedNodeVersion -ne "v$($nodeSpec.version)") { throw "Staged Node version mismatch: expected v$($nodeSpec.version), found '$stagedNodeVersion'." }
        if (-not (Test-Path -LiteralPath (Join-Path $nodeStage 'npm.cmd')) -or -not (Test-Path -LiteralPath (Join-Path $nodeStage 'npx.cmd'))) { throw 'Node.js archive is missing npm.cmd or npx.cmd.' }
        Move-Item -LiteralPath $nodeStage -Destination $nodeRoot
    }

    $pythonExe = Join-Path $pythonRoot 'bin\python.exe'
    $env:UV_PYTHON_INSTALL_DIR = Join-Path $pythonRoot 'runtimes'
    $env:UV_PYTHON_BIN_DIR = Join-Path $pythonRoot 'bin'
    $env:UV_CACHE_DIR = Join-Path $pythonRoot 'cache'
    if (Test-Path -LiteralPath $pythonExe) {
        Assert-ExactVersion $pythonExe @('--version') $manifest.portableTools.python.version 'Python' | Out-Null
    }
    else {
        New-Item -ItemType Directory -Force -Path $env:UV_PYTHON_INSTALL_DIR, $env:UV_PYTHON_BIN_DIR, $env:UV_CACHE_DIR | Out-Null
        & $uvExe python install $manifest.portableTools.python.version --default --force
        if ($LASTEXITCODE -ne 0) { throw 'uv could not install the pinned Python runtime.' }
        Assert-ExactVersion $pythonExe @('--version') $manifest.portableTools.python.version 'Installed Python' | Out-Null
    }

    $dataRoot = Join-Path $InstallRoot 'data'
    $launch = @'
@echo off
setlocal
set "ELECTRON_RUN_AS_NODE="
set "ROOT=%~dp0"
set "VSCODE_PORTABLE_ROOT=%ROOT%"
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
chcp 65001 >nul
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
    $pythonWrapper = @'
@echo off
setlocal
set "ROOT=%~dp0..\"
set "PATH=%ROOT%portable-tools\Python\bin;%PATH%"
set "UV_PYTHON_INSTALL_DIR=%ROOT%portable-tools\Python\runtimes"
set "UV_PYTHON_BIN_DIR=%ROOT%portable-tools\Python\bin"
set "UV_CACHE_DIR=%ROOT%portable-tools\Python\cache"
"%ROOT%portable-tools\uv\uv.exe" run --python __PYTHON_VERSION__ --no-project python %*
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
'@
    $pythonWrapper = $pythonWrapper.Replace('__PYTHON_VERSION__', [string]$manifest.portableTools.python.version)
    $portableHome = Join-Path $dataRoot 'home'
    New-Item -ItemType Directory -Force -Path $portableHome, (Join-Path $dataRoot 'user-data'), (Join-Path $dataRoot 'extensions'), (Join-Path $portableHome '.codex') | Out-Null
    $portableScripts = Join-Path $InstallRoot 'scripts'
    New-Item -ItemType Directory -Force -Path $portableScripts | Out-Null
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\Initialize-PortableTerminal.ps1') -Destination $portableScripts -Force
    Write-BatchFile (Join-Path $InstallRoot 'Launch-VSCode.cmd') $launch
    Write-BatchFile (Join-Path $toolsRoot 'git.cmd') $gitWrapper
    Write-BatchFile (Join-Path $toolsRoot 'python.cmd') $pythonWrapper
    Write-Host "Portable tools match the locked versions in $manifestPath"
}
finally {
    foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name, $oldEnvironment[$name], 'Process') }
    if ($stageRoot -and (Test-Path -LiteralPath $stageRoot)) {
        try { Remove-Item -LiteralPath $stageRoot -Recurse -Force }
        catch { Write-Warning "Could not remove this run's temporary tool extraction: $stageRoot" }
    }
}
