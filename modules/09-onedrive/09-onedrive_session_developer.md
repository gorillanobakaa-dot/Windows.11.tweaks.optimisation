# Module 09 (`09-onedrive`): remove OneDrive leftovers per account, block reinstall per machine

> Session record generated 2026-09-28

---

## Problem Being Solved

After a user-initiated uninstall (`UserInitiatedUninstall` = 1 under `HKCU\Software\Microsoft\OneDrive`), the audited machine retains `%SystemRoot%\System32\OneDriveSetup.exe` (86 MB), no OneDrive policy, the account's `OneDrive` and `OneDriveConsumer` environment variables pointing into a migrated account's profile path, `HKCU\Software\Microsoft\OneDrive` (with recorded account and host names), a `grvopen` URL handler targeting the deleted `OneDrive.exe`, an empty `HKCU\Software\SyncEngines\Providers`, and three leftover folders. No module in the framework covers this; module 08 only handles the `Microsoft.OneDriveSync` Appx package.

## Approach Taken

You add module 09 with two applying scripts split on the elevation boundary. `Remove-OneDriveLeftovers.ps1` (per-user, unelevated) removes values, exports then deletes keys, and recycles folders. `Block-OneDrive.ps1` (elevated; `-WhatIf` works unelevated) sets the two documented policies, stashes the installer into the run's backup after `takeown /a` and an Administrators grant with a SHA-256 comparison, removes `Run\OneDriveSetup` and `Run\OneDrive` from the default-user hive loaded at `HKU\W11T_OdDefault`, and recycles `%ProgramData%\Microsoft OneDrive`. `Restore-OneDrive.ps1` reverses either part from a per-run backup folder. The value machinery (absent versus zero, created-key chains, allow-list restore, pre-restore snapshots) follows module 04.

## Before

Framework modules 01 to 08; no OneDrive leftover handling and no OneDrive policy handling. On the audited account, `Test-OneDrive.ps1` (once written) reports seven account leftovers, two open policies, one installer present and one machine folder present.

## After

`modules/09-onedrive` exists with `_Common.ps1`, three applying/undo scripts, `Test-OneDrive.ps1`, `Test-SafetyLogic.ps1` (43 checks), `Test-RoundTrip.ps1`, nine launchers, `README.md`, `HOWTO.md` and this session record. The account part is applied on the audited machine: seven items removed, zero failures, all account items read as `gone`. The machine part is built and previewed (four planned changes) but not applied, and its round trip is not run; both need elevation.

## Known Alternatives

Extending module 08. Not taken: module 08 removes Appx packages and is recorded as not restorable, while this work is registry, file and hive state with a full undo. Deleting `OneDriveSetup.exe` outright. Not taken: moving it into the backup keeps the change reversible. Applying the uncited items only behind an opt-in switch, as module 04 does. Not taken: they are leftovers of a program already removed, not feature choices.

## Files Changed

| File | Change | What Changed | Why |
|------|--------|--------------|-----|
| `modules/09-onedrive/_Common.ps1` | added | Settings tables (`$script:OdValues`, `$script:OdKeys`, folders, installers, default-hive constants), state capture, verified backup, key export, guarded removal, allow-list restore. | Single source of truth for apply, backup and restore, as in module 04. |
| `modules/09-onedrive/Remove-OneDriveLeftovers.ps1` | added | Account part; exit codes 0, 3, 4, 5. | Per-user removal needs no elevation. |
| `modules/09-onedrive/Block-OneDrive.ps1` | added | Machine part; refuses unelevated with exit 4 unless `-WhatIf`. | HKLM, System32 and the default-user hive need elevation. |
| `modules/09-onedrive/Restore-OneDrive.ps1` | added | Undo for either part; validates `.reg` export names from the backup as bare `.reg` leaf names. | The undo must work with no arguments and must not trust file names in a backup. |
| `modules/09-onedrive/Test-OneDrive.ps1` | added | Read-only report with counts of open ways back and remaining leftovers. | One place to verify the end state. |
| `modules/09-onedrive/Test-SafetyLogic.ps1` | added | 43 checks in a temp folder and `HKCU\Software\W11T_OdSelfTest`. | Tests refusal paths without touching real state. |
| `modules/09-onedrive/Test-RoundTrip.ps1` | added | Apply, undo, compare; keys compared by full `reg export` text. | Proves the undo; leaves folders and the installer out so the proof is automatic. |
| `modules/09-onedrive/*.cmd` | added | Nine launchers; 4, 6 and 8 self-elevate with the `fltmc` check used in module 07. | Double-click entry points in the house style. |
| `modules/09-onedrive/README.md, HOWTO.md, narrative.txt` | added | Dual-track documentation and citation table R-145, R-146. | Module standard requires both documents; the table feeds `Build-ReferenceLibrary.py`. |

