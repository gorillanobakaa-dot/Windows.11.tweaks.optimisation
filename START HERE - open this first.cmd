@echo off
rem ===========================================================================
rem  THE central control panel. Every action in every module runs from here:
rem  check, preview, apply, undo, prove the undo - plus APPLY ALL and UNDO
rem  ALL. Each action explains itself and asks before changing anything;
rem  applies write a verified backup first. The module folders stay browsable
rem  for anyone who wants to read the code, but you never NEED to leave this
rem  menu.
rem
rem  You can open this file in Notepad and read every line of it. Please do.
rem ===========================================================================
setlocal
title Windows 11 tweaks - control panel
cd /d "%~dp0"

:menu
cls
echo.
echo   ===================================================================
echo     WINDOWS 11 TWEAKS AND OPTIMISATION  -  CONTROL PANEL (v0.1.0-beta)
echo   ===================================================================
echo.
echo     Everything runs from THIS menu. Every change asks first and
echo     writes a backup first. Reads never change anything.
echo     Most changes have an undo. The two that REMOVE software - [5]
echo     Copilot and [R] bloat apps - say plainly where they do not.
echo.
echo     [1]  Unblock the downloaded files        DO THIS FIRST, once.
echo     [2]  Show what my machine is set to now  reads only, SAVES A FILE
echo.
echo     One module at a time - check it, apply it, undo it:
echo     [3]  Visual effects        stop menus and windows dawdling
echo     [4]  Update sharing        stop serving updates to other PCs
echo     [5]  Copilot               turn off, or remove entirely
echo     [6]  Suggestions and ads   incl. Windows installing apps unasked
echo     [7]  Xbox services         lock the wakeable Xbox surface
echo     [8]  SERVICES + profiles   light / moderate / super hardening
echo     [D]  Defer feature updates  hold the big releases 3 / 6 / 12 months
echo.
echo     Removes software - no undo from a backup:
echo     [R]  Remove bloat apps      Game Bar, Xbox, Teams, Widgets, preloads
echo.
echo     Or everything at once:
echo     [A]  APPLY ALL modules     each backs itself up first
echo     [U]  UNDO ALL modules      put every setting back
echo.
echo     [C]  Does ALT-TAB still work?  a real test, not an opinion
echo     [H]  How do I run the tools?  worked examples, real output
echo     [9]  Where is the project up to? (ROADMAP)  [0] README  [Q] Quit
echo.
set "pick="
set /p "pick=  Type your choice and press Enter (or just Enter to quit): "
if not defined pick goto end
if /i "%pick%"=="1" goto unblock
if /i "%pick%"=="2" goto checkall
if /i "%pick%"=="3" goto m01
if /i "%pick%"=="4" goto m02
if /i "%pick%"=="5" goto m03
if /i "%pick%"=="6" goto m04
if /i "%pick%"=="7" goto m05
if /i "%pick%"=="8" goto m06
if /i "%pick%"=="D" goto m07
if /i "%pick%"=="R" goto m08
if /i "%pick%"=="A" goto applyall
if /i "%pick%"=="U" goto undoall
if /i "%pick%"=="C" goto alttab
if /i "%pick%"=="H" start "" "%~dp0TOOLS-HOWTO.md"
if /i "%pick%"=="9" start "" "%~dp0ROADMAP.md"
if /i "%pick%"=="0" start "" "%~dp0README.md"
if /i "%pick%"=="Q" goto end
goto menu

:unblock
cls
echo.
echo   Removing the internet tag from the files in this folder...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -File | Unblock-File; Write-Host ''; Write-Host '  Done. No Windows setting was changed - only the hidden marker Windows'; Write-Host '  attaches to downloaded files was removed from the files in this folder.'"
echo.
pause
goto menu

