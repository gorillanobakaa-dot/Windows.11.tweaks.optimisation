@echo off
rem ===========================================================================
rem  Double-click this to stop your machine sharing Windows updates with other
rem  machines, and to stop other machines being able to connect to it to ask.
rem
rem  Two changes:
rem    - Delivery Optimization download mode set to CdnOnly. Windows still
rem      downloads updates normally, from Microsoft's own servers. It just
rem      stops serving pieces of them to anybody else.
rem    - The two inbound firewall rules for port 7680 are disabled.
rem
rem  It does NOT disable the Delivery Optimization service. Windows Update and
rem  the Microsoft Store use that service to DOWNLOAD, not merely to share.
rem
rem  It backs up first and checks the backup was really written. If the backup
rem  fails it changes nothing.
rem
rem  THIS ONE NEEDS ADMINISTRATOR RIGHTS. These are machine-wide settings.
rem ===========================================================================
setlocal
title Update distribution - apply
cd /d "%~dp0"

rem --- Are we already elevated? -------------------------------------------
rem  "fltmc" only succeeds when running as administrator. More reliable across
rem  Windows versions than testing group membership.
fltmc >nul 2>&1
if not errorlevel 1 goto :elevated

echo.
echo   This task needs administrator rights.
echo.
echo   These settings are machine-wide - the download mode applies to every
echo   account on this PC, and firewall rules are not per-user either.
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

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Disable-PeerDistribution.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
