@echo off
rem  Read-only preview: every change that WOULD be made, none of it done.
setlocal
title Xbox services - preview
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Disable-XboxServices.ps1" -WhatIf
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
