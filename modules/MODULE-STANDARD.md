# MODULE-STANDARD.md

**The convention every module in this project must follow.**

Status: normative. Version 1, 2026-08-26. Derived from the one module that
exists, `modules/01-visual-effects`, by reading its four scripts and writing down
the rules they embody.

---

## 0. What this document is, and how to read it

### 0.1 In plain language

This project is a folder of scripts that change settings on a Windows 11 machine
— what runs in the background, what gets sent to Microsoft, how much work the
graphics chip is asked to do. There is one such set of scripts so far. There will
be roughly a dozen.

A dozen sets of scripts written a dozen different ways is a trap. You would have
to learn each one separately, and worse, you would have no way of knowing whether
the fifth one was as careful about letting you undo it as the first one was. So
this document fixes the shape. Once you have learned one module you have learned
all of them: the same three scripts with the same three names, the same undo
button, the same two documents, the same promises about backups.

The rules are written as requirements, not suggestions, because a module that
half-follows them is more dangerous than one that follows none — you would trust
it out of habit and it would not deserve the trust.

### 0.2 In technical terms

This is a specification for the layout, interface, safety contract, documentation
and evidence requirements of a change module. It uses **MUST**, **MUST NOT**,
**SHOULD** and **MAY** in the ordinary RFC sense. **MUST** items are conformance
requirements; a module failing any of them is not finished, regardless of whether
its logic is correct.

The reference implementation is `modules/01-visual-effects`. Where this document
and that module disagree, this document wins and the module is a defect to be
fixed (see §12 for the defects known at the time of writing).

### 0.3 The dual-track rule (applies to this document and every document a module ships)

Every document carries **two parallel explanations of the same material**, written
together, neither derived from the other by deletion:

- **The human track.** Plain language, no assumed knowledge, written from the
  point of view of the person the change happens to. It answers "what does this
  do to me, or for me?" with concrete consequences.
- **The developer track.** Mechanisms, exact registry paths, API names,
  parameters, trade-offs and failure modes, in correct terminology. It assumes
  sysadmin literacy but not familiarity with this project.

The human track is **not** a simplification. It is a translation. It carries the
same facts — including the uncomfortable ones — in a different vocabulary. It
MUST NOT omit a consequence because the consequence is complicated, and it MUST
NOT patronise, moralise or repeat warnings for emphasis. Assume the reader is
intelligent; assume only that the jargon is new to them.

Rules that bind both tracks:

- British spelling throughout: behaviour, colour, recognise, analyse, summarise,
  minimise, prioritise.
- No marketing language. No exclamation marks. Do not write "simply", "just",
  "easily", "blazing", "powerful", or "one click and you're done".
- Every technical term that must appear in the human track is explained in place,
  in the same sentence or the next one.
- Analogies MUST be accurate. A decorative analogy that misdescribes the
  mechanism is worse than no analogy. If you cannot find a true one, describe the
  mechanism plainly instead.
- The stated audience includes non-technical people running old, low-end
  hardware. Assume the reader may be on a machine where a mistake matters and a
  reinstall is a genuine hardship.

---

## 1. Folder layout and naming

### 1.1 In plain language

Every module lives in its own folder under `modules/`, numbered so the folders
sort in a sensible order, and named after what it does. Inside, the file names
tell you what each file is for before you open it: one that only looks, one that
changes things, one that puts them back.

### 1.2 The layout

```
modules/
  MODULE-STANDARD.md            this file
  NN-topic-name/
    _Common.ps1                 shared core: settings table, state capture,
                                backup and restore primitives. Executes nothing.
    Test-<Topic>.ps1            read-only. Shows current state. Changes nothing.
    <Verb>-<Topic>.ps1          applies the change. -WhatIf mandatory.
    Restore-<Topic>.ps1         the rollback. Works with NO arguments.
    README.md                   dual-track, human track first
    HOWTO.md                    every capability, every parameter, worked examples
    backups/                    state files written by the scripts
      original-state.json       written once, never overwritten
      state_<stamp>[_<tag>].json
```

### 1.3 Naming rules

| Item | Rule |
|---|---|
| Folder | `NN-topic-name`. `NN` is a zero-padded two-digit number, allocated from the register in §1.4 and **never reused**. `topic-name` is lowercase kebab-case, a noun phrase describing the subject, not the action. |
| Read-only script | `Test-<Topic>.ps1`. `<Topic>` is PascalCase, singular or plural as reads naturally, and identical across the three scripts of the module. |
| Applying script | `<ApprovedVerb>-<Topic>.ps1` using a PowerShell approved verb that states the direction of the change: `Disable-`, `Remove-`, `Set-`, `Harden-`, `Reduce-`. |
| Rollback script | `Restore-<Topic>.ps1`. Always this exact prefix, in every module, without exception. |
| Shared core | `_Common.ps1`. The leading underscore marks a file that is dot-sourced and never run directly. |
| Backups folder | `backups/`, inside the module folder, created on demand. |

Module `01-visual-effects` therefore ships `Test-VisualEffects.ps1`,
`Disable-VisualEffects.ps1`, `Restore-VisualEffects.ps1` and `_Common.ps1`.

Every script MUST resolve its own paths from its own location, so that it works
regardless of the caller's working directory:

```powershell
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')
$backupDir = Join-Path $here 'backups'
```

A script MUST NOT depend on a relative path like `..\_backups\` reached from the
current directory, and MUST NOT write outside its own module folder except where
§8 requires an evidence artifact.

### 1.4 Module number register

Numbers are allocated here, in order, and appended. A number is never reused even
if its module is deleted.

| NN | Folder | Subject | State |
|---|---|---|---|
| 01 | `01-visual-effects` | animations, fades, shadows, translucency across four layers | **finished and applied.** Audited, round trip proved, benefit measured |
| 02 | `02-update-distribution` | Delivery Optimization peer sharing, port 7680, inbound firewall rules | **built, not shipped.** No adversarial audit; rollback never executed (needs elevation) |
| 03 | `03-copilot` | the Copilot app, the 1.3 GB Program Files install, its LocalSystem service | **finished and executed 2026-08-26.** Two tiers: settings proved reversible; removals executed, recorded as not-restorable with the route back. Audited: 14 findings, all fixed |
| 04 | `04-recommendations` | suggestions, tips, personalised content, Start recommendations | **built, not shipped.** Round trip proved and comparison shown falsifiable; no adversarial audit |
| 05+ | — | unallocated | — |

Candidate subjects not yet allocated a number: services hardening, telemetry
scheduled tasks, Defender posture, and the ownership/update-cache tools. Earlier
working scripts for several of these were **withdrawn** on 2026-08-26 and their
documentation preserved in `_withdrawn-pending-audit/`. They predate this standard
and do not conform to it. Bringing one back means rebuilding it to this
specification, not moving the file.

**Two modules are per-user and two are not, and it shows.** Modules 01 and 04
touch only `HKEY_CURRENT_USER`, so they could be built, applied, undone and proved
end to end without anyone approving an elevation prompt — and both are further
along as a direct result. Modules 02 and 03 need administrator rights for their
central settings, and both are stalled at exactly the step that requires them.
That is not a coincidence to design around: prefer per-user mechanisms where they
achieve the same outcome, and expect a machine-wide module to take longer to
finish because its rollback is harder to demonstrate.

---

## 2. The mandatory trio

### 2.1 In plain language

Every module has exactly three scripts you run, and they divide the work the way
a careful person would:

1. **The one that only looks.** It reads the current settings and prints them. It
   cannot change anything, so you can run it whenever you like, including when
   you have no idea what state the machine is in.
2. **The one that changes things.** Before it touches anything it writes down the
   current state to a file. It can be asked to show you what it would do without
   doing it.
3. **The undo button.** A separate file, with `Restore-` at the front of its
   name, which you run with no arguments at all.

The undo is a separate file rather than an option on the change script for a
specific reason. Someone reaching for the undo is usually worried and often in a
hurry — something looks wrong, the machine behaves oddly, a colleague needs the
laptop back in ten minutes. That person must not have to read documentation to
find out what to type. They should be able to look in the folder, see a file with
"Restore" in the name, run it, and have it do the sensible thing. Making the
rollback a flag on the change script (`-Restore`, say) buries it: you have to
already know it exists, know its spelling, and know what to pass it. The whole
point of a rollback is that it works when you are least equipped to look things
up.

### 2.2 Requirements

**R2.1** A module MUST contain all three scripts. A module with no `Test-` script
is not finished. A module with no `Restore-` script MUST NOT be run at all.

**R2.2** The `Test-` script MUST be read-only. It MUST NOT write to the registry,
call any setting API, start or stop a process, or require elevation. It MAY write
a JSON snapshot into `backups/` when passed `-Json`, and that snapshot MUST be
named `snapshot_<stamp>.json` so it is distinguishable from a real backup.

**R2.3** The applying script MUST NOT be the rollback. It MUST NOT accept a
`-Restore` parameter. The rollback lives in `Restore-<Topic>.ps1` and nowhere
else.

**R2.4** `Restore-<Topic>.ps1` MUST do the correct thing when invoked with no
arguments whatsoever. "The correct thing" is: restore the most recent
timestamped backup, which is the state the machine was in immediately before the
last time the applying script ran.

**R2.5** The applying script MUST end its output by printing the exact command
that undoes it, in full, copy-pasteable. Module 01 prints:

```
  TO UNDO EVERYTHING:
     powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1
