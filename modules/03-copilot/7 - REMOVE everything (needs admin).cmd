@echo off
rem ===========================================================================
rem  Double-click this for the FULL removal: the settings, the app, AND the
rem  1.3 GB application in Program Files via its registered uninstaller -
rem  which also removes the MicrosoftCopilotElevationService.
rem
rem  THIS IS NOT UNDONE FROM A BACKUP. The route back is downloading Copilot
rem  again from Microsoft. What was removed is recorded in
rem  backups\removed-not-restorable.json.
rem
rem  NEEDS ADMINISTRATOR RIGHTS: the system-level uninstaller and the
rem  machine-wide policy value are both machine-wide.
rem ===========================================================================
setlocal
title Copilot - full removal
cd /d "%~dp0"

rem --- elevation: fltmc only succeeds as administrator ----------------------
fltmc >nul 2>&1
if not errorlevel 1 goto :elevated

echo.
echo   This task needs administrator rights for the machine-wide policy value
echo   and the system-level uninstaller.
echo   Windows will now ask you to allow it. That prompt comes from Windows,
echo   not from this script. Close it and nothing happens.
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
echo   Running with administrator rights.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0Remove-Copilot.ps1' -RemoveApp -RemoveSystemInstall"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
