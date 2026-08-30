# How to use the update-distribution module

Everything this module can do, every option, and what each one is for.

If you only want to use it, the [README](README.md) is shorter and enough. This
page is for the person who wants to know exactly what will happen before it does,
or who is auditing it before letting it near a machine they are responsible for.

---

## Before you start

### This module asks for administrator rights, and means it

Four of its six launchers request elevation. The visual-effects module never
does. That difference is not stylistic:

| Module 01 | Module 02 |
|---|---|
| `HKCU` - your account only | `HKLM` - the whole machine |
| Windows display settings | Delivery Optimization policy |
| - | Windows Firewall rules |

Firewall rules are not per-user. Neither is a machine policy. There is no
unprivileged way to change either, and any script claiming otherwise is either
not doing what it says or is doing it somewhere that does not take effect.

**Reading needs nothing.** `1 - Check what is on now` and
`2 - Preview the changes (safe)` do not ask, because they only read.

### What "peer distribution" is, in one paragraph

When Windows downloads an update, Delivery Optimization keeps the pieces and
offers them to other PCs so they do not each fetch the whole thing from
Microsoft. In the default mode it offers them only to machines behind the same
router. To do that it opens **port 7680** and accepts incoming connections, and
Windows ships two firewall rules that let other machines reach it.

### Read the counters before you believe anything

Run `1 - Check what is on now` first, and look at **bytes uploaded**. On the
machine this module was developed on it was **zero** - the sharing was permitted
and reachable, but had never actually happened.

That number decides which claim is true for *your* machine. A page that tells you
this feature has been costing you bandwidth, without asking your machine, is
guessing. The counter is right there.

---

## The five scripts at a glance

| Script | What it does | Changes anything? | Needs admin? |
|---|---|---|---|
| `Test-UpdateDistribution.ps1` | Reports configured mode, actual mode, listener, firewall rules, services | No. Never. | No |
| `Disable-PeerDistribution.ps1` | Backs up, verifies the backup, then applies | Yes - unless `-WhatIf` | Yes |
| `Restore-UpdateDistribution.ps1` | Puts everything back from a backup | Yes - unless `-WhatIf` | Yes |
| `Test-RoundTrip.ps1` | Applies for real, undoes, compares every setting | Yes - temporarily. Asks first | Yes |
| `Test-SafetyLogic.ps1` | Tests the logic that decides whether to write anything | No. Works in a temp folder | No |
| `_Common.ps1` | Shared code. Not a script you run | No | No |

### The two tests do different jobs

`Test-RoundTrip.ps1` proves the **writes** work, by performing them. It needs
administrator rights and it changes the machine while it runs.

`Test-SafetyLogic.ps1` proves the **decisions** work, by feeding the module bad
input it would never encounter in normal use - a corrupt backup, a backup naming
foreign registry paths, an unwritable backup folder, a tag full of illegal
filename characters. It needs nothing and changes nothing.

You need both. A module whose writes are correct but whose validation is absent
will happily restore from a file someone edited. A module whose validation is
perfect but whose writes silently fail will report twenty successful restores and
change nothing.

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-SafetyLogic.ps1
powershell -ExecutionPolicy Bypass -File .\Test-SafetyLogic.ps1 -Detailed
```

Exit code 0 if every check passes, 1 otherwise, so it can gate a commit. Current
result on this machine: **37 checks, 0 failures.**

Each check corresponds to a defect that was actually found - most of them in
module 01, by adversarial audit. They are tests rather than assertions in a
document because a claim in a README cannot fail, and a test can.

All four scripts dot-source `_Common.ps1`, so the checker, the applier and the
undo read and write through the same code. The settings table cannot drift
between them.

`Disable-PeerDistribution.ps1` and `Restore-UpdateDistribution.ps1` are declared
`[CmdletBinding(SupportsShouldProcess = $true)]`, which is where `-WhatIf` and
`-Confirm` come from. All four accept the PowerShell common parameters.

Output goes to the host stream via `Write-Host`, so it cannot be captured by
plain assignment. Redirect all streams (`*>`) or use `Start-Transcript`.

---

## Recommended first session

Nothing changes until step 4, and step 5 undoes it completely.

1. **`1 - Check what is on now`** - read it. Note **bytes uploaded**.
2. **`2 - Preview the changes (safe)`** - see the exact list. Still nothing changed.
3. **`6 - Prove the undo works`** - make the machine demonstrate the undo before
   you rely on it. Net effect on a pass: nothing.
4. **`3 - Apply the changes`** - approve the Windows prompt.
5. **`1 - Check what is on now`** again - confirm the mode and the rules moved.
6. If you dislike it: **`4 - UNDO everything`**.

**Step 3 before step 4 is the whole point of the ordering.** Any script can claim
it is reversible.

---

## `Test-UpdateDistribution.ps1` - every option

**In plain terms.** Shows the current state and changes nothing.

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-UpdateDistribution.ps1
```

