# OneDrive: remove the leftovers, block the way back

## Just want to click something?

| Double-click this | What happens | Admin? |
|---|---|---|
| **1 - Check what is on now** | Shows every trace of OneDrive on this computer | No |
| **2 - Preview the changes (safe)** | Lists what 3 and 4 would change, then changes nothing | No |
| **3 - Remove my account's leftovers** | Clears what OneDrive left in your account | No |
| **4 - BLOCK OneDrive on this machine** | Stops OneDrive coming back, for every account | **Yes** |
| **5 - Prove the undo works** | Removes, undoes and compares, for your account | No |
| **6 - Prove the machine undo works** | The same, for the machine block. Run it before 4 | **Yes** |
| **7 - UNDO my account** | Puts back what 3 removed | No |
| **8 - UNDO the machine block** | Takes the block off again | **Yes** |
| **9 - Test the safety logic** | Tests the machinery that decides whether to write | No |

The usual order is **1**, **3**, **4**, then **1** again to see everything say "gone".

---

## What this is for

### In plain language

Uninstalling OneDrive from Settings removes the program. It does not remove the
means of putting it back, and it does not clean up after itself.

On the laptop this module was built on, OneDrive had been uninstalled by its
owner months earlier. This is what was still there:

- **Windows' own OneDrive installer**, an 86 MB file inside the Windows folder.
  It is what puts OneDrive back, for example when a new account is created.
- **No rule telling Windows that OneDrive is not wanted.** Nothing stopped it
  being installed or used again.
- **An entry that installs OneDrive for every new account** the first time that
  account signs in.
- **Two "environment variables"** in the account. An environment variable is a
  small named setting that Windows hands to every program you start. These two
  pointed at a OneDrive folder belonging to an old account, so every program on
  the machine was being told an old account's folder name.
- **OneDrive's own settings**, which had recorded the account name and the
  computer's name.
- **A link handler**: the setting that tells Windows which program opens a
  particular kind of link. This one pointed at the deleted OneDrive program.
- **Two leftover folders**: the old OneDrive folder, and what the uninstall left
  of the program.

This module removes the leftovers and blocks the way back. It works in two parts,
because Windows draws a line between your own account and the machine as a whole:

- **Your account** (number 3). No administrator rights. It removes the
  environment variables, OneDrive's settings, the link handler and the two
  folders.
- **The machine** (number 4). Administrator rights, because it changes things
  that apply to every account. It sets the two rules Microsoft itself documents
  for turning OneDrive off, moves the installer out of the Windows folder into
  this module's backup, and removes the new-account entry.

Nothing is thrown away for good. Registry settings are exported to a file before
they are removed. Folders go to the Recycle Bin. The installer is moved, not
deleted. Numbers 7 and 8 put everything back.

Undoing does not reinstall OneDrive. It puts back what this module changed.

### In technical terms

| Part | Item | Action | Source |
|---|---|---|---|
| Machine | `HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive\DisableFileSyncNGSC` | set to `1` (REG_DWORD) | documented [R-145] |
| Machine | `HKLM\SOFTWARE\Microsoft\OneDrive\PreventNetworkTrafficPreUserSignIn` | set to `1` (REG_DWORD) | documented [R-146] |
| Machine | `%SystemRoot%\System32\OneDriveSetup.exe` (and `SysWOW64` where present) | `takeown /a`, grant Administrators, move into `backups\run_*\files`, SHA-256 compared | uncited |
| Machine | Default-user hive `C:\Users\Default\NTUSER.DAT`, `Run\OneDriveSetup` and `Run\OneDrive` | hive loaded at `HKU\W11T_OdDefault`, values recorded then removed, hive always unloaded | uncited |
| Machine | `%ProgramData%\Microsoft OneDrive` | Recycle Bin | uncited |
| Account | `HKCU\Environment\OneDrive`, `OneDriveConsumer` | recorded in the state file, removed, `WM_SETTINGCHANGE` broadcast | uncited |
| Account | `HKCU\Software\Microsoft\OneDrive` | `reg export`, verified, then deleted | uncited |
| Account | `HKCU\Software\SyncEngines` | same, **only if no other sync provider** is registered under it | uncited |
| Account | `HKCU\Software\Classes\grvopen` | same, **only if its open command points at `OneDrive.exe`** | uncited |
| Account | `%USERPROFILE%\OneDrive`, `%LOCALAPPDATA%\Microsoft\OneDrive` | Recycle Bin | uncited |

**Why the uncited items are applied by default.** Module 04 puts its uncited
settings behind an opt-in switch, because each is a choice about a feature. The
uncited items here are leftovers of, and reinstall paths for, a program the
owner has already removed. Leaving them is not a neutral default. They stay
labelled `[uncited]` in every place they appear.

