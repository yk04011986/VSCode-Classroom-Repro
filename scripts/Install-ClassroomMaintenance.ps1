[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InstallRoot,
    [string]$BackupRoot,
    [switch]$Apply,
    [switch]$ReplaceExisting
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$templateRoot = Join-Path $projectRoot 'config\maintenance'
$installFull = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$installLeaf = Split-Path -Leaf $installFull
$portableRoot = Split-Path -Parent $installFull
if ($installLeaf -notmatch '^Portable-VSCode-[A-Za-z0-9._-]+$') {
    throw 'InstallRoot leaf must match Portable-VSCode-[A-Za-z0-9._-]+.'
}
if ([IO.Path]::GetFullPath((Join-Path $portableRoot $installLeaf)).TrimEnd('\') -ne $installFull) {
    throw 'InstallRoot must be a direct child of PortableRoot.'
}
if (-not (Test-Path -LiteralPath $installFull -PathType Container)) {
    throw "InstallRoot must already exist: $installFull"
}

if (-not $BackupRoot) {
    $BackupRoot = Join-Path (Join-Path $portableRoot 'maintenance\maintenance-backups') ('{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), ([guid]::NewGuid().ToString('N').Substring(0,8)))
}
$backupFull = [IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
$targetSpecs = @(
    [pscustomobject]@{ Template = 'Update-Portable.ps1'; Target = (Join-Path $portableRoot 'scripts\Update-Portable.ps1') },
    [pscustomobject]@{ Template = 'Update-Portable-Runner.ps1'; Target = (Join-Path $portableRoot 'scripts\Update-Portable-Runner.ps1') },
    [pscustomobject]@{ Template = 'Update-VSCode.ps1'; Target = (Join-Path $portableRoot 'scripts\Update-VSCode.ps1') },
    [pscustomobject]@{ Template = 'Setup-Portable.ps1'; Target = (Join-Path $portableRoot 'scripts\Setup-Portable.ps1') },
    [pscustomobject]@{ Template = 'Initialize-Terminal.ps1'; Target = (Join-Path $installFull 'portable-tools\Initialize-Terminal.ps1') },
    [pscustomobject]@{ Template = 'Launch-Portable-VSCode.cmd'; Target = (Join-Path $portableRoot 'Launch-Portable-VSCode.cmd') },
    [pscustomobject]@{ Template = 'Launch-Portable-CMD.cmd'; Target = (Join-Path $portableRoot 'Launch-Portable-CMD.cmd') },
    [pscustomobject]@{ Template = 'Launch-Portable-PowerShell.cmd'; Target = (Join-Path $portableRoot 'Launch-Portable-PowerShell.cmd') },
    [pscustomobject]@{ Template = 'Update-Portable.cmd'; Target = (Join-Path $portableRoot 'Update-Portable.cmd') },
    [pscustomobject]@{ Template = 'Update-VSCode.cmd'; Target = (Join-Path $portableRoot 'Update-VSCode.cmd') }
)
$plan = @()
$conflicts = @()
foreach ($spec in $targetSpecs) {
    $templatePath = Join-Path $templateRoot $spec.Template
    if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) { throw "Template is missing: $templatePath" }
    $content = [IO.File]::ReadAllText($templatePath)
    if ($content.Contains('@@INSTALL_ROOT_LEAF@@')) { $content = $content.Replace('@@INSTALL_ROOT_LEAF@@', $installLeaf) }
    if ($content.Contains('@@')) { throw "Unresolved template token in $($spec.Template)." }
    $target = [IO.Path]::GetFullPath($spec.Target)
    $existing = Test-Path -LiteralPath $target
    $same = $false
    if ($existing) {
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Target exists but is not a file: $target" }
        $same = [string]::Equals([IO.File]::ReadAllText($target), $content, [StringComparison]::Ordinal)
        if (-not $same) { $conflicts += $target }
    }
    $plan += [pscustomobject]@{ Name = $spec.Template; Target = $target; Content = $content; Existing = $existing; Same = $same }
}
if ($conflicts.Count -gt 0 -and -not $ReplaceExisting) {
    throw "Existing maintenance files differ; no files changed. Review them or rerun with -ReplaceExisting: $($conflicts -join '; ')"
}
foreach ($entry in $plan) {
    $status = if (-not $entry.Existing) { 'CREATE' } elseif ($entry.Same) { 'KEEP (identical)' } else { 'REPLACE (backup first)' }
    Write-Host ("{0,-23} {1}" -f $status, $entry.Target)
}
if (-not $Apply) {
    Write-Host 'Preview only. Add -Apply to deploy these maintenance files.'
    return
}

$replacements = @($plan | Where-Object { $_.Existing -and -not $_.Same })
if ($replacements.Count -gt 0) {
    foreach ($entry in $plan) {
        if ($backupFull -eq $entry.Target -or $entry.Target.StartsWith($backupFull + '\', [StringComparison]::OrdinalIgnoreCase) -or $backupFull.StartsWith($entry.Target + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "BackupRoot overlaps a deployment target or its containing directory: $backupFull"
        }
    }
    if ($backupFull.StartsWith($portableRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $backupRelative = $backupFull.Substring($portableRoot.Length).TrimStart('\')
        if (-not $backupRelative.StartsWith('maintenance\maintenance-backups\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'A BackupRoot inside PortableRoot must be under maintenance\maintenance-backups.'
        }
    }
    if (Test-Path -LiteralPath $backupFull) { throw "BackupRoot already exists; choose a new empty path: $backupFull" }
    New-Item -ItemType Directory -Force -Path $backupFull | Out-Null
    foreach ($entry in $replacements) {
        $relative = $entry.Target.Substring($portableRoot.Length).TrimStart('\')
        $backupPath = Join-Path $backupFull $relative
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupPath) | Out-Null
        Copy-Item -LiteralPath $entry.Target -Destination $backupPath
        if ((Get-FileHash -LiteralPath $entry.Target -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash) {
            throw "Backup verification failed; target has not been replaced: $($entry.Target)"
        }
    }
    Write-Host "Replaced files backed up at $backupFull"
}
foreach ($entry in $plan) {
    if ($entry.Same) { continue }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $entry.Target) | Out-Null
    $temporary = $entry.Target + '.' + $PID + '.tmp'
    $encoding = if ([IO.Path]::GetExtension($entry.Target) -ieq '.cmd') { [Text.Encoding]::ASCII } else { [Text.UTF8Encoding]::new($true) }
    [IO.File]::WriteAllText($temporary, $entry.Content, $encoding)
    Move-Item -LiteralPath $temporary -Destination $entry.Target -Force
}
Write-Host "Maintenance files deployed for $installFull. No updater was run."
