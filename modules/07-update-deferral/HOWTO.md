# How to hold feature updates back

*Three hold lengths, one pin, and a caveat this page will not let you skip.
Security patches keep arriving throughout.*

---

## Before you start

### The two kinds of Windows update, because this module only touches one

| | What it is | This module |
|---|---|---|
| **Quality updates** | The monthly security patches. Cumulative - the newest one contains all the earlier ones. | **never touched** |
| **Feature updates** | The big twice-yearly releases that change how Windows works - 24H2, 25H2. The ones that break things. | **held back** |

If you have ever had a Windows update rearrange your machine and lose you a
day, it was a feature update. That is the one this holds. The patches keep
coming.

### The caveat: this is Home, and Microsoft does not document these for Home

Every policy here is documented for **Pro, Education and Enterprise**. Home is
not on that list - and is not listed as unsupported either. So:

- The module **writes** the values and **proves** they were written.
- The module **does not claim** the Home update client obeys them.

Anyone telling you with confidence that these registry keys work on Home is
guessing. So would I be. **The only honest test is time**, and the module builds
the evidence for you: every apply and undo records the Windows release it saw,
so check 1 shows you a dated history. If the release has not moved after the
next feature release, it worked.

### A hold is a delay, not a refusal

Home gets **24 months** of support per feature update, and once you are **60
days past end of service** Microsoft updates the machine regardless. Check 1
prints this every time. Plan to move the pin forward deliberately.

---

## The launchers at a glance

| # | Launcher | Admin? | What it does |
|---|---|---|---|
| 1 | Check what is on now | no | Release, policy, client view, safeguard hold, history |
| 2 | Preview the 3-month hold (safe) | no | Every value that would change; changes none |
| 3 | HOLD feature updates 3 months | **yes** | 90 days + pin |
| 4 | HOLD feature updates 6 months | **yes** | 180 days + pin |
| 5 | HOLD feature updates 12 months | **yes** | 365 days + pin |
| 6 | UNDO everything | **yes** | Back to the newest backup |
| 7 | UNDO back to the original | **yes** | As if this was never run |
| 8 | Prove the undo works | **yes** | Apply, undo, compare - net zero on a pass |
| 9 | Test the safety logic | no | 70 checks on the machinery |

**The undo is 6, not 5.** 5 is the twelve-month hold.

---

## Recommended first session

1. **`1 - Check what is on now`** - read the release number. That is the number
   you are about to freeze.
2. **`9 - Test the safety logic`** - 70 checks, no admin needed, ten seconds.
3. **`8 - Prove the undo works`** - proves the round trip on *your* machine
   before you trust it.
4. **`2 - Preview`** - see the five values.
5. Then pick 3, 4 or 5.

---

## Which hold?

| | Days | Who it fits |
|---|---|---|
| **3 months** | 90 | You want the worst of the launch bugs found by other people, but you do not want to fall far behind. |
| **6 months** | 180 | The middle. Roughly one release cycle. |
| **12 months** | 365 | The documented maximum. You update on your schedule, once a year, deliberately. |

All three write the same five values - only the day count differs. All three
pin the release identically.

**12 months is not "safest".** It is the furthest from Microsoft's testing and
the closest to the 24-month support ceiling. Being a year behind means being
three months from being force-updated.

---

## `Set-UpdateDeferral.ps1` - every option

```bash
powershell -ExecutionPolicy Bypass -File .\Set-UpdateDeferral.ps1 -Months 3 -WhatIf
powershell -ExecutionPolicy Bypass -File .\Set-UpdateDeferral.ps1 -Months 6
powershell -ExecutionPolicy Bypass -File .\Set-UpdateDeferral.ps1 -Months 12 -Force -Tag before-holiday
```

### `-Months` (required)

`3`, `6` or `12`. Anything else is refused before a backup is even attempted -
the self-test proves that refusal fires by feeding it 1, 0 and 24.

### `-WhatIf`

Prints every change and makes none. Works **without** administrator rights,
deliberately.

### `-Force`

Skips the typed confirmation. Without it you must type the number of months -
not "y", the actual number, because this is not a decision to make by reflex.

### `-Tag`

Labels the backup file. A tag can never impersonate an internal snapshot: the
`~` character is stripped by the tag sanitiser, and the self-test proves it.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | applied |
| 3 | backup refused; nothing changed |
| 4 | nothing to do, unelevated, or you declined |
| 5 | completed, but a write failed |

### What the output tells you, precisely

```
    ESTABLISHED : 5 policy value(s) written and read back from the registry.
    ESTABLISHED : the pin names 25H2, which is the release now installed.
    NOT ESTABLISHED : that the update client on this edition obeys them.
```

That third line is the module refusing to overclaim. It is not hedging - it is
the difference between what was measured and what was hoped.

---

## `Restore-UpdateDeferral.ps1` - every option

```bash
powershell -ExecutionPolicy Bypass -File .\Restore-UpdateDeferral.ps1
powershell -ExecutionPolicy Bypass -File .\Restore-UpdateDeferral.ps1 -Original
powershell -ExecutionPolicy Bypass -File .\Restore-UpdateDeferral.ps1 -List
```

### Absent is not zero

None of these five values exists on a default machine. The backup records that,
so the undo **removes** them rather than writing zeros - and removes the policy
key too, if this module created it and nothing else has been written into it
since.

An explicit `0` is a policy a future administrator has to reason about. Absent
is absent. The round trip compares the **key's existence** as well as the
values, so a "restore" that left an empty key behind is reported as a failure.

---

## Troubleshooting

### The release changed anyway

Then the hold was not honoured on this edition, which is the outcome the module
warned was possible. Two things worth doing:

1. Run check 1 and read the history - it will show both releases, and say so.
2. Check whether the values are still present. Microsoft's own warning applies:
   *"registry keys can be easily overwritten"*, and a feature update is exactly
   the sort of thing that overwrites them.

This is not a module failure; it is the module producing the evidence that
settles the question. Record it and move on.

### Security updates seem to have stopped

Undo immediately with **6**. This module writes nothing that should affect
quality updates, and the self-test asserts it for all three hold lengths - so
if patches genuinely stopped, something else is going on and the hold should
not be left in place while you find out.

### Check 1 says the pin does not match the installed release

You applied a hold, then Windows moved anyway. Re-apply - the pin is always
computed from the live release, so re-applying re-pins you to where you now are.

### Check 1 says a safeguard hold is in effect

`GStatus = 0` means **Microsoft** is holding this machine back, independently of
anything you set - a known-bad combination for this hardware. Do not work
around it. It is the one form of update blocking that exists specifically to
protect you.

### I want to move to the next release deliberately

Undo with **6**, let the update install, then re-apply the hold. The pin is
re-read from the machine each time, so it will pin you to the new release.

---

## What this module deliberately does not do

- **Defer, pause or otherwise delay security updates.**
- **Use the 35-day pause.** It expires silently; a setting that stops working
  without telling you is worse than no setting.
- **Touch `NoAutoUpdate` or `AUOptions`.** Turning updates off entirely is a
  different and worse decision than holding feature releases.
- **Touch any update service.** `wuauserv`, `UsoSvc`, `BITS` and `DoSvc` are all
  never-touch in module 06.
- **Bypass a safeguard hold.**
- **Claim it works on Home.** It reports what it wrote and what that does and
  does not establish.
