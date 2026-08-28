# Services — three profiles, and the machinery that stops them bricking your machine

## Just want to click something?

| Double-click this | What happens | Admin? | Reversible? |
|---|---|---|---|
| **1 - Check what is on now** | Every service, and what each profile would do | No | reads only |
| **2 - Preview LIGHT** | Every service LIGHT disables, by category | No | reads only |
| **3 - Preview MODERATE** | Same, for MODERATE | No | reads only |
| **4 - Preview SUPER** | Same, for SUPER — **read this one before applying it** | No | reads only |
| **5 - APPLY profile LIGHT** | Disables ~64 services | **Yes** | **yes, from a backup** |
| **6 - APPLY profile MODERATE** | Disables ~116 | **Yes** | **yes** |
| **7 - APPLY profile SUPER** | Disables ~167 | **Yes** | **yes** |
| **8 - UNDO everything** | Every start type back from the newest backup | **Yes** | — |
| **9 - UNDO back to the original** | Back to before this module ever ran | **Yes** | — |
| **10 - Prove the undo works** | Applies LIGHT, undoes it, compares all 284 | **Yes** | net zero on a pass |
| **11 - Test the safety logic** | Tests the refusals, including that they can fire | No | reads only |

**Preview before you apply.** Every profile prints what *this machine actually
uses* that it would take away, before it asks.

Full walkthrough with every option, and troubleshooting: [`HOWTO.md`](HOWTO.md).

**Before you pick a profile**, read *What you actually lose* and
*SERVICES NOT TO SHUT* further down this page. Two features were switched
off on this machine without warning before those sections existed.

Deep dive on the four services this profile could not disable — what the
Windows Diagnostic Infrastructure actually is, what breaks if it is closed, and
what Microsoft's own documentation says about it:
[`BLAST-RADIUS-diagnostics.md`](BLAST-RADIUS-diagnostics.md).

---

## In plain language

### The thing everyone gets wrong about services

Open Task Manager, count the running services, feel reassured. On this machine
that number is about 101 — and it is close to meaningless.

The real number is **284 services installed**. Before this project ran, **174 sat at "Manual"**.
Manual does not mean off. It means *Windows starts it when something asks* — a
device arriving, a network packet, a policy refresh, a scheduled task. **112 of
them carry trigger definitions that do exactly that, and 170 run as
LocalSystem**, the highest privilege on Windows.

A stopped service is a door that is closed but not locked. This module locks
the ones you do not use.

### Three profiles, cumulative

| Profile | Disables | What you give up |
|---|---|---|
| **LIGHT** | **64** (23%) | Hardware this machine hasn't got, OEM bloat, third-party updater services, telemetry and appraisal, legacy network discovery |
| **MODERATE** | **116** (41%) | LIGHT **plus** remote access (RDP, WinRM, remote registry, SMB *server*), cloud sync, Microsoft-account plumbing, diagnostics, push notifications, geolocation |
| **SUPER** | **167** (59%) | MODERATE **plus** printing, Bluetooth, Windows Search indexing, the Store surface, and legacy protocols (NetBIOS, SNMP, RPC Locator, DTC). Audio, thermal and brightness are deliberately **not** touched |

Each is a superset of the one before. **"LIGHT" does not mean "no cost"** — an
earlier draft of this page claimed it disabled "nothing you use", and the audit
called that false. LIGHT also ends scanning, Mobile Hotspot, File History,
Windows Backup, WebDAV and smart-card support. MODERATE additionally ends
Bluetooth *pairing* and the built-in troubleshooters. SUPER is a genuinely
locked-down workstation: **no printing, no Bluetooth, slower search.**

### The three things that stop this wrecking your machine

Disabling services is easy. Disabling services *without breaking the machine at
the next boot* is the whole job, and it is why this module is mostly refusals.

**1. A NEVER-TOUCH list, enforced in code.** 95 services no profile may
contain, ever — the RPC substrate (`RpcSs` alone has **152** dependents), sign-in,
the firewall, Windows Update, and **UAC elevation itself**. If a profile ever
names one, the apply **refuses outright** rather than skipping the entry
quietly, because a profile that names `RpcSs` is a profile someone edited
without understanding it.

> `Appinfo` is on that list for a pointed reason: it *is* UAC elevation.
> Disable it and nothing can ever run as administrator again — **including this
> module's own undo.**

**2. A LOCKOUT-RISK list.** 9 services that can stop you *signing in*:
Windows Hello, the biometric service, Credential Manager, the local Kerberos
KDC, and the Microsoft-account assistant that is the *recovery* path for a
forgotten PIN. This machine has
Windows Hello running, which means a PIN is very likely in use. A backup file
on a disk you cannot log in to reach is not a rescue, so no profile contains
these at all.

**3. Dependency validation, computed from the live machine every time.**
Before a single value is written: *does anything that stays enabled depend on
something this profile disables?* If yes, the apply refuses and names both
services.

> This matters more than it sounds. A dependency break **does not fail when you
> make it.** It fails at the next boot — which is the worst possible moment to
> find out.

All three profiles currently pass that check on this machine with **zero**
violations.

### What the adversarial audit changed

