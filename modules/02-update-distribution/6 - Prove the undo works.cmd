@echo off
rem ===========================================================================
rem  Double-click this to make the machine PROVE the undo works, rather than
rem  taking our word for it.
rem
rem  It applies every change for real, undoes them, then compares every setting
rem  one by one - including the difference between "set to zero" and "not set
rem  at all", which is the case most likely to go wrong in this module.
rem
rem  A PASS means the round trip is lossless and the net effect is nothing.
rem
rem  It is a real change while it runs, so it asks you to confirm first.
rem
rem  NEEDS ADMINISTRATOR RIGHTS.
rem ===========================================================================
setlocal
title Update distribution - prove the undo works
cd /d "%~dp0"

rem --- Are we already elevated? -------------------------------------------
rem  "fltmc" only succeeds when running as administrator. More reliable across
rem  Windows versions than testing group membership.
fltmc >nul 2>&1
if not errorlevel 1 goto :elevated

echo.
echo   This task needs administrator rights.
echo.
echo   These settings are machine-wide - the download mode applies to every
echo   account on this PC, and firewall rules are not per-user either.
echo.
echo   Windows will now show a prompt asking you to allow it. That prompt is
echo   Windows itself asking, not this script. If you would rather not, close
echo   it and nothing will happen.
echo.
pause

powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" 2>nul
if errorlevel 1 (
    echo.
    echo   Elevation was refused or cancelled. Nothing has been changed.
    echo.
    pause
)
exit /b

:elevated
echo.
echo   Running with administrator rights.
echo.

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
