@echo off
rem ===========================================================================
rem  Every app the SUPER tier would remove. IT REMOVES NOTHING.
rem  
rem  Read this one before choosing any tier - it is the fastest way to see what
rem  these tiers actually are.
rem ===========================================================================
setlocal
title App de-bloat - preview SUPER
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-Apps.ps1" -Tier super -WhatIf

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
