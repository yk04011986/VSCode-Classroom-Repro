@echo off
setlocal
set "ELECTRON_RUN_AS_NODE="
chcp 65001 >nul
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"
set "ROOT=%~dp0"
set "CODEX_HOME=%ROOT%@@INSTALL_ROOT_LEAF@@\data\home\.codex"
set "INSTALL=%ROOT%@@INSTALL_ROOT_LEAF@@"
if not exist "%INSTALL%\Code.exe" (
  echo ERROR: Portable VS Code is missing Code.exe.
  echo Run scripts\Setup-Portable.ps1 after extracting the official VS Code ZIP.
  exit /b 1
)
if not exist "%INSTALL%\portable-tools\Git\cmd\git.exe" echo WARNING: Portable Git is missing; run Update-Portable.cmd.
if not exist "%INSTALL%\portable-tools\uv\uv.exe" echo WARNING: uv is missing; run Update-Portable.cmd.
if not exist "%INSTALL%\portable-tools\Python\bin\python.exe" echo WARNING: Managed Python is missing; run Update-Portable.cmd.
if not exist "%INSTALL%\data\home\.gitconfig" echo NOTE: Portable Git config is missing; configure user.name and user.email before committing.
call "%INSTALL%\Launch-VSCode.cmd" "%ROOT%Workspace"
set "RC=%ERRORLEVEL%"
endlocal & exit /b %RC%
