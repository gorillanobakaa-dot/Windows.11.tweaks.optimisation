# Xbox services - close the dormant-but-wakeable surface

## Just want to click something?

| Double-click this | What happens | Admin? | Reversible? |
|---|---|---|---|
| **1 - Check what is on now** | Every Xbox service, task and app, read-only | No | reads only |
| **2 - Preview the changes (safe)** | Every change that would happen; does none of it | No | reads only |
| **3 - Apply the changes** | Disables 5 services + 1 scheduled task, backup first | **Yes** | **yes, from a backup** |
| **4 - UNDO everything** | Puts every start type back from the newest backup | **Yes** | - |
| **5 - UNDO back to the original** | Back to before this module ever ran | **Yes** | - |
| **6 - Prove the undo works** | Applies, undoes, compares every reading | **Yes** | net zero on a pass |
| **7 - Test the safety logic** | Tests the machinery that decides whether to write | No | reads only |

Full walkthrough with every option, and troubleshooting: [`HOWTO.md`](HOWTO.md).

---

## In plain language

On this machine the four Xbox services and the Game-DVR service are set to
**Manual and Stopped**. Task Manager calls that harmless. This repository's
threat model calls it what it is: five doors that are closed but not locked -
each one starts the moment anything asks for it, four of them as
**LocalSystem**, the highest privilege there is. See
[`../../THREAT-MODEL.md`](../../THREAT-MODEL.md).

If you do not play Xbox games on this machine, nothing you use asks for these
services. Disabling them (start type 4) locks the door, and this module records
every previous value in a verified backup so one click puts it all back.

**This is Microsoft's own advice, quoted exactly.** Their security guidance for
disabling system services says:

> "We recommend you disable the following services and their related scheduled tasks on Windows Server 2016 with Desktop Experience:" [R-98]

and lists Xbox Live Auth Manager and Xbox Live Game Save first, each carrying
the recommendation:

> "Should be disabled" [R-99] [R-100]

together with the scheduled task this module also disables [R-101]. Microsoft's
VDI optimization guidance additionally lists the accessory service [R-102], the
networking service [R-103] and the per-user Game-DVR service - for which it
notes "the template service must be disabled" [R-104], which is exactly what
this module does (per-user copies like `BcastDVRUserService_xxxxx` are created
from the template and inherit its setting).

**The honest caveat, in full view:** both source documents are Windows
*Server* documentation. They describe the same service names, delivered by the
same component set - Microsoft records each of these services' installation as
"Only with Desktop Experience" [R-105], and there is no equivalent per-service guidance for
client Windows in the corpus. The claim this module makes is precisely "these
are the vendor's own words about these exact services" - no more.

### What this module deliberately does NOT touch

- **The Xbox app packages** (Game Bar and friends). Removing apps is a
  different class of change - a later module handles it. `1 - Check` lists
  them so you can see what is there.
- **GamingServices / GamingServicesNet** - not present on this machine.
- Nothing is removed. A disabled service is one registry value away from
  exactly where it was.

---

## What has actually been proved

| | Result |
|---|---|
| Round trip, elevated, on this machine | **PASS** - 6 readings moved (5 services + the task) and every one came back; test backups cleaned up |
| Comparison proved falsifiable | doctored start type detected; null state trips the guard |
| Safety logic self-test | **39 checks, 0 failures** - its first run caught a real defect: `$null -as [int]` coerces to 0, and 0 is a BOOT-DRIVER start type, so the valid range was tightened to 2-4 |
| Citations | **7 / 7 verified** against the offline corpus |
| Adversarial audit | **done - 14 findings (2 serious), all fixed.** The serious pair: the round trip ran its undo on ANY unexpected apply exit code (a crashed apply would have sent it after a stale backup), and the apply exited 0 even when every write failed. Both fixed and tripwired; the self-test grew from 39 to 44 checks |
| Applied to this machine | **YES - 2026-08-26 22:10.** All 5 services Start=4, task disabled, every value read back. The per-user instance `BcastDVRUserService_7d78f` keeps Start=3 until the next sign-out - instances are stamped from the template, which is what Microsoft says to disable [R-104] |

This table is updated as each row becomes true.

---

## References

```bash
powershell -ExecutionPolicy Bypass -File ..\..\READ-ONLY-verification\Verify-Citations.ps1 -Document .\README.md -Detailed
```

| ID | Claim | rel_path | line | quote |
|---|---|---|---|---|
| R-98 | Microsoft recommends disabling these services and their tasks | windowsserverdocs/WindowsServerDocs/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server.md | 38 | We recommend you disable the following services and their related scheduled tasks on Windows Server 2016 with Desktop Experience: |
| R-99 | XblAuthManager: should be disabled | windowsserverdocs/WindowsServerDocs/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server.md | 2135 | Should be disabled |
| R-100 | XblGameSave: should be disabled | windowsserverdocs/WindowsServerDocs/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server.md | 2146 | Should be disabled |
| R-101 | The XblGameSave scheduled task is named alongside | windowsserverdocs/WindowsServerDocs/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server.md | 41 | \Microsoft\XblGameSave\XblGameSaveTask |
| R-102 | XboxGipSvc listed in Microsoft VDI disable guidance | windowsserverdocs/WindowsServerDocs/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration.md | 494 | Xbox Accessory Management Service|XboxGipSvc|This service manages connected Xbox Accessories. |
| R-103 | XboxNetApiSvc listed in the same guidance | windowsserverdocs/WindowsServerDocs/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration.md | 495 | Xbox Live Networking Service|XboxNetApiSvc|This service supports the Windows.Networking.XboxLive application programming interface. |
| R-104 | The per-user Game-DVR service: disable the TEMPLATE | windowsserverdocs/WindowsServerDocs/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration.md | 466 | This is a "per-user service", and as such, the template service must be disabled. |
| R-105 | These Xbox services ship with the Desktop Experience component set - the same set this client machine runs | windowsserverdocs/WindowsServerDocs/security/windows-services/security-guidelines-for-disabling-system-services-in-windows-server.md | 2133 | Only with Desktop Experience |
