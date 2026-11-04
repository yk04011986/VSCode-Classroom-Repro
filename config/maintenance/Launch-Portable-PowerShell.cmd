@echo off
setlocal
chcp 65001 >nul
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
set "CODEX_HOME=%~dp0@@INSTALL_ROOT_LEAF@@\data\home\.codex"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NoExit -ExecutionPolicy Bypass -File "%~dp0@@INSTALL_ROOT_LEAF@@\portable-tools\Initialize-Terminal.ps1"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
