# How to use the visual-effects module

This module turns off the animations, fades, shadows and frosted-glass effects
that Windows 11 draws constantly, and it can put every one of them back.

It is written in two tracks throughout. **In plain terms** explains what the
thing does to your machine and to you. **In technical terms** gives the exact
mechanism, registry path, API code and failure mode. Neither is a summary of the
other; they are the same information in two languages, and you are welcome to
read only the one that suits you.

---


> **Status note (2026-08-26).** This module has been applied on the machine it was
> written for, after its rollback was proved by `Test-RoundTrip.ps1` (20 settings
> restored, 0 skipped, 0 failed). The apply and undo paths were also hardened
> following two adversarial audits - see the "What the safety audit changed"
> section of `README.md`. In particular: a backup that cannot be written now
> **aborts** the apply instead of proceeding, the undo no longer re-applies the
> tweaks when run twice, and the undo reports `restored / skipped / failed`
> counts rather than a single number.

## Before you start

### What this module actually changes

**In plain terms.** Windows draws a lot of small decorative movement: menus that
slide open, tooltips that fade in, a shadow under every window, a blurred
translucent look on the Start menu and taskbar, a preview of the desktop when
you brush the corner of the screen. All of it is redrawn by your graphics
hardware, many times a second. On a fast machine you barely notice the cost. On
an older or cheaper machine, or on a laptop running on battery, the cost is
visible: the interface feels sluggish, the fan runs, the battery drains.

This module switches that decoration off. It does not change how Windows works,
what it can do, or what your files look like. Windows becomes plainer and
quicker to respond. Everything still functions.

**In technical terms.** Windows exposes visual-effect state across four
independent surfaces, and the built-in *Performance Options → Adjust for best
performance* control reaches only the first of them:

| Layer | What lives there | How it is reached |
|---|---|---|
| **Legacy** | Classic USER32 effects: menu and tooltip animation, fades, window and cursor drop shadows, gradient title bars, full-window drag, menu show delay | `SystemParametersInfo` SPI codes |
| **Modern** | Animation inside modern (WinRT/XAML) apps, and inside web-based apps, because the same flag surfaces to Chromium as `prefers-reduced-motion`; plus acrylic/Mica translucency | `SPI_SETCLIENTAREAANIMATION`; `HKCU\...\Themes\Personalize\EnableTransparency` |
| **Shell** | Taskbar button animation, translucent list-view selection rectangle, desktop icon label shadows, and the flag that makes the Performance Options dialog report "Custom" | `HKCU\...\Explorer\Advanced`, `HKCU\...\Explorer\VisualEffects` |
| **DWM** | Aero Peek desktop preview | `HKCU\Software\Microsoft\Windows\DWM\EnableAeroPeek` |

Desktop composition itself is not switchable. It has been permanently on since
Windows 8 and `DwmEnableComposition` cannot disable it (R-71/R-72/R-73). What
this module reduces is the amount of work composition is asked to do, not
whether composition happens.

### What it does not require

**In plain terms.** No administrator password. Nothing here changes the machine
for other people who use it, and nothing here changes Windows itself. Every
setting is one of *your* personal preferences — the same category as your
wallpaper. If you have a second user account on this PC, its settings are
untouched.

**In technical terms.** Every write is per-user: `HKCU` registry values and
per-user `SystemParametersInfo` calls with
`SPIF_UPDATEINIFILE | SPIF_SENDCHANGE` (`0x1 -bor 0x2`), which persists the
value to the user profile and broadcasts `WM_SETTINGCHANGE` so running
processes re-read it without a sign-out. No `HKLM` write, no service change, no
elevation request. The only `HKLM` access anywhere in the module is a read:
`Get-VfxState` reads `CurrentBuildNumber` from
`HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion` to record the build number
in each backup. If a UAC prompt appears while running these scripts, something
other than this module produced it.

### The safety design, and why it is built this way

**In plain terms.** Three things protect you.

1. Every time the disable script runs, it first writes down the current value of
   all 20 settings into a dated file in the `backups` folder.
2. The **first** time it ever runs, it additionally writes `original-state.json`
   — a record of how your machine was before this project touched anything.
   That file is written once and never written over. This matters because of a
   classic trap: if you run a tweaking script twice, the second run often "backs
   up" the already-changed state, and the way home is quietly lost. This module
   cannot do that to you.
3. The restore script takes its own backup *before* it undoes anything. So
   undoing is itself undoable. If you restore and decide you preferred the fast
   version, the state you just left is on disk.

**In technical terms.** `Save-VfxBackup` in `_Common.ps1` serialises the full
`Get-VfxState` object (SPI values, registry values, WinRT `UISettings` readings,
host, user, OS build, UTC timestamp) to
`backups\state_<yyyy-MM-dd_HH-mm-ss>[_<Tag>].json`, then writes
`backups\original-state.json` only when that path does not already exist. The
restore path calls the same function with `-Tag pre-restore` before applying,
so a restore leaves a `state_<stamp>_pre-restore.json` behind. Restore also
*deletes* registry values that were `null` or empty-string at capture time,
rather than setting them to zero, so a rollback leaves no residue. A recorded
value of `0` is not treated as absent — it is written back as `0`.

Files are written with `Set-Content -Encoding UTF8`, which under Windows
PowerShell 5.1 means UTF-8 **with** a byte-order mark. The scripts read them
back with `Get-Content -Encoding UTF8`, so the BOM is handled; if you process
these files with other tools, expect the BOM.

### Honesty about what is and is not vendor-documented

**In plain terms.** Some of what this module relies on comes straight from
Microsoft's own published documentation. Some of it comes from reading the
system and testing it. The manual tells you which is which, because a claim
backed by a vendor document and a claim backed by "we tried it and watched what
happened" are not the same strength of claim.

**In technical terms.**

Vendor-documented, quotable, and in this project's offline corpus:

- Acrylic translucency is expensive. R-63, `acrylic.md` line 70: rendering
  acrylic surfaces "is GPU-intensive, which can increase device power
  consumption and shorten battery life", and acrylic "effects are automatically
  disabled when a device enters Battery Saver mode".
- R-66, `composition-tailoring.md` line 114 classes Gaussian Blur, Shadow Mask,
  `BackDropBrush`, `HostBackDropBrush` and Layer Visual as "high performance
  impact ... not recommended for low end devices".
- R-69/R-70, `client-area-animation.md` lines 11 and 13: the client-area
  animation parameter "indicates whether the user wants to disable animations in
  UI elements", and applications use `SPI_GETCLIENTAREAANIMATION` /
  `SPI_SETCLIENTAREAANIMATION` with `SystemParametersInfo` "to turn client area
  animations on or off".
- R-71/R-72/R-73: DWM composition is always on from Windows 8 onwards and
  `DwmEnableComposition` cannot disable it.
- R-67/R-68: applications should respect `UISettings.AnimationsEnabled` and
  `UISettings.AdvancedEffectsEnabled`.

**Not** vendor-cited here: the *calling conventions* of `SystemParametersInfo`.
The Win32 API reference pages are not part of this project's offline Microsoft
corpus, so the three-way convention split documented at the top of `_Common.ps1`
—

- `SPI_GET*`: `pvParam` is a pointer to the value,
- `SPI_SET*` in the UI-effects family: `pvParam` *is* the value, cast to `PVOID`,
- `SPI_SETDRAGFULLWINDOWS` and `SPI_SETMENUSHOWDELAY`: the value travels in
  `uiParam`, `pvParam` is `NULL`

— is presented as **engineering observation, not vendor fact**. It is
falsifiable and you can falsify it yourself: run `Test-VisualEffects.ps1`,
apply, run it again. Getting the convention wrong produces a call that returns
success while doing nothing, which is exactly why the module verifies by
re-reading rather than by trusting the return value.

Also not vendor-cited: the claim that the client-area animation flag is what
Chromium surfaces to web content as `prefers-reduced-motion`. What is
vendor-documented (R-69/R-70) is that the flag exists and that it indicates
whether the user wants animations in UI elements disabled. The
`prefers-reduced-motion` projection is engineering observation.

### Where you are

**In plain terms.** All the scripts live in one folder and must be run from
that folder, because they load a shared file from alongside themselves.

If you have not used PowerShell before:

1. Press the Windows key, type `powershell`, and open **Windows PowerShell**.
   You do **not** need "Run as administrator" — this module never asks for it.
2. A blue or black window opens with a blinking cursor. You type commands there
   and press Enter. Right-click pastes.
3. Move into the module folder with `cd` followed by the folder path. If you are
   unsure of the path, type `cd ` (with the space), then drag the module folder
   from File Explorer onto the PowerShell window — it fills in the path for you
   — then press Enter.

Do **not** double-click a `.ps1` file in File Explorer. Windows opens `.ps1`
files in Notepad by default; it will not run them.

The path below is where this module lives on the machine it was written on.
Substitute wherever you put it. If your path contains spaces, wrap it in
double quotes.

```powershell
cd C:\Users\Username\Documents\Windows.11.tweaks.optimisation\modules\01-visual-effects
```

If you get `Cannot find path ... because it does not exist`, the folder is
somewhere else; use the drag-and-drop trick above.

**In technical terms.** Each script resolves `_Common.ps1` via
`Split-Path -Parent $MyInvocation.MyCommand.Path`, and the backup directory as
`<script dir>\backups`. Because both are derived from the script's own location,
the scripts work when invoked by full path from any working directory — but
`-Backup` with a bare filename is resolved against your *current* directory
first (see that parameter below), so running from the module directory is the
supported and least surprising form. The examples in this manual assume it.

Use `powershell.exe` (Windows PowerShell 5.1), not `pwsh` (PowerShell 7). See
*Troubleshooting* for what degrades under PowerShell 7.

### The state of the machine this was built on

Measured 2026-08-26, on the development machine only. Your machine will differ;
run `Test-VisualEffects.ps1` to see yours.

- Windows 11 Home, build 26200, Intel i7-1255U, 63.7 GB RAM, integrated graphics.
- **Already off**: modern app animations (`UISettings.AnimationsEnabled = False`)
  and frosted glass (`AdvancedEffectsEnabled = False`, `EnableTransparency = 0`).
- **Still on**: Gradient window captions, Menu fade, Tooltip fade, Drop shadow
  (windows), UI effects (master), Drag full windows.
- **Shell/DWM to change**: `TaskbarAnimations=1`, `ListviewAlphaSelect=1`,
  `ListviewShadow=1`, `EnableAeroPeek=1`, `VisualFXSetting` unset (the script
  sets it to 3, meaning "Custom").
