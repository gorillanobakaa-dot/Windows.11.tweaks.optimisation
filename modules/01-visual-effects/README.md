# Visual effects - animations, blur, and what they cost

## Just want to click something?

You do not need a terminal, and you do not need to know any PowerShell. Seven
files in this folder end in `.cmd`, and those are double-clickable. They are
numbered in the order you would normally use them:

| Double-click this | What happens |
|---|---|
| **1 - Check what is on now** | Shows which effects are currently switched on. Changes nothing |
| **2 - Preview the changes (safe)** | Lists every change that would be made, then makes none of them |
| **3 - Apply the changes** | Saves your current settings, then turns the effects off |
| **4 - UNDO everything** | Puts everything back the way it was before the last run |
| **5 - UNDO back to the original** | Goes all the way back to how the machine was before this was ever used |
| **6 - Prove the undo works** | Applies everything, undoes it, and checks every setting came back |
| **7 - Measure what it actually saves** | Measures your machine with the effects on and off, and prints the difference |

Numbers 3, 4, 5, 6 and 7 change settings. Numbers 1 and 2 cannot.

**None of them asks for administrator rights**, because none is needed: these are
your own display settings, not machine-wide ones. If something ever asks you to
approve an administrator prompt for this module, that is worth being suspicious
about.

A window will open, show what it did, and wait for you to press a key before
closing, so you can actually read the result.

### Why the `.cmd` files exist at all

Double-clicking a `.ps1` file opens it in Notepad rather than running it. That is
how Windows treats PowerShell scripts by default, and it means a folder of
scripts is unusable to anyone who has not been taught the incantation to run
them. The `.cmd` files are small wrappers that run the real script properly.

They also avoid the advice you will find elsewhere. A common instruction is to
run `Set-ExecutionPolicy Unrestricted`, which permanently lowers a machine-wide
security setting to solve a single run. These wrappers pass
`-ExecutionPolicy Bypass` instead, which applies to that one invocation and
changes nothing on your machine.

You can open any of them in Notepad and read exactly what they do. Each one
explains itself in its first few lines.

## Status on this machine

**Applied on 2026-08-26.** Twelve settings were changed; eight were already at
their target; none failed. Before that, the rollback was proved on this machine
rather than assumed: `Test-RoundTrip.ps1` applied every change for real, restored
them, and confirmed all twenty managed settings - plus the shared legacy byte
mask - returned to exactly their starting values. It reported
`restored: 20   skipped: 0   failed: 0`.

To undo everything, from this folder:

```bash
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1
```

### What the safety audit changed

Before this module was allowed near the machine, two independent adversarial
audits read the apply and undo paths line by line and asked one question: after
applying and then restoring, is the machine exactly as it started? Both returned
**gaps found**. The defects they demonstrated have been fixed, and they are
recorded here because a rollback nobody has attacked is only a claim:

- **A failed backup was reported as a success.** The backup function never
  checked that the file was actually written, so on a full, read-only or synced
  folder the apply step would have proceeded believing an undo existed. The write
  is now verified - the file must exist, be a sensible size, and parse back - and
  a failure **aborts before anything is changed**.
- **Running the undo twice re-applied the tweaks.** The snapshot the restore
  script takes of the current state was itself eligible for selection as "the
  most recent backup", so a second undo restored the already-disabled state. The
  default selection now excludes those snapshots.
- **The legacy master gate was restored in the wrong order.** It was always set
  first; that is correct only when restoring it to "on". Restoring it to "off"
  silently discarded the ten writes that followed while reporting each as
  restored. The gate is now opened first and set to its captured value **last**.
- **The undo wrote to whatever registry paths the backup named.** It iterated the
  backup's data rather than a fixed list, so an edited or corrupt file could
  direct writes anywhere. Entries are now checked against the six values this
  module owns, and anything else is ignored and reported.
- **Failed registry writes printed as successes.** Each write is now checked,
  read back, and counted only if it genuinely landed; failures are listed.
