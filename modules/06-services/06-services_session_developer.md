# Profiles.json update: Remove OEM bloat kills to restore Lenovo ThinkPad hardware buttons

> Session record generated 2026-08-30

---

## Problem Being Solved

The standard service optimization profiles were disabling critical Lenovo background services (ImControllerService, DisplayEnhancementService), breaking hardware features like Microphone Mute, Airplane Mode, Phone buttons, and Brightness sliders.

## Approach Taken

Removed Lenovo/OEM services from the automated `profiles.json` kill-lists to prevent hardware lobotomy. Created a dedicated opt-in PowerShell script with explicit warnings for users who still want to disable these services manually.

## Before

OEM services (LvfInstallService, UDCService, LenovoVantageService, ImControllerService, LPlatSvc, LenovoSmartStandby, DisplayEnhancementService) were automatically disabled in the 'light' and 'super' tiers.

## After

These OEM services are no longer present in `profiles.json`. They are only disabled if a user explicitly runs the new interactive `Disable-LenovoServices.ps1` script.

## Known Alternatives

We could have created a new strict profile in `profiles.json` (e.g. 'lenovo-lobotomy'), but the Apply-ServiceProfile script tightly controls the profile ValidateSet to light/moderate/super. An external opt-in script was less invasive.

## Files Changed

| File | Change | What Changed | Why |
|------|--------|--------------|-----|
| `profiles.json` | modified | Removed all Lenovo and OEM bloat services from the 'light' and 'super' arrays. | To prevent the automated profiles from crippling hardware capabilities. |
| `Disable-LenovoServices.ps1` | added | Created a new interactive PowerShell script with GridView. | To give advanced users an explicit, warned opt-in path to disable these services. |
| `README.md` | modified | Appended explicit strong warnings about Lenovo business laptops and hardware buttons. | To document the hardware risks associated with disabling OEM services. |

## Decisions Made

- 📄 **Remove OEM services from automatic kill-lists rather than adding them to the 'never' list.** — Users may still want the option to strictly reduce their attack surface if they don't care about the hardware buttons.

## Verifying OEM Profile Changes

**Step 1:**
```bash
Run `Get-Content profiles.json | ConvertFrom-Json` and verify that `ImControllerService` is not in the `.profiles` lists.
```
  - **Pass:** The service is not returned.
  - **Fail:** The service is still listed in the 'light' or 'super' tiers.

**Step 2:**
```bash
Run `.\Disable-LenovoServices.ps1`
```
  - **Pass:** An Out-GridView window appears showing the available Lenovo services to disable.
  - **Fail:** The script errors out or fails to launch the GridView.


## Claim Sources

| Claim | Basis | Evidence |
|-------|-------|----------|
| Applying standard profiles lobotomizes hardware. | 📄 stated in input | applying the standard 06-services optimization profiles completely lobotomizes the hardware capabilities |


---
**How to verify this document:**
`📄 stated in input` — the model's phrasing of something your source text said.
Find the matching line in the original to verify.
`🤖 model inference` — the model's own judgment or synthesis. Treat as opinion,
not measurement. Re-run on the same input and check whether specific numbers
stay consistent between runs.

*Session record. Developer track. Covers work done, not current code state.*