The audit found **26 findings, 6 severe** — and the dangerous ones were in the
profile *content*, not the machinery:

| Finding | What it would have done |
|---|---|
| `LocalKdc` was in MODERATE | Its own description: *"If this service is stopped, users will be unable to log on to the local machine."* Now on the lockout-risk list |
| The never-touch list was **unvalidated data** | A JSON typo nulling that key removed the entire enforcement layer silently, and `RpcSs` would have been disabled. The file now refuses to load without plausible safety lists |
| The undo guarded `never` but not `lockoutRisk` | A stale backup could disable Windows Hello *through the undo* — the script you run when already in trouble |
| `StorSvc`, `DsSvc`, `NcbService`, `TimeBrokerSvc` | All declare **zero dependents**, so the dependency graph called them safe. All are activated at runtime by COM or WinRT; Windows Update staging uses `StorSvc` |
| `RmSvc` was in **LIGHT** | The airplane-mode toggle, on a laptop whose only network path is Wi-Fi |
| SUPER disabled five audio services | While this page promised audio survives every profile |
| The dependency check could not see **drivers** | `applockerfltr` (a driver) declares a dependency on `AppIDSvc` (a service that was in SUPER). Drivers are now scanned |

Twenty-five never-touch entries and two lockout entries were added as a result,
and the profiles got **smaller** — 197 to 167 at SUPER. That is the correct
direction when the alternative is a machine that will not boot.

### Blast radius is not the dependency graph

That is the lesson underneath most of those findings. `DependOnService` records
*declared* dependencies. It does not record COM activation, RPC activation,
WinRT brokering, or "the servicing stack calls this to check free disk space".
Four services with zero declared dependents nearly shipped in a profile.

Two read-only tools exist because of it:

```bash
powershell -ExecutionPolicy Bypass -File ..\..\READ-ONLY-diagnostics\Report-BlastRadius.ps1 -Profile super
python ..\..\READ-ONLY-verification\Lookup-ServiceDocs.py --profile super
```

The first reads each service's **own description** — where Microsoft writes the
consequence directly, and where the sentence that should have kept `LocalKdc`
out of a profile was sitting all along — and scores it for words like *log on*,
*boot*, *update* and *network*. Current result: **zero severe findings** in any
profile.

The second searches the **6 GB offline documentation corpus** for every service
a profile would disable, narrowing with the corpus's own full-text index and
then requiring an exact, word-boundary match before it will attribute a
sentence to a service. Current result: **96 of 175 are mentioned in the corpus,
79 are not mentioned at all.** Those 79 rest on category reasoning and machine
observation — which is allowed here, and labelled, but it is the first place to
look when something breaks.

### Why disable, and not `sc delete`

A fair challenge: as long as the service infrastructure is still on the
machine, it can be reactivated. That is **true** — and `sc delete` does not fix
it. Measured on this machine, on a service already disabled:

| | |
|---|---|
| `XblGameSave` start type | 4 (disabled) |
| Its code | `C:\WINDOWS\System32\XblGameSave.dll`, **847,872 bytes, still there** |
| Its trigger registration | **still present** |
| Binary owner | `NT SERVICE\TrustedInstaller` |

`sc delete` removes the **registration**, not the **code**. The DLL stays
exactly where it is, and anything with administrator rights re-creates the
service with one `sc create`. So the reactivation risk barely moves, while
three real costs arrive:

1. **It does not stick.** Those files are owned by TrustedInstaller. Windows
   Update, SFC and DISM restore both files *and* service registrations — so a
   deletion is undone silently by the next servicing operation, leaving a
   machine whose real configuration no longer matches its documentation.
2. **It can break patching.** Deleting system binaries is a known cause of
   failed cumulative updates, because an update patches files it expects to
   exist. This project's never-touch list protects Windows Update precisely
   because updates are the primary defence; trading a dormant DLL for broken
   patching is a bad trade.
3. **It is not honestly reversible with what is backed up.** The state file
   holds name, start type, service type, dependencies and display name —
   enough to restore a start type, and *not* enough to re-create a deleted
   service. That needs `ImagePath`, `ObjectName`, `ServiceDll`, the trigger
   definitions, the failure actions and the security descriptor.

The honest counter-argument is recorded too: `sc delete` **does** remove the
trigger registration, which is the actual automatic activation path. If it is
ever added, it needs a full service export written and verified *before* the
first deletion. See `DEC-06-008` in
[`../../decision-records/`](../../decision-records/).

### Alt-Tab

Hardening can break the task switcher, and almost nobody would connect a
broken Alt-Tab to a tweak made days earlier. So there is a test rather than a
promise — launcher **12**, or `[C]` on the control panel:

- It presses Alt+Tab for real, looks for the switcher window, and cancels with
  Escape before releasing Alt so the switch is abandoned.
- It lists every switcher-relevant setting, marking which this project set.
- It cross-checks **all three profiles** against the 16 services the shell and
  the switcher depend on.

Current result on this machine: switcher appears (`XamlExplorerHostIslandWindow`),
composition on, **16 of 16 shell-critical services on the never-touch list, and
no profile touches any of them.**

### What it will not do

