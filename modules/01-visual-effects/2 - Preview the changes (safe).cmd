@echo off
rem ===========================================================================
rem  Double-click this to see exactly what WOULD be changed, without changing
rem  anything. This is the safe way to look before you leap.
rem
rem  No administrator rights are requested. None are needed.
rem ===========================================================================
setlocal
title Visual effects - preview the changes
cd /d "%~dp0"

echo.
echo   PREVIEW ONLY
echo.
echo   This shows every change that would be made, and then makes none of
echo   them. Read the list, and if you are happy with it, close this window
echo   and run "3 - Apply the changes".
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0Disable-VisualEffects.ps1' -WhatIf"

echo.
echo   --------------------------------------------------------------------
echo   Finished. This was a preview - NOTHING was changed.
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
