# How to use the OneDrive module

*Removes what OneDrive leaves behind after it is uninstalled, and blocks it from
coming back. Your account's part needs no administrator rights; the machine
part does.*

---

## Before you start

### Uninstall OneDrive first

This module does not uninstall OneDrive. Do that from Settings > Apps >
Installed apps > Microsoft OneDrive > Uninstall. Then run `1 - Check what is on
now`: the first three lines should say "no".

### Nothing here deletes anything for good

- Registry keys are exported to `.reg` files before removal.
- Folders go to the Recycle Bin.
- The installer is moved into this module's `backups` folder.

If you empty the Recycle Bin, the folders are gone for good. That is your
decision, not this module's.

---

## The launchers at a glance

| # | Launcher | What it does | Admin? |
|---|---|---|---|
| 1 | Check what is on now | Every trace, labelled `gone`, `present`, `open` or `BLOCKED` | No |
| 2 | Preview the changes (safe) | Runs 3 and 4 in preview mode | No |
| 3 | Remove my account's leftovers | Environment variables, registry keys, folders | No |
| 4 | BLOCK OneDrive on this machine | Two policies, installer, new-account entry, setup folder | Yes |
| 5 | Prove the undo works | Account round trip (folders left alone) | No |
| 6 | Prove the machine undo works | Machine round trip (installer left alone) | Yes |
| 7 | UNDO my account | Reverses 3 | No |
| 8 | UNDO the machine block | Reverses 4 | Yes |
| 9 | Test the safety logic | 43 checks in a throwaway area | No |

### The careful order

1. **`1`**: see what is there.
2. **`9`**: prove the machinery on your machine.
3. **`5`**, then **`6`**: prove both undos while there is still something to move.
4. **`3`**, then **`4`**.
5. **`1`** again. The last lines should read `ways back still open : 0` and
   `leftovers remaining  : 0`.

---

## `Remove-OneDriveLeftovers.ps1`: every option

```bash
powershell -ExecutionPolicy Bypass -File .\Remove-OneDriveLeftovers.ps1 -WhatIf
powershell -ExecutionPolicy Bypass -File .\Remove-OneDriveLeftovers.ps1
powershell -ExecutionPolicy Bypass -File .\Remove-OneDriveLeftovers.ps1 -NoFolders -Tag test
```

| Parameter | Effect |
|---|---|
| `-WhatIf` | Lists every item and changes nothing |
| `-NoFolders` | Leaves the two folders alone (the round trip uses this) |
| `-Tag <text>` | Adds a label to the backup folder name |

Exit codes: `0` done or previewed, `3` backup refused (nothing changed), `4`
nothing to do, `5` finished with failures.

## `Block-OneDrive.ps1`: every option

```bash
powershell -ExecutionPolicy Bypass -File .\Block-OneDrive.ps1 -WhatIf
powershell -ExecutionPolicy Bypass -File .\Block-OneDrive.ps1
```

| Parameter | Effect |
|---|---|
| `-WhatIf` | Preview. Works **without** administrator rights |
| `-NoFiles` | Leaves the installer and the setup folder alone |
| `-Tag <text>` | Adds a label to the backup folder name |

Without administrator rights, and without `-WhatIf`, it refuses and exits `4`.
The new-account entry can only be read with administrator rights, so the preview
says so instead of guessing.

## `Restore-OneDrive.ps1`: every option

```bash
powershell -ExecutionPolicy Bypass -File .\Restore-OneDrive.ps1
powershell -ExecutionPolicy Bypass -File .\Restore-OneDrive.ps1 -Part Machine
powershell -ExecutionPolicy Bypass -File .\Restore-OneDrive.ps1 -List
powershell -ExecutionPolicy Bypass -File .\Restore-OneDrive.ps1 -Run run_2026-09-28_07-44-57_account
```

| Parameter | Effect |
|---|---|
| (none) | Undoes the newest **account** run |
| `-Part Machine` | Undoes the newest **machine** run (administrator rights) |
| `-List` | Lists backup runs, marking the undo's own snapshots |
| `-Run <folder>` | Restores from a specific run |
| `-WhatIf` | Says what would be restored and restores nothing |

## `Test-RoundTrip.ps1`

```bash
powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1 -Part Account
powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1 -Part Machine
```

Exit codes: `0` PASS, `1` FAIL, `2` INCONCLUSIVE (nothing was there to move),
`4` refused. INCONCLUSIVE after you have already run 3 or 4 is correct: a round
trip of zero distance proves nothing, and the test says so rather than
reporting a PASS.

---

## Troubleshooting

**"1 - Check" says `open` for the two policies after I ran 4.**
Open launcher 4 again and read the `applying:` lines. A `failed:` line names
the value that did not stick. Security software can block writes under
`HKLM\SOFTWARE\Policies`.

**The installer line says `present` after 4.**
The move failed. The `FAILED:` line in launcher 4's output gives the reason. The
most common one is that another program had the file open; restart and run 4
again.

**OneDrive is back after a big Windows update.**
Run `1`. If the installer is `present` again, the update replaced it. Run `4`
again. The two policies are set by name under `HKLM\SOFTWARE\Policies`, and
Windows updates normally leave policies in place.

**Programs still show the old OneDrive folder in their settings.**
Programs that were open when you ran 3 keep the old environment variables until
they are closed. Sign out and back in to be sure.

---

## What this module deliberately does not do

- **Uninstall OneDrive.** Use Settings for that.
- **Touch other accounts' leftovers.** Number 3 works on the account that runs
  it. The machine policies in number 4 apply to every account.
- **Delete anything outright.** Folders go to the Recycle Bin; the installer is
  moved into the backup.
- **Present the uncited items as documented.** Only the two policies carry a
  Microsoft citation.
