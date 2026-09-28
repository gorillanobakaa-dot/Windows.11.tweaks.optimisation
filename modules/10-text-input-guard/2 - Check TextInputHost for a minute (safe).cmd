@echo off
rem ===========================================================================
rem  Double-click this to measure TextInputHost for one minute, exactly as the
rem  guard does, and see whether it would be ended.
rem
rem  IT CHANGES NOTHING. It ends nothing and writes nothing.
rem  No administrator rights are requested.
rem ===========================================================================
setlocal
title TextInputHost guard - one-minute check
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-TextInputGuard.ps1" -WhatIf

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
