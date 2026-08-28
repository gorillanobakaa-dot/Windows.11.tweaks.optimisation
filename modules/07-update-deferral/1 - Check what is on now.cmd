@echo off
rem ===========================================================================
rem  Double-click this to see whether feature updates are being held back on
rem  this machine, what the update client itself believes, and whether Microsoft
rem  is already holding this machine back with a safeguard hold.
rem  
rem  IT CHANGES NOTHING. It only reads and reports.
rem  
rem  It also prints the ceiling: a hold is a delay, never a refusal.
rem ===========================================================================
setlocal
title Update deferral - check
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-UpdateDeferral.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