:checkall
cls
echo.
echo   Running every module's read-only check, one after another, and
echo   SAVING THE WHOLE THING to a file so you do not have to copy it out
echo   of this window. None of them can change anything.
echo.
echo   This takes a minute. The file path is printed at the end.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0READ-ONLY-diagnostics\Save-StateReport.ps1"
echo.
set "seelog="
set /p "seelog=  Open the logs folder now? Type Y, or just press Enter: "
if /i "%seelog%"=="Y" start "" "%~dp0logs"
pause
goto menu

rem ===========================================================================
:applyall
cls
echo.
echo   APPLY ALL  -  what will run, in order:
echo   -------------------------------------------------------------------
echo     1. Visual effects        apply
echo     2. Update sharing        apply - Windows will ask for admin
echo     3. Copilot               turn OFF, settings only. The removals
echo                              are NOT included: they cannot be undone,
echo                              so they stay a separate, deliberate click.
echo     4. Suggestions and ads   apply the five Microsoft documents
echo     5. Xbox services         disable - Windows will ask for admin
echo.
echo   THREE THINGS ARE NOT PART OF "ALL". Typing YES does NOT do any of
echo   these. They only happen if you open that menu yourself and pick them:
echo.
echo     [8] Services profiles    can stop printing, Bluetooth and Windows
echo                              search from working. You choose how far.
echo     [D] Feature-update hold  you choose 3, 6 or 12 months.
echo     [R] Remove bloat apps    DELETES apps. Nothing can put deleted
echo                              software back from a backup file.
echo.
echo   They are left out because each one costs you something real, and
echo   which of those trades you want is your call, not a default.
echo.
echo   THE FIVE ABOVE ARE DIFFERENT. Each writes a verified backup before
echo   it changes anything, and [U] on the main menu undoes all five.
echo.
set "sure="
set /p "sure=  Type YES to run all five, anything else to go back: "
if /i not "%sure%"=="YES" goto menu
set "W11T_CHAIN=1"
echo.
echo   Each step runs in turn and PAUSES when it finishes. Press a key at
echo   each pause to move on to the next one. Steps needing admin will also
echo   show a Windows permission prompt in a separate window.
echo.
call "%~dp0modules\01-visual-effects\3 - Apply the changes.cmd"
call "%~dp0modules\02-update-distribution\3 - Apply the changes.cmd"
call "%~dp0modules\03-copilot\3 - Turn Copilot off (settings only).cmd"
call "%~dp0modules\04-recommendations\3 - Apply the changes.cmd"
call "%~dp0modules\05-xbox-services\3 - Apply the changes.cmd"
set "W11T_CHAIN="
echo.
echo   =====================================================================
echo   APPLY ALL finished. Each module printed its own result above; each
echo   wrote its own backup. [U] on the main menu reverses all of it.
echo.
pause
goto menu

rem ===========================================================================
:undoall
cls
echo.
echo   UNDO ALL  -  what will run, in order:
echo   -------------------------------------------------------------------
echo     1. Visual effects        undo, from its newest backup
echo     2. Update sharing        undo - Windows will ask for admin
echo     3. Copilot               undo the SETTINGS. If you also clicked
echo                              REMOVE earlier, removed software cannot
echo                              come back from a backup - reinstalling
echo                              is the route back, and the module says so.
echo     4. Suggestions and ads   undo, from its newest backup
echo     5. Xbox services         undo - Windows will ask for admin
echo     6. Services profile      undo - restores every start type
echo     7. Feature-update hold   undo - removes the policy values
echo.
echo   NOT undone: apps you deleted with [R]. Deleted software cannot come
echo   back from a backup file - this menu cannot reverse it and does not
echo   pretend to. To try: go back, press [R], then choose 8 in that menu.
echo   It puts back whatever it still can, and names what only the
echo   Microsoft Store can reinstall.
echo.
set "sure="
set /p "sure=  Type YES to undo all seven, anything else to go back: "
if /i not "%sure%"=="YES" goto menu
set "W11T_CHAIN=1"
echo.
echo   Each step runs in turn and PAUSES when it finishes. Press a key at
echo   each pause to move on to the next one. Steps needing admin will also
echo   show a Windows permission prompt in a separate window.
echo.
call "%~dp0modules\01-visual-effects\4 - UNDO everything.cmd"
call "%~dp0modules\02-update-distribution\4 - UNDO everything.cmd"
call "%~dp0modules\03-copilot\4 - UNDO the settings.cmd"
call "%~dp0modules\04-recommendations\5 - UNDO everything.cmd"
call "%~dp0modules\05-xbox-services\4 - UNDO everything.cmd"
call "%~dp0modules\06-services\8 - UNDO everything.cmd"
call "%~dp0modules\07-update-deferral\6 - UNDO everything.cmd"
set "W11T_CHAIN="
echo.
echo   =====================================================================
echo   UNDO ALL finished. Each module printed its own result above.
echo.
pause
goto menu