- **Settings that could not be read were still written.** The apply path now
  leaves unreadable settings alone, because a value the backup has no record of
  is a value the undo cannot put back.

Two limits are stated rather than fixed. The legacy effects live packed inside a
shared eight-byte preference mask; this module manages ten of its bits and cannot
restore the others, so the mask is captured and **compared**, and any difference
is reported instead of hidden. And `Test-RoundTrip.ps1` can only check the
settings this module knows about - it cannot detect a change to something outside
that list, and says so when it finishes.

## In plain language

When a menu slides open, a tooltip fades into view, a window casts a shadow on
what is behind it, or a panel shows a frosted-glass blur, the computer is doing
arithmetic to draw that. The arithmetic is done by the graphics processor. On many
laptops the graphics processor is not a separate card with its own memory - it is
built into the same chip as the main processor and shares the same memory and the
same battery. The machine this module was written on is one of those. On such a
machine decoration is not free. It competes with the work you actually asked for.

Frosted glass is the expensive one. A blur is not a picture drawn once and kept;
it is recalculated for every frame, for every translucent surface on screen.
Microsoft's own developer documentation says that rendering it "is GPU-intensive,
which can increase device power consumption and shorten battery life", and that
Windows switches it off by itself when a device enters Battery Saver mode. The
same documentation lists blur and its relatives as "not recommended for low end
devices".

Windows has a Performance Options dialog with an "Adjust for best performance"
button, and that button does not reach most of this. Windows has accumulated four
separate systems for drawing effects, built at different times, each with its own
switch. This document calls them layers, and that is all the word means here. The
button reaches only the oldest of the four. This module manages 20 settings spread
across all four:

- **The old effects** - 13 settings. Menu and drop-down-list animation, smooth
  list scrolling, menu and selection fades, tooltip animation and fade, the mouse
  pointer's shadow, drop shadows under windows, gradient title bars, a master
  switch that gates the rest, whether a window's contents are redrawn while you
  drag it, and how long a menu waits before opening. Inherited from Windows XP and
  Vista. This is the part the button controls.
- **Modern app animations** - 2 settings. The movement inside Settings, the Start
  menu and Store apps, and inside applications that are really web pages in a
  frame; plus frosted-glass translucency itself. The animation switch here is also
  what those web-based applications read as the "reduce motion" preference.
- **The desktop shell** - 4 settings. Taskbar button animation, the translucent
  selection rectangle you drag across a file list, the shadows under desktop icon
  labels, and the value that makes the Performance Options dialog report "Custom".
- **The compositor** - 1 setting. The compositor is the part of Windows that
  assembles all the windows into the single picture you see. The setting is Aero
  Peek, the preview of the desktop when you hover the far end of the taskbar.

The compositor itself cannot be switched off on Windows 8 and later. Microsoft
documents that the call an application would use to disable it "will return
success; however, desktop composition is not disabled". Only the amount of work
the compositor is asked to do can be reduced. That is a real limit, not an
omission from these scripts.

### What was measured on this machine

