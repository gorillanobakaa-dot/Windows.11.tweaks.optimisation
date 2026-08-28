@echo off
rem ===========================================================================
rem  Double-click this to turn off suggestions, tips, personalised content and
rem  Start-menu recommendations for your account.
rem
rem  This applies the FIVE settings Microsoft documents explicitly. The five
rem  undocumented ones - including the setting that lets Windows install
rem  promoted apps without asking - are applied by number 4 instead.
rem
rem  It backs up first and checks the backup was really written. If the backup
rem  fails it changes nothing.
rem
rem  No administrator rights are requested. Every setting this module touches
rem  belongs to your account only.
rem ===========================================================================
setlocal
title Recommendations - apply
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Disable-Recommendations.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
