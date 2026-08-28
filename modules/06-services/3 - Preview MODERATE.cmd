@echo off
rem  Read-only preview of the MODERATE profile.
setlocal
title Services - preview MODERATE
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-Services.ps1" -Profile moderate -Full
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
