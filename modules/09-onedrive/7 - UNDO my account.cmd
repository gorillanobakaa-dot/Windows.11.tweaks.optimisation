@echo off
rem ===========================================================================
rem  Double-click this to put back what number 3 removed from your account.
rem  Folders are in the Recycle Bin; it tells you which ones to restore there.
rem
rem  This does NOT reinstall OneDrive. No administrator rights are requested.
rem ===========================================================================
setlocal
title OneDrive - undo account
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-OneDrive.ps1" -Part Account

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