```

**R2.6** The `Restore-` script MUST support at minimum:

| Parameter | Behaviour |
|---|---|
| *(none)* | restore the newest `state_*.json` |
| `-Original` | restore `backups/original-state.json`, the pristine pre-project state |
| `-Backup <path>` | restore one named file; MUST accept both a full path and a bare filename resolved inside `backups/` |
| `-List` | print every available restore point with its date and a short summary, then stop, changing nothing |
| `-WhatIf` | print exactly what would be put back, changing nothing |

**R2.7** All three scripts MUST read and write through the same code in
`_Common.ps1`. The backup writer and the restore applier MUST derive from the
same settings table, so that adding a setting to the module cannot leave the
rollback one setting behind. This is the single most important structural rule in
the standard: **drift between what is changed and what is restorable is the
failure mode this layout exists to prevent.**

**R2.8** A module SHOULD ship `Test-SafetyLogic.ps1`: a read-only, unelevated
self-test of the logic that decides **whether** to write anything, exercised with
input the module would never meet in normal use.

The round-trip test proves the writes work by performing them. It cannot prove
the module refuses a corrupt backup, or a backup naming registry paths the module
does not own, or that a failed backup is reported as failed — because those
situations cannot be produced by using the module correctly, which is precisely
why they are never found by using it correctly.

Minimum coverage, each of which corresponds to a defect found in a real module
here:

- a file that is merely JSON-shaped is rejected as a state file
- a backup entry naming a setting outside the allow-list is ignored, not written
- an unwritable backup destination returns failure, not a path
- only the apply path can create `original-state.json` (R4.4a)
- pre-restore snapshots are excluded from restore candidates
- where the module has an absent-versus-zero distinction, it survives JSON

It MUST exit non-zero on any failure so it can gate a commit.

**R2.8a** The test harness itself MUST NOT be able to skip a check silently.

Two specific requirements, both of which come from the harness in this project
producing a false pass:

- The assertion helper's condition parameter MUST NOT be typed `[bool]`. A value
  that cannot be coerced then fails at **parameter binding**, before the helper
  runs, so the assertion is recorded neither as a pass nor as a failure. Type it
  `[object]` and coerce inside a `try`/`catch`, counting a non-boolean as a
  failure.
- The run MUST wrap its checks in a `catch` that records a failure. An exception
  part-way through means everything after it did not execute, and a summary of
  "0 failed" in that situation is a lie with a green tick on it.

Module 01's self-test reported **"37 passed, 0 failed"** while two checks threw at
parameter binding and never ran. After the fix the same file reports 40. A
harness that can quietly not run a test is worse than no harness, because the
absence of a harness at least does not produce confidence.

**R2.9** A round-trip test that moved **nothing** MUST report `INCONCLUSIVE`, not
`PASS`.

If every setting was already at the value the apply script wanted, then it
changed nothing, so the restore reversed nothing, so the comparison passed
trivially. Both ends of a journey of zero distance are the same place. That is
not evidence the undo works, and printing `PASS` there hands the reader
reassurance the test did not earn.

The message MUST say how to get a real test — restore to the original state
first, then run it again.

*(Found by running module 01's round-trip on an already-applied machine. It
reported `PASS - 0 setting(s) were changed and all 0 came back`, which is true,
and worthless, and looks exactly like a real pass in a log.)*

---

## 3. The shared core: `_Common.ps1`

### 3.1 In plain language

The three scripts share one file that holds the list of settings the module deals
with, plus the code that reads them, saves them and puts them back. Keeping that
list in one place is what guarantees that anything the module can switch off, it
can also switch back on. If the list lived in two files they would eventually
disagree, and the disagreement would only surface on the day someone needed the
undo to work.

### 3.2 Requirements

**R3.1** `_Common.ps1` MUST execute nothing on its own. It defines a settings
table and functions; it produces no output and takes no action when dot-sourced.

**R3.2** The settings the module manages MUST be declared **once**, as data, in an
ordered table. Module 01 uses two: `$script:VfxEffects` (API-driven settings) and
`$script:VfxRegistry` (registry-driven ones). Every table row MUST carry, at
minimum:

- how to read the setting,
- how to write it,
- which layer or category it belongs to (for scope selection, §6.3),
- the target value when the module applies its change,
- a plain-English description, in the human track's vocabulary, used verbatim in
  console output.

Module 01's registry rows are the pattern:

```powershell
@{ Key='HKCU:\...\Explorer\Advanced'; Name='TaskbarAnimations'; Layer='Shell';
   Target=0; Desc='taskbar buttons animate' }
