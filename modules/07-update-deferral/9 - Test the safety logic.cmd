@echo off
rem ===========================================================================
rem  Run 70 checks on this module's own machinery: that it refuses hold lengths
rem  it cannot honour, that it never writes a quality-update value, that a
rem  damaged backup is rejected, and that the Home caveat cannot be dropped.
rem  
rem  IT CHANGES NOTHING and needs no administrator rights.
rem ===========================================================================
setlocal
title Update deferral - safety logic
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
