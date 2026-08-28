@echo off
rem ===========================================================================
rem  Every app the MODERATE tier would remove. IT REMOVES NOTHING.
rem ===========================================================================
setlocal
title App de-bloat - preview MODERATE
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-Apps.ps1" -Tier moderate -WhatIf

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
