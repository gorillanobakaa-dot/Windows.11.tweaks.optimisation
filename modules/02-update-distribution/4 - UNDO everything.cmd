@echo off
rem ===========================================================================
rem  Double-click this to put back whatever the last apply changed.
rem
rem  No arguments, no choosing a backup, no options. It finds the most recent
rem  usable backup and restores from it.
rem
rem  Where a setting did not exist before, this REMOVES it rather than writing
rem  a zero - "not configured" and "configured to zero" are different states.
rem
rem  NEEDS ADMINISTRATOR RIGHTS, for the same reason applying does.
rem ===========================================================================
setlocal
title Update distribution - undo
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

rem  -Command, not -File. With -File, PowerShell parses everything after the
rem  script path as plain strings, so "-Confirm:$false" arrives as the TEXT
rem  "$false" and the script dies with "Cannot convert System.String to the type
rem  System.Management.Automation.SwitchParameter". -Command parses it properly.
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0Restore-UpdateDistribution.ps1' -Confirm:$false"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
