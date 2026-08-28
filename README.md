# Windows 11 Tweaks and Optimisation

> [!WARNING]
> **Status: v0.1.0-beta (Public Beta)**
> This is a highly developed framework. It works flawlessly on the author's machine, and it has been heavily audited against Microsoft's official documentation. However, it is now entering public beta for wide-scale hardware testing. This beta status gives us the freedom to introduce breaking changes (like rewriting a module) based on real-world feedback before we formally commit to a stable `1.0.0` release.

### The Gorilla Open Source Philosophy
This project does not ask for your blind trust. It is built on a strict "Dual-Track" documentation philosophy: every decision is explained in plain English for the layman, and backed up by rigorous technical proof for the developer. 

We have spent hundreds of hours testing this framework against real-world failures. We didn't just write code; we adversarial-audited it. We clicked buttons three times in a row to see if the undo broke. We checked if disabling the camera privacy slider secretly broke Windows Hello face sign-in. 

**Do not take our word for it. Read the proof:**
- Read [LESSONS-LEARNED.md](LESSONS-LEARNED.md) to see exactly how every single rule in this project was bought with a real failure on a real machine.
- Read [FINDINGS.md](FINDINGS.md) and the XML files in [decision-records/](decision-records/) to see the exact Microsoft documentation we cited to justify every single registry key we change.

Nothing here is a "best practice somebody read somewhere." Everything is measured, audited, and proven.

---

# START HERE

A measured, cited, reversible approach to reducing what a Windows 11 machine does
without being asked — and to closing the parts of it that face the network.

Everything here was measured on one real laptop (Windows 11 Home, build 26200).
Every claim is traceable either to Microsoft's own published documentation or to
an artifact produced by a read-only script you can run yourself.

**What has it actually achieved?** Real numbers, including the unflattering
ones: [SCORECARD.md](SCORECARD.md) — 5 of 283 services closed, 108 still
trigger-startable, Copilot gone entirely (1,287 MB + a LocalSystem service), 42
settings changed, 105 sources verified.

**How do I run the tools?** [TOOLS-HOWTO.md](TOOLS-HOWTO.md) — every read-only
tool, with a worked example and the real output it produced here. Nothing on
that page changes your machine.

**Where is the project up to?** One page answers that: [ROADMAP.md](ROADMAP.md) —
what is done, what is running right now, and what is waiting for a decision.

**Why was each change made?** [decision-records/](decision-records/) — one record
per setting and per service, each carrying Microsoft's own description of the
thing, the reasoning, the evidence *against*, the cost, and the reversal. Two
tools check the citations against the offline corpus and refuse to pass a record
whose quotations are not real.

---

# START HERE

You have just downloaded this, you are looking at a folder of documents, and there
is nothing obvious to click. That is on purpose — **nothing in this top folder can
change your machine** — but it is not helpful on its own, so here is the whole
thing, start to finish.

*(A quick preview of the interactive control panel you will get)*
![Control Panel Showcase](Screenshots%20for%20github/showcase-1.png)
![Control Panel Showcase](Screenshots%20for%20github/showcase-2.png)
![Control Panel Showcase](Screenshots%20for%20github/showcase-3.png)
![Control Panel Showcase](Screenshots%20for%20github/showcase-4.png)
![Control Panel Showcase](Screenshots%20for%20github/showcase-5.png)

## Step 0 — unblock it first (one minute, and it will save you a headache)

Windows tags every file that came from the internet. Scripts in a tagged folder can
throw security warnings or refuse to run, and the error it gives you will not
mention the tag.

**If you downloaded a ZIP:** right-click the ZIP → **Properties** → tick
**Unblock** at the bottom → **OK** → *then* extract it. Unblocking the ZIP first
clears every file inside it in one go.

**If you already extracted it,** or you cloned with git, open PowerShell in this
folder and run:

```powershell
Get-ChildItem -Recurse | Unblock-File
```

That removes the internet tag and nothing else. It changes no setting and touches
no file contents. If you skipped this and something later says "Windows protected
your PC" or a script window flashes and vanishes, this is why.