rem ===========================================================================
:m01
cls
echo.
echo   VISUAL EFFECTS  (module 01)
echo   -------------------------------------------------------------------
echo   Turns off the animations that make every menu and window wait.
echo   Proved on this machine: menus went from 400 ms to instant.
echo.
echo     [1]  Check what is on now           reads only
echo     [2]  Preview the changes            reads only, lists every change
echo     [3]  APPLY the changes              backup written first
echo     [4]  UNDO                           back to the newest backup
echo     [5]  UNDO back to the original      as if this was never run
echo     [6]  Prove the undo works           apply, undo, compare - net zero
echo     [7]  Measure what it actually saves
echo     [8]  Open the module folder         read the code and its README
echo     [B]  Back to the main menu
echo.
set "pick="
set /p "pick=  Type your choice and press Enter: "
if not defined pick goto menu
if /i "%pick%"=="1" call "%~dp0modules\01-visual-effects\1 - Check what is on now.cmd"
if /i "%pick%"=="2" call "%~dp0modules\01-visual-effects\2 - Preview the changes (safe).cmd"
if /i "%pick%"=="3" call "%~dp0modules\01-visual-effects\3 - Apply the changes.cmd"
if /i "%pick%"=="4" call "%~dp0modules\01-visual-effects\4 - UNDO everything.cmd"
if /i "%pick%"=="5" call "%~dp0modules\01-visual-effects\5 - UNDO back to the original.cmd"
if /i "%pick%"=="6" call "%~dp0modules\01-visual-effects\6 - Prove the undo works.cmd"
if /i "%pick%"=="7" call "%~dp0modules\01-visual-effects\7 - Measure what it actually saves.cmd"
if /i "%pick%"=="8" start "" "%~dp0modules\01-visual-effects"
if /i "%pick%"=="B" goto menu
goto m01

rem ===========================================================================
:m02
cls
echo.
echo   UPDATE SHARING  (module 02)
echo   -------------------------------------------------------------------
echo   Windows offers Windows-update files from this PC to other machines
echo   and holds port 7680 open for it. This closes that. Your own updates
echo   still download normally, straight from Microsoft.
echo.
echo     [1]  Check what is on now           reads only
echo     [2]  Preview the changes            reads only, lists every change
echo     [3]  APPLY the changes              backup first - asks for admin
echo     [4]  UNDO                           back to the newest backup
echo     [5]  UNDO back to the original      as if this was never run
echo     [6]  Prove the undo works           apply, undo, compare - net zero
echo     [7]  Open the module folder         read the code and its README
echo     [B]  Back to the main menu
echo.
set "pick="
set /p "pick=  Type your choice and press Enter: "
if not defined pick goto menu
if /i "%pick%"=="1" call "%~dp0modules\02-update-distribution\1 - Check what is on now.cmd"
if /i "%pick%"=="2" call "%~dp0modules\02-update-distribution\2 - Preview the changes (safe).cmd"
if /i "%pick%"=="3" call "%~dp0modules\02-update-distribution\3 - Apply the changes.cmd"
if /i "%pick%"=="4" call "%~dp0modules\02-update-distribution\4 - UNDO everything.cmd"
if /i "%pick%"=="5" call "%~dp0modules\02-update-distribution\5 - UNDO back to the original.cmd"
if /i "%pick%"=="6" call "%~dp0modules\02-update-distribution\6 - Prove the undo works.cmd"
if /i "%pick%"=="7" start "" "%~dp0modules\02-update-distribution"
if /i "%pick%"=="B" goto menu
goto m02

