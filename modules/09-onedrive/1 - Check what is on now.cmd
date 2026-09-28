@echo off
rem ===========================================================================
rem  Double-click this to see every trace of OneDrive on this computer: whether
rem  it is installed or running, whether the machine blocks it, and what is left
rem  in your account.
rem
rem  IT CHANGES NOTHING. It only reads and reports.
rem  No administrator rights are requested.
rem ===========================================================================
setlocal
title OneDrive - check
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-OneDrive.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
