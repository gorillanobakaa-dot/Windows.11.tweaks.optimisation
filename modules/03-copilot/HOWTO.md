# How to use the Copilot module

*Two tiers. One is reversible from a backup and proved by execution. The other
removes software and can never be undone from a file. The module never blurs
that line, and neither does this page.*

---

## Before you start

### Copilot is four separate installed things

That is the finding the whole module is shaped around. On the machine this was
written for, "Copilot" meant:

| | What it is | Removable by |
|---|---|---|
| The app | `Microsoft.Copilot`, an app package | Store reinstall |
| The application | A full Chromium program in `Program Files (x86)`, **1,287 MB**, with its own updater | Downloading it again |
| The service | `MicrosoftCopilotElevationService`, running as **LocalSystem** | Removed with the application |
| The settings | Taskbar button, policy values | A backup file |

Both installs carried the **same version number** - one release delivered twice
by two mechanisms, which is why removing one leaves the other. Most guides
remove the app package and stop, leaving 1.3 GB of privileged software with its
own updater on disk.

### The advice everyone gives is the advice Microsoft withdrew

Every debloat guide sets `TurnOffWindowsCopilot`. Microsoft's own documentation
says of that policy: *"The policy is subject to near-term deprecation."* The
recommended replacement is AppLocker, which is **not available on Windows
Home**. The modern alternative, policy-based in-box app removal, is *"Only
Enterprise (ENT) and Education (EDU) editions"*.

So on a Home machine none of the three documented controls is both available
and endorsed. That is the platform's actual state, not a gap in this module -
and it is why the module's real answer is removal.

### Tier 2 is not reversible. Decide before you click, not after.

You cannot restore 1,287 MB of deleted files from a JSON file. The module
records what to **reinstall** - package name, Store link, version, uninstall
string - which is a different thing and is never presented as a backup.

---

## The launchers at a glance

| # | Launcher | Admin? | Reversible? |
|---|---|---|---|
| 1 | Check what is on now | No | reads only |
| 2 | Preview the changes (safe) | No | reads only |
| 3 | Turn Copilot off (settings only) | No | **yes, from a backup** |
| 4 | UNDO the settings | No | - |
| 5 | Prove the settings undo works | No | net zero on a pass |
| 6 | REMOVE the Copilot app | No | **only by reinstalling from the Store** |
| 7 | REMOVE everything | **Yes** | **only by downloading Copilot again** |
| 8 | Test the safety logic | No | reads only |

**3 is undone by 4 and proved by 5. 6 and 7 are removals and nothing undoes
them.**

---

## Recommended first session

1. **`1 - Check what is on now`** - see all four forms on your machine.
2. **`2 - Preview the changes`** - see exactly what would happen.
3. **`5 - Prove the settings undo works`** - prove the reversible tier
   round-trips before trusting it.
4. **`3 - Turn Copilot off`** - if settings are all you want, stop here.
5. Only then consider 6 or 7.

---

## `Test-Copilot.ps1` - every option

```bash
powershell -ExecutionPolicy Bypass -File .\Test-Copilot.ps1
```

Reports all four forms, plus the related packages the module deliberately
leaves alone. Run it **elevated** if you want the provisioned-package state -
that is what a newly created user account would receive, and it cannot be read
without administrator rights.

> On the machine this was written for, that read returned "Access is denied"
> even when elevated. The module reports the real reason rather than blaming
> missing rights, and records the state as **unknown** rather than "no".

---

## `Remove-Copilot.ps1` - every option

```bash
powershell -ExecutionPolicy Bypass -File .\Remove-Copilot.ps1 -WhatIf
powershell -ExecutionPolicy Bypass -File .\Remove-Copilot.ps1
powershell -ExecutionPolicy Bypass -File .\Remove-Copilot.ps1 -RemoveApp -RemoveSystemInstall
```

### No switches - settings only

Sets the taskbar button and the policy values. Fully reversible. This is
launcher 3.