rem ===========================================================================
:m03
cls
echo.
echo   COPILOT  (module 03)
echo   -------------------------------------------------------------------
echo   Copilot here is four things: an app, a second hidden 1.3 GB install,
echo   a system service, and settings. The SETTINGS are undoable from a
echo   backup. The REMOVALS ARE NOT - the route back is reinstalling.
echo.
echo     [1]  Check what is on now              reads only
echo     [2]  Preview everything                reads only
echo     [3]  Turn Copilot off - settings only  reversible, backup first
echo     [4]  UNDO the settings                 back to the newest backup
echo     [5]  Prove the settings undo works     apply, undo, compare
echo     [6]  REMOVE the app                    back only via the Store
echo     [7]  REMOVE everything - needs admin   back only by reinstalling
echo     [8]  Open the module folder            read the code and its README
echo     [B]  Back to the main menu
echo.
set "pick="
set /p "pick=  Type your choice and press Enter: "
if not defined pick goto menu
if /i "%pick%"=="1" call "%~dp0modules\03-copilot\1 - Check what is on now.cmd"
if /i "%pick%"=="2" call "%~dp0modules\03-copilot\2 - Preview the changes (safe).cmd"
if /i "%pick%"=="3" call "%~dp0modules\03-copilot\3 - Turn Copilot off (settings only).cmd"
if /i "%pick%"=="4" call "%~dp0modules\03-copilot\4 - UNDO the settings.cmd"
if /i "%pick%"=="5" call "%~dp0modules\03-copilot\5 - Prove the settings undo works.cmd"
if /i "%pick%"=="6" call "%~dp0modules\03-copilot\6 - REMOVE the Copilot app.cmd"
if /i "%pick%"=="7" call "%~dp0modules\03-copilot\7 - REMOVE everything (needs admin).cmd"
if /i "%pick%"=="8" start "" "%~dp0modules\03-copilot"
if /i "%pick%"=="B" goto menu
goto m03

rem ===========================================================================
:m04
cls
echo.
echo   SUGGESTIONS AND ADS  (module 04)
echo   -------------------------------------------------------------------
echo   Tips, "recommendations", Start menu promos - including the switch
echo   that lets Windows install promoted apps without asking. Five of the
echo   ten switches are documented by Microsoft; the other five are real
echo   but undocumented, so they sit behind their own separate button.
echo.
echo     [1]  Check what is on now             reads only
echo     [2]  Preview the changes              reads only, lists every change
echo     [3]  APPLY the documented five        backup written first
echo     [4]  Apply the undocumented five too  labelled for what they are
echo     [5]  UNDO                             back to the newest backup
echo     [6]  UNDO back to the original        as if this was never run
echo     [7]  Prove the undo works             apply, undo, compare - net zero
echo     [8]  Open the module folder           read the code and its README
echo     [B]  Back to the main menu
echo.
set "pick="
set /p "pick=  Type your choice and press Enter: "
if not defined pick goto menu
if /i "%pick%"=="1" call "%~dp0modules\04-recommendations\1 - Check what is on now.cmd"
if /i "%pick%"=="2" call "%~dp0modules\04-recommendations\2 - Preview the changes (safe).cmd"
if /i "%pick%"=="3" call "%~dp0modules\04-recommendations\3 - Apply the changes.cmd"
if /i "%pick%"=="4" call "%~dp0modules\04-recommendations\4 - Apply the undocumented ones too.cmd"
if /i "%pick%"=="5" call "%~dp0modules\04-recommendations\5 - UNDO everything.cmd"
if /i "%pick%"=="6" call "%~dp0modules\04-recommendations\6 - UNDO back to the original.cmd"
if /i "%pick%"=="7" call "%~dp0modules\04-recommendations\7 - Prove the undo works.cmd"
if /i "%pick%"=="8" start "" "%~dp0modules\04-recommendations"
if /i "%pick%"=="B" goto menu
goto m04

