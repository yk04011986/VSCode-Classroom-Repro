[CmdletBinding()]
param(
    [string]$InstallRoot,
    [string]$CacheRoot,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $projectRoot 'manifests\versions.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$extensionsPath = Join-Path (Split-Path -Parent $manifestPath) $manifest.extensionManifest
$extensions = Get-Content -LiteralPath $extensionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$workspaceRoot = Split-Path -Parent $projectRoot
$vscodeRoot = Split-Path -Parent $workspaceRoot
if (-not $InstallRoot) { $InstallRoot = Join-Path $vscodeRoot "Portable-VSCode-$($manifest.vscode.version)" }
if (-not $CacheRoot) { $CacheRoot = Join-Path $vscodeRoot $manifest.downloadCacheRelativePath }
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$CacheRoot = [IO.Path]::GetFullPath($CacheRoot)
if (-not $ReportPath) { $ReportPath = Join-Path $projectRoot 'output\offline-cache-report.json' }
$ReportPath = [IO.Path]::GetFullPath($ReportPath)

$items = [System.Collections.Generic.List[object]]::new()
function Add-InventoryItem {
    param([string]$Name,[string]$Version,[string]$ExpectedPath,[string]$FoundPath,[string]$Status,[Nullable[long]]$Bytes,[string]$Sha256,[string]$Note,[string]$IntegrityState='NOT_ASSESSED',[string]$OriginState='UNKNOWN')
    $items.Add([pscustomobject]@{
        name = $Name; version = $Version; expectedPath = $ExpectedPath; foundPath = $FoundPath
        status = $Status; bytes = $Bytes; sha256 = $Sha256; note = $Note
        integrityState = $IntegrityState; originState = $OriginState
    })
}
function Get-RelativePath([string]$Path,[string]$Base) {
    if (-not $Path) { return $null }
    $baseFull = [IO.Path]::GetFullPath($Base).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($Path)
    if ($full.StartsWith($baseFull,[StringComparison]::OrdinalIgnoreCase)) { return $full.Substring($baseFull.Length) }
    return $full
}
function Get-FileDigest([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-MatchingAssets([string]$Directory,[string]$Pattern) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return @() }
    return @(Get-ChildItem -LiteralPath $Directory -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $Pattern })
}

# VS Code: deterministic archive location, fixed manifest size and digest.
$vscodeSpec = $manifest.vscode
$vscodeRel = "vscode\VSCode-$($vscodeSpec.version)-win32-x64.zip"
$vscodeFile = Join-Path $CacheRoot $vscodeRel
if (-not (Test-Path -LiteralPath $vscodeFile -PathType Leaf)) {
    Add-InventoryItem 'VS Code ZIP' $vscodeSpec.version $vscodeRel $null 'MISSING' $null $null 'Bootstrap expects this exact cached archive path.'
} else {
    $file = Get-Item -LiteralPath $vscodeFile
    $hash = Get-FileDigest $vscodeFile
    $sidecarPath = "$vscodeFile.sha256"
    $sidecarOK = $true
    if (Test-Path -LiteralPath $sidecarPath -PathType Leaf) {
        $sidecarOK = (Get-Content -LiteralPath $sidecarPath -Raw -Encoding ASCII).Trim().ToLowerInvariant() -eq $hash
    }
    $valid = ([int64]$file.Length -eq [int64]$vscodeSpec.archiveSizeBytes) -and ($hash -eq ([string]$vscodeSpec.sha256).ToLowerInvariant()) -and $sidecarOK
    $note = if ($valid) { 'Exact manifest byte size and SHA-256 match.' } else { 'Archive size, manifest SHA-256, or existing sidecar does not match.' }
    Add-InventoryItem 'VS Code ZIP' $vscodeSpec.version $vscodeRel (Get-RelativePath $vscodeFile $CacheRoot) $(if ($valid) {'PASS'} else {'FAIL'}) ([int64]$file.Length) $hash $note $(if($valid){'MANIFEST_SHA256_MATCH'}else{'HASH_OR_SIZE_MISMATCH'}) $(if($valid){'MANIFEST_PINNED'}else{'UNKNOWN'})
}

