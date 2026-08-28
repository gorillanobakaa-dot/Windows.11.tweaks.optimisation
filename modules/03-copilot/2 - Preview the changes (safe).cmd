@echo off
rem ===========================================================================
rem  Double-click this to see every change that WOULD be made - settings AND
rem  removals - without making any of them. IT CHANGES NOTHING.
rem  No administrator rights are requested; previewing only reads.
rem ===========================================================================
setlocal
title Copilot - preview
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0Remove-Copilot.ps1' -RemoveApp -RemoveSystemInstall -WhatIf"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