- **Touch a driver.** Only Win32 service types are enumerated, so a kernel
  driver cannot be reached by any profile even if someone typed one in.
- **Delete anything.** Services are set to *disabled*. Nothing is removed.
- **Disable audio.** `Audiosrv` is deliberately kept in every profile, up to
  and including SUPER: silence is a large cost for no security gain.
- **Disable Windows Update, the firewall or Defender.** They are on the
  never-touch list. Updates are the primary defence.

---

## What has actually been proved

| | Result |
|---|---|
| Round trip, elevated, on this machine | **PASS** — LIGHT applied for real, **64 start types moved and all 64 came back**, all 283 services compared |
| Safety self-test | **83 checks, 0 failures** |
| Refusals proved able to FIRE | a forbidden service (`RpcSs`), a lockout-risk service (`NgcSvc`), and a plan that strands a dependency are each **detected**, not merely handled |
| Dependency safety, all three profiles | **0** violations on this machine |
| Profiles vs never-touch list | **disjoint** — verified, not assumed |
| Adversarial audit | **done — 26 findings, 6 severe.** Six were in the PROFILE CONTENT, not the machinery |
| Corpus cross-check | every profile service looked up in the 6 GB offline documentation |
| Applied to this machine | **not yet** — the owner's call |

The self-test caught a real defect before any of this shipped: the round-trip
comparison iterated `.PSObject.Properties` on a **live** state, which is a
hashtable — so it enumerated `Count`, `Keys` and `Values` instead of services,
compared nothing, and reported PASS. That is this project's most-repeated
defect class wearing a new disguise, and there is now a regression guard
naming it.

A second defect was fixed on the way: the first version asked WMI about each
service individually — 283 separate queries — and the self-test took minutes.
Correct but unusably slow is still a defect: **a safety check nobody waits for
is a safety check nobody runs.** One cached query, four seconds.

---

## Technical detail

### Profiles are data

`profiles.json` holds all three, so they can be reviewed and diffed without
reading any PowerShell:

```json
{
  "never":       [ { "service": "RpcSs", "reason": "152 services depend on it…" } ],
  "lockoutRisk": [ { "service": "NgcSvc", "reason": "Windows Hello / PIN…" } ],
  "profiles": {
    "light": { "services": [
      { "service": "QServiceEM05G", "category": "unused hardware",
        "reason": "Quectel WWAN modem helper. This machine's cellular adapters all report Not Present…",
        "microsoft_disposition": null, "tier": "light" } ] }
  }
}
```

`microsoft_disposition` carries Microsoft's own word for that exact service
name where one exists, harvested by
`READ-ONLY-verification/Harvest-ServiceGuidance.py` from the vendor's service
guidance — 198 services, of which Microsoft explicitly permits disabling 39.
The rest are justified by category and by what this machine demonstrably does
not use, and are labelled as such rather than dressed in a citation that does
not exist.

### Reality warnings

A profile is a policy; the machine is a fact. Before writing, the apply checks
the two against each other and prints the disagreements — Bluetooth devices
actually paired, printers actually installed, whether RDP is actually enabled,
whether the machine is actually domain-joined. Warnings, not refusals: the
owner may genuinely want the trade.

### Backups cover everything

The backup records **every** Win32 service's start type, not only the ones the
profile changes. A backup covering only the planned changes cannot restore a
machine where something else moved in between.

### Exit codes (MODULE-STANDARD §16)

| Code | Meaning |
|---|---|
| 0 | applied |
| 3 | backup refused; nothing changed |
| 4 | nothing to do (or unelevated); no backup written |
| 5 | completed, but one or more writes failed |
| 6 | **the profile is illegal or unsafe** — never-touch, lockout-risk, or a stranded dependency |

The round trip gates on all five *and* on any unexpected code, because a
crashed apply that fell through to the undo would restore a stale backup and
mutate the machine mid-proof.

### A restart is the honest test

Services already running keep running until then. The change is what happens at
the next boot — which is exactly why the dependency check runs before the
write, not after.

---

---

## What you actually lose — read this before you pick a profile

Two things on this machine were switched off by a profile and **nobody was told
until they broke**. Both are written up here because the same thing will happen
to somebody else otherwise.

### The camera — and why the privacy slider lies to you

`FrameServer` is called *"Windows Camera Frame Server"*. Microsoft's own
description is *"Enables multiple clients to access video frames from camera
devices"*, and the entry in this module used to paraphrase that as *"lets
multiple apps share the camera"*.

Both are true. Both are badly misleading. **Without it, no application gets the
camera at all** — not Teams, not Zoom, not a video call in a browser, not the
Camera app.

And here is the part that wastes an afternoon:

> **The privacy slider will still say "Allow".** Settings → Privacy → Camera
> keeps reporting that the camera is permitted, because that switch grants
> *permission*. It cannot start a service that has been disabled. Nothing in the
> interface tells you the difference.

On this machine that meant two working cameras — one of them the **infrared
camera Windows Hello face sign-in uses** — sitting there dead while the
permission screen said everything was fine.

**Fixed:** `FrameServer` and `FrameServerMonitor` were moved out of MODERATE and
into SUPER, and the checker now warns you, with the count of cameras it can see,
before you apply anything. See `DEC-06-014`.

