# Module 10 (10-text-input-guard): per-user scheduled task that ends a stuck TextInputHost.exe

> Session record generated 2026-09-28

---

## Problem Being Solved

`TextInputHost.exe` (package `MicrosoftWindows.Client.CBS`, build 26200.9457) enters a loop in which one thread holds one logical processor at 97-99 %. On the audited machine the first copy had used 14,594 CPU-seconds by 18:24, 14,520 of them in thread 11812. A screenshot by the Claude Code computer-use tool, which masks `textinputhost.exe` windows during capture, starts the loop within 15-30 s (reproduced at 18:42 and 18:57). No registry setting explained it.

## Approach Taken

Do not disable the feature or `TextInputManagementService`. Install a per-user scheduled task `\W11T\TextInputHost guard` (`LogonType Interactive`, `RunLevel Limited`, repetition `PT10M`, no duration) whose action is `conhost.exe --headless powershell.exe ... -File Invoke-TextInputGuard.ps1 -ThresholdPercent 90 -WindowSeconds 60 -Quiet`. The guard differences `Process.TotalProcessorTime` across the window and calls `Stop-Process` only on verdict `end`. The module follows MODULE-STANDARD: one-row settings table in `_Common.ps1`, `Test-`/`Install-`/`Restore-` trio, backups with `-RecordAsOriginal` and `_~prerestore`, `Test-SafetyLogic.ps1`, `Test-RoundTrip.ps1`, nine launchers.

## Before

No guard task; the first stuck copy running since sign-in at 06:37:24; module number 10 unallocated.

## After

Commit `62be63d` adds `modules/10-text-input-guard/` (21 files with the launchers), a `[T]` menu in `START HERE - open this first.cmd`, and register row 10 in `MODULE-STANDARD.md`. The task is installed on the audited machine with defaults. Verified by execution, not by reading: 62/62 self-test checks, round trip PASS (1 item), `-Original` after two installs, `-Backup` of a `_~prerestore` snapshot, the real scheduled task ending pid 17384 at 97.1 %.

## Known Alternatives

Disabling `TextInputManagementService` (rejected: it also carries text input for the Start menu search, Settings and modern apps - engineering observation, not documented in the corpus); putting the guard in the fan-control service (rejected: that service runs as SYSTEM and serves other platforms); `-WindowStyle Hidden` instead of `conhost --headless` (not taken and not tested here; `conhost --headless` was tested and showed no window); using `READ-ONLY-diagnostics/_MeasureLib.ps1` per R15.2 (not possible: that folder is not published).

## Files Changed

| File | Change | What Changed | Why |
|------|--------|--------------|-----|
| `modules/10-text-input-guard/_Common.ps1` | added | `$TigTask` table, `Get-TigCpuPercent`, `Get-TigVerdict`, `Test-TigGenuinePath`, `Measure-TigProcesses`, task XML parsing (`Get-TigTaskSettings`), `Test-TigLegitTaskXml`, `Test-TigSameTask`, `Save-TigBackup`, `Read-TigBackup`, `Get-TigBackups`, `Set-TigTaskFromState`, log helpers | One source of truth for install, undo, tests and the guard (R2.7) |
| `modules/10-text-input-guard/Invoke-TextInputGuard.ps1` | added | the guard: measure, verdict, `Stop-Process`, log; exit 0/10/1 | What the task runs |
| `modules/10-text-input-guard/Install-TextInputGuard.ps1` | added | backup then `Register-ScheduledTask -Force`, read-back verification; exit 0/3/4/5 | The applying script |
| `modules/10-text-input-guard/Restore-TextInputGuard.ps1` | added | no-arg, `-Original`, `-Backup`, `-List`, `-WhatIf`; fatal pre-restore snapshot | R2.4, R2.6, R4.4b, R4.5, R16.6 |
| `modules/10-text-input-guard/Test-SafetyLogic.ps1` | added | 62 checks; `[object]` assertion parameter and an outer `catch` counted as failure | R2.8, R2.8a |
| `modules/10-text-input-guard/Test-RoundTrip.ps1` | added | install, no-arg undo, compare by task content; INCONCLUSIVE on exit 4; cleanup on PASS | R2.9, R16.2, R16.4 |
| `START HERE - open this first.cmd` | modified | `[T]` main-menu entry and `:m10` submenu; listed as not part of APPLY ALL / UNDO ALL | Every module action reachable from the control panel |
| `modules/MODULE-STANDARD.md` | modified | register row 10; 11+ unallocated | R1.4 number allocation |

## Decisions Made

- 📄 **Leave the feature and its service enabled** - TextInputManagementService also carries typing into the Start menu search, Settings and modern apps
- 📄 **Per-user task with limited rights** - no administrator rights, runs as the user, can only end the user's own processes
- 🤖 **Compare tasks by Command, Arguments, interval and RunLevel, not raw XML** - Task Scheduler rewrites incidental XML (dates, whitespace, the user as a SID) on registration
- 📄 **A window shorter than 90 % of its length yields verdict `unknown`** - a window cut short measures nothing trustworthy; added after the 3 ms measurement defect
- 📄 **Read the log, not `LastTaskResult`** - conhost does not pass on the guard's exit code 10