**Guards.** `SyncEngines` is a shared list: Dropbox and other sync programs can
register there too, so the key is kept if anything other than OneDrive is in it.
`grvopen` is kept unless it points at `OneDrive.exe`. The self-test checks both
guards against keys that should be kept.

**Backups.** Each run writes `backups\run_<stamp>_<part>[_tag]\` containing a
verified `state.json`, one `.reg` export per removed key, and for the machine
part a `files\` folder with the installer. A key is only removed after its export
has been written and checked to name that key. The undo takes a `_~prerestore`
snapshot first, which is never offered as a restore point (MODULE-STANDARD
R16.3). The restore iterates the module's own allow-list, never the backup's
contents, and refuses values of the wrong kind or shape.

**The backups folder is private.** The `.reg` exports record whatever OneDrive
stored, which can include account and computer names. The folder is excluded
from git on the machine it was built on and must never be published.

---

## Undoing it

- **Your account:** `7 - UNDO my account`. The environment variables and
  registry keys come back. It then lists the folders that went to the Recycle
  Bin; restore those from the Recycle Bin yourself (right-click, Restore).
- **The machine:** `8 - UNDO the machine block`, with administrator rights. The
  two policies are removed (or set back to what they were), the installer is
  moved back to where it came from, and the new-account entry is written back.

One limit: after the undo, the installer file is owned by Administrators rather
than by Windows' TrustedInstaller account. It works the same; a later Windows
update may replace it.

---

## What has actually been proved

| | Result |
|---|---|
| Safety logic self-test | **43 checks, 0 failures** |
| The self-test can fail | **verified**: with the value check and the key guards deliberately broken, 8 checks failed |
| Round trip, account part | **PASS**: two environment variables and three registry keys removed and returned, keys compared by their full exported contents |
| Round trip, machine part | **PASS for the two policies**, 2026-09-28. The new-account entry was **not tested**: see "Known limitation" below |
| Applied, account part | **yes**, on the audited machine, 2026-09-28: seven items removed, zero failures |
| Applied, machine part | **yes**, 2026-09-28: both policies set, installer moved into the backup, setup folder to the Recycle Bin; four changes, zero failures. The new-account entry was **not removed**: see below |
| Citations | **2 / 2** quoted from the offline corpus at the cited line |
| Adversarial audit | **not yet done** |

---

## Known limitation: the new-account entry

**In plain language.** Windows keeps a template that every new account is
copied from. On the machine this was built on, that template still contains an
entry that installs OneDrive the first time a new account signs in. The module
could not remove it, because Windows refused to open the template. The entry
is harmless there: the installer it points at has been moved out of the Windows
folder, and the two policies stop OneDrive being used anyway. `1 - Check what is
on now` shows it as **not checked**, with Windows' own reason, and does not
claim that everything is clear.

**Technically.** `reg load HKU\W11T_OdDefault C:\Users\Default\NTUSER.DAT`
fails elevated with `ERROR: The filename or extension is too long.` (exit 1).
A plain copy of `NTUSER.DAT`, `.LOG1` and `.LOG2` in `%TEMP%`, without the
`.TM.blf` / `.regtrans-ms` / `.cnpf` transaction files, fails identically, so
those files are ruled out. The cause is not known. The remaining entry is
`Run\OneDriveSetup` = `C:\Windows\System32\OneDriveSetup.exe /thfirstsetup`.
On a machine where the template loads, launcher 4 removes it with a backup, and
launcher 8 puts it back.

Until 2026-09-28 a failed load was reported only as "cannot be read", the check
left the item out of its totals and printed an all-clear, and the machine round
trip printed PASS without touching it. All three now say what they could not do.

---

## Sources

| ID | Claim | Microsoft page | line (offline copy) | quote |
|---|---|---|---|---|
| R-145 | Turning off OneDrive: prevent its use for file storage | [Manage connections from Windows 10 and Windows 11 Server/Enterprise editions operating system components to Microsoft services - Windows Privacy](https://learn.microsoft.com/en-us/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services) | 674 | Create a REG\_DWORD registry setting named **DisableFileSyncNGSC** in **HKEY\_LOCAL\_MACHINE\SOFTWARE\Policies\Microsoft\Windows\OneDrive** with a value of 1 (one). |
| R-146 | Turning off OneDrive: no network traffic before sign-in | [Manage connections from Windows 10 and Windows 11 Server/Enterprise editions operating system components to Microsoft services - Windows Privacy](https://learn.microsoft.com/en-us/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services) | 680 | Create a REG\_DWORD registry setting named **PreventNetworkTrafficPreUserSignIn** in **HKEY\_LOCAL\_MACHINE\SOFTWARE\Microsoft\OneDrive** with a **value of 1 (one)** |

**The uncited items have no entries here, deliberately.** Microsoft documents
the two policies above for turning OneDrive off. It does not document removing
its installer, the default-user Run entry, or the leftovers; those come from
observation of this machine.
