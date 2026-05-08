@echo off
setlocal
cd /d "%~dp0"
set "CODEX_SWITCHER_HOME=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start-codex-switcher.ps1"
