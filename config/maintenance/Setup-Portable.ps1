param(
    [string]$InstallRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) '@@INSTALL_ROOT_LEAF@@')
)

$ErrorActionPreference = 'Stop'
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$UpdateScript = Join-Path $PSScriptRoot 'Update-Portable.ps1'

if (-not (Test-Path (Join-Path $InstallRoot 'Code.exe'))) {
    throw "Code.exe was not found in InstallRoot: $InstallRoot. Extract the official Windows x64 ZIP there first."
}

New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot 'data') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot 'portable-tools') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'Workspace') | Out-Null
& $UpdateScript -InstallRoot $InstallRoot
if ($LASTEXITCODE -ne 0) { throw 'Portable tool setup failed.' }
Write-Host "Portable VS Code is ready at $InstallRoot"
