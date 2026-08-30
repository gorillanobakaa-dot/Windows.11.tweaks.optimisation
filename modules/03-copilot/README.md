# Copilot - what is actually installed, and what can be undone

## Just want to click something?

| Double-click this | What happens | Admin? | Reversible? |
|---|---|---|---|
| **1 - Check what is on now** | Full inventory of every form Copilot takes on this PC | No | reads only |
| **2 - Preview the changes (safe)** | Every change AND removal that would happen; does none of it | No | reads only |
| **3 - Turn Copilot off (settings only)** | The taskbar button and the per-user policy value | No | **yes, from a backup** |
| **4 - UNDO the settings** | Puts the settings back from the most recent backup | No | - |
| **5 - Prove the settings undo works** | Applies the settings, undoes them, compares every one | No | net zero on a pass |
| **6 - REMOVE the Copilot app** | Removes the app for your account, the way Microsoft documents | No | **only by reinstalling from the Store** |
| **7 - REMOVE everything** | The app AND the 1.3 GB Program Files install, via its registered uninstaller | **Yes** | **only by downloading Copilot again** |
| **8 - Test the safety logic** | Tests the machinery that decides whether to write | No | reads only |

The reversibility column is the honest one. 3 is undone by 4 and proved by 5.
**6 and 7 are removals: no backup file can reverse them**, and the module records
what to reinstall and from where instead of pretending otherwise.

---

## In plain language

### Copilot is not one thing

That is the finding that shapes everything else here. On this machine, "Copilot"
means four separate things, installed in four different ways, removed in four
different ways:

| | What it is | Size | Can it be put back? |
|---|---|---|---|
| **The app** | `Microsoft.Copilot`, an app package | small | Yes - reinstall from the Store |
| **The application** | A full Chromium program in `Program Files (x86)` with its own updater | **1,287 MB** | Only by downloading it again |
| **The service** | `MicrosoftCopilotElevationService`, running as **LocalSystem** | - | Removed with the application |
| **The settings** | Taskbar button, policy values | - | Yes - from a backup file |

Most guides deal with the first one and stop. On this machine the first one is
the small one.

### The service is the part worth pausing on

`MicrosoftCopilotElevationService` runs as **LocalSystem** - the highest
privilege level on Windows - and its start type is **Manual**.

Manual does not mean off. It means it is not running *now*, and starts when
something asks for it. This is precisely the distinction the rest of this
repository is built around: a resting snapshot of a machine says 133 services are
running, and hides the fact that many more can be woken. A stopped LocalSystem
service is not an absent one. See [`../../THREAT-MODEL.md`](../../THREAT-MODEL.md).

### The advice everyone gives is the advice Microsoft withdrew

Every "debloat Windows 11" guide tells you to set a registry value called
`TurnOffWindowsCopilot`. Microsoft's own documentation says not to. Of that
policy and its MDM equivalent:

> "The policy is subject to near-term deprecation." [R-86]

The recommended replacement is AppLocker, which:

> "Prevent the consumer app from being installed if it isn't already on the device." [R-87]

> "Block the consumer app from being launched if it's already installed." [R-88]

**AppLocker enforcement is not available on Windows 11 Home**, which is what this
machine runs.

And the *other* modern mechanism, policy-based in-box app removal, is not
available either:

> "Only Enterprise (ENT) and Education (EDU) editions support this feature." [R-89]

It also requires MDM enrolment or domain join. On a home machine, neither exists.

So the honest position is this. Of the three documented ways to deal with Copilot:

- **AppLocker** - recommended by Microsoft, unavailable on Home
- **Policy-based in-box app removal** - modern, Enterprise/Education only
- **`TurnOffWindowsCopilot`** - available on Home, and deprecated by its author

None of them is both available here and endorsed. That is not a gap in this
module; it is the actual state of the platform, and a page that told you
otherwise would be selling you something.

What *is* both available and documented is direct removal:

> "Remove the Copilot app using PowerShell script:" [R-90]

followed by an exact `Get-AppxPackage` / `Remove-AppxPackage` pair. That is the
route this module takes.

### Removing software is not a settings change

This is the fact the whole module is shaped around.

Modules 01 and 02 change settings. A setting has a previous value, so "undo"
means writing the old value back, and a small JSON file is enough to hold it.
Both modules prove their undo by performing it.