**The figures below are the "before" reading, taken prior to applying.** They come from
`Test-VisualEffects.ps1`, which only reads, and from `Disable-VisualEffects.ps1
-WhatIf`, which prints what it would do and writes nothing. The `backups\` folder
is empty and `backups\original-state.json` does not exist, which is what you would
expected of a module that had not yet been run for real. It has since been
applied - see "Status on this machine" above.

Taken on 2026-08-26: Windows 11 Home, build 26200, Intel i7-1255U, 63.7 GB of RAM,
graphics built into the processor.

One of the four layers - **Modern** - was already entirely at its target before
this module existed. Modern app animations were already off
(`UISettings.AnimationsEnabled` reported False) and so was frosted glass
(`AdvancedEffectsEnabled` False, `EnableTransparency` set to 0). Saying so matters
more than claiming credit for it, and it changes what you should expect: the
single largest saving described on this page was already banked before the module
was written.

Still switched on, in the old-effects layer: gradient window captions, menu fade,
tooltip fade, window drop shadows, redrawing window contents while dragging, and
the master switch for the family - six items. On the shell and compositor side:
taskbar animation, translucent list selection, icon label shadows, Aero Peek, and
`VisualFXSetting`, which was not set at all - five items. A dry run counted those
eleven as the real changes pending.

Separately, the delay before a menu opens measured 400 ms. The script sets it to
zero. That is not a graphics saving; it is 400 ms removed from every menu you
open.

At the moment of measurement `dwm.exe`, the process that composites the desktop,
held about 178 MB of memory, and eighteen web-application processes held about
917 MB between them. Those are readings taken at one instant and they move
between runs. Neither figure is a target: this module makes no claim to reduce
either number, and turning off animations does not free that memory.

### What to expect

Less work per frame, and less power drawn to do it. Menus and tooltips appear
without a fade to wait through, which feels quicker whether or not a stopwatch
agrees.

Two things keep that honest. First, the expensive item - translucency - is already
off on this machine, so what remains here are the cheaper effects, and the gain
from turning them off is correspondingly smaller. On a machine where frosted glass
is still on, that one setting is the significant one. Second, no power measurement
has been taken. The direction of the effect on battery life is documented; the size
of it is not measured here, and this page does not promise a number of minutes.

Everything else you can measure for yourself - see below.

### Measuring it yourself, instead of believing this page

Double-click **7 - Measure what it actually saves**.

It measures your machine with the effects on, then with them off, and prints the
difference. It is allowed to report **no measurable difference**, and if that is
what your hardware shows, that is what it will say. A report that can only ever
produce flattering numbers is not measuring anything.

It has to change settings to do this: there is no way to measure both states
without putting the machine in both states. So it restores the original state,
measures, applies the changes, measures, and repeats. It finishes with the changes
applied and tells you so on the last line. `4 - UNDO everything` still works
afterwards.

Two things it does that a stopwatch and Task Manager cannot:

- **It reports its own noise floor.** It measures the same state twice and shows
  how much the numbers moved when *nothing* changed. Any before-and-after
  difference smaller than that is printed as `within noise` rather than as a
  saving. This is the difference between a measurement and a number.
- **It measures consumption, not a snapshot.** Task Manager shows you what a
  process is doing at the instant you look. This differences a counter that only
  ever counts upwards, across a fixed window, so the figure it reports *is* the
  processor time consumed rather than an estimate of it.

It also opens a window of its own and drives it - menus opening and closing, a
drop-down list, a long list scrolling, a tooltip, minimise and restore, and the
window being dragged across the screen. Those seven operations are not decorative:
each one is driven by a specific setting this module changes. Measuring an idle
desktop alone would miss almost all of the effect, because most of the cost of an
animation is paid while it animates.

Results land in `RESULTS.md` next to this file. That file deliberately records the
processor, graphics chip and Windows build but **not** the machine name or user
name, so it is safe to publish. The raw readings, which do contain those, go to
`measurements\` and are excluded from version control.

Budget about ten minutes, close your browser first, stay on mains power, and leave
the machine alone while it runs.

Some of it you will see. Dragging a window shows a moving outline instead of the
window itself until you let go. Title bars become flat rather than graded. Windows
and the mouse pointer stop casting shadows, which makes overlapping windows
slightly harder to tell apart. Desktop icon labels lose their drop shadow, and that
shadow is there to keep the text legible over a busy wallpaper. Hovering the far
end of the taskbar no longer previews the desktop.

None of this turns a slow machine into a fast one. If the machine is slow for
other reasons, this will not fix those.

## What it will and will not change

| It changes | It does not change |
|---|---|
| The classic effects: menu and drop-down-list animation, smooth list scrolling, menu and selection fades, tooltip animation and fade, cursor shadow, window drop shadows, gradient title bars, and their master switch | Anything belonging to another user account, or to the machine as a whole |
| Whether window contents redraw while you drag a window | Your theme, wallpaper, accent colour, or light/dark mode |
| The menu-open delay, set to 0 ms - unless you pass `-KeepMenuDelay`, or exclude the old-effects layer | Screen resolution, scaling, or refresh rate |
| The animation flag modern apps read, and that web-based apps read as "reduce motion" | Any driver, service, scheduled task or system file |
| `EnableTransparency`, the frosted-glass translucency switch | The compositor itself, which cannot be turned off on Windows 8 and later |
| Taskbar animation, translucent list selection, icon label shadows | Whether an application honours these settings - one that draws its own animations is unaffected, and this module has not surveyed how many do |
| Aero Peek desktop preview | Window minimise and maximise animation, which lives in a setting this module does not manage |
| `VisualFXSetting`, set to 3 so the Performance Options dialog reads "Custom" and agrees with the rest | Anything outside `HKCU` - the part of the registry, Windows' settings database, that holds your own account's settings |

Nothing here needs administrator rights, and none of the scripts asks for any.
Every setting is per-user.

Honest caveats:

- The settings written through the Windows programming interface take effect at
  once, because the write also broadcasts a notice to running applications. The six
  registry values get no such broadcast. The scripts state that the taskbar and
  file-list items apply at your next sign-in, or immediately if you use
  `-RestartExplorer`, which closes any open File Explorer windows. Whether Windows
  picks up `EnableTransparency`, `EnableAeroPeek` or `VisualFXSetting` sooner than
  that has not been measured here.
- An application that draws its own animations without consulting Windows will
  keep drawing them. There is no switch that reaches those.
- Every run writes a new file into `backups\`. Nothing removes old ones.

To see the current state, and then to see exactly what would change, without
changing anything:

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-VisualEffects.ps1
powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -WhatIf
```

