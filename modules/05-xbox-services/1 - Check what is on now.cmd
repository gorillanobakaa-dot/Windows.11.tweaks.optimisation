@echo off
rem  Read-only. Lists every Xbox service, task and app. Changes nothing.
setlocal
title Xbox services - check
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-XboxServices.ps1"
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
