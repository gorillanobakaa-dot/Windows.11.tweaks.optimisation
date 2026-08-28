# Blast radius: DPS, WdiServiceHost, WdiSystemHost

*The three services the MODERATE profile named and could not disable. What they
actually are, what actually breaks, and what the Microsoft corpus on this
machine actually says — quoted, with the file and line.*

---

## Why this page exists

The MODERATE profile was applied on 2026-08-27 at 16:15:36. It disabled 114
services. Three writes failed:

```
DPS  ·  WdiServiceHost  ·  WdiSystemHost
```

They failed because their registry keys grant `BUILTIN\Administrators` **read
only**. That is a mechanism problem, covered in `DEC-06-010`. This page answers
the prior question: *before* we work around the lock, **should** these three be
closed, and what happens to the machine if they are?

The rule here is the project's rule. Every claim about what these services do
is either a quotation from the Microsoft documentation on this machine, with a
file and a line you can open, or a measurement taken from this machine, or it
is labelled as neither.

---

# Track 1 — the plain-language version

## What these three things are

They are Windows' **self-diagnosis system**. Think of a building with a
maintenance inspector:

| | Role |
|---|---|
| **DPS** (Diagnostic Policy Service) | The inspector's **supervisor**. Decides which inspections happen and when. Starts at boot, always. |
| **WdiServiceHost** (Diagnostic Service Host) | The inspector who does **low-privilege** jobs. |
| **WdiSystemHost** (Diagnostic System Host) | The same inspector doing the jobs that need **the keys to everything**. Runs as LocalSystem. |

The two "hosts" are literally the same program — both are `wdi.dll` — started
twice at two different privilege levels. That is not a guess; it is Microsoft's
own description:

> "The Diagnostic Service Host is used by the Diagnostic Policy Service to host
> diagnostics that need to run in a **Local Service** context." [R-108]

> "The Diagnostic Policy Service uses the Diagnostic System host to host
> diagnostics that need to run in a **Local System** context." [R-109]

Neither host does anything by itself. They are **containers**. DPS hands them a
small program — a "diagnostic module" — and they run it. On this machine there
are **29 registered modules pointing at 15 different DLLs**, and **54
registered scenarios** that can call them.

## Is any of this actually running here?

Yes. This is not theoretical. Measured on this machine:

| Log | Records | Newest |
|---|---|---|
| `Microsoft-Windows-Diagnosis-DPS/Operational` | **126** | 2026-08-27 16:18:46 |
| `Microsoft-Windows-Diagnosis-PCW/Operational` | **1508** | 2026-08-27 17:02:18 |
| `Microsoft-Windows-Diagnosis-Scheduled/Operational` | **91** | 2026-08-27 16:32:03 |
| `Microsoft-Windows-Diagnosis-Scripted/Operational` | **52** | 2026-08-27 16:32:03 |

Two things run regularly:

1. **Performance checks at every boot and shutdown.** `diagperf.dll` detects a
   "problem", opens a troubleshooting scenario, and closes it. 46 detections in
   the log.
2. **A maintenance check roughly weekly.** The scripted engine runs a package
   from `C:\WINDOWS\diagnostics\scheduled\Maintenance`. It has run **13 times**
   since March, and **every single run** ended with:

   > *"System maintenance detected issues requiring your attention. A
   > notification was sent to Security and Maintenance."*

   Thirteen out of thirteen. Whatever it is finding, it has been finding it for
   five months and nothing has been fixed by it.

## What breaks if you close all three

Honest list. These stop:

- **Boot and shutdown performance logging.** Microsoft states this outright:
  > "With the DPS service disabled, this setting has no effect, as Windows
  > doesn't log performance data." [R-113]
- **The weekly maintenance scan** and its Security-and-Maintenance notifications.
- **The low-memory warning.** `radardt.dll` / `radarrs.dll` are the Resource
  Exhaustion Detector and Resolver — the thing that says *"Close programs to
  prevent information loss"*. This is the loss most likely to be noticed.
- **The built-in troubleshooters** under Settings → System → Troubleshoot, to
  the extent they still route through this engine.
- **Network diagnostics** (`netdiagfx.dll`), the *Diagnose* button on a
  connection.
- **Disk failure prediction** (`DFDTS.dll`), **hardware error triage**
  (`whealogr.dll`), **Fault Tolerant Heap** (`fthsvc.dll`), **Program
  Compatibility Assistant diagnostics** (`pcadm.dll`).

And this is what does **not** break, which matters just as much:

- **Nothing fails to start.** No service and no driver on this machine declares
  a dependency on any of the three. Checked directly, including drivers.