```

**R3.3** Function names MUST be prefixed with a short module tag so that two
modules dot-sourced into one PowerShell session cannot collide:
`Get-VfxState`, `Save-VfxBackup`, `Restore-VfxState`, `Get-VfxBackups`. Use a
three- or four-letter tag derived from the module name.

**R3.4** Any type defined with `Add-Type` MUST be guarded, because defining the
same type twice in one session throws:

```powershell
if (-not ('VfxNative.User32' -as [type])) { Add-Type -Namespace VfxNative ... }
```

**R3.5** `Set-StrictMode` MUST NOT be enabled in code paths that read state
objects deserialised from JSON. A restore reads files written by older versions
of the module; a missing property MUST degrade gracefully rather than throw. A
rollback script that fails on an unexpected field is worse than useless. Module
01 states this in a comment at the top of `_Common.ps1` and the rule is inherited
by every module.

**R3.6** JSON MUST be written with `Set-Content -Encoding UTF8` and read with
`Get-Content -Raw -Encoding UTF8`. Windows PowerShell 5.1 otherwise reads a
BOM-less UTF-8 file as ANSI, which corrupts non-ASCII characters silently.

**R3.7** State capture MUST read from the **authoritative** source for each
setting, not from a source that merely correlates with it. Module 01 records why:
an earlier audit script inferred the modern-animation setting from the registry
and reported it backwards, because on this build the value is packed into an
undocumented byte block (`UserPreferencesMask`) with no standalone registry
value. Asking the API that applications themselves consult was the only honest
read. Where the authoritative source is expensive or awkward, use it anyway and
say so in the README.

**R3.8** Where a setting family has a **master gate** — one switch that
suppresses a whole group — the ordering MUST be explicit and commented: the gate
is written **last** when disabling (so the individual writes are not swallowed)
and **first** when restoring (so the individual restores take effect under it).
Module 01 does this with `SPI_SETUIEFFECTS`.

---

## 4. The backup contract

### 4.1 In plain language

Four promises. All of them are mechanical properties of the code, not intentions.

**One: nothing changes before the current state is written down.** The change
script's first action is to record every setting it knows about — not only the
ones it is about to alter — into a timestamped file in `backups/`.

**Two: the very first backup is kept forever.** The first time you run the change
script, it also writes `original-state.json`, a copy of how your machine was
before this module had ever touched it. That file is written once and is never
overwritten, no matter how many times you run anything.

This defeats a specific and common trap. Imagine backups that overwrite each
other. You run the change script and it saves your original settings. A week
later you run it again — perhaps to include a layer you skipped the first time —
and it dutifully saves the current state, which is the state it created last
week. Your original settings are gone. The route home has been paved over by the
thing you wanted to escape. The write-once original file means that cannot happen
here: `Restore-<Topic>.ps1 -Original` always leads back to the machine as it was.

**Three: undoing is itself undoable.** The restore script takes its own backup —
tagged `pre-restore` — before it puts anything back. If you restore and decide
you preferred the changed state, that state is still on disk.

**Four: restoring removes what was not there.** If a setting did not exist before
the module ran, restoring deletes it rather than setting it to zero. "Zero" and
"absent" are not the same thing to Windows, and being left with leftovers is a
form of not being put back.

### 4.2 Requirements

**R4.1** The applying script MUST call the backup writer **before** its first
change, and MUST print the path of the file it wrote.

**R4.2** A backup MUST capture the **complete** state of every setting in the
module's tables, not only the subset being changed on this run. A run scoped to
one layer still backs up all layers. Module 01 backs up all 20 settings on every
run regardless of `-Layers`.

**R4.3** A backup file MUST contain, alongside the settings: capture timestamp in
UTC ISO-8601, machine name, username, and OS build. Module 01's envelope:

```powershell
[ordered]@{
    capturedUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    host        = $env:COMPUTERNAME
    user        = $env:USERNAME
    osBuild     = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    spi = ...; registry = ...; uiSettings = ...
}
```

**R4.4** `backups/original-state.json` MUST NOT be overwritten, ever, by any
script in the module. The implementation is a bare existence test, and it MUST
NOT be defeatable by a `-Force` parameter, because the whole value of the file is
that no flag can destroy it.

**R4.4a** `original-state.json` MUST only be written by a script that is **about
to change something**, from the reading it took **beforehand**. The backup writer
MUST gate it behind an explicit switch — `-RecordAsOriginal` — and only the
applying script may pass it.

```powershell
# in the backup writer
param([string]$BackupDir, [string]$Tag = '', [switch]$RecordAsOriginal)
...
if ($RecordAsOriginal) {
    $original = Join-Path $BackupDir 'original-state.json'
    if (-not (Test-Path $original)) {
        $state | ConvertTo-Json -Depth 6 | Set-Content -Path $original -Encoding UTF8
    }
}

