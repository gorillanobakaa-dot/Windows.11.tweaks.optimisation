# How to use the services module

*The most dangerous module in this repository, and the one with the most
refusals built into it. Read the first section before you run anything.*

---

## Before you start

### This module can stop a machine booting. That is why it mostly says no.

Everything else here changes settings. This changes **whether Windows is
allowed to start a service at all**, and a bad set does not fail when you
apply it — it fails at the next boot, potentially with no network, no sign-in,
or no way to elevate and undo it.

That risk is why roughly half the code is refusals:

- **95 services no profile may contain**, enforced in code. If a profile names
  one, the apply *refuses the whole profile* and exits 6.
- **9 services excluded entirely** because disabling them can stop you
  **signing in**. A backup on a disk you cannot log in to reach is not a
  rescue.
- **A dependency check computed from the live machine** before any write,
  which now also scans **drivers** — a kernel driver can declare a dependency
  on a service, and there is a live example on this machine.

None of that makes it safe. It makes it *checkable*.

### A restart is the honest test

Services already running keep running after the apply. The change is what
happens at the **next boot**. So the real sequence is: apply, restart, use the
machine normally for a day, and only then decide it worked.

### Do this first, in this order

1. **`10 - Prove the undo works`** — before applying anything, prove the undo
   round-trips on *your* machine. It applies LIGHT for real, undoes it, and
   compares every service. Net zero on a pass.
2. **`4 - Preview SUPER`** — read what the most aggressive profile would take
   away, even if you intend to use LIGHT. It is the fastest way to understand
   what these profiles are.
3. Then pick a profile.

---

## The launchers at a glance

| # | Launcher | Admin? | What it does |
|---|---|---|---|
| 1 | Check what is on now | No | Every service, and what each profile would do |
| 2 | Preview LIGHT | No | Every service LIGHT disables, by category |
| 3 | Preview MODERATE | No | Same, for MODERATE |
| 4 | Preview SUPER | No | Same, for SUPER |
| 5 | APPLY profile LIGHT | **Yes** | Disables ~64 services |
| 6 | APPLY profile MODERATE | **Yes** | ~116 |
| 7 | APPLY profile SUPER | **Yes** | ~167 |
| 8 | UNDO everything | **Yes** | Every start type back from the newest backup |
| 9 | UNDO back to the original | **Yes** | Back to before this module ever ran |
| 10 | Prove the undo works | **Yes** | Apply LIGHT, undo, compare — net zero on a pass |
| 11 | Test the safety logic | No | 83 checks on the refusals themselves |
| 12 | Does Alt-Tab still work | No | Presses Alt+Tab and looks |

**The undo is 8, not 4.** An earlier version of the apply printed the wrong
number here; 4 is *Preview SUPER*.

---

## Which profile?

| Profile | Disables | What you actually lose |
|---|---|---|
| **LIGHT** | 64 | Scanning, Mobile Hotspot, File History, Windows Backup, WebDAV, smart cards, and Windows' own self-repair services |
| **MODERATE** | 116 | LIGHT + remote access (RDP, WinRM, SMB *server*), cloud sync, diagnostics, geolocation, **Bluetooth pairing**, the built-in troubleshooters |
| **SUPER** | 165 | MODERATE + **printing** (including Print to PDF), **Bluetooth**, **Windows Search indexing**, the Store surface, legacy protocols. The **camera is no longer touched by any profile** — see below |

Profiles are **cumulative**: MODERATE includes LIGHT, SUPER includes both.

**"LIGHT" does not mean "no cost".** An earlier draft of this module claimed it
disabled "nothing you use" and an audit called that false. The table above is
the corrected version.

### Choosing honestly

- If you print, scan or use Bluetooth: **LIGHT or MODERATE**, not SUPER. The camera is safe in all three now.
- If you use Windows Search heavily (or Outlook search): not SUPER.
- If you ever connect to this machine remotely: not MODERATE or SUPER.
- If this is a locked-down single-purpose workstation: SUPER is what it is for.

---

## `Test-Services.ps1` — every option

```bash
powershell -ExecutionPolicy Bypass -File .\Test-Services.ps1
powershell -ExecutionPolicy Bypass -File .\Test-Services.ps1 -Profile super -Full
```