Run these from inside this module's folder - `.\` means "in the folder I am
currently in". PowerShell refuses to run script files by default;
`-ExecutionPolicy Bypass` lifts that refusal for that one command only and changes
no setting on your machine. The first command shows the current state of all four
layers. The second prints every change it would make. Neither writes anything -
under `-WhatIf` the disable script does not even write its backup.

Two further options on the disable script: `-Layers` restricts it to some of
`Legacy`, `Modern`, `Shell`, `DWM` (the default is all four), and `-Tag <word>`
folds a label of your choosing into the backup filename.

## If you press Apply more than once

**Nothing bad happens, and that took a fix.**

### In plain language

Pressing *Apply* again when everything is already applied used to write another
backup - a backup of the machine **as it already was**. Since *Undo* restores the
most recent backup, two presses of *Apply* meant *Undo* had nothing useful to go
back to. It would run, say **"restored: 20, failed: 0"**, and change nothing at
all. No error, no warning, just a safety net that had quietly stopped working.

That is fixed at both ends:

- **Apply** now notices there is nothing to do, **deletes the pointless backup it
  just wrote**, tells you why, and stops.
- **Undo** now checks first. If the backup it picked would change nothing, it
  **refuses to run** and points you at *"UNDO back to the original"*, which is
  the one that still works.

You can press Apply as many times as you like. It will keep telling you there is
nothing to do, and it will not damage anything.

If you want to see the state of your own restore points:

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -List
```

Anything useless is marked **DEAD**, with the reason.

### Technical detail

MODULE-STANDARD §16 requires a run that changes nothing to exit **4** and leave
no backup. This module predates that rule and was **the only one of eight**
without it - every other module holds 1-3 backups; this one had accumulated 19.

The nothing-to-do check runs **after** the work, not before it. That is
deliberate: the plan is computed inline with the writes, so a pre-flight check
would be a second copy of that logic and the two would drift. Judging by the
actual result cannot drift from the actual result.

The undo's guard compares the chosen backup against the live machine. The two
are different types - a JSON-parsed backup is `PSCustomObject`, a live reading
is `OrderedDictionary` - so the comparison extracts values shape-agnostically.
The first version of the guard did **not** allow for that, compared `"0"`
against the string `"System.Collections.Specialized.OrderedDictionary"`, found
six phantom differences and failed to fire. Found by instrumenting it rather
than trusting it. One shared function now serves both `-List` and the guard, so
the two cannot disagree about what "the same" means.

Five dead restore points were moved to `backups\_quarantine-poisoned\` - moved,
not deleted, so a wrong classification is recoverable. Recorded in `DEC-01-002`
and `DEC-01-003`.

---

## If you change your mind

One command, no arguments:

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1
```