### What it reports, and why it is split into four parts

**1. What it is set to.** The registry policy value. May be `<not set>`, which is
the default and is *not* the same as being set to anything.

**2. What it is actually doing.** What the Delivery Optimization service itself
reports, via `Get-DeliveryOptimizationPerfSnap`. **This is the authoritative
reading.** The two can disagree, and the disagreement is the interesting part: a
policy that this edition of Windows ignores looks exactly like a policy that
worked, right up until you ask the service.

This matters more on **Home** than anywhere else. Home has no Group Policy editor
and silently ignores some policies. This module does not assume the registry
value took effect - it asks.

**3. Is anything listening on port 7680.** Read from the actual listening socket
via `Get-NetTCPConnection`, not inferred from configuration.

**4. Is the firewall letting them in.** Rule state, direction, action, and
**profile**. If a rule's profile includes `Any` or `Public`, the report flags it,
because Public is the profile Windows uses for hotel, café and airport Wi-Fi.

It also lists `DoSvc`, `BITS`, `wuauserv` and `UsoSvc` - none of which this
module changes. They are shown so you can see they did not move.

### `-Json`

Writes a timestamped `snapshot_*.json` into `backups\`.

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-UpdateDistribution.ps1 -Json
```

A snapshot is a **record**, not a backup. It is the same shape as a real backup,
but it is named `snapshot_*` rather than `state_*`, so the restore script will
never select it. It also does **not** create `original-state.json` - only the
apply path may do that (see [The absent-value problem](#the-absent-value-problem)).

Compare two:

```powershell
$a = Get-Content .\backups\snapshot_BEFORE.json | ConvertFrom-Json
$b = Get-Content .\backups\snapshot_AFTER.json  | ConvertFrom-Json
"mode: {0} -> {1}" -f $a.runtime.effectiveModeName, $b.runtime.effectiveModeName
"listening: {0} -> {1}" -f $a.listener.listening, $b.listener.listening
```

### Running it without administrator rights

Everything above reads fine unelevated. The header says which mode it is in, so a
report is never silently partial.

---

## `Disable-PeerDistribution.ps1` - every option

**In plain terms.** Stops the sharing and closes the inbound rules.

**Launcher:** `3 - Apply the changes.cmd`

### What it does, in order

1. Reads the current state.
2. If not elevated and not `-WhatIf`, explains and stops. Changes nothing.
3. Works out what would change and prints it, one line per setting.
4. If `-WhatIf`, prints the count and returns.
5. If nothing needs changing, says so and returns.
6. **Writes a backup, then verifies it** - file exists, is over 200 bytes, parses
   back, and still has the sections a restore needs. **If any of that fails it
   stops and changes nothing.**
7. Applies each change, reading each one back.
8. Re-reads the machine and reports what it actually finds - including where that
   disagrees with what it intended.

### `-Steps`

`DownloadMode`, `Firewall`, or `Both` (default).

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-PeerDistribution.ps1 -Steps DownloadMode
```

Stops the sharing, leaves the firewall rules alone. Useful on a managed network
where something else expects those rules to exist, or if you want to change one
thing at a time and observe.

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-PeerDistribution.ps1 -Steps Firewall
```

Closes the door, leaves the mode alone. The machine still *wants* to peer; it
just cannot be reached.

### `-Tag`

Adds a label to the backup file name.

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-PeerDistribution.ps1 -Tag before-travel
```

Produces `state_2026-08-26_14-02-11_before-travel.json`. Non-word characters are
replaced with hyphens and the tag is truncated at 40 characters, so it cannot
produce an illegal filename.

### `-WhatIf`

```powershell
powershell -ExecutionPolicy Bypass -File .\Disable-PeerDistribution.ps1 -WhatIf
```

Prints every change and makes none. **Needs no administrator rights**, and does
not trigger an elevation prompt - a preview that demanded privileges would defeat
its own purpose. If changes are pending it tells you that applying them will need
rights, rather than discovering it later.

### What it prints afterwards, and why it may not be all good news

After applying it re-reads the machine and reports:

- the download mode **the service** reports (not the registry value it just wrote)
- whether port 7680 is **still listening**
- each firewall rule's state

Two notes it may print, both deliberate:

**"the service still reports a peer-capable mode".** Delivery Optimization
re-reads its configuration periodically rather than instantly, so this is usually
a stale reading - check again in a few minutes. If it still disagrees with the
registry after a reboot, that is a real finding: it would mean this edition is
ignoring the policy, and it is worth reporting.

**"the port is still open".** Expected. The firewall rules control whether
anything can *reach* the port; the service controls whether it *listens*. Closing
the socket entirely would mean stopping `DoSvc`, which is the service Windows
Update uses to download. An open socket behind a disabled inbound rule is a
smaller exposure than an open socket behind an allow rule - but it is not zero,
and this script says so instead of claiming a clean result it did not achieve.

---

## `Restore-UpdateDistribution.ps1` - every option

**In plain terms.** Undoes it. With no arguments at all.

**Launchers:** `4 - UNDO everything.cmd`, `5 - UNDO back to the original.cmd`

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-UpdateDistribution.ps1
```

Finds the most recent usable backup and restores from it. No arguments, no
choosing. That is the case that has to work, so it is the default.

### `-Original`

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-UpdateDistribution.ps1 -Original
```

Restores `backups\original-state.json` - how the machine looked before this
module was ever used, not merely before the last run. That file is written once,
by the apply path, and never overwritten.

If it does not exist, the script says so plainly rather than falling back to
something else. See below for why that matters.

### `-Backup`

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-UpdateDistribution.ps1 -Backup .\backups\state_2026-08-26_14-02-11_before-travel.json
```

### `-List`

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-UpdateDistribution.ps1 -List
```

Shows every backup with its timestamp, marks the ones tagged `pre-restore` as not
offered as restore points, and says whether `original-state.json` exists. Changes
nothing, needs no rights.

### `-WhatIf`

```powershell
powershell -ExecutionPolicy Bypass -File .\Restore-UpdateDistribution.ps1 -WhatIf
```

Shows what would be restored, from where, and to what. Needs no rights.

### How it chooses a backup, and the two traps it avoids

**Trap 1: restoring from the snapshot taken during the last restore.** Every
restore first saves where you are now, tagged `pre-restore`. If that file were
eligible as a restore point, running undo twice would put the *applied* state
back - the undo would re-apply itself. `Get-UdRestoreCandidates` excludes
`*pre-restore*`.

**Trap 2: a corrupt newest backup.** The default path walks candidates newest
first, parses each, and validates its shape, taking the first that is usable and
saying which ones it skipped. A single bad file does not block the undo.

### It restores from its own list, not from the file

`Restore-UdState` iterates the module's own allow-list of settings and looks each
one up in the backup - not the other way round. An entry in the backup naming a
registry path this module does not own is reported as **ignored** and never
written.

This matters because a backup is a JSON file on disk that anyone can edit. A
restore that wrote whatever paths its input named would be an arbitrary registry
writer with a friendly name.

Every write is read back. A write that did not stick is counted as **failed**,
never as restored.

---

## The absent-value problem

This is the part of this module most worth reading, because it is where scripts
of this kind usually get it wrong, and because it is subtle enough to look
correct while being wrong.

**On a default machine, the Delivery Optimization policy key does not exist.**

Applying this module *creates* it. So "undo" cannot mean "write the old value
back" - there was no old value.

| A restore that... | Leaves you with | Which is |
|---|---|---|
| writes `DODownloadMode = 0` | the applied state | the thing you asked to undo |
| writes an assumed default `1` | an explicit policy that was never there | an invention |
| **deletes the value, and the key if it created it** | genuinely not configured | correct |

"Not configured" and "configured to the default" are different states with
different consequences. Not configured means a future administrator's policy
applies cleanly. Explicitly configured means they find a setting nobody remembers
making and have to decide whether it was deliberate.

So the backup records, for every value, **whether the value existed** and
**whether its key existed**. On restore:

- value existed → write it back, with its original type
- value absent, key existed → delete the value, keep the key
- value absent, key absent → delete the value, **and** delete the key - but only
  if it is now empty. If something else has written into that key since, the key
  stays and the script says so.

`6 - Prove the undo works` treats *existed / did not exist* as a difference that
**fails** the test. A round trip that ends with `DODownloadMode = 0` where it
started absent is a failure, even though every value is "correct".

### The related rule about `original-state.json`

`original-state.json` may only be written by a script that is **about to change
something**, from the reading it took **beforehand**. In code that is the
`-RecordAsOriginal` switch on `Save-UdBackup`, which only the apply path passes.

This was a real defect in both modules, fixed on 2026-08-26. Without the switch,
the restore script's own pre-restore snapshot would create `original-state.json`
whenever none existed - recording the **current** state as "original". Because
that file is deliberately never overwritten, a machine that had already been
modified would have "before any of this" permanently defined as "after all of
this", and `5 - UNDO back to the original` would restore to the applied state
forever, with nothing in its output to reveal it.

The fix is one parameter. The lesson is that a write-once file is only as
trustworthy as the rule about who is allowed to write it.

---

## `Test-RoundTrip.ps1` - every option

**In plain terms.** Makes the machine prove the undo, instead of you trusting it.

**Launcher:** `6 - Prove the undo works.cmd`

```powershell
powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1
```

Reads state A, applies for real, reads state B, undoes, reads state C, compares A
with C field by field.

### `-Force`

Skips the `YES` prompt. For unattended use.

### What it compares

- every managed registry value, **and whether it existed**, **and its type**,
  **and whether its key existed**
- every managed firewall rule: present, enabled, profile
- `DoSvc`, `BITS`, `wuauserv`, `UsoSvc` start types - which this module must not
  change, so any movement there is a finding about the module

### "INCONCLUSIVE - nothing moved, so nothing was proved"

If the settings were already where the apply script wanted them, it changed
nothing, so the undo reversed nothing, so the comparison passed trivially.

Both ends of a journey of zero distance are the same place. That is not evidence.
The script says so rather than banking the reassurance. To get a real test, run
`5 - UNDO back to the original` first, then run this again.

*(This was added after a run of module 01's equivalent reported `PASS - 0
setting(s) were changed and all 0 came back`, which is true and worthless.)*

### If the apply step refuses

If the backup cannot be written and verified, the apply step stops and changes
nothing - so there is nothing to undo and the test cannot complete. The script
detects this and says so. That is the safety behaviour working, not a failure of
the test.

---

## The settings this module manages

| # | What | Where | Applied value | Default |
|---|---|---|---|---|
| 1 | `DODownloadMode` | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization` | `0` (DWord) | absent → LAN |
| 2 | `DeliveryOptimization-TCP-In` | Windows Firewall, inbound | disabled | enabled, profile `Any` |
| 3 | `DeliveryOptimization-UDP-In` | Windows Firewall, inbound | disabled | enabled, profile `Any` |

Three settings. That is the whole module.

**Firewall rules are addressed by `Name`, never `DisplayName`.** `DisplayName` is
localised - "Delivery Optimization (TCP-In)" only exists on English Windows.
`DeliveryOptimization-TCP-In` is the same everywhere. A script matching on the
display name silently does nothing on a German or Japanese install *and reports
success while doing it*, which is worse than failing.

### Download mode numbers

| Value | Name | Behaviour |
|---|---|---|
| 0 | CdnOnly | Microsoft servers only, no peer sharing |
| 1 | LAN | **the default** - shares with PCs behind the same NAT |
| 2 | Group | shares within a configured group |
| 3 | Internet | shares with PCs on the internet |
| 99 | Simple | no peering, and no DO cloud service |
| 100 | Bypass | uses BITS instead of Delivery Optimization |

Taken from Microsoft's telemetry field documentation, not from folklore:

> "The download mode used for this file download session (CdnOnly = 0, Lan = 1,
> Group = 2, Internet = 3, Simple = 99, Bypass = 100)."
> - `windows-itpro-docs/privacy/required-windows-diagnostic-data-events-and-fields-2004.md`

**Why 0 and not 99.** Mode 99 also stops peering, but it drops the Delivery
Optimization cloud service as well, which Microsoft describes as providing
"additional metadata ... for a peerless reliable and efficient download
experience". Mode 0 stops the sharing while keeping the efficient download. If
you want to cut the cloud service too, that is a defensible choice, and it is a
one-word edit to `$script:UdRegistry` in `_Common.ps1` - but it is a different
decision from the one this module makes, and it is not the one documented here.

---

## Troubleshooting

| Symptom | Cause | What to do |
|---|---|---|
| "This needs administrator rights" | You ran the `.ps1` directly, or declined the prompt | Use the numbered `.cmd`, approve the Windows prompt |
| Elevation prompt never appears | UAC prompt opened behind another window, or was auto-declined by policy | Check the taskbar; try right-click → Run as administrator |
| Service still reports `Lan` right after applying | DO re-reads its configuration periodically, not instantly | Check again in a few minutes. If it survives a reboot, that is a real finding |
| Port 7680 still listening after applying | Expected - the rules control reachability, the service controls listening | See the note in the apply section. Closing it would mean stopping `DoSvc` |
| Firewall rules re-enable themselves later | Microsoft documents that DO registers its own port. A service restart or update may re-register the rules | Run `1 - Check what is on now` after a reboot. If they came back, the module is not persistent for that half and you should know it |
| `-Confirm:$false` fails with a type conversion error | You used `-File`. Under `-File` everything after the script path is a plain string | Use `-Command "& '.\Script.ps1' -Confirm:$false"` |
| "There is nothing to undo - no backups exist" | The module was never applied on this machine | Nothing to do |
| Restore says a setting was **ignored** | The backup names a registry path this module does not own | Working as intended. The file was edited, or came from elsewhere |
| Round trip says **INCONCLUSIVE** | Nothing moved, so nothing was tested | Run `5 - UNDO back to the original` first, then retry |
| Windows Update stops working after "hardening" | Something disabled `DoSvc` - this module does not | Set `DoSvc` back to Automatic and start it |

---

## What this module deliberately does not do

**It does not disable `DoSvc`.** This is the most common piece of advice on the
subject and it is wrong. `DoSvc` is not a sharing service that also downloads -
it is the **download engine** for Windows Update and the Microsoft Store.
Disabling it does not harden the machine; it makes updates fail quietly until one
day you are months behind on security patches. The supported way to stop the
sharing is the download mode.

**It does not touch BITS, `wuauserv` or `UsoSvc`.** They are reported so you can
see they did not move.

**It does not delete the Delivery Optimization cache.** The service manages it on
its own schedule. Deleting it by hand only forces the machine to download the
same content again - costing you exactly the bandwidth the exercise was supposed
to save.

**It does not defer, pause or reschedule updates.** Delaying security updates is
a separate decision with a real cost, and it does not belong in a module about
peer sharing.

**It does not set a bandwidth cap.** `DOMaxUploadBandwidth` and friends limit how
much of your connection peering may use. They are the right tool if you *want*
peering but want it bounded. This module stops the peering, which makes a cap on
it redundant.

**It makes no performance claim.** `MODULE-STANDARD.md` §15.1 requires that to be
said out loud rather than glossed over: the benefit here is a closed inbound port
and no outbound sharing, which is a security outcome. Your machine will not be
faster. There is no `Measure-` script because there is nothing to measure that
would honestly support the change.