rem ===========================================================================
:m05
cls
echo.
echo   XBOX SERVICES  (module 05)
echo   -------------------------------------------------------------------
echo   Five services that sit "Manual and stopped" - not off, WAKEABLE, four
echo   of them as LocalSystem. Microsoft's own guidance: "Should be
echo   disabled". This locks them, reversibly, previous values backed up.
echo.
echo     [1]  Check what is on now           reads only
echo     [2]  Preview the changes            reads only, lists every change
echo     [3]  APPLY - disable them           backup first - asks for admin
echo     [4]  UNDO                           back to the newest backup
echo     [5]  UNDO back to the original      as if this was never run
echo     [6]  Prove the undo works           apply, undo, compare - net zero
echo     [7]  Test the safety logic          reads only
echo     [8]  Open the module folder         read the code and its README
echo     [B]  Back to the main menu
echo.
set "pick="
set /p "pick=  Type your choice and press Enter: "
if not defined pick goto menu
if /i "%pick%"=="1" call "%~dp0modules\05-xbox-services\1 - Check what is on now.cmd"
if /i "%pick%"=="2" call "%~dp0modules\05-xbox-services\2 - Preview the changes (safe).cmd"
if /i "%pick%"=="3" call "%~dp0modules\05-xbox-services\3 - Apply the changes.cmd"
if /i "%pick%"=="4" call "%~dp0modules\05-xbox-services\4 - UNDO everything.cmd"
if /i "%pick%"=="5" call "%~dp0modules\05-xbox-services\5 - UNDO back to the original.cmd"
if /i "%pick%"=="6" call "%~dp0modules\05-xbox-services\6 - Prove the undo works.cmd"
if /i "%pick%"=="7" call "%~dp0modules\05-xbox-services\7 - Test the safety logic.cmd"
if /i "%pick%"=="8" start "" "%~dp0modules\05-xbox-services"
if /i "%pick%"=="B" goto menu
goto m05

rem ===========================================================================
:m06
cls
echo.
echo   SERVICES - PROFILES  (module 06)
echo   -------------------------------------------------------------------
echo   284 services are installed here. MODERATE is applied: 123 are now
echo   disabled, 93 still sit at "Manual" - not off, but started by Windows
echo   when something asks. 69 can still be woken by a trigger.
echo.
echo     LIGHT      64 present here - scanning, hotspot, backup, smart cards
echo     MODERATE  117 - plus remote access, cloud sync, diagnostics  [APPLIED]
echo     SUPER     167 - plus printing, Bluetooth, search indexing
echo.
echo   MODERATE is not fully in place: 5 services outstanding. 3 REFUSED
echo   the write (their registry keys deny Administrators), 1 came back
echo   on its own, 1 was added later. Re-running [6] fixes the last two.
echo.
echo     [1]  Check what is on now         reads only
echo     [2]  Preview LIGHT                reads only, every service listed
echo     [3]  Preview MODERATE             reads only
echo     [4]  Preview SUPER                reads only - READ THIS FIRST
echo     [5]  APPLY LIGHT                  backup first - asks for admin
echo     [6]  APPLY MODERATE               backup first - asks for admin
echo     [7]  APPLY SUPER                  backup first - asks for admin
echo     [8]  UNDO everything              every start type back
echo     [9]  UNDO back to the original    as if this was never run
echo     [P]  Prove the undo works         apply, undo, compare - net zero
echo     [T]  Test the safety logic        reads only
echo     [C]  Does ALT-TAB still work?     presses it and looks
echo     [O]  Open the module folder       read the code and its README
echo     [B]  Back to the main menu
echo.
set "pick="
set /p "pick=  Type your choice and press Enter: "
if not defined pick goto menu
if /i "%pick%"=="1" call "%~dp0modules\06-services\1 - Check what is on now.cmd"
if /i "%pick%"=="2" call "%~dp0modules\06-services\2 - Preview LIGHT.cmd"
if /i "%pick%"=="3" call "%~dp0modules\06-services\3 - Preview MODERATE.cmd"
if /i "%pick%"=="4" call "%~dp0modules\06-services\4 - Preview SUPER.cmd"
if /i "%pick%"=="5" call "%~dp0modules\06-services\5 - APPLY profile LIGHT.cmd"
if /i "%pick%"=="6" call "%~dp0modules\06-services\6 - APPLY profile MODERATE.cmd"
if /i "%pick%"=="7" call "%~dp0modules\06-services\7 - APPLY profile SUPER.cmd"
if /i "%pick%"=="8" call "%~dp0modules\06-services\8 - UNDO everything.cmd"
if /i "%pick%"=="9" call "%~dp0modules\06-services\9 - UNDO back to the original.cmd"
if /i "%pick%"=="P" call "%~dp0modules\06-services\10 - Prove the undo works.cmd"
if /i "%pick%"=="T" call "%~dp0modules\06-services\11 - Test the safety logic.cmd"
if /i "%pick%"=="C" call "%~dp0modules\06-services\12 - Does Alt-Tab still work.cmd"
if /i "%pick%"=="O" start "" "%~dp0modules\06-services"
if /i "%pick%"=="B" goto menu
goto m06

