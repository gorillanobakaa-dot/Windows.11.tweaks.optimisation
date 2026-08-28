@echo off
rem ===========================================================================
rem  Double-click this file to see which animations and visual effects are
rem  currently switched on. It only LOOKS. It changes nothing.
rem
rem  Why this .cmd file exists: double-clicking a .ps1 script opens it in
rem  Notepad instead of running it, because Windows treats PowerShell scripts
rem  as text by default. This wrapper runs the script properly.
rem
rem  It deliberately does NOT ask for administrator rights. These are your own
rem  personal display settings and changing them needs no special permission.
rem ===========================================================================
setlocal
title Visual effects - check what is on now
cd /d "%~dp0"

echo.
echo   Reading your current animation and visual-effect settings...
echo   Nothing will be changed.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-VisualEffects.ps1"

echo.
echo   --------------------------------------------------------------------
echo   Finished. Nothing was changed.
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
