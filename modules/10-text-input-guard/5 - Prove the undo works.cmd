@echo off
rem ===========================================================================
rem  Double-click this to prove the undo works by doing it: it installs the
rem  guard, undoes it, and compares. You are asked to type YES first.
rem
rem  On a PASS the net effect is nothing. If the guard is already installed
rem  it reports INCONCLUSIVE and changes nothing: run number 7 first.
rem  No administrator rights are requested.
rem ===========================================================================
setlocal
title TextInputHost guard - round-trip proof
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-RoundTrip.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
