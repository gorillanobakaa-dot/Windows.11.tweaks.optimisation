@echo off
rem ===========================================================================
rem  TEMPLATE - a double-clickable launcher for a script that DOES need
rem  administrator rights.
rem
rem  Copy this next to your module's .ps1, rename it to something a
rem  non-technical person would understand (for example
rem  "3 - Apply the changes.cmd"), and edit the two marked lines.
rem
rem  WHY THIS FILE EXISTS
rem  Double-clicking a .ps1 opens it in Notepad rather than running it, because
rem  Windows treats PowerShell scripts as text by default. On top of that, a
rem  script that changes machine-wide settings needs elevated ("administrator")
rem  rights, and a normal user has no obvious way to grant them. This wrapper
rem  solves both: it runs the script properly, and it asks Windows for
rem  elevation, which produces the standard "Do you want to allow this app to
rem  make changes?" prompt.
rem
rem  ONLY USE THIS TEMPLATE IF THE SCRIPT GENUINELY NEEDS ADMINISTRATOR RIGHTS.
rem  If it only changes the current user's own settings, use the read-only
rem  template instead and do not request elevation. Asking for privileges you
rem  do not need trains people to click "Yes" without reading, which is how
rem  they end up approving something that matters.
rem ===========================================================================
setlocal
title <<< EDIT: window title >>>
cd /d "%~dp0"

rem --- Are we already elevated? -------------------------------------------
rem  "fltmc" is a filter-manager command that only succeeds when running with
rem  administrator rights. Testing it is more reliable across Windows versions
rem  than checking for a specific group membership.
fltmc >nul 2>&1
if not errorlevel 1 goto :elevated

echo.
echo   This task needs administrator rights.
echo.
echo   Windows will now show a prompt asking you to allow it. That prompt is
echo   Windows itself asking, not this script. If you would rather not, close
echo   the prompt and nothing will happen.
echo.
pause

rem  Re-launch THIS SAME FILE with elevation. The single quotes handle spaces
rem  in the folder name; the elevated copy starts in System32, which is why the
rem  "cd /d" above matters.
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" 2>nul
if errorlevel 1 (
    echo.
    echo   Elevation was refused or cancelled. Nothing has been changed.
    echo.
    pause
)
exit /b

:elevated
echo.
echo   Running with administrator rights.
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