## Tried and Abandoned

- **`if ($first.Count)` on the result of `Get-TigProcesses`** - Windows PowerShell 5.1 returns a single object unwrapped with no dependable `.Count`; the wait was skipped and a 3 ms window measured. Now `@(Get-TigProcesses)`
- **Converting inputs with `-as [double]` directly** - `$null -as [double]` is 0, so an unreadable counter read as idle; missing values are now tested first
- **Returning the difference list as `,$d`** - wrapped in `@()` it counts as one item; caught before the first run
- **Interpreting `LastTaskResult` 10 as 'ended a stuck copy'** - the recorded result is always 0 through conhost

## ⚠ Claimed But Not Verified

*Prior documents claimed these are done. No test evidence found in this diff:*

- That `conhost --headless` hides the window on builds other than 26200
- That normal heavy use of the panels (long voice typing) stays below 90 % of a core for a minute
- That other screen-capture or accessibility tools trigger the loop
- Behaviour on other editions, builds and machines

## Open Items

| Item | Priority | Blocks |
|------|----------|--------|
| Adversarial audit of module 10 | medium | calling the module finished by the project's own rule |
| Module 09's `Test-SafetyLogic.ps1` types its `Check` condition as `[bool]` and has no failure-counting `catch` (R2.8a) | medium | module 09's self-test result can be a false pass |
| Report the screenshot trigger to Anthropic | low | nothing currently |

## How to verify this work is correct

**Step 1:**
```bash
`powershell -ExecutionPolicy Bypass -File .\Test-SafetyLogic.ps1`
```
  - **Pass:** `checks passed : 62`, `checks failed : 0`, exit 0
  - **Fail:** any `FAILED:` line, or 'the self-test stopped early'

**Step 2:**
```bash
`powershell -ExecutionPolicy Bypass -File .\Restore-TextInputGuard.ps1 -Original` then `.\Test-RoundTrip.ps1 -Force`
```
  - **Pass:** `PASS - everything came back`, `items that changed: 1`, exit 0
  - **Fail:** `FAIL` with a list, or `INCONCLUSIVE` (the guard was still installed)

**Step 3:**
```bash
Install, cause the fault (a screen capture that masks TextInputHost), then `Start-ScheduledTask -TaskPath '\W11T\' -TaskName 'TextInputHost guard'` and wait 70 s
```
  - **Pass:** a new line in `guard-log.txt`: `ended TextInputHost pid N: 9x.x % of one core for 60 s`
  - **Fail:** the task finishes in seconds with no log line (the measurement did not wait)

**Step 4:**
```bash
`Export-ScheduledTask -TaskPath '\W11T\' -TaskName 'TextInputHost guard'`
```
  - **Pass:** `<RunLevel>LeastPrivilege</RunLevel>`, `<Interval>PT10M</Interval>`, command `conhost.exe`
  - **Fail:** `HighestAvailable`, or an action other than conhost


## Glossary

**TotalProcessorTime** - The cumulative CPU time a process has used; read twice and differenced it gives the share of one core over the window.

**conhost --headless** - Starts a console program with no visible window (observed on build 26200).

**`_~prerestore`** - The suffix of the undo's own snapshot; the `~` cannot appear in a user tag, so the two cannot collide (R16.3).

**Verdict** - `end`, `ok`, `young` or `unknown`; only `end` ends a process.

## Technical Debt

🟡 **LOW** - The guard's own measurement instead of `_MeasureLib.ps1` → Publish a minimal measuring library, or keep the deviation stated in the README
🟡 **LOW** - The task stores the module folder's full path → Keep the warning in option 1; consider re-registering the task when the check sees another path
🟠 **MEDIUM** - No adversarial audit → Run the project's audit on module 10 before the next release

## Claim Sources

| Claim | Basis | Evidence |
|-------|-------|----------|
| One thread held almost all the process's CPU time | 📄 stated in input | One of its 41 threads had used 14,520 of the process's 14,594 seconds |
| The screenshot is the trigger on this machine | 📄 stated in input | one screenshot at 18:42:10, and by 18:42:26 it was at 19.7 CPU-seconds |
| The guard works end to end | 📄 stated in input | The next real run ended a stuck copy at 97.1 % |
| Task Scheduler rewrites incidental XML | 🤖 model inference | *(none - model judgment)* |
| Disabling the service would break typing in modern apps | 🤖 model inference | *(none - model judgment)* |
| Module 09's self-test can falsely pass | 🤖 model inference | *(none - model judgment)* |


---
**How to verify this document:**
`📄 stated in input` - the model's phrasing of something your source text said.
Find the matching line in the original to verify.
`🤖 model inference` - the model's own judgment or synthesis. Treat as opinion,
not measurement. Re-run on the same input and check whether specific numbers
stay consistent between runs.

*Session record. Developer track. Covers work done, not current code state.*