### Screen capture — Win+Shift+S

`CaptureService` describes itself as *"capture service for screen capture in
Store apps"*. The Snipping Tool **is** a Store app doing screen capture. With
this service off, **Win+Shift+S does nothing at all** — no overlay, no error, no
message. It simply does not happen.

It sat in the SUPER profile under the category "misc".

**Fixed:** it is now on the never-touch list, so no profile can reach it, and a
profile that names it is refused outright. See `DEC-06-013`.

### The Fn keys (Lenovo laptops) - hardware vs software

If you apply a profile on a Lenovo laptop, your `Fn + Esc` key combo (the Fn Lock) will stop working in Windows.

Why? Because Lenovo uses a privileged background service (`TPHKLOAD`) to listen for that key combination. Our profiles disable that service to reduce the background noise and attack surface on your machine.

**The Fix:** You do not need the software to get your function keys back. You can set this directly in the laptop's hardware:
1. Reboot and press `F1` or `Enter` to enter the BIOS/UEFI.
2. Go to **Config** -> **Keyboard/Mouse**.
3. Enable **F1-F12 as Primary Function**.

By doing this, your keyboard firmware sends standard `F1-F12` keystrokes directly to the operating system. You get your F-keys back perfectly across Windows, Debian, or any other OS, and you keep Lenovo's bloatware service permanently disabled.

**Technical Proof:**
* The service is `TPHKLOAD` (Lenovo hotkey loader).
* Disabling it breaks software-based Fn key intercepts.
* Hardware interception via BIOS/UEFI predates the OS bootloader, sending raw scancodes (e.g., 0x3B for F1) directly to the OS input stack, completely bypassing the need for an OEM driver or Windows service.

### The honest part

Neither of these was found by anything in this project. Not by the blast-radius
report, not by the live dependency check, not by the 83 safety checks — **all of
them passed**. No service depends on either one. Microsoft publishes no
"do not disable" guidance for either.

They were found by a person using the machine and noticing.

That is a real limit, and it is worth stating rather than implying: this module
can prove that **nothing stops starting**, and it cannot prove that **nothing
you use stops working**. The warning list below is a list of things somebody
thought of. Something is missing from it right now.

---

## SERVICES NOT TO SHUT

*102 services this module refuses to touch — 95 never-touch and 7 that can lock
you out — with what Microsoft says each one does and where that is written.*

### How to read this

Every profile in this module is **forbidden** from containing anything below. If
one ever appears in a profile, the apply refuses the whole profile and exits 6.
It does not skip the entry and carry on, because a profile naming one of these
is a profile somebody edited without understanding it.

Three kinds of source appear in the "where" column, and the difference matters:

| What it says | What that means |
|---|---|
| a **file and line number** | Microsoft's own words, in the documentation on this machine. Open the file at that line and check it |
| *this machine's own service description* | what Windows itself reports for that service. Real, but not the vendor's published guidance |
| **no Microsoft description anywhere** | our reasoning only, labelled `[uncited]`. Seven entries. Judge them accordingly |

The source file for almost all of the citations is Microsoft's *Security
guidelines for system services in Windows Server*, which is Windows **Server**
documentation describing the same service names shipped with the same Desktop
Experience component set that client Windows runs. That caveat applies to this
whole table and is stated once here rather than repeated 76 times.

### Sign-in — these can lock you out of your own machine

If one of these is off, the machine may boot to a login screen that will not accept you. A backup on a disk you cannot log in to reach is not a rescue. These seven are excluded from every profile and the undo refuses to touch them even if a backup file says to.

| Service | What Microsoft says it does | Where that is written |
|---|---|---|
| `LocalKdc` | **[uncited]** Kerberos Local Key Distribution Center. Microsoft's own description: 'This service enables users to log on to the local machine using the Kerberos authentication protocol | **no Microsoft description anywhere** - our reasoning only |
| `NgcSvc` | Provides process isolation for cryptographic keys the system uses to authenticate to a user's associated identity providers. If you disable this service, all uses and management of these keys become available, which includes the ability to sign in to the machine and single-sign on for apps and websites. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:911 |
| `NgcCtnrSvc` | Manages local user identity keys used to authenticate user to identity providers and TPM virtual smart cards. If you disable this service, the system can't access local user identity keys and TPM virtual smart cards. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:922 |
| `WbioSrvc` | The Windows biometric service gives client applications the ability to capture, compare, manipulate, and store biometric data without gaining direct access to any biometric hardware or samples. The service is hosted in a privileged SVCHOST process. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1813 |
| `wlidsvc` | Enables user sign-in through Microsoft account identity services. If you stop this service, users can't sign in to the computer with their Microsoft account. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:878 |
| `NaturalAuthentication` | **[uncited]** companion-device and phone-based sign-in. | **no Microsoft description anywhere** - our reasoning only |
| `SamSs` | The startup of this service signals other services that the Security Accounts Manager (SAM) is ready to accept requests. Disabling this service prevents the system from notifying other services when the SAM is ready, which can prevent those services from starting correctly. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1351 |
| `FrameServer` | Enables multiple clients to access video frames from camera devices. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1824 |
| `FrameServerMonitor` | **[uncited]** Health watchdog for FrameServer. Moves with it - disabling one without the other achieves nothing, and FrameServer is a sign-in path. | **no Microsoft description anywhere** - our reasoning only |

