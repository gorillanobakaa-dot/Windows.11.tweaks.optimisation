# Module 07 — hold feature updates back

*Stop Windows installing the big twice-yearly feature releases for 3, 6 or 12
months. Keep every security patch. Let somebody else find the bugs first.*

---

## Just want to click something?

| # | Launcher | Admin? |
|---|---|---|
| 1 | Check what is on now | no |
| 2 | Preview the 3-month hold (safe) | no |
| 3 | HOLD feature updates 3 months | **yes** |
| 4 | HOLD feature updates 6 months | **yes** |
| 5 | HOLD feature updates 12 months | **yes** |
| 6 | UNDO everything | **yes** |
| 7 | UNDO back to the original | **yes** |
| 8 | Prove the undo works | **yes** |
| 9 | Test the safety logic | no |

Full walkthrough with every option and troubleshooting: [`HOWTO.md`](HOWTO.md).

---

## Read this before you use it

### This is Windows 11 Home, and Microsoft does not document these policies for Home

Every deferral and pinning policy this module writes is documented as a feature
of a service *"available for the following editions of Windows 10 and Windows
11"* [R-123] — and the list is Pro, Education and Enterprise [R-134][R-135][R-136].
**Home is not on it.** Home is also not explicitly listed as *unsupported*.

So the module makes three claims and no more:

1. The documented values were **written**. Proved by read-back.
2. The pin names the release this machine is **actually running**. Proved by
   reading `DisplayVersion` live.
3. Whether the Home update client **obeys** them is **not established** by
   either of the above.

Every script says so on every run. A module that quietly implied Home support
would be making exactly the claim the documentation does not support.

**The observable that settles it is time.** If the release line in check 1 still
reads the same number after the next feature release, the hold worked. If it has
moved, it did not. Every apply and undo records the release it saw, so the
history builds itself.

### Security updates are not touched. That is the whole design.

The brief was to avoid being an early adopter of *feature* releases — not to
stop being patched. Microsoft: *"Most organizations consider monthly security
update releases as mandatory."* [R-127] And the mechanisms are genuinely
separate: *"If you pause a feature update, quality updates are still offered to
devices to ensure they stay secure."* [R-133]

This module writes **no** quality-update value. The self-test asserts that, for
all three hold lengths.

### A hold is a delay, never a refusal

Home gets *"24 months of support for Home and Pro editions of Windows"*
[R-126], and past the end of that window Microsoft moves you anyway:

> *"the device will automatically be updated once it's 60 days past end of
> service for its edition."* [R-124]

Check 1 prints this every time. A hold whose ceiling the owner does not know
is a trap, not a setting.

---

## What it writes

Everything this module does lives in **one registry key**:

```
HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate
```

Five values under it:

| Value | Set to | In plain English |
|---|---|---|
| `TargetReleaseVersion` | `1` | release pinning: **ON** |
| `TargetReleaseVersionInfo` | **read from this machine** (e.g. `25H2`) | "stay on this release" — never hardcoded, see [Why not just a .reg file](#why-not-just-a-reg-file) |
| `ProductVersion` | `Windows 11` | the product the pin applies to |
| `DeferFeatureUpdates` | `1` | the older-style day-count deferral: **ON** — belt *and* braces |
| `DeferFeatureUpdatesPeriodInDays` | `90` / `180` / `365` | your 3 / 6 / 12 months, as a number of days |

After an apply, check 1 (`1 - Check what is on now`) reads these five back, shows
what the update client itself believes, and records your release — so "did Home
actually obey?" gets answered by the release history over time, not by hope.

### Why both a pin and a day count

They are not redundant, and Microsoft says they interact:

> *"When you specify target version policy, feature update deferrals won't be
> in effect."* [R-125]

So the **pin is the mechanism** and the day count is a fallback for the case
where the pin is not honoured. The day count is also flagged by Microsoft as
legacy: *"This policy is a legacy policy and isn't applicable for Windows 11."*
[R-121] It is written anyway, labelled `[LEGACY]` everywhere it appears, because
on an edition where neither is documented to work, writing only the one the
vendor calls legacy — or only the one the vendor calls current — would be
guessing which guess is right.

The day count's own semantics are documented plainly: *"if you set a feature
update deferral period of 365 days, the device won't install a feature update
that has been released for less than 365 days."* [R-122] 365 is the maximum
[R-120].

### A documentation trap worth knowing

Microsoft's prose spells the value **`DeferFeatureUpdatesPeriodinDays`** — lower
case `i` in `in`. The registry value is `DeferFeatureUpdatesPeriodInDays`, capital
`I`. Copying the sentence straight out of the documentation gives you a value
name Windows ignores silently. This module writes the capital-`I` form.

---

## Why not just a .reg file?

Back in the day this whole module would have been a `Hold-updates.reg` you
double-click, and regedit would merge the five values. It would even work —
once, on one machine, on the day it was written. This project refuses that
shortcut for four reasons, all of them scars rather than preferences:

**1. A `.reg` file cannot look before it writes.** It has no way to record
what the key held beforehand, so there is nothing to restore. Every module
here backs up first, and the undo must prove a restore actually changed
something. A `.reg` merge is a write with amnesia.

**2. One of the five values must be read from *your* machine at the moment of
writing.** `TargetReleaseVersionInfo` pins the release you are currently on.
A shipped `.reg` file freezes whatever release its author had — and this value
is not just a brake. Microsoft's guidance for it is to *"specify the version
that you want your devices to use"* [R-143] — and Microsoft names this same
value as the thing that *upgrades* managed machines: endpoints *"don't
automatically upgrade to Windows 11 unless an administrator explicitly
configures a Target Version"* [R-144]. Point it at a newer release and it is
an upgrade order, not a hold. Point it at an older or invalid one — say,
a `.reg` file written a year ago — and *"the device won't receive any feature
updates until the policy is updated"* [R-142]: silent update starvation, with
no expiry and no error, which is *more* broken than what anyone intended. The
same five characters hold one machine, move a second, and starve a third.
Only something that reads the machine first can write this value safely.

**3. regedit cannot refuse, and cannot prove.** No elevation check with a
clean exit code, no validation of what is already there, no "nothing to do",
no read-back showing the write landed. A merge reports success and shows you
nothing. Every apply here exits with a code its caller gates on, and check 1
reads the values back independently.

**4. The classic companion `undo.reg` is a trap.** The old pattern starts
with `[-HKEY_LOCAL_MACHINE\...\WindowsUpdate]` — delete the whole key. That
key is shared: anything else that ever set a Windows Update policy loses its
values along with ours. This project has already deleted a stranger's data
once by treating a shared container as its own (lesson L5 in
`LESSONS-LEARNED.md`), so the undo here restores only the values it recorded
and removes only what the apply created.

The registry writes themselves are exactly what a `.reg` file would do.
Everything around them — look first, back up, refuse when wrong, prove by
read-back, undo precisely — is the part the `.reg` file never had.

---

## What it deliberately does not do

- **Touch quality (security) updates.** No `DeferQualityUpdates*`, no quality
  pause. Asserted by the self-test.
- **Use the pause mechanism.** A pause lasts *"up to 35 days from when the value
  is set"* [R-130] and then silently stops protecting anything. Using an
  expiring mechanism for a 3–12 month hold would be a setting that lies.
- **Touch `NoAutoUpdate` or `AUOptions`.** Turning automatic updating off
  altogether is a different and worse decision.
- **Touch `wuauserv`, `UsoSvc`, `BITS` or `DoSvc`.** All never-touch in module 06.
- **Bypass a safeguard hold.** It reads the state and reports it. Microsoft
  applies these to stop known-bad combinations reaching your hardware, and
  working around one is how you get the update that breaks your machine.

---

## Safeguard holds — what Microsoft is doing to you

Separate from anything you set, Microsoft can hold *your* machine back. It is
edition-agnostic and locally readable [R-128]:

```
HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Appraiser\GWX
    GStatus = 2   no hold in effect       [R-129]
    GStatus = 0   a hold IS in effect
```

Check 1 reads and reports it. On this machine at the time of writing: **GStatus
= 2, no hold**.

---

## Policy set by registry still counts as managed — with a caveat

Microsoft is explicit that writing these keys directly makes the device managed,
and equally explicit about the risk:

> *"we don't recommended doing this action because registry keys can be easily
> overwritten."* [R-132]

That is a real risk here and it is not hypothetical: this project has already
watched Windows re-enable a disabled service and re-enable Defender real-time
protection against a recorded decision. **Re-run check 1 after any feature
update to confirm the values are still there.**

The visible symptom of "managed": Windows Update in Settings may now say
**"Some settings are managed by your organization."** That is you — you are
the organization. Launcher `7 - UNDO back to the original` removes every
value this module wrote, and the banner with it.

---

## What has actually been proved

| | |
|---|---|
| Self-test checks | **67**, 0 failures |
| Round trip executed on this machine | see below |
| Applied to this machine | **NO — not yet applied.** Which hold, if any, is the owner's call |
| Citations verified at the cited line | every row in the table below |

The self-test found a real defect in this module's own code before it shipped:
`Test-UdfStateShape` **threw** on an object with no properties instead of
returning false — a shape check that crashed on the most malformed input it
would ever see. Fixed, and the check that caught it is check 7.

---

## References

Every quotation carries a tag, the file, the line it starts on, and the
sentence. Check them yourself:

```bash
python ..\..\READ-ONLY-verification\Build-ReferenceLibrary.py
```

| ID | Claim | rel_path | line | quote |
|---|---|---|---|---|
| R-120 | Feature updates can be deferred up to 365 days | windows-itpro-docs/deployment/update/waas-configure-wufb.md | 99 | You can defer receiving these feature updates for a period of up to 365 days from their release |
| R-121 | The day-count feature deferral GPO is legacy and flagged as not applicable to Windows 11 | windows-itpro-docs/deployment/update/waas-configure-wufb.md | 107 | This policy is a legacy policy and isn't applicable for Windows 11. |
| R-122 | Deferral semantics - the device will not install a release younger than the deferral | windows-itpro-docs/deployment/update/waas-manage-updates-wufb.md | 115 | if you set a feature update deferral period of 365 days, the device won't install a feature update that has been released for less than 365 days. |
| R-123 | The whole policy family is scoped to a list of editions | windows-itpro-docs/deployment/update/waas-manage-updates-wufb.md | 55 | Windows Update client policies are a free service that is available for the following editions of Windows 10 and Windows 11: |
| R-124 | The documented ceiling - Windows updates the machine anyway 60 days past end of service | windows-itpro-docs/deployment/update/waas-wufb-group-policy.md | 152 | the device will automatically be updated once it's 60 days past end of service for its edition. |
| R-125 | A target-version pin overrides the day-count deferrals | windows-itpro-docs/deployment/update/waas-wufb-group-policy.md | 154 | When you specify target version policy, feature update deferrals won't be in effect. |
| R-126 | Home gets 24 months of support per feature update | windows-itpro-docs/deployment/update/release-cycle.md | 159 | 24 months of support for Home and Pro editions of Windows |
| R-127 | Monthly security updates are treated as mandatory - which is why this module never defers them | windows-itpro-docs/deployment/update/release-cycle.md | 80 | Most organizations consider monthly security update releases as mandatory. |
| R-128 | Safeguard hold state is locally readable | windows-itpro-docs/deployment/update/safeguard-holds.md | 88 | The GStatus value can be found in the following registry key |
| R-129 | GStatus 2 means no safeguard hold | windows-itpro-docs/deployment/update/safeguard-holds.md | 90 | A safeguard hold isn't in effect |
| R-130 | The pause mechanism expires after 35 days, which is why this module does not use it | windows-itpro-docs/deployment/update/waas-configure-wufb.md | 118 | You can also pause a device from receiving feature updates by a period of up to 35 days from when the value is set. |
| R-131 | The update client's own status values are the ground truth after a pause | windows-itpro-docs/deployment/update/waas-configure-wufb.md | 139 | check the status registry key |
| R-132 | Microsoft discourages setting these by direct registry write because they are easily overwritten | windows-itpro-docs/deployment/update/update-managed-unmanaged-devices.md | 60 | we don't recommended doing this action because registry keys can be easily overwritten. |
| R-133 | Holding feature updates still lets security updates through | windows-itpro-docs/deployment/update/waas-manage-updates-wufb.md | 125 | If you pause a feature update, quality updates are still offered to devices to ensure they stay secure. |
| R-134 | Supported edition 1 - Pro. Home is absent from this list | windows-itpro-docs/deployment/update/waas-manage-updates-wufb.md | 57 | - Pro, including Pro for Workstations |
| R-135 | Supported edition 2 - Education | windows-itpro-docs/deployment/update/waas-manage-updates-wufb.md | 58 | - Education |
| R-136 | Supported edition 3 - Enterprise | windows-itpro-docs/deployment/update/waas-manage-updates-wufb.md | 59 | - Enterprise, including Enterprise LTSC, IoT Enterprise, and IoT Enterprise LTSC |
| R-142 | A target release that is older than the installed one, or invalid, silently stops all feature updates until the policy is fixed - the stale-.reg-file failure mode | windows-itpro-docs/deployment/update/waas-wufb-group-policy.md | 154 | the device won't receive any feature updates until the policy is updated |
| R-143 | The same target-version policy is the documented way to MOVE devices to a chosen version, so a hardcoded value can be an upgrade order rather than a hold | windows-itpro-docs/deployment/update/waas-wufb-group-policy.md | 152 | specify the version that you want your devices to use |
| R-144 | Microsoft names TargetReleaseVersion as the thing that upgrades managed machines - even across products, 10 to 11 | windows-itpro-docs/whats-new/windows-11-prepare.md | 92 | don't automatically upgrade to Windows 11 unless an administrator explicitly configures a **Target Version** |