- Menu show delay 400 ms; the script sets it to 0.
- `dwm.exe` about 178 MB resident; 18 web-app processes using about 917 MB
  between them, each animating its own interface.
- A dry run reported 11 real changes pending.

That figure of 11 is the recorded measurement from that machine on that day. It
is the number of pending change lines, which depends entirely on how much was
already switched off; it is not a target and not a number to check yours
against. This machine was already partly optimised before measurement. A default
installation will have considerably more still switched on, and a correspondingly
higher count.

---

## The five scripts at a glance

**In plain terms.**

| Script | What it does | Does it change anything? |
|---|---|---|
| `Test-VisualEffects.ps1` | Shows you the current setting of everything, across all four layers, plus how much memory the window manager and web apps are using | No. Never. |
| `Disable-VisualEffects.ps1` | Backs up, then switches the effects off | Yes — unless you add `-WhatIf` |
| `Restore-VisualEffects.ps1` | Puts everything back from a backup | Yes — unless you add `-WhatIf` |
| `Test-RoundTrip.ps1` | Proves the undo works: changes the machine, changes it back, and compares | Yes — temporarily. It asks first |
| `Measure-VisualEffects.ps1` | Measures the machine in both states and reports what the change is actually worth | Yes — repeatedly, on purpose. It asks first |

There is a sixth file, `_Common.ps1`. It is not a script you run; it is the
shared code the others load. Running it directly does nothing.

`Measure-VisualEffects.ps1` also loads
`..\..\READ-ONLY-diagnostics\_MeasureLib.ps1`. That is the only cross-folder
dependency in the module, and it is deliberate: the measuring code is shared with
every other module rather than copied into each one. If the file is missing the
script says exactly which file and where, and does nothing else.

**In technical terms.** All four dot-source `_Common.ps1`, so all four read and
write the same 20 settings through the same code path; the settings table cannot
drift between the reader, the writer and the roll-back. `_Common.ps1` executes
nothing on its own beyond an `Add-Type` guarded by
`if (-not ('VfxNative.User32' -as [type]))`, and is not intended to be run
directly.

`Test-VisualEffects.ps1` is declared `[CmdletBinding()]`; the other three are
`[CmdletBinding(SupportsShouldProcess = $true)]` (`Test-RoundTrip.ps1` adds
`ConfirmImpact = 'High'`), which is where `-WhatIf` and `-Confirm` come from.
All four therefore accept the PowerShell common parameters (`-Verbose`,
`-Debug`, `-ErrorAction`, `-ErrorVariable`, `-OutVariable`, and so on); those
are standard PowerShell behaviour, not module features. None of the four scripts
calls `Write-Verbose`, `Write-Debug` or `Write-Warning` itself — all their
output goes to the information/host stream via `Write-Host`, with `Write-Error`
used for two failure cases in the restore script. Passing `-Verbose` may still
produce output, because it propagates `$VerbosePreference` to the registry
provider cmdlets the scripts call.

Because output is `Write-Host`, it cannot be captured by simple assignment or
piped into `Out-File`; redirect the information stream (`6>`) or all streams
(`*>`) if you want a transcript, or use `Start-Transcript`.

`_Common.ps1` deliberately does **not** set `Set-StrictMode`. Restore paths read
objects deserialised from JSON where a missing property must degrade gracefully;
a rollback script that throws on an unexpected field is worse than useless.

All four scripts set `$ErrorActionPreference = 'Continue'`. This matters in one
place: see `-Tag` below.

---

## Recommended first session

**In plain terms.** Do it in this order. Nothing is changed until step 3, and
step 5 undoes step 3 completely.

**In technical terms.** The sequence is: capture, preview, apply with automatic
backup, verify by re-read, and demonstrate the rollback so you know it works
before you need it.

### Step 1 — Move into the module folder

Open Windows PowerShell (Windows key, type `powershell`, Enter — no
administrator rights needed), then:

```powershell
cd C:\Users\Username\Documents\Windows.11.tweaks.optimisation\modules\01-visual-effects
```

The prompt should now end with `01-visual-effects>`. If it does not, the `cd`
did not work — check the path.

### Step 2 — See what your machine is doing now

Type this on one line and press Enter. The leading `.\` means "in this folder"
and is required.

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-VisualEffects.ps1
```

Expected output: a report headed *Visual effects - current state* with your
computer name, Windows build and username, then four blocks — the
`SystemParametersInfo` effects with `ON` or `off` beside each (and
`<- costs cycles` beside the ones that are on), the two WinRT readings, the
shell and compositor registry values, and a short summary listing what is still
on, the menu delay in milliseconds, and the memory used by `dwm.exe` and by any
WebView2 processes. Nothing is written.

When it finishes you are returned to the prompt. Nothing needs saving and
nothing needs closing.

### Step 3 — Preview exactly what would change

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -WhatIf
```

Expected output: the header, then `backup would be written to:` followed by the
backups path, then a `What if:` line for every single change that a real run
would make — one per effect, one for drag-full-windows, one for the menu delay,
one for the master gate, one per registry value. No file is created, no setting
is touched, and the `backups` folder is not created.

Three things to expect and not be alarmed by:

- The closing counter line will read `changed: 0   already as wanted: N
  failed: 0`. The `changed` and `failed` counters only increment inside the
  blocks that a real run executes, so under `-WhatIf` they stay at zero. The
  `already as wanted` counter *does* increment, because it is counted outside
  those blocks: `N` is the number of settings in the requested layers that are
  already at their target value. Under `-WhatIf` the `What if:` lines are the
  preview, not the counters.
- The verification block is skipped entirely, because there is nothing yet to
  verify.
- The closing `TO UNDO EVERYTHING:` reminder is printed anyway. It is printed
  unconditionally; under `-WhatIf` there is nothing to undo.

### Step 4 — Apply it, with a label on the backup

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -Tag first-run -RestartExplorer
```

Expected output: `backup written           : ...\backups\state_<timestamp>_first-run.json`,
followed by `pristine state preserved : ...\backups\original-state.json` and the
note that that file is written once and never overwritten. Then, under a heading
`effects:`, a line per setting reading `DISABLED`, `already off` or (for the menu
delay) `SET` / `already 0` / `skipped`. Then a heading `shell / compositor:` and
a line per registry value reading `SET` or `already set`. Then `desktop shell
restarted` — your taskbar will blink and any open File Explorer windows will
close. Then the verification block, which re-reads every value from the API
rather than trusting what was just written, and should say `every targeted
effect reads back as off`. Finally the counters, and a reminder of the undo
command.

If you would rather not have Explorer restart under you, drop `-RestartExplorer`
and sign out and back in later instead.

### Step 5 — Verify independently

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-VisualEffects.ps1
```

Expected output: the same report as step 2, now showing `off` where it showed
`ON`, `0 ms` for the menu delay, and `effects still on   : none`. This is a
separate program reading the system fresh; it is not repeating what the disable
script claimed.

### Step 6 — Prove the undo works, before you need it

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -WhatIf
```

Expected output: the backup it would restore from (at this point,
`state_<timestamp>_first-run.json` from step 4), its capture time, and a line
per setting showing the value it would put back — including any line reading
`removed (was not set originally)`. Nothing changes, and the pre-restore safety
backup is *not* written either, because nothing is being undone.

One wrinkle to expect, because it is genuinely confusing: those per-setting
lines are **not** prefixed with `What if:` and they are worded in the past
tense, exactly as a real restore words them. Only the final line distinguishes
the two — under `-WhatIf` it reads `N settings WOULD be restored. Nothing was
changed.` Read that last line to be sure which you got.

### Step 7 — Undo for real, if you want to

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -RestartExplorer
```

Expected output: `current state saved first : ...\state_<stamp>_pre-restore.json`,
then a line per restored setting, then `desktop shell restarted`, then
`N settings restored.` and a suggestion to check with `Test-VisualEffects.ps1`.

### Optional step 8 — Have the machine prove it to you

If you want the round trip demonstrated and checked automatically rather than by
eye, `Test-RoundTrip.ps1` does steps 3 to 7 in one go and compares the result
setting by setting. It changes your machine and changes it back, and it asks for
confirmation first. See its own section below.

---

## Test-VisualEffects.ps1 - every option

**In plain terms.** This one only looks. It cannot change anything, no matter
what you pass it. Run it whenever you want to know where you stand.

**In technical terms.** It calls `Get-VfxState` and formats the result. It reads
every effect through `SystemParametersInfo` rather than inferring from the
registry, because on current builds the modern animation flag has no standalone
registry value — it is packed into an undocumented block of bytes. Asking the API
is the only honest read. It additionally instantiates
`Windows.UI.ViewManagement.UISettings` and reports `AnimationsEnabled` and
`AdvancedEffectsEnabled`, which is what modern and web-based applications
actually consult (R-67/R-68). If the WinRT type cannot be loaded, those two lines
read `unavailable` and everything else still works.

The script has exactly one parameter of its own: `-Json`.

### (no parameters)

**What it does.** Prints the full state report and exits.

**When to use it.** Before anything else; after anything else; any time you want
to confirm what is currently set.

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-VisualEffects.ps1
```

Expected output: five sections.

1. Header with host, Windows build and user.
2. `LAYER 1+2  effects read through SystemParametersInfo` — the twelve effects
   in the shared table (ten legacy effects, the client-area animation flag, and
   the master gate), each shown as `ON `, `off`, or `unreadable` if the API call
   itself failed, followed by `Drag full windows` and `Menu show delay` in
   milliseconds.
3. `LAYER 2  what modern apps actually see (WinRT UISettings - authoritative)` —
   `AnimationsEnabled` and `AdvancedEffectsEnabled`, each `True`, `False
   (already off)`, or `unavailable`.
4. `LAYER 3+4  shell and compositor settings (registry)` — the six registry
   values with their current value or `<not set>`, and a description.
5. A summary giving `effects still on`, `shell/DWM to change`, `menu delay`,
   `dwm.exe` resident memory, and — only if such processes exist — the count and
   total working set of `msedgewebview2` processes.

Two precision points on that last line. It counts **only** `msedgewebview2`
processes, which is the WebView2 runtime that hosts web-based desktop
applications. Chrome, Edge and Electron applications are not counted, even
though they animate their interfaces the same way. And the `dwm.exe` line
assumes a single desktop window manager process; on a machine with more than one
active session the figure will not format sensibly.

### -Json

