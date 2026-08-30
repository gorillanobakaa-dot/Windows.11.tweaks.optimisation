# Recommendations, suggestions and "personalised" content

## Just want to click something?

| Double-click this | What happens | Admin? |
|---|---|---|
| **1 - Check what is on now** | Shows what is switched on for your account | No |
| **2 - Preview the changes (safe)** | Lists every change that would be made, then makes none | No |
| **3 - Apply the changes** | The five settings Microsoft documents | No |
| **4 - Apply the undocumented ones too** | All ten, including silent app installation | No |
| **5 - UNDO everything** | Puts back whatever the last run changed | No |
| **6 - UNDO back to the original** | All the way back to before this was ever used | No |
| **7 - Prove the undo works** | Applies, undoes, checks every setting came back | No |
| **8 - Test the safety logic** | Tests the machinery that decides whether to write | No |

**None of them asks for administrator rights, and none needs any.** Every setting
here lives under your own account. If anything in this module ever produces a
Windows permission prompt, something is wrong.

Full walkthrough with every option, and troubleshooting: [`HOWTO.md`](HOWTO.md).

---

## In plain language

### What this turns off

The switches under **Settings → Privacy & security → Recommendations & offers**,
plus several related ones that page does not show you: suggested apps, Windows
tips, "personalised" offers based on your diagnostic data, the language list
websites are allowed to read, Windows Spotlight, and the Recommended section of
the Start menu.

### The split that runs through this whole module

This project's rule is that a factual claim is either quoted from Microsoft's own
documentation or labelled as uncited. Applied honestly here, these settings fall
into two groups - and the split is enforced in code, not described in a footnote.

**Five are documented.** Microsoft names them, gives the exact registry path, and
states the value. `3 - Apply the changes` applies these.

**Five are not.** They are real, they are on this machine, their names describe
their function, and every debloat guide on the internet sets them - but nobody at
Microsoft has written them down anywhere this project can quote. They need
`4 - Apply the undocumented ones too`.

Both tiers are backed up identically and undone identically. The only difference
is whether a claim about them can be checked.

### The one in the undocumented group worth reading about

`SilentInstalledAppsEnabled`. On this machine it is set to **1**.

That is the setting governing whether Windows may install promoted apps onto your
machine **without asking you**. It is not in Microsoft's published documentation,
so this module will not apply it by default and this page will not pretend there
is a citation for it. It is still worth knowing about, which is why it is
reported by `1 - Check what is on now` with a note attached rather than buried in
a list.

That is the honest position: important, undocumented, opt-in, reversible.

### What was on this machine

Measured on 2026-08-26, Windows 11 Home, build 26200:

| Setting | State | Tier |
|---|---|---|
| `HttpAcceptLanguageOptOut` | not set → websites get your language list | documented [R-92] |
| `DisableTailoredExperiencesWithDiagnosticData` | not set | documented [R-93] |
| `DisableWindowsSpotlightFeatures` | not set | documented [R-94] |
| `DisableCloudOptimizedContent` | not set | documented [R-95] |
| `Start_TrackDocs` | not set | documented [R-96] |
| **`SilentInstalledAppsEnabled`** | **1 - silent installs permitted** | observed |
| `SystemPaneSuggestionsEnabled` | 1 | observed |
| `SubscribedContent-338389Enabled` | 1 | observed |
| `SoftLandingEnabled` | 1 | observed |
| `Start_TrackProgs` | not set | observed |

All ten would change. Note that "not set" here does **not** mean off - for these
settings, absent means Windows uses its default, and the default is on.

### Why Advertising ID is not in this module

Microsoft documents it at `HKEY_LOCAL_MACHINE`, which needs administrator rights,
and the per-user toggle is already off on the audited machine. Pulling one
machine-wide value into a per-user module would force **every** launcher here to
demand elevation for it. Keeping the module strictly per-account is why none of
the eight buttons above asks for permission.

---

## Undoing it

Run **`5 - UNDO everything`**. No arguments.