# in the applying script - the only caller entitled to pass it
$backupPath = Save-XxxBackup -BackupDir $backupDir -Tag $Tag -RecordAsOriginal
```

**This was a real defect in modules 01 and 02, fixed 2026-08-26, and R4.4 alone
did not prevent it.** R4.5 requires the restore script to take a `pre-restore`
backup. That call went through the same writer, which created
`original-state.json` whenever none existed — recording the **current** state as
"original". Since the file is then never overwritten, a machine that had already
been modified had "before any of this" permanently defined as "after all of
this", and `-Original` restored to the applied state forever, with nothing in its
output to reveal it.

Module 01's HOWTO had *documented* this as a known consequence for weeks.
Documenting a hazard is not fixing it, and a repository that lists its own traps
instead of closing them is doing the easier half of the job.

**R4.4b** Where `original-state.json` does not exist, `-Original` MUST say so and
stop. It MUST NOT fall back to another backup. A silent fallback is exactly the
failure R4.4a describes, arrived at from the other direction.

**R4.5** The restore script MUST take its own backup, tagged `pre-restore`,
before applying anything, and MUST skip that backup under `-WhatIf`.

**R4.6** Restoring MUST **delete** any registry value that was absent when the
backup was taken, rather than writing a zero or leaving it in place:

```powershell
if ($null -eq $val -or "$val" -eq '') {
    Remove-ItemProperty -Path $key -Name $name -ErrorAction SilentlyContinue
    Write-Host ("  {0,-28} -> removed (was not set originally)" -f $name)
}
```

**R4.7** Restoring MUST recreate a registry key that has since been deleted
(`New-Item -Path $key -Force`) before writing a value into it.

**R4.8** Backup filenames MUST be `state_yyyy-MM-dd_HH-mm-ss.json`, with an
optional `_<tag>` suffix when `-Tag` is supplied. The `pre-restore` backups use
this same form, which means they appear in `-List` and can themselves be
restored.

**R4.9** Backups MUST NOT be pruned, rotated or deleted automatically. They are
small JSON files. Deleting a user's route home to save kilobytes is not a
trade-off this project makes.

**R4.10** If a module's change is **not** fully reversible by replaying a state
file — an uninstalled package, a deleted file, a service binary removed — the
module MUST say so explicitly in both tracks of its README, name precisely which
parts are irreversible, and state what would be needed to recover them. A module
MUST NOT present a partial rollback as a complete one.

---

## 5. Documentation requirements

### 5.1 In plain language

Two documents ship with every module, and they have different jobs.

`README.md` answers "what is this, what does it do to my machine, and should I
run it?" It leads with the human track: what changes, what you will notice, what
it will not fix, what might break. The technical explanation follows in the same
document, so a developer reading it top to bottom gets the plain account first
and then the mechanisms — which is the right order for anyone, not a concession.

`HOWTO.md` answers "how do I actually use this?" Every script, every parameter,
and a worked example for each — the literal command line, and what it prints.

Writing the plain-language version is not a courtesy that comes after the real
work. It is a form of rigour. Explaining a mechanism without jargon forces you to
know what it actually does; vagueness that hides comfortably behind
`SPI_SETCLIENTAREAANIMATION` becomes visible the moment you have to say it in
ordinary words. Several errors in this project were caught that way.

### 5.2 `README.md` — required sections, in order

**R5.1** `README.md` MUST exist in the module folder and MUST open with the human
track. Required sections:

1. **Title** — the subject, in ordinary words.
2. **In plain language** — what the module changes and what the reader will
   notice, in concrete terms. What it does for them; what it costs them.
3. **What we found on this machine** — the measured starting state, including
   anything that was **already** done. Claiming credit for a setting that was
   already off is a form of dishonesty this project rejects.
4. **What this will not do** — the honest limits. What is out of reach, what
   cannot be guaranteed, what a reasonable person might expect that will not
   happen.
5. **What might break** — the realistic failure modes, named specifically.
6. **Technical detail** — mechanisms, exact paths, API names, ordering
   constraints, the traps.
7. **Errors worth recording** — any place an earlier version of this module, or
   this project, got it wrong. Include the wrong answer, why it was believable,
   and how it was corrected.
8. **Grounding** — the citations, per §8.
9. **Honest limits** — what the documentation corpus does *not* support, stated
   plainly rather than left implicit.

**R5.2** The README MUST state whether the module needs administrator rights, and
if it does not, MUST say so positively rather than staying silent. Module 01:
*"This script is per-user. It needs no administrator rights and asks for none; it
touches only your own settings, not the machine's."*

**R5.3** The README MUST record the date and machine of the measurements it
quotes. Measurements from another machine, or of unknown vintage, MUST NOT be
presented as this machine's state.

### 5.3 `HOWTO.md` — required content

**R5.4** `HOWTO.md` MUST document **every** capability of **every** script in the
module. A parameter that exists in code and not in HOWTO.md is a defect.

**R5.5** For each script, HOWTO.md MUST provide:

- one sentence on what it does and whether it changes anything;
- a table of every parameter: name, type, default, and what it does in plain
  language;
- **a worked example per capability** — the literal command line, and a
  description or excerpt of what it prints;
- the expected exit behaviour when there is nothing to do.

**R5.6** HOWTO.md MUST open with the shortest useful sequence, so a reader who
stops after ten lines still does the right thing. For module 01 that is: run the
`Test-` script, run the applying script with `-WhatIf`, run it for real, and the
one-line undo.

**R5.7** Command lines in documentation MUST be complete and copy-pasteable,
including the execution-policy prefix used throughout this project:

```
powershell -ExecutionPolicy Bypass -File .\Test-VisualEffects.ps1
```

**R5.8** Both documents MUST follow the dual-track and language rules in §0.3.
This includes British spelling and the ban on "simply" and "just".

### 5.4 Comment-based help

**R5.9** Every script MUST carry a PowerShell comment-based help block with
`.SYNOPSIS`, `.DESCRIPTION`, a `.PARAMETER` entry for every parameter, and at
least one `.EXAMPLE` per capability. The help block is written in the human track
— it is what `Get-Help` shows, and it is often the only documentation a person
reads. Module 01's `Disable-VisualEffects.ps1` carries four examples and a SAFETY
block inside `.DESCRIPTION`; treat that as the floor.

---

## 6. Script requirements

### 6.1 In plain language

Rules the code must obey so the scripts behave predictably.

- Anything that changes a setting must be able to show you what it *would* do,
  without doing it.
- After making a change, the script must go and read the setting back to see
  whether it actually took. Assuming a write worked because it returned without
  complaining is how silent failures survive.
- When there is nothing to do, the script says so in a sentence that explains
  why, and stops. It does not print an error, and it does not print nothing.
- No script asks for administrator rights unless it genuinely needs them. Most
  of these settings belong to your user account, not the machine, and a UAC
  prompt that is not necessary teaches you to click through the ones that are.
- The preview mode must never trigger a UAC prompt. Previewing is looking, and
  looking should not require permission.

### 6.2 `-WhatIf`

**R6.1** Every script that changes state MUST declare
`[CmdletBinding(SupportsShouldProcess = $true)]` and MUST gate every mutating
operation behind `$PSCmdlet.ShouldProcess(...)` or an explicit
`if (-not $WhatIfPreference)` test.

**R6.2** `-WhatIf` MUST cover the backup write as well as the changes, and MUST
say where the backup *would* go:

```powershell
if ($PSCmdlet.ShouldProcess($backupDir, 'write a full backup of all 20 settings')) {
    $backupPath = Save-VfxBackup -BackupDir $backupDir -Tag $Tag
    Write-Host "  backup written           : $backupPath"
} else {
    Write-Host "  backup would be written to: $backupDir"
}
```

**R6.3** `-WhatIf` output MUST be readable. Do not perform work under `-WhatIf`
that makes PowerShell narrate module autoloading and bury the preview. Module 01
reads the OS build from the registry rather than `Get-CimInstance` for exactly
this reason, and records why in a comment.

**R6.4** `-WhatIf` MUST report a count of what would change, distinguishable from
a real run's summary. Module 01: *"11 settings WOULD be restored. Nothing was
changed."*

### 6.3 Scope selection

**R6.5** Where a module addresses distinct categories, it SHOULD expose a
validated scope parameter defaulting to everything, so a cautious user can
proceed one category at a time:

```powershell
[ValidateSet('Legacy','Modern','Shell','DWM','All')]
[string[]]$Layers = @('All')
```

**R6.6** Scoping MUST affect only what is **changed**, never what is **backed
up** (see R4.2), and the chosen scope MUST be echoed in the header output.

**R6.7** A parameter that suppresses one specific change SHOULD be named for what
it preserves, not what it skips: `-KeepMenuDelay`, not `-NoMenuDelay`.

### 6.4 Verification

**R6.8** After applying, a script MUST re-read state through the same reader the
`Test-` script uses and report what is genuinely in effect. It MUST NOT report
success on the strength of the write having returned. Some Windows APIs return
success while doing nothing when called with the wrong convention; a re-read is
the only thing that catches this.

**R6.9** Verification MUST be skipped under `-WhatIf` and MUST name itself
honestly in the output:

```
  verification (re-read from the API, not from what we just wrote):
    every targeted effect reads back as off
```

**R6.10** Anything that did not take effect MUST be listed by name under a
heading a worried reader will recognise, such as `STILL ON:`.

**R6.11** The final summary line MUST report three counts separately: changed,
already as wanted, failed. Conflating "already correct" with "changed" inflates
the apparent effect of the module and is prohibited.

### 6.5 Graceful no-op

**R6.12** When there is nothing to do, a script MUST explain **why** in ordinary
language and return cleanly. It MUST NOT throw, MUST NOT emit a red error, and
MUST NOT exit silently. The pattern from `Restore-VisualEffects.ps1`:

```
  Nothing to restore: no backups exist in
    ...\modules\01-visual-effects\backups
  That means Disable-VisualEffects.ps1 has not been run from this folder,
  so there is nothing this script needs to undo.