# Git and uv have no pinned archive hashes in the manifest. A sidecar alone is only a self-check;
# PASS additionally requires a local .release.json binding repository, tag, filename, size and digest.
$localReleaseEvidence = [ordered]@{ git = $false; uv = $false }
$toolMetadataPath = Join-Path $InstallRoot 'portable-tools\versions.json'
$toolMetadata = $null
if (Test-Path -LiteralPath $toolMetadataPath -PathType Leaf) {
    try { $toolMetadata = Get-Content -LiteralPath $toolMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $toolMetadata = $null }
}
$assetSpecs = @(
    [pscustomobject]@{ key='git'; label='PortableGit archive'; spec=$manifest.portableTools.git; directory=(Join-Path $CacheRoot 'Git'); pattern=$manifest.portableTools.git.assetPattern },
    [pscustomobject]@{ key='uv'; label='uv archive'; spec=$manifest.portableTools.uv; directory=(Join-Path $CacheRoot 'uv'); pattern=('^' + [regex]::Escape($manifest.portableTools.uv.assetName) + '$') }
)
foreach ($asset in $assetSpecs) {
    $matches = @(Get-MatchingAssets $asset.directory $asset.pattern)
    $expectedRel = if ($asset.key -eq 'git') { 'Git\<GitHub-release-asset-name>' } else { "uv\$($asset.spec.assetName)" }
    if ($matches.Count -eq 0) {
        Add-InventoryItem $asset.label $asset.spec.version $expectedRel $null 'MISSING' $null $null 'Cache file not found at the Bootstrap cache location.'
        continue
    }
    if ($matches.Count -ne 1) {
        Add-InventoryItem $asset.label $asset.spec.version $expectedRel ($matches.Name -join '; ') 'UNVERIFIED' $null $null "Found $($matches.Count) matching archives; Bootstrap release metadata must identify one exact asset."
        continue
    }
    $archive = $matches[0]
    $actualHash = Get-FileDigest $archive.FullName
    $actualSize = [int64]$archive.Length
    $sidecarPath = "$($archive.FullName).sha256"
    $sidecarHash = if (Test-Path -LiteralPath $sidecarPath -PathType Leaf) { (Get-Content -LiteralPath $sidecarPath -Raw -Encoding ASCII).Trim().ToLowerInvariant() } else { $null }
    $releasePath = "$($archive.FullName).release.json"
    $release = $null
    if (Test-Path -LiteralPath $releasePath -PathType Leaf) {
        try { $release = Get-Content -LiteralPath $releasePath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $release = $null }
    }
    $toolRecord = if ($toolMetadata) { $toolMetadata.($asset.key) } else { $null }
    $hasReleaseProof = $release -and
        $release.repository -eq $asset.spec.githubRepository -and
        $release.releaseTag -eq $asset.spec.releaseTag -and
        $release.assetName -eq $archive.Name -and
        [int64]$release.size -eq $actualSize -and
        ([string]$release.sha256).ToLowerInvariant() -eq $actualHash
    $hasInstalledMetadataProof = $toolRecord -and
        $toolRecord.release -eq $asset.spec.releaseTag -and
        ([string]$toolRecord.sha256).ToLowerInvariant() -eq $actualHash -and
        [int64]$toolRecord.size -eq $actualSize
    $sidecarValid = $sidecarHash -and $sidecarHash -eq $actualHash
    $status = if ($sidecarHash -and -not $sidecarValid) { 'FAIL' } elseif ($sidecarValid -and ($hasReleaseProof -or $hasInstalledMetadataProof)) { 'PASS' } else { 'UNVERIFIED' }
    $note = switch ($status) {
        'PASS' { 'SHA-256 sidecar matches and local release/version metadata binds this exact asset to the pinned release.' }
        'FAIL' { 'SHA-256 sidecar does not match the archive.' }
        default { 'A local SHA-256 sidecar and matching local release metadata are both required; current Bootstrap does not persist release metadata for Git/uv.' }
    }
    $integrityState = if ($status -eq 'PASS') {'SIDECAR_AND_RELEASE_METADATA_MATCH'} elseif ($status -eq 'FAIL') {'SIDECAR_MISMATCH'} elseif ($sidecarValid) {'SIDECAR_ONLY'} else {'NO_VERIFIABLE_DIGEST'}
    $originState = if ($status -eq 'PASS') {'LOCAL_RELEASE_METADATA_MATCH'} else {'UNKNOWN'}
    Add-InventoryItem $asset.label $asset.spec.version (Join-Path (Split-Path $expectedRel -Parent) $archive.Name) (Get-RelativePath $archive.FullName $CacheRoot) $status $actualSize $actualHash $note $integrityState $originState
}

