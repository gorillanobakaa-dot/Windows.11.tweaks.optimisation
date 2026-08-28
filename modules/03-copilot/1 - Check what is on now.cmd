@echo off
rem ===========================================================================
rem  Double-click this to see every form Copilot takes on this machine.
rem
rem  IT CHANGES NOTHING. It only reads and reports.
rem
rem  Copilot is not one thing. On a current Windows 11 machine it can be an app
rem  package, a separate full Chromium application in Program Files with its own
rem  updater, a service running as LocalSystem, a package waiting to be handed to
rem  the next user account created here, and a handful of settings. This reports
rem  all of them.
rem
rem  It also reports which of them could be put back if you removed them, and
rem  which could not - which is the difference between a settings change and
rem  deleting software.
rem
rem  No administrator rights are requested. One reading is fuller if you happen
rem  to be an administrator - the list of packages a NEW user account would get -
rem  and the report says so rather than printing a blank.
rem ===========================================================================
setlocal
title Copilot - check what is on now
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-Copilot.ps1"

echo.
echo   --------------------------------------------------------------------
echo   Nothing was changed. That script can only read.
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
