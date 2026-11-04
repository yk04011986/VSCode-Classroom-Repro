@echo off
setlocal
chcp 65001 >nul
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-ClassroomPersistence.ps1" %*
set "RC=%ERRORLEVEL%"
echo.
pause
endlocal & exit /b %RC%
