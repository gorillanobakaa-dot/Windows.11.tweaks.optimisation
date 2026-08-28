@echo off
rem ===========================================================================
rem  Double-click this to make your account PROVE the undo works, rather than
rem  taking our word for it.
rem
rem  It applies all ten changes for real, undoes them, then compares every
rem  setting one by one - including the difference between "set to zero" and
rem  "not set at all", and whether the policy key itself existed.
rem
rem  A PASS means the round trip is lossless and the net effect is nothing.
rem
rem  It is a real change while it runs, so it asks you to confirm first.
rem
rem  No administrator rights are requested. Every setting this module touches
rem  belongs to your account only.
rem ===========================================================================
setlocal
title Recommendations - prove the undo works
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-RoundTrip.ps1" -IncludeObserved

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
