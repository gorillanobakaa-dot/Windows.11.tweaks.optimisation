# TextInputHost guard: stop a stuck Windows text-input program from holding a processor core

## Just want to click something?

| Double-click this | What happens | Admin? |
|---|---|---|
| **1 - Check what is on now** | Shows whether TextInputHost is using the processor, and whether the guard is installed | No |
| **2 - Check TextInputHost for a minute (safe)** | Measures it for one minute, as the guard does, and ends nothing | No |
| **3 - Preview the install (safe)** | Shows what 4 would do, and changes nothing | No |
| **4 - Install the guard** | Installs the guard (backs up first) | No |
| **5 - Prove the undo works** | Installs, undoes and compares; the net effect is nothing | No |
| **6 - UNDO (remove the guard)** | Undoes the last install | No |
| **7 - UNDO back to the original** | Back to before this module was ever installed | No |
| **8 - Test the safety logic** | Tests the decision logic with inputs normal use never produces | No |
| **9 - End a stuck TextInputHost now** | Does once, now, what the guard does every 10 minutes | No |

The usual order is **1**, **3**, **4**, then **1** again after a while to see the guard's log.

This module is per-user. It needs no administrator rights and asks for none; it
creates one scheduled task that runs as you, with your normal rights, and it
ends only a program that runs as you.

---

## In plain language

### What TextInputHost is

`TextInputHost.exe` is part of Windows 11. It draws the touch keyboard, the
emoji panel (Windows key + full stop), clipboard history (Windows key + V),
voice typing (Windows key + H) and typing suggestions. Windows starts it when
you sign in and keeps it waiting in the background. It should use almost no
processor time until one of those panels is opened.

### What goes wrong

Sometimes one part of it (one "thread", a single line of work inside a program)
starts going round in a loop and never stops. It then keeps one of the
processor's cores busy all the time - on the machine this was built on, 97 to
99 % of one core - while doing nothing useful. The laptop gets warmer, the fan
runs harder, and the battery drains faster. Nothing on screen tells you.

Ending the stuck copy fixes it straight away. Nothing you typed is lost, and
Windows starts a fresh copy by itself the next time one of those panels is
needed.

### What this module does

It installs a **guard**: a scheduled task that runs every 10 minutes, as you,
with no window. Each time, it watches TextInputHost for one minute and counts
how much processor time it used. Only if it used at least **90 % of one core
for that whole minute** does it end it, and it writes one line in
`guard-log.txt` in this folder saying so. Normal use of the touch keyboard or
emoji panel comes nowhere near that.

What it costs you: every 10 minutes, a PowerShell program sits waiting for one
minute and then reads two numbers. It uses almost no processor time itself.

### What it deliberately does not do

It does not switch off the touch keyboard, emoji panel, clipboard history or
the Windows service behind them. That service also carries typing into the
Start menu search box, Settings and other modern Windows apps, so switching it
off would break typing there.

---

## What we found on this machine

Measured 2026-09-28 on the machine this project was built for: a ThinkPad L15
Gen 3, Intel Core i7-1255U, Windows 11 Home build 26200.9457. The machine
name is left out on purpose.

