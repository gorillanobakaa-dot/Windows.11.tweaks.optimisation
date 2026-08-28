# Module 08 — app de-bloat

*Remove the preinstalled apps you never asked for. Three cumulative tiers, 31
protected packages that no tier may name, and an honest answer to the question
every debloat script dodges: they come back.*

---

## Just want to click something?

| # | Launcher | Admin? |
|---|---|---|
| 1 | Check what is on now | no |
| 2 | Preview LIGHT | no |
| 3 | Preview MODERATE | no |
| 4 | Preview SUPER | no |
| 5 | REMOVE tier LIGHT | **yes** |
| 6 | REMOVE tier MODERATE | **yes** |
| 7 | REMOVE tier SUPER | **yes** |
| 8 | Try to put back what was removed | **yes** |
| 9 | Show what was removed | no |
| 10 | Test the safety logic | no |

Full walkthrough: [`HOWTO.md`](HOWTO.md).

---

## Read this before you use it

### This module removes software. It is not a settings module.

Every other module here changes a value and can put it back. This one deletes
app packages. **There is no backup file that restores an app**, and nothing in
this module pretends there is.

There is one real undo path, and it works only sometimes:

> If the package **payload** survives on disk after removal, the package can be
> re-registered from it. If the payload went with the package, the Microsoft
> Store is the only route back.

So the module records, for every removal, whether the payload survived — and
launcher 8 sorts the record into "can retry" and "Store only" and tells you
which is which. That record is **not** a backup and is never called one.

### Removed apps come back. This is measured, not theoretical.

On **2026-08-27 at 16:59** this machine's own Windows Update reinstalled
`Microsoft.XboxGameOverlay` and `Microsoft.XboxIdentityProvider` — hours after
the Xbox *services* had been disabled by module 05.

Microsoft documents exactly one mechanism that stops this. Under policy-based
in-box app removal, *"While the policy is active, removed apps remain blocked
from reinstallation"* [R-139]. And:

> *"Only Enterprise (ENT) and Education (EDU) editions support this feature."*
> [R-140]

**This machine is Home.** So on this edition removal is a delete, not a block.
That is not a flaw in the module; it is the platform, and the module's job is to
say so and to give you a checker that names anything that crawled back.

### What removing the *provisioned* copy actually buys you

Microsoft's documented method has two steps, and most guides only do the second:

- *"Remove the app for new user accounts."* [R-137] — the **provisioned** copy
- *"Remove the app for the current user."* [R-138] — your copy

Removing only your copy leaves the app waiting for the next account created on
the machine. This module does both, in that order, which is why the real run
needs administrator rights while the preview does not.

---

## The three tiers

Cumulative: MODERATE includes LIGHT, SUPER includes both. On this machine
**every package named by every tier is actually present** — 16, 30 and 37.

| Tier | Packages | What goes |
|---|---|---|
| **LIGHT** | 16 | Game Bar + Xbox overlays, Mixed Reality Portal, Feedback Hub, Get Help, Mobile Plans, Journal, Power Automate, Dev Home, Clipchamp, Messaging, People |
| **MODERATE** | 30 | LIGHT + Teams (both), Phone Link, Cross Device, Mail & Calendar, Media Player, Films & TV, **the Widgets board**, Bing web results in Start, OneDrive sync package, Quick Assist |
| **SUPER** | 37 | MODERATE + WhatsApp, Adobe Express, Glance, Lenovo Settings, new Outlook, Camera, **Photos** |

**SUPER removes Photos**, which leaves no default image viewer unless you
install one. That is stated in the tier data, in the preview, and on the
launcher, because a surprise like that discovered a week later is indefensible.

---

## The three refusals, enforced in code

A tier that names a protected package is **refused whole** — exit 6 — not
quietly trimmed. A tier naming a protected package is a tier somebody edited
without understanding it, and skipping the entry hides that from the person who
most needs to see it.

**1. The never-remove list — 31 patterns.** Not a taste list; each entry has a
reason:

