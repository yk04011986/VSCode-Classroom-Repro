[CmdletBinding()]
param(
    [string]$InstallRoot = 'D:\Night_Trains\@George\VSCode\Portable-VSCode-1.142.0'
)

$ErrorActionPreference = 'Stop'
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\manifests\versions.json') -Raw -Encoding utf8 | ConvertFrom-Json
$extensionManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\manifests\extensions.json') -Raw -Encoding utf8 | ConvertFrom-Json
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)

$code = Join-Path $InstallRoot 'Code.exe'
if (-not (Test-Path -LiteralPath $code)) { throw "Code.exe is missing: $code" }
$signature = Get-AuthenticodeSignature -FilePath $code
$publisher = ''
if ($signature.SignerCertificate) { $publisher = $signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) }
if ($signature.Status -ne 'Valid' -or $publisher -ne $manifest.vscode.expectedPublisher) { throw "VS Code signature mismatch: $($signature.Status), $publisher" }
$productFile = Get-ChildItem -LiteralPath $InstallRoot -Filter 'product.json' -File -Recurse | Where-Object { $_.FullName -match '\\resources\\app\\product\.json$' } | Select-Object -First 1
if (-not $productFile) { throw 'Could not find VS Code resources\app\product.json.' }
$product = Get-Content -LiteralPath $productFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
if (-not $product.version -or -not $product.commit) { $package = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $productFile.FullName) 'package.json') -Raw -Encoding utf8 | ConvertFrom-Json; if (-not $product.version) { $product | Add-Member -NotePropertyName version -NotePropertyValue $package.version -Force }; if (-not $product.commit) { $product | Add-Member -NotePropertyName commit -NotePropertyValue $package.commit -Force } }
if ($product.version -ne $manifest.vscode.version -or $product.commit -ne $manifest.vscode.commit) { throw "VS Code product mismatch: found $($product.version) $($product.commit)." }
Write-Host "OK VS Code $($product.version) ($publisher)"

$checks = @(
    [pscustomobject]@{ Label = 'Git'; Path = (Join-Path $InstallRoot 'portable-tools\Git\cmd\git.exe'); Args = @('--version'); Version = $manifest.portableTools.git.version },
    [pscustomobject]@{ Label = 'uv'; Path = (Join-Path $InstallRoot 'portable-tools\uv\uv.exe'); Args = @('--version'); Version = $manifest.portableTools.uv.version },
    [pscustomobject]@{ Label = 'Node'; Path = (Join-Path $InstallRoot 'portable-tools\Node\node.exe'); Args = @('--version'); Version = "v$($manifest.portableTools.node.version)" },
    [pscustomobject]@{ Label = 'Python'; Path = (Join-Path $InstallRoot 'portable-tools\Python\bin\python.exe'); Args = @('--version'); Version = $manifest.portableTools.python.version }
)
foreach ($check in $checks) {
    if (-not (Test-Path -LiteralPath $check.Path)) { throw "$($check.Label) is missing: $($check.Path)" }
    $output = & $check.Path @($check.Args)
    $codeExit = $LASTEXITCODE
    $actual = ($output | Out-String).Trim()
    if ($codeExit -ne 0 -or $actual -notmatch [regex]::Escape([string]$check.Version)) { throw "$($check.Label) expected $($check.Version); found '$actual' (exit $codeExit)." }
    Write-Host "OK $($check.Label): $actual"
}
foreach ($command in @('npm.cmd', 'npx.cmd')) {
    if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot "portable-tools\Node\$command"))) { throw "Node tool is missing: $command" }
}

$registryPath = Join-Path $InstallRoot 'data\extensions\extensions.json'
if (-not (Test-Path -LiteralPath $registryPath)) { throw "VS Code extension registry is missing: $registryPath" }
$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding utf8 | ConvertFrom-Json
$extensionErrors = @()
foreach ($expected in $extensionManifest.extensions) {
    $actual = $registry | Where-Object { $_.identifier.id -ieq $expected.id } | Select-Object -First 1
    if (-not $actual) { $extensionErrors += "$($expected.id) is missing" }
    elseif ([string]$actual.version -ne [string]$expected.version) { $extensionErrors += "$($expected.id) expected $($expected.version), found $($actual.version)" }
}
if ($extensionErrors.Count -gt 0) { throw "Extension state mismatch: $($extensionErrors -join '; ')" }
Write-Host "OK extensions: $($extensionManifest.extensions.Count) pinned versions"

$launch = Get-Content -LiteralPath (Join-Path $InstallRoot 'Launch-VSCode.cmd') -Raw -Encoding ascii
$gitWrapper = Get-Content -LiteralPath (Join-Path $InstallRoot 'portable-tools\git.cmd') -Raw -Encoding ascii
$pythonWrapper = Get-Content -LiteralPath (Join-Path $InstallRoot 'portable-tools\python.cmd') -Raw -Encoding ascii
if (-not $launch.Contains('set "CODEX_HOME=%ROOT%data\home\.codex"') -or -not $launch.Contains('endlocal & exit /b %RC%')) { throw 'Portable VS Code launcher is missing CODEX_HOME or exit-code forwarding.' }
if (-not $launch.Contains('%ROOT%portable-tools\uv;%ROOT%portable-tools\Node;%PATH%')) { throw 'Portable VS Code launcher PATH is missing uv/uvx or Node/npm/npx.' }
if (-not $launch.Contains('chcp 65001 >nul') -or -not $launch.Contains('PYTHONUTF8=1') -or -not $launch.Contains('PYTHONIOENCODING=utf-8')) { throw 'Portable launcher UTF-8 environment is missing.' }
if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot 'scripts\Initialize-PortableTerminal.ps1'))) { throw 'Portable terminal initializer was not deployed.' }
if (-not $gitWrapper.Contains('endlocal & exit /b %RC%') -or -not $pythonWrapper.Contains('endlocal & exit /b %RC%')) { throw 'Git/Python wrappers are missing exit-code forwarding.' }
Write-Host 'OK portable wrappers, Node/npm/npx, uvx PATH, and CODEX_HOME'
