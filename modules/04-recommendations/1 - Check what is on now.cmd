@echo off
rem ===========================================================================
rem  Double-click this to see which suggestions, tips and "personalised"
rem  content are switched on for your account.
rem
rem  IT CHANGES NOTHING. It only reads and reports.
rem
rem  The report is split into settings Microsoft documents explicitly, and
rem  settings that are real but undocumented. You should be able to see which
rem  of these this project can back up with a quotation and which it cannot.
rem
rem  No administrator rights are requested. Every setting this module touches
rem  belongs to your account only.
rem ===========================================================================
setlocal
title Recommendations - check
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-Recommendations.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
