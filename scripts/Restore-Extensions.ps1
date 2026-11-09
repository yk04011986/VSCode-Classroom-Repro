[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [Parameter(Mandatory = $true)][string]$CacheRoot,
    [switch]$ReplaceMismatched
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PSScriptRoot '..\manifests\extensions.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
$code = Join-Path $InstallRoot 'bin\code.cmd'
$userData = Join-Path $InstallRoot 'data\user-data'
$extensionsDir = Join-Path $InstallRoot 'data\extensions'
$vsixCache = Join-Path $CacheRoot 'extensions'

function Get-InstalledExtensions {
    $items = & $code --user-data-dir $userData --extensions-dir $extensionsDir --list-extensions --show-versions
    if ($LASTEXITCODE -ne 0) { throw "VS Code could not enumerate extensions (exit $LASTEXITCODE)." }
    $map = @{}
    foreach ($item in $items) {
        if ($item -match '^([^@]+)@(.+)$') { $map[$Matches[1].ToLowerInvariant()] = $Matches[2] }
    }
    return $map
}

if (-not (Test-Path -LiteralPath $code)) { throw "VS Code CLI is missing: $code" }
New-Item -ItemType Directory -Force -Path $userData, $extensionsDir, $vsixCache | Out-Null
$oldElectronRunAsNode = [Environment]::GetEnvironmentVariable('ELECTRON_RUN_AS_NODE', 'Process')
[Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE', $null, 'Process')
try {
    $installed = Get-InstalledExtensions
    $toInstall = [System.Collections.Generic.List[string]]::new()

    foreach ($extension in $manifest.extensions) {
        $id = ([string]$extension.id).ToLowerInvariant()
        $expectedVersion = [string]$extension.version
        if ($installed.ContainsKey($id) -and $installed[$id] -eq $expectedVersion) {
            Write-Host "Already installed: $id@$expectedVersion"
            continue
        }
        if ($installed.ContainsKey($id) -and -not $ReplaceMismatched) {
            throw "Extension $id is $($installed[$id]), expected $expectedVersion. Re-run with -ReplaceMismatched to replace it."
        }

        $vsixPath = Join-Path $vsixCache "$id-$expectedVersion.vsix"
        if (Test-Path -LiteralPath $vsixPath) {
            $extensionSource = $vsixPath
            Write-Host "Installing cached VSIX: $vsixPath"
        }
        else {
            $extensionSource = "$id@$expectedVersion"
            Write-Host "Installing from VS Code Marketplace: $extensionSource"
        }
        $toInstall.Add($extensionSource)
    }

    if ($toInstall.Count -gt 0) {
        $arguments = [System.Collections.Generic.List[string]]::new()
        $arguments.Add('--user-data-dir'); $arguments.Add($userData)
        $arguments.Add('--extensions-dir'); $arguments.Add($extensionsDir)
        foreach ($extensionSource in $toInstall) {
            $arguments.Add('--install-extension'); $arguments.Add($extensionSource)
        }
        $arguments.Add('--force')
        $nativeArguments = $arguments.ToArray()
        $output = & $code @nativeArguments
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) { throw "Extension batch install failed (exit $exitCode): $($output -join ' ')" }
    }

    $installed = Get-InstalledExtensions
    $mismatches = @()
    foreach ($extension in $manifest.extensions) {
        $id = ([string]$extension.id).ToLowerInvariant()
        if (-not $installed.ContainsKey($id)) { $mismatches += "$id is missing" }
        elseif ($installed[$id] -ne [string]$extension.version) { $mismatches += "$id expected $($extension.version), found $($installed[$id])" }
    }
    if ($mismatches.Count -gt 0) { throw "Extension verification failed: $($mismatches -join '; ')" }
    Write-Host "Verified all $($manifest.extensions.Count) pinned extensions."
}
finally {
    [Environment]::SetEnvironmentVariable('ELECTRON_RUN_AS_NODE', $oldElectronRunAsNode, 'Process')
}