### `-Profile light|moderate|super`

Shows the detail for one profile: the reality warnings, the dependency check,
and a count. Without `-Full` it stops there.

### `-Full`

Lists every service the profile would disable, **grouped by category**, with
its current state. This is the one to read before applying anything.

### What the reality warnings mean

A profile is a policy; your machine is a fact. Where they disagree, this says
so before you write anything:

```
    THINGS THIS MACHINE ACTUALLY USES THAT THIS PROFILE TOUCHES:
      ! Bluetooth: 4 device(s) are present and working. Disabling bthserv
        ends Bluetooth on this machine.
      ! Printing: 1 printer(s) installed, including 'Microsoft Print to PDF'.
```

They are **warnings, not refusals** — you may genuinely want the trade.

---

## `Apply-ServiceProfile.ps1` — every option

```bash
powershell -ExecutionPolicy Bypass -File .\Apply-ServiceProfile.ps1 -Profile light
```

### `-Profile` (required)

`light`, `moderate` or `super`.

### `-WhatIf`

Prints every change and makes none. Works **without** administrator rights,
deliberately — the preview should not require elevation.

### `-Force`

Skips the typed confirmation. Intended for the round-trip proof. Without it,
you must type the profile name to proceed — not "y", the actual word, because
this is not a decision to make by reflex.

### `-Tag`

Labels the backup file. Useful if you want to find a specific backup later.

### The three refusals, and what they look like

**A forbidden service** (exit 6):

```
    STOPPING. This profile names services that must never be disabled:
      X RpcSs is on the NEVER-TOUCH list: 152 services depend on it
    Nothing was changed.
```

**A stranded dependency** (exit 6):

```
    STOPPING. This plan would break service dependencies:
      X DRIVER applockerfltr (start 3) stays enabled but depends on AppIDSvc
    A dependency break does not fail when you make it. It fails at the next boot.
```

**No verified backup** (exit 3): nothing is written without one.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | applied |
| 3 | backup refused; nothing changed |
| 4 | nothing to do, unelevated, or you declined |
| 5 | completed, but a write or a stop failed |
| 6 | the profile is illegal or unsafe |

---

## `Restore-Services.ps1` — every option

```bash
powershell -ExecutionPolicy Bypass -File .\Restore-Services.ps1
powershell -ExecutionPolicy Bypass -File .\Restore-Services.ps1 -Original
powershell -ExecutionPolicy Bypass -File .\Restore-Services.ps1 -List
```

### No arguments

Restores from the most recent usable backup. This is what launcher 8 runs.

### `-Original`

Restores from the write-once `original-state.json` — the state from before
this module was ever used. Launcher 9.

### `-Backup <path>`

Restores from a specific file. Use `-List` to see what exists.

### `-List`

Shows every backup, marking internal snapshots as *not offered as a restore
point*. That annotation is derived from the real filter, not a second
hand-written pattern — in another module, a duplicated pattern annotated the
list exactly backwards.

### `-Verbose`

Prints the reason each skipped service was skipped. Without it you get a count,
because a full restore skips around 90 services (the never-touch and
lockout-risk lists are out of scope in **both** directions).

### What it will not restore

Services on the never-touch or lockout-risk lists — even if a backup file says
to. A doctored or simply stale backup must not be able to disable Windows Hello
through the undo, which is the script you run when you are already in trouble.

---

## `Test-RoundTrip.ps1` — proving the undo

```bash
powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1 -Force
```

Applies **LIGHT** for real, undoes it, and compares every service start type on
the machine. It uses LIGHT deliberately: proving the machinery round-trips
faithfully does not require 167 services, and failing halfway through 167 leaves
a much worse machine.

A pass looks like this:

```
    [A] reading every service start type before anything happens ...
        284 services recorded
    [B] applying the LIGHT profile for real ...
        start types that moved between A and B: 63
    [C] undoing ...
        restored: 63  skipped: 221  failed: 0
    PASS - every service start type came back to exactly where it started.
```

On a pass it deletes the backups it created. On a failure it keeps them, and
prints what the apply and the undo actually said.

