@echo off
rem ===========================================================================
rem  TEMPLATE - a double-clickable launcher for a script that does NOT need
rem  administrator rights.
rem
rem  Copy this next to your module's .ps1, rename it to something a
rem  non-technical person would understand, and edit the marked lines.
rem
rem  WHY THIS FILE EXISTS
rem  Double-clicking a .ps1 opens it in Notepad rather than running it, because
rem  Windows treats PowerShell scripts as text by default. A person who has
rem  been handed a folder of scripts has no obvious way to run one. This
rem  wrapper runs it properly, shows the output, and keeps the window open
rem  afterwards so the result can actually be read.
rem
rem  It deliberately does NOT request elevation. If your script only changes
rem  the current user's own settings, it must not ask for administrator
rem  rights, and the launcher should say so in plain words. Requesting
rem  privileges you do not need trains people to approve prompts unread.
rem ===========================================================================
setlocal
title <<< EDIT: window title >>>
cd /d "%~dp0"

echo.
echo   <<< EDIT: one or two plain-English lines saying what is about to happen,
echo             and whether anything will be changed. >>>
echo.

rem <<< EDIT: point this at your script, and pass whatever parameters it needs >>>
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0YourScript.ps1"

echo.
echo   --------------------------------------------------------------------
echo   Finished.
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