```

That output tells the reader what was looked for, where, what its absence
implies, and that no action is needed. All four are required.

**R6.13** Per-setting no-ops MUST be reported too, distinguished from changes:
`already off`, `already set`, `already 0`.

### 6.6 Elevation

**R6.14** A module MUST NOT request administrator rights unless it genuinely
writes outside the user's own hive or otherwise requires them. Per-user modules —
HKCU, per-user API settings — MUST state in both README and `.DESCRIPTION` that
no elevation is needed or asked for.

**R6.15** Where elevation **is** required, the script MUST self-elevate rather
than failing with an instruction, so it works when double-clicked or run from a
non-elevated shell. The project's established pattern relaunches with parameters
preserved:

```powershell
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
# -WhatIf must preview WITHOUT triggering UAC; only a real run self-elevates.
if ((-not $isAdmin) -and (-not $WhatIfPreference)) {
    $relaunch = @('-NoProfile','-ExecutionPolicy','Bypass','-NoExit','-File',('"{0}"' -f $MyInvocation.MyCommand.Path))
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [System.Management.Automation.SwitchParameter]) { if ($kv.Value) { $relaunch += "-$($kv.Key)" } }
        else { $relaunch += "-$($kv.Key)"; $relaunch += ('"{0}"' -f $kv.Value) }
    }
    Write-Host "Requesting administrator rights (UAC prompt)..."
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $relaunch -ErrorAction Stop | Out-Null; exit 0 }
    catch { Write-Warning "Elevation declined - exiting without changing anything."; exit 1 }
}
```

**R6.16** Self-elevation MUST NOT fire under `-WhatIf`. The `-not
$WhatIfPreference` guard above is mandatory. A preview that demands
administrator rights defeats the purpose of a preview and trains users to accept
prompts they have not read.

**R6.17** Declining the UAC prompt MUST be safe and MUST be reported. The script
either exits without changing anything, or degrades to the subset it can do
without elevation and says explicitly which subset that is.

**R6.18** `Test-` scripts MUST never elevate, under any circumstances.

### 6.7 Side effects

**R6.19** Any action with a visible cost to the user — restarting Explorer,
stopping a service, signing out — MUST be opt-in behind an explicit switch, MUST
name its cost in the help text (*"This closes any open File Explorer
windows"*), and MUST NOT be implied by any other parameter.

**R6.20** If some changes do not take effect until a restart or sign-in, the
script MUST say which ones and what would apply them sooner:

```
  taskbar and file-list items apply at your next sign-in,
  or immediately if you re-run with -RestartExplorer.
```

### 6.8 Error handling

**R6.21** `$ErrorActionPreference = 'Continue'` at the top of change scripts: one
failed setting MUST NOT abandon the remaining settings, and MUST NOT abandon the
summary that tells the user what state they are now in.

**R6.22** Individual failures MUST be caught, counted, and printed with the
setting name and the error message. A silent failure is the worst outcome the
standard admits.

---

## 7. Console output conventions

### 7.1 In plain language

The output is documentation that arrives at the moment it is needed. It should
read as sentences, be legible in a default console on a low-resolution screen,
and never require the reader to already know what the module does.

### 7.2 Requirements

**R7.1** Output MUST be aligned into columns with format strings
(`"    {0,-28} {1}"`), two-space indentation for the body, four for list items.

**R7.2** Every script MUST print a header naming the module, the scope in effect,
and — for the `Test-` script — the machine, build and user.

**R7.3** State MUST be printed in the human track's vocabulary. Print the setting
name a person can recognise (`Menu fade`), and where a raw identifier matters,
print it alongside rather than instead.

**R7.4** Consequences MUST be annotated inline where they are not obvious. Module
01 marks each active effect `<- costs cycles` and each already-off value
`(already off)`.

**R7.5** Scripts MUST NOT use colour as the only carrier of meaning, and MUST NOT
use emoji or box-drawing characters. Console encoding on a default Windows 11
PowerShell 5.1 host mangles them. ASCII rules (`-`), ASCII arrows (`->`).

**R7.6** Where the module can measure the thing it claims to affect — process
memory, service count, listener count — the `Test-` script SHOULD print that
measurement so a before/after comparison is available without extra tooling.
Module 01 prints `dwm.exe` resident size and the WebView2 process count.

---

## 8. Evidence and citation requirements

### 8.1 In plain language

Every factual claim in a module's documentation is backed by one of two things,
and you can check both without trusting anyone:

- **A Microsoft document**, quoted verbatim, with the file and line where the
  sentence lives — tagged `[R-nn]`. The repository ships a script that opens each
  cited file and confirms the sentence is really there.
- **A measurement from this machine**, saved as a file you can re-create by
  running the same read-only scan — tagged `[M-nn]`.

There is a third category, and it is the one that matters most for honesty:
things that are true, that we rely on, and that the documentation we hold does
not cover. Those are labelled as engineering observation and the reader is told
how to verify them. They are never dressed up as vendor statements.

### 8.2 Requirements

**R8.1** Every factual claim about Windows behaviour in a module's documentation
MUST be traceable to a `[R-nn]` vendor citation, an `[M-nn]` measurement
artifact, or an explicit statement that it is engineering observation.

**R8.2** `[R-nn]` citations MUST name the corpus-relative path and line, and MUST
quote the source verbatim so `tools/Verify-Citations.ps1` can confirm it. New
references are appended to the reference table in `FINDINGS.md`; numbers are
never reused.

**R8.3** `[M-nn]` measurements MUST point at a real artifact under `evidence/`
produced by a named read-only script, so the reader can re-run it.

**R8.4** Where the corpus cannot support a claim, the module MUST say so in
place, in both tracks, and state how the claim can be verified instead. Module
01's mandatory disclosure, which every module inherits in form:

> The parameter conventions of `SystemParametersInfo` are **not** vendor-cited:
> the Win32 API reference pages are absent from this project's offline
> documentation corpus. They are stated as engineering observation, verifiable by
> running `Test-VisualEffects.ps1` before and after a change and comparing the
> values. What **is** vendor-documented is that the client-area animation
> parameter exists and turns UI animations on or off, and that translucency is
> GPU-expensive.

**R8.5** A module MUST NOT invent a citation, paraphrase a source and present it
as a quotation, or cite a document it has not opened. Citations that fail
`tools/Verify-Citations.ps1` block the module from being called finished.

**R8.6** A module MUST NOT claim a capability its scripts do not implement.
Documentation is written by reading the code, not by reading the plan.

### 8.3 Citations underpinning module 01 (the worked example)

| Tag | Source | Supports |
|---|---|---|
| R-63 | https://learn.microsoft.com/en-us/windows/apps/design/style/acrylic line 70 | *"Rendering acrylic surfaces is GPU-intensive, which can increase device power consumption and shorten battery life. Acrylic effects are automatically disabled when a device enters Battery Saver mode."* |
| R-66 | https://learn.microsoft.com/en-us/windows/apps/develop/composition/composition-tailoring line 114 | Gaussian Blur, Shadow Mask, BackDropBrush, HostBackDropBrush and Layer Visual are of "high performance impact … not recommended for low end devices" |
| R-67, R-68 | as above | applications are expected to honour `UISettings.AnimationsEnabled` and `UISettings.AdvancedEffectsEnabled` |
| R-69, R-70 | https://learn.microsoft.com/en-us/windows/win32/WinAuto/client-area-animation lines 11 and 13 | the client-area animation parameter "indicates whether the user wants to disable animations in UI elements"; applications use `SPI_GETCLIENTAREAANIMATION` / `SPI_SETCLIENTAREAANIMATION` with `SystemParametersInfo` "to turn client area animations on or off" |
| R-71, R-72, R-73 | three corpus documents | DWM composition has been always-on since Windows 8 and `DwmEnableComposition` cannot disable it |
| M-05 | `evidence/2026-08-26_07-31-11_baseline/visual-effects.txt` | the measured state below |
| *(uncited)* | — | `SystemParametersInfo` parameter conventions — engineering observation, per R8.4 |

### 8.4 Measured baseline, module 01

Measured 2026-08-26 on the machine this project was built for. No other machine's
figures appear anywhere in this project, and none may be invented.

```
Windows 11 Home, build 26200, Intel i7-1255U, 63.7 GB RAM, integrated graphics

Already off  : modern app animations (UISettings.AnimationsEnabled = False)
               frosted glass (AdvancedEffectsEnabled = False, EnableTransparency = 0)
Still on     : Gradient window captions, Menu fade, Tooltip fade,
               Drop shadow (windows), UI effects (master), Drag full windows
Shell to set : TaskbarAnimations=1, ListviewAlphaSelect=1, ListviewShadow=1,
               EnableAeroPeek=1, VisualFXSetting unset (to be set to 3 = Custom)
