# How to remove preinstalled apps

*The module that deletes software. Read the first two sections before you click
anything — this is the one where a wrong choice costs you something real.*

---

## Before you start

### There is no undo file. There is a best effort.

Every other module here writes a backup and puts things back. **This one cannot.**
You cannot restore a deleted app package from a JSON file.

What exists instead:

| | |
|---|---|
| **Payload still on disk** | Launcher 8 can re-register the app. Genuinely works. |
| **Payload deleted too** | Microsoft Store only. Launcher 8 says so per package rather than pretending. |

Which one you get depends on whether the provisioned copy went with it. The
module records the answer at the moment of removal, so you are never guessing.

### They come back, and that is the platform, not the module

On **2026-08-27 at 16:59** this machine's Windows Update reinstalled two Xbox
packages on its own, hours after the Xbox services were disabled.

Microsoft documents one mechanism that blocks reinstallation — and documents it
as **Enterprise and Education only**. This is Home.

So the honest expectation is: **removal is a delete, not a block.** Run
`1 - Check what is on now` every few weeks; it names anything that returned and
you re-run the removal. That is the workflow, not a workaround.

### Removing the *provisioned* copy is the half everyone skips

Microsoft's method is two steps. Most guides do only the second, which leaves
the app waiting for the next account created on the machine. This module does
both — which is why the real run asks for administrator rights and the preview
does not.

---

## Recommended first session

1. **`1 - Check what is on now`** — 107 packages, 44 of which Windows will not
   let go of.
2. **`10 - Test the safety logic`** — 58 checks, ten seconds, no admin.
3. **`4 - Preview SUPER`** — read the most aggressive tier even if you want
   LIGHT. It is the fastest way to understand what these tiers are.
4. Then pick a tier.

---

## Which tier?

| Tier | Removes | Pick it if |
|---|---|---|
| **LIGHT** | 16 | You want the obvious junk gone and nothing else. Game Bar, Xbox overlays, Mixed Reality, Feedback Hub, Journal, Clipchamp, Dev Home. Nothing here has a hardware or runtime role. |
| **MODERATE** | 30 | LIGHT + you do not use Teams, Phone Link, Mail & Calendar, Media Player, Films & TV, **Widgets**, or the OneDrive sync app. |
| **SUPER** | 37 | MODERATE + you accept losing **Photos** and Camera, and want the third-party preloads (WhatsApp, Adobe Express, Glance, Lenovo Settings) gone. |

### The three that catch people out

- **Widgets** (MODERATE) — `MicrosoftWindows.Client.WebExperience` *is* the
  widgets board. The taskbar button stops working because the thing behind it
  is gone.
- **Bing web results in Start** (MODERATE) — Start still searches your machine
  normally. Only the web results panel goes.
- **Photos** (SUPER) — **no default image viewer afterwards** unless you install
  one. Double-clicking a JPG will ask you what to open it with.

---

## `Remove-Apps.ps1` — every option

```bash
powershell -ExecutionPolicy Bypass -File .\Remove-Apps.ps1 -Tier light -WhatIf
powershell -ExecutionPolicy Bypass -File .\Remove-Apps.ps1 -Tier moderate
powershell -ExecutionPolicy Bypass -File .\Remove-Apps.ps1 -Tier super -Force -Tag before-trip
```

### `-Tier` (required)

`light`, `moderate` or `super`. Cumulative.

### `-WhatIf`

Lists every package that would go, with what each one is, and removes nothing.
Works **without** administrator rights, deliberately.

### `-Force`

Skips the typed confirmation. Without it you must type the **tier name** — not
"y", the actual word.

### `-Tag`

Labels the inventory file.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | done |
| 3 | inventory could not be written; nothing removed |
| 4 | nothing to do, unelevated, or you declined |
| 5 | completed, but a removal failed |
| 6 | the tier names a protected package — **nothing was touched** |

### What a refusal looks like

```
    STOPPING. This tier names packages that must never be removed:
      X Microsoft.SecHealthUI is on the NEVER-REMOVE list: the Windows
        Security app - the interface to Defender...
    Nothing was changed.
```

The refusal fires **before** the inventory is written — the self-test asserts
that ordering, so an illegal tier cannot even leave a file behind.

### What the output tells you, precisely

```
    ESTABLISHED : 16 package(s) removed and confirmed absent afterwards.
    ESTABLISHED : 16 provisioned copy/copies removed - new accounts will
                  not receive those.
    NOT ESTABLISHED : that they stay gone. On this edition Windows Update
                  can reinstall them.
```

Each removal is confirmed by **re-querying the machine**, not by the absence of
an error. A removal that returns success and leaves the package installed is
reported as a failure.

---

## `Restore-Apps.ps1` — best effort

```bash
powershell -ExecutionPolicy Bypass -File .\Restore-Apps.ps1 -List
powershell -ExecutionPolicy Bypass -File .\Restore-Apps.ps1
powershell -ExecutionPolicy Bypass -File .\Restore-Apps.ps1 -Name Microsoft.GetHelp
```

`-List` shows everything removed and the route back for each — changes nothing.
Without arguments it re-registers everything whose payload survived, and lists
the ones only the Store can bring back.

**The removal record is never cleared.** It is the history of what this module
removed, and check 1 uses it to spot apps that come back on their own.

---

## Troubleshooting

### An app I removed is back

Expected on this edition. Check 1 names it. Re-run the removal for its tier —
it is idempotent and reports anything already absent as nothing to do.

### Photos is gone and I want it back

Launcher 8 first. If the payload went, install Photos from the Microsoft Store —
launcher 9 shows the exact package name that was removed.

### The Widgets button does nothing

You removed MODERATE. `MicrosoftWindows.Client.WebExperience` is the board
itself. Hide the button in Taskbar settings, or reinstall from the Store.

### "Access is denied" reading the provisioned list, even as administrator

Known on this machine and recorded rather than explained away. The user-scope
removals still happen; what a **new account** would receive is reported as
**unknown**, not as none.

### Removal failed for one package

The module names it and exits 5. Common causes: the package is in use, or
Windows has re-flagged it as non-removable since the inventory was read. Re-run;
the tier is idempotent.

---

## What this module deliberately does not do

- **Call any removal reversible.** The record is named
  `removed-not-restorable.json`.
- **Remove Edge**, hardware control panels (Realtek, Intel, ELAN, Dolby), shared
  runtimes, media codecs, or the Store.
- **Touch anything you installed yourself** — including `Claude`, which is on
  the never-remove list by name.
- **Delete package folders by hand.**
- **Enumerate frameworks or resource packages at all.**
