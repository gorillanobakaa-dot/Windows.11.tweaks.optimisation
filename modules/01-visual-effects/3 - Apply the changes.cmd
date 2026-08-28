@echo off
rem ===========================================================================
rem  Double-click this to turn off the animations, fades, shadows and
rem  frosted-glass effects.
rem
rem  Before it changes anything it saves the current state of every setting it
rem  manages, and it refuses to continue if that save fails. You can undo the
rem  whole thing at any time with "4 - UNDO everything".
rem
rem  No administrator rights are requested. None are needed: these are your own
rem  personal display settings.
rem ===========================================================================
setlocal
title Visual effects - apply the changes
cd /d "%~dp0"

echo.
echo   ABOUT TO CHANGE YOUR DISPLAY SETTINGS
echo.
echo   This turns off animations, fades, window shadows and frosted glass.
echo   Your current settings are saved first, and you can put everything back
echo   at any time by running "4 - UNDO everything".
echo.
echo   Press CTRL+C to cancel, or
pause

echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0Disable-VisualEffects.ps1' -Confirm:$false"

echo.
echo   --------------------------------------------------------------------
echo   Some items - the taskbar and file-list ones - only appear after you
echo   sign out and back in, or after the desktop is restarted.
echo.
echo   To undo everything, run:  4 - UNDO everything
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