- **Sign-in, boot, networking, Windows Update, Defender and the firewall are
  untouched.** None of the three is on the never-touch or lockout-risk list for
  any reason connected to those.
- **Alt-Tab is unaffected.** None of the three is one of the 16 shell-critical
  services.

## So is closing them reasonable?

Microsoft itself lists DPS and WdiSystemHost among services **"that may be
considered to disable"** [R-110], and states the cost in one sentence:

> "Disabling this service disables the ability to run Windows diagnostics." [R-111]

That is the whole trade. You lose Windows' ability to diagnose itself. You do
not lose the ability to *use* the machine.

**The honest counterweight:** that guidance is written for **virtual desktop
infrastructure** — fleets of disposable VMs where a broken machine is deleted
and rebuilt, not diagnosed. This is a personal laptop. When something goes
wrong here, the diagnostic history is the thing you would want. Five months of
`MaintenanceDiagnostic` runs saying "issues requiring your attention" is
evidence the subsystem is at least *trying* to tell you something.

---

# Track 2 — the developer / sysadmin version

## Architecture, as installed

```
  DPS  (dps.dll — "WDI Diagnostic Policy Service")
    svchost.exe -k LocalServiceNoNetwork -p     account: NT AUTHORITY\LocalService
    Start = 2 (Automatic)          no start triggers
        |
        |  hands a scenario + module to one of two hosts
        v
  WdiServiceHost  (wdi.dll — "Windows Diagnostic Infrastructure")
    svchost.exe -k LocalService -p              account: NT AUTHORITY\LocalService
    Start = 3 (Manual)             no start triggers

  WdiSystemHost   (wdi.dll — same binary)
    svchost.exe -k LocalSystemNetworkRestricted -p   account: LocalSystem
    Start = 3 (Manual)             no start triggers
```

Three facts worth pinning down, because each contradicts an assumption that is
easy to make:

**1. None of the three carries a start trigger.** `sc qtriggerinfo` returns
*"has not registered for any start or stop triggers"* for all three. So the
usual framing for this project — *Manual means trigger-startable* — **does not
apply here**. The Wdi hosts are started by DPS through WDI activation, and DPS
is Automatic. The activation path is the parent service, not the trigger
subsystem.

**2. Nothing declares a dependency on them.** A full sweep of
`DependOnService` across every key under `CurrentControlSet\Services`,
**including drivers**, returns nothing for all three. They also declare no
dependencies of their own.

This is the exact shape that burned this project before — `StorSvc`, `DsSvc`,
`NcbService`, `TimeBrokerSvc` all had zero declared dependents and all were
wrong to disable. Here the corpus was read first, which is the whole point of
this page. The conclusion happens to be different, but the method is what
matters: **`DependOnService` records declared SCM edges, not activation.**

**3. The two hosts are one binary.** Both resolve to
`C:\WINDOWS\system32\wdi.dll`. The only difference is the svchost group, and
therefore the token. `LocalSystemNetworkRestricted` for the system host,
`LocalService` for the other.

## The extensibility surface

`HKLM\SYSTEM\CurrentControlSet\Control\WDI` holds:

- `DiagnosticModules` — **29 registrations** → **15 distinct DLLs**
- `Scenarios` — **54 registrations**

| DLL | `FileDescription` (read from the binary) |
|---|---|
| `diagperf.dll` | Microsoft Performance Diagnostics — **13 of the 29 modules** |
| `radardt.dll` | Microsoft Windows Resource Exhaustion Detector |
| `radarrs.dll` | Microsoft Windows Resource Exhaustion Resolver |
| `netdiagfx.dll` | Network Diagnostic Framework |
| `pcadm.dll` | Program Compatibility Assistant Diagnostic Module |
| `APPHLPDM.DLL` | Application Compatibility Help Module |
| `DFDTS.dll` | Windows Disk Failure Diagnostic Module |
| `whealogr.dll` | WHEA Troubleshooter |
| `fthsvc.dll` | Microsoft Windows Fault Tolerant Heap Diagnostic Module |
| `pnpts.dll` | PlugPlay Troubleshooter |
| `pots.dll` | Power Troubleshooter |
| `cofiredm.dll` | Corrupted File Recovery Diagnostic Module |
| `msicofire.dll` | Corrupted MSI File Recovery Diagnostic Module |
| `DXGWDI.DLL` | Microsoft DirectX Graphics WDI Handler |
| `srumsvc.dll` | System Resource Usage Monitor Service |

### Can that surface be abused?

