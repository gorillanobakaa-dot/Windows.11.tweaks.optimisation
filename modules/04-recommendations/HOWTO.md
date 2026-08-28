# How to use the recommendations module

*Ten switches that turn off suggestions, tips, "recommendations" and — the one
that matters — Windows installing promoted apps without asking. All per-user,
all reversible, no administrator rights needed anywhere.*

---

## Before you start

### This is the least dangerous module here

Every change is a per-user registry value with a recorded previous value. No
services, no software removal, no administrator rights. If you are working
through the modules in order and want to build confidence, this is a good one
to start with.

### The split that matters: documented vs observed

The ten settings are **not** equivalent, and the module refuses to pretend they
are.

**Five are documented by Microsoft**, each with a quoted sentence, a file and a
line number you can check. These apply by default.

**Five are real, present on this machine, recommended by every debloat guide on
the internet, and absent from Microsoft's documentation entirely.** They sit
behind a separate switch, `-IncludeObserved`, and are labelled `[uncited]`
everywhere they appear.

That split is the project's rule — a claim is quoted or it is labelled — and it
does not bend for a good story. Including the most important one:

> **`SilentInstalledAppsEnabled` was set to `1` on this machine.** That governs
> whether Windows may **install promoted applications without asking you**.
> It is undocumented. It is also the single most consequential value in this
> entire repository.

---

## The launchers at a glance

| # | Launcher | What it does |
|---|---|---|
| 1 | Check what is on now | All ten settings, with their citations |
| 2 | Preview the changes (safe) | Every change that would happen; does none |
| 3 | Apply the changes | The **documented five** |
| 4 | Apply the undocumented ones too | All ten |
| 5 | UNDO everything | Back to the newest backup |
| 6 | UNDO back to the original | As if this was never run |
| 7 | Prove the undo works | Apply, undo, compare — net zero on a pass |
| 8 | Test the safety logic | 36 checks on the machinery |

None of them needs administrator rights.

---

## Recommended first session

1. **`1 - Check what is on now`** — see which are set, and read the citations.
2. **`7 - Prove the undo works`** — prove the round trip on your machine first.
3. **`3 - Apply the changes`** — the documented five.
4. If you also want the undocumented five, **`4`**. Read what they are first.

---

## The ten settings

### Documented by Microsoft (launcher 3)

| Setting | What it stops |
|---|---|
| `HttpAcceptLanguageOptOut` | Handing websites your language list — a browser-fingerprinting signal |
| `DisableTailoredExperiencesWithDiagnosticData` | Your diagnostic data being used to tailor tips and ads |
| `DisableWindowsSpotlightFeatures` | The whole Spotlight family: suggested apps, Windows tips, lock-screen rotation |
| `DisableCloudOptimizedContent` | Windows fetching cloud-chosen content to show you |
| `Start_TrackDocs` | Recently-opened items appearing in Start, Jump Lists and Explorer |

### Observed but undocumented (launcher 4 adds these)

| Setting | What it stops |
|---|---|
| **`SilentInstalledAppsEnabled`** | **Windows installing promoted apps without asking** |
| `SystemPaneSuggestionsEnabled` | App suggestions in the Start menu |
| `SubscribedContent-338389Enabled` | Tips, tricks and suggestion notifications |
| `SoftLandingEnabled` | Tip notifications shown after updates |
| `Start_TrackProgs` | Windows tracking which apps you open to rank Start and search |

---

## `Disable-Recommendations.ps1` — every option

```bash
powershell -ExecutionPolicy Bypass -File .\Disable-Recommendations.ps1 -WhatIf
powershell -ExecutionPolicy Bypass -File .\Disable-Recommendations.ps1
powershell -ExecutionPolicy Bypass -File .\Disable-Recommendations.ps1 -IncludeObserved
```

### No switches

Applies the documented five. Each row in the output carries its `[R-nn]`
citation tag.

### `-IncludeObserved`

Adds the five undocumented ones, each marked `[uncited]` in the output so the
distinction survives all the way to the screen.

### `-WhatIf`, `-Tag`

Preview without writing; label the backup file.

### Exit codes

`3` = backup refused, nothing changed. `4` = nothing to do, no backup written.

---

## `Restore-Recommendations.ps1` — every option

```bash
powershell -ExecutionPolicy Bypass -File .\Restore-Recommendations.ps1
powershell -ExecutionPolicy Bypass -File .\Restore-Recommendations.ps1 -Original
powershell -ExecutionPolicy Bypass -File .\Restore-Recommendations.ps1 -List
```

### Absent is not zero

Most of these values **did not exist** before the module ran. The backup
records that, so the undo **removes** the value rather than writing a `0` —
and removes the registry key the apply created, if nothing else has been
written into it.

An explicit `0` is a policy a future administrator has to reason about. Absent
is absent. They are not the same state, and the round trip proves the
difference survives: ten readings moved and returned, **including whole key
chains** created by the apply.

---

## Troubleshooting

### The settings do not seem to have taken effect

Several are read when Explorer starts. Sign out and back in, or restart
Explorer:

```bash
powershell -Command "Stop-Process -Name explorer -Force"
```

It restarts automatically.

### Suggestions came back after a Windows update

Feature updates can reset per-user content settings. Re-run the apply; it is
idempotent and will report "already as wanted" for anything still set.

### I want the Spotlight lock-screen pictures back

That is `DisableWindowsSpotlightFeatures`. Undo everything with 5, or re-enable
just that one:

```bash
powershell -Command "Remove-ItemProperty 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name DisableWindowsSpotlightFeatures"
```

---

## What this module deliberately does not do

- **Present the undocumented five as documented.** They are behind their own
  switch and labelled `[uncited]` in every place they appear.
- **Need administrator rights.** Everything here is per-user by design.
- **Touch the machine-wide equivalents.** A per-user change affects you; the
  machine-wide version affects every account, which is a different decision.
