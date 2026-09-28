@echo off
rem ===========================================================================
rem  Double-click this to go back to how things were before this module was
rem  ever installed, however many times it has been installed since.
rem
rem  No administrator rights are requested.
rem ===========================================================================
setlocal
title TextInputHost guard - undo to original
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-TextInputGuard.ps1" -Original

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
