# HOWTO: TextInputHost guard

## The shortest useful sequence

1. Look: `1 - Check what is on now.cmd`
2. Preview: `3 - Preview the install (safe).cmd`
3. Install: `4 - Install the guard.cmd`
4. Undo, whenever you want: `6 - UNDO (remove the guard).cmd`

Or from PowerShell, in this folder:

```
powershell -ExecutionPolicy Bypass -File .\Test-TextInputGuard.ps1
powershell -ExecutionPolicy Bypass -File .\Install-TextInputGuard.ps1 -WhatIf
powershell -ExecutionPolicy Bypass -File .\Install-TextInputGuard.ps1
powershell -ExecutionPolicy Bypass -File .\Restore-TextInputGuard.ps1
```

No script in this module asks for administrator rights.

---

## Test-TextInputGuard.ps1 - look (changes nothing)

Shows every TextInputHost in your session (where it runs from, when it started,
processor time so far, and how much of one core it is using now), whether the
guard task is installed with what settings, when it last ran and runs next, and
the last lines of `guard-log.txt`. Read-only.

| Parameter | Type | Default | What it does |
|---|---|---|---|
| `-MeasureSeconds` | whole number, 0-120 | 10 | how long to measure current use; 0 skips it |
| `-Json` | switch | off | also write `backups\snapshot_<date>.json` (a snapshot, never offered by the undo) |

**The full picture:**

```
powershell -ExecutionPolicy Bypass -File .\Test-TextInputGuard.ps1
```

prints, for example:

```
  TextInputHost (the touch keyboard, emoji panel and clipboard history)
    measuring for 10 s (reading its processor-time counter twice) ...
    pid 17384
      runs from              C:\WINDOWS\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\TextInputHost.exe
      the Windows one        yes
      using now              0 % of one core   (idle, as it should be)

  The guard (scheduled task)
    installed              yes
    runs                   every 10 minutes
    ends it at             90 % of one core for 60 s
    last ran               9/28/2026 6:59:37 PM  (ran; what it did is in the log below)

  Guard log (one line each time it ends a stuck copy or fails)
    1 line(s) in total; the last 1:
      2026-09-28 19:00:37  ended TextInputHost pid 17384: 97.1 % of one core for 60 s (threshold 90 %)
```

A stuck copy is marked `<- STUCK: this is the fault the guard ends`.

**Without waiting:** `-MeasureSeconds 0` prints the same, with "using now: not measured".

**With a snapshot:** `-Json` adds `snapshot written: ...\backups\snapshot_2026-09-28_19-10-00.json`.

Nothing to do is not a case here: it always reports. If TextInputHost is not
running it says so ("not running in your session").

---

## Install-TextInputGuard.ps1 - install

Creates (or replaces) the scheduled task `\W11T\TextInputHost guard`. Backs up
first; the first run also writes `backups\original-state.json`, once.

| Parameter | Type | Default | What it does |
|---|---|---|---|
| `-IntervalMinutes` | 5-60 | 10 | how often the guard runs |
| `-ThresholdPercent` | 50-100 | 90 | how much of one core counts as stuck |
| `-WindowSeconds` | 30-120 | 60 | how long each run measures |
| `-Tag` | text | none | a label in the backup file name (letters, digits, `-`, `_`, `.`) |
| `-WhatIf` | switch | off | preview; change nothing |

**Preview:**

```
powershell -ExecutionPolicy Bypass -File .\Install-TextInputGuard.ps1 -WhatIf
```

```
    the task does not exist yet; it will be created
    backup would be written to: ...\modules\10-text-input-guard\backups
    1 change WOULD be made (the task created or replaced). Nothing was changed.
```

**Install with the defaults:**

```
powershell -ExecutionPolicy Bypass -File .\Install-TextInputGuard.ps1
```

```
    backup written           : ...\backups\state_2026-09-28_18-56-28.json
    verification (read back from Task Scheduler, not from what we just sent):
      installed: every 10 min, ends TextInputHost at 90 % of one core for 60 s,
      normal rights, no window. The first run is about one minute from now.
    changed: 1   already as wanted: 0   failed: 0

  TO UNDO EVERYTHING:
     powershell -ExecutionPolicy Bypass -File .\Restore-TextInputGuard.ps1
```

**Change the settings** (run it again with other values):

```
powershell -ExecutionPolicy Bypass -File .\Install-TextInputGuard.ps1 -IntervalMinutes 5 -ThresholdPercent 80
```

```
    the task exists with other settings (10 min, 90 %, 60 s); it will be replaced
      installed: every 5 min, ends TextInputHost at 80 % of one core for 60 s,
```

**With a tag:** `-Tag before-holiday` gives `state_<date>_before-holiday.json`.

**Nothing to do:** if the guard is already installed with exactly these
settings and enabled, it says so, writes no backup, and exits 4.

---

## Restore-TextInputGuard.ps1 - undo

With no arguments it puts back the state from before the last install
(normally: the task removed). It snapshots the current state first
(`state_<date>_~prerestore.json`), so the undo can be undone.