## Decisions Made

- 📄 **Split into account and machine scripts.** - "two parts, because Windows draws a line between an account and the machine".
- 📄 **Apply uncited items by default.** - "they are leftovers of a program the owner already removed, not settings with a choice attached".
- 📄 **Guard `SyncEngines` and `grvopen`.** - "SyncEngines is kept if any other sync provider (Dropbox, for example) is registered in it, and grvopen is kept unless it points at OneDrive.exe".
- 🤖 **Use citation IDs R-145 and R-146.** - R-97 to R-101 are already assigned in modules 03 and 05; R-144 is the highest ID in use.
- 📄 **Keep `backups/` out of git through `.git/info/exclude`.** - "It is excluded from git and must never be published."

## Tried and Abandoned

- **Citation IDs R-97 and R-98.** - Both are already used by the decision records of modules 03 and 05; the module renumbers to R-145 and R-146 and the self-test passes 43 checks after the change.

## ⚠ Claimed But Not Verified

*Prior documents claimed these are done. No test evidence found in this diff:*

- That `Block-OneDrive.ps1` applies cleanly on a real elevated run. It is previewed only.
- That the machine round trip passes. It has not run.
- That the default-user hive holds a `Run\OneDriveSetup` value on this machine. Reading it needs elevation.
- That the two policies survive a feature update.

## Open Items

| Item | Priority | Blocks |
|------|----------|--------|
| Run launcher 6 (machine round trip), then launcher 4, elevated, on the audited machine. | high | the machine block on the audited machine |
| Adversarial audit of module 09. | medium | nothing currently |
| Decision records DEC-09-* and reference-library rebuild for R-145 and R-146. | medium | nothing currently |

## How to verify this work is correct

**Step 1:**
```bash
`powershell -ExecutionPolicy Bypass -File .\Test-SafetyLogic.ps1`
```
  - **Pass:** `checks passed : 43`, `checks failed : 0`, exit 0
  - **Fail:** Any `FAILED:` line and exit 1.

**Step 2:**
```bash
Elevated: `powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1 -Part Machine -Force` before any machine apply.
```
  - **Pass:** `PASS - everything came back to exactly where it started.`, exit 0
  - **Fail:** `FAIL` followed by the items that differ, exit 1.

**Step 3:**
```bash
Elevated: `powershell -ExecutionPolicy Bypass -File .\Block-OneDrive.ps1`
```
  - **Pass:** `backup written and verified`, `failed: 0`, exit 0
  - **Fail:** A `FAILED:` line naming the item, exit 5.

**Step 4:**
```bash
`powershell -ExecutionPolicy Bypass -File .\Test-OneDrive.ps1`
```
  - **Pass:** `ways back still open : 0`, `leftovers remaining  : 0`
  - **Fail:** Any item marked `open` or `present`.


## Technical Debt

🟡 **LOW** - After an undo, `OneDriveSetup.exe` is owned by Administrators, not TrustedInstaller. → Restore the original owner with `icacls /setowner "NT SERVICE\TrustedInstaller"` in `Restore-OneDrive.ps1`.
🟡 **LOW** - Account cleanup covers only the account that runs it. → Add an elevated pass over other loaded or loadable profiles, guarded per key as now.
🟡 **LOW** - Round-trip output parsing depends on exit codes only; child output is discarded. → Write the child output to the run folder on FAIL for forensics.

## Claim Sources

| Claim | Basis | Evidence |
|-------|-------|----------|
| Account part applied cleanly | 📄 stated in input | seven items removed, zero failures |
| Self-test detects sabotage | 📄 stated in input | 8 checks failed |
| Account round trip compares full key contents | 📄 stated in input | with every key compared by its full reg.exe export |
| Machine part unverified in a real run | 📄 stated in input | The machine round trip has not been run yet |
| R-97 and R-98 collide with existing records | 🤖 model inference | *(none - model judgment)* |
| Moving the installer keeps the change reversible | 🤖 model inference | *(none - model judgment)* |


---
**How to verify this document:**
`📄 stated in input` - the model's phrasing of something your source text said.
Find the matching line in the original to verify.
`🤖 model inference` - the model's own judgment or synthesis. Treat as opinion,
not measurement. Re-run on the same input and check whether specific numbers
stay consistent between runs.

*Session record. Developer track. Covers work done, not current code state.*