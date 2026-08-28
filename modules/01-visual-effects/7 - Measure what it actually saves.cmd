@echo off
rem ===========================================================================
rem  Double-click this to find out what the change is WORTH on this machine,
rem  instead of taking anyone's word for it.
rem
rem  It measures the machine with the animations on, then with them off, and
rem  prints the difference in processor time, graphics time and memory. It is
rem  perfectly capable of reporting "no measurable difference" - that is a real
rem  answer, and you should trust a report that can say it.
rem
rem  IT CHANGES SETTINGS WHILE IT RUNS. It has to: it cannot measure both
rem  states without putting the machine in both states. It turns the animations
rem  back on, measures, turns them off, measures, and repeats. Explorer is
rem  restarted each time, so the taskbar will blink.
rem
rem  It finishes with the changes APPLIED (animations off) and says so.
rem
rem  Takes about ten minutes. A window will open and drive itself - do not
rem  click on it. Go and make a cup of tea.
rem
rem  It writes RESULTS.md next to this file, with no machine name in it, so you
rem  can publish it.
rem
rem  No administrator rights are requested. None are needed.
rem ===========================================================================
setlocal
title Visual effects - measure what it actually saves
cd /d "%~dp0"

echo.
echo   MEASURE WHAT IT ACTUALLY SAVES
echo.
echo   This takes about ten minutes and changes settings while it runs.
echo   Leave the machine alone once it starts. A window will open and drive
echo   itself; do not click on it.
echo.
echo   It ends with the changes applied.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Measure-VisualEffects.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
