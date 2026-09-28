@echo off
rem ===========================================================================
rem  Double-click this to stop OneDrive coming back, for every account:
rem    - sets the two policies Microsoft documents for turning OneDrive off
rem    - moves Windows' own OneDrive installer into this module's backup
rem    - removes the entry that installs OneDrive for every NEW account
rem
rem  It backs up first. The installer is moved, not deleted.
rem
rem  THIS ONE NEEDS ADMINISTRATOR RIGHTS. Undo with number 8.
rem ===========================================================================
setlocal
title OneDrive - block on this machine
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

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Block-OneDrive.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