### The machine stops working at all

Not 'a feature breaks' — the desktop does not come up, or nothing can start.

| Service | What Microsoft says it does | Where that is written |
|---|---|---|
| `RpcSs` | The RPCSS service is the Service Control Manager for COM and DCOM servers. It performs object activations requests, object exporter resolutions and distributed garbage collection for COM and DCOM servers. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1263 |
| `RpcEptMapper` | Resolves Remote Procedure Call (RPC) interfaces identifiers to transport endpoints. If you stop or disable this service, programs using RPC services stop functioning properly. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1318 |
| `DcomLaunch` | The DCOMLAUNCH service launches Component Object Model (COM) and Distributed Component Object Model (DCOM) servers in response to object activation requests. If you stop or disable this service, programs using COM or DCOM are unable to function properly. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:405 |
| `PlugPlay` | Enables a computer to recognize and adapt to hardware changes with little or no user input. Stopping or disabling this service will result in system instability. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:427 |
| `Power` | Manages power policy and power policy notification delivery. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1131 |
| `ProfSvc` | This service is responsible for loading and unloading user profiles. If you stop or disable this service, users become unable to successfully sign in or sign out, apps might have problems getting to users' data, and components registered to receive profile event notifications don't receive them. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1747 |
| `LSM` | Core Windows Service that manages local user sessions. Stopping or disabling this service causes system instability. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:856 |
| `BrokerInfrastructure` | Windows infrastructure service that controls which background tasks can run on the system. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:207 |
| `CoreMessagingRegistrar` | Manages communication between system components. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:350 |
| `Appinfo` | Facilitates the running of interactive applications with additional administrative privileges. If you stop this service, users can't launch applications with the additional administrative privileges they may require to perform desired user tasks. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:141 |
| `gpsvc` | The service is responsible for applying settings that administrators configured for the computer and users through the Group Policy component. If you disable the service, the settings aren't applied and applications and Group Policy can't manage the components. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:647 |
| `Schedule` | Lets users configure and schedule automated tasks on this computer. The service also hosts multiple Windows system-critical tasks. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1593 |
| `EventLog` | This service manages events and event logs. It supports logging events, querying events, subscribing to events, archiving event logs, and managing event metadata. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1912 |
| `EventSystem` | Supports System Event Notification Service (SENS), which provides automatic distribution of events to subscribing Component Object Model (COM) components. If the service is stopped, SENS closes and is unable to provide logon and logoff notifications. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:284 |
| `SENS` | Monitors system events and notifies subscribers to COM+ Event System of these events. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1571 |
| `Winmgmt` | Provides a common interface and object model to access management information about operating system, devices, applications and services. If you stop this service, most Windows-based software will not function properly. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1989 |
| `StateRepository` | Provides required infrastructure support for the application model. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1505 |

### Security — turning these off is the opposite of hardening

This is a hardening project. Disabling the firewall to make the machine 'leaner' would be self-defeating, so these are unreachable by design.

| Service | What Microsoft says it does | Where that is written |
|---|---|---|
| `mpssvc` | Windows Firewall protects your computer by preventing unauthorized users from gaining access to your computer through the Internet or a network. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1923 |
| `BFE` | The Base Filtering Engine (BFE) is a service that manages firewall and Internet Protocol security (IPsec) policies and implements user mode filtering. Stopping or disabling the BFE service significantly reduces system security and causes unpredictable behavior in IPsec management and firewall applications. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:218 |
| `MDCoreSvc` | **[uncited]** Defender core service | **no Microsoft description anywhere** - our reasoning only |
| `WinDefend` | Helps protect users from malware and other potentially unwanted software. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1857 |
| `SecurityHealthService` | **[uncited]** Windows Security surface and health reporting | **no Microsoft description anywhere** - our reasoning only |
| `wscsvc` | **[uncited]** Security Center; reports protection state to the OS and to you | **no Microsoft description anywhere** - our reasoning only |
| `webthreatdefsvc` | **[uncited]** web threat defence; part of the protection stack | **no Microsoft description anywhere** - our reasoning only |
| `CryptSvc` | Provides three management services: Catalog Database Service, which confirms the signatures of Windows files and allows new programs to be installed; Protected Root Service, which adds and removes Trusted Root Certification Authority certificates from this computer; and Automatic Root Certificate Update Service, which retrieves root certificates from Windows Update and enable scenarios such as SSL. If you stop this service, these management services are unable to function properly and any services that explicitly depend on it are unable to start. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:372 |
| `EFS` | Provides the core file encryption technology used to store encrypted files on NTFS file system volumes. If you stop or disable this service, applications can't access encrypted files. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:581 |
| `BDESVC` | **[uncited]** BitLocker service. On a 25H2 Home machine Device Encryption is often on by default; disabling this removes the ability to suspend protection or read the recovery key, and | **no Microsoft description anywhere** - our reasoning only |
| `KeyIso` | **[uncited]** CNG key isolation; protects private keys, 2 dependents | **no Microsoft description anywhere** - our reasoning only |
| `AppIDSvc` | Determines and verifies the identity of an application. Disabling this service prevents AppLocker from being enforced. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:130 |
| `TokenBroker` | **[uncited]** web account tokens; sign-in and Store authentication | **no Microsoft description anywhere** - our reasoning only |

