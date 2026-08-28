@echo off
rem  Applies for real, undoes, compares every reading. Net zero on a pass.
rem  NEEDS ADMINISTRATOR RIGHTS: service configuration lives under HKLM.
setlocal
title Xbox services - round-trip proof
cd /d "%~dp0"

rem --- elevation: fltmc only succeeds as administrator ----------------------
fltmc >nul 2>&1
if not errorlevel 1 goto :elevated

echo.
echo   This task needs administrator rights - service start types are
echo   machine-wide. Windows will now ask you to allow it. That prompt comes
echo   from Windows, not from this script. Close it and nothing happens.
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
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-RoundTrip.ps1" -Force
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
