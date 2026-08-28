@echo off
rem ===========================================================================
rem  Double-click this to turn Copilot OFF without removing anything: the
rem  taskbar button and the per-user policy value. FULLY REVERSIBLE from a
rem  backup, via number 4.
rem
rem  The machine-wide policy value needs administrator rights and is skipped
rem  here (and named). Numbers 6 and 7 cover the removals.
rem  No administrator rights are requested.
rem ===========================================================================
setlocal
title Copilot - settings only
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-Copilot.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
