@echo off
rem ===========================================================================
rem  Double-click this to see what number 4 would do: which task it creates,
rem  how often it runs, and where the backup would go.
rem
rem  IT CHANGES NOTHING.
rem  No administrator rights are requested.
rem ===========================================================================
setlocal
title TextInputHost guard - preview
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-TextInputGuard.ps1" -WhatIf

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
