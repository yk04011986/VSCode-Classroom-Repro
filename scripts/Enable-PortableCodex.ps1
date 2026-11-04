[CmdletBinding()]
param(
    [string]$InstallRoot = 'D:\Night_Trains\@George\VSCode\Portable-VSCode-1.142.0',
    [string]$SourceCodexHome,
    [switch]$Apply,
    [switch]$LauncherOnly
)

$ErrorActionPreference = 'Stop'
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$target = Join-Path $InstallRoot 'data\home\.codex'
$launcher = Join-Path $InstallRoot 'Launch-VSCode.cmd'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw "Missing launcher: $launcher" }
$text = [IO.File]::ReadAllText($launcher)
$setting = 'set "CODEX_HOME=%ROOT%data\home\.codex"'
if ($text -match '(?im)^set "?CODEX_HOME=') {
    if (-not $text.Contains($setting)) { throw 'Launcher already has a different CODEX_HOME. Review it before changing.' }
    $patched = $text
} else {
    $anchor = 'set "USERPROFILE=%ROOT%data\home"'
    if (-not $text.Contains($anchor)) { throw 'Portable USERPROFILE anchor not found in launcher.' }
    $patched = $text.Replace($anchor, $anchor + "`r`n" + $setting)
}

$copies = @()
if (-not $LauncherOnly) {
    if (-not $SourceCodexHome) { throw 'Specify -SourceCodexHome explicitly, for example C:\Users\N22\.codex.' }
    $source = (Resolve-Path -LiteralPath $SourceCodexHome).Path.TrimEnd('\')
    $targetFull = [IO.Path]::GetFullPath($target).TrimEnd('\')
    if ($source -ieq $targetFull -or $targetFull.StartsWith($source + '\', [StringComparison]::OrdinalIgnoreCase) -or $source.StartsWith($targetFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Source and destination must be separate directories.'
    }
    # Do not capture a live SQLite database or a growing transcript.
    if (Get-Process -Name Code, Codex -ErrorAction SilentlyContinue) {
        throw 'Close all VS Code and Codex windows/processes, then run this script from an external PowerShell window.'
    }
    $files = @()
    foreach ($directory in @('sessions', 'archived_sessions', 'memories')) {
        $path = Join-Path $source $directory
        if (Test-Path -LiteralPath $path) { $files += @(Get-ChildItem -LiteralPath $path -File -Recurse -Force) }
    }
    $files += @(Get-ChildItem -LiteralPath $source -File -Force | Where-Object {
        $_.Name -in @('session_index.jsonl', 'history.jsonl') -or
        $_.Name -match '^(state|memories)_\d+\.sqlite(-wal)?$'
    })
    if ($files.Count -eq 0) { throw "No conversation or memory data found in $source" }
    foreach ($file in $files) {
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Linked file is not supported: $($file.FullName)" }
        $relative = $file.FullName.Substring($source.Length + 1)
        $destination = Join-Path $target $relative
        # A migration is an initial import, never a merge of live SQLite stores.
        if (Test-Path -LiteralPath $destination) { throw "Destination already exists; no files changed: $destination" }
        $copies += [pscustomobject]@{ Source = $file.FullName; Destination = $destination; Hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
    }
    $existingData = @(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -in @('sessions', 'archived_sessions', 'memories', 'session_index.jsonl', 'history.jsonl') -or $_.Name -match '^(state|memories)_\d+\.sqlite'
    })
    if ($existingData.Count) { throw 'Both Codex homes contain data. This script only performs an initial import; no files changed. For a safe merge, close all Codex/VS Code processes, back up both homes, use SQLite backup API to snapshot each state/memories DB (including WAL), merge unique JSONL records and correct rollout_path references, then validate in a separate CODEX_HOME before switching.' }
}

Write-Host "CODEX_HOME: $target"
Write-Host "Conversation/memory files to copy: $($copies.Count)"
Write-Host "Launcher needs update: $($patched -ne $text)"
if (-not $Apply) { Write-Host 'Preview only. Repeat with -Apply to write changes.'; return }

foreach ($entry in $copies) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $entry.Destination) -Force | Out-Null
    Copy-Item -LiteralPath $entry.Source -Destination $entry.Destination
    if ((Get-FileHash -LiteralPath $entry.Destination -Algorithm SHA256).Hash -ne $entry.Hash -or
        (Get-FileHash -LiteralPath $entry.Source -Algorithm SHA256).Hash -ne $entry.Hash) {
        throw "Copy verification failed. Source preserved; inspect destination before retrying: $($entry.Destination)"
    }
}
if ($patched -ne $text) {
    $backup = $launcher + '.before-codex-' + [guid]::NewGuid().ToString('N') + '.bak'
    Copy-Item -LiteralPath $launcher -Destination $backup
    [IO.File]::WriteAllText($launcher, $patched, [Text.Encoding]::ASCII)
    Write-Host "Launcher backup: $backup"
}
Write-Host 'Done. Original data was preserved. Start VS Code through Launch-VSCode.cmd.'
Write-Host 'Authentication, configuration, skills and plugins were not migrated; sign in/configure them in the portable environment as needed.'