**What it does — in plain terms.** Does everything above, and also saves the
reading to a dated file in the `backups` folder so you can compare it with a
later reading.

**What it does — in technical terms.** Serialises the same `Get-VfxState` object
to `backups\snapshot_<yyyy-MM-dd_HH-mm-ss>.json` with
`ConvertTo-Json -Depth 6`, UTF-8 with BOM. It creates the `backups` directory if
it does not exist, but it does **not** create `original-state.json` — only
`Save-VfxBackup`, called by the disable and restore scripts, does that. The file
format is identical to a real backup. The distinction is one of intent, not of
shape: a snapshot is a record, whereas the files the disable script writes are
restore points. The path is printed at the end.

**When to use it.** When you want a before-and-after pair you can diff, or when
you are collecting evidence about a machine.

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-VisualEffects.ps1 -Json
```

Expected output: the normal report, then a blank line and
`    snapshot written   : ...\backups\snapshot_2026-08-26_09-14-02.json`.

One consequence worth knowing, because it is not obvious: `Restore-VisualEffects.ps1`
lists every `.json` in `backups`, snapshots included, and if no `state_*.json`
restore point exists it will fall back to restoring the newest file it can find —
which could be a snapshot. See *Troubleshooting* below.

### Common parameters

`Test-VisualEffects.ps1` is `[CmdletBinding()]` without `SupportsShouldProcess`,
so it accepts `-Verbose`, `-Debug`, `-ErrorAction` and the rest, but **not**
`-WhatIf` and **not** `-Confirm`. Passing `-WhatIf` to it is an error. This is
correct: a read-only script has nothing to preview.

---

## Disable-VisualEffects.ps1 - every option

**In plain terms.** This is the one that makes the change. It always backs up
first. Run it with no options and it does everything, which is the usual choice.

**In technical terms.** It has four parameters of its own — `-Layers`,
`-KeepMenuDelay`, `-RestartExplorer`, `-Tag` — plus `-WhatIf` and `-Confirm`
from `SupportsShouldProcess`.

Order of operations: capture `$before` state → write backup (subject to
`ShouldProcess`) → apply SPI effects for the requested layers, skipping the
master gate → **if and only if `Legacy` is requested**, apply drag-full-windows,
then the menu delay, then the master gate → apply registry values for the
requested layers → optionally restart Explorer → re-read and verify → print
counters.

The master gate is set last on purpose. With `SPI_SETUIEFFECTS` off, USER32 skips
the entire legacy family, so setting the individual effects first ensures their
stored values are correct underneath the gate rather than being written through a
closed gate.

Every decision about whether a change is needed is made against the `$before`
snapshot taken at the start, not re-read as the run proceeds.

### -Layers

**What it does — in plain terms.** Chooses which of the four groups of settings
to act on. Leave it out and all four are done. You would narrow it if you want to
keep a particular look: for example, keep the sliding menus you like but stop the
taskbar bouncing.

**What it does — in technical terms.** `[ValidateSet('Legacy','Modern','Shell','DWM','All')]`,
`[string[]]`, default `@('All')`. If `All` appears anywhere in the list, it
expands to all four and any other values you passed are irrelevant. Accepts a
comma-separated list with no spaces around the commas. Any value outside the set
is rejected by PowerShell before the script body runs, with a message naming the
valid values. The layer of every setting is declared in the tables in
`_Common.ps1`; the script filters on it and silently ignores everything else.

Precisely which of the 20 settings each value reaches:

| Value | Settings acted on | Count |
|---|---|---|
| `Legacy` | Menu animation, Combo box animation, List box smooth scrolling, Gradient window captions, Menu fade, Selection fade, Tooltip animation, Tooltip fade, Cursor shadow, Drop shadow (windows), UI effects (master), Drag full windows, Menu show delay | 13 |
| `Modern` | Client area animation, `EnableTransparency` | 2 |
| `Shell` | `TaskbarAnimations`, `ListviewAlphaSelect`, `ListviewShadow`, `VisualFXSetting` | 4 |
| `DWM` | `EnableAeroPeek` | 1 |
| `All` | all of the above (the default) | 20 |

Note that `Drag full windows`, `Menu show delay` and the master gate are all
handled inside the `Legacy` branch. If `Legacy` is not among the requested
layers, none of the three is touched and `-KeepMenuDelay` has no effect.

**Example — everything (the default).**

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1
```

Expected output: header reading `layers: Legacy, Modern, Shell, DWM`, backup
path, the `effects:` block, the `shell / compositor:` block, the verification
block, and the counters.

**Example — only the modern layer.** This is the highest-value, lowest-visible-
change option on a weak GPU: it removes translucency and stops modern and
web-based apps animating, while leaving the classic desktop exactly as it looks
today.

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -Layers Modern
```

Expected output: `layers: Modern`, then just two candidate lines —
`Client area animation` under `effects:` and `EnableTransparency` under
`shell / compositor:` — each either `DISABLED`/`SET` or `already off`/`already
set`. The verification block should report `UISettings.Animations` as `False`.
`UISettings.AdvancedFx` should also read `False`, but a registry write carries no
`WM_SETTINGCHANGE` broadcast, so if it still reads `True` immediately after the
run, re-check with `Test-VisualEffects.ps1` after a shell restart or the next
sign-in before concluding anything failed.

**Example — only the legacy layer.**

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -Layers Legacy
```

Expected output: `layers: Legacy`, then the ten non-master USER32 effects, then
drag-full-windows, then the menu delay, then the master gate last — thirteen
candidate lines in total. The `shell / compositor:` heading is still printed,
with nothing beneath it, because the heading is unconditional and every registry
entry is filtered out.

**Example — only the shell layer.**

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -Layers Shell -RestartExplorer
```

Expected output: `layers: Shell`, an empty `effects:` block, four registry lines
(`TaskbarAnimations`, `ListviewAlphaSelect`, `ListviewShadow`,
`VisualFXSetting = 3`), then `desktop shell restarted`. `-RestartExplorer` is
paired with `Shell` here because these four are the settings Explorer reads at
start-up.

**Example — only DWM.**

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -Layers DWM
```

Expected output: `layers: DWM` and a single registry line setting
`EnableAeroPeek = 0`. Aero Peek is the desktop preview you get by hovering the
far corner of the taskbar.

**Example — two layers at once, classic desktop untouched.**

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -Layers Modern,Shell
```

Expected output: `layers: Modern, Shell`, and only those six settings considered.

**Example — the explicit form of the default.**

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -Layers All
```

Expected output: identical to running with no `-Layers` at all.

### -KeepMenuDelay

**What it does — in plain terms.** Leaves the delay before a menu opens alone.
By default the script sets that delay to zero, which removes the pause you get
when you hover over something like *File* and wait for the submenu. On the
machine this was built on that pause was 400 milliseconds — just under half a
second, every time. Some people find the pause useful, because it stops menus
flying open when the pointer merely crosses them. If you are one of those people,
use this switch.

**What it does — in technical terms.** `[switch]`. When present, the
`SPI_SETMENUSHOWDELAY` (`0x006B`) branch is skipped entirely and the script
prints `    skipped      Menu show delay (-KeepMenuDelay)`. Nothing is counted:
neither `changed` nor `already` increments.

When absent and the current delay is non-zero, the call made is
`Set-VfxSpiUiParam 0x006B 0`, which resolves to
`SpiSetUi(0x006B, [uint32]0, IntPtr.Zero, SPIF)`. The second argument is
`uiParam`, and it carries the value; it reads as `0` here because `0` ms is the
target. `pvParam` is `IntPtr.Zero`. This is the third of the three conventions
described above, and it is engineering observation, not vendor fact.

When absent and the delay is already zero, the script prints
`    already 0    Menu show delay` and increments the *already as wanted*
counter.

Only meaningful when `Legacy` is among the requested layers.

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -KeepMenuDelay
```

Expected output: everything as normal, but with
`    skipped      Menu show delay (-KeepMenuDelay)` where the change would have
been, and the verification block still reporting your unchanged delay, for
example `    menu show delay          : 400 ms`.

### -RestartExplorer

**What it does — in plain terms.** Restarts the desktop — the taskbar, the Start
menu and File Explorer — so the taskbar and file-list changes appear
immediately instead of at your next sign-in. **This closes any open File Explorer
windows.** It does not close your other applications, and it does not sign you
out. Expect the taskbar to disappear for a second or two.

**What it does — in technical terms.** `[switch]`. Guarded by `ShouldProcess`,
so `-WhatIf` shows it rather than doing it. Runs
`Stop-Process -Name explorer -Force`, waits two seconds, and starts
`explorer.exe` again only if no `explorer` process came back on its own (Windows
usually relaunches the shell itself). Without it, the four `Explorer` registry
values are on disk but not in the running shell's memory; the script prints a
reminder saying so. With it, that reminder is omitted.

The restart happens **before** the verification block, so the verification reads
a freshly started shell.

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -RestartExplorer
```

Expected output: the normal run, then a blank line and `  desktop shell restarted`,
then the verification block and counters, and the closing reminder about next
sign-in is omitted.

### -Tag

**What it does — in plain terms.** Puts a label of your choosing into the backup
filename, so you can recognise it later in a list of dated files.

**What it does — in technical terms.** `[string]`, default `''`. Passed to
`Save-VfxBackup`, producing `state_<yyyy-MM-dd_HH-mm-ss>_<Tag>.json` instead of
`state_<yyyy-MM-dd_HH-mm-ss>.json`. There is **no validation** on the value and
it is interpolated directly into the filename.

Keep it to letters, digits and hyphens. This is not cosmetic advice. If the tag
contains a character that is illegal in a Windows filename
(`\ / : * ? " < > |`), the `Set-Content` call fails. Because
`$ErrorActionPreference` is `Continue`, that failure prints a red error and the
script **carries on and changes your settings anyway**, with no timestamped
backup written. A failed backup is precisely the situation this module exists to
avoid, so check the `backup written` line actually names a file before letting a
run proceed on a machine you care about.

Two mitigations are worth knowing. On a first run, `original-state.json` is
written to a separate, tag-free path, so the pristine record is still created
even if the tagged file fails. And `-WhatIf` never writes a backup at all, so a
bad tag is invisible under `-WhatIf` and will only bite on the real run.

