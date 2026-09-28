@echo off
rem ===========================================================================
rem  Double-click this to make your account PROVE the undo works.
rem
rem  It removes the environment variables and registry keys for real, undoes
rem  that, and compares every value and every key's full contents. Folders are
rem  left alone. A PASS means the net effect is nothing.
rem
rem  If number 3 has already run, there is nothing left to move and the test
rem  says INCONCLUSIVE. That is correct, not a failure.
rem ===========================================================================
setlocal
title OneDrive - prove the account undo
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-RoundTrip.ps1" -Part Account

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
