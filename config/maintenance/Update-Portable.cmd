@echo off
setlocal
chcp 65001 >nul
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Update-Portable-Runner.ps1"
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo Update failed. See the log path above.
if /i not "%~1"=="--no-pause" pause
endlocal & exit /b %RC%
