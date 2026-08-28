@echo off
rem ===========================================================================
rem  Double-click this to put the SETTINGS back from the most recent backup.
rem  It cannot reinstall removed software - if software was removed, it says
rem  so and names the route back (the Store link, the version).
rem  No administrator rights are requested; the machine-wide value, if it was
rem  applied, needs an elevated run and the script names it when skipped.
rem ===========================================================================
setlocal
title Copilot - undo settings
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-Copilot.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