- **The first stuck copy.** At 18:21 one TextInputHost was using 99 % of one
  core. It had started at 06:37 when the account signed in and had used 14,594
  seconds (about four hours) of processor time. One of its 41 threads held
  14,520 of those seconds; the other 40 were asleep. It was the genuine
  Windows program: signed "CN=Microsoft Windows", from
  `C:\WINDOWS\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\`,
  started by Windows' own service host. [M-11]
- **Ending it helped at once.** Before: processor 48.1 C, total load 20 %.
  Two minutes after ending it: 41.1 C and 2 %. [M-12]
- **Nothing in the settings explained it.** Clipboard history, cloud
  clipboard, the touch keyboard icon and voice typing were at Windows'
  defaults; typing suggestions for the physical keyboard were off.
- **What set it off, on this machine: a screen-capture tool.** A fresh copy
  that had been idle for three minutes, at 1.6 seconds of processor time in
  total, was spinning within 15 seconds of one screenshot taken by the Claude
  Code "computer use" tool, which hides certain windows (TextInputHost's among
  them) while it captures the screen. This was reproduced on purpose twice
  that evening (18:42 and 18:57), and seen once before that (18:35), when an
  idle copy started spinning right after a screenshot. [M-11, M-13]
- **The guard, run for real by Task Scheduler,** found a stuck copy at 97.1 %
  of one core over 60 seconds, ended it, and logged it. No window appeared.
  [M-13]

Nothing was already in place before this module: there was no guard task.

---

## What this will not do

- **It does not stop the fault happening.** It ends a stuck copy after the
  fact: at worst about 11 minutes later (up to 10 minutes until the next run,
  plus the one-minute measurement). If the fault comes back, the guard ends it
  again.
- **It does not know why the loop starts.** What sets it off here is a
  screen-capture tool; other triggers may exist and are not known.
- **It does not touch anything but TextInputHost.** Other programs that get
  stuck are out of its reach.
- **It only works while you are signed in.** The task runs in your session; if
  nobody is signed in, there is no TextInputHost of yours to watch.
- **It makes no general speed claim.** When TextInputHost is behaving, the
  guard changes nothing and saves nothing.

---

## What might break

- **A panel closes while you use it.** If TextInputHost were ending at the
  exact moment you use the emoji panel or clipboard history, that panel would
  close, and would open again (from a fresh copy) the next time you press the
  keys. For that, TextInputHost must have used 90 % of a core for a full
  minute. Idle copies measured here used under 2 %; heavy use of the panels
  (for example long voice typing) was not measured, so how close normal use
  can come to 90 % is not known.
- **A different threshold is your choice.** Lower thresholds (the install
  accepts 50 to 100 %) end it sooner and make a false alarm more likely.
- **Moving this folder breaks the task.** The task runs
  `Invoke-TextInputGuard.ps1` from this folder by its full path. If you move or
  rename the folder, run **6** first, move it, then run **4** again. The check
  (**1**) warns if the task points somewhere else.
- **Antivirus products** may dislike a script that ends processes. The script
  only ends `TextInputHost.exe` from the Windows `SystemApps` folder, in your
  own session.

---

## Technical detail

### The one thing this module changes

| Item | Value |
|---|---|
| Scheduled task | `\W11T\TextInputHost guard` (its own task folder) |
| Principal | the signed-in user, `LogonType Interactive`, `RunLevel Limited`: "Tasks run by using the least-privileged user account (LUA)." [R-148] |
| Trigger | once, one minute after install, repeating every 10 minutes ("The task will run, wait for the time interval specified, and then run again." [R-149]); no repetition duration, which Task Scheduler stores as open-ended (engineering observation: the exported task has an `Interval` and no `Duration`) |
| Action | `%SystemRoot%\System32\conhost.exe --headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "<this folder>\Invoke-TextInputGuard.ps1" -ThresholdPercent 90 -WindowSeconds 60 -Quiet` |
| Settings | runs on battery, not stopped on battery, 5-minute time limit, a second run is not started while one is running, a missed run starts when possible |

`conhost.exe --headless` is what keeps a console window from appearing every
10 minutes. It is not in the documentation corpus this project holds; it is an
engineering observation on build 26200, where every process the task started
had no window (`MainWindowHandle` 0). Check it by running the task from Task
Scheduler and watching the screen.

### How the guard measures

For every `TextInputHost.exe` in the current session it reads
`Process.TotalProcessorTime` (processor time used since the program started),
waits the window (60 s), and reads it again. The difference divided by the
window is the share of one core it used. That is a cumulative counter read
twice and differenced, never a single instantaneous sample.

It ends a copy only if all of these hold:

- its path is `TextInputHost.exe` under `%SystemRoot%\SystemApps\` (a program of
  the same name elsewhere is never ended);
- it is in the current user's session;
- it existed for the whole window (a copy started mid-window is not judged);
- the window really lasted at least 90 % of its length;
- it used at least the threshold (default 90 % of one core).

A value that cannot be read (for example a process that ended during the
window) makes the verdict "unknown", and "unknown" never ends anything.

### Backups and the undo

The state is one record: whether the task exists and, if so, its full
definition (the XML Task Scheduler exports). It is written to
`backups\state_<date>_<time>[_tag].json` before any change, and read back to
prove it. The first install also writes `backups\original-state.json` once;
nothing overwrites it. The undo snapshots the current state first
(`_~prerestore`), then removes the task or registers the recorded definition.

A recorded definition is only registered if it is exactly what this module
creates: one action, `conhost.exe` running this folder's
`Invoke-TextInputGuard.ps1` with the guard's own arguments and in-range
settings, with limited rights, for the current account. Anything else in a
backup file is refused.

### Exit codes

| Script | Codes |
|---|---|
| `Install-TextInputGuard.ps1` | 0 installed or previewed; 3 no verified backup, nothing changed; 4 already installed with these settings, no backup written; 5 installed but the read-back found a problem |
| `Restore-TextInputGuard.ps1` | 0 restored, previewed or already as recorded; 3 the pre-restore snapshot failed, nothing changed; 4 nothing to restore or an unusable backup; 5 failed or refused |
| `Invoke-TextInputGuard.ps1` | 0 nothing stuck (or preview); 10 a stuck copy was ended; 1 a stuck copy could not be ended |
| `Test-RoundTrip.ps1` | 0 PASS; 1 FAIL; 2 INCONCLUSIVE; 4 refused |
| `Test-SafetyLogic.ps1` | 0 all passed; 1 any failed |

Run from the scheduled task, the guard's exit code does not reach Task
Scheduler: the task runs `conhost.exe`, which reports 0. The record of what the
guard did is `guard-log.txt`, and **1** reads it.

### Files

| File | Role |
|---|---|
| `_Common.ps1` | the settings table (one row: the task), state, backups, the checks, the decision rule |
| `Test-TextInputGuard.ps1` | read-only check |
| `Install-TextInputGuard.ps1` | the install |
| `Restore-TextInputGuard.ps1` | the undo |
| `Invoke-TextInputGuard.ps1` | the guard the task runs |
| `Test-SafetyLogic.ps1` | self-test of the decision logic (62 checks) |
| `Test-RoundTrip.ps1` | proof that the undo works |
| `guard-log.txt` | written by the guard; one line per copy ended or failure; kept out of version control |
| `backups\` | state files; kept out of version control |

---

## Errors worth recording

- **"It held a core since 06:37" was wrong.** The first report to the owner
  said the stuck copy had held one core at 99 % since it started at 06:37. It
  had been measured at 99 % only once, at 18:21. Its four hours of processor
  time over about 11.7 hours mean it was spinning roughly a third of the time.
  The mistake was believable because a steady 99 % reading and a large total
  looked like one fact; they are two.
- **"Windows is doing this by itself" was incomplete.** The first explanation
  blamed a Windows fault alone. Testing showed that on this machine a
  screenshot by the Claude Code computer-use tool starts the loop within 15 to
  30 seconds: twice on purpose, and once seen before the test. The loop is
  Windows'; the trigger was the tool used to investigate it.
- **The guard measured over 3 milliseconds instead of 60 seconds.** In
  Windows PowerShell 5.1 a function that returns one object does not return a
  list, and that object has no dependable `.Count`. The guard's "is anything
  running?" test came out as no, the one-minute wait was skipped, and every
  run measured nothing. It was safe (an unmeasurable copy is never ended) but
  useless. The self-test missed it because it tested the decision rule with
  numbers, not the measuring; running the real scheduled task found it. The
  fix wraps the result in `@()`, and a measurement shorter than 90 % of its
  window now counts as unknown. The self-test gained a check that the
  measurement really waits.
- **`$null -as [double]` is 0.** An unreadable processor-time counter read as
  "0 %, idle", and a missing process age as "just started". Both happened to
  leave the process alone, but for the wrong reason. The self-test caught it;
  missing values are now tested before conversion.
- **Task Scheduler's result code is always 0.** The first version of the
  check (**1**) read the task's last result and would have said "nothing was
  stuck" after a run that ended a stuck copy. It now points at the log.

---

## Grounding

| Tag | Supports | Source | Line | Quote |
|---|---|---|---|---|
| R-147 | The touch keyboard is backed by a Windows service, which Microsoft's own service guidance lists | [Guidance on configuring system services - Windows IoT Enterprise](https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/optimize/services) | 283 | Enables Touch Keyboard and Handwriting Panel pen and ink functionality. |
| R-148 | The task runs with limited rights | [New-ScheduledTaskPrincipal](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal?view=windowsserver2016-ps) | 205 | Tasks run by using the least-privileged user account (LUA). |
| R-149 | The task repeats at a fixed interval | [New-ScheduledTaskTrigger](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasktrigger?view=windowsserver2016-ps) | 299 | The task will run, wait for the time interval specified, and then run again. |
| M-11 | The stuck copies, the trigger test | `evidence/2026-09-28_textinputhost/trigger-test.txt` (kept private) | - | - |
| M-12 | Temperature and load before and after ending it | `evidence/2026-09-28_textinputhost/after-ending-first-copy.txt` (kept private) | - | - |
| M-13 | The real scheduled task ending a stuck copy | `evidence/2026-09-28_textinputhost/scheduled-task-run.txt` (kept private) | - | - |

The three links were checked on 2026-09-28: each answered 200, and a made-up
page on the same site answered 404. The line numbers refer to the offline copy
of the documentation this project verifies against, and each quote was checked
word for word against it. The R-147 page contains stray carriage returns, so
tools disagree about its line numbers: 283 counting line feeds (as grep and
GitHub do), 518 in PowerShell.

R-147 names the service `TabletInputService`. On build 26200 the service
behind TextInputHost is `TextInputManagementService`; `TabletInputService` does
not exist on this machine. That the two play the same role is engineering
observation.

---

## Honest limits

- **What TextInputHost does, and why it loops, is not documented** in the
  Microsoft documentation this project holds: a search of the whole offline
  copy for `TextInputHost` and for `TextInputManagementService` found nothing.
  Everything this README says about the program's behaviour is measured on one
  machine [M-11, M-12, M-13], and you can check it with **1** and **2**.
- **The trigger is proved for one tool on one machine.** Whether other
  screen-capture or accessibility tools set it off, and whether other builds
  of Windows behave the same, is not known.
- **No performance claim beyond the fault.** The guard frees a core only when
  TextInputHost is stuck. Processor time is not power draw, and no figure here
  converts one into the other.
- **The shared measuring engine is not used.** MODULE-STANDARD R15.2 asks
  measurement to use `READ-ONLY-diagnostics\_MeasureLib.ps1`. That folder is not
  published, and this guard has to run on any computer it is copied to, so it
  carries its own measurement. It follows R15.3 (a cumulative counter read
  twice and differenced) and states its window.
- **One machine, one account.** Built and tested on Windows 11 Home build
  26200. Task Scheduler behaves the same on other editions, as far as this
  project knows; that is not tested.

---

## Status

Installed on the machine this project was built for on 2026-09-28, with the
defaults. Self-test: 62 checks passed. Round trip: PASS (1 item moved and came
back). Undo with no arguments, `-Original` after two installs, `-Backup` of a
pre-restore snapshot, `-List`, `-WhatIf` and the empty-folder message were all
run. The real scheduled task ended a stuck copy. No adversarial audit yet.
