@echo off
rem ===========================================================================
rem  Double-click this to undo the last install: normally that removes the
rem  guard task. It snapshots first, so the undo itself can be undone.
rem
rem  It does not change anything in Windows' own text-input features.
rem  No administrator rights are requested.
rem ===========================================================================
setlocal
title TextInputHost guard - undo
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-TextInputGuard.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
