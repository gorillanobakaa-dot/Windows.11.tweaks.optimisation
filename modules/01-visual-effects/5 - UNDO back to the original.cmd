@echo off
rem ===========================================================================
rem  Double-click this to return the machine to exactly how it was BEFORE this
rem  module was ever used - not just before the last run.
rem
rem  It restores "original-state.json", which is written once, the very first
rem  time the apply script runs, and is never overwritten afterwards. That is
rem  deliberate: it means no amount of re-running anything can destroy your
rem  route home.
rem
rem  No administrator rights are requested. None are needed.
rem ===========================================================================
setlocal
title Visual effects - UNDO back to the original
cd /d "%~dp0"

echo.
echo   RESTORING THE ORIGINAL SETTINGS
echo.
echo   This goes all the way back to how your machine was before this module
echo   was used for the first time.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0Restore-VisualEffects.ps1' -Original -Confirm:$false"

echo.
echo   --------------------------------------------------------------------
echo   The taskbar and file-list items come back after you sign out and back
echo   in, or after the desktop is restarted.
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
