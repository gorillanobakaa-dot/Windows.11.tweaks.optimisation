@echo off
rem ===========================================================================
rem  Double-click this to go all the way back to how your account was before
rem  this module was EVER used - not just before the last run.
rem
rem  It restores from original-state.json, which is written once, by the apply
rem  script, and never overwritten afterwards.
rem
rem  No administrator rights are requested. Every setting this module touches
rem  belongs to your account only.
rem ===========================================================================
setlocal
title Recommendations - undo to original
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-Recommendations.ps1" -Original

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
