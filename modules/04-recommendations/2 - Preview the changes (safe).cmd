@echo off
rem ===========================================================================
rem  Double-click this to see every change that WOULD be made, without making
rem  any of them.
rem
rem  IT CHANGES NOTHING.
rem
rem  No administrator rights are requested. Every setting this module touches
rem  belongs to your account only.
rem ===========================================================================
setlocal
title Recommendations - preview
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Disable-Recommendations.ps1" -WhatIf -IncludeObserved

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