There is a wrinkle worth understanding. Nearly every setting here is **absent** on
a default machine - and absent is not the same as zero. Applying this module
*creates* those values, and for the CloudContent policy settings it may create the
key as well.

So the undo removes them rather than writing zeros. Writing a zero would leave
your account looking deliberately configured when it never was, and a future
administrator's policy would then find an explicit setting nobody remembers
making. `7 - Prove the undo works` treats *existed / did not exist* as a
difference that **fails** the test.

Where a policy key existed before this module ran, the undo leaves it alone even
if it ends up empty - it is not ours to remove - and says so, because an empty
policy key looks alarming to anyone auditing the registry later. An empty key sets
nothing: policies are values, not keys.

---

## What has actually been proved

| | Result |
|---|---|
| Adversarial audit | **16 findings, all fixed the same day** - including the undo instruction naming the wrong launcher, the round trip's own backup disarming "UNDO everything", and created parent keys leaking past the undo |
| Round trip, all 10 settings | **PASS** - 10 changed, 10 returned, including absent-vs-zero, whether the key existed, and how far up the created key chain goes |
| Comparison can detect a difference | **verified** - a doctored value, a doctored ancestor chain, and a null state are all caught |
| Safety logic self-test | **36 checks, 0 failures** |
| Citations | **5 / 5 verified** word-for-word against the offline corpus |
| Applied on the audited machine | **no** - every test left it exactly as it started |

The round-trip comparison was **wrong on its first run** and reported a false
PASS. The cause is worth recording because it is a PowerShell trap that reads as
correct: variable names are case-insensitive, so `param($A, $C)` followed by
`$a = $A.registry[$k]` assigns to the very variable it just read from. `$A` was
destroyed on the first iteration, every row afterwards threw *"Cannot index into a
null array"*, the differences list stayed empty, and the script printed PASS.

The same bug had already been found and fixed in module 01, and was reproduced
here from memory of the wrong lesson. The parameters are now `$Start` and `$End`,
and there is a guard that reports `COMPARISON BROKEN` if either state arrives
without a registry section - because a test that cannot fail is not a test.

---

## References

Every quotation carries a tag, the file, the line it starts on, and the sentence.
Check them yourself:

```bash
powershell -ExecutionPolicy Bypass -File ..\..\READ-ONLY-verification\Verify-Citations.ps1 -Document .\README.md -Detailed
```

| ID | Claim | rel_path | line | quote |
|---|---|---|---|---|
| R-92 | Opting out of the language list | windows-itpro-docs/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services.md | 845 | Create a new REG_DWORD registry setting named HttpAcceptLanguageOptOut in HKEY_CURRENT_USER\Control Panel\International\User Profile with a value of 1. |
| R-93 | Turning off tailored experiences | windows-itpro-docs/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services.md | 1263 | Create a REG_DWORD registry setting named DisableTailoredExperiencesWithDiagnosticData in HKEY_CURRENT_USER\SOFTWARE\Policies\Microsoft\Windows\CloudContent with a value of 1 (one) |
| R-94 | Turning off all Windows Spotlight features | windows-itpro-docs/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services.md | 1598 | Create a new REG_DWORD registry setting named DisableWindowsSpotlightFeatures in HKEY_CURRENT_USER\SOFTWARE\Policies\Microsoft\Windows\CloudContent with a value of 1 (one). |
| R-95 | Turning off cloud optimized content | windows-itpro-docs/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services.md | 1605 | Create a new REG_DWORD registry setting named DisableCloudOptimizedContent in HKEY_CURRENT_USER\SOFTWARE\Policies\Microsoft\Windows\CloudContent with a value of 1 (one). |
| R-96 | Turning off the Start menu Recommended section | windows-itpro-docs/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services.md | 1780 | In the registry, you can set HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\Start_TrackDocs to 0. |

**The five observed settings have no entries here, deliberately.** Adding a
plausible-looking reference for something the corpus does not contain is exactly
the failure this table exists to prevent.
