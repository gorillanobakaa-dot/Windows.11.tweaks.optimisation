@echo off
rem ===========================================================================
rem  Double-click this to make the machine PROVE the settings-undo works:
rem  apply for real, undo, compare every setting. REMOVES NOTHING - the
rem  removals are not reversible and no test here pretends otherwise.
rem  It is a real change while it runs, so it asks you to confirm first.
rem  No administrator rights are requested (the HKLM value is skipped
rem  unelevated, exercised in an elevated run).
rem ===========================================================================
setlocal
title Copilot - prove the undo
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-RoundTrip.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
