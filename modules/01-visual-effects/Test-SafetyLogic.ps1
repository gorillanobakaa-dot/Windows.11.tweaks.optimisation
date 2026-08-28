<#
.SYNOPSIS
    Test this module's own safety machinery. Changes nothing on your machine,
    needs no administrator rights, takes a couple of seconds.

.DESCRIPTION
    `Test-RoundTrip.ps1` proves the WRITES work, by performing them. This proves
    the DECISIONS work, by feeding the module input it would never meet in normal
    use: a corrupt backup, a backup naming registry paths this module does not
    own, an unwritable backup folder, a tag full of characters that are illegal
    in a filename, a value that is not a whole number.

    Those situations cannot be produced by using the module correctly, which is
    exactly why they are never found by using it correctly. Two independent
    adversarial auditors found ten real defects in this module, and most of them
    lived in this space.

    Every check below corresponds to a defect that was actually found here. They
    are tests rather than assertions in a document because a claim in a README
    cannot fail, and a test can.

    Works entirely in a temporary folder, which it deletes afterwards. It reads
    the real machine only where a check needs a genuine state object.

.PARAMETER Detailed
    Print each check that passed, not only the failures.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-SafetyLogic.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-SafetyLogic.ps1 -Detailed

.NOTES
    Exit code 0 if every check passes, 1 otherwise, so it can gate a commit.
#>

[CmdletBinding()]
param([switch]$Detailed)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$script:Passed = 0
$script:Failed = 0
$script:Failures = New-Object System.Collections.Generic.List[string]

function Assert-That {
    # $Condition is [object], not [bool], on purpose. With [bool], a value that
    # cannot be coerced - say a function that returns an object rather than a
    # boolean - fails at PARAMETER BINDING, before this function runs. The
    # assertion is then never recorded either way, and the run reports zero
    # failures while silently skipping checks. That happened here, and a test
    # harness that can quietly not run a test is worse than no harness.
    param([string]$Name, [object]$Condition, [string]$Because = '')

    $ok = $false
    try { $ok = [bool]$Condition }
    catch {
        $script:Failed++
        $script:Failures.Add("$Name  (condition was not boolean: $($_.Exception.Message))")
        Write-Host ("    FAIL  {0}" -f $Name)
        Write-Host ("          condition did not evaluate to true or false")
        return
    }

    if ($ok) {
        $script:Passed++
        if ($Detailed) { Write-Host ("    pass  {0}" -f $Name) }
    }
    else {
        $script:Failed++
        $script:Failures.Add($Name + $(if ($Because) { "  ($Because)" } else { '' }))
        Write-Host ("    FAIL  {0}" -f $Name)
        if ($Because) { Write-Host ("          {0}" -f $Because) }
    }
}

Write-Host ''
Write-Host '  Visual effects - safety logic self-test'
Write-Host ('  ' + ('-' * 74))
Write-Host '  Changes nothing. Works in a temporary folder. No administrator rights.'
Write-Host ''