The tag has no effect on which file `Restore-VisualEffects.ps1` picks by
default — that is chosen by last-write time among files whose names begin
`state_` — but it makes `-List` readable and gives you an exact name to pass to
`-Backup`.

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -Tag before-gaming-session
```

Expected output: `  backup written           : ...\backups\state_2026-08-26_09-31-40_before-gaming-session.json`,
then the usual run.

### -WhatIf

**What it does — in plain terms.** Shows you every change it would make, and
makes none of them. Nothing at all is written — not even the backup file, and not
even the `backups` folder. Use it first, every time, on any machine you care
about.

**What it does — in technical terms.** Supplied by
`[CmdletBinding(SupportsShouldProcess = $true)]`. Every mutating operation is
wrapped in `$PSCmdlet.ShouldProcess(...)`, including the backup write and the
Explorer restart, so under `-WhatIf` all of them return `$false` and print a
`What if:` line instead. The post-change verification block is gated on
`-not $WhatIfPreference` and is therefore skipped.

The counters need explaining because they are easy to misread. `$changed` and
`$failed` increment inside the `ShouldProcess` blocks and therefore stay at zero
under `-WhatIf`. `$already` increments **outside** them, so it counts normally.
The closing summary will read `changed: 0   already as wanted: N   failed: 0`;
that is expected and is not a claim that nothing would happen. Read the
`What if:` lines. The `TO UNDO EVERYTHING:` reminder also prints, and under
`-WhatIf` means nothing.

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -WhatIf
```

Expected output: `  backup would be written to: ...\backups`, then one `What if:`
line per pending change, then `changed: 0   already as wanted: N   failed: 0`.

**Example — preview a narrowed run.** `-WhatIf` combines with everything else.

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -Layers Shell,DWM -WhatIf
```

Expected output: `layers: Shell, DWM` and `What if:` lines for at most the five
registry values in those two layers, plus one for the backup.

### -Confirm

**What it does — in plain terms.** Asks you before each individual change, one at
a time. Answer `Y` for yes, `A` for yes-to-all, `N` to skip that one, `L` to skip
all the rest, `S` to suspend into a nested prompt.

**What it does — in technical terms.** Also from `SupportsShouldProcess`. Because
every change is individually wrapped, `-Confirm` prompts per setting, per
registry value, for the backup write and for the Explorer restart. Declining a
prompt skips only that operation; the run continues. This is a genuine per-item
veto, not a single yes/no gate.

Declining the backup prompt while approving the changes is possible and is a bad
idea; the script will not stop you.

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -Confirm
```

Expected output: a `Confirm` prompt for the backup, then one per pending change,
then the verification block and counters reflecting only what you approved.

### Understanding the output lines

| Line | Meaning |
|---|---|
| `DISABLED     <name>  (<description>)` | The effect was on and the API call reported success |
| `SET          <name> = <n>  (<description>)` | A registry value was written |
| `SET          Menu show delay              400 ms -> 0 ms` | The menu delay was written |
| `already off  <name>` | Effect already off; nothing done, counted under *already as wanted* |
| `already 0    Menu show delay` | Delay already zero; counted under *already as wanted* |
| `already set  <name> = <n>` | Registry value already at target; counted under *already as wanted* |
| `FAILED       <name>` | The `SystemParametersInfo` call returned `false`; counted under *failed* |
| `FAILED       <name>: <message>` | The registry write threw; the exception message is shown; counted under *failed* |
| `skipped      Menu show delay (-KeepMenuDelay)` | You asked for it to be left alone; not counted at all |
| `STILL ON: <names>` | The verification re-read found something that did not take. This is the line that matters — it is read back from the system, not from what was written |
| `every targeted effect reads back as off` | The verification re-read found nothing left on in the requested layers |

The verification block checks the twelve table effects (filtered to the
requested layers) and drag-full-windows. It reports the menu delay and the two
`UISettings` readings as information, but does not include them in the `STILL ON`
list — a non-zero menu delay after a run without `-KeepMenuDelay` will show in
the `menu show delay` line, not as a failure.

---

## Restore-VisualEffects.ps1 - every option

**In plain terms.** This puts things back. With no options at all it does the
sensible thing: it restores the state your machine was in immediately before the
last time you ran the disable script.

**In technical terms.** It has four parameters of its own — `-Original`,
`-Backup`, `-List`, `-RestartExplorer` — plus `-WhatIf` and `-Confirm` from
`SupportsShouldProcess`. There is deliberately no `-Layers` and no `-Tag`.

It reads a JSON state file, then calls `Restore-VfxState`, which writes the
master gate first (so the individual legacy effects are restored underneath an
open gate), then every other SPI effect in table order, then drag-full-windows
and menu show delay via the `uiParam` convention, then every registry value —
deleting rather than zeroing any value that was `null` or empty at capture time.
Any SPI value recorded as `null` (unreadable at capture) is skipped rather than
guessed. Before doing any of this it takes a `pre-restore` backup of the current
state.

Four properties of the restore worth knowing up front:

- **It is not layer-scoped.** There is no `-Layers` on this script. A restore
  always restores all 20 settings from the chosen file. If you disabled only one
  layer, restoring still rewrites all four — but it rewrites them to the values
  recorded in the backup, which for the layers you never touched are the values
  they already have. The net effect is correct; the log will simply be longer
  than you expect.
- **The WinRT readings are not restored.** `UISettings.AnimationsEnabled` and
  `AdvancedEffectsEnabled` are recorded in every backup for evidence, but they
  are read-only projections of `Client area animation` and `EnableTransparency`.
  Restoring those two restores what modern apps see.
- **`-Confirm` on this script is nearly a no-op.** Neither `Save-VfxBackup` nor
  `Restore-VfxState` is wrapped in `ShouldProcess`, so `-Confirm` will prompt
  only for the Explorer restart — not for the pre-restore backup and not for the
  settings themselves. Use `-WhatIf` if you want to inspect before committing.
  This is an accurate description of the code as written, not a recommendation of
  it.
- **The per-setting log looks the same under `-WhatIf` as it does for real.**
  `Restore-VfxState` prints the same past-tense lines either way, with no
  `What if:` prefix, because it suppresses writes with an internal `-WhatIfMode`
  switch rather than through `ShouldProcess`. Only the closing line differs.

### (no parameters)

**What it does.** Restores the newest file in `backups` whose name begins
`state_`.

**When to use it.** Almost always. This is the undo button for the last run.

**In technical terms.** `Get-VfxBackups` sorts all `*.json` in `backups` by
`LastWriteTime` descending; the script takes the first whose name matches
`state_*`. Note that this pattern also matches `state_<stamp>_pre-restore.json`
and `state_<stamp>_roundtrip.json`. That has a consequence which surprises
people: after you have run a restore once, the newest `state_*` file is the
*pre-restore* backup, which records the **disabled** configuration. Running plain
`Restore-VisualEffects.ps1` a second time therefore puts the effects back off
again, not on. It is behaving exactly as documented — "restore the newest
timestamped state" — but "newest" is rarely what you mean after the first
restore. Use `-Original`, or name the file with `-Backup`, once more than one
restore point exists.

`original-state.json` does not match `state_*` and so is never chosen by the
default path; it can only be reached through the fallback, which takes the newest
file of any name when no `state_*` file exists at all. In that situation a
`snapshot_*.json` or a `roundtrip_A_*.json` could be selected instead. If the
folder is empty or absent it explains that the disable script has not been run
from this folder and exits without touching anything.

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1
```

Expected output: header naming the file and its UTC capture time,
`current state saved first : ...\state_<stamp>_pre-restore.json`, then a line per
restored setting. SPI effects print as `  <name>  -> True` or `-> False`; the
menu delay prints as `-> 400 ms`; registry values print their **numeric** value,
`  TaskbarAnimations  -> 1`, not `True`/`False`; and absent-at-capture registry
values print `-> removed (was not set originally)`. Then `N settings restored.`,
the next sign-in reminder, and a suggestion to verify with
`Test-VisualEffects.ps1`. On a complete backup, `N` is 20.

### -Original

**What it does — in plain terms.** Puts the machine back exactly as it was before
this project touched it, whatever has happened since. This is the option for "I
have run things several times, I have lost track, put it all back."

**What it does — in technical terms.** Restores `backups\original-state.json`,
which `Save-VfxBackup` writes on the first backup and never overwrites. That
guarantee is the reason this option can be trusted after any number of disable
runs. If the file does not exist, the script says so plainly — it is created the
first time `Disable-VisualEffects.ps1` runs — and exits without changing
anything. The header additionally prints `this is the pristine state recorded
before this module was first used` so you can see which file you are getting.

`-Backup` takes precedence over `-Original`; do not pass both.

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -Original -RestartExplorer
```

Expected output: `from : original-state.json`, the pristine-state note, the
pre-restore backup path, a line per setting, `desktop shell restarted`, and the
count restored.

### -Backup

**What it does — in plain terms.** Restores one specific saved file that you
name. Use `-List` first to see what you have.

**What it does — in technical terms.** `[string]`. Resolved in two steps: first
as given — which means a full path works, and a bare filename is resolved against
your **current working directory**, not the module folder — and if that does not
exist, as `backups\<value>` relative to the script's own folder. So a bare
filename works as long as you are not standing in a directory that happens to
contain a file of the same name. If neither resolves, it emits
`Backup not found: <value>` via `Write-Error` and returns without changing
anything.

Pass an exact filename. Wildcards are not supported: `Test-Path` would match and
`Get-Item` would return several files, after which the read fails and you get
`Could not read ...` rather than a useful message.

`-Backup` takes precedence over `-Original` because it is tested first in the
selection chain. Any file with the state shape is acceptable, including a
`snapshot_*.json` written by `Test-VisualEffects.ps1 -Json`, a
`roundtrip_A_*.json` written by `Test-RoundTrip.ps1`, and a `_pre-restore` file —
which is how you undo a restore.

**Example — a named restore point by bare filename.**

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -Backup state_2026-08-26_09-31-40_before-gaming-session.json
```

Expected output: `from : state_2026-08-26_09-31-40_before-gaming-session.json`,
its capture time, the pre-restore backup, then the restored lines.

**Example — undoing a restore, using the pre-restore file it left behind.**

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -Backup state_2026-08-26_10-02-11_pre-restore.json
```

Expected output: the same shape, returning you to the state you were in
immediately before the previous restore — that is, back to the disabled-effects
configuration.