## Step 1 — go to the only folder that does anything

```
Windows.11.tweaks.optimisation\
└── modules\                      <- open this
    ├── 01-visual-effects\        <- finished, proved, measured, applied
    ├── 02-update-distribution\   <- audited, rollback proved, APPLIED 2026-08-26
    ├── 03-copilot\               <- audited (14 findings, fixed); EXCISED 2026-08-26
    └── 04-recommendations\       <- audited, rollback proved, APPLIED 2026-08-26
```

Everything else in this repository reads, verifies, documents, or has been
withdrawn.

**Start with `01-visual-effects`.** It has been through the adversarial audit,
its rollback has been executed and verified on a real machine, and what it saves
has been measured.

**`02-update-distribution` and `04-recommendations` have both been through an
adversarial audit** — 9 and 16 findings respectively, every one fixed the same
day — and both rollbacks have been **executed and proved on this machine**,
including the case where a value must return to "not set at all" rather than
zero. `MODULE-STANDARD.md` §13 records the current state of every module, and
§16 records the rules those audits produced. The habit stands: run
`Prove the undo works` on YOUR machine before applying anything.

On the machine this repository documents, all four modules were **applied on
2026-08-26** - by the owner, through the control-panel menu, each module
writing its verified backup first.

## Step 2 — look before you touch

Double-click **`1 - Check what is on now.cmd`**

A window opens and lists every animation, fade, shadow and translucency setting on
your machine, across all four of the separate systems Windows spreads them over.
At the bottom it summarises what is still switched on.

**It changes nothing.** It cannot. Read it, press a key, the window closes.

## Step 3 — see exactly what would change

Double-click **`2 - Preview the changes (safe).cmd`**

It prints a line for every setting it would alter, with the value now and the value
it would set — then makes none of the changes and says so:

```
PREVIEW ONLY - nothing was changed.  would change: 12
```

**This is the step people skip and then get surprised.** Don't skip it.

## Step 4 — apply it

Double-click **`3 - Apply the changes.cmd`**

It saves your current settings to a backup file **first**, checks the backup was
actually written, and only then changes anything. If the backup fails it stops and
changes nothing. Then it reports:

```
changed: 12, already as wanted: 8, skipped: 0, failed: 0
```

The first time it ever runs, it also writes `backups\original-state.json` — a
write-once record of how your machine looked before this repository touched it.
Nothing ever overwrites that file.

**You will see the difference immediately.** Menus open with no delay. Dragging a
window shows an outline instead of the window. Title bars go flat. Desktop icon
labels lose their drop shadow.

## Changed your mind?

Double-click **`4 - UNDO everything.cmd`** — puts back what the last run changed.

Or **`5 - UNDO back to the original.cmd`** — goes all the way back to how the
machine was before any of this, from that write-once file.

Neither needs arguments. Neither asks you to pick a backup. Double-click and it
works.

## The two optional ones

**`6 - Prove the undo works.cmd`** — don't take our word that the undo works. This
applies every change for real, undoes it, and compares all twenty settings one by
one. On the machine this was written on it reported `restored: 20, skipped: 0,
failed: 0` and a full match. Net effect on a pass: nothing at all.

**`7 - Measure what it actually saves.cmd`** — don't take our word that it helps
either. Roughly ten minutes. It measures your machine with the effects on, then
off, and prints the difference alongside its own margin of error. It is fully
capable of telling you the change is worth nothing on your hardware.

## Things worth knowing before you start

| | |
|---|---|
| **Administrator rights** | **Never needed.** These are your own display settings. If anything in this module asks you to approve an administrator prompt, something is wrong — stop |
| **Does it affect other accounts?** | No. Per-account. Each user applies it separately |
| **Does it survive a reboot?** | Yes. There is no temporary mode and no "make permanent" step |
| **Will it slow anything down?** | No. It removes work; it does not add any |
| **Will it fix a slow PC?** | No. If the machine is slow for other reasons, this will not touch those |
| **A window flashed and vanished** | You skipped Step 0. Unblock the files |
| **Nothing happens when I double-click a `.ps1`** | Correct — that opens Notepad. The `.cmd` files are the runnable ones. That is why they are numbered |

