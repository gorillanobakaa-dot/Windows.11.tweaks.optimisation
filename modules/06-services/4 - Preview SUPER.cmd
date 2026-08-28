@echo off
rem  Read-only preview of the SUPER / enterprise-secure profile.
setlocal
title Services - preview SUPER
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-Services.ps1" -Profile super -Full
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