**Example — a file from somewhere else entirely, by full path.**

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -Backup C:\Users\Username\Documents\Windows.11.tweaks.optimisation\_backups\state_2026-08-20_12-00-00.json
```

Expected output: as above. The file is read with `ConvertFrom-Json`; if it is not
valid JSON the script reports `Could not read <path>: <message>` and stops
without changing anything. Note that this check happens *before* the pre-restore
backup, so a corrupt file costs you nothing.

### -List

**What it does — in plain terms.** Shows every restore point you have, newest
first, with the date it was taken and a short summary of what was on at the time.
Then it stops. It changes nothing and restores nothing.

**What it does — in technical terms.** Lists every `*.json` in `backups` sorted by
`LastWriteTime` descending — timestamped backups, `pre-restore` files,
`original-state.json`, snapshots and round-trip files alike. For each, it parses
the file and prints three indented lines: the UTC capture time, the number of the
twelve table effects that were on at capture, and the menu show delay at capture.
That count excludes `Drag full windows` and all six registry values, so a file
showing `effects on at capture : 0` may still record shell settings that were on.
`original-state.json` is annotated `<-- pristine, use -Original`. A file that will
not parse prints `(unreadable)` and the listing continues. When `-List` is present
the script returns before any selection or restore logic runs, so it is safe to
combine with anything.

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -List
```

Expected output when backups exist: `Restore points in ...\backups`, then per
file its name, last-write time, and three indented summary lines, then two
reminder lines giving the commands for restoring the newest and restoring
pristine. Those two reminder lines are printed in the short form
`.\Restore-VisualEffects.ps1` without the `powershell -ExecutionPolicy Bypass
-File` prefix; if you are relying on that prefix, add it back.

Expected output when the folder is empty or absent: `No restore points found.
Nothing has been backed up yet, which means the disable script has not been run
from this folder.`

### -RestartExplorer

**What it does — in plain terms.** Same as on the disable script: restarts the
desktop so the taskbar and file-list settings come back at once rather than at
your next sign-in. Closes open File Explorer windows.

**What it does — in technical terms.** `[switch]`, gated on
`-not $WhatIfPreference` and then on `ShouldProcess`, so it never fires during a
dry run. Same `Stop-Process` / two-second wait / conditional `Start-Process`
sequence as the disable script. This is the only operation in the restore script
that `-Confirm` will prompt for.

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -RestartExplorer
```

Expected output: the normal restore, then `desktop shell restarted`, and the
closing next-sign-in reminder is omitted.

### -WhatIf

**What it does — in plain terms.** Shows what would be put back, and puts nothing
back. Useful for checking that a backup file contains what you think it does
before you commit to it.

**What it does — in technical terms.** `$WhatIfPreference` is passed into
`Restore-VfxState` as `-WhatIfMode`, which suppresses every write while still
printing the full per-setting log. It also suppresses the pre-restore safety
backup and the Explorer restart.

Because the suppression is a plain switch rather than `ShouldProcess`, **no**
`What if:` lines are printed and the per-setting lines are worded identically to
a real run — including `-> removed (was not set originally)` for values that
would be deleted. The only thing that distinguishes a dry run is the final line:
`N settings WOULD be restored. Nothing was changed.` Note that `N` counts every
setting the file describes, including ones already at the target value —
`Restore-VfxState` does not compare before writing, it simply writes.

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -Original -WhatIf
```

Expected output: `from : original-state.json`, its capture time, a line per
setting showing the value that would be restored, then
`N settings WOULD be restored. Nothing was changed.` No pre-restore file appears
in `backups`.

### -Confirm

**What it does — in plain terms.** On this script, almost nothing. It asks before
restarting the desktop, and nothing else. If you want to see what a restore would
do before doing it, use `-WhatIf` instead.

**What it does — in technical terms.** Available because the script declares
`SupportsShouldProcess`, but only one operation in it — the Explorer restart —
calls `$PSCmdlet.ShouldProcess`. The pre-restore backup and every setting write
happen unprompted. `-Confirm:$false` is accepted and is what `Test-RoundTrip.ps1`
passes when it invokes this script non-interactively.

---

## Test-RoundTrip.ps1 - every option

**In plain terms.** This script exists to prove the undo works on *your* machine
rather than asking you to take the manual's word for it. It records what your
settings are, runs the disable script for real, checks something actually
changed, runs the restore script for real, and then compares the end state with
the start state one setting at a time. If every setting came back, it prints
`PASS`. If any did not, it prints `FAIL` and names them.

It genuinely changes your machine while it runs. On a `PASS` the net effect is
nothing. It asks for confirmation before starting.

This script was not mentioned in earlier drafts of this manual, which listed only
three scripts. That was an omission: the file is in the folder and it runs.

**In technical terms.** `[CmdletBinding(SupportsShouldProcess = $true,
ConfirmImpact = 'High')]`, which is why it prompts by default under the standard
`$ConfirmPreference` of `High`. Sequence:

1. `Get-VfxState` → state A, also written to
   `backups\roundtrip_A_<yyyy-MM-dd_HH-mm-ss>.json`. Note the `roundtrip_A_`
   prefix does not match `state_*`, so this file is never selected by a default
   restore.
2. Invokes `Disable-VisualEffects.ps1 -Layers <Layers> -Tag roundtrip
   -Confirm:$false`, discarding all of its output with `*>&1 | Out-Null`.
3. `Get-VfxState` → state B, compared with A to confirm something moved.
4. Invokes `Restore-VisualEffects.ps1 -Confirm:$false` with no other arguments,
   which selects the newest `state_*` file — the `state_<stamp>_roundtrip.json`
   the previous step just wrote, whose contents are state A.
5. `Get-VfxState` → state C, compared with A across all twelve table effects,
   drag-full-windows, the menu show delay, and all six registry values
   (`<unset>` compared as a distinct value from `0`).

`exit 0` on PASS, `exit 1` on FAIL, so it can be used as a scripted check.

Two honest limitations. Because step 4 calls the restore script with no
arguments, the proof depends on the newest `state_*` file being the one step 2
wrote; that holds in normal use but would not if another process wrote a newer
`state_*` file mid-run. And if step 3 reports that nothing moved — because
everything was already disabled — the script says so and prints `PASS` with a
count of zero, which proves nothing. Read the `[3/5]` line.

### -Layers

**What it does — in plain terms.** Narrows the test to particular layers, the
same way the disable script does. Leave it out to test everything, which is the
meaningful test.

**What it does — in technical terms.** `[ValidateSet('Legacy','Modern','Shell','DWM','All')]`,
`[string[]]`, default `@('All')`. Passed straight through to
`Disable-VisualEffects.ps1`. It does **not** narrow the restore step or the
comparison: the restore is never layer-scoped, and `Compare-VfxStates` always
compares all 20 settings. Narrowing therefore changes what gets disturbed, not
what gets checked.

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1 -Layers Shell
```

### -KeepBackups

**What it does — in plain terms.** Whether to leave behind the state files this
test creates. They are kept by default.

**What it does — in technical terms.** `[switch]$KeepBackups = $true` — note the
switch defaults to *on*, so to turn it off you must use the explicit form
`-KeepBackups:$false`, with the colon. Passing the bare `-KeepBackups` sets it to
`$true`, which is already the default and does nothing. When false, the script
removes every `*.json` in `backups` that was not present before the run,
excluding `original-state.json`, which is never removed.

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1 -KeepBackups:$false
```

### -Confirm and -WhatIf

**In plain terms.** It asks you to confirm before it does anything, because it
really does change your settings. Answer `Y` to proceed. `-Confirm:$false` skips
the question, which is what you want if you are running it as part of a scripted
check. `-WhatIf` cancels the whole thing.

