@echo off
rem ===========================================================================
rem  Shows every app this module removed, when, whether it is installed again,
rem  and the route back for each one.
rem  
rem  IT CHANGES NOTHING.
rem ===========================================================================
setlocal
title App de-bloat - removal record
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-Apps.ps1" -List

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
