# Module 04: add `ScoobeSystemSettingEnabled` and `SubscribedContent-310093Enabled`; derive printed counts from the settings table

> Session record generated 2026-09-28

---

## Problem Being Solved

After an overnight shutdown, the audited machine shows the full-screen SCOOBE page ("Let's finish setting up your device") at sign-in. Event logs show no update install and no reset: Fast Startup (`HiberbootEnabled` = 1) turns the Start-menu power-off into a hybrid hibernate, and the page appears at the next sign-in. All ten settings module 04 manages read as applied. The toggle that governs the page is absent from the module's allow-list. Settings > System > Notifications > Additional settings exposes three toggles, and the module holds one of them (`SubscribedContent-338389Enabled`).

## Approach Taken

You add the two missing values to the observed tier (`$script:RcObserved` in `_Common.ps1`) with the same shape as the existing entries: `Kind = 'DWord'`, `Target = 0`, `Cite = $null`. Because `Restore-RcState` iterates the allow-list and `Get-RcState` records every allow-listed value, backup and restore cover the new entries with no further code. You replace the fixed count words in `Disable-Recommendations.ps1` and `Test-RoundTrip.ps1` with three script-scope counts (`$script:RcDocumentedCount`, `$script:RcObservedCount`, `$script:RcAllCount`) that `_Common.ps1` computes from the tables.

## Before

10 managed settings (five documented, five observed). `HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement` does not exist on the audited account, and `SubscribedContent-310093Enabled` is absent; both mean default-on. `Disable-Recommendations.ps1` prints "documented AND observed (10 settings)" and "Five further undocumented settings" as literals, and `Test-RoundTrip.ps1` prints "all 10 settings".

## After

12 managed settings (five documented, seven observed). The safety self-test passes 36 checks with 0 failures. The round trip with `-IncludeObserved` passes: the two new values move and return, including creation and removal of the `UserProfileEngagement` key. The change is applied on the audited machine with a verified backup, 12 of 12 set. The printed counts come from the tables. `README.md`, `HOWTO.md` and three `.cmd` header comments state twelve and seven.

## Known Alternatives

Setting the value once with `reg add` outside the module. Not taken: a one-off write has no backup, no undo and no round-trip proof, and the module standard requires all three. Adding Fast Startup (`HiberbootEnabled`) to this module. Not taken: the value lives under `HKLM`, needs elevation, and module 04 is per-user by design so that no launcher asks for administrator rights.

## Files Changed

| File | Change | What Changed | Why |
|------|--------|--------------|-----|
| `modules/04-recommendations/_Common.ps1` | modified | Two entries appended to `$script:RcObserved`; tier description updated; `RcDocumentedCount`, `RcObservedCount`, `RcAllCount` added after `Get-RcAllSettings`. | The allow-list is the single source of truth for apply, backup and restore. |
| `modules/04-recommendations/Disable-Recommendations.ps1` | modified | Scope line and `-WhatIf` hint use the derived counts; help text says seven observed and twelve total. | The literal counts go stale on every addition. |
| `modules/04-recommendations/Test-RoundTrip.ps1` | modified | Scope line uses the derived counts; help text says twelve. | Same reason. |
| `modules/04-recommendations/3 - Apply the changes.cmd` | modified | Header comment says the observed group has seven settings. | Keeps the launcher comment accurate. |
| `modules/04-recommendations/4 - Apply the undocumented ones too.cmd` | modified | Header comment says twelve and seven. | Keeps the launcher comment accurate. |
| `modules/04-recommendations/7 - Prove the undo works.cmd` | modified | Header comment says twelve. | Keeps the launcher comment accurate. |
| `modules/04-recommendations/README.md` | modified | New section on the two missed settings, round-trip row for 12 settings, applied status. | Dual-track documentation of the change and its limits. |
| `modules/04-recommendations/HOWTO.md` | modified | Counts updated; both settings added to the observed table. | The HOWTO lists every setting the module manages. |
| `modules/04-recommendations/narrative.txt` | added | Session narrative for `dual_track.py`. | Records the reasoning behind the change. |
| `modules/04-recommendations/.gitignore` | added | Ignores `*.prep.json`, `*.filled.json`, `PAYLOAD.*`, `PRECHECK.json`. | `dual_track.py` working files are local only, as in module 06. |
| `README.md` | modified | Module 04 paragraph mentions the two added settings and says seven undocumented. | The top-level summary quoted the old counts. |