**In technical terms.** A single `$PSCmdlet.ShouldProcess('this user profile',
'apply visual-effect changes and then restore them')` gates the entire run. Under
`-WhatIf` it returns `$false` and the script prints `Cancelled. Nothing was
changed.` and returns — it does not preview the individual steps. There is no
per-step confirmation; it is one gate for everything.

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1
```

**Corrected 2026-08-26.** This page previously gave the second form as
`powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1 -Confirm:$false`.
That does not work, and it was published without being run.

Under `-File`, PowerShell treats everything after the script path as plain text,
so `-Confirm:$false` arrives as the *string* `"$false"` and the script dies with:

```
Cannot convert 'System.String' to the type
'System.Management.Automation.SwitchParameter' required by parameter 'Confirm'.
```

Switch parameters taking an explicit value need `-Command`, which parses them:

```powershell
powershell -ExecutionPolicy Bypass -Command "& '.\Test-RoundTrip.ps1' -Confirm:$false"
```

This is why the `.cmd` launchers in this folder use `-Command` and not `-File`
wherever a `-Confirm:$false` is involved, and `-File` everywhere else.

Expected output on success: five numbered progress lines, then `PASS - every one
of the managed settings returned to its starting value.` and the count of
settings that moved and came back.

Expected output on failure: `FAIL - N setting(s) did NOT return to their starting
value:`, a table of `was <x> now <y>` per setting, the full path of the state A
file, and the exact `-Backup` command to restore it.

---

## Measure-VisualEffects.ps1 - every option

**In plain terms.** This is the script that answers "yes, but does it actually do
anything?" It measures your machine with the animations on, then with them off,
and prints the difference. It is the only script here that changes settings
without you asking for a change, because it cannot measure both states without
putting the machine in both states.

It is allowed to tell you the change is worth nothing. That is the point.

**Launcher:** `7 - Measure what it actually saves.cmd`

```powershell
powershell -ExecutionPolicy Bypass -File .\Measure-VisualEffects.ps1
```

### What one run does, in order

1. Prints the hardware, the Windows build, the power scheme and whether you are on
   mains, then refuses to pretend a battery run is comparable to a mains run.
2. Names any browser or web-application host it can see, with a process count,
   because those are the largest single source of noise on a desktop.
3. Asks you to type `YES`.
4. Checks `backups\original-state.json` exists. Without it there is no "before" to
   restore to, and it stops.
5. For each repeat:
   - restores the original state, restarts Explorer, waits out the settle period
   - measures the machine idle, then under the workload, then times the animated
     operations
   - applies the module's changes, restarts Explorer, waits the same settle period
   - measures all three again
6. Prints the comparison, with a noise floor derived from the repeats.
7. Leaves the machine applied — or original, with `-LeaveOriginal` — and says which.
8. Writes `RESULTS.md` (publishable) and `measurements\vfx_measurement_*.json` (not).

### Every parameter

| Parameter | Default | What it does |
|---|---|---|
| `-Seconds` | `25` | Length of each measurement window. Longer resolves smaller differences and takes longer |
| `-Repeats` | `2` | Complete before/after pairs. **Two is the minimum that produces a noise floor.** One produces a report that says so, in place of every verdict |
| `-SettleSeconds` | `20` | Wait after each state change and Explorer restart before the clock starts. Both sides wait the same, so the wait is fair even where it is not sufficient |
| `-LeaveOriginal` | off | Finish with the animations back **on** instead of applied |
| `-NoWorkload` | off | Idle measurements only. Faster, opens no window, and misses most of the effect |
| `-Force` | off | Skip the `YES` prompt. For unattended runs |

Plus the PowerShell common parameters, from `[CmdletBinding()]`.

### Examples for every capability

**The normal run.** Two pairs, 25-second windows, about ten minutes.

```powershell
powershell -ExecutionPolicy Bypass -File .\Measure-VisualEffects.ps1
```

**A quieter, slower run** for a machine with noisy background activity — three
pairs and 40-second windows roughly halve the noise floor, at the cost of about
half an hour.

```powershell
powershell -ExecutionPolicy Bypass -File .\Measure-VisualEffects.ps1 -Repeats 3 -Seconds 40
```

**Measure, then hand the machine back untouched** — both sides are still measured;
it simply finishes on the original side.

```powershell
powershell -ExecutionPolicy Bypass -File .\Measure-VisualEffects.ps1 -LeaveOriginal
```

**What the compositor costs at rest**, with no window opening on your screen. Long
windows, because at idle the differences are small.

```powershell
powershell -ExecutionPolicy Bypass -File .\Measure-VisualEffects.ps1 -NoWorkload -Seconds 60 -Repeats 3
```

**Unattended, with a transcript.** Output goes to the host stream, so redirect all
streams to capture it.

```powershell
powershell -ExecutionPolicy Bypass -File .\Measure-VisualEffects.ps1 -Force *> measure.log
```

**A fast shake-out** to confirm the script runs on a new machine, before spending
ten minutes on it. The numbers from this are meaningless and it will say so.

```powershell
powershell -ExecutionPolicy Bypass -File .\Measure-VisualEffects.ps1 -Seconds 8 -Repeats 1 -SettleSeconds 5 -Force
```

**Establish the noise floor separately, first.** This changes nothing at all, and
tells you the smallest difference your machine can resolve today.

```powershell
powershell -ExecutionPolicy Bypass -File ..\..\READ-ONLY-diagnostics\Measure-Performance.ps1 -Repeats 3 -Seconds 30
```

### Reading the report

Three sections, and they answer different questions.

**IDLE** — what the machine costs sitting still. This is where a continuously
rendered effect such as frosted glass shows up. If translucency is already off,
expect this section to be small and possibly to disappear into the noise.

**WORKLOAD** — what the machine costs while things animate. Seven operations run
on a fixed clock: menu open and close, drop-down list open and close, long-list
scroll, list selection, tooltip show and hide, minimise and restore, and window
drag. Each maps to a specific setting the module changes. Fixed timing means both
sides perform the same operations over the same duration, which is what makes
"processor milliseconds consumed" a fair comparison rather than a race.

**RESPONSIVENESS** — how long an animated open blocks the application. Menus and
drop-downs are animated in-process by `AnimateWindow`, which is **synchronous**:
the call does not return until the animation has finished, so timing the call is
real waiting, not a proxy for it.

Minimise and restore are deliberately absent from that section. Those are
composited by DWM out of process; the call returns immediately and the animation
plays afterwards, so timing it would measure nothing. Their cost appears in the
processor and GPU figures instead.

Finally, **MENU SHOW DELAY** is not measured at all — it is read from the setting.
400 ms to 0 ms is a pure wait with no work behind it, and no benchmark is needed
to establish that removing it removes it.

### Units, and what counts as a result

Everything in the comparison table is **per second of runtime**, because the two
windows are never exactly the same length — reading the counters takes time, and
that time varies. A rate is comparable across unequal windows; a total is not.
Both window lengths are printed so you can see how close they were.

- **CPU ms/s** — milliseconds of processor time consumed per second of runtime,
  summed across all cores. On a 12-thread machine the ceiling is 12 000.
- **GPU ms/s** — milliseconds of graphics-engine time per second. Engines run
  concurrently, so a total across engines above 1 000 is legitimate.
- **RAM MB** — resident memory, a level rather than a rate, and never divided by
  time.

A row marked `within noise` changed by less than the spread observed between
repeats of the *same* state. It is not a saving. Treat it as "no result".

### What this cannot tell you

- **Power drawn.** Processor time is a proxy for it, not a measurement of it. No
  claim about battery minutes is made anywhere in this module.
- **Anything about a different machine.** The workload is reproducible; the numbers
  are not transferable. That is why `RESULTS.md` leads with the hardware.
- **Whether you will like it.** Whether a 400 ms menu delay is "responsive" or
  "jarring when removed" is not a measurable quantity.

### Failure modes and what they mean

| Symptom | Cause | What to do |
|---|---|---|
| "There is no original-state.json in backups\" | The module has never been applied for real, so there is no recorded before-state | Run `3 - Apply the changes` once, then measure |
| "Cannot find the measurement engine" | The module has been copied out of the repository | Keep it in place, or copy `_MeasureLib.ps1` into a `READ-ONLY-diagnostics` folder two levels up |
| "workload failed: ..." | The window could not be created — no interactive desktop, or a remote session without one | Use `-NoWorkload`, or run it at the console |
| Every verdict says `within noise` | Correct behaviour on a quiet machine with small effects, or a machine too noisy to resolve them | Close the browser, then raise `-Seconds` and `-Repeats` |
| The numbers contradict each other between repeats | The noise floor is larger than the effect | The same. If it persists, the honest conclusion is that this change is not worth measurable processor time on your hardware |
| It stopped part-way and the animations are back on | The run was interrupted between the restore and the apply | Run `3 - Apply the changes`. Nothing is damaged; the machine is simply on the "before" side |

### Why it changes settings at all, when nothing else here does without asking

Because the alternative is a repository that asserts savings and never checks
them. Everything this script does is reversible by the module's own audited
restore path, it uses those audited scripts rather than a private copy of the
logic, the write-once original state is never overwritten, and it states which
side of the comparison it left you on. If you would rather not, do not run it —
nothing else in the module depends on it.

---

## The 20 settings this module manages

**In plain terms.** These are all of them. "What it looks like when it is on" is
what you will stop seeing. Nothing in this list removes a feature — a menu with
no fade is still a menu; a window with no shadow is still a window.

**In technical terms.** Fourteen are read and written through
`SystemParametersInfo`; six are `HKCU` registry values. The two WinRT
`UISettings` readings recorded in each backup are observations of the first
group's effect and are not separately writable, which is why the count is 20 and
not 22.

### Read and written through SystemParametersInfo

| # | Setting | Layer | What it looks like when it is on | GET / SET code | Target |
|---|---|---|---|---|---|
| 1 | Menu animation | Legacy | Menus slide or fade open rather than appearing at once | `0x1002` / `0x1003` | 0 |
| 2 | Combo box animation | Legacy | Drop-down lists animate as they open | `0x1004` / `0x1005` | 0 |
| 3 | List box smooth scrolling | Legacy | Lists glide as you scroll instead of jumping line by line | `0x1006` / `0x1007` | 0 |
| 4 | Gradient window captions | Legacy | Title bars painted as a colour gradient rather than flat | `0x1008` / `0x1009` | 0 |
| 5 | Menu fade | Legacy | Menus fade out when closing | `0x1012` / `0x1013` | 0 |
| 6 | Selection fade | Legacy | The item you clicked in a menu fades out after the click | `0x1014` / `0x1015` | 0 |
| 7 | Tooltip animation | Legacy | Tooltips slide into view | `0x1016` / `0x1017` | 0 |
| 8 | Tooltip fade | Legacy | Tooltips fade in and out | `0x1018` / `0x1019` | 0 |
| 9 | Cursor shadow | Legacy | The mouse pointer casts a small shadow | `0x101A` / `0x101B` | 0 |
| 10 | Drop shadow (windows) | Legacy | Windows cast a shadow on whatever is behind them | `0x1024` / `0x1025` | 0 |
| 11 | Client area animation | **Modern** | All animation inside modern apps, and inside web-based apps, which see this flag as `prefers-reduced-motion` | `0x1042` / `0x1043` | 0 |
| 12 | UI effects (master) | Legacy | The master gate for the whole legacy family; set **last** when disabling, **first** when restoring | `0x103E` / `0x103F` | 0 |
| 13 | Drag full windows | Legacy | A window's contents redraw continuously while you drag it, instead of showing an outline | `0x0026` / `0x0025` (value in `uiParam`) | 0 |
| 14 | Menu show delay | Legacy | The pause before a hovered submenu opens — 400 ms on the reference machine | `0x006A` / `0x006B` (value in `uiParam`) | 0 ms |

Entries 1 to 12 are the ordered table in `_Common.ps1`; entries 13 and 14 are
held as four separate constants, which is why they are handled by their own
branches rather than by the main loop, and why they are listed separately in
every output block. Note that for entry 13 the GET code (`0x0026`) is numerically
higher than the SET code (`0x0025`); that is not a transcription error, it is how
those two constants are defined.

Setting 11 is the single highest-value item in this table on a machine that runs
web-based applications, because one flag reaches every Chromium-based app at
once (R-69/R-70 for the flag's documented purpose; the `prefers-reduced-motion`
projection is engineering observation).

### Read and written in the registry

| # | Value name | Key | Layer | What it looks like when it is on | Target |
|---|---|---|---|---|---|
| 15 | `EnableTransparency` | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` | **Modern** | Frosted-glass translucency (acrylic / Mica) on Start, the taskbar, and app surfaces. The most GPU-expensive item in this module — a blur recalculated every frame for every translucent surface | 0 |
| 16 | `TaskbarAnimations` | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | Shell | Taskbar buttons animate as they appear, move and are clicked | 0 |
| 17 | `ListviewAlphaSelect` | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | Shell | The rubber-band selection rectangle you drag in a folder is translucent rather than a plain outline | 0 |
| 18 | `ListviewShadow` | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | Shell | Desktop icon labels have a drop shadow behind the text | 0 |
| 19 | `VisualFXSetting` | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects` | Shell | Not an effect. It is what the Performance Options dialog reads to decide which radio button to show. Set to **3** so that dialog reports "Custom" and agrees with what this module has done | 3 |
| 20 | `EnableAeroPeek` | `HKCU:\Software\Microsoft\Windows\DWM` | DWM | Hovering the far corner of the taskbar makes every window go transparent to preview the desktop | 0 |

All six are written as `DWord` with `New-ItemProperty -Force`, and the containing
key is created with `New-Item -Force` if it is absent.

`VisualFXSetting` is the one entry whose target is not zero, and the one entry
that is a report rather than a behaviour. It exists so that a user who later
opens *Performance Options* is not told "Let Windows choose" while the effects
sit switched off.

On restore, any of these six that was `null` or empty at capture time is
**removed** with `Remove-ItemProperty`, not set to zero. A recorded `0` is
written back as `0`. On a machine where `VisualFXSetting` was never set — which
was the case on the reference machine — restoring deletes it again, and the log
line reads `VisualFXSetting -> removed (was not set originally)`.

### The two readings that are recorded but not written

| Reading | Source | What it tells you |
|---|---|---|
| `UISettings.AnimationsEnabled` | `Windows.UI.ViewManagement.UISettings` | What modern and web-based apps actually see. This is the authoritative answer for setting 11 (R-67/R-68) |
| `UISettings.AdvancedEffectsEnabled` | same | What apps see for translucency. This is the authoritative answer for setting 15 |

If the WinRT type cannot be loaded, `Get-VfxState` catches the failure silently
and both read `null`, displayed as `unavailable`. Everything else continues to
work; you simply lose the independent confirmation. The most common cause is
running under PowerShell 7 rather than Windows PowerShell 5.1 — see below.

---

## Troubleshooting

### "Nothing to do" — did it fail?

**What you see.**

```
  changed: 0   already as wanted: 20   skipped: 0   failed: 0

  Nothing to do - every setting was already as this module wants it.
  The backup just written has been REMOVED, because keeping it would
  overwrite your real undo point with a copy of the current state.

  Exit code 4: nothing to do.
