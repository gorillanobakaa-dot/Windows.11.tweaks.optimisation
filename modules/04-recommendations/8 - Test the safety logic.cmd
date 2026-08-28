@echo off
rem ===========================================================================
rem  Double-click this to test the machinery that decides WHETHER to write.
rem
rem  IT CHANGES NOTHING. It works in a temporary folder and deletes it after.
rem
rem  Number 7 proves the writes work by performing them. This proves the
rem  decisions work, by feeding the module input it would never meet in normal
rem  use: a corrupt backup, one naming registry keys this module does not own,
rem  an unwritable backup folder, a tag full of illegal filename characters.
rem
rem  No administrator rights are requested. Every setting this module touches
rem  belongs to your account only.
rem ===========================================================================
setlocal
title Recommendations - safety logic self-test
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-SafetyLogic.ps1"

echo.
echo   --------------------------------------------------------------------
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
