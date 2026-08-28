@echo off
rem ===========================================================================
rem  Double-click this to apply all TEN settings, including the five that are
rem  real but that Microsoft has not documented anywhere this project can quote.
rem
rem  The notable one is SilentInstalledAppsEnabled, which governs whether
rem  Windows may install promoted apps without asking you.
rem
rem  These are fully backed up and fully reversible, exactly like the others.
rem  The only difference is that this project cannot cite a source for them,
rem  and it will not pretend otherwise by applying them silently.
rem
rem  No administrator rights are requested. Every setting this module touches
rem  belongs to your account only.
rem ===========================================================================
setlocal
title Recommendations - apply all
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Disable-Recommendations.ps1" -IncludeObserved

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