Menu delay   : 400 ms (script sets 0)
dwm.exe      : ~178 MB resident
Web apps     : 18 processes, ~917 MB
Dry run      : 11 real changes pending
```

Note the honesty requirement this table exists to demonstrate: two of the four
layers were **already** in the desired state before the module ran. A module
README that omitted that would be overstating its own effect.

---

## 9. Honesty requirements

These bind the author, not the code.

**R9.1** State what is not known. "We could not determine X" is an acceptable
sentence in this project and a required one when true.

**R9.2** State what cannot be guaranteed. Turning work off reduces work; it does
not make a slow machine fast. Say that where a reader might expect otherwise.

**R9.3** State what might break, specifically. Not "some applications may be
affected" but which ones and how.

**R9.4** Where an earlier attempt was wrong, record the error, why it was
plausible, and the correction. Module 01's README does this for the registry
misreading of the modern-animation flag. Deleting a mistake removes the evidence
that the method works.

**R9.5** Report what was already done before the module ran, and do not count it
as an effect of the module.

**R9.6** Do not describe an unapplied change as applied. If a module has been
dry-run only, its README says so and its status in the register says so.

**R9.7** Edition limits are real and MUST be stated. This machine is Windows 11
**Home**: no AppLocker enforcement, no `gpedit.msc`, and some policies that
appear in documentation are silently ignored. Where a module's mechanism is
edition-dependent, say which editions honour it rather than implying universality.

**R9.8** Third-party software outside the module's reach MUST be named as outside
its reach. Module 01: applications that animate through their own engines and do
not honour `prefers-reduced-motion` are unaffected.

**R9.9** A claimed benefit MUST either be measured or be labelled as unmeasured.
Both are acceptable; asserting a saving as though it had been measured is not.
See §15.

---

## 10. Shared parameter vocabulary

The same idea uses the same parameter name in every module, so that learning one
module teaches the next.

| Parameter | Script | Meaning |
|---|---|---|
| `-WhatIf` | all changing scripts | preview; change nothing; do not elevate |
| `-Json` | `Test-` | also write a timestamped snapshot to `backups/` |
| `-Tag <string>` | applying | label folded into the backup filename |
| `-List` | `Restore-` | show restore points and stop |
| `-Original` | `Restore-` | restore the write-once pristine state |
| `-Backup <path>` | `Restore-` | restore one named file |
| `-Apply` | applying, where the default is audit-only | perform the change |
| `-Keep<Thing>` | applying | leave one specific setting alone |
| `-Restart<Component>` | applying and `Restore-` | opt into a visible, costly side effect |

`-Force` MUST NOT be used to mean "skip the backup" or "overwrite
`original-state.json`" in any module.

---

## 11. Is this module finished?

Copy this block into the module's pull request, commit message or a scratch file
and tick every line. A module is finished when every box is ticked and not
before.

```markdown
### Layout
- [ ] Folder is `modules/NN-topic-name/`, number allocated in MODULE-STANDARD.md §1.4
- [ ] `_Common.ps1` exists, executes nothing, holds the single settings table
- [ ] `Test-<Topic>.ps1` exists and is genuinely read-only
- [ ] `<Verb>-<Topic>.ps1` exists
- [ ] `Restore-<Topic>.ps1` exists as its own file (no `-Restore` flag anywhere)
- [ ] `backups/` is created on demand by the scripts
- [ ] Every script resolves paths from `$MyInvocation.MyCommand.Path`, not the cwd

### The trio
- [ ] `Restore-` works correctly with NO arguments
- [ ] `Restore-` supports `-Original`, `-Backup`, `-List`, `-WhatIf`
- [ ] The applying script prints the full undo command as its last output
- [ ] All three scripts share one settings table; adding a setting updates all three

### Backups
- [ ] Full state captured before the first change, path printed
- [ ] Backup covers ALL settings, including those out of scope for this run
- [ ] Envelope carries capturedUtc, host, user, osBuild
- [ ] `original-state.json` written once; no code path overwrites it; no flag can
- [ ] `Restore-` takes a `pre-restore` backup before undoing (skipped under -WhatIf)
- [ ] Restore DELETES values that did not exist at capture time
- [ ] Restore recreates registry keys that have since been deleted
- [ ] Nothing is auto-pruned or rotated
- [ ] Any irreversible part is named explicitly in the README, both tracks

### Scripts
- [ ] `SupportsShouldProcess` on everything that changes state
- [ ] Every mutation gated by ShouldProcess or `-not $WhatIfPreference`
- [ ] `-WhatIf` previews the backup write too, and is readable (no module-load noise)
- [ ] Post-change verification RE-READS state; does not trust the write
- [ ] Failures listed by name; summary reports changed / already / failed separately
- [ ] Nothing-to-do prints what was looked for, where, and what its absence means
- [ ] No elevation requested unless genuinely required
- [ ] If elevation is required: self-elevates, preserves parameters, and does NOT
      fire under `-WhatIf`; declining is safe and reported
- [ ] `Test-` never elevates
- [ ] Costly side effects are opt-in and their cost is stated
- [ ] Deferred effects ("applies at next sign-in") are named
- [ ] `Add-Type` guarded against redefinition; no `Set-StrictMode` in restore paths
- [ ] JSON written and read with explicit `-Encoding UTF8`
- [ ] Master gates written last on disable, first on restore, with a comment saying why

### Documentation
- [ ] `README.md`: human track first, all nine required sections present
- [ ] `README.md` states the elevation position positively
- [ ] `HOWTO.md`: every script, every parameter, a worked example per capability
- [ ] Comment-based help on every script: SYNOPSIS, DESCRIPTION, every PARAMETER,
      an EXAMPLE per capability
- [ ] British spelling; no exclamation marks; no "simply" / "just"; no marketing
- [ ] Every jargon term explained in place in the human track
- [ ] Analogies checked for accuracy

### Evidence
- [ ] Every behavioural claim carries [R-nn], [M-nn], or an explicit
      "engineering observation" label with a stated way to verify it
- [ ] New references appended to FINDINGS.md; `tools\Verify-Citations.ps1` exits 0
- [ ] Measurements point at a real artifact under `evidence/`
- [ ] Corpus gaps declared in the README rather than left implicit
- [ ] No claimed capability the scripts do not implement

### Honesty
- [ ] What was already done before the module ran is reported as such
- [ ] Known unknowns stated
- [ ] Realistic breakage named specifically
- [ ] Any earlier wrong answer recorded, with why it was plausible
- [ ] Edition limits (Windows 11 Home) stated where relevant
- [ ] Applied vs dry-run-only status accurate in the README and the §1.4 register

