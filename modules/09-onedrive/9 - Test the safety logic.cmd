@echo off
rem ===========================================================================
rem  Double-click this to test the machinery that decides whether to write,
rem  remove or refuse. It works in a temporary folder and a throwaway registry
rem  key, and changes nothing real. No administrator rights are requested.
rem ===========================================================================
setlocal
title OneDrive - safety self-test
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
