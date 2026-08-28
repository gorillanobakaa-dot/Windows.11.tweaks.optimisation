@echo off
rem ===========================================================================
rem  Every app the LIGHT tier would remove, with what each one is and what you
rem  lose. IT REMOVES NOTHING and needs no administrator rights.
rem ===========================================================================
setlocal
title App de-bloat - preview LIGHT
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-Apps.ps1" -Tier light -WhatIf

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
