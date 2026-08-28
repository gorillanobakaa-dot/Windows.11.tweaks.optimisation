@echo off
rem ===========================================================================
rem  Double-click this to go all the way back to how the machine was before this
rem  module was EVER used - not just before the last run.
rem
rem  It restores from original-state.json, which is written once, the first time
rem  the apply script runs, and is never overwritten afterwards.
rem
rem  NEEDS ADMINISTRATOR RIGHTS.
rem ===========================================================================
setlocal
title Update distribution - undo to original
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

rem  -Command, not -File: see the note in "4 - UNDO everything.cmd". With -File,
rem  "-Confirm:$false" is passed as a literal string and the script fails.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0Restore-UpdateDistribution.ps1' -Original -Confirm:$false"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