### Exercised
- [ ] `Test-` run on a clean machine state; output read end to end
- [ ] Applying script run with `-WhatIf`; predicted count matches reality
- [ ] Applying script run for real; verification block confirms effect
- [ ] `Restore-` run with no arguments; `Test-` confirms the machine is back
- [ ] `Restore- -Original` run after two applying runs; `Test-` confirms pristine
- [ ] `Restore-` run against an empty `backups/`; the no-op message is correct
```

---
- [ ] Every script a user runs has a numbered, plainly-named `.cmd` launcher beside it
- [ ] Launchers use `cd /d "%~dp0"`, `-NoProfile`, `-ExecutionPolicy Bypass`, and end with `pause >nul`
- [ ] Elevation is requested only where genuinely required, and the launcher says so
- [ ] The undo is reachable by double-click, with no parameters to work out

## 12. Known non-conformance in the reference module

Recorded rather than quietly fixed, per §9.

At the time of writing, `modules/01-visual-effects` contains its four scripts and
an empty `backups/` folder. It does **not** yet contain `README.md` or
`HOWTO.md`, and therefore fails **R5.1** and **R5.4**. A dual-track README for
this subject exists at `visual-effects/README.md` — the pre-modules location —
and is the right starting material, but it is not in the module folder, does not
carry all nine required sections, and documents an older script that used a
`-Restore` flag rather than a separate rollback file.

Two further points of drift with that older document, noted so nobody copies them
forward:

- It describes `-Restore <file>` on the disable script. That interface is
  superseded by `Restore-VisualEffects.ps1` and is prohibited by **R2.3**.
- It cites backups under `..\_backups\`. Module backups now live in the module's
  own `backups/` folder, per **R1.2**.

Until the two documents exist in `modules/01-visual-effects/`, module 01 is not
finished by its own standard.

---

## 13. Conformance summary

A module conforms when:

1. It has the folder layout of §1 and a number from the register.
2. It has the mandatory trio of §2, with a no-argument rollback in its own file.
3. It honours the four backup promises of §4, including the write-once original.
4. It ships `README.md` and `HOWTO.md` meeting §5, dual-track, human track first.
5. Its scripts meet §6: `-WhatIf`, re-read verification, graceful no-ops, no
   unnecessary elevation, no elevation under `-WhatIf`.
6. Its claims are cited or labelled per §8, and its corpus gaps are declared.
7. Every box in §11 is ticked.

8. It meets §15: a measurement where a resource benefit is claimed, or an
   explicit statement that no performance claim is being made.

Anything less is a module in progress, and its status in §1.4 says so.

### Where each module stands

| | 01 visual effects | 02 update distribution | 03 copilot | 04 recommendations |
|---|---|---|---|---|
| Folder layout (§1) | yes | yes | partial | yes |
| Mandatory trio (§2) | yes | yes | yes | yes |
| Safety-logic self-test (R2.8) | **yes — 40 checks** | **yes — 37 checks** | not yet | **yes — 33 checks** |
| Harness cannot skip silently (R2.8a) | yes | yes | n/a yet | yes |
| Round-trip INCONCLUSIVE rule (R2.9) | yes | yes | n/a yet | yes |
| Backup contract (§4) | yes | yes | n/a yet | yes |
| `-RecordAsOriginal` (R4.4a) | yes | yes | n/a yet | yes |
| Absent-value restore (R4.6) | n/a — no absent values | **yes** | will apply | **yes — 8 of 10 are absent by default** |
| Irreversible-change rule (R4.10) | n/a | n/a | **yes — its hard case** | n/a |
| README + HOWTO (§5) | yes | yes | README only | README only |
| Script requirements (§6) | yes | yes | checker only | yes |
| Citations (§8) | 90/90 verified | 5/5 verified | 6/6 verified | 5/5 verified |
| Uncited claims labelled (§8) | yes | yes | yes | **yes — enforced by a second tier in code** |
| Launchers (§14) | 8, none elevated | 7, four elevated | 1, none elevated | 8, none elevated |
| Measurement (§15) | `Measure-VisualEffects.ps1` | n/a — stated | disk only, stated | **n/a — no performance claim, stated** |
| Adversarial audit | **done** — 10 defects fixed | **done — 9 findings, all fixed** | **in progress** | **done — 16 findings, all fixed** |
| Round trip proved on a real machine | **yes** — 13 moved, returned | **yes — 3 moved, returned, elevated** | **yes — 3 moved, returned, elevated (tier 1)** | **yes — 10 moved, returned** |
| Round-trip comparison proved falsifiable | not yet | **yes** | **yes** | **yes** |
| Applied on the audited machine | **yes** | **no** | **no** | **no** |

Module 02 is **not finished** until its last three rows change. Its scripts are
written, syntax-checked, preview-tested and citation-verified, but no adversarial
audit has been run against it and its rollback has never been executed. By the
rule this project applies to everything else, that means it does not ship.

Module 04 is the furthest along after module 01, and got there because every
setting it manages is per-user: it could be built, applied, undone and proved
without anyone approving an elevation prompt. It is the only module whose
round-trip comparison has itself been shown capable of failing — a doctored entry
is detected and a null state trips a guard — which matters because that
comparison returned a **false PASS** on its first run.

Module 03 was **earlier still, deliberately** — a read-only checker shipped
alone until the removal scripts could be tested elevated. That caution paid its
way: before execution the module went through the same adversarial audit as the
others and it produced the largest haul of the day — **14 findings, 2 severe**,
among them an exit-code contract that was gated on but never implemented, and a
key-cleanup emptiness check that would have deleted a third party's data. All
fixed, all regression-tested (45 checks), and only then was the removal
executed on 2026-08-26. The uninstaller exited 19 with its folder verifiably
gone; the module recorded the removal **with** that exit code rather than
rounding it to success — R16-grade honesty exercised on the first real run.

Module 03 is also the first to meet **R4.10**: part of what it does cannot be
reversed by replaying a state file, because deleting 1.3 GB of software is not a
settings change. Its two tiers are separated in `_Common.ps1` so that the restore
allow-list physically cannot contain the removals — the honesty is enforced by
the data structure, not by the documentation.

## 14. Double-clickable launchers (mandatory)

### Why this is a requirement and not a nicety

Double-clicking a `.ps1` file opens it in Notepad. That is Windows' default and
it is not going to change. A person who has been handed a folder of PowerShell
scripts therefore cannot run any of them, and the usual advice - open a terminal,
set an execution policy, type a path - assumes exactly the knowledge this project
exists to stop assuming. A module whose scripts cannot be run by the people it
was written for is not finished.

Worse, the obvious workarounds are the dangerous ones. Telling someone to run
`Set-ExecutionPolicy Unrestricted` changes a machine-wide security setting
permanently, to solve a problem that a per-invocation `-ExecutionPolicy Bypass`
solves for that one run.

### The rule

**Every script a user is expected to run gets a `.cmd` launcher beside it.**

- Name it for what it does, in words a non-technical person would use, and
  number it so the folder sorts into the order the scripts should be run in.
  `3 - Apply the changes.cmd` beats `Run-Disable.cmd`.
- Start with `cd /d "%~dp0"` so relative paths work no matter where it is
  launched from, and so an elevated relaunch does not start in System32.
- Invoke with `powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Script.ps1"`.
  `-NoProfile` keeps a user's profile customisations out of it;
  `-ExecutionPolicy Bypass` applies to that single invocation only and changes
  no machine setting.
- **Use `-Command`, not `-File`, whenever a switch is given an explicit value**
  such as `-Confirm:$false`. Under `-File`, PowerShell treats everything after
  the script path as plain text, so `-Confirm:$false` arrives as the *string*
  `"$false"` and the script dies with:

  ```
  Cannot convert 'System.String' to the type
  'System.Management.Automation.SwitchParameter' required by parameter 'Confirm'.
  ```

  The working form is
  `powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0Script.ps1' -Confirm:$false"`.
  Module 02 shipped two launchers and a round-trip test with the broken form, and
  module 01's HOWTO published the broken form as a worked example. All three were
  found by running them; none would have been found by reading them.
- End with `pause >nul` so the window stays open and the result can be read.
  A window that flashes and vanishes has told the user nothing.
- Explain in the file's own comment header what it does and whether it changes
  anything. People do open these in Notepad, and that is a feature.

### Elevation