```

**No, that is success.** Everything this module wants is already set. Press it
again as many times as you like — it will keep saying the same thing and will
change nothing.

**Why it deletes a backup.** Because a backup taken *now* would be a photograph
of the machine as it already is. The undo restores the **newest** backup, so
keeping that one would overwrite your real undo point with a useless copy of the
current state. This used to happen, and it silently broke the undo — see the
README section *"If you press Apply more than once"*.

### UNDO says "this undo would change nothing" and stops

**What you see.**

```
  STOPPING - this undo would change nothing.

  The newest restore point (state_....json) records
  exactly the state this machine is in now (20 settings compared, 0 differ).
  Restoring it would look like it worked and would achieve nothing.
```

**This is the safety check working, not a failure.** It found that the backup it
was about to restore is identical to your machine right now — so restoring it
would print a convincing success message and do nothing.

**What to do:** use the launcher **`5 - UNDO back to the original`**, which goes
to the state recorded before this module was ever used:

```bash
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -Original
```

**Why it happened:** an older version of the apply wrote a backup on every
press, including presses that changed nothing. Both ends are fixed now, so new
dead restore points cannot be created.

### How do I see which restore points are still any use?

```bash
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -List
```

Each one is now labelled with what restoring it would actually do:

```
      restoring this would change 12 setting(s).
      DEAD - restoring this would change NOTHING (20 settings compared, 0 differ).
```

`DEAD` entries are harmless — the undo refuses to use one. Files already moved
out of the way live in `backups\_quarantine-poisoned\` and can be moved back if
you ever want them.

### PowerShell refuses to run the script

**What you see.** A red message containing `cannot be loaded because running
scripts is disabled on this system`, or `UnauthorizedAccess`, or
`is not digitally signed`.

**In plain terms.** Windows blocks scripts by default. This is a sensible default
and you do not need to change it permanently. Every example in this manual
already includes `-ExecutionPolicy Bypass`, which lifts the block for that one
run only and changes nothing on your machine. If you are seeing this error, you
have probably run the script without that part — for example by typing
`.\Test-VisualEffects.ps1` on its own. Use the full command:

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-VisualEffects.ps1
```

Expected output: the state report, as in step 2 above.

The important detail: `-ExecutionPolicy Bypass` is an argument to
`powershell.exe`. It only works when you are *launching* PowerShell. Typing
`-ExecutionPolicy Bypass` inside a PowerShell session you already have open does
nothing. That is why every command in this manual starts with the word
`powershell`, even when you are already in PowerShell — you are starting a second,
short-lived PowerShell process with the block lifted, and it closes when the
script finishes.

**In technical terms.** `-ExecutionPolicy Bypass` on the `powershell.exe` command
line sets the policy for that process only; it does not write to the registry and
does not require elevation. To inspect what is in force:

```powershell
powershell -Command "Get-ExecutionPolicy -List"
```

Expected output: a table of five scopes — `MachinePolicy`, `UserPolicy`,
`Process`, `CurrentUser`, `LocalMachine` — with the effective policy for each.

If a `MachinePolicy` or `UserPolicy` row shows anything other than `Undefined`,
your execution policy is set by Group Policy. Group Policy overrides
`-ExecutionPolicy Bypass` on the command line, and there is nothing this module
can do about that. On a managed work machine that is the likely explanation, and
the answer is to ask whoever manages it.

If you would rather set a persistent per-user policy instead of typing `Bypass`
each time, that is your decision to make, not this module's. `RemoteSigned` at
`CurrentUser` scope is the usual choice and needs no administrator rights. Be
aware it is a change to a security setting and it applies to every script you run
as this user, not only these four.

A separate cause with the same symptom: if you downloaded this repository as a
zip, Windows marks the extracted files as coming from the internet, and that mark
can block them independently of execution policy. Clearing the mark is per-file
and does nothing else:

```powershell
powershell -Command "Get-ChildItem 'C:\Users\Username\Documents\Windows.11.tweaks.optimisation\modules\01-visual-effects' -Filter *.ps1 | Unblock-File"
```

Expected output: nothing. `Unblock-File` is silent on success.

### The two "what modern apps see" lines say `unavailable`

**In plain terms.** The two lines under *LAYER 2* are an independent second
opinion: they report what modern and web-based applications actually see, rather
than what the setting was written as. If they say `unavailable`, you have lost
that second opinion, but nothing else is affected and no change has failed. Every
other reading and every change still works.

The usual cause is running the scripts with `pwsh` (PowerShell 7) instead of
`powershell` (Windows PowerShell 5.1). Use `powershell`.

**In technical terms.** `Get-VfxState` loads the type with the Windows PowerShell
type-literal form
`[Windows.UI.ViewManagement.UISettings, Windows.UI.ViewManagement, ContentType=WindowsRuntime]`,
which is a Windows PowerShell 5.1 feature. Under PowerShell 7 the WinRT
projection is not present by default and the load throws; the `try`/`catch` in
`Get-VfxState` swallows it deliberately and leaves both properties `null`. The
`Add-Type` P/Invoke block and every registry operation work identically under
both hosts, so the only loss is the WinRT cross-check. Backups taken under
PowerShell 7 will record `null` for both readings; since neither is ever
restored, this does not affect a round trip.

### The taskbar changes have not appeared

**In plain terms.** Four of the settings — taskbar animation, the translucent
selection rectangle, icon label shadows, and the Performance Options label — are
read by the desktop program when it starts. Changing them on disk does not
change the copy already running in memory. You have three choices: sign out and
back in, restart the PC, or restart just the desktop. The third is quickest and
does not close your applications, but it does close open File Explorer windows.

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -Layers Shell -RestartExplorer
```

Expected output: `layers: Shell`, an empty `effects:` block, four lines mostly
reading `already set` (because the values are already written from your earlier
run), then `desktop shell restarted`. The taskbar will vanish for a second or two
and come back with the changes in place.

**In technical terms.** The four `Explorer` values under `...\Explorer\Advanced`
and `...\Explorer\VisualEffects` are cached by `explorer.exe` at process start.
`SPIF_SENDCHANGE` broadcasts `WM_SETTINGCHANGE` for the `SystemParametersInfo`
family, which is why those apply instantly, but a registry `DWORD` write carries
no such broadcast. Re-running the disable script is idempotent: it re-reads the
current state first, prints `already set` for anything at target, and increments
the *already as wanted* counter rather than the *changed* one, so using it purely
to trigger the shell restart is harmless. It will, however, write another backup
file.

`EnableTransparency` is in the same position: the write lands immediately but
`UISettings.AdvancedEffectsEnabled` may not reflect it until the shell picks the
change up.

A related and honest caveat about the reporting: `Test-VisualEffects.ps1` builds
its `shell/DWM to change` summary line by comparing each registry value against
its target, and treats an *absent* value as needing a change only when the target
is zero. `VisualFXSetting` has a target of 3, so when it is unset — which is the
default on a clean machine — it will not appear in that summary line even though
the disable script will in fact set it. The `LAYER 3+4` block above the summary
shows it correctly as `<not set>`. This is a cosmetic gap in the summary, not a
defect in the change itself.

### Someone has run the disable script twice

**In plain terms.** No harm has been done. This is the exact situation the module
was designed around.

The second run made no changes, because everything was already off — the log will
be full of `already off` and `already set` lines. It wrote a second backup file,
which records the already-disabled state. That is harmless. Critically, it did
**not** overwrite `original-state.json`, so the way back to your original
configuration still exists and always will.

What you should **not** do in this situation is run `Restore-VisualEffects.ps1`
with no arguments and expect your original look back. With no arguments it
restores the *newest* backup, which is the one the second run wrote — the
already-disabled state. Use `-Original` instead.

Check what you have:

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -List
```

Expected output: your files newest-first. The second run's backup will show
`effects on at capture : 0`, which tells you at a glance that restoring *that*
one would put you back to the disabled state, not the original one. The line
ending `<-- pristine, use -Original` is the one you want if you are after your
original configuration.

**In technical terms.** `Save-VfxBackup` guards the pristine copy with
`if (-not (Test-Path $original))`. There is no code path in any of the four
scripts that writes `original-state.json` when it already exists, and no code
path that deletes it — `Test-RoundTrip.ps1 -KeepBackups:$false` explicitly
excludes it from its cleanup. The default restore selection deliberately skips it
by filtering on `state_*`, so plain `Restore-VisualEffects.ps1` will restore the
most recent *timestamped* state — after two disable runs that is the
already-disabled state, which is almost certainly not what you want. Use
`-Original`.

