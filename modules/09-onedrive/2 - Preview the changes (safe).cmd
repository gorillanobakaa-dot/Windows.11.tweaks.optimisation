@echo off
rem ===========================================================================
rem  Double-click this to see exactly what numbers 3 and 4 would change.
rem
rem  IT CHANGES NOTHING. Both previews run without administrator rights.
rem ===========================================================================
setlocal
title OneDrive - preview
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Remove-OneDriveLeftovers.ps1" -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Block-OneDrive.ps1" -WhatIf

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
