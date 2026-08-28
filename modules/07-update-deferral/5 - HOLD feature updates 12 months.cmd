@echo off
rem ===========================================================================
rem  Hold FEATURE updates for 12 months (365 days) and pin this machine to the
rem  Windows release it is already running. 365 is the documented maximum.
rem  
rem  SECURITY UPDATES ARE NOT TOUCHED. They keep arriving monthly.
rem  
rem  Note the ceiling: Home gets 24 months of support per feature update, and
rem  Windows updates the machine anyway once it is 60 days past end of service.
rem
rem  THIS ONE NEEDS ADMINISTRATOR RIGHTS. Windows Update policy is machine-wide.
rem ===========================================================================
setlocal
title Update deferral - 12 months
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

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Set-UpdateDeferral.ps1" -Months 12

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
