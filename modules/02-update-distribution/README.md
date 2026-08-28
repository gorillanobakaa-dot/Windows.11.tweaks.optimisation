# Update distribution - who else can reach your PC for Windows updates

## Just want to click something?

Seven files in this folder end in `.cmd` and those are double-clickable. They are
numbered in the order you would normally use them:

| Double-click this | What happens | Admin? |
|---|---|---|
| **1 - Check what is on now** | Shows whether this PC shares updates, and whether anything can connect to it | No |
| **2 - Preview the changes (safe)** | Lists every change that would be made, then makes none | No |
| **3 - Apply the changes** | Backs up, verifies the backup, then stops the sharing | **Yes** |
| **4 - UNDO everything** | Puts back whatever the last run changed | **Yes** |
| **5 - UNDO back to the original** | Goes all the way back to before this was ever used | **Yes** |
| **6 - Prove the undo works** | Applies, undoes, and checks every setting came back | **Yes** |
| **7 - Test the safety logic** | Tests the machinery that decides whether to write anything | No |

## What has actually been proved

| | Result |
|---|---|
| Adversarial audit | **9 findings, all fixed the same day** — including a round trip that could un-apply a deliberately-applied machine and blame the undo, and a restore that trusted value and kind from an editable file |
| Round trip, elevated, on this machine | **PASS** — 3 settings moved (including deleting the created policy key) and all came back |
| Comparison proved falsifiable | a doctored registry entry and a doctored firewall entry are both caught; a null state trips a guard |
| Safety logic self-test | **48 checks, 0 failures** |
| Citations | **5 / 5 verified** against the offline corpus |
| Applied on this machine | **no** — every test left it exactly as it started |

An earlier version of the round trip **printed PASS while comparing nothing**: a
case-insensitive variable collision destroyed the state object on the first row,
every comparison threw, and the empty difference list read as success. The
comparison now uses distinct names, carries a guard that reports
`COMPARISON BROKEN` rather than passing, and is itself tested for the ability to
fail. The full defect list and the rules it produced are in
`MODULE-STANDARD.md` §16.

**`7 - Test the safety logic` is worth running before you trust any of the
others.** It changes nothing, needs no rights, takes a couple of seconds, and
checks the machinery that decides *whether* to write anything: that a file which
is merely JSON-shaped is rejected as a backup, that a backup naming registry
paths this module does not own is refused rather than obeyed, that a failed
backup reports failure so the apply script aborts, that only the apply path can
define "the original state", and that "not set at all" stays distinguishable from
"set to zero" through a round trip to JSON and back.

Every one of those corresponds to a defect that was actually found — most of them
in module 01, by adversarial audit, after it had been written carefully by
someone who believed it was correct. Current count: **48 checks, 0 failures.**

**Four of these ask for administrator rights, and they genuinely need them.**
That is different from the visual-effects module, which never asks. The reason is
simple: these settings are machine-wide. The download mode applies to every
account on the PC, and firewall rules are not per-user at all.

Windows will show its standard "Do you want to allow this app to make changes?"
prompt. That prompt comes from Windows, not from this script. Numbers 1 and 2 do
not ask, because reading and previewing do not need permission.

---

## In plain language

### What Windows is doing

Windows 11 ships with a feature called **Delivery Optimization**. When your PC
downloads a Windows update, it does not only download it — it also keeps a copy
and offers pieces of that copy to other PCs, so they do not each have to fetch
the whole thing from Microsoft.

Microsoft's own documentation describes the default mode this way:

> "This default operating mode for Delivery Optimization enables peer sharing on
> the same network"
> — `win32/desktop-src/delivery_optimization/downloadmode.md`  [R-82]

and defines that network precisely:

> "**LAN**. Gets or sends updates and apps to PCs on the same NAT only."
> — `windows-itpro-docs/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services.md`  [R-83]

### What that actually means for you — and what it does not

**It is not uploading your updates to the internet.** You may have read that it
does. In the default mode it does not. "The same NAT" means the machines behind
your router — the mode that shares with strangers across the internet is a
*different* setting (mode 3), and it is not the default.

So the honest description of the risk is narrower than the popular one, and it
has two parts:

**1. Who is behind your router?** At home, that is your own devices, and sharing
between them is arguably useful — one download instead of four. But "behind the
same router" is not always "yours". Student accommodation, a shared house, a
serviced office, a hotel, an apartment building with shared internet: all of
those put strangers on the same NAT as you. In those places, your PC offering
update data to the network is offering it to people you do not know, on a
connection you may be paying for.

