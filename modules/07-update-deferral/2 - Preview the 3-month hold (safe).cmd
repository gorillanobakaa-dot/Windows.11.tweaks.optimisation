@echo off
rem ===========================================================================
rem  Double-click this to see exactly which values a 3-month hold would write,
rem  and what they are currently set to.
rem  
rem  IT CHANGES NOTHING. No administrator rights are requested, on purpose:
rem  a preview should never need elevation.
rem ===========================================================================
setlocal
title Update deferral - preview
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-UpdateDeferral.ps1" -Months 3 -WhatIf

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