Copilot is different. You cannot restore 1,287 MB of deleted files from a JSON
file. Microsoft is explicit about this for its own removal mechanism:

> "After an app is removed from a device via this policy, you need to reprovision the app on the device." [R-91]

So the module splits in two, and the split is enforced in code - the removals are
deliberately **not** in the list a restore is permitted to act on, so a restore
cannot claim them:

**Tier 1 - reversible.** The taskbar button and the policy values. Backed up,
restored, round-trip proved, exactly like modules 01 and 02.

**Tier 2 - not reversible here.** Removing the app and the 1.3 GB application.
What gets recorded is enough to *reinstall from Microsoft* - the exact package
name, the Store link, the version - which is not the same as a backup, and will
never be described as one.

`MODULE-STANDARD.md` R4.10 covers this case: where a change cannot be reversed by
replaying a state file, the module must say so and state what the route back
actually is.

---

## What is on this machine right now

Measured on 2026-08-26, Windows 11 **Home**, build 26200, by
`1 - Check what is on now`:

| Reading | Value |
|---|---|
| `Microsoft.Copilot` app | present, v152.0.4191.42 |
| Program Files application | present, **1,779 files, 1,287.2 MB** |
| Its version | 152.0.4191.42 - the same, so they are two copies of one release |
| Registered uninstaller | yes - `copilot_setup.exe --uninstall --mscopilot --system-level` |
| `MicrosoftCopilotElevationService` | present, **Stopped**, start type **Manual**, runs as **LocalSystem** |
| `ShowCopilotButton` | not set |
| `TurnOffWindowsCopilot` (user and machine) | not set |
| Copilot processes running | none |
| `Microsoft.BingSearch` | present, v1.1.43.0 - related, deliberately left alone |

Two details worth drawing out.

**The two installs are the same version.** 152.0.4191.42 in both places. This is
not an old leftover next to a current app; it is one release delivered twice, by
two different mechanisms, which is why removing one does not remove the other.

**Nothing is running.** That is a fact about this moment, not about what is
installed. The service is Manual and the application is on disk. Judging exposure
by what is in Task Manager right now is the mistake this whole repository exists
to avoid.

---

## What has actually been proved

| | Result |
|---|---|
| Settings round trip, elevated, on this machine | **PASS** - all 3 settings moved (including creating and deleting the policy keys) and every one came back. No software moved |
| Settings round trip, unelevated | **PASS** - the 2 per-user settings; the HKLM value skipped and named symmetrically |
| Comparison proved falsifiable | a doctored setting, a doctored software-presence flag, and a null state are all caught |
| Safety logic self-test | **33 checks, 0 failures** - and its first run caught a real crash bug in this module's own file validator, which was also present in modules 01 and 02 |
| Citations | **7 / 7 verified** against the offline corpus |
| Adversarial audit | **done - 14 findings (2 severe, 3 serious), every one fixed and regression-tested the same day; the self-test grew from 33 to 45 checks** |
| Removals executed on this machine | **YES - 2026-08-26, see below** |

What is deliberately NOT proved: that the removals are reversible. They are not,
no test pretends they are, and the restore allow-list is structurally incapable
of containing them - which the self-test checks.

Full walkthrough with every option: [`HOWTO.md`](HOWTO.md).

---

## What happened when it ran (2026-08-26)

The full removal was executed on this machine, elevated, on 2026-08-26.

| | Result |
|---|---|
| Tier 1 settings | all 3 at target (the HKLM policy value was set by this run; the per-user two were already applied) |
| `Microsoft.Copilot` app | **removed** - and a later elevated sweep confirmed **zero** packages matching \*copilot\* remain for ANY account on the machine |
| Program Files application | **gone** - the registered uninstaller ran and the folder no longer exists |
| `MicrosoftCopilotElevationService` | **not present** |
| Uninstall registrations (HKLM native + WOW6432Node + HKCU) | zero Copilot entries |
| `removed-not-restorable.json` | written and parse-verified: 2 entries, each with its route back |

Three honest footnotes, because a clean summary would be hiding them:

1. **The uninstaller exited 19, not 0.** The folder was verifiably gone, so the
   removal was recorded - *with* that exit code in the record - and the summary
   said to check for leftovers instead of calling it clean. A later sweep found
   no appx, no service, no uninstall entry and no files.
