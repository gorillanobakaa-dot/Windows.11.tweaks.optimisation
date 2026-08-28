@echo off
rem ===========================================================================
rem  Double-click this to see whether your machine shares Windows updates with
rem  other machines, and whether anything can connect to it to ask for them.
rem
rem  IT CHANGES NOTHING. It only reads and reports.
rem
rem  No administrator rights are requested. A couple of readings are fuller if
rem  you happen to be an administrator, and it says so where that applies.
rem ===========================================================================
setlocal
title Update distribution - check
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-UpdateDistribution.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
