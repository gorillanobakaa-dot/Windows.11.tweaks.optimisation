@echo off
rem ===========================================================================
rem  REMOVES the LIGHT tier: Game Bar and the Xbox overlays, Mixed Reality
rem  Portal, Feedback Hub, Get Help, Mobile Plans, Journal, Power Automate,
rem  Dev Home, Clipchamp, Messaging and People.
rem  
rem  THIS REMOVES SOFTWARE. There is no undo from a backup file. Where the
rem  payload survives on disk it can be re-registered (launcher 8); otherwise
rem  the Microsoft Store is the only route back.
rem
rem  THIS ONE NEEDS ADMINISTRATOR RIGHTS.
rem ===========================================================================
setlocal
title App de-bloat - remove LIGHT
cd /d "%~dp0"

fltmc >nul 2>&1
if not errorlevel 1 goto :elevated

echo.
echo   This task needs administrator rights.
echo.
echo   Removing the PROVISIONED copy of an app - the copy a NEW user account
echo   would receive - is a machine-wide change and needs elevation. Without
echo   it, a new account would still get every app you removed.
echo.
echo   Windows will now show a prompt asking you to allow it. That prompt is
echo   Windows itself asking, not this script. If you would rather not, close
echo   it and nothing will happen.
echo.
pause

powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" 2>nul
if errorlevel 1 (
    echo.
    echo   Elevation was refused or cancelled. Nothing has been changed.
    echo.
    pause
)
exit /b

:elevated
echo.
echo   Running with administrator rights.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-Apps.ps1" -Tier light

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
