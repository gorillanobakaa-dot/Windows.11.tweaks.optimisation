@echo off
rem ===========================================================================
rem  Double-click this to test the module's own safety machinery.
rem
rem  IT CHANGES NOTHING. It works in a temporary folder and deletes it after.
rem  No administrator rights are requested.
rem
rem  Number 6 proves the WRITES work, by performing them. This proves the
rem  DECISIONS work, by feeding the module input it would never meet in normal
rem  use: a corrupt backup, a backup naming registry keys this module does not
rem  own, an unwritable backup folder, a tag full of characters that are
rem  illegal in a filename, a value that is not a whole number.
rem
rem  Those situations cannot be produced by using the module correctly, which
rem  is exactly why they are never found by using it correctly. Two independent
rem  auditors found ten real defects in this module and most of them lived here.
rem
rem  Every check corresponds to a defect that was actually found.
rem ===========================================================================
setlocal
title Visual effects - safety logic self-test
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Test-SafetyLogic.ps1"

echo.
echo   --------------------------------------------------------------------
echo   Nothing on your machine was changed.
echo.
if defined W11T_CHAIN (
echo   Press any key to move on to the NEXT step in the sequence...
) else (
echo   Press any key to close this window.
)
pause >nul