That puts back the state your machine was in immediately before the last time the
disable script ran, including deleting any registry value that did not exist
before, so you are not left with leftovers.

If you have run the disable script more than once, or you want the machine exactly
as it was before this module was ever used:

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -Original
```

Why that always works: every run of the disable script writes a full record of all
20 settings into `backups\` first. The **first** run additionally writes
`backups\original-state.json`, and that file is never overwritten. This defeats the
classic trap where running a script twice quietly backs up the already-changed
state and destroys the route home. The pristine state is captured once and kept.

The restore script takes its own backup before undoing anything, tagged
`pre-restore`, so changing your mind twice is possible. One consequence to know
about: that pre-restore file is itself the newest backup afterwards, so running the
restore script a second time with no arguments re-applies the disabled state rather
than reaching further back. To go further back, name the file you want with
`-Backup <filename>`, or use `-Original`.

To see every restore point with its date, without changing anything:

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -List
```

`-WhatIf` works on the restore script too, and under it the pre-restore backup is
not written either.

There is also `Test-RoundTrip.ps1`, which proves the rollback on your own machine
rather than asking you to take this page's word for it: it records the state,
applies the changes for real, checks something moved, restores for real, and
compares all 20 settings against the starting state, reporting PASS or FAIL by
name. It makes genuine changes while it runs and asks for confirmation before
starting. On a PASS the net effect is nothing. It HAS been run on this machine,
and it passed: 20 settings restored, 0 skipped, 0 failed.

## Technical detail

Four layers, four mechanisms. **Legacy** effects are USER32 client-side flags read
and written through `SystemParametersInfoW`; the settings table in `_Common.ps1`
pairs each `SPI_GET*` code with its `SPI_SET*` counterpart (menu animation
`0x1002`/`0x1003` through to the master `SPI_GETUIEFFECTS`/`SPI_SETUIEFFECTS`
`0x103E`/`0x103F`), plus `SPI_GET/SETDRAGFULLWINDOWS` (`0x0026`/`0x0025`) and
`SPI_GET/SETMENUSHOWDELAY` (`0x006A`/`0x006B`). **Modern** is
`SPI_GETCLIENTAREAANIMATION`/`SPI_SETCLIENTAREAANIMATION` (`0x1042`/`0x1043`) plus
`EnableTransparency` under
`HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`. **Shell** is
`TaskbarAnimations`, `ListviewAlphaSelect`, `ListviewShadow` under
`HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced`, plus
`VisualFXSetting` under
`HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects`, written
as 3. **DWM** is `EnableAeroPeek` under `HKCU:\Software\Microsoft\Windows\DWM`.
That is 14 values through the API and 6 in the registry - the 20 the backup format
carries. Composition itself is unconditional since Windows 8 and
`DwmEnableComposition` returns success without disabling it, so the module does not
pretend otherwise.

Every SPI **write** passes `fWinIni = SPIF_UPDATEINIFILE | SPIF_SENDCHANGE`
(`0x1 | 0x2`). The first persists the change to the user profile; the second
broadcasts `WM_SETTINGCHANGE` so running applications re-read it without a
sign-out. Omit them and the change is either transient, unannounced, or both.
Reads pass `fWinIni = 0`. The six registry writes go through `New-ItemProperty`
and broadcast nothing.

