@echo off
setlocal
chcp 65001 >nul
set "CODEX_HOME=%~dp0@@INSTALL_ROOT_LEAF@@\data\home\.codex"
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
"%SystemRoot%\System32\cmd.exe" /d /k
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