### `-RemoveApp`

Removes the `Microsoft.Copilot` package using Microsoft's documented
PowerShell method, and - when elevated and readable - the **provisioned** copy
too, so new user accounts do not receive it.

### `-RemoveSystemInstall`

Runs the **registered uninstaller** for the Program Files application. Needs
administrator rights.

It does not delete the folder by hand. A registered uninstaller exists and it
is the supported route; deleting the folder underneath it leaves the uninstall
entry, the service registration and the updater task behind, turning a clean
removal into a mess.

### `-SkipSettings`

Removes without touching the tier 1 settings.

### `-WhatIf`

Prints every change and removal that would happen, and does none of it.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | done |
| 3 | backup refused; nothing changed |
| 4 | nothing to do; no backup written |

### What "success" looks like, and what it does not

The uninstaller's exit code is **recorded, not assumed**. On the run this
module documents, it exited **19** with the folder verifiably gone - so the
removal was recorded *with that exit code*, and the summary told the operator
to check for leftovers. A subsequent sweep found no files, no service and no
uninstall entry.

If the folder is still present a minute later, the module reports FAILED and
writes **no** removal record, because a removal it cannot confirm is not a
removal.

---

## `Restore-Copilot.ps1` - every option

```bash
powershell -ExecutionPolicy Bypass -File .\Restore-Copilot.ps1
powershell -ExecutionPolicy Bypass -File .\Restore-Copilot.ps1 -Original
powershell -ExecutionPolicy Bypass -File .\Restore-Copilot.ps1 -List
```

Restores the **settings only**. It cannot reinstall removed software and will
never claim to. If `backups\removed-not-restorable.json` exists, it prints the
contents - what was removed, when, and the route back.

`-Original` restores from the write-once original state. `-List` shows the
available backups.

---

## The removal record

`backups\removed-not-restorable.json` is the module's central honesty artifact:

```json
[ { "removedAt": "...", "what": "system-level application",
    "id": "C:\\Program Files (x86)\\Microsoft\\Copilot",
    "version": "152.0.4191.42",
    "uninstallerExitCode": 19, "serviceLeftBehind": false,
    "routeBack": "download and install Copilot again from Microsoft" } ]
```

**It is not a backup.** It records what to reinstall and from where.

If it ever fails to parse, the module preserves the unreadable copy under
another name rather than overwriting it - it is the only inventory of software
already removed, and it once had weaker protection than the ordinary backups.

---

## Troubleshooting

### Copilot still appears in Start-menu search after removal

The search panel and an open Settings window both cache app lists. The live
list (`Get-StartApps`) will not have it. Flush the cache:

```bash
powershell -Command "Stop-Process -Name SearchHost -Force"
```

It restarts on its own. Judge state by what the machine reports, not by what a
cached panel still paints.

### How do I confirm it is really gone?

```bash
powershell -Command "Get-AppxPackage -AllUsers -Name '*copilot*'"
powershell -Command "Test-Path 'C:\Program Files (x86)\Microsoft\Copilot'"
powershell -Command "Get-Service MicrosoftCopilotElevationService -ErrorAction SilentlyContinue"
```

All three empty or `False` means gone at every level Windows registers software.

### I want Copilot back

Reinstall from the Microsoft Store listing recorded in the removal record. The
settings tier is restored separately with launcher 4.

---

## What this module deliberately does not do

- **Delete files by hand** under `Program Files (x86)\Microsoft\Copilot`.
- **Touch `Microsoft.BingSearch`.** It is what the Start menu uses for web
  results; removing it is a different decision and yours to make separately.
- **Disable the service directly.** It is removed by the application's own
  uninstaller. Disabling a service whose files remain is a half-measure that
  looks like a result.
- **Claim the deprecated policy is the answer.** It is set as a secondary
  measure and labelled deprecated everywhere it appears.
- **Claim any of it is reversible when it is not.** The restore allow-list is
  structurally incapable of containing the removals, and the self-test asserts
  that.