Reads go through the API rather than the registry deliberately. On this build the
modern animation flag has no standalone registry value; the effective bit lives
inside `UserPreferencesMask`, an undocumented, build-dependent block of eight
bytes, measured here as `90 12 07 80 10 00 00 00`. The registry is therefore not
an honest source for it.
An earlier version of this project's probe inferred state from the absence of a
`HKCU\Control Panel\Accessibility\ClientAreaAnimation` value and reported modern
animations as "unset = on by default". That was wrong; WinRT `UISettings`
contradicted it, and the API showed them already off. The mistake is recorded here
rather than quietly corrected.

`_Common.ps1` declares three P/Invoke entries against the same export - `SpiGet`,
`SpiSetPv`, `SpiSetUi` - because `SystemParametersInfo` uses three different
conventions:

| Action | Convention |
|---|---|
| `SPI_GET*` | `pvParam` is a **pointer** to receive the value (`ref int`) |
| `SPI_SET*`, UI-effects family | `pvParam` **is** the value, cast to `PVOID` |
| `SPI_SETDRAGFULLWINDOWS`, `SPI_SETMENUSHOWDELAY` | the value travels in `uiParam`; `pvParam` is `NULL` |

Strictly, only two distinct marshalling signatures are needed: `SpiSetPv` and
`SpiSetUi` are declared identically (`uint, uint, IntPtr, uint`) and the third
convention is expressed in the wrappers - `Set-VfxSpiValue` puts the value in
`pvParam`, `Set-VfxSpiUiParam` puts it in `uiParam` and passes `IntPtr::Zero`. The
declarations are kept separate so the call site names which convention it means.

Getting this wrong is not loud. The call returns `true` and does nothing, so a
script that mixes them up appears to succeed while changing nothing. That is why
`Disable-VisualEffects.ps1` finishes by re-reading state from the API rather than
trusting the boolean each call returned. Note the scope of that check: it re-reads
the SPI effects, drag-full-windows, the menu delay and the two `UISettings` flags,
and reports anything still on. It does not re-verify the six registry values -
those are written with `-ErrorAction Stop` inside a `try`/`catch`, where a genuine
failure does surface.

Ordering matters and is asymmetric. When disabling, the master `SPI_SETUIEFFECTS`
gate is written **last**; when restoring, it is written **first**. The module's
working assumption is that with the gate off USER32 stops evaluating the individual
legacy flags, so setting them under a closed gate would have no observable effect.
That ordering rule is the module's own engineering judgement, not a vendor-cited
fact.

`-Layers` gates more than the effect list: drag-full-windows and the menu-show
delay both sit inside the `Legacy` branch, so `-Layers Modern,Shell` leaves the
menu delay at 400 ms whether or not `-KeepMenuDelay` is passed. Failures do not
abort a run - `$ErrorActionPreference` is `Continue` and the closing summary
reports `changed`, `already as wanted` and `failed` counts. `-RestartExplorer`
force-terminates `explorer.exe`, waits two seconds, and starts it again if it has
not come back on its own; open File Explorer windows and their state are lost, and
the desktop is absent for those seconds.

`Restore-VfxState` skips any setting whose captured value was `null`, so a setting
that was unreadable at capture time is left alone rather than guessed at. A
registry value recorded as `null` or empty is **removed**, not written as zero.

**Citation honesty.** The Win32 API *reference* pages are not part of this
project's offline Microsoft documentation corpus. The calling conventions above,
the write-order rule, the mapping from these two settings to
`UISettings.AnimationsEnabled` and `AdvancedEffectsEnabled`, the claim that
Chromium-based applications surface the animation flag to page content as
`prefers-reduced-motion`, and the meaning of `VisualFXSetting = 3` are therefore
stated as engineering observation, verifiable by running `Test-VisualEffects.ps1`
before and after a change - not as vendor-cited fact. What *is* vendor-documented
is that the client-area animation parameter exists and governs UI animations, that
translucency is GPU-expensive and is among the effects not recommended for low-end
devices, that composition cannot be disabled, and that applications are expected to
respect the `UISettings` flags.