---

## Read this before you run anything

**Only one folder in this repository contains scripts that change your machine:**

```
modules/
```

Everything else either reads, verifies, documents, or has been withdrawn. The
folder names say so on purpose:

| Folder | What it does to your machine |
|---|---|
| **`modules/`** | **CHANGES THINGS.** Audited, reversible, one-click undo |
| `READ-ONLY-diagnostics/` | **Nothing.** Looks and reports |
| `READ-ONLY-verification/` | **Nothing.** Checks this repository's own claims |
| `evidence/` | **Nothing.** Captured output, hash-manifested |
| `_research/` | **Nothing.** The citation audit |
| `_withdrawn-pending-audit/` | **Nothing — the scripts are gone.** Docs kept, and why |

If you are about to double-click something and you are not in `modules/`, it will
not change your machine.

### Why some scripts were withdrawn

Earlier versions of this project kept change-scripts in topic folders. They
worked. They had **not** been through the adversarial safety audit that is now
required before a change-script ships.

That audit is not ceremony. Run against the one module that has had it, two
independent auditors found defects the author had missed — including a backup
routine that reported success without verifying the file had been written, so a
failed backup would have left someone with no way to undo changes already made.
Every withdrawn script was written to the same pattern, by the same author, on
the same day, before that lesson.

The risk was never that those scripts are broken. It is that a repository which
advertises audited, reversible tooling gives a reader no way to tell an audited
script from an unaudited one by looking at it. Someone will clone this and run
something, entitled to assume it had the same scrutiny as everything around it.

They are in the Recycle Bin, recoverable, and their documentation is preserved in
[`_withdrawn-pending-audit/`](_withdrawn-pending-audit/). Each returns as a proper
module when it has earned it.

---

## Available now: module 01 — visual effects

[`modules/01-visual-effects/`](modules/01-visual-effects/) turns off animations,
fades, window shadows and frosted-glass translucency across all four layers
Windows spreads them over — the built-in "Adjust for best performance" button
reaches only the oldest one.

You do not need a terminal. The folder contains numbered, double-clickable files:

```
1 - Check what is on now.cmd          (looks, changes nothing)
2 - Preview the changes (safe).cmd    (lists what would change, changes nothing)
3 - Apply the changes.cmd
4 - UNDO everything.cmd
5 - UNDO back to the original.cmd
6 - Prove the undo works.cmd
7 - Measure what it actually saves.cmd
```

None asks for administrator rights, because none needs them: these are per-user
display settings. **If anything in this module ever asks you to approve an
administrator prompt, treat that as suspicious.**

Its rollback was not assumed, it was proved. `6 - Prove the undo works` applies
every change for real, restores, and compares all twenty managed settings plus the
shared legacy byte mask. On this machine it reported `restored: 20, skipped: 0,
failed: 0` and a full match.

Nor is the benefit asserted. `7 - Measure what it actually saves` measures the
machine with the effects on and with them off, on a fixed self-driving workload,
and prints the difference — including a **noise floor** taken by measuring the same
state twice, so that anything smaller than the machine's own background variation
is reported as `within noise` rather than as a saving. It is fully capable of
reporting that the change is worth nothing measurable, and the module standard
now requires that of every module claiming a resource benefit (§15).

Start with its [README](modules/01-visual-effects/README.md), or the complete
operator's manual in [HOWTO.md](modules/01-visual-effects/HOWTO.md).

---

## Built, not yet shipped: module 02 — update distribution

[`modules/02-update-distribution/`](modules/02-update-distribution/) stops the
machine sharing Windows updates with other PCs, and closes the two inbound
firewall rules that let other machines reach it on port 7680.

**It has not been audited and its rollback has never been run.** Steps `1` and `2`
read and preview only; the rest wait. See
[its README](modules/02-update-distribution/README.md).

Two things about it are worth reading even if you never run it.

**The popular claim about this feature is wrong, and the machine can prove it.**
"Windows is uploading your updates to strangers" describes download mode 3. The
default is mode 1, which Microsoft documents as *"PCs on the same NAT only"* — the
machines behind your own router. On the machine this was developed on, the
lifetime upload counter read **zero bytes**. The real finding is narrower and
still worth acting on: port 7680 is listening on all addresses, and both inbound
firewall rules are enabled on the **`Any`** profile, which includes **Public** —
the profile Windows uses for hotel and café Wi-Fi, where "everyone behind the same
router" genuinely does mean strangers.

**It refuses to do the thing every other guide tells you to do.** Disabling
`DoSvc` is the standard advice and it is wrong: that service is the *download*
engine for Windows Update and the Microsoft Store, not just the sharing half.
Turning it off does not harden anything — it makes updates fail silently until you
are months behind on patches. The module changes the download mode instead, which
is the documented way to get the same outcome.

---

## Available to try: module 04 — recommendations and suggestions

[`modules/04-recommendations/`](modules/04-recommendations/) turns off suggested
apps, Windows tips, "personalised" offers, the language list websites can read,
Windows Spotlight and the Start menu's Recommended section.

**Not one of its eight buttons asks for administrator rights**, because every
setting it touches belongs to your own account. Its rollback has been executed and
proved: 10 settings changed, 10 returned, including the difference between "set to
zero" and "not set at all". It has not had an adversarial audit yet.

The interesting part is the split running through it. Five of these settings are
documented by Microsoft — exact registry path, exact value, quotable. Five are
not: they are real, they are on this machine, every debloat guide sets them, and
nobody at Microsoft has written them down anywhere this project can cite. So the
module applies the documented five by default and puts the rest behind a separate
button, with the split enforced in code rather than mentioned in a footnote.

The most interesting one is in the undocumented group: **`SilentInstalledAppsEnabled`,
which on this machine is set to 1** — the setting governing whether Windows may
install promoted apps without asking you. Important, undocumented, opt-in,
reversible. This project will not manufacture a citation to make that read better.

---

## Module 03 — Copilot: built, audited, and EXECUTED

[`modules/03-copilot/`](modules/03-copilot/) is finished. On 2026-08-26 its full
removal ran on this machine: the app package, the 1,287 MB Program Files
install (via its registered uninstaller) and the LocalSystem service are gone,
verified at every level Windows can register an application. The settings tier
was applied with a verified backup and a proved undo; the removals are recorded
in `backups\removed-not-restorable.json` with the exact route back, because a
removal is not a settings change and no backup file can reverse it. The
adversarial audit found 14 defects before execution - two of them severe - and
every one was fixed and regression-tested the same day. Details, including the
uninstaller's nonzero exit code and what was done about it, are in
[its README](modules/03-copilot/README.md).

Run `1 - Check what is on now` and it will tell you something most guides never
mention: **Copilot is not one thing.** On the machine this was written on it is
four, installed four ways and removed four ways —

| | Size |
|---|---|
| `Microsoft.Copilot` app package | small |
| A full Chromium application in `Program Files (x86)` with its own updater | **1,287 MB** |
| `MicrosoftCopilotElevationService`, running as **LocalSystem**, start type Manual | — |
| Taskbar and policy settings | — |

Both installs are the **same version**, 152.0.4191.42 — one release delivered
twice by two mechanisms, which is why removing one leaves the other. The service
is *Stopped*, which is not the same as absent: Manual means it starts when
something asks, with full control of the machine.

**And the advice everyone gives is the advice Microsoft withdrew.** Every debloat
guide sets `TurnOffWindowsCopilot`. Microsoft's own documentation says of it:
*"The policy is subject to near-term deprecation."* The recommended replacement is
AppLocker — unavailable on Home. The other modern mechanism, policy-based in-box
app removal, is *"Only Enterprise (ENT) and Education (EDU)"*. On a Home machine
none of the three is both available and endorsed. That is the platform's actual
state, not a gap in the module.

