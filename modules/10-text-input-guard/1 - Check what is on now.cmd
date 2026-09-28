@echo off
rem ===========================================================================
rem  Double-click this to see whether TextInputHost (the touch keyboard, emoji
rem  panel and clipboard history) is using the processor right now, and whether
rem  the guard is installed, when it last ran and what it has ended.
rem
rem  IT CHANGES NOTHING. It only reads and reports.
rem  No administrator rights are requested.
rem ===========================================================================
setlocal
title TextInputHost guard - check
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-TextInputGuard.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
