@echo off
rem ===========================================================================
rem  Double-click this to make the machine PROVE that the undo works, rather
rem  than taking our word for it.
rem
rem  It applies every change for real, then restores them, then compares the
rem  before and after values one by one. A PASS means the round trip is
rem  lossless. The net effect on a PASS is nothing at all.
rem
rem  It is still a real change while it runs, so the script asks you to
rem  confirm before it starts.
rem
rem  No administrator rights are requested. None are needed.
rem ===========================================================================
setlocal
title Visual effects - prove the undo works
cd /d "%~dp0"

echo.
echo   ROUND-TRIP PROOF
echo.
echo   This will change your settings and then change them straight back,
echo   checking every one. If it says PASS, the undo is trustworthy.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-RoundTrip.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
