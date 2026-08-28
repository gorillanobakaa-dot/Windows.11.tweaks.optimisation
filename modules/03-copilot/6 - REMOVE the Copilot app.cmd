@echo off
rem ===========================================================================
rem  Double-click this to REMOVE the Microsoft.Copilot app for your account,
rem  using the method Microsoft documents, plus the settings.
rem
rem  THIS IS NOT UNDONE FROM A BACKUP. The route back is reinstalling from
rem  the Microsoft Store; the exact package name and link are recorded in
rem  backups\removed-not-restorable.json.
rem  No administrator rights are requested.
rem ===========================================================================
setlocal
title Copilot - remove the app
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0Remove-Copilot.ps1' -RemoveApp"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
