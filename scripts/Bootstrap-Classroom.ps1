[CmdletBinding()]
param(
    [string]$InstallRoot,
    [string]$CacheRoot,
    [switch]$ReplaceMismatchedExtensions,
    [switch]$InstallFusion
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PSScriptRoot '..\manifests\versions.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
$projectRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $projectRoot
$vscodeRoot = Split-Path -Parent $workspaceRoot
if (-not $InstallRoot) { $InstallRoot = Join-Path $vscodeRoot "Portable-VSCode-$($manifest.vscode.version)" }
if (-not $CacheRoot) { $CacheRoot = Join-Path $vscodeRoot $manifest.downloadCacheRelativePath }
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
$partialArchive = $null
$stageRoot = $null

function Get-ProductInfo([string]$Root) {
    $productFile = Get-ChildItem -LiteralPath $Root -Filter 'product.json' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\resources\\app\\product\.json$' } |
        Select-Object -First 1
    if (-not $productFile) { throw "Could not find resources\app\product.json below $Root." }
    $product = Get-Content -LiteralPath $productFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
    $packagePath = Join-Path (Split-Path -Parent $productFile.FullName) 'package.json'
    $package = if (Test-Path -LiteralPath $packagePath) { Get-Content -LiteralPath $packagePath -Raw -Encoding utf8 | ConvertFrom-Json } else { $null }
    if (-not $product.version -and $package) { $product | Add-Member -NotePropertyName version -NotePropertyValue $package.version -Force }
    if (-not $product.commit -and $package) { $product | Add-Member -NotePropertyName commit -NotePropertyValue $package.commit -Force }
    return $product
}

function Assert-CodeInstall([string]$Root, $Expected) {
    $code = Join-Path $Root 'Code.exe'
    if (-not (Test-Path -LiteralPath $code)) { throw "Code.exe is missing from $Root." }
    $signature = Get-AuthenticodeSignature -FilePath $code
    $publisher = ''
    if ($signature.SignerCertificate) {
        $publisher = $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    }
    if ($signature.Status -ne 'Valid' -or $publisher -ne $Expected.expectedPublisher) {
        throw "VS Code signature check failed: status=$($signature.Status), publisher=$publisher."
    }
    $product = Get-ProductInfo $Root
    if ($product.version -ne $Expected.version) {
        throw "VS Code version mismatch: expected $($Expected.version), found $($product.version)."
    }
    if ($Expected.commit -and $product.commit -ne $Expected.commit) {
        throw "VS Code commit mismatch: expected $($Expected.commit), found $($product.commit)."
    }
}

function Write-BatchFile([string]$Path, [string]$Content) {
    $windowsContent = $Content -replace "`r?`n", "`r`n"
    [IO.File]::WriteAllText($Path, $windowsContent, [Text.Encoding]::ASCII)
}

function Install-VSCodeIfMissing {
    if (Test-Path -LiteralPath (Join-Path $InstallRoot 'Code.exe')) {
        Assert-CodeInstall $InstallRoot $manifest.vscode
        Write-Host "VS Code $($manifest.vscode.version) is already present."
        return
    }

    if (Test-Path -LiteralPath $InstallRoot) {
        throw "InstallRoot exists but is not a verified VS Code install; inspect it and choose an empty target path: $InstallRoot"
    }

    $archiveCache = Join-Path $CacheRoot 'vscode'
    New-Item -ItemType Directory -Force -Path $archiveCache | Out-Null
    $archivePath = Join-Path $archiveCache "VSCode-$($manifest.vscode.version)-win32-x64.zip"
    if (-not (Test-Path -LiteralPath $archivePath)) {
        $url = $manifest.vscode.downloadUrlTemplate.Replace('{version}', $manifest.vscode.version)
        $partialArchive = "$archivePath.$PID.partial"
        Write-Host "Downloading VS Code $($manifest.vscode.version) from Microsoft's official update service..."
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $partialArchive -TimeoutSec 1800
        if ((Get-Item -LiteralPath $partialArchive).Length -lt 100MB) { throw 'Downloaded VS Code archive is unexpectedly small.' }
        Move-Item -LiteralPath $partialArchive -Destination $archivePath
        $partialArchive = $null
    }

    $archiveHashPath = "$archivePath.sha256"
    $archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($manifest.vscode.sha256 -and $archiveHash -ne $manifest.vscode.sha256.ToLowerInvariant()) { throw "VS Code ZIP SHA-256 mismatch: $archivePath" }
    if ($manifest.vscode.archiveSizeBytes -and (Get-Item -LiteralPath $archivePath).Length -ne [int64]$manifest.vscode.archiveSizeBytes) { throw "VS Code ZIP size mismatch: $archivePath" }
    if (Test-Path -LiteralPath $archiveHashPath) {
        $expectedHash = (Get-Content -LiteralPath $archiveHashPath -Raw -Encoding ascii).Trim().ToLowerInvariant()
        if ($expectedHash -ne $archiveHash) { throw "Cached VS Code ZIP checksum mismatch: $archivePath" }
    }

    $parent = Split-Path -Parent $InstallRoot
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $stageRoot = "$InstallRoot.repro-stage-$PID"
    if (Test-Path -LiteralPath $stageRoot) { throw "Staging directory already exists; inspect it before continuing: $stageRoot" }
    New-Item -ItemType Directory -Path $stageRoot | Out-Null
    Expand-Archive -LiteralPath $archivePath -DestinationPath $stageRoot -Force
    Assert-CodeInstall $stageRoot $manifest.vscode
    New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot 'data\user-data'), (Join-Path $stageRoot 'data\extensions'), (Join-Path $stageRoot 'data\home') | Out-Null
    [IO.File]::WriteAllText($archiveHashPath, $archiveHash, [Text.Encoding]::ASCII)
    Move-Item -LiteralPath $stageRoot -Destination $InstallRoot
    $stageRoot = $null
    Write-Host "Installed verified VS Code at $InstallRoot"
}