| Protected | Because |
|---|---|
| `Microsoft.SecHealthUI` | the Windows Security app. Removing the UI does not remove the protection, it removes your ability to **see** it |
| `Microsoft.WindowsStore` | it is the documented route back for everything this module removes. Removing it removes the undo |
| `MicrosoftCorporationII.WinAppRuntime.*`, `Microsoft.VCLibs.*`, `Microsoft.UI.Xaml.*`, `Microsoft.NET.*` | shared runtimes. Removing one breaks *other people's applications*, not Windows |
| HEIF / HEVC / AV1 / VP9 / WebP / MPEG2 / AVC / WebMedia extensions | without them ordinary phone photos and web video stop working, silently |
| `RealtekSemiconductorCorp.*`, `AppUp.IntelGraphicsExperience`, `AppUp.IntelArcSoftware`, `ELANMicroelectronicsCorpo.*`, `DolbyLaboratories.DolbyAccess` | **hardware control panels, not bloat.** This is how the audio, graphics and trackpoint hardware is configured |
| `Microsoft.Paint`, `Microsoft.WindowsNotepad`, `Microsoft.WindowsCalculator`, `Microsoft.ScreenSketch` | basic utilities people expect to exist |
| `Claude` | **the owner's own installed application.** Nothing in a de-bloat module should touch software the owner chose to install |

**2. `NonRemovable` computed live.** Windows marks packages it will not release
— **44 of the 107** on this machine. The module reads that flag from the
machine rather than trusting a list, and refuses those too.

**3. Frameworks and resource packages are never enumerated.** A framework is a
shared runtime; it is out of scope by construction, not by remembering to
exclude it.

---

## What has actually been proved

| | |
|---|---|
| Self-test checks | **55**, 0 failures |
| Refusals proved able to fire | protected name, and a live `NonRemovable` flag |
| Applied to this machine | **NO — not yet.** Which tier, if any, is the owner's call |
| Citations verified at the cited line | every row below |

The self-test does not merely assert the refusals exist. It builds a **doctored
inventory** in which a real tier app is marked `NonRemovable`, feeds it to the
legality check, and requires the check to catch it and name it. A check that
cannot fail proves nothing.

---

## What this module deliberately does not do

- **Call any removal reversible.** The record file is literally named
  `removed-not-restorable.json`.
- **Remove Edge.** A separate decision with its own consequences.
- **Remove hardware control panels.** Realtek, Intel, ELAN and Dolby are on the
  never-remove list.
- **Touch anything the owner installed themselves.**
- **Delete package folders by hand.** Removal goes through the documented
  PowerShell method, which is the supported route.
- **Claim removal is permanent on this edition.** It is not, and the checker
  exists to catch the ones that return.

---

## References

Every quotation carries a tag, the file, the line it starts on, and the
sentence. Check them yourself:

```bash
python ..\..\READ-ONLY-verification\Build-ReferenceLibrary.py
```

| ID | Claim | rel_path | line | quote |
|---|---|---|---|---|
| R-137 | Microsoft's documented first step - remove the provisioned copy, so new accounts do not receive the app | windows-itpro-docs/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services.md | 695 | Remove the app for new user accounts. |
| R-138 | Microsoft's documented second step - remove the app for the current user | windows-itpro-docs/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services.md | 698 | Remove the app for the current user. |
| R-139 | The only documented mechanism that stops removed apps reinstalling themselves | windows-itpro-docs/configuration/policy-based-inbox-app-removal/policy-based-inbox-app-removal.md | 62 | While the policy is active, removed apps remain blocked from reinstallation |
| R-140 | That mechanism is unavailable on this edition, which is why removal here is a delete and not a block | windows-itpro-docs/configuration/policy-based-inbox-app-removal/policy-based-inbox-app-removal.md | 67 | Only Enterprise (ENT) and Education (EDU) editions support this feature. |
| R-141 | Provisioned UWP apps can be removed after the OS is installed, not only during imaging | windowsserverdocs/WindowsServerDocs/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration.md | 143 | UWP apps that are provisioned to a system can be removed during OS installation as part of a task sequence, or later after the OS is installed. |
