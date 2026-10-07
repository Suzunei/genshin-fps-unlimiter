@echo off
setlocal
chcp 65001 >nul
title Genshin FPS Unlimiter
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0fps-unlock.ps1" %*
set "result=%errorlevel%"
echo.
pause
exit /b %result%