## Decisions Made

- 📄 **Put both values in the observed tier, behind `-IncludeObserved`.** - Neither value appears in the offline Microsoft corpus; the project rule is that a claim is quoted or labelled.
- 📄 **Keep Fast Startup out of module 04.** - "Fast Startup is a machine-wide setting that needs administrator rights, and this module is deliberately per-user".
- 📄 **Derive printed counts from the tables instead of updating the words.** - "adding a setting can never again leave a message saying 'ten' when there are twelve".
- 🤖 **Accept that pre-change backups do not restore the new values.** - Older backups never recorded them; `Restore-RcState` already reports such entries as skipped and does not guess a prior state.

## Tried and Abandoned

- **Scripted text replacement over `README.md` and `HOWTO.md` with LF-only search strings.** - The working-tree copies use CRLF while the index is LF, so no match. The edits are redone with line-ending-agnostic matching, and the touched files are normalised to LF to match the index.

## ⚠ Claimed But Not Verified

*Prior documents claimed these are done. No test evidence found in this diff:*

- That `ScoobeSystemSettingEnabled` = 0 suppresses the SCOOBE page on future sign-ins. The value is written and read back, but the page has not been observed staying away over time.
- That the Settings page toggles map one-to-one onto these two values. This comes from observation, not from Microsoft documentation.

## Open Items

| Item | Priority | Blocks |
|------|----------|--------|
| Confirm over several sign-ins and one cumulative update that the SCOOBE page does not return. | medium | nothing currently |
| Decide whether Fast Startup belongs in a separate elevated module. | low | nothing currently |
| Adversarial audit of module 04 including the two new entries. | low | nothing currently |

## How to verify this work is correct

**Step 1:**
```bash
`powershell -ExecutionPolicy Bypass -File .\Test-SafetyLogic.ps1`
```
  - **Pass:** `checks passed : 36`, `checks failed : 0`
  - **Fail:** Any failed check, or a PowerShell parse error from `_Common.ps1`.

**Step 2:**
```bash
`powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1 -IncludeObserved -Force`
```
  - **Pass:** `scope: all 12 settings` and `PASS - every setting came back to exactly where it started.`
  - **Fail:** `FAIL` with a list of settings whose value or key existence differs.

**Step 3:**
```bash
`powershell -ExecutionPolicy Bypass -File .\Disable-Recommendations.ps1 -IncludeObserved -WhatIf`
```
  - **Pass:** `scope: documented AND observed (12 settings)`, both new names listed with `[uncited]`.
  - **Fail:** `10 settings`, or the new names missing.

**Step 4:**
```bash
`reg query HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement /v ScoobeSystemSettingEnabled` after an apply.
```
  - **Pass:** `REG_DWORD 0x0`
  - **Fail:** `ERROR: The system was unable to find the specified registry key or value.`


## Technical Debt

🟡 **LOW** - Neither new value has a vendor citation. → Re-query the corpus after its next refresh and promote either value to the documented tier only if Microsoft documents it.
🟡 **LOW** - Working-tree files drift to CRLF while the index is LF. → Add a `.gitattributes` with explicit `eol` rules so checkouts on every machine match the index.

## Claim Sources

| Claim | Basis | Evidence |
|-------|-------|----------|
| No update or reset caused the page | 📄 stated in input | No update was installed and nothing was reset. |
| Absent values mean default-on | 📄 stated in input | The registry key did not exist at all, which means the page is on. |
| Round trip covers the new key creation and removal | 📄 stated in input | including the UserProfileEngagement registry key, which the apply creates and the undo removes again |
| Restore needs no code change for new entries | 🤖 model inference | *(none - model judgment)* |
| Suppression of the page over time is unverified | 🤖 model inference | *(none - model judgment)* |
| Pre-change backups leave the new values untouched | 📄 stated in input | The undo reports them as "not in this backup" and leaves them as they are. |


---
**How to verify this document:**
`📄 stated in input` - the model's phrasing of something your source text said.
Find the matching line in the original to verify.
`🤖 model inference` - the model's own judgment or synthesis. Treat as opinion,
not measurement. Re-run on the same input and check whether specific numbers
stay consistent between runs.

*Session record. Developer track. Covers work done, not current code state.*