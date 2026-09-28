@echo off
rem ===========================================================================
rem  Double-click this to test the logic that decides whether to end a
rem  process and whether a backup may be trusted, with inputs normal use
rem  never produces.
rem
rem  IT CHANGES NOTHING. No administrator rights are requested.
rem ===========================================================================
setlocal
title TextInputHost guard - safety self-test
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-SafetyLogic.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