rem ===========================================================================
:m07
cls
echo.
echo   DEFER FEATURE UPDATES  (module 07)
echo   -------------------------------------------------------------------
echo   Windows ships two kinds of update. The monthly SECURITY patches, and
echo   the big twice-yearly FEATURE releases that rearrange your machine.
echo.
echo   This holds the feature releases back. Security patches keep coming -
echo   nothing here touches them, and the self-test proves it.
echo.
echo   NOTE: this is Windows 11 Home. Microsoft documents these settings for
echo   Pro, Education and Enterprise only. The module writes them and proves
echo   they were written - it does NOT claim Home obeys them. Check 1 records
echo   your Windows release each run so you can see for yourself over time.
echo.
echo     [1]  Check what is on now        reads only
echo     [2]  Preview the 3-month hold    reads only
echo.
echo     [3]  HOLD 3 months               asks for admin
echo     [4]  HOLD 6 months               asks for admin
echo     [5]  HOLD 12 months              asks for admin - the documented max
echo.
echo     [6]  UNDO everything             back to the newest backup
echo     [7]  UNDO back to the original   as if this was never run
echo     [P]  Prove the undo works        apply, undo, compare - net zero
echo     [T]  Test the safety logic       70 checks, reads only
echo     [O]  Open the module folder      read the code and its README
echo     [B]  Back to the main menu
echo.
set "pick="
set /p "pick=  Choice: "
if not defined pick goto menu
if /i "%pick%"=="1" call "%~dp0modules\07-update-deferral\1 - Check what is on now.cmd"
if /i "%pick%"=="2" call "%~dp0modules\07-update-deferral\2 - Preview the 3-month hold (safe).cmd"
if /i "%pick%"=="3" call "%~dp0modules\07-update-deferral\3 - HOLD feature updates 3 months.cmd"
if /i "%pick%"=="4" call "%~dp0modules\07-update-deferral\4 - HOLD feature updates 6 months.cmd"
if /i "%pick%"=="5" call "%~dp0modules\07-update-deferral\5 - HOLD feature updates 12 months.cmd"
if /i "%pick%"=="6" call "%~dp0modules\07-update-deferral\6 - UNDO everything.cmd"
if /i "%pick%"=="7" call "%~dp0modules\07-update-deferral\7 - UNDO back to the original.cmd"
if /i "%pick%"=="P" call "%~dp0modules\07-update-deferral\8 - Prove the undo works.cmd"
if /i "%pick%"=="T" call "%~dp0modules\07-update-deferral\9 - Test the safety logic.cmd"
if /i "%pick%"=="O" start "" "%~dp0modules\07-update-deferral"
if /i "%pick%"=="B" goto menu
goto m07