### Network — no address, no name resolution, no connection

Each of these removes a different part of being on a network at all.

| Service | What Microsoft says it does | Where that is written |
|---|---|---|
| `Dhcp` | Registers and updates IP addresses and DNS records for this computer. If you stop this service, this computer doesn't receive dynamic IP addresses and DNS updates. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:471 |
| `Dnscache` | The DNS Client service (dnscache) caches Domain Name System (DNS) names and registers the full computer name for this computer. If you stop this service, the dnscache continues to resolve DNS names. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:548 |
| `NlaSvc` | Collects and stores configuration information for the network and notifies programs when this information is modified. If you stop this service, configuration information might be unavailable. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1021 |
| `nsi` | This service delivers network notifications, such as interface addition and deletions, to user mode clients. Stopping this service causes the system to lose network connectivity. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1043 |
| `Netman` | Manages objects in the Network and Dial-Up Connections folder, in which you can view both local area network and remote connections. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:988 |
| `netprofm` | Identifies the networks the computer has connected to, collects and stores properties for these networks, and notifies applications when these properties change. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1010 |
| `NetSetupSvc` | The Network Setup Service manages the installation of network drivers and permits the configuration of low-level network settings. If you stop this service, the system may cancel any in-progress driver installations. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1032 |
| `LanmanWorkstation` | Creates and maintains client network connections to remote servers using the SMB protocol. If you stop this service, these connections will be unavailable. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:2121 |
| `iphlpsvc` | Provides tunnel connectivity using IPv6 transition technologies (6to4, ISATAP, Port Proxy, and Teredo) and IP-HTTPS. If you stop this service, the computer loses the enhanced connectivity benefits that these technologies offer. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:801 |
| `WlanSvc` | **[uncited]** WLAN AutoConfig - this is a laptop; disabling it removes Wi-Fi | **no Microsoft description anywhere** - our reasoning only |
| `EapHost` | The Extensible Authentication Protocol (EAP) service provides network authentication in such scenarios as 802.1x wired and wireless, VPN, and Network Access Protection (NAP). EAP also provides the application programming interfaces (APIs) that network access clients use during the authentication process, including wireless and Virtual Private Network (VPN) clients. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:603 |
| `NcbService` | Brokers connections that allow Microsoft Store Apps to receive notifications from the internet. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:977 |

### Updates and installation

Disabling these means the machine stops receiving security patches — the thing you were hardening it against needing.

| Service | What Microsoft says it does | Where that is written |
|---|---|---|
| `wuauserv` | Enables the detection, download, and installation of updates for Windows and other programs. If you disable this service, users of this computer will not be able to use Windows Update or its automatic updating feature, and programs will not be able to use the Windows Update Agent (WUA) API. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:2077 |
| `BITS` | Transfers files in the background using idle network bandwidth. If the service is disabled, then any applications that depend on BITS, such as Windows Update or MSN Explorer, are unable to automatically download programs and other information. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:196 |
| `DoSvc` | **[uncited]** Delivery Optimization is the update DOWNLOAD engine (module 02 closed its peering by mode, deliberately not by disabling this) | **no Microsoft description anywhere** - our reasoning only |
| `msiserver` | Adds, modifies, and removes applications provided as a Windows Installer (*.msi, *.msp) package. If you disable this service, any services that explicitly depend on it become unable to start. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1967 |
| `TrustedInstaller` | Enables installation, modification, and removal of Windows updates and optional components. If you disable this service, install or uninstall of Windows updates might fail for this computer. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:2011 |
| `InstallService` | Provides infrastructure support for the Microsoft Store. | `remote-desktop-services-vdi-optimize-configuration.md`:477 |
| `AppXSvc` | Provides infrastructure support for deploying Store applications. This service starts on demand and, if disabled, Store applications don't deploy to the system and may not function properly. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:174 |
| `ClipSVC` | Provides infrastructure support for the Microsoft Store. This service starts on demand, and, if disabled, applications bought using Microsoft Store don't behave correctly. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:262 |
| `LicenseManager` | Provides infrastructure support for the Microsoft Store. This service is started on demand and if disabled then content acquired through the Microsoft Store will not function properly. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:262 |
| `AppReadiness` | Gets apps ready for use the first time a user signs in to this PC and when adding new apps. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:119 |

### The desktop, the Start menu and your apps

The machine boots, but the shell is broken or Store apps refuse to run.