2. **The provisioning database refused to be read, even elevated** ("Access is
   denied" from `Get-AppxProvisionedPackage` in two separate elevated runs). So
   whether a *provisioned* copy exists - what a brand-new user account would
   receive - is recorded as UNKNOWN, not as "no". The module knows the
   documented route for that copy - "Remove the app for new user accounts.
   From an elevated command prompt, run the following Windows PowerShell
   command:" [R-97] - and executes it when the database can be read. Zero packages are staged for
   any existing account, so no current account can see Copilot regardless. The
   module now reports the real reason instead of a wrong "needs administrator
   rights" message; the denial itself is an open finding about this machine.
3. **The Start-menu search panel and a stale Settings window kept showing a
   "Copilot" tile after the excision.** Both draw from caches; the live app
   list (`Get-StartApps`) had no such entry. Restarting the search hosts
   clears it. Judge state by what the machine reports, not by what a cached
   panel still paints - the thesis of this repository, once again.

One anomaly is on record: during the owner's apply-all run, the settings-only
apply at 21:43:02 wrote its backup and then its two per-user values were found
absent ninety seconds later. The same script re-run at 21:45:57 applied them
and they held from then on, surviving everything that followed. Most likely the
first run was interrupted at the console between backup and write; the honest
statement is that the cause was not captured. The backup written at 21:43:02
records the true original state either way.

---

## What this module will and will not do

**Will:** report everything; set the taskbar and policy values with a verified
backup and a proved undo; remove the app using Microsoft's documented method;
run the registered uninstaller for the Program Files application; record exactly
what is needed to reinstall either one.

**Will not:**

- **Delete files by hand.** No `Remove-Item` over `Program Files (x86)\Microsoft\Copilot`.
  A registered uninstaller exists and it is the supported route. Deleting the
  folder underneath it leaves the uninstall entry, the service registration and
  the updater scheduled work behind, and turns a reversible removal into a mess.
- **Touch `Microsoft.BingSearch`.** It is what the Start menu uses for web
  results. Removing it changes how Start behaves, which is a different decision
  and yours to make separately.
- **Disable the service directly.** It is removed by the application's own
  uninstaller. Disabling a service whose files remain is a half-measure that
  looks like a result.
- **Claim the deprecated policy is the answer.** It is set as a secondary
  measure and labelled deprecated everywhere it appears.
- **Claim any of it is reversible when it is not.**

---

## References

Every quotation carries a tag, the file, the line it starts on, and the sentence.
Check them yourself - the table is in the repository's machine-readable format:

```bash
powershell -ExecutionPolicy Bypass -File ..\..\READ-ONLY-verification\Verify-Citations.ps1 -Document .\README.md -Detailed
```

| ID | Claim | rel_path | line | quote |
|---|---|---|---|---|
| R-86 | TurnOffWindowsCopilot is deprecated by Microsoft | windows-itpro-docs/client-management/manage-windows-copilot.md | 110 | The policy is subject to near-term deprecation. |
| R-87 | AppLocker prevents installation | windows-itpro-docs/client-management/manage-windows-copilot.md | 118 | Prevent the consumer app from being installed if it isn't already on the device. |
| R-88 | AppLocker blocks launch of an already-installed copy | windows-itpro-docs/client-management/manage-windows-copilot.md | 119 | Block the consumer app from being launched if it's already installed. |
| R-89 | Policy-based in-box app removal is Enterprise/Education only | windows-itpro-docs/configuration/policy-based-inbox-app-removal/policy-based-inbox-app-removal.md | 67 | Only Enterprise (ENT) and Education (EDU) editions support this feature. |
| R-90 | Removal via PowerShell is the documented method | windows-itpro-docs/client-management/manage-windows-copilot.md | 120 | Remove the Copilot app using PowerShell script: |
| R-91 | Removal is not undone by policy; the app must be reprovisioned | windows-itpro-docs/configuration/policy-based-inbox-app-removal/policy-based-inbox-app-removal.md | 216 | After an app is removed from a device via this policy, you need to reprovision the app on the device. |
| R-97 | Removing the provisioned copy is Microsoft's documented route for keeping an app from new accounts | windows-itpro-docs/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services.md | 695 | Remove the app for new user accounts. From an elevated command prompt, run the following Windows PowerShell command: |
