@echo off
rem ===========================================================================
rem  Double-click this to put back whatever the last apply changed.
rem
rem  No arguments, no choosing a backup. It finds the most recent usable
rem  backup and restores from it - both tiers, whichever were applied.
rem
rem  Where a setting did not exist before, this REMOVES it rather than writing
rem  a zero. Most of these are absent on a default machine, so that is the
rem  normal path here, not an edge case.
rem
rem  No administrator rights are requested. Every setting this module touches
rem  belongs to your account only.
rem ===========================================================================
setlocal
title Recommendations - undo
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-Recommendations.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