**Weaker than it first looks — state it accurately.** The obvious attack is
registering a rogue module and getting it loaded into a LocalSystem svchost.
The ACL on `Control\WDI\DiagnosticModules` blocks the casual version:

```
NT SERVICE\TrustedInstaller     Allow  FullControl
NT AUTHORITY\SYSTEM             Allow  ReadKey
BUILTIN\Administrators          Allow  ReadKey
BUILTIN\Users                   Allow  ReadKey
```

**TrustedInstaller owns write.** Not SYSTEM, not Administrators. An attacker
already holding admin would have to take ownership first — a noisy, auditable
act, and one that is a defeat condition on its own. So this is **not** a
quiet privilege-escalation or persistence path, and it should not be sold as
one.

What genuinely remains is smaller and duller: a LocalSystem process that starts
without anyone asking, loads 15 DLLs' worth of parsing code, and exists to
process telemetry-shaped inputs about the machine's own behaviour. It is
attack surface in the ordinary sense — more running code than the owner asked
for — not a specific exploitable hole.

### The one genuinely interesting privilege detail

`WdiServiceHost` is named in Microsoft's **Windows Filtering Platform**
documentation as a principal granted rights on WFP objects, in the same
sentence as the firewall and the IPsec policy agent:

> "access rights to the following service security identifiers (SSIDs): MpsSvc
> (Windows Firewall), NapAgent (Network Access Protection Agent), PolicyAgent
> (IPsec Policy Agent), RpcSs (Remote Procedure Call), and **WdiServiceHost
> (Diagnostic Service Host)**." [R-116]

That is the mechanism behind "the network troubleshooter found a firewall rule
blocking this". A diagnostic host holding firewall-platform rights is a
defensible design and a real widening of what that service can reach.

## Why the writes failed, and the supported route

The registry keys for all three grant Administrators `ReadKey` and no
`SetValue`; the module writes start types with `Set-ItemProperty`
([`_Common.ps1:474`](_Common.ps1)), so the write is refused and the apply exits
**5** with each name printed.

The SCM path is a different door, and it is open. All three service DACLs grant
`DC` — `SERVICE_CHANGE_CONFIG` — to `BA`:

```
DPS  D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRRC;;;BA)
                                                 ^^
```

So `sc.exe config <name> start= disabled` should succeed where the registry
write cannot.

> **Not yet proved by execution.** That conclusion is decoded from the SDDL. The
> proof is an elevated no-op — `sc.exe config DPS start= auto`, which writes the
> value DPS already has — and it has not been run. Until it is, this is
> analysis, not a result. See `DEC-06-010`.

## Microsoft's disposition, precisely

| Service | Server services guidance | VDI optimisation guidance |
|---|---|---|
| `DPS` | "No guidance" | **listed** as may-consider-disabling [R-110][R-111] |
| `WdiSystemHost` | "No guidance" | **listed** [R-110][R-112] |
| `WdiServiceHost` | "No guidance" | **absent from the table** |

`WdiServiceHost`'s absence is worth not over-reading. The VDI document explains
its own exclusion rule:

> "Many services that may seem like good candidates to disable are set to manual
> service start type... Services that are already set to start type manual
> aren't listed here." [R-115]

But `WdiSystemHost` is *also* Manual and *is* listed. So Microsoft's own table
does not apply its own rule consistently, and the absence of `WdiServiceHost`
carries no signal either way. Recording that rather than inventing a reason for
it.

Microsoft also attaches a caveat to the whole exercise, which applies here
directly:

> "make sure the service isn't a component of some other service" [R-114]

`WdiServiceHost` and `WdiSystemHost` **are** components of another service —
they are DPS's hosts. That is an argument for treating the three as one unit:
disable all three or none. Disabling DPS while leaving the hosts enabled leaves
two services that nothing will ever start; disabling the hosts while leaving
DPS enabled leaves a supervisor whose workers are gone.

## The supported alternative, which is not disabling anything

Microsoft's VDI guidance does not only disable the service — it also sets the
**scenario execution levels** to Disabled through policy, per diagnostic
family: Boot Performance, Shutdown Performance, Standby/Resume Performance,
System Responsiveness, Memory Leak, Resource Exhaustion, and PerfTrack [R-113].

That is a finer instrument than a start type. It turns off the *work* while
leaving the service able to start, and it is fully supported and fully
reversible. On a machine where the low-memory warning is worth keeping but boot
tracing is not, it is the better tool. It is also **not** what this module
does, and that gap is worth naming.

## Deprecation context — relevant, but do not overstate it

The legacy troubleshooter engine is being retired:

