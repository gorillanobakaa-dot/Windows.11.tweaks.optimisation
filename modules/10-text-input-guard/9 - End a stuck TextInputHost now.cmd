@echo off
rem ===========================================================================
rem  Double-click this to do once, now, what the guard does every 10 minutes:
rem  measure TextInputHost for one minute and end it only if it held a whole
rem  processor core. Windows starts a fresh copy when it is needed.
rem
rem  It works whether or not the guard is installed.
rem  No administrator rights are requested.
rem ===========================================================================
setlocal
title TextInputHost guard - check and end now
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Invoke-TextInputGuard.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