Two templates live in `modules\_templates\`:

| Template | Use when |
|---|---|
| `TEMPLATE - launcher (no admin needed).cmd` | the script changes only the current user's settings |
| `TEMPLATE - launcher (needs admin).cmd` | the script changes machine-wide state |

The elevated template detects its own privilege level with `fltmc`, which
succeeds only when running as administrator and is more reliable across Windows
versions than testing group membership. If not elevated it explains, in plain
words, that Windows is about to ask permission and that the prompt comes from
Windows rather than from the script - then relaunches itself with
`Start-Process -Verb RunAs`. A refused or cancelled prompt must say so and change
nothing.

**Do not request elevation a module does not need.** Module 01 changes only
per-user display settings, so none of its seven launchers asks for administrator
rights, and each says so in its header. Asking for privileges unnecessarily
trains people to approve prompts unread, which is precisely how they end up
approving the one that matters.

---

## 16. The exit-code and snapshot contract (mandatory)

Everything in this section exists because its absence produced a specific,
observed failure on 2026-08-26. None of it is speculative.

**R16.1** An applying script MUST signal its outcome with exit codes, and a
caller MUST key off them - never off words found in the output.

| Exit | Meaning |
|---|---|
| 0 | applied (or previewed) successfully |
| 3 | refused: no verified backup could be written; nothing was changed |
| 4 | nothing to do: every setting was already at target; NO backup was written |

*Why:* module 02's round trip matched the word `STOPPING` in the child's output.
It false-positived on a run where the backup had succeeded and the apply had
completed - so the test skipped its undo and left the machine changed, while a
test's whole promise is net zero. Text in output is a message for a human; an
exit code is a signal for a program.

**R16.2** A round-trip test MUST abort before its undo step when the apply
reports exit 4. *Why:* without the gate, a round trip on an already-applied
machine ran the real undo against the newest OLD backup, un-applied the machine,
and then reported FAIL against an undo that had worked perfectly.

**R16.3** Internal snapshots (the undo's pre-restore capture) MUST be named with
the `_~prerestore` suffix via a dedicated `-InternalSuffix` parameter - never via
the user-facing `-Tag`. Restore candidates exclude exactly that suffix and
nothing broader.

*Why, in two halves:* the original audit finding was that a USER tag of
"pre restore" produced a filename the exclusion pattern matched, hiding the
apply's own backup from the undo. The first fix transformed reserved tags - and
thereby renamed the INTERNAL snapshot too, freeing it to appear as a restore
candidate: a double-undo then restored the applied state from the undo's own
snapshot. The `~` marker resolves both, because the safe-tag charset strips `~`,
so no user tag can ever produce or collide with the internal name.

**R16.4** A round-trip test MUST delete the backup files it caused, on a PASS
(never `original-state.json`), and MUST keep them with a warning on a FAIL.
*Why:* a passed round trip's newest backup records an intermediate applied
state; a later "UNDO everything" faithfully restored it and reported
`restored: 10 failed: 0` while undoing nothing.

**R16.5** A restore MUST validate value and kind against what the module knows to
be legitimate - not merely the key and name. *Why:* module 02's restore took
`Value` and `Kind` straight from the JSON, so an edited backup could set
`DODownloadMode = 3` (internet-wide peering, worse than the default) as a
REG_SZ, reported as `restored: 1 failed: 0`.

**R16.6** The undo MUST treat a failure of its own pre-restore snapshot as
fatal, exactly as the apply treats a failed backup. *Why:* the apply aborted on
backup failure while the undo discarded the same signal with `[void](...)` and
restored anyway - making the undo itself un-undoable at the precise moment the
backup folder went bad.

**R16.7** Registry emptiness checks MUST count the `(Default)` value.
`GetValueNames()` reports it as `''`; filtering it out judged a key holding only
a third party's default value as empty, and deleted it.

**R16.8** `schemaVersion` checks MUST NOT use a bare `[int]` cast, which throws
on non-numeric input and crashes the restore at exactly the guard meant to
reject bad files. Use a caught cast (or `-as [int]`) and return "not usable".
Found by audit in module 04, then found again by self-test in module 03, and
present in modules 01 and 02 as well: one root cause, four copies.

---

## 15. Measurement (mandatory where a benefit is claimed)

A module that says a change makes the machine better has made a testable claim.
Either test it, or say plainly that you have not.

**R15.1** Where a module claims a **resource** benefit - processor, graphics,
memory, disk, network, battery - it MUST ship a script that measures that claim on
the machine it runs on, named `Measure-<Area>.ps1`, with a numbered launcher.

Where the claim is not about resources - a service that can no longer be triggered
from the network is a security benefit, not a performance one - R15.1 does not
apply, and the README MUST say plainly that no performance claim is being made.
Inventing a performance justification for a security change is worse than
claiming nothing.

**R15.2** Measurement scripts MUST use the shared engine at
`READ-ONLY-diagnostics\_MeasureLib.ps1`, and MUST NOT carry a private copy of the
measuring logic. If two modules measure differently their numbers cannot be
compared, and a repository whose own figures disagree with each other is worth
less than one that publishes none.

**R15.3** Measurements MUST come from cumulative counters differenced across a
window, never from instantaneous samples. Two reads of a counter that only counts
upwards yield the quantity consumed. One read of a rate counter yields the number
Task Manager would have shown, which is not a measurement.

**R15.4** Every measurement MUST report its own noise floor: the spread between
repeats of the **same** condition. Any before/after difference smaller than that
spread MUST be reported as within noise, and MUST NOT be described as a saving. A
run that cannot establish a noise floor MUST say so in place of its verdicts,
rather than printing verdicts it cannot support.

**R15.5** Where a module changes state in order to measure both sides, it MUST:

- use the module's own audited apply and restore scripts, not a private copy of
  that logic;
- verify the write-once original state exists before starting, and stop if it does
  not;
- treat both sides identically - same window length, same settle time, same
  workload, same restarts;
- state which side it left the machine on, in its final output;
- offer a switch to finish on the original side;
- ask for confirmation before starting, with a `-Force` switch for unattended use.

**R15.6** A workload, where one is used, MUST exercise the specific settings the
module changes, and the documentation MUST say which operation maps to which
setting. A generic benchmark measures the benchmark.

**R15.7** Results MUST be recorded in `RESULTS.md` in the module folder,
regenerated by the script rather than hand-edited. It MUST carry the processor,
graphics, Windows build and power state, because without them the numbers mean
nothing; it MUST NOT carry the machine name or the user name, because it is meant
to be published. Raw readings go to `measurements\`, which is excluded from
version control.

**R15.8** A measurement script MUST be capable of reporting no difference, and its
documentation MUST say so. If no plausible outcome of running it would weaken the
module's own claims, it is not a measurement.

**R15.9** State what the measurement cannot establish. Processor time is a proxy
for power draw, not a measurement of it, and no module may convert one into the
other.

### Conformance

| Module | R15.1 | R15.2 | R15.4 | R15.5 | R15.7 |
|---|---|---|---|---|---|
| 01 visual effects | `Measure-VisualEffects.ps1`, launcher 7 | yes | yes | yes | yes |
| 02 update distribution | n/a — security benefit only, and its README says so in as many words | — | — | — | — |

### The undo must be as clickable as the change

If applying a change is a double-click, undoing it must be a double-click too,
requiring no parameters, no reading, and no decisions. Module 01 ships
`4 - UNDO everything.cmd` and `5 - UNDO back to the original.cmd` for exactly
this reason. A rollback that only a competent operator can reach is not a
rollback for the person most likely to need it.
