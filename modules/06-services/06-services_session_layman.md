# Restoring Lenovo Business Laptop Hardware Buttons (Opt-in Bloat Removal) — Plain Language

> Session record generated 2026-08-30

---

## What happened

We discovered that applying the standard optimization profiles completely lobotomized the hardware capabilities of expensive business-oriented laptops (specifically Lenovo ThinkPads). By aggressively disabling services categorized as 'OEM Bloat', we inadvertently broke the hardware buttons for Microphone Mute, Airplane Mode, Phone Answer/Hang-up, and Brightness sliders. We have now fixed this by removing these services from the automatic kill-lists and making them strictly opt-in.

## Honest state of play

The standard profiles have been updated to skip Lenovo and brightness services. A new script (Disable-LenovoServices.ps1) has been created to allow users to manually disable these services if they wish.

## Worst case if something is wrong

If the new script fails or users run it without understanding the warnings, they will still lose access to their hardware buttons.

## What changed for you

**Lenovo OEM Services**
- Before: Automatically disabled by 'light' and 'super' optimization profiles.
- After:  No longer disabled automatically. Must be manually selected via a new opt-in script.
- Affects: everyone

## What you can do now

- Run the standard optimization profiles on Lenovo laptops without breaking the Fn keys, brightness slider, or special hardware buttons.
- Manually disable Lenovo OEM bloat services using `Disable-LenovoServices.ps1` if you strictly want to reduce background noise.

## What is still missing

- **Re-enabling services on already affected laptops automatically.** — Users who already ran the old profiles will need to manually run `Restore-LenovoHotkeys.ps1` to get their buttons back.

## How to verify your hardware buttons still work after applying the profile

**Step 1:**
```bash
Run the standard Apply-ServiceProfile.ps1 script.
```
  - **Pass:** The script finishes without errors.

**Step 2:**
```bash
Press your physical Microphone Mute, Airplane Mode, and Brightness buttons.
```
  - **Pass:** The buttons work as expected and trigger the appropriate actions in Windows.


## Should you be concerned?

No, this change reduces risk. It ensures that standard optimization profiles do not break critical hardware functionality on business laptops.

## Glossary

**OEM Bloat** — Software pre-installed by the manufacturer that runs in the background, often providing specialized hardware integration but consuming resources.

## Claim Sources

| Claim | Basis | Evidence |
|-------|-------|----------|
| Lenovo hardware physically relies on OEM background services. | 📄 stated in input | Lenovo hardware physically relies on these privileged background services to intercept and translate special hardware buttons |


---
**How to verify this document:**
`📄 stated in input` — the model's phrasing of something your source text said.
Find the matching line in the original to verify.
`🤖 model inference` — the model's own judgment or synthesis. Treat as opinion,
not measurement. Re-run on the same input and check whether specific numbers
stay consistent between runs.

*Session record. Plain-language track. Its developer twin covers the same session in technical detail.*