| Service | What Microsoft says it does | Where that is written |
|---|---|---|
| `FontCache` | Optimizes performance of applications by caching commonly used font data. Applications automatically start this service if it's not already running. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1934 |
| `Themes` | Provides user experience theme management. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1626 |
| `embeddedmode` | The Embedded Mode service enables scenarios related to Background Applications. Disabling this service prevents Background Applications from activating. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:570 |
| `DevQueryBroker` | Enables apps to discover devices with a background task. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:460 |
| `DeviceInstall` | Enables a computer to recognize and adapt to hardware changes with little or no user input. Stopping or disabling this service results in system instability. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:427 |
| `DeviceAssociationService` | Enables pairing between the system and wired or wireless devices. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:416 |
| `DsmSvc` | Enables the detection, download, and installation of device-related software. If you disable this service, devices may be configured with outdated software and not work correctly. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:449 |
| `DsSvc` | Provides data brokering between applications. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:383 |
| `StorSvc` | Provides enabling services for storage settings and external storage expansion. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1527 |
| `UserManager` | User Manager provides the runtime components required for multi-user interaction. If you stop this service, some applications may not operate correctly. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1736 |
| `TextInputManagementService` | **[uncited]** text input - typing itself | **no Microsoft description anywhere** - our reasoning only |
| `hidserv` | Activates and maintains the use of hot buttons on keyboards, remote controls, and other multimedia devices. We recommend you keep this service running. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:658 |
| `WPDBusEnum` | Enforces group policy for removable mass-storage devices. Enables applications such as Windows Media Player and Image Import Wizard to transfer and synchronize content using removable mass-storage devices. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1120 |
| `CaptureService` | Enables optional screen capture functionality for applications that call the Windows.Graphics.Capture API. | `remote-desktop-services-vdi-optimize-configuration.md`:467 |
| `cbdhsvc` | **[uncited]** clipboard; copy and paste | **no Microsoft description anywhere** - our reasoning only |
| `ConsentUxUserSvc` | **[uncited]** Capability consent prompts - a hardening module that disables the consent UI is pointing the wrong way | **no Microsoft description anywhere** - our reasoning only |
| `CredentialEnrollmentManagerUserSvc` | **[uncited]** credential enrollment; a Type-80 service the enumerator did not even cover until this audit | **no Microsoft description anywhere** - our reasoning only |

### Hardware on THIS machine

These are specific to this laptop. On different hardware the names differ, but the principle does not: the service that runs your sound, your fans or your screen is not bloat.

| Service | What Microsoft says it does | Where that is written |
|---|---|---|
| `Audiosrv` | Manages audio for Windows-based programs. If you stop this service, audio devices and effects stop functioning properly. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1791 |
| `AudioEndpointBuilder` | Manages audio devices for the Windows Audio service. If you stop this service, audio devices and effects stop functioning properly. | `security-guidelines-for-disabling-system-services-in-windows-server.md`:1802 |
| `ApxSvc` | **[uncited]** Windows Virtual Audio Device Proxy - part of the audio path, and 'any services that explicitly depend on it will fail to start' | **no Microsoft description anywhere** - our reasoning only |
| `IntelAudioService` | **[uncited]** Intel SST audio service - Bluetooth and USB audio path | **no Microsoft description anywhere** - our reasoning only |
| `RtkAudioUniversalService` | **[uncited]** Realtek audio service - this machine's speaker endpoint. Auto-start, depends on Audiosrv | **no Microsoft description anywhere** - our reasoning only |
| `IBMPMSVC` | **[uncited]** Lenovo power management - thermal and battery behaviour | **no Microsoft description anywhere** - our reasoning only |
| `LITSSVC` | **[uncited]** Lenovo Intelligent Thermal Solution - fan and thermal policy | **no Microsoft description anywhere** - our reasoning only |
| `TPHKLOAD` | **[uncited]** Lenovo hotkey loader - the Fn keys, including brightness | **no Microsoft description anywhere** - our reasoning only |
| `DispBrokerDesktopSvc` | **[uncited]** display policy; disabling risks a black screen | **no Microsoft description anywhere** - our reasoning only |
| `DisplayEnhancementService` | **[uncited]** brightness control | **no Microsoft description anywhere** - our reasoning only |
| `camsvc` | **[uncited]** capability access manager; app permission enforcement | **no Microsoft description anywhere** - our reasoning only |
| `ipfsvc` | **[uncited]** Intel Innovation Platform Framework - power and thermal policy | **no Microsoft description anywhere** - our reasoning only |
| `IsoEnvBroker` | **[uncited]** Isolation Environment Broker - performs privileged operations for the 25H2 Administrator-protection elevation model. Latent today (that mode is off) and on the elevation  | **no Microsoft description anywhere** - our reasoning only |

### Also protected, not grouped above