| Parameter | Type | Default | What it does |
|---|---|---|---|
| *(none)* | | | restore the newest `state_*.json` (never a pre-restore snapshot) |
| `-Original` | switch | off | restore `backups\original-state.json`; if it does not exist, say so and stop |
| `-Backup` | text | none | restore one file: a full path, or a file name inside `backups\` |
| `-List` | switch | off | show every restore point and what it records; change nothing |
| `-WhatIf` | switch | off | say what would be put back; change nothing |

**Undo the last install:**

```
powershell -ExecutionPolicy Bypass -File .\Restore-TextInputGuard.ps1
```

```
    restoring from : state_2026-09-28_18-56-28.json
    it records     : no guard installed
    now            : guard installed: every 10 min, 90 % for 60 s
    snapshot of now: state_2026-09-28_18-56-34_~prerestore.json
    task: removed (it did not exist in that backup)
    now : no guard installed   (read back from Task Scheduler)
    restored: 1   already as recorded: 0   failed: 0
```

**Back to the original:** `-Original` (same output, "restoring from :
original-state.json").

**List:**

```
powershell -ExecutionPolicy Bypass -File .\Restore-TextInputGuard.ps1 -List
```

```
    original-state.json (use -Original)          no guard installed
    state_2026-09-28_18-56-30.json               guard installed: every 10 min, 90 % for 60 s
    state_2026-09-28_18-56-28.json               no guard installed
```

**One restore point, including undoing an undo:**

```
powershell -ExecutionPolicy Bypass -File .\Restore-TextInputGuard.ps1 -Backup state_2026-09-28_18-56-34_~prerestore.json
```

```
    it records     : guard installed: every 5 min, 80 % for 60 s
    task: put back as recorded
```

**Preview:** `-WhatIf` prints `1 change WOULD be made. Nothing was changed.`

**Nothing to restore:** with no backups it prints where it looked, that the
install has not been run from this folder, and exits 4. A backup naming a task
that this module would not create is refused: `REFUSED: the task recorded in
this backup is not one this module creates (...)`, exit 5.

---

## Invoke-TextInputGuard.ps1 - the guard

What the scheduled task runs. You can run it by hand.

| Parameter | Type | Default | What it does |
|---|---|---|---|
| `-ThresholdPercent` | 50-100 | 90 | how much of one core counts as stuck |
| `-WindowSeconds` | 10-300 | 60 | how long to measure |
| `-Quiet` | switch | off | print nothing; write to `guard-log.txt` only when a copy is ended or ending fails |
| `-WhatIf` | switch | off | measure and report; end nothing, write nothing |

**Check without ending anything** (launcher 2):

```
powershell -ExecutionPolicy Bypass -File .\Invoke-TextInputGuard.ps1 -WhatIf
```

```
    measuring 1 process(es) for 60 s ...
    pid 17384    94.9 % of one core   STUCK
What if: Performing the operation "end it (Windows starts a fresh copy when needed)" on target "TextInputHost pid 17384".
    ended: 0   failed: 0   measured: 1
    PREVIEW ONLY - nothing was ended and nothing was written.
```

**End a stuck copy now** (launcher 9): without `-WhatIf`, the same, then
`ended. Windows starts a fresh copy when it is needed.` and a line in the log.

**Shorter, stricter:** `-WindowSeconds 20 -ThresholdPercent 80`.

**As the task runs it:** `-Quiet` prints nothing.

**Nothing to do:** no TextInputHost in your session: it says so and exits 0.
A healthy copy: `fine`, exit 0.

Exit codes: 0 nothing stuck (or preview), 10 a stuck copy was ended, 1 ending
failed. From the scheduled task they do not reach Task Scheduler (it runs
`conhost.exe`, which reports 0); read the log instead.

---

## Test-SafetyLogic.ps1 - self-test (changes nothing)

62 checks of the decision rule, the process filter, the backup checks and the
task checks, with inputs normal use never produces. No parameters.

```
powershell -ExecutionPolicy Bypass -File .\Test-SafetyLogic.ps1
```

```
    checks passed : 62
    checks failed : 0
    All safety checks passed.
```

Exit 0 only if every check passed; a check that throws counts as failed. If no
TextInputHost is running, the three measurement checks are skipped and said to
be skipped, not counted as passed.

---

## Test-RoundTrip.ps1 - prove the undo works

Installs for real, undoes with no arguments, and compares by what the task
does. Asks you to type YES.

| Parameter | Type | Default | What it does |
|---|---|---|---|
| `-Force` | switch | off | do not ask for YES |

```
powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1 -Force
```

```
    [A] reading the state before anything happens ...
    [B] installing for real ...
        items that changed: 1
    [C] undoing (Restore-TextInputGuard.ps1 with no arguments) ...
    PASS - everything came back to exactly where it started.
    cleaned up 2 backup file(s) this test created
```

If the guard is already installed with the default settings, the install has
nothing to do, and the test stops before its undo: `INCONCLUSIVE`, exit 2,
nothing touched. Run `7 - UNDO back to the original` first for a real test.
