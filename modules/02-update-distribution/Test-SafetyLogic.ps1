<#
.SYNOPSIS
    Test this module's own safety logic. Changes nothing on your machine, needs
    no administrator rights, and takes a couple of seconds.

.DESCRIPTION
    The round-trip test proves the undo works by running it. This proves the
    machinery underneath behaves when it is given bad input - which is the case
    you cannot produce on demand and therefore never find by using the module
    normally.

    Every check here corresponds to a defect that was found in module 01 by
    adversarial audit, or to one found in this module while writing it. They are
    tests rather than assertions in a document because a claim in a README
    cannot fail, and a test can.

    It works entirely in a temporary folder. It reads the real machine only where
    a check needs a genuine state object to work with, and it writes nothing
    outside the temporary folder.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-SafetyLogic.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-SafetyLogic.ps1 -Detailed
    Also print each check that passed, not only the failures.

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
    # cannot be coerced fails at PARAMETER BINDING, before this function runs -
    # so the assertion is never recorded either way and the run reports zero
    # failures while silently skipping checks. That happened in module 01's copy
    # of this file: it printed "37 passed, 0 failed" while two checks threw and
    # never executed. A harness that can quietly not run a test is worse than no
    # harness, because it produces false confidence with a green tick on it.
    param([string]$Name, [object]$Condition, [string]$Because = '')

    $ok = $false
    try { $ok = [bool]$Condition }
    catch {
        $script:Failed++
        $script:Failures.Add("$Name  (condition was not boolean: $($_.Exception.Message))")
        Write-Host ("    FAIL  {0}" -f $Name)
        Write-Host  "          condition did not evaluate to true or false"
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
Write-Host '  Update distribution - safety logic self-test'
Write-Host ('  ' + ('-' * 74))
Write-Host '  Changes nothing. Works in a temporary folder. No administrator rights.'
Write-Host ''

$tmp = Join-Path $env:TEMP ("ud-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $real = Get-UdState

    # =====================================================================
    Write-Host '  1. State validation rejects things that are not state files'
    # A restore driven by anything merely JSON-shaped is a restore that writes
    # anything. Module 01 shipped without this check.
    # =====================================================================
    Assert-That 'rejects $null' (-not (Test-UdStateShape -State $null))
    Assert-That 'rejects an empty object' (-not (Test-UdStateShape -State ([pscustomobject]@{})))
    Assert-That 'rejects a wrong schema version' (-not (Test-UdStateShape -State ([pscustomobject]@{
        schemaVersion = 99; registry = @{}; firewall = @{} })))
    Assert-That 'rejects a state with no registry section' (-not (Test-UdStateShape -State ([pscustomobject]@{
        schemaVersion = $script:UdSchemaVersion; firewall = @{} })))
    Assert-That 'rejects a state with no firewall section' (-not (Test-UdStateShape -State ([pscustomobject]@{
        schemaVersion = $script:UdSchemaVersion; registry = @{} })))
    Assert-That 'accepts a genuine state' (Test-UdStateShape -State $real)

    # =====================================================================
    Write-Host '  2. The allow-list refuses settings this module does not own'
    # Module 01's audit: the restore iterated the BACKUP's contents, so a
    # backup naming "registry":[1,2] produced eight phantom writes.
    # =====================================================================
    Assert-That 'owns DODownloadMode' ($null -ne (Get-UdRegistryRule -Key $script:UdRegistry[0].Key -Name 'DODownloadMode'))
    Assert-That 'refuses a foreign value name' ($null -eq (Get-UdRegistryRule -Key $script:UdRegistry[0].Key -Name 'EnableLUA'))
    Assert-That 'refuses a foreign key' ($null -eq (Get-UdRegistryRule -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'DODownloadMode'))
    Assert-That 'refuses a lookalike key (trailing path)' ($null -eq (Get-UdRegistryRule -Key ($script:UdRegistry[0].Key + '\Evil') -Name 'DODownloadMode'))
    Assert-That 'owns the two firewall rules' (
        ($null -ne (Get-UdFirewallRuleDef -Name 'DeliveryOptimization-TCP-In')) -and
        ($null -ne (Get-UdFirewallRuleDef -Name 'DeliveryOptimization-UDP-In')))
    Assert-That 'refuses a foreign firewall rule' ($null -eq (Get-UdFirewallRuleDef -Name 'RemoteDesktop-UserMode-In-TCP'))

    # =====================================================================
    Write-Host '  3. Backups are verified, not assumed'
    # Module 01's audit: the backup writer reported success without checking
    # anything reached the disk, after which twenty settings were changed.
    # =====================================================================
    $good = Save-UdBackup -State $real -Directory $tmp -Tag 'selftest'
    Assert-That 'a good backup returns a path' ($null -ne $good)
    Assert-That 'the file it names actually exists' ($good -and (Test-Path $good))
    Assert-That 'the file parses back into a valid state' (
        $good -and (Test-UdStateShape -State (Get-Content $good -Raw -Encoding UTF8 | ConvertFrom-Json)))

    $badDir = Join-Path $tmp 'no\such\place\that\cannot\be\made:<>|'
    $bad = Save-UdBackup -State $real -Directory $badDir -Tag 'selftest' 3>$null
    Assert-That 'an unwritable directory returns $null, not a path' ($null -eq $bad) `
        'the apply script keys off this to abort - a false success here means changes with no undo'

    # =====================================================================
    Write-Host '  4. Only the apply path may define "original"'
    # Found 2026-08-26 in BOTH modules: the restore script''s own pre-restore
    # snapshot created original-state.json from the CURRENT state when none
    # existed, so "undo to original" restored to the applied state forever.
    # =====================================================================
    $origDir = Join-Path $tmp 'orig'
    New-Item -ItemType Directory -Path $origDir -Force | Out-Null
    [void](Save-UdBackup -State $real -Directory $origDir -Tag 'pre-restore')
    Assert-That 'a backup WITHOUT -RecordAsOriginal does not create original-state.json' `
        (-not (Test-Path (Join-Path $origDir 'original-state.json'))) `
        'this is the exact defect that made "undo to original" restore to the applied state'

    [void](Save-UdBackup -State $real -Directory $origDir -Tag 'apply' -RecordAsOriginal)
    Assert-That 'a backup WITH -RecordAsOriginal does create it' `
        (Test-Path (Join-Path $origDir 'original-state.json'))

    $firstHash = (Get-FileHash (Join-Path $origDir 'original-state.json') -Algorithm SHA256).Hash
    Start-Sleep -Milliseconds 1100   # so the second file gets a distinct timestamp
    [void](Save-UdBackup -State $real -Directory $origDir -Tag 'apply2' -RecordAsOriginal)
    $secondHash = (Get-FileHash (Join-Path $origDir 'original-state.json') -Algorithm SHA256).Hash
    Assert-That 'original-state.json is never overwritten, even by the apply path' `
        ($firstHash -eq $secondHash)

    # =====================================================================
    Write-Host '  5. Restore never offers its own pre-restore snapshots'
    # Module 01's audit: running the undo twice re-applied the changes, because
    # the snapshot taken before the first undo was eligible as a restore point.
    # =====================================================================
    $candDir = Join-Path $tmp 'cands'
    New-Item -ItemType Directory -Path $candDir -Force | Out-Null
    foreach ($n in @('state_2026-01-01_00-00-00.json',
                     'state_2026-01-02_00-00-00_~prerestore.json',
                     'state_2026-01-03_00-00-00_apply.json',
                     'state_2026-01-04_00-00-00_pre-restore.json')) {
        '{}' | Set-Content (Join-Path $candDir $n) -Encoding UTF8
        # distinct timestamps: files born in the same second tie on
        # LastWriteTime and made the newest-first assertion flaky
        if ($n -match 'state_2026-01-(\d\d)') { (Get-Item (Join-Path $candDir $n)).LastWriteTime = Get-Date ('2026-01-' + $Matches[1]) }
    }
    $cands = Get-UdRestoreCandidates -Directory $candDir
    Assert-That 'internal ~prerestore snapshots are excluded' `
        (@($cands | Where-Object { $_.Name -like '*~prerestore*' }).Count -eq 0) `
        'offering them makes a second undo re-apply the changes the first one reversed'
    Assert-That 'a USER tag of pre-restore does NOT hide a backup' `
        (@($cands | Where-Object { $_.Name -like '*_pre-restore*' }).Count -eq 1) `
        'audit finding: -Tag "pre restore" once made the apply backup invisible to the undo'
    Assert-That 'the ordinary backups are offered' ($cands.Count -eq 3)
    Assert-That 'candidates are newest first' ($cands[0].Name -like '*2026-01-04*')
    $intSnap = Save-UdBackup -State $real -Directory $candDir -InternalSuffix 'prerestore'
    Assert-That 'Save-UdBackup -InternalSuffix produces the ~ marker' `
        ($intSnap -and $intSnap -like '*_~prerestore*')
    Assert-That 'and that snapshot is invisible to the candidate list' `
        (@((Get-UdRestoreCandidates -Directory $candDir) | Where-Object { $_.FullName -eq $intSnap }).Count -eq 0)

    # =====================================================================
    Write-Host '  6. Tags cannot produce an illegal filename'
    # =====================================================================
    $t = ConvertTo-UdSafeTag 'a/b\c:d*e?f"g<h>i|j'
    Assert-That 'path separators and wildcards are stripped from tags' `
        ($t -notmatch '[\\/:*?"<>|]') "got '$t'"
    Assert-That 'an over-long tag is truncated' ((ConvertTo-UdSafeTag ('x' * 300)).Length -le 41)
    Assert-That 'an empty tag yields an empty suffix' ((ConvertTo-UdSafeTag '') -eq '')

    # =====================================================================
    Write-Host '  7. Download mode numbers are described, not guessed'
    # =====================================================================
    Assert-That 'unset is described as the LAN default, not as 0' `
        ((Get-UdModeName $null) -match 'unset' -and (Get-UdModeName $null) -match 'LAN')
    Assert-That '0 is CdnOnly' ((Get-UdModeName 0) -match 'CdnOnly')
    Assert-That '1 is LAN' ((Get-UdModeName 1) -match 'LAN')
    Assert-That '3 is Internet' ((Get-UdModeName 3) -match 'Internet')
    Assert-That 'an unrecognised value says so rather than inventing a name' `
        ((Get-UdModeName 42) -match 'unrecognised')

    # =====================================================================
    Write-Host '  8. "Absent" and "set to zero" are distinguishable'
    # This module's own hard case. If these two ever compare equal, the undo
    # cannot tell "never configured" from "configured to CdnOnly".
    # =====================================================================
    $absent = [pscustomobject]@{ value = $null; kind = $null; existed = $false; keyExisted = $false }
    $zero   = [pscustomobject]@{ value = 0;     kind = 'DWord'; existed = $true;  keyExisted = $true }
    Assert-That 'an absent value and a zero value differ on .existed' ($absent.existed -ne $zero.existed)
    Assert-That 'a real reading carries keyExisted' `
        ($null -ne $real.registry["$($script:UdRegistry[0].Key)|$($script:UdRegistry[0].Name)"].keyExisted)

    # A round trip through JSON must not lose the distinction - this is how the
    # backup is actually stored, and a $false that comes back as $null would
    # silently turn "delete it" into "leave it alone".
    $j = $absent | ConvertTo-Json | ConvertFrom-Json
    Assert-That 'the absent/present flag survives a JSON round trip' `
        (($j.existed -eq $false) -and ($j.existed -isnot [string]))

    # =====================================================================
    Write-Host '  8b. Restore-UdState refuses what the allow-list refuses'
    # Audit finding: the self-test proved Get-UdRegistryRule refuses foreign
    # names but never proved Restore-UdState USES it. This exercises the real
    # restore against a state whose registry section holds ONLY foreign entries:
    # everything must land in Ignored/Skipped and nothing may be written.
    $foreign = [pscustomobject]@{
        schemaVersion = $script:UdSchemaVersion
        registry = [pscustomobject]@{
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System|EnableLUA' =
                [pscustomobject]@{ value = 0; kind = 'DWord'; existed = $true; keyExisted = $true }
        }
        firewall = [pscustomobject]@{}
    }
    $rr = Restore-UdState -State $foreign
    Assert-That 'a foreign-only backup restores nothing'      ($rr.Restored -eq 0)
    Assert-That 'the foreign entry is reported as Ignored'    (@($rr.Ignored).Count -eq 1)
    Assert-That 'owned entries missing from it are Skipped'   ($rr.Skipped -eq ($script:UdRegistry.Count + $script:UdFirewallRules.Count))
    Assert-That 'nothing is reported Failed for a no-op'      ($rr.Failed -eq 0)

    # =====================================================================
    Write-Host '  8c. The round-trip comparison is falsifiable'
    # Audit finding: Compare-UdStates had no coverage at all, which is exactly
    # how a case-collision bug inside it survived into a real elevated run and
    # printed PASS having compared nothing.
    $srcRt = Get-Content (Join-Path $here 'Test-RoundTrip.ps1') -Raw
    $fnRt  = [regex]::Match($srcRt, '(?s)function Compare-UdStates \{.*?\n\}').Value
    Assert-That 'Compare-UdStates could be extracted from Test-RoundTrip.ps1' (-not [string]::IsNullOrWhiteSpace($fnRt))
    if ($fnRt) {
        Invoke-Expression $fnRt
        $live1 = Get-UdState
        $live2 = Get-UdState
        Assert-That 'two live readings compare equal'      ((Compare-UdStates -Start $live1 -End $live2).Count -eq 0)
        $doctor = Get-UdState
        $dk = "$($script:UdRegistry[0].Key)|$($script:UdRegistry[0].Name)"
        $cur = $doctor.registry[$dk]
        $doctor.registry[$dk] = [pscustomobject]@{ value = 42; kind = 'DWord'; existed = (-not $cur.existed); keyExisted = $true }
        Assert-That 'a doctored registry entry is detected' ((Compare-UdStates -Start $live1 -End $doctor).Count -ge 1) `
            'a comparison that cannot fail is not a comparison'
        $doctorFw = Get-UdState
        $fwName = $script:UdFirewallRules[0].Name
        $fwCur = $doctorFw.firewall[$fwName]
        if ($fwCur.present) {
            $doctorFw.firewall[$fwName] = [pscustomobject]@{ present=$true; enabled=(-not $fwCur.enabled); direction=$fwCur.direction; profile=$fwCur.profile; action=$fwCur.action; display=$fwCur.display }
            Assert-That 'a doctored firewall entry is detected' ((Compare-UdStates -Start $live1 -End $doctorFw).Count -ge 1)
        }
    }

    # =====================================================================
    Write-Host '  9. The module reads the machine without claiming to have changed it'
    # =====================================================================
    Assert-That 'a state reading includes the runtime section' ($null -ne $real.runtime)
    Assert-That 'a state reading includes the listener check' ($null -ne $real.listener)
    Assert-That 'a state reading records whether it was elevated' ($real.PSObject.Properties['elevated'] -ne $null)
    Assert-That 'services are recorded but not in the change allow-list' (
        ($real.services.Keys.Count -gt 0) -and
        ($script:UdRegistry.Key -notcontains 'DoSvc'))
}
catch {
    # Any exception here means checks were skipped. Reporting "0 failed" after
    # that would be a false pass, which is the failure mode this file exists to
    # prevent - so it is recorded as a failure and the exit code reflects it.
    $script:Failed++
    $script:Failures.Add("the test run itself threw: $($_.Exception.Message)")
    Write-Host ''
    Write-Host ("    FAIL  the test run threw before finishing: {0}" -f $_.Exception.Message)
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
Write-Host '    works" does, and it needs administrator rights.'
Write-Host ''
exit 0