try {
    Install-VSCodeIfMissing

    $userData = Join-Path $InstallRoot 'data\user-data\User'
    New-Item -ItemType Directory -Force -Path $userData, (Join-Path $InstallRoot 'data\extensions'), (Join-Path $InstallRoot 'data\home\.codex') | Out-Null
    $settingsPath = Join-Path $userData 'settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        Copy-Item -LiteralPath (Join-Path $projectRoot 'config\settings.template.json') -Destination $settingsPath
    }

    & (Join-Path $PSScriptRoot 'Install-PortableTools.ps1') -InstallRoot $InstallRoot -CacheRoot $CacheRoot

    $extensionArgs = @{ InstallRoot = $InstallRoot; CacheRoot = $CacheRoot }
    if ($ReplaceMismatchedExtensions) { $extensionArgs.ReplaceMismatched = $true }
    & (Join-Path $PSScriptRoot 'Restore-Extensions.ps1') @extensionArgs

    & (Join-Path $PSScriptRoot 'Verify-Classroom.ps1') -InstallRoot $InstallRoot

    if ($InstallFusion) {
        $fusionCmd = Join-Path $workspaceRoot 'Fusion360-Installer\scripts\Install-Fusion.cmd'
        if (-not (Test-Path -LiteralPath $fusionCmd)) { throw "Fusion installer project is not present: $fusionCmd" }
        & $env:ComSpec /d /c "`"$fusionCmd`""
        if ($LASTEXITCODE -ne 0) { throw "Fusion installer returned exit code $LASTEXITCODE." }
    }

    Write-Host "Classroom repro is ready. Launch: $(Join-Path $InstallRoot 'Launch-VSCode.cmd')"
}
finally {
    if ($partialArchive -and (Test-Path -LiteralPath $partialArchive)) {
        Remove-Item -LiteralPath $partialArchive -Force -ErrorAction SilentlyContinue
    }
    if ($stageRoot -and (Test-Path -LiteralPath $stageRoot)) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
