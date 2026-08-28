@echo off
rem ===========================================================================
rem  Double-click this to see every change that WOULD be made, without making
rem  any of them.
rem
rem  IT CHANGES NOTHING. No administrator rights are requested, because
rem  previewing only needs to read.
rem ===========================================================================
setlocal
title Update distribution - preview
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Disable-PeerDistribution.ps1" -WhatIf

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
