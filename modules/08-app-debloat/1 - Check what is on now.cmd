@echo off
rem ===========================================================================
rem  Double-click this to see every app package installed for your account, what
rem  each tier would remove, and - the point of this module - whether anything
rem  you already removed has COME BACK on its own.
rem  
rem  IT CHANGES NOTHING. It only reads and reports.
rem ===========================================================================
setlocal
title App de-bloat - check
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-Apps.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