# Node has a pinned official SHA-256; exact archive name and digest are enough to verify the cache.
$nodeSpec = $manifest.portableTools.node
$nodeRel = "node\node-v$($nodeSpec.version)-win-x64.zip"
$nodeFile = Join-Path $CacheRoot $nodeRel
if (-not (Test-Path -LiteralPath $nodeFile -PathType Leaf)) {
    Add-InventoryItem 'Node.js ZIP' $nodeSpec.version $nodeRel $null 'MISSING' $null $null 'Bootstrap expects this exact archive path.'
} else {
    $nodeInfo = Get-Item -LiteralPath $nodeFile
    $nodeHash = Get-FileDigest $nodeFile
    $nodeSidecarPath = "$nodeFile.sha256"
    $sidecarValid = -not (Test-Path -LiteralPath $nodeSidecarPath -PathType Leaf) -or (Get-Content -LiteralPath $nodeSidecarPath -Raw -Encoding ASCII).Trim().ToLowerInvariant() -eq $nodeHash
    $nodeValid = $nodeHash -eq ([string]$nodeSpec.sha256).ToLowerInvariant() -and $sidecarValid
    Add-InventoryItem 'Node.js ZIP' $nodeSpec.version $nodeRel (Get-RelativePath $nodeFile $CacheRoot) $(if ($nodeValid) {'PASS'} else {'FAIL'}) ([int64]$nodeInfo.Length) $nodeHash $(if ($nodeValid) {'Pinned official SHA-256 matches.'} else {'Pinned manifest SHA-256 or existing sidecar does not match.'}) $(if($nodeValid){'MANIFEST_SHA256_MATCH'}else{'HASH_MISMATCH'}) $(if($nodeValid){'MANIFEST_PINNED'}else{'UNKNOWN'})
}

# Python is installed by uv, not from a deterministic archive in the Bootstrap cache.
$pythonRoot = Join-Path $InstallRoot 'portable-tools\Python'
$runtimes = Join-Path $pythonRoot 'runtimes'
$uvCache = Join-Path $pythonRoot 'cache'
$pythonExe = Get-ChildItem -LiteralPath $runtimes -Filter 'python.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
$uvCacheFiles = if (Test-Path -LiteralPath $uvCache -PathType Container) { @(Get-ChildItem -LiteralPath $uvCache -File -Recurse -ErrorAction SilentlyContinue) } else { @() }
$pythonBytes = [int64](($uvCacheFiles | Measure-Object -Property Length -Sum).Sum)
$pythonNote = 'Installed runtime is useful when the D-drive installation persists, but it is not an archive for a clean rebuild.'
Add-InventoryItem 'Python installed runtime' $manifest.portableTools.python.version 'portable-tools\Python\runtimes\<runtime>\python.exe' $(if($pythonExe){Get-RelativePath $pythonExe.FullName $InstallRoot}else{$null}) $(if($pythonExe){'UNVERIFIED'}else{'MISSING'}) $(if($pythonExe){[int64](Get-Item -LiteralPath $pythonExe.FullName).Length}else{$null}) $null $pythonNote 'INSTALLED_BINARY_ONLY' 'NOT_AN_OFFLINE_ARCHIVE'
$cacheNote = if ($uvCacheFiles.Count) { 'uv cache is present but current Bootstrap does not pin or consume a standalone Python archive from this directory; network may still be needed.' } else { 'Current Bootstrap provisions Python through uv and does not create a pinned standalone Python archive here.' }
Add-InventoryItem 'Python uv cache' $manifest.portableTools.python.version 'portable-tools\Python\cache (UV_CACHE_DIR)' $(if($uvCacheFiles.Count){Get-RelativePath $uvCache $InstallRoot}else{$null}) $(if($uvCacheFiles.Count){'UNVERIFIED'}else{'MISSING'}) $pythonBytes $null $cacheNote 'UV_CACHE_UNPINNED' 'UNKNOWN'

