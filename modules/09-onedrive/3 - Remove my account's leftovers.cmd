@echo off
rem ===========================================================================
rem  Double-click this to remove what OneDrive left in YOUR account after it
rem  was uninstalled: its settings, its link handler, two environment variables,
rem  and its old folders.
rem
rem  It backs up first and checks the backup was really written. Registry keys
rem  are exported before removal. Folders go to the Recycle Bin, never deleted
rem  outright.
rem
rem  No administrator rights are requested. Undo with number 7.
rem ===========================================================================
setlocal
title OneDrive - remove account leftovers
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-OneDriveLeftovers.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