### "INCONCLUSIVE — nothing moved, so nothing was proved"

The profile is already applied, so the apply had nothing to do. Run `8 - UNDO
everything` first, then run the proof again.

---

## Troubleshooting

### Something broke after a restart

1. Run `8 - UNDO everything`. It needs administrator rights.
2. Restart.
3. If it is still wrong, run `9 - UNDO back to the original`.

### I cannot elevate to run the undo

This should be impossible — `Appinfo`, which *is* UAC elevation, is on the
never-touch list precisely so that the undo can always run. If it happens
anyway, boot into Safe Mode, where the minimal service set applies, and run the
undo from there.

### The apply says "nothing to do" but I have not applied anything

Some of the profile's services were already disabled by Windows or by an
earlier module. Check with `1 - Check what is on now`.

### Bluetooth / printing / search stopped working

That is documented, not a bug — see the profile table above. Undo with 8, or
re-enable the single service by hand:

```bash
sc.exe config bthserv start= demand
```

### Something stopped working and it is a PER-USER service

Some services are **templates**. Windows stamps a per-session copy from the
template when you sign in — you will see a name with a random suffix, like
`CaptureService_62d6e`. This module only ever touches the **template**, which is
what Microsoft's own guidance says to do.

The consequence catches people out: **fixing the template does not fix the
copy that is already running.** Two ways round it.

Sign out and back in — the copy is re-stamped from the corrected template. Or
write the copy's own key directly, elevated:

```bash
reg add "HKLM\SYSTEM\CurrentControlSet\Services\<name>_<suffix>" /v Start /t REG_DWORD /d 3 /f
```

`sc.exe config` does **not** work on an instance — it fails with *error 87, the
parameter is incorrect*. That is Windows refusing, not a mistake in the command.

**This applies to the module's own UNDO too.** Per-user *instances* are service
type 224, which is not in the list of types this module enumerates, so the undo
restores the template and leaves the current session's copy as it was. Sign out
and back in after any undo that involved a per-user service.

### A service I need is disabled and I do not want to undo everything

```bash
sc.exe config <name> start= demand
```

`demand` is Manual, `auto` is Automatic, `disabled` is disabled. The module's
own backup is still the safer route.

---

## What this module deliberately does not do

- **Delete services.** `sc delete` removes the *registration*, not the code —
  the DLL stays on disk, servicing restores the registration, and it is not
  reversible with what this module backs up. See `DEC-06-008`.
- **Touch drivers.** Only Win32 service types are enumerated, so no profile can
  reach a kernel driver even if someone typed one in.
- **Disable audio.** Kept in every profile including SUPER.
- **Disable Windows Update, the firewall, or Defender.** All never-touch.
- **Get swept into APPLY ALL.** The control panel's apply-all deliberately
  excludes the services profiles, because printing and Bluetooth are a real
  trade-off and should be a deliberate click.

---

## Checking the profiles yourself

```bash
powershell -ExecutionPolicy Bypass -File ..\..\READ-ONLY-diagnostics\Report-BlastRadius.ps1 -Profile super
python ..\..\READ-ONLY-verification\Lookup-ServiceDocs.py --profile super --undocumented
```

The first shows what Microsoft's own service descriptions say breaks. The
second shows which services rest on category reasoning rather than
documentation — **79 of 175** currently. Full usage in
[`../../TOOLS-HOWTO.md`](../../TOOLS-HOWTO.md).

---

## "It says 4 still to disable — why didn't they apply?"

Three of them — `DPS`, `WdiServiceHost`, `WdiSystemHost` — **cannot** be written
by this module. Their registry keys grant Administrators read access and no
write, so the apply reports each by name and exits **5**. That is the module
telling the truth, not a bug in your run.

The fourth, `dmwappushservice`, is different and more interesting: it **was**
disabled by the apply and came back to Manual on its own.

What the three are, what actually breaks if they are closed, and what
Microsoft's documentation says about each — with the file and line for every
quotation — is in
[`BLAST-RADIUS-diagnostics.md`](BLAST-RADIUS-diagnostics.md).

Re-running the apply is safe and idempotent: it will report the ones already
disabled as nothing to do and retry anything that has drifted back.
