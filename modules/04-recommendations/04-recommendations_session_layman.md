# Stopping the "Let's finish setting up your device" page from coming back - Plain Language

> Session record generated 2026-09-28

---

## What happened

You shut your laptop down at night, and in the morning Windows greets you with a full-screen page saying "Let's finish setting up your device". It looks as if something went wrong overnight, or as if Windows reset itself. Nothing went wrong. The page is an advertisement. It offers you a Microsoft account, OneDrive backup, Microsoft 365 and Phone Link, and Windows shows it again every so often until you switch it off.

The Windows event logs on the laptop where this happened show no update and no reset. The reason the page appears after a shutdown is Fast Startup, which Windows turns on by default. With Fast Startup on, "Shut down" does not fully power off. Windows signs you out and puts the core of the system into hibernation, a saved sleep state on the disk. In the morning the laptop wakes from that state, you sign in, and Windows shows the page.

This module already switches off ten settings that show you suggestions, tips and adverts. All ten were off on that laptop. The switch that controls this page was never in the module, and neither was the switch for its neighbour, the "welcome" page Windows shows after updates. This session adds both switches, so the module now covers 12 settings.

## Honest state of play

Done: both new switches are in the module, the scripts count settings correctly, and the `README.md` and `HOWTO.md` describe both new switches in plain words. Tested: the safety test passes 36 checks with 0 failures, and the undo test passes for all 12 settings. Applied: the change is in use on the laptop where the problem appeared, with 12 of 12 settings set and a backup written first. Not done: Fast Startup is untouched, because it needs administrator rights and this module never asks for them. Not documented by Microsoft: neither new switch appears in Microsoft's own documentation, so the module labels both as uncited.

## Worst case if something is wrong

If one of the two new switches does not do what its name says, the page still appears, and you see exactly what you saw before this change. Neither switch can stop Windows from starting or remove any program. The other worst case is an undo gap: if you undo from a backup made before this change, the two new switches stay off, because that older backup never recorded them. You would then still not see the setup page or the welcome page, and you switch them back on from Settings > System > Notifications > Additional settings.

## What changed for you

**The "Let's finish setting up your device" page**
- Before: The module did not know about this switch. The page stayed on and could appear at any sign-in.
- After:  Button `4 - Apply the undocumented ones too` switches it off, and `5 - UNDO everything` switches it back on.
- Affects: everyone who uses button 4

**The Windows welcome page after updates**
- Before: The module did not know about this switch. The page stayed on.
- After:  Button `4 - Apply the undocumented ones too` switches it off as well.
- Affects: everyone who uses button 4

**The counts the module prints on screen**
- Before: The messages had the numbers typed in as words, such as "five" and "ten", so they were wrong as soon as a setting was added.
- After:  The module counts its own list of settings, so the numbers on screen always match what it actually does.
- Affects: everyone

## What you can do now

- Stop the "Let's finish setting up your device" page from appearing, by double-clicking `4 - Apply the undocumented ones too`.
- Stop the Windows welcome page after updates, with the same button.
- Put both pages back with `5 - UNDO everything`, which restores exactly what you had before.
- See the state of all 12 settings, without changing anything, with `1 - Check what is on now`.

## What is still missing

- **Turning off Fast Startup** - "Shut down" still hibernates the core of Windows instead of fully powering off. To change that yourself, open Control Panel > Power Options > "Choose what the power buttons do" and untick "Turn on fast startup". That page asks for administrator rights.
- **A Microsoft source for the two new switches** - Nobody can point you to a Microsoft page that confirms what the two switches do. Their meaning comes from the labels on the Windows Settings page and from watching what they change. They are kept behind button 4 for that reason.
- **Undo from older backups** - An undo from a backup made before this change leaves the two new switches as they are. Every backup made from now on covers all 12 settings.

## How to check that the new switches work on your computer

**Step 1:**
```bash
Double-click `1 - Check what is on now` in the `modules\04-recommendations` folder.
```
  - **Pass:** The list shows 12 settings, and `ScoobeSystemSettingEnabled` and `SubscribedContent-310093Enabled` are both in it.

**Step 2:**
```bash
Double-click `7 - Prove the undo works`, and type YES when it asks.
```
  - **Pass:** The window ends with PASS and says the net effect on your account is nothing.

**Step 3:**
```bash
Double-click `4 - Apply the undocumented ones too`.
```
  - **Pass:** The window says "backup written and verified" and ends with "failed: 0".

**Step 4:**
```bash
Open Settings > System > Notifications, scroll to the bottom, and open Additional settings.
```
  - **Pass:** All three ticks are off: the welcome experience, the "finish setting up" suggestion, and tips and suggestions.


## Should you be concerned?

No, as long as you understand one limit. The change only touches settings that belong to your own Windows account, it never asks for administrator rights, and it writes a checked backup before it changes anything. The undo test passes for all 12 settings. The limit is that Microsoft does not document the two new switches, so their effect is observed, not promised. If a future Windows update renames them, the page can come back. You would see it again, and you would not lose anything.

## Glossary

**Fast Startup** - A Windows feature, on by default, that saves the core of the system to disk at shutdown so the next start is quicker.

**Hibernation** - A power state in which Windows saves what is in memory to the disk and switches off, then restores it when you start the computer.

**SCOOBE** - Microsoft's internal name for the "finish setting up your device" page, short for Second-chance Out-Of-Box Experience.

**Registry** - The database where Windows stores its settings, including the switches this module changes.

**Uncited** - A label this project puts on any setting that Microsoft does not describe in its own documentation.

**Round trip** - A test that applies every change, undoes it, and checks that each setting returns exactly to where it started.

## Claim Sources

| Claim | Basis | Evidence |
|-------|-------|----------|
| Nothing went wrong with the laptop overnight | 📄 stated in input | No update was installed and nothing was reset. |
| Fast Startup explains why the page appears after shutdown | 📄 stated in input | Fast Startup is on by default, so Windows signs you out and hibernates the system kernel instead. |
| The page is advertising | 📄 stated in input | It is advertising: it offers a Microsoft account, OneDrive backup, Microsoft 365 and Phone Link |
| A missing setting means the page is on | 📄 stated in input | The registry key did not exist at all, which means the page is on. |
| The undo works for all 12 settings | 📄 stated in input | The round-trip proof applied all twelve settings for real, undid them, and compared every one: PASS. |
| The worst case is the page reappearing, not damage to the machine | 🤖 model inference | *(none - model judgment)* |
| A future Windows update could rename the switches and bring the page back | 🤖 model inference | *(none - model judgment)* |
| No need for concern for per-user changes with a checked backup | 🤖 model inference | *(none - model judgment)* |


---
**How to verify this document:**
`📄 stated in input` - the model's phrasing of something your source text said.
Find the matching line in the original to verify.
`🤖 model inference` - the model's own judgment or synthesis. Treat as opinion,
not measurement. Re-run on the same input and check whether specific numbers
stay consistent between runs.

*Session record. Plain-language track. Its developer twin covers the same session in technical detail.*