**2. Something is listening, and the door is open.** This is the part that does
not depend on where you are. To take part in sharing, your PC opens **port 7680**
and accepts incoming connections on it:

> "Port 7680 is automatically registered and opened by the Delivery Optimization
> service. If you block port 7680, peer-to-peer functionality is disabled.
> However, devices can still download content using HTTP over port 80 or HTTPS
> over port 443."
> — `windows-itpro-docs/deployment/do/delivery-optimization-configure.md`  [R-85]

Two firewall rules are switched on to let other machines reach it, and on this
machine both are set to the **Any** profile — which includes **Public** networks.
Public is the profile Windows uses for hotel, café and airport Wi-Fi: the exact
places where "everyone behind the same router" means "strangers".

An open, reachable port is attack surface whether or not anything ever connects
to it. That is true of any listener, and it is the part of this that is worth
closing regardless of where you use the machine.

### What was actually measured here — including the inconvenient bit

On this machine, at the time of writing:

| Reading | Value |
|---|---|
| Configured download mode | **not set** — the policy key does not exist at all |
| Mode actually in use | **LAN** (the default when unset) |
| Listening on port 7680 | **yes**, bound to `::` (all addresses) |
| Inbound firewall rules | **both enabled**, profile `Any` (includes Public) |
| Upload bandwidth cap | **100%** — uncapped when it does upload |
| Cache held on disk | ~1,390 MB |
| **Files uploaded to peers** | **0** |
| **Bytes uploaded to peers** | **0** |

That last pair matters and it is stated here rather than buried. **This machine
has not uploaded anything to anyone.**

### But be careful how much that zero is worth

It is true, and it is weak evidence, and saying so is the difference between a
measurement and a talking point.

Windows' own Delivery Optimization activity monitor covers a 25.7-day window and
reports 4.1 GB downloaded from Microsoft's cache servers, 237 MB direct from
Microsoft, and **0.00% from PCs on the local network and 0.00% from PCs on the
internet** — which independently corroborates the counter above, from a different
source, in the Windows UI.

Now the part that undercuts it. Over that same window the machine was barely
running — and establishing *how* barely took three attempts, two of which were
wrong. The wrong ones are kept here because the mistakes are instructive.

**Attempt 1, wrong.** System event log IDs 6005 and 6006 mark the event-log
service starting and stopping — boot and shutdown. That gave 149.7 hours "powered
on", a 24.3% duty cycle. But sleep produces neither event, so a laptop asleep in a
bag counts as fully up.

**Attempt 2, also wrong.** Subtracting `Kernel-Power` 42 (entering sleep) and 107
(resuming) gave a total sleep time of zero. The 42/107 pairs on this hardware are
two seconds apart — they are low-power-idle transitions, not the actual sleep.

**Attempt 3, also wrong.** `Microsoft-Windows-Power-Troubleshooter` does record
the real sleep and wake timestamps. But the boot/shutdown events were only
queried from the start of the window, so a session that had begun *earlier and
was still running* was invisible, and its time landed in "fully off". That
produced the impossible result of a machine 0.0% awake and 89.7% asleep.

**Attempt 4.** Query boot/shutdown from well before the window, clip every
session to it, and count only sleep that overlaps both a real session and the
window.

| State | Time | Share of the 25.7-day window |
|---|---|---|
| Genuinely awake | 63.7 h | **10.3%** |
| Asleep but **network connected** | 552.6 h | **89.7%** |
| Fully off | 0.1 h | **0.0%** |

There is a single boot-to-shutdown session spanning **2026-05-29 to 2026-08-20**.
The machine was never shut down at all. It was used for about a tenth of the
window and spent the rest in standby, on the network.

**The limit of that middle row, stated plainly.** A sleep record has a start and
an end and nothing in between. If the battery went flat part way through, the
machine left the network at that moment, and the event log cannot say when —
a flat battery writes nothing, and looks identical to continued standby. So
89.7% is an **upper bound** on network-connected time, not a measurement of it.
The longest sleep here ran 51.7 days on a laptop battery, which certainly ended
flat rather than in continuous standby.

What it does establish is that this time was not spent *switched off*, which is
the claim people are actually making when they say a machine was in a drawer.

### "In a drawer" is not "off the network"

This is the part worth carrying away, and it is not really about Delivery
Optimization at all.

`powercfg /a` on this machine reports:

```
The following sleep states are available on this system:
    Standby (S0 Low Power Idle) Network Connected
    Hibernate
    Fast Startup
```

S1, S2 and S3 are all unavailable — the firmware does not offer them, and they are
disabled anyway when S0 low-power idle is supported. This laptop has **no
traditional sleep state**. What it has is Modern Standby, and Microsoft's own name
for it ends in *Network Connected*.