rem ===========================================================================
:m08
cls
echo.
echo   REMOVE BLOAT APPS  (module 08)
echo   -------------------------------------------------------------------
echo   107 app packages are installed for this account. 44 of them Windows
echo   will not let go of at all. Three cumulative tiers remove the rest.
echo.
echo     LIGHT      16 - Game Bar, Xbox overlays, Mixed Reality, Feedback
echo                     Hub, Journal, Clipchamp, Dev Home, People
echo     MODERATE   30 - plus Teams, Phone Link, Mail, Media Player,
echo                     WIDGETS, Bing in Start, OneDrive sync, Quick Assist
echo     SUPER      37 - plus WhatsApp, Adobe Express, Glance, Outlook,
echo                     Camera and PHOTOS (leaves no image viewer)
echo.
echo   THIS REMOVES SOFTWARE. There is no undo from a backup file. Where the
echo   payload survives on disk it can be re-registered; otherwise the Store
echo   is the only way back. [8] sorts them and tells you which is which.
echo.
echo   AND THEY COME BACK. Microsoft only blocks reinstalls on Enterprise and
echo   Education. This is Home. Windows Update reinstalled two Xbox packages
echo   on this machine by itself. Re-run [1] now and then to catch them.
echo.
echo     [1]  Check what is on now      reads only - names anything that CAME BACK
echo     [2]  Preview LIGHT             reads only
echo     [3]  Preview MODERATE          reads only
echo     [4]  Preview SUPER             reads only
echo.
echo     [5]  REMOVE tier LIGHT         asks for admin
echo     [6]  REMOVE tier MODERATE      asks for admin
echo     [7]  REMOVE tier SUPER         asks for admin
echo.
echo     [8]  Try to put back what was removed   best effort, not an undo
echo     [9]  Show what was removed              reads only
echo     [T]  Test the safety logic              58 checks, reads only
echo     [O]  Open the module folder
echo     [B]  Back to the main menu
echo.
set "pick="
set /p "pick=  Choice: "
if not defined pick goto menu
if /i "%pick%"=="1" call "%~dp0modules\08-app-debloat\1 - Check what is on now.cmd"
if /i "%pick%"=="2" call "%~dp0modules\08-app-debloat\2 - Preview LIGHT.cmd"
if /i "%pick%"=="3" call "%~dp0modules\08-app-debloat\3 - Preview MODERATE.cmd"
if /i "%pick%"=="4" call "%~dp0modules\08-app-debloat\4 - Preview SUPER.cmd"
if /i "%pick%"=="5" call "%~dp0modules\08-app-debloat\5 - REMOVE tier LIGHT.cmd"
if /i "%pick%"=="6" call "%~dp0modules\08-app-debloat\6 - REMOVE tier MODERATE.cmd"
if /i "%pick%"=="7" call "%~dp0modules\08-app-debloat\7 - REMOVE tier SUPER.cmd"
if /i "%pick%"=="8" call "%~dp0modules\08-app-debloat\8 - Try to put back what was removed.cmd"
if /i "%pick%"=="9" call "%~dp0modules\08-app-debloat\9 - Show what was removed.cmd"
if /i "%pick%"=="T" call "%~dp0modules\08-app-debloat\10 - Test the safety logic.cmd"
if /i "%pick%"=="O" start "" "%~dp0modules\08-app-debloat"
if /i "%pick%"=="B" goto menu
goto m08

rem ===========================================================================
:alttab
cls
echo.
echo   Hardening can break the Alt-Tab task switcher, and most people would
echo   never connect a broken switcher to a tweak made days earlier. So this
echo   does not give you an opinion - it presses Alt+Tab and looks.
echo.
echo   It changes NO setting. It briefly takes keyboard focus, then cancels.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0READ-ONLY-diagnostics\Test-AltTab.ps1"
echo.
pause
goto menu

:end
endlocal
