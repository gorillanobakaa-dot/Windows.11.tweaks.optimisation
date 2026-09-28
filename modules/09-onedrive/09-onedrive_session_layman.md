# Clearing out OneDrive for good, and stopping it from coming back - Plain Language

> Session record generated 2026-09-28

---

## What happened

You uninstall OneDrive from Settings and expect it to be gone. The program is gone. Much of what came with it is not. On the laptop this work was done on, OneDrive had been uninstalled months earlier, and a check found Windows' own 86 MB OneDrive installer still sitting in the Windows folder, no rule telling Windows that OneDrive is unwanted, and an entry that installs OneDrive for every new account the first time it signs in.

The account itself still held leftovers too. Two environment variables pointed at a OneDrive folder in an old account's user folder. An environment variable is a small named setting that Windows hands to every program you start, so every program on the laptop was being told that old folder name. OneDrive's own settings had recorded the account name and the computer name. A link handler, the setting that tells Windows which program opens a kind of link, still pointed at the deleted OneDrive program. Two leftover folders remained.

This session adds module 09 to the tweaks. It removes the leftovers and blocks the way back. It works in two parts, because Windows separates your own account from the machine as a whole: your account's part needs no administrator rights, and the machine part does.

## Honest state of play

Done and in use: your account's part ran on the laptop this was built on, and removed seven items with zero failures. The check afterwards shows every account item as gone. Tested: the safety test passes 43 checks, and the undo test for your account passes. Built but not yet run: the machine part, because it needs administrator rights, which this work did not have. Until you run button 4, the check shows three ways back still open (the two rules and the installer) and one leftover (an empty setup folder). The undo test for the machine part has not run yet either, for the same reason. No independent review of this module has happened yet.

## Worst case if something is wrong

If the machine block does not hold, OneDrive can come back, for example after a large Windows update puts the installer back. You would see OneDrive again, and nothing else would break. If the undo failed, you would be left without OneDrive's leftovers, which is the state you asked for. Folders sit in the Recycle Bin, so emptying the Recycle Bin is the one step that makes a removal permanent, and that step is yours.

## What changed for you

**Leftovers in your account**
- Before: Two environment variables, three registry keys and two folders from OneDrive stayed behind after the uninstall.
- After:  Button `3 - Remove my account's leftovers` removes all seven. On the laptop this was built on, all seven are gone.
- Affects: everyone who uses button 3

**OneDrive coming back**
- Before: Nothing stopped OneDrive from being reinstalled or used again, and Windows kept the installer that puts it back.
- After:  Button `4 - BLOCK OneDrive on this machine` sets the two rules Microsoft documents for turning OneDrive off, moves the installer into a backup, and removes the new-account entry.
- Affects: every account on the computer, once button 4 runs

**Seeing what is left**
- Before: You had no single place to check what OneDrive left behind.
- After:  Button `1 - Check what is on now` lists every trace, and ends with how many ways back are still open and how many leftovers remain.
- Affects: everyone

## What you can do now

- Remove every OneDrive leftover from your account with button `3 - Remove my account's leftovers`, without administrator rights.
- Block OneDrive from coming back, for every account on the computer, with button `4 - BLOCK OneDrive on this machine`.
- See every trace of OneDrive in one list with button `1 - Check what is on now`.
- Put everything back with buttons `7 - UNDO my account` and `8 - UNDO the machine block`. Undoing does not reinstall OneDrive.

## What is still missing

- **The machine block on the laptop this was built on** - OneDrive can still be reinstalled there until you run button 4 with administrator rights.
- **The undo test for the machine part** - Nobody has yet shown on a real machine that button 8 puts the machine part back exactly. Run button 6 before button 4 to show it.
- **A Microsoft source for the extra steps** - Microsoft documents the two rules. It does not document removing the installer, the new-account entry or the leftovers. Those steps come from what the check found on this laptop, and the module labels them uncited.
- **Leftovers in other accounts** - Button 3 cleans the account that runs it. The machine rules from button 4 cover every account, but leftovers inside other accounts stay until each account runs button 3.

## How to check that OneDrive is gone and blocked

**Step 1:**
```bash
Double-click `9 - Test the safety logic` in the `modules\09-onedrive` folder.
```
  - **Pass:** The window ends with `checks passed : 43` and `checks failed : 0`.

**Step 2:**
```bash
Double-click `6 - Prove the machine undo works`, allow the administrator prompt, and type YES.
```
  - **Pass:** The window ends with PASS and says the net effect is nothing.

**Step 3:**
```bash
Double-click `4 - BLOCK OneDrive on this machine` and allow the administrator prompt.
```
  - **Pass:** The window says "backup written and verified" and ends with "failed: 0".

**Step 4:**
```bash
Double-click `1 - Check what is on now`.
```
  - **Pass:** The last lines read `ways back still open : 0` and `leftovers remaining  : 0`.


## Should you be concerned?

No, with two limits you should know. First, nothing here deletes anything for good: registry settings are saved to a file before removal, folders go to the Recycle Bin, and the installer moves into a backup folder. Second, a large Windows update can put the installer back. The two Microsoft rules normally survive updates, but check with button 1 after each large update and run button 4 again if the installer is back. One more point: the backup folder can hold account and computer names that OneDrive recorded, so keep it private and never share or upload it.

## Glossary

**Environment variable** - A small named setting that Windows hands to every program you start.

**Registry** - The database where Windows and programs store their settings.

**Policy** - A rule in the registry that tells Windows how to behave, which settings pages cannot override.

**Default-user hive** - The template of settings that Windows copies into every new account.

**Link handler** - The setting that tells Windows which program opens a particular kind of link.

**Round trip** - A test that makes each change, undoes it, and checks that everything returns exactly to where it started.

**Administrator rights** - Permission to change things that affect the whole computer, which Windows asks you to confirm.

## Claim Sources

| Claim | Basis | Evidence |
|-------|-------|----------|
| OneDrive was uninstalled by its owner | 📄 stated in input | Windows recorded that in its own OneDrive settings as "UserInitiatedUninstall = 1" |
| The installer is what puts OneDrive back | 📄 stated in input | It is the file that puts OneDrive back. |
| Every program was told the old folder name | 📄 stated in input | Windows hands environment variables to every program you start, so every program was told that old folder name. |
| The account part worked on the real machine | 📄 stated in input | seven items removed, zero failures |
| The self-test can detect broken safety code | 📄 stated in input | we broke the value check and the key guards on purpose: 8 checks failed |
| Only the two policies are documented by Microsoft | 📄 stated in input | Only the two policies are documented by Microsoft. |
| A large Windows update can put the installer back | 🤖 model inference | *(none - model judgment)* |
| The two policies normally survive Windows updates | 🤖 model inference | *(none - model judgment)* |
| A failed block leaves nothing else broken | 🤖 model inference | *(none - model judgment)* |


---
**How to verify this document:**
`📄 stated in input` - the model's phrasing of something your source text said.
Find the matching line in the original to verify.
`🤖 model inference` - the model's own judgment or synthesis. Treat as opinion,
not measurement. Re-run on the same input and check whether specific numbers
stay consistent between runs.

*Session record. Plain-language track. Its developer twin covers the same session in technical detail.*