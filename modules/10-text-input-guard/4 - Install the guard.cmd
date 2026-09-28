@echo off
rem ===========================================================================
rem  Double-click this to install the guard: a scheduled task that runs every
rem  10 minutes, with no window, and ends TextInputHost only when it has used a
rem  whole processor core for a full minute. Windows starts a fresh copy when
rem  the touch keyboard, emoji panel or clipboard history is needed.
rem
rem  It backs up first. Undo it with number 6.
rem  No administrator rights are requested: the task runs as you.
rem ===========================================================================
setlocal
title TextInputHost guard - install
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-TextInputGuard.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
