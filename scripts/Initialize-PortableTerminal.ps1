[CmdletBinding()]
param()
$utf8 = [Text.UTF8Encoding]::new($false)
[Console]::InputEncoding = $utf8
[Console]::OutputEncoding = $utf8
$global:OutputEncoding = $utf8
$global:PSDefaultParameterValues['Get-Content:Encoding'] = 'utf8'
$global:PSDefaultParameterValues['Set-Content:Encoding'] = 'utf8'
$global:PSDefaultParameterValues['Add-Content:Encoding'] = 'utf8'
$global:PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