> "MSDT is the engine used to run legacy Windows built-in troubleshooters. There
> are currently 28 built-in troubleshooters for MSDT. Half of the built-in
> troubleshooters have already been redirected to the Get Help platform, while
> the other half will be retired." [R-117]

That document also states MSDT would be "fully retired in 2025", which is now
in the past.

**MSDT is not DPS.** MSDT (`msdt.exe`) is the troubleshooting-pack front end;
DPS/WDI is the scenario infrastructure underneath, and `diagperf.dll` and RADAR
are not MSDT troubleshooters. What the retirement establishes is narrower than
"DPS is obsolete": the *user-facing troubleshooter* half of what this subsystem
feeds is being dismantled by the vendor, so the value of keeping it is falling.
Both binaries are still present here at 10.0.26100.1.

## Adjacent finding — not part of this blast radius

While measuring the above, one item turned up that is **not** governed by these
three services and deserves its own decision:

```
\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner
    principal : SYSTEM, RunLevel = Highest
    action    : ComHandler {AD08DCC2-4E35-4486-9D49-547CBD30942D}
    triggers  : BootTrigger + 3x WnfStateChangeTrigger
    state     : Ready        last run: never
```

A SYSTEM task at highest integrity that fires **at boot and on Windows
Notification Facility state changes**, whose purpose is to look for
Microsoft-recommended troubleshooters. Both policy keys that would govern
recommended-troubleshooting behaviour
(`HKLM\SOFTWARE\Policies\Microsoft\Windows\Troubleshooting`,
`HKLM\SOFTWARE\Microsoft\WindowsMitigation`) are **absent**, so the default
applies.

It is driven by Task Scheduler, not by DPS, so **disabling these three services
will not stop it.** Flagged for its own record; not folded into this one.

## The recommendation

Close all three, as a unit, **once the SCM route is proved by execution**.
Grounds: Microsoft lists two of the three as disable-candidates and states the
cost in one sentence; nothing declares a dependency; no sign-in, boot, network
or update path is involved; and the subsystem's demonstrated output on this
machine over five months is thirteen notifications that nothing acted on.

Against, and recorded rather than argued away: the source guidance is written
for disposable VDI images, not a personal laptop; the low-memory warning is a
real loss; and the finer, fully supported instrument — scenario execution level
policy — was not evaluated for this machine and probably should be.

---

## References

| ID | Claim | rel_path | line |
|---|---|---|---|
| R-107 | What DPS is, and what stops when it stops | `windowsserverdocs/.../security-guidelines-for-disabling-system-services-in-windows-server.md` | 482 |
| R-108 | WdiServiceHost is DPS's LocalService-context host | same | 493 |
| R-109 | WdiSystemHost is DPS's LocalSystem-context host | same | 504 |
| R-110 | Microsoft lists services that may be considered for disabling in VDI | `windowsserverdocs/.../remote-desktop-services-vdi-optimize-configuration.md` | 461 |
| R-111 | The stated cost of disabling DPS | same | 473 |
| R-112 | The stated cost of disabling WdiSystemHost | same | 489 |
| R-113 | With DPS disabled Windows stops logging performance data | same | 343 |
| R-114 | Check the service is not a component of another service | same | 448 |
| R-115 | Microsoft's manual-start framing, and the table's own exclusion rule | same | 452 |
| R-116 | WdiServiceHost holds granted rights on Windows Filtering Platform objects | `win32/desktop-src/FWP/access-control.md` | 31 |
| R-117 | MSDT, the legacy troubleshooter engine, is being retired | `windows-itpro-docs/whats-new/deprecated-features-resources.md` | 155 |

Full quotations, APA 7th entries and machine-verification live in
[`../../decision-records/references.xml`](../../decision-records/references.xml)
and [`../../decision-records/REFERENCES.md`](../../decision-records/REFERENCES.md).
Every quote is checked **at the cited line**:

```bash
python ..\..\READ-ONLY-verification\Build-ReferenceLibrary.py
```

## Reproducing the measurements on this page

```bash
powershell -ExecutionPolicy Bypass -File ..\..\READ-ONLY-diagnostics\Report-BlastRadius.ps1 -Profile moderate
```

```bash
python ..\..\READ-ONLY-verification\Lookup-ServiceDocs.py --service DPS
```

The event counts, module registrations and ACLs were read with ordinary
built-ins — `wevtutil el`, `Get-WinEvent`, `Get-ChildItem` over
`HKLM\SYSTEM\CurrentControlSet\Control\WDI`, `Get-Acl`, `sc.exe qtriggerinfo`
and `sc.exe sdshow`. Nothing on this page required a write.
