@echo off
rem ===========================================================================
rem  Apply a 3-month hold FOR REAL, undo it, and compare every value.
rem  
rem  A pass means every value came back to exactly where it started, and the
rem  policy key is present or absent exactly as it was. On a pass it deletes the
rem  backups it created; on a failure it keeps them and prints what happened.
rem  
rem  Run this BEFORE trusting the undo.
rem
rem  THIS ONE NEEDS ADMINISTRATOR RIGHTS. Windows Update policy is machine-wide.
rem ===========================================================================
setlocal
title Update deferral - round trip
cd /d "%~dp0"

rem --- Are we already elevated? --------------------------------------------
fltmc >nul 2>&1
if not errorlevel 1 goto :elevated

echo.
echo   This task needs administrator rights.
echo.
echo   Windows Update policy lives under HKLM and applies to the whole
echo   machine, not just your account.
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

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-RoundTrip.ps1" -Force

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
