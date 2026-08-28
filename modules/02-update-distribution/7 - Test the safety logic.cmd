@echo off
rem ===========================================================================
rem  Double-click this to test the module's own safety machinery.
rem
rem  IT CHANGES NOTHING on your machine. It works in a temporary folder and
rem  deletes it afterwards. No administrator rights are requested.
rem
rem  What it checks is the logic that decides WHETHER to write anything:
rem    - that a file which is merely JSON-shaped is rejected as a backup
rem    - that a backup naming registry paths this module does not own is
rem      refused rather than obeyed
rem    - that a backup which failed to write reports failure, so the apply
rem      script aborts instead of changing things with no undo
rem    - that only the apply path can define "the original state"
rem    - that the undo never offers its own pre-restore snapshots, which would
rem      make running it twice re-apply the changes
rem    - that "not set at all" and "set to zero" stay distinguishable, including
rem      through a round trip to JSON and back
rem
rem  Every one of those corresponds to a defect that was actually found - most
rem  of them in module 01, by adversarial audit, after it had been written
rem  carefully by someone who believed it was correct.
rem
rem  This does NOT prove the writes themselves work. That is what
rem  "6 - Prove the undo works.cmd" does, and it needs administrator rights.
rem ===========================================================================
setlocal
title Update distribution - safety logic self-test
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