# Bootstrap's Restore-Extensions uses CacheRoot\extensions\<id>-<version>.vsix.
foreach ($extension in $extensions.extensions) {
    $extensionName = '{0}-{1}.vsix' -f $extension.id.ToLowerInvariant(), $extension.version
    $extensionRel = Join-Path 'extensions' $extensionName
    $extensionPath = Join-Path $CacheRoot $extensionRel
    if (-not (Test-Path -LiteralPath $extensionPath -PathType Leaf)) {
        Add-InventoryItem "VSIX $($extension.id)" $extension.version $extensionRel $null 'MISSING' $null $null 'No local VSIX; Restore-Extensions falls back to the VS Code Marketplace.'
        continue
    }
    $extensionFile = Get-Item -LiteralPath $extensionPath
    $extensionHash = Get-FileDigest $extensionPath
    $extensionSidecarPath = "$extensionPath.sha256"
    $expectedSidecar = if (Test-Path -LiteralPath $extensionSidecarPath -PathType Leaf) { (Get-Content -LiteralPath $extensionSidecarPath -Raw -Encoding ASCII).Trim().ToLowerInvariant() } else { $null }
    $package = $null
    $zip = $null
    $packageError = $null
    try {
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($extensionPath)
        $packageEntry = $zip.GetEntry('extension/package.json')
        if (-not $packageEntry) { throw 'VSIX is missing extension/package.json.' }
        $reader = [IO.StreamReader]::new($packageEntry.Open())
        try { $package = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    } catch { $packageError = $_.Exception.Message }
    finally { if ($zip) { $zip.Dispose() } }
    $packageId = if ($package.publisher -and $package.name) { ('{0}.{1}' -f $package.publisher,$package.name).ToLowerInvariant() } else { $null }
    $metadataMatches = $package -and $packageId -eq $extension.id.ToLowerInvariant() -and [string]$package.version -eq [string]$extension.version
    $sidecarMismatch = $expectedSidecar -and $expectedSidecar -ne $extensionHash
    if ($packageError -or ($package -and -not $metadataMatches) -or $sidecarMismatch) {
        $extensionStatus = 'FAIL'
        $integrityState = if ($sidecarMismatch) {'SIDECAR_MISMATCH'} else {'VSIX_METADATA_MISMATCH'}
        $extensionOrigin = 'UNKNOWN'
        $extensionNote = if ($packageError) { "VSIX metadata could not be read: $packageError" } elseif ($sidecarMismatch) { 'Local SHA-256 sidecar mismatch.' } else { "VSIX metadata does not match manifest ($($packageId)@$($package.version))." }
    } elseif ($metadataMatches -and $expectedSidecar) {
        $extensionStatus = 'UNVERIFIED'
        $integrityState = 'NOT_PINNED_HASH_VERIFIED'
        $extensionOrigin = 'UNKNOWN'
        $extensionNote = 'VSIX package ID/version and local SHA-256 sidecar match; manifest pins no digest, so the archive origin is still unknown.'
    } else {
        $extensionStatus = 'UNVERIFIED'
        $integrityState = if ($metadataMatches) {'VERSION_METADATA_ONLY'} else {'UNKNOWN'}
        $extensionOrigin = 'UNKNOWN'
        $extensionNote = 'VSIX archive origin is unknown; manifest does not pin a digest and no matching sidecar proves these bytes.'
    }
    Add-InventoryItem "VSIX $($extension.id)" $extension.version $extensionRel (Get-RelativePath $extensionPath $CacheRoot) $extensionStatus ([int64]$extensionFile.Length) $extensionHash $extensionNote $integrityState $extensionOrigin
}

$counts = [ordered]@{}
foreach ($status in @('PASS','UNVERIFIED','MISSING','FAIL')) { $counts[$status] = @($items | Where-Object status -eq $status).Count }
$report = [ordered]@{
    schemaVersion = 1
    generatedUtc = (Get-Date).ToUniversalTime().ToString('o')
    manifest = 'manifests/versions.json'
    installRoot = $InstallRoot
    cacheRoot = $CacheRoot
    counts = $counts
    fullyOfflineBootstrapSupported = $false
    offlineLimitations = @(
        'Git and uv Bootstrap paths query the GitHub release API to resolve asset names and advertised metadata, even when an archive is cached.',
        'Python is installed through uv; the current workflow does not pin or consume a standalone Python archive from CacheRoot.',
        'Marketplace VSIX files without a pinned digest are reported UNVERIFIED; missing VSIX files fall back to Marketplace.',
        'A passing cache component does not establish that the complete current Bootstrap can run without network access.'
    )
    items = @($items)
}
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReportPath) | Out-Null
[IO.File]::WriteAllText($ReportPath, ($report | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($true))
Write-Host "Offline cache audit: PASS=$($counts.PASS), UNVERIFIED=$($counts.UNVERIFIED), MISSING=$($counts.MISSING), FAIL=$($counts.FAIL)"
Write-Host "Report: $ReportPath"
Write-Host 'This inventory is read-only for cache/install data; it does not prove full offline Bootstrap support.'
if ($counts.FAIL -gt 0) { exit 1 }
