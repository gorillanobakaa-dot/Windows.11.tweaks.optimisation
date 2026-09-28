@echo off
rem ===========================================================================
rem  Double-click this to remove the machine block that number 4 set: the two
rem  policies go, the installer goes back, the new-account entry comes back.
rem
rem  This does NOT reinstall OneDrive.
rem
rem  THIS ONE NEEDS ADMINISTRATOR RIGHTS.
rem ===========================================================================
setlocal
title OneDrive - undo machine block
cd /d "%~dp0"

rem --- Are we already elevated? --------------------------------------------
fltmc >nul 2>&1
if not errorlevel 1 goto :elevated

echo.
echo   This task needs administrator rights.
echo.
echo   The OneDrive block is machine-wide: it lives under HKLM and in
echo   the Windows folder, and applies to every account on this computer.
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

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-OneDrive.ps1" -Part Machine

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
