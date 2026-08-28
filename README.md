# Windows 11 Tweaks and Optimisation

> [!WARNING]
> **Status: v0.1.0-beta (Public Beta)**
> This is a highly developed framework. It works flawlessly on the author's machine, and it has been heavily audited against Microsoft's official documentation. However, it is now entering public beta for wide-scale hardware testing. This beta status gives us the freedom to introduce breaking changes (like rewriting a module) based on real-world feedback before we formally commit to a stable `1.0.0` release.

### The Gorilla Open Source Philosophy
This project does not ask for your blind trust. It is built on a strict "Dual-Track" documentation philosophy: every decision is explained in plain English for the layman, and backed up by rigorous technical proof for the developer.

Everything here was measured on one real laptop (Windows 11 Home, build 26200). Every claim is traceable either to Microsoft's own published documentation or to an artifact produced by a read-only script you can run yourself.

---

# START HERE

A measured, cited, reversible approach to reducing what a Windows 11 machine does without being asked — and to closing the parts of it that face the network.

### Download the Standalone Tool
If you do not want to download the entire source code repository, you can download the **Standalone ZIP** from the [Releases](https://github.com/gorillanobakaa-dot/Windows.11.tweaks.optimisation/releases) page. It contains only the execution scripts without the heavy documentation.

### Step 0 — unblock it first (one minute, and it will save you a headache)
Windows tags every file that came from the internet. Scripts in a tagged folder can throw security warnings or refuse to run, and the error it gives you will not mention the tag.

If you downloaded the Standalone ZIP: right-click the ZIP → Properties → tick Unblock at the bottom → OK → then extract it. Unblocking the ZIP first clears every file inside it in one go.

If you already extracted it, or you cloned with git, open PowerShell in this folder and run:
`Get-ChildItem -Recurse | Unblock-File`

### Step 1 — go to the only folder that does anything
```text
Windows.11.tweaks.optimisation\
└── modules\             <- open this
```

Everything else in this repository reads, verifies, or documents. Start with `01-visual-effects`. It has been through the adversarial audit, its rollback has been executed and verified on a real machine, and what it saves has been measured.

### Step 2 — look before you touch
Double-click `1 - Check what is on now.cmd`
It changes nothing. It cannot. Read it, press a key, the window closes.

### Step 3 — see exactly what would change
Double-click `2 - Preview the changes (safe).cmd`
It prints a line for every setting it would alter, with the value now and the value it would set — then makes none of the changes.

### Step 4 — apply it
Double-click `3 - Apply the changes.cmd`
It saves your current settings to a backup file first, checks the backup was actually written, and only then changes anything. If the backup fails it stops and changes nothing. 

### Changed your mind?
Double-click `4 - UNDO everything.cmd` — puts back what the last run changed.
Or `5 - UNDO back to the original.cmd` — goes all the way back to how the machine was before any of this, from that write-once file.

---

## The Modules

* **01-visual-effects**: Turns off animations, fades, window shadows and frosted-glass translucency.
* **02-update-distribution**: Stops the machine sharing Windows updates with other PCs.
* **03-copilot**: Removes Copilot completely.
* **04-recommendations**: Turns off suggested apps, Windows tips, and the Start menu's Recommended section.
* **05-xbox-services**: Disables Xbox background services.
* **06-services**: Safely applies service profiles.
* **07-update-deferral**: Defers feature updates.
* **08-app-debloat**: Removes pre-installed bloatware safely.

## Document History
| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-08-28 | Initial public release of module documentation and framework |
