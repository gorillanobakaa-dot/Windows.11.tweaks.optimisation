# How to use the Xbox services module

*Five services and one scheduled task, all Xbox, all named by Microsoft's own
guidance as services to disable. Fully reversible, and the undo has been
executed and compared rather than promised.*

---

## Before you start

### These services are "stopped", and that is not the same as off

All five sit at **Manual** start type. Task Manager calls that harmless. It is
not: Windows starts a Manual service the moment something asks for it, and
**four of these five run as LocalSystem** — the highest privilege on Windows.
Two of them carry live trigger definitions, which is Windows' own mechanism for
starting a service without a person involved.

A stopped service is a door that is closed but not locked. This module locks
the five you almost certainly do not use.

### This is Microsoft's own recommendation, not ours

Microsoft's security guidance for system services says:

> *"We recommend you disable the following services and their related scheduled
> tasks on Windows Server 2016 with Desktop Experience:"*

and lists Xbox Live Auth Manager and Xbox Live Game Save first, each carrying
the recommendation **"Should be disabled"**, together with the scheduled task
this module also disables.

**The honest caveat:** both source documents are Windows *Server*
documentation. They describe the same service names, shipped with the same
Desktop Experience component set that client Windows runs — Microsoft records
each of these services' installation as *"Only with Desktop Experience"*. There
is no equivalent per-service disable guidance for client Windows in the corpus.
The claim made is precisely that these are the vendor's own words about these
exact services, and no more.

### Administrator rights are required

Service start types live under `HKLM\SYSTEM` and are machine-wide. The
numbered launchers ask Windows for elevation properly.

---

## The launchers at a glance

| # | Launcher | Admin? | What it does |
|---|---|---|---|
| 1 | Check what is on now | No | Every service, task and Xbox app |
| 2 | Preview the changes (safe) | No | Every change; does none of them |
| 3 | Apply the changes | **Yes** | Disables 5 services + 1 task |
| 4 | UNDO everything | **Yes** | Every start type back from the newest backup |
| 5 | UNDO back to the original | **Yes** | As if this was never run |
| 6 | Prove the undo works | **Yes** | Apply, undo, compare — net zero on a pass |
| 7 | Test the safety logic | No | 44 checks on the machinery |

---

## What it changes

| Service | Was | Becomes | Had a trigger? |
|---|---|---|---|
| `XblAuthManager` | Manual, LocalSystem | Disabled | no |
| `XblGameSave` | Manual, LocalSystem | Disabled | **yes — neutralised** |
| `XboxGipSvc` | Manual, LocalSystem | Disabled | **yes — neutralised** |
| `XboxNetApiSvc` | Manual, LocalSystem | Disabled | no |
| `BcastDVRUserService` | Manual (per-user **template**) | Disabled | no |
| `XblGameSaveTask` | Enabled | Disabled | — |

Start `3` is Manual (wakes when asked), `4` is disabled.

### The per-user service, and why "disabled" means the template

`BcastDVRUserService` is a **template**. Windows stamps a per-user instance
from it at sign-in — you will see something like `BcastDVRUserService_7d78f` —
and deletes the instance at sign-out.

Microsoft's guidance is specific about this class: *"This is a 'per-user
service', and as such, the template service must be disabled."* So the module
disables the template and **deliberately does not touch the live instance**:
rewriting a thing that is about to be deleted, while leaving the thing that
recreates it, would be a half-measure that looks like a result.

**Consequence you should know about:** Game DVR keeps working in your *current*
session until the next sign-out, because that session's instance predates the
change. The module's own output says so; this is not a failure.

---

## Recommended first session

1. **`1 - Check what is on now`** — see the five services, their accounts and
   their trigger state.
2. **`6 - Prove the undo works`** — prove the round trip on your machine.
3. **`3 - Apply the changes`**.
4. Sign out and back in to clear the per-user DVR instance.

---

## `Remove-XboxServices` scripts — every option

```bash
powershell -ExecutionPolicy Bypass -File .\Test-XboxServices.ps1
powershell -ExecutionPolicy Bypass -File .\Disable-XboxServices.ps1 -WhatIf
powershell -ExecutionPolicy Bypass -File .\Disable-XboxServices.ps1
powershell -ExecutionPolicy Bypass -File .\Restore-XboxServices.ps1
powershell -ExecutionPolicy Bypass -File .\Restore-XboxServices.ps1 -Original
powershell -ExecutionPolicy Bypass -File .\Restore-XboxServices.ps1 -List
```

### Exit codes

| Code | Meaning |
|---|---|
| 0 | applied |
| 3 | backup refused (or the undo's own snapshot failed); nothing changed |
| 4 | nothing to do, or unelevated; no backup written |
| 5 | completed, but a write failed |

The round trip gates on **all** of these, and on any unexpected code — a
crashed apply that fell through to the undo would restore a stale backup and
mutate the machine mid-proof.

---

## Troubleshooting

### Game DVR still works after applying

Expected until your next sign-out. See the per-user template section above.

### An Xbox controller stopped being recognised

`XboxGipSvc` manages Xbox accessories. Undo with 4, or re-enable just that one:

```bash
sc.exe config XboxGipSvc start= demand
```

### The Xbox apps are still installed

Correct — this module disables **services**, not apps. Removing app packages is
a different class of change with a different reversibility story, and it
belongs to a separate module. `1 - Check what is on now` lists them so nothing
is hidden.

### `xboxgip` is still enabled

Also correct, and deliberate. `xboxgip` is a **kernel driver**, not a service —
it lives in the same registry container and is easily swept up by a name match.
The module's allow-list names services exactly, never by wildcard, and its
self-test asserts that a lookalike name is refused.

---

## What this module deliberately does not do

- **Remove any Xbox app package.** Services only.
- **Touch `GamingServices` / `GamingServicesNet`.** Store gaming plumbing.
- **Touch the `xboxgip` driver.** Out of scope by construction.
- **Delete anything.** A disabled service is one registry value away from
  exactly where it was, and the round trip proves the return.
