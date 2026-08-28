@echo off
rem ===========================================================================
rem  Run 58 checks on this module's own machinery: that the never-remove list
rem  genuinely refuses, that a package Windows marks NonRemovable is caught,
rem  that tiers are cumulative, and that nothing here ever calls a removal
rem  reversible.
rem  
rem  IT CHANGES NOTHING and needs no administrator rights.
rem ===========================================================================
setlocal
title App de-bloat - safety logic
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