A closed laptop in a drawer on this hardware is not a machine that has stopped. It
is a machine in a low-power state, on the network, able to run maintenance, fetch
updates and answer for itself — until the battery runs out, which is what ended
both of the sleeps above. That is the same argument this repository makes about
trigger-start services, arriving from a direction nobody looks at: **judging a
machine's exposure by whether you were using it is a category error.**

On top of all that, LAN mode only shares when **another Windows PC behind the same
router is fetching the same content at the same time**. On a network whose other
machines run Linux, that condition is never met, and the counter would read zero
however the feature were configured.

So the honest reading is:

- **What the zero shows:** on this machine, in this window, nothing was uploaded.
- **What it does not show:** anything about what Delivery Optimization does on a
  machine that is switched on, or on a network with other Windows PCs on it. A
  zero produced by absence of opportunity is not a zero produced by absence of
  behaviour, and this page will not treat the two as the same.

**None of the module's actual case rests on that counter.** The listener bound to
all addresses, the two inbound rules on the `Any` profile including Public, and
the uncapped upload rate are facts about how the machine is *configured*. They are
true whether it has been running for six days or six years, and they are what the
module changes.

If a page tells you this setting has been costing you money, ask it for your own
machine's upload counter **and** its uptime. The first number without the second
is decoration.

### What this module does about it

Two changes:

**1. Sets the download mode to CdnOnly.** Windows keeps downloading updates
exactly as before, from Microsoft's servers:

> "This setting disables peer-to-peer caching but still allows Delivery
> Optimization to download content from Microsoft servers. This mode uses
> additional metadata provided by the Delivery Optimization cloud services for a
> peerless reliable and efficient download experience."
> — `win32/desktop-src/delivery_optimization/downloadmode.md`  [R-81]

**2. Disables the two inbound firewall rules** for port 7680, so other machines
cannot open a connection to yours.

### What it deliberately does not do

**It does not disable the Delivery Optimization service.** This is the advice you
will find in most "debloat" guides and it is wrong. `DoSvc` is not a sharing
service that also happens to download — it is the **download** engine for Windows
Update and the Microsoft Store. Turning it off does not make you safer; it makes
your updates fail, quietly, until one day you notice you are months behind. The
supported way to stop the sharing is the download mode, which is what this module
uses.

It also does not touch BITS, `wuauserv` or `UsoSvc`; does not delete the cache
(the service manages that itself, and deleting it by hand only forces a
re-download); and does not defer, pause or reschedule updates. Delaying security
updates is a separate decision with a real cost, and it does not belong in a
module about peer sharing.

### What you will and will not notice

Nothing, in normal use. Updates download the same way from the same place.

The one case where you might: if you have several Windows PCs at home on the same
router, they will each now download updates separately from Microsoft instead of
sharing between themselves. On a metered or slow connection with several PCs,
that is a real cost, and it is the case where leaving this alone is the better
decision. This module has no opinion about which matters more to you — it just
makes the choice reversible.

---

## Undoing it, and the one thing that makes this module different

Run **`4 - UNDO everything`**. No arguments, no picking a backup.

There is a wrinkle here that the visual-effects module never had, and it is worth
understanding because it is where this kind of script usually gets it wrong.

On a default machine, the Delivery Optimization policy key **does not exist**.
Applying this module *creates* it. So "undo" cannot mean "write the old value
back" — there was no old value.

A lazy undo would write `DODownloadMode = 0`… which is the applied state. A
slightly less lazy one would write some assumed default like `1`, which is worse:
it invents a configuration that was never there. The correct undo is to **delete
the value**, and to delete the key as well if this module created it and nothing
else has been written into it since.

"Not configured" and "configured to the default" are different states. The first
means a future administrator's policy will apply cleanly. The second means they
will find an explicit setting they have to reason about, that nobody remembers
making. This module restores to the first.

`6 - Prove the undo works` checks exactly that, and treats "existed / did not
exist" as a difference that fails the test.

---

## Technical detail

**Settings managed.** One registry value and two firewall rules:

| What | Where | Applied value |
|---|---|---|
| `DODownloadMode` | `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization` | `0` (DWord) |
| `DeliveryOptimization-TCP-In` | Windows Firewall, inbound | disabled |
| `DeliveryOptimization-UDP-In` | Windows Firewall, inbound | disabled |

Mode numbers are taken from Microsoft's own telemetry field documentation rather
than from folklore:

> "The download mode used for this file download session (CdnOnly = 0, Lan = 1,
> Group = 2, Internet = 3, Simple = 99, Bypass = 100)."
> — `windows-itpro-docs/privacy/required-windows-diagnostic-data-events-and-fields-2004.md`  [R-84]

**Firewall rules are addressed by `Name`, never `DisplayName`.** The display name
is localised; `DeliveryOptimization-TCP-In` is not. A script matching on
"Delivery Optimization (TCP-In)" silently does nothing on a non-English Windows,
and reports success while doing it.

**Configured versus effective are read separately.** `1 - Check what is on now`
reports what the registry says *and* what the Delivery Optimization service
itself reports it is using. Those can disagree — and on Windows **Home**, where
there is no Group Policy editor and some policies are silently ignored, that
disagreement is exactly the thing worth watching for. The apply script re-reads
the service afterwards and says so if the two do not line up.

**The listener is checked, not assumed.** The report reads the actual listening
socket on port 7680 rather than inferring it from the configuration. If the port
is still open after applying, the script says so plainly rather than claiming a
result it did not achieve — an open socket behind a disabled inbound rule is a
smaller exposure than an open socket behind an allow rule, but it is not zero,
and closing it entirely would mean stopping the service that downloads your
updates.

**Backup before change, verified.** The backup is written, read back, parsed, and
checked for the sections a restore needs. If any of that fails, the apply script
stops and changes nothing. Every applied write is read back; a write that did not
stick is reported as failed rather than counted as a success.

**Restore is driven by the module's own allow-list**, not by the contents of the
backup file. An entry in the file naming a registry path this module does not own
is reported as ignored and never written. A backup file is data, and data can be
edited.

**`-WhatIf` loads its modules up front.** PowerShell auto-loads a module the first
time one of its commands runs; if that happens under `-WhatIf`, it narrates every
alias the module defines and buries the preview under twenty lines of noise about
`Set Alias`. `_Common.ps1` imports them first with `-WhatIf` explicitly off.

---

## What is NOT claimed

- **No performance claim.** This module makes the machine no faster. Per
  `MODULE-STANDARD.md` §15.1 that is stated rather than glossed over: the benefit
  here is a closed inbound port and no outbound sharing, which is a security
  outcome, not a speed one. There is no `Measure-` script because there is
  nothing to measure that would honestly support the change.
- **No claim that bandwidth was being consumed.** On this machine it was not.
  Zero bytes, zero files, zero peers.
- **No claim that the port stops listening.** The firewall rules stop things
  reaching it. Only stopping `DoSvc` would close the socket, and that breaks
  Windows Update.
- **No claim about editions other than the one it was tested on.** Windows 11
  Home, build 26200. Policy handling differs by edition and this module reports
  what the service says rather than assuming the policy took.

---

## References

Every quotation on this page carries a tag. The table below gives, for each one,
the exact file in Microsoft's published documentation, the line it starts on, and
the sentence itself.

**You do not have to take any of it on trust.** The table is in the same machine-
readable format as `FINDINGS.md`, so the repository's own citation checker can be
pointed at this page and will confirm every quote is present, word for word, in
your own copy of the corpus:

```bash
powershell -ExecutionPolicy Bypass -File ..\..\READ-ONLY-verification\Verify-Citations.ps1 -Document .\README.md -Detailed
```

It contains no AI and makes no judgements. It compares strings against primary
sources and exits non-zero if anything is wrong.

| ID | Claim | rel_path | line | quote |
|---|---|---|---|---|
| R-81 | CdnOnly stops peer sharing but keeps downloading from Microsoft | win32/desktop-src/delivery_optimization/downloadmode.md | 47 | This setting disables peer-to-peer caching but still allows Delivery Optimization to download content from Microsoft servers. |
| R-82 | LAN is the default mode and it enables peer sharing | win32/desktop-src/delivery_optimization/downloadmode.md | 54 | This default operating mode for Delivery Optimization enables peer sharing on the same network |
| R-83 | LAN mode shares only with PCs behind the same NAT, not the internet | windows-itpro-docs/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services.md | 1658 | LAN. Gets or sends updates and apps to PCs on the same NAT only. |
| R-84 | Download mode numbering | windows-itpro-docs/privacy/required-windows-diagnostic-data-events-and-fields-2004.md | 8278 | The download mode used for this file download session (CdnOnly = 0, Lan = 1, Group = 2, Internet = 3, Simple = 99, Bypass = 100). |
| R-85 | Port 7680 is opened automatically by the service | windows-itpro-docs/deployment/do/delivery-optimization-configure.md | 830 | Port 7680 is automatically registered and opened by the Delivery Optimization service. |