$tmp = Join-Path $env:TEMP ("vfx-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $real = Get-VfxState

    # =====================================================================
    Write-Host '  1. A backup that is merely JSON-shaped is rejected'
    # Test-VfxStateShape returns a LIST OF PROBLEMS - empty means usable.
    # =====================================================================
    Assert-That 'null is reported as a problem'        ((Test-VfxStateShape -State $null).Count -gt 0)
    Assert-That 'an empty object is reported'          ((Test-VfxStateShape -State ([pscustomobject]@{})).Count -gt 0)
    Assert-That 'a state with no spi section is reported' `
        ((Test-VfxStateShape -State ([pscustomobject]@{ registry = ([pscustomobject]@{}); schemaVersion = $script:VfxSchemaVersion })).Count -gt 0)
    Assert-That 'a state with no registry section is reported' `
        ((Test-VfxStateShape -State ([pscustomobject]@{ spi = ([pscustomobject]@{}); schemaVersion = $script:VfxSchemaVersion })).Count -gt 0)
    Assert-That 'a registry section that is not an object is reported' `
        ((Test-VfxStateShape -State ([pscustomobject]@{ spi = ([pscustomobject]@{}); registry = @(1, 2); schemaVersion = $script:VfxSchemaVersion })).Count -gt 0) `
        'a backup containing "registry":[1,2] once produced eight phantom registry writes'
    Assert-That 'a newer schemaVersion is reported' `
        ((Test-VfxStateShape -State ([pscustomobject]@{ spi = ([pscustomobject]@{}); registry = ([pscustomobject]@{}); schemaVersion = ($script:VfxSchemaVersion + 1) })).Count -gt 0) `
        'restoring from a file written by a newer build would silently skip settings it does not know'

    $realShape = Test-VfxStateShape -State ($real | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
    Assert-That 'a genuine state has no problems' ($realShape.Count -eq 0) ("reported: " + ($realShape -join '; '))

    # =====================================================================
    Write-Host '  2. The allow-list refuses settings this module does not own'
    # The restore once iterated the BACKUP's contents rather than the module's
    # own list, so a backup could name any registry path and have it written.
    # =====================================================================
    $owned = $script:VfxRegistry[0]
    Assert-That 'owns its own first registry setting' ($null -ne (Get-VfxRegistryRule -Key $owned.Key -Name $owned.Name))
    Assert-That 'refuses a foreign value name in an owned key' ($null -eq (Get-VfxRegistryRule -Key $owned.Key -Name 'EnableLUA'))
    Assert-That 'refuses an owned value name in a foreign key' `
        ($null -eq (Get-VfxRegistryRule -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name $owned.Name))
    Assert-That 'refuses a lookalike key with a trailing path' ($null -eq (Get-VfxRegistryRule -Key ($owned.Key + '\Evil') -Name $owned.Name))

    # =====================================================================
    Write-Host '  3. Backups are verified, not assumed'
    # The original defect: the backup writer reported success without checking
    # anything reached the disk, after which the apply script changed twenty
    # settings believing an undo existed.
    # =====================================================================
    $good = Save-VfxBackup -BackupDir $tmp -Tag 'selftest'
    Assert-That 'a good backup returns a path' ($null -ne $good)
    Assert-That 'the file it names actually exists' ($good -and (Test-Path $good))
    Assert-That 'the file parses back into a usable state' `
        ($good -and ((Test-VfxStateShape -State (Get-Content $good -Raw -Encoding UTF8 | ConvertFrom-Json)).Count -eq 0))

    $badDir = Join-Path $tmp 'nope\<>|:'
    $bad = Save-VfxBackup -BackupDir $badDir -Tag 'selftest' 3>$null
    Assert-That 'an unwritable folder returns $null, not a path' ($null -eq $bad) `
        'the apply script keys off this to abort - a false success means changes with no undo'

    # =====================================================================
    Write-Host '  4. Only the apply path may define "the original state"'
    # Fixed 2026-08-26 in this module and module 02. Without the switch, the
    # restore script's own pre-restore snapshot created original-state.json from
    # the CURRENT state when none existed, so "undo to original" restored to the
    # applied state forever.
    # =====================================================================
    $origDir = Join-Path $tmp 'orig'
    New-Item -ItemType Directory -Path $origDir -Force | Out-Null

    [void](Save-VfxBackup -BackupDir $origDir -Tag 'pre-restore')
    Assert-That 'a backup WITHOUT -RecordAsOriginal does not create original-state.json' `
        (-not (Test-Path (Join-Path $origDir 'original-state.json'))) `
        'this is the exact defect that made "undo to original" restore the applied state'

    [void](Save-VfxBackup -BackupDir $origDir -Tag 'apply' -RecordAsOriginal)
    Assert-That 'a backup WITH -RecordAsOriginal does create it' (Test-Path (Join-Path $origDir 'original-state.json'))

    $h1 = (Get-FileHash (Join-Path $origDir 'original-state.json') -Algorithm SHA256).Hash
    Start-Sleep -Milliseconds 1100
    [void](Save-VfxBackup -BackupDir $origDir -Tag 'apply2' -RecordAsOriginal)
    $h2 = (Get-FileHash (Join-Path $origDir 'original-state.json') -Algorithm SHA256).Hash
    Assert-That 'original-state.json is never overwritten, even by the apply path' ($h1 -eq $h2)

    # =====================================================================
    Write-Host '  5. The undo never offers its own pre-restore snapshots'
    # Running the undo twice once re-applied the changes, because the snapshot
    # taken before the first undo was eligible as a restore point.
    # =====================================================================
    $candDir = Join-Path $tmp 'cands'
    New-Item -ItemType Directory -Path $candDir -Force | Out-Null
    foreach ($n in @('state_2026-01-01_00-00-00.json',
                     'state_2026-01-02_00-00-00_pre-restore.json',
                     'state_2026-01-03_00-00-00_apply.json',
                     'snapshot_2026-01-04_00-00-00.json',
                     'original-state.json')) {
        '{}' | Set-Content (Join-Path $candDir $n) -Encoding UTF8
    }
    $cands = @(Get-VfxRestoreCandidates -BackupDir $candDir)
    Assert-That 'pre-restore snapshots are excluded' `
        (@($cands | Where-Object { $_.Name -like '*pre-restore*' }).Count -eq 0) `
        'including them makes a second undo re-apply what the first one reversed'
    Assert-That 'read-only snapshots are excluded'  (@($cands | Where-Object { $_.Name -like 'snapshot_*' }).Count -eq 0)
    Assert-That 'original-state.json is excluded'   (@($cands | Where-Object { $_.Name -eq 'original-state.json' }).Count -eq 0)
    Assert-That 'the two real backups are offered'  ($cands.Count -eq 2)
    Assert-That 'candidates are newest first'       ($cands[0].Name -like '*2026-01-03*')

    # =====================================================================
    Write-Host '  6. A value that is not a whole number is refused, not rounded'
    # [int] silently rounds. A backup holding 0.7 would restore as 1 - a value
    # that was never captured on any machine.
    # =====================================================================
    Assert-That 'a whole number converts'            ((ConvertTo-VfxInt 1) -eq 1)
    Assert-That 'zero converts'                      ((ConvertTo-VfxInt 0) -eq 0)
    Assert-That 'a boolean converts'                 ((ConvertTo-VfxInt $true) -eq 1)
    Assert-That 'null stays null'                    ($null -eq (ConvertTo-VfxInt $null))
    Assert-That '0.7 is refused rather than rounded to 1' ($null -eq (ConvertTo-VfxInt 0.7)) `
        'silent rounding would restore a value that was never captured'
    Assert-That 'a non-numeric string is refused'    ($null -eq (ConvertTo-VfxInt 'banana'))
    Assert-That 'a value beyond Int32 is refused'    ($null -eq (ConvertTo-VfxInt 99999999999))

    # =====================================================================
    Write-Host '  7. Tags cannot produce an illegal or invisible filename'
    # A colon in a tag creates an NTFS alternate data stream: the file appears
    # to write, is 0 bytes, and is invisible to the undo path.
    # =====================================================================
    $t = ConvertTo-VfxSafeTag 'a/b\c:d*e?f"g<h>i|j'
    Assert-That 'separators, wildcards and colons are stripped' ($t -notmatch '[\\/:*?"<>|]') "got '$t'"
    Assert-That 'an over-long tag is truncated'  ((ConvertTo-VfxSafeTag ('x' * 300)).Length -le 40)
    Assert-That 'an empty tag yields an empty suffix' ((ConvertTo-VfxSafeTag '') -eq '')

    # =====================================================================
    Write-Host '  8. The master gate is known to be a gate'
    # The legacy master switch suppresses writes to the ten effects behind it.
    # Restoring it FIRST silently discarded those writes whenever the captured
    # value was 0, while reporting all of them as restored.
    # =====================================================================
    Assert-That 'the master gate has a name the restore can find' `
        (-not [string]::IsNullOrWhiteSpace($script:VfxMasterName))
    Assert-That 'the master gate is one of the managed effects' `
        ($script:VfxEffects.Keys -contains $script:VfxMasterName) `
        'if this drifts, the restore cannot special-case the gate and ordering breaks silently'
    Assert-That 'the effects table is ordered (restore ordering depends on it)' `
        ($script:VfxEffects -is [System.Collections.Specialized.OrderedDictionary])

    # =====================================================================
    Write-Host '  9. The shared byte mask is compared, not assumed'
    # This module owns ten bits of UserPreferencesMask and cannot restore the
    # rest. It therefore captures it and COMPARES, reporting any difference.
    # =====================================================================
    $mask = Get-VfxUserPreferencesMask
    Assert-That 'the mask is readable' ($null -ne $mask)

    # Test-VfxMaskUnchanged takes a STATE and compares its captured mask against
    # the machine now, returning an object with .Same - not a boolean, and $null
    # for a backup too old to contain one.
    $sameResult = Test-VfxMaskUnchanged -State $real
    Assert-That 'comparing a fresh state against the machine reports Same' `
        ($null -ne $sameResult -and $sameResult.Same -eq $true)

    $doctored = $real | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    $doctored.userPreferencesMask = '00 11 22 33 44 55 66 77'
    $diffResult = Test-VfxMaskUnchanged -State $doctored
    Assert-That 'a different captured mask is detected as changed' `
        ($null -ne $diffResult -and $diffResult.Same -eq $false) `
        'if this cannot fail, the round-trip proof cannot see damage to the shared byte mask'

    $noMask = [pscustomobject]@{ spi = ([pscustomobject]@{}); registry = ([pscustomobject]@{}) }
    Assert-That 'a backup with no captured mask returns null rather than a false match' `
        ($null -eq (Test-VfxMaskUnchanged -State $noMask))
}
catch {
    # Any exception here means checks were skipped. Reporting "0 failed" after
    # that would be a false pass, which is the failure mode this whole file
    # exists to prevent.
    $script:Failed++
    $script:Failures.Add("the test run itself threw: $($_.Exception.Message)")
    Write-Host ''
    Write-Host ("    FAIL  the test run threw before finishing: {0}" -f $_.Exception.Message)
    Write-Host ("          at {0}" -f $_.InvocationInfo.PositionMessage.Split("`n")[0].Trim())
    Write-Host '          Checks after that point did NOT run.'
}
finally {
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    checks passed : {0}" -f $script:Passed)
Write-Host ("    checks failed : {0}" -f $script:Failed)
if ($script:Failed -gt 0) {
    Write-Host ''
    foreach ($f in $script:Failures) { Write-Host ("      {0}" -f $f) }
    Write-Host ''
    Write-Host '    Do not use this module until these are explained.'
    Write-Host ''
    exit 1
}
Write-Host ''
Write-Host '    All safety checks passed. Note what this does and does not show:'
Write-Host '    it exercises the logic that decides WHETHER to write. It does not'
Write-Host '    prove the writes themselves work - that is what "6 - Prove the undo'
Write-Host '    works" does, by performing them.'
Write-Host ''
exit 0