| Service | Why it is protected |
|---|---|
| `sppsvc` | Enables the download, installation and enforcement of digital licenses for Windows and Windows applications. If you disable the service, the operating system and licensed applications may ru |
| `swprv` | Manages software-based volume shadow copies taken by the Volume Shadow Copy service. If you stop this service, the system becomes unable to manage software-based volume shadow copies. |
| `SystemEventsBroker` | Coordinates execution of background work for WinRT applications. If you stop or disable this service, then background work might not be triggered. |
| `TimeBrokerSvc` | Coordinates execution of background work for WinRT applications. If you stop or disable this service, then background work might not be triggered. |
| `UsoSvc` | Manages Windows Updates. If stopped, your devices will not be able to download and install latest updates. |
| `vaultsvc` | Provides secure storage and retrieval of credentials to users, applications, and security service packages. |
| `VSS` | Manages and implements Volume Shadow Copies used for backup and other purposes. If you stop this service, shadow copies become unavailable for backup, causing the backup to fail. |
| `W32Time` | Maintains date and time synchronization on all clients and servers in the network. If you stop this service, date and time synchronization will be unavailable. |
| `Wcmsvc` | Makes automatic connect or disconnect decisions based on the network connectivity options currently available to the PC and enables management of network connectivity based on Group Policy s |
| `WdNisSvc` | Helps guard against intrusion attempts targeting known and newly discovered vulnerabilities in network protocols. |
| `WinHttpAutoProxySvc` | WinHTTP implements the client HTTP stack and provides developers with a Win32 API and COM Automation component for sending HTTP requests and receiving responses. In addition, WinHTTP provide |
| `WpnService` | This service runs in session 0 and hosts the notification platform and connection provider which handles the connection between the device and WNS server. |
| `WpnUserService` | This service hosts Windows notification platform which provides support for local and push notifications. Supported notifications are tile, toast and raw. |

---

## References

Every quotation carries a tag, the file, the line it starts on, and the
sentence. Check them yourself:

```bash
python ..\..\READ-ONLY-verification\Build-ReferenceLibrary.py
```

| ID | Claim | rel_path | line | quote |
|---|---|---|---|---|
| R-106 | Microsoft's own recommendation vocabulary includes an explicit permission to disable, here for the Bluetooth Support Service | windowsserverdocs/WindowsServerDocs/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server.md | 232 | OK to disable |
| R-107 | What the Diagnostic Policy Service is, and what stops when it stops | windowsserverdocs/WindowsServerDocs/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server.md | 482 | The Diagnostic Policy Service enables problem detection, troubleshooting, and resolution for Windows components. If you stop this service, diagnostics stops functioning. |
| R-108 | WdiServiceHost is the LocalService-context host that DPS loads diagnostic modules into | windowsserverdocs/WindowsServerDocs/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server.md | 493 | The Diagnostic Service Host is used by the Diagnostic Policy Service to host diagnostics that need to run in a Local Service context. |
| R-109 | WdiSystemHost is the same host at LocalSystem privilege | windowsserverdocs/WindowsServerDocs/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server.md | 504 | The Diagnostic Policy Service uses the Diagnostic System host to host diagnostics that need to run in a Local System context. |
| R-110 | Microsoft lists services that may be considered for disabling in virtual desktop environments - DPS and WdiSystemHost are in that table | windowsserverdocs/WindowsServerDocs/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration.md | 461 | The following table contains some services that may be considered to disable in virtual desktop environments: |
| R-111 | Microsoft states the cost of disabling DPS in one sentence | windowsserverdocs/WindowsServerDocs/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration.md | 473 | Disabling this service disables the ability to run Windows diagnostics. |
| R-112 | Microsoft states the same cost for the LocalSystem diagnostic host | windowsserverdocs/WindowsServerDocs/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration.md | 489 | Disabling this service disables the ability to run Windows diagnostics |
| R-113 | With DPS disabled, Windows stops logging boot and shutdown performance data entirely | windowsserverdocs/WindowsServerDocs/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration.md | 343 | With the DPS service disabled, this setting has no effect, as Windows doesn't log performance data. |
| R-114 | Microsoft's own caveat before disabling any service: check it is not a component of another service | windowsserverdocs/WindowsServerDocs/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration.md | 448 | make sure the service isn't a component of some other service |
| R-115 | Microsoft's manual-start framing, and the VDI table's own stated exclusion rule | windowsserverdocs/WindowsServerDocs/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration.md | 452 | Many services that may seem like good candidates to disable are set to manual service start type. This means that the service doesn't automatically start and start only if an event triggers a request to the service. |
| R-116 | WdiServiceHost holds granted rights on Windows Filtering Platform objects, alongside the firewall and IPsec policy agent | win32/desktop-src/FWP/access-control.md | 31 | access rights to the following service security identifiers (SSIDs): MpsSvc (Windows Firewall), NapAgent (Network Access Protection Agent), PolicyAgent (IPsec Policy Agent), RpcSs (Remote Procedure Call), and WdiServiceHost (Diagnostic Service Host). |
| R-117 | MSDT, the engine behind the legacy Windows built-in troubleshooters, is being retired | windows-itpro-docs/whats-new/deprecated-features-resources.md | 155 | MSDT is the engine used to run legacy Windows built-in troubleshooters. There are currently 28 built-in troubleshooters for MSDT. Half of the built-in troubleshooters have already been redirected to the Get Help platform, while the other half will be retired. |
| R-118 | DirectAccess - the only thing NcaSvc reports on - is deprecated and scheduled for removal | windows-itpro-docs/whats-new/deprecated-features.md | 98 | DirectAccess is deprecated and will be removed in a future release of Windows. |
| R-119 | What NcaSvc is for, in Microsoft's own words | windowsserverdocs/WindowsServerDocs/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server.md | 999 | Provides DirectAccess status notification for UI components |