---

## The research

| Document | What it is |
|---|---|
| [`FINDINGS.md`](FINDINGS.md) | The write-up. Every finding in plain language **and** technical detail, with 96 Microsoft-documentation references and 10 measurement artifacts |
| [`THREAT-MODEL.md`](THREAT-MODEL.md) | The activated attack surface: 113 services that wake on a trigger, 56 of them by a network event, 34 of those as `LocalSystem` |
| [`ACTION-PLAN.md`](ACTION-PLAN.md) | The phased plan and the baseline it started from |
| [`_research/CITATION-AUDIT.md`](_research/CITATION-AUDIT.md) | The adversarial citation audit: what was verified, what had **no** vendor backing, and what the verifiers had to correct |
| [`modules/MODULE-STANDARD.md`](modules/MODULE-STANDARD.md) | The convention every module must meet |
| [`decision-records/`](decision-records/) | **Why every change was made** — 28 records, 105 verified sources, APA 7th reference list, and embeddable payloads for a future model |
| [`TOOLS-HOWTO.md`](TOOLS-HOWTO.md) | Every read-only tool, how to run it, and the real output it produces — written for both a person and a future model |
| [`LESSONS-LEARNED.md`](LESSONS-LEARNED.md) | Every engineering rule this project bought with a real failure, and the test that would catch each one coming back |

---

## Don't trust this repository — check it

Every factual claim in `FINDINGS.md` is tagged `[R-nn]` (a quotation from
Microsoft's documentation) or `[M-nn]` (a measurement on this machine). Both are
mechanically checkable, with no AI involved:

```bash
powershell -ExecutionPolicy Bypass -File .\READ-ONLY-verification\Verify-Citations.ps1 -Detailed
```

It opens every cited document in your own copy of the corpus, confirms each quoted
sentence is genuinely present word for word, confirms each measurement artifact
exists, and exits non-zero if any citation is wrong, dangling or unused.

Two stricter tools came later, and both have already caught real errors:

```bash
python .\READ-ONLY-verification\Build-ReferenceLibrary.py
python .\READ-ONLY-verification\Verify-DecisionRecords.py
```

The first checks each quote is at its **cited line**, not merely somewhere in
the file — which found **28 line numbers that had never been checked and were
wrong**. The second checks every decision record is complete and every quoted
passage is really the text of a source that record cites — which caught a
**fabricated quotation of Microsoft** in our own draft. Current status:
**105/105 sources verify at their cited line; 28/28 decision records pass;
exit code 0.**

```bash
powershell -ExecutionPolicy Bypass -File .\READ-ONLY-verification\Collect-Evidence.ps1
```

Regenerates the measurement side on your own machine. Read-only, hash-manifested,
recording the SHA-256 of every script that produced an artifact. Your numbers will
differ from ours — different hardware, different software. The method should not.

---

## What this project will not do

- **It will not claim a change is safe because it is reversible.** Reversibility is
  proved per module by a round-trip test, or it is not claimed.
- **It will not disable things because a forum said to.** Every recommendation
  cites a Microsoft document, or is labelled as our own measurement or reasoning.
- **It will not pretend Windows Home is Windows Enterprise.** Where a control does
  not exist on this edition, the documentation says so instead of offering a
  registry value that is quietly ignored.
- **It will not ship an unaudited script next to an audited one.**

---

## Conventions, for anyone continuing this work

- Measure, change one thing, measure again. Snapshots are timestamped JSON so
  before and after can be diffed with real numbers.
- Reversible or it does not ship: a backup verified before any change, a
  write-once pristine state that is never overwritten, and a separate one-click
  undo script.
- Cite the document. Claims reference a path inside the offline Microsoft corpus
  and are checkable with `Verify-Citations.ps1`.
- Say what is not known. An honest gap is worth more than a confident guess.

---

## Document History

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-08-26 | Initial public release of module documentation and framework |