`Set-StrictMode` is deliberately not set in `_Common.ps1`: restore paths read state
objects deserialised from JSON, where a missing property must degrade gracefully. A
rollback that throws on an unexpected field is worse than useless.

## References (Microsoft Official Documentation)

All citations below are sourced directly from the **Microsoft Learn** knowledge base and the official Microsoft Win32/UWP developer documentation. They are formatted to academic standards (APA 7 adapted for offline corpus tracking) to ensure exact traceability.

- **R-63** - Microsoft. (n.d.). *Acrylic material*. Microsoft Learn. Retrieved from https://learn.microsoft.com/en-us/windows/apps/design/style/acrylic : "Rendering acrylic surfaces is GPU-intensive, which can increase device power consumption and shorten battery life. Acrylic effects are automatically disabled when a device enters Battery Saver mode."

- **R-66** - Microsoft. (n.d.). *Tailoring effects & experiences using Composition*. Microsoft Learn. Retrieved from https://learn.microsoft.com/en-us/windows/apps/develop/composition/composition-tailoring : Gaussian Blur, Shadow Mask, BackDropBrush, HostBackDropBrush and Layer Visual are listed as having "high performance impact" and "are not recommended for low end devices".

- **R-67** - Microsoft. (n.d.). *Tailoring effects & experiences using Composition*. Microsoft Learn. Retrieved from https://learn.microsoft.com/en-us/windows/apps/develop/composition/composition-tailoring: 
  Applications should listen and respond to UISettings.AnimationsEnabled.

- **R-68** - Microsoft. (n.d.). *Tailoring effects & experiences using Composition*. Microsoft Learn. Retrieved from https://learn.microsoft.com/en-us/windows/apps/develop/composition/composition-tailoring: 
  Applications need to respond to UISettings.AdvancedEffectsEnabled for custom effects.

- **R-69** - Microsoft. (n.d.). *Client Area Animation*. Microsoft Learn. Retrieved from https://learn.microsoft.com/en-us/windows/win32/WinAuto/client-area-animation : The client area animation parameter "indicates whether the user wants to disable animations in UI elements".

- **R-70** - Microsoft. (n.d.). *Client Area Animation*. Microsoft Learn. Retrieved from https://learn.microsoft.com/en-us/windows/win32/winauto/client-area-animation: 
  Applications use SPI_GETCLIENTAREAANIMATION and SPI_SETCLIENTAREAANIMATION with SystemParametersInfo to turn client area animations on or off.

- **R-71** - Microsoft. (n.d.). *Desktop Window Manager is always ON*. Microsoft Learn. Retrieved from https://learn.microsoft.com/en-us/windows/win32/w8cookbook/desktop-window-manager-is-always-on : "In Windows 8, Desktop Window Manager (DWM) is always ON and cannot be disabled by end users and apps."

- **R-72** - Microsoft. (n.d.). *Desktop Window Manager is always ON*. Microsoft Learn. Retrieved from https://learn.microsoft.com/en-us/windows/win32/w8cookbook/desktop-window-manager-is-always-on: 
  "Apps cannot use DwmEnableComposition to disable desktop composition. In order to maintain backward compatibility, a call to this API will return success; however, desktop composition is not disabled".

- **R-73** - Microsoft. (n.d.). *DWM Messages*. Microsoft Learn. Retrieved from https://learn.microsoft.com/en-us/windows/win32/dwm/dwm-messages : "As of Windows 8, DWM composition is always enabled".

R-numbers index the project's citation table in ..\..\FINDINGS.md, which ..\..\tools\Verify-Citations.ps1 checks mechanically against the local documentation corpus. The file and line numbers above are reproduced from that table; if this page and FINDINGS.md ever disagree, FINDINGS.md and the corpus are the authority, not this file.

Everything stated about the state of *this* machine - which layers were already off, which six legacy effects remained, the UserPreferencesMask value, the process memory readings - is this project's own measurement, recorded as **M-05**, with the raw output kept at ..\..\evidence\2026-08-26_07-31-11_baseline\visual-effects.txt.

