@echo off
rem ===========================================================================
rem  Double-click this to test the machinery that decides WHETHER to write.
rem  IT CHANGES NOTHING. Works in a temporary folder, deleted afterwards.
rem  Pays particular attention to the tier split: the removals must be
rem  structurally incapable of appearing in the restore path.
rem  No administrator rights are requested.
rem ===========================================================================
setlocal
title Copilot - safety logic self-test
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-SafetyLogic.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
