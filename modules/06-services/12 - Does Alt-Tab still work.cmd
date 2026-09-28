@echo off
rem  Presses Alt+Tab and checks the task switcher still appears, and
rem  cross-checks all three profiles against the services the shell needs.
rem  Changes nothing.
setlocal
title Services - does Alt-Tab still work
cd /d "%~dp0"
if not exist "%~dp0..\..\READ-ONLY-diagnostics\Test-AltTab.ps1" (
    echo.
    echo   This option uses the project's private diagnostics folder, which is
    echo   not part of the public download. Every module's own check - option
    echo   [1] inside each module menu - works without it.
    goto :done
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\READ-ONLY-diagnostics\Test-AltTab.ps1"
:done
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