The same trap has a second form, worth stating separately because it catches
people who did everything right: `state_*` also matches
`state_<stamp>_pre-restore.json`. So if you disable, then restore, then run the
restore script again with no arguments, the newest `state_*` file is the
pre-restore backup, which records the **disabled** state — and the second restore
turns the effects back off. That is not a malfunction, but it is not what the
words "restore again" suggest. Once you have more than one restore point, name
the one you want.

### You want the machine exactly as it was originally

**In plain terms.** One command. It reads the file that was written the very
first time anything ran, and puts all 20 settings back to those values, deleting
any registry entries that were not there before.

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -Original -RestartExplorer
```

Expected output: `from : original-state.json`, the note
`this is the pristine state recorded before this module was first used`, the
pre-restore backup path, a line for each of the 20 settings,
`desktop shell restarted`, and `20 settings restored.`

If you would like to see it first without doing it:

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -Original -WhatIf
```

Expected output: the same per-setting listing, ending
`20 settings WOULD be restored. Nothing was changed.` Remember that the
per-setting lines are worded the same either way; the last line is what tells you
which you got.

Then confirm independently:

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-VisualEffects.ps1
```

Expected output: the state report showing the values you started with.

**If the message says `No original-state.json exists`**, then
`Disable-VisualEffects.ps1` has never completed a real (non-`-WhatIf`) run from
this folder, and no pristine state was ever recorded — which also means nothing
was ever changed by this module, so there is nothing to undo. Check with `-List`.

### A restore picked a file you did not expect

**In plain terms.** With no arguments, the restore script picks the newest file
whose name starts with `state_`. That set is larger than most people assume: it
includes the pre-restore backups a restore leaves behind and the backups the
round-trip test writes, not just the ones you deliberately created. And if no
`state_` file exists at all, it falls back to the newest file of any name — which
could be a snapshot from `Test-VisualEffects.ps1 -Json`. A snapshot is a record
of a moment, not a considered restore point.

Avoid the ambiguity by looking first and then naming the file you want:

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -List
```

Expected output: every file with its date and a summary, so you can pick
deliberately and pass the exact name to `-Backup`.

**In technical terms.** `Get-VfxBackups` returns all `*.json` in the backup
directory sorted by `LastWriteTime` descending. The default selection is
`$all | Where-Object { $_.Name -like 'state_*' } | Select-Object -First 1`, with
a fallback of `$all | Select-Object -First 1` when that yields nothing. Files
matching `state_*` therefore include `state_<stamp>.json`,
`state_<stamp>_<Tag>.json`, `state_<stamp>_pre-restore.json` and
`state_<stamp>_roundtrip.json`. Files that do **not** match, and so are reachable
only through the fallback, are `original-state.json`, `snapshot_*.json` and
`roundtrip_A_*.json`.

**Corrected 2026-08-26 — this used to be a real defect, and it is worth recording
rather than quietly deleting.**

Earlier versions of this page described the following as a consequence to be aware
of: the restore script's own pre-restore `Save-VfxBackup` call would create
`original-state.json` from the *current* state whenever none existed yet — and
because that file is deliberately never overwritten, it became the permanent
"pristine" record even though the machine may already have been modified.

The effect was that `5 - UNDO back to the original` would restore to the
**applied** state, permanently, and nothing in its output would reveal that the
"original" it was restoring to had been captured after the fact.

Documenting a hazard is not the same as fixing it, and this one cost one
parameter. `Save-VfxBackup` now takes `-RecordAsOriginal`, and only
`Disable-VisualEffects.ps1` passes it — the apply path, reading the machine
*before* it changes anything, which is the only reading entitled to define
"original". The restore script's pre-restore snapshot is still written, still
tagged `pre-restore`, and still excluded from restore selection; it simply can no
longer masquerade as the pristine record.

If `original-state.json` does not exist, `-Original` now says so plainly instead
of silently using a file that was never an original. It is created the first time
the apply script runs, which is the only moment at which the machine's untouched
state is actually observable.

The same defect existed in module 02 and was fixed in the same way, in the same
change.

### The backup line did not name a file

**In plain terms.** If the `backup written` line is missing or is preceded by a
red error, the backup did not happen — and the script will have gone on to change
your settings anyway. Stop and check the `backups` folder before doing anything
else.

The most likely cause is a `-Tag` containing a character Windows will not accept
in a filename: `\ / : * ? " < > |`. Use letters, digits and hyphens.

**In technical terms.** `Save-VfxBackup` interpolates the tag into the filename
with no validation. `Set-Content` fails on an illegal path, and because every
script sets `$ErrorActionPreference = 'Continue'` the failure is non-terminating:
the error record is printed, `Save-VfxBackup` returns, and the disable run
proceeds to apply changes. The `original-state.json` write uses a separate,
tag-free path and will still succeed on a first run, so the pristine route home
survives even in this case — but the timestamped restore point for *this* run
does not exist. There is no post-write verification of the backup file; adding
one would be a reasonable improvement and is not currently implemented.

### Something reports FAILED, or the verification says STILL ON

**In plain terms.** The script tells you rather than hiding it. Re-run the test
script to see the current truth, and re-run the disable script — it is safe to
run repeatedly and will retry only what is still on.

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-VisualEffects.ps1
```

Expected output: the state report. The `effects still on` line names exactly what
did not take.

**In technical terms.** `FAILED` means the `SystemParametersInfo` call returned
`false` or the registry write threw; the exception message is printed for
registry failures. `STILL ON` in the verification block means the write reported
success but a fresh `Get-VfxSpi` read still returns non-zero — which is the
signature of a wrong calling convention, of policy or another process overwriting
the value, or of a per-session state that is not persisting. Because the
verification block re-reads through the API rather than echoing what was written,
this distinction is visible to you.

Known and expected causes: a Group Policy or management agent enforcing a value;
a second copy of a settings UI (Settings, or the Performance Options dialog) open
at the same time writing the value back; and, on the legacy family specifically,
another tool that writes the packed `UserPreferencesMask` blob wholesale.

If an individual effect reads `unreadable` in `Test-VisualEffects.ps1`, that is a
different condition: the `SPI_GET*` call itself returned `false`, so the module
has no value to compare against and `Restore-VfxState` will skip that setting
rather than guess at it.

### Nothing looks different after a full run

**In plain terms.** Check three things in order. First, whether the effects were
already off — the log will say `already off` on every line if so, and the machine
this module was built on already had several of them off before it ever ran.
Second, whether you have restarted the desktop, since four items need it. Third,
that you are looking for the right thing: with the master gate off, menus appear
instantly instead of sliding, window shadows are gone, and the taskbar no longer
animates. These are absences, and absences are harder to notice than additions.

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-VisualEffects.ps1 -Json
```

Expected output: the state report plus a saved snapshot path, which you can
compare against a snapshot taken before your run to see precisely what moved.

If you want the machine to do that comparison for you rather than doing it by
eye, `Test-RoundTrip.ps1` records the before state, applies, restores, and
reports every setting that did not return.

---

## What this module deliberately does not do

**In plain terms.** An honest tool tells you where it stops.

**In technical terms.** Each of the following is a considered exclusion, not an
omission.

**It does not switch off desktop composition.** It cannot. Composition has been
permanently on since Windows 8, and `DwmEnableComposition` cannot disable it
(R-71/R-72/R-73). Advice found online telling you to turn off Aero or disable the
DWM service is describing Windows 7. What this module reduces is the amount of
work composition is asked to do — fewer blurs, fewer shadows, fewer animated
surfaces — which is the only lever that still exists. `dwm.exe` will still be
running afterwards, and its memory use will not drop to nothing.

**It does not claim vendor authority for the SystemParametersInfo calling
conventions.** See *Honesty about what is and is not vendor-documented* above.
The conventions are engineering observation, verifiable by you with the test
script. The `prefers-reduced-motion` projection is likewise observation.

**It does not require, request, or use administrator rights.** Every write is
`HKCU` and per-user `SystemParametersInfo`; the only `HKLM` access is a read of
the build number. It cannot change settings for other users on the machine, and
it cannot change machine-wide policy. If you need this applied to several
accounts, run it once as each account.

**It does not touch Windows' own Performance Options presets.** It does not click
"Adjust for best performance" on your behalf, and it does not write the packed
`UserPreferencesMask` blob that that dialog manipulates. It sets the individual
flags through the API and sets `VisualFXSetting` to 3 so the dialog honestly
reports "Custom". If you later use that dialog to select "Adjust for best
appearance", it will overwrite much of what this module did — and
`Restore-VisualEffects.ps1 -Original` will still be there.

**It does not restore layer by layer.** There is no `-Layers` on the restore
script; a restore always applies all 20 settings from the chosen file. If you
need finer control, restore a backup that already contains the mix you want, or
re-run the disable script with the layers you do want.

**It does not prompt per setting on restore.** `-Confirm` on
`Restore-VisualEffects.ps1` reaches only the Explorer restart, because
`Restore-VfxState` is called outside `ShouldProcess`. `-WhatIf` is the way to
inspect a restore before committing to it. This is a description of the code as
written, not an endorsement of the design.

**It does not validate what you pass to -Tag.** The value goes into a filename
unchecked, and a filename-illegal character costs you that run's backup while the
run proceeds regardless. See *The backup line did not name a file*.

**It does not force a reboot or sign-out.** `-RestartExplorer` is the strongest
action it will take, it is opt-in, and it is announced. `Test-RoundTrip.ps1` is
the only script that changes settings without you naming the change, and it asks
first.

**It does not delete backups on its own.** The only deletion path anywhere is
`Test-RoundTrip.ps1 -KeepBackups:$false`, which removes only the files that run
created and never `original-state.json`. Nothing prunes the `backups` folder over
time; it will grow one file per disable run and one per restore, and clearing it
is your decision.

**It does not know whether your machine will feel faster.** It can tell you
exactly what it changed and prove it by re-reading the system. It cannot promise
a frame-rate improvement, and this manual will not pretend otherwise.
Microsoft's own documentation is clear that acrylic rendering "is GPU-intensive,
which can increase device power consumption and shorten battery life" (R-63) and
that blur, shadow-mask and backdrop-brush effects are "not recommended for low
end devices" (R-66), which is a strong reason to expect a benefit on integrated
graphics — but expecting a benefit and measuring one are different things. Take a
`-Json` snapshot before and after, watch `dwm.exe`, and judge for yourself.

**It does not modify or remove applications.** Nothing here uninstalls anything,
disables a service, or edits a policy. The worst outcome of running every script
in this module in every combination is a desktop that looks plainer than you
wanted, and `Restore-VisualEffects.ps1 -Original` fixes that in one command.
