@echo off
rem ===========================================================================
rem  Double-click this to put everything back the way it was.
rem
rem  You do not need to know anything or choose anything. It finds the most
rem  recent saved state and restores it. If you would rather go all the way
rem  back to how the machine was before this module was ever used, run
rem  "5 - UNDO back to the original" instead.
rem
rem  No administrator rights are requested. None are needed.
rem ===========================================================================
setlocal
title Visual effects - UNDO everything
cd /d "%~dp0"

echo.
echo   PUTTING YOUR SETTINGS BACK
echo.
echo   This restores the animations, fades and shadows to the way they were
echo   before the last time the changes were applied.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0Restore-VisualEffects.ps1' -Confirm:$false"

echo.
echo   --------------------------------------------------------------------
echo   The taskbar and file-list items come back after you sign out and back
echo   in, or after the desktop is restarted.
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
