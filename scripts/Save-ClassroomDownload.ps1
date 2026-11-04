[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$SourceArchive,
    [Parameter(Mandatory=$true)][string]$CacheRoot,
    [switch]$Apply
)
$ErrorActionPreference='Stop'
$manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\manifests\versions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$source=Get-Item -LiteralPath $SourceArchive
if ($source.Length -ne [int64]$manifest.vscode.archiveSizeBytes) {throw 'Source ZIP size mismatch.'}
$expected=$manifest.vscode.sha256.ToLowerInvariant()
if ((Get-FileHash -LiteralPath $source.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {throw 'Source ZIP checksum mismatch.'}
$destination=Join-Path ([IO.Path]::GetFullPath($CacheRoot)) "vscode\VSCode-$($manifest.vscode.version)-win32-x64.zip"
if (Test-Path -LiteralPath $destination) {
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {throw 'Existing cache differs; it was not overwritten.'}
    Write-Host 'Verified persistent ZIP already exists.'
    return
}
Write-Host "Verified source ZIP. Persistent cache: $destination"
if (-not $Apply) {Write-Host 'Preview only; pass -Apply to copy.'; return}
New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
$partial="$destination.$PID.partial"
if (Test-Path -LiteralPath $partial) {throw 'Partial cache path already exists.'}
Copy-Item -LiteralPath $source.FullName -Destination $partial
if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {throw 'Copied ZIP checksum mismatch; inspect partial cache.'}
Move-Item -LiteralPath $partial -Destination $destination
[IO.File]::WriteAllText("$destination.sha256",$expected,[Text.Encoding]::ASCII)
Write-Host 'Verified VS Code ZIP saved to persistent cache. C: download retained.'
