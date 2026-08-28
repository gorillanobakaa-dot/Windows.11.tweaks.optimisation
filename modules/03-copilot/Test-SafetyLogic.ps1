<#
.SYNOPSIS
    Test this module's own safety machinery. Changes nothing, needs no
    administrator rights, takes a couple of seconds.

.DESCRIPTION
    Number 5 proves the settings-undo by performing it. This proves the
    DECISIONS, with input the module never meets in normal use. Every check
    corresponds to a defect actually found in this project by audit or by a
    test failing honestly.

    The tier split gets particular attention here: the removals must be
    structurally incapable of appearing in the restore path, because that is
    the module's central honesty claim.

.PARAMETER Detailed
    Print each check that passed, not only the failures.

.NOTES
    Exit code 0 if every check passes, 1 otherwise.
#>

[CmdletBinding()]
param([switch]$Detailed)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$script:Passed = 0; $script:Failed = 0
$script:Failures = New-Object System.Collections.Generic.List[string]

function Assert-That {
    # [object], not [bool]: a non-coercible value must count as a FAILURE, not
    # vanish at parameter binding (module 01's self-test printed "37 passed,
    # 0 failed" while two checks never ran).
    param([string]$Name, [object]$Condition, [string]$Because = '')
    $ok = $false
    try { $ok = [bool]$Condition }
    catch {
        $script:Failed++; $script:Failures.Add("$Name  (condition was not boolean)")
        Write-Host ("    FAIL  {0}" -f $Name); return
    }
    if ($ok) { $script:Passed++; if ($Detailed) { Write-Host ("    pass  {0}" -f $Name) } }
    else {
        $script:Failed++; $script:Failures.Add($Name + $(if ($Because) { "  ($Because)" } else { '' }))
        Write-Host ("    FAIL  {0}" -f $Name)
        if ($Because) { Write-Host ("          {0}" -f $Because) }
    }
}

Write-Host ''
Write-Host '  Copilot module - safety logic self-test'
Write-Host ('  ' + ('-' * 74))
Write-Host '  Changes nothing that stays: a temporary folder and one throwaway HKCU'
Write-Host '  test key, both deleted at the end. No administrator rights.'
Write-Host ''

$tmp = Join-Path $env:TEMP ("cp-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $real = Get-CpState

    Write-Host '  1. A file that is merely JSON-shaped is rejected as a backup'
    Assert-That 'rejects $null'                      (-not (Test-CpStateShape -State $null))
    Assert-That 'rejects an empty object'            (-not (Test-CpStateShape -State ([pscustomobject]@{})))
    Assert-That 'rejects a wrong schema version'     (-not (Test-CpStateShape -State ([pscustomobject]@{ schemaVersion = 99; registry = ([pscustomobject]@{}); packages = ([pscustomobject]@{}) })))
    Assert-That 'rejects a NON-NUMERIC schema version' (-not (Test-CpStateShape -State ([pscustomobject]@{ schemaVersion = 'x'; registry = ([pscustomobject]@{}); packages = ([pscustomobject]@{}) }))) `
        'module 04 audit finding 12: the [int] cast threw instead of returning $false'
    Assert-That 'rejects a missing registry section' (-not (Test-CpStateShape -State ([pscustomobject]@{ schemaVersion = $script:CpSchemaVersion; packages = ([pscustomobject]@{}) })))
    Assert-That 'accepts a genuine state'            (Test-CpStateShape -State ($real | ConvertTo-Json -Depth 8 | ConvertFrom-Json))

    Write-Host '  2. The restore allow-list is tier 1 ONLY - the removals cannot appear in it'
    Assert-That 'owns its three tier-1 settings' (
        ($null -ne (Get-CpRegistryRule -Key $script:CpRegistry[0].Key -Name $script:CpRegistry[0].Name)) -and
        ($null -ne (Get-CpRegistryRule -Key $script:CpRegistry[1].Key -Name $script:CpRegistry[1].Name)) -and
        ($null -ne (Get-CpRegistryRule -Key $script:CpRegistry[2].Key -Name $script:CpRegistry[2].Name)))
    Assert-That 'every allow-list entry is tier 1' (@($script:CpRegistry | Where-Object { $_.Tier -ne 1 }).Count -eq 0) `
        'a tier-2 removal in the restore allow-list would let a restore claim to reverse a removal'
    Assert-That 'refuses a foreign value name' ($null -eq (Get-CpRegistryRule -Key $script:CpRegistry[0].Key -Name 'EnableLUA'))
    Assert-That 'refuses a foreign key'        ($null -eq (Get-CpRegistryRule -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name $script:CpRegistry[0].Name))
    Assert-That 'refuses a lookalike key path' ($null -eq (Get-CpRegistryRule -Key ($script:CpRegistry[0].Key + '\Evil') -Name $script:CpRegistry[0].Name))

    Write-Host '  3. Backups are verified, not assumed'
    $good = Save-CpBackup -State $real -Directory $tmp -Tag 'selftest'
    Assert-That 'a good backup returns a path'       ($null -ne $good)
    Assert-That 'the file it names exists'           ($good -and (Test-Path $good))
    Assert-That 'it parses back into a usable state' ($good -and (Test-CpStateShape -State (Get-Content $good -Raw -Encoding UTF8 | ConvertFrom-Json)))
    $bad = Save-CpBackup -State $real -Directory (Join-Path $tmp 'nope\<>|:') -Tag 'x' 3>$null
    Assert-That 'an unwritable folder returns $null' ($null -eq $bad)

    Write-Host '  4. Only the apply path may define "the original state"'
    $od = Join-Path $tmp 'orig'; New-Item -ItemType Directory -Path $od -Force | Out-Null
    [void](Save-CpBackup -State $real -Directory $od -InternalSuffix 'prerestore')
    Assert-That 'an internal snapshot does not create original-state.json' `
        (-not (Test-Path (Join-Path $od 'original-state.json')))
    [void](Save-CpBackup -State $real -Directory $od -Tag 'apply' -RecordAsOriginal)
    Assert-That 'a backup WITH -RecordAsOriginal creates it' (Test-Path (Join-Path $od 'original-state.json'))
    $h1 = (Get-FileHash (Join-Path $od 'original-state.json') -Algorithm SHA256).Hash
    [void](Save-CpBackup -State $real -Directory $od -Tag 'apply2' -RecordAsOriginal)
    $h2 = (Get-FileHash (Join-Path $od 'original-state.json') -Algorithm SHA256).Hash
    Assert-That 'original-state.json is never overwritten' ($h1 -eq $h2)

    Write-Host '  5. The undo never offers internal snapshots, and user tags cannot hide backups'
    $cd = Join-Path $tmp 'cands'; New-Item -ItemType Directory -Path $cd -Force | Out-Null
    foreach ($n in @('state_2026-01-01_00-00-00.json',
                     'state_2026-01-02_00-00-00_~prerestore.json',
                     'state_2026-01-03_00-00-00_apply.json',
                     'state_2026-01-04_00-00-00_pre-restore.json',
                     'original-state.json')) {
        '{}' | Set-Content (Join-Path $cd $n) -Encoding UTF8
        if ($n -match 'state_2026-01-(\d\d)') { (Get-Item (Join-Path $cd $n)).LastWriteTime = Get-Date ('2026-01-' + $Matches[1]) }
    }
    $c = @(Get-CpRestoreCandidates -Directory $cd)
    Assert-That 'internal ~prerestore snapshots excluded' (@($c | Where-Object { $_.Name -like '*~prerestore*' }).Count -eq 0) `
        'offering them made a double-undo restore the applied state in module 04'
    Assert-That 'a USER tag of pre-restore does NOT hide a backup' (@($c | Where-Object { $_.Name -like '*_pre-restore*' }).Count -eq 1)
    Assert-That 'original-state.json excluded' (@($c | Where-Object { $_.Name -eq 'original-state.json' }).Count -eq 0)
    Assert-That 'the ordinary backups offered' ($c.Count -eq 3)
    Assert-That 'candidates newest first'      ($c[0].Name -like '*2026-01-04*')

    Write-Host '  6. "Absent" and "set to zero" stay distinguishable, chain included'
    $absent = [pscustomobject]@{ value = $null; kind = $null; existed = $false; keyExisted = $false; existingAncestor = 'HKCU:\SOFTWARE\Policies' }
    $zero   = [pscustomobject]@{ value = 0; kind = 'DWord'; existed = $true; keyExisted = $true }
    Assert-That 'they differ on .existed' ($absent.existed -ne $zero.existed)
    $j = $absent | ConvertTo-Json | ConvertFrom-Json
    Assert-That 'the flags survive a JSON round trip' (($j.existed -eq $false) -and ($j.keyExisted -eq $false))
    Assert-That 'the ancestor survives a JSON round trip' ($j.existingAncestor -eq 'HKCU:\SOFTWARE\Policies')
    Assert-That 'Get-CpExistingAncestor finds a real ancestor' `
        ((Get-CpExistingAncestor -Key 'HKCU:\SOFTWARE\No\Such\Chain\Здесь') -eq 'HKCU:\SOFTWARE')

    Write-Host '  7. The comparison in the round trip is falsifiable'
    $srcRt = Get-Content (Join-Path $here 'Test-RoundTrip.ps1') -Raw
    $fnRt  = [regex]::Match($srcRt, '(?s)function Compare-CpStates \{.*?\n\}').Value
    Assert-That 'Compare-CpStates could be extracted' (-not [string]::IsNullOrWhiteSpace($fnRt))
    if ($fnRt) {
        Invoke-Expression $fnRt
        $s1 = Get-CpState
        Assert-That 'two live readings compare equal' ((Compare-CpStates -Start $s1 -End (Get-CpState)).Count -eq 0)
        $s3 = Get-CpState
        $dk = "$($script:CpRegistry[0].Key)|$($script:CpRegistry[0].Name)"
        $cur = $s3.registry[$dk]
        $s3.registry[$dk] = [pscustomobject]@{ value = 9; kind = 'DWord'; existed = (-not $cur.existed); keyExisted = $true }
        Assert-That 'a doctored setting is detected' ((Compare-CpStates -Start $s1 -End $s3).Count -ge 1)
        $s4 = Get-CpState
        $s4.packages['Microsoft.Copilot'] = [pscustomobject]@{ present = (-not $s4.packages['Microsoft.Copilot'].present) }
        Assert-That 'software presence changing is detected' ((Compare-CpStates -Start $s1 -End $s4).Count -ge 1) `
            'the settings round trip must be able to notice if it somehow moved software'
        Assert-That 'a null state trips the guard' ((Compare-CpStates -Start $null -End $s1).Count -eq 1)
    }

    Write-Host '  8. Removal honesty: uninstall strings are parsed, not shelled'
    # The uninstall string is data from the registry. Splitting the quoted exe
    # from its arguments and existence-checking it is what stands between this
    # module and running arbitrary text through a shell.
    $u = '"C:\Program Files (x86)\Microsoft\Copilot\Application\1\Installer\copilot_setup.exe" --uninstall --mscopilot'
    $m = [regex]::Match($u, '^\s*"([^"]+)"\s*(.*)$')
    Assert-That 'a quoted uninstall string parses into exe + args' `
        ($m.Success -and $m.Groups[1].Value.EndsWith('copilot_setup.exe') -and $m.Groups[2].Value -eq '--uninstall --mscopilot')

    Write-Host '  9. The exit-code contract and the audit regressions stay fixed'
    $srcApply = Get-Content (Join-Path $here 'Remove-Copilot.ps1') -Raw
    Assert-That 'apply exits 3 when the backup is refused' ($srcApply -match '(?m)^\s*exit 3\b') `
        'the round trip gated on exit 3 while the apply never emitted it - dead code'
    Assert-That 'apply exits 4 when there is nothing to do' ($srcApply -match '(?m)^\s*exit 4\b') `
        'a nothing-to-do apply exiting 0 let the round trip restore a STALE backup'
    Assert-That 'the round trip gates on exit 4' ($srcRt -match '\$applyExit -eq 4')
    Assert-That 'no unguarded [int] cast on live registry data' ($srcApply -notmatch '\[int\]\s*\$e\.value')
    Assert-That 'uninstaller arguments are not re-split on whitespace' ($srcApply -notmatch '\$argline\s+-split')
    Assert-That 'a corrupt removal record is preserved, never overwritten' ($srcApply -match 'unreadable-')
    $srcRestore = Get-Content (Join-Path $here 'Restore-Copilot.ps1') -Raw
    Assert-That '-List annotation is derived from the real candidate filter' `
        (($srcRestore -match 'Get-CpRestoreCandidates') -and ($srcRestore -notmatch "-like\s+'\*pre-restore\*'")) `
        'a second hand-written pattern annotated the backup list backwards'
    Assert-That 'the undo stops if its own pre-restore snapshot fails' ($srcRestore -match 'STOPPING')
    # PS 5.1: ConvertFrom-Json emits a JSON array as ONE pipeline object.
    # @(pipe) therefore counts 1 for any array; assign-then-wrap counts right.
    # The wrong pattern false-alarmed the removal record's read-back, live.
    $parsedDemo = '[{"a":1},{"a":2}]' | ConvertFrom-Json
    Assert-That 'assign-then-wrap counts JSON array entries correctly' (@($parsedDemo).Count -eq 2) `
        'if this fails the fix pattern itself is wrong on this PowerShell'
    Assert-That 'no piped-into-@() ConvertFrom-Json on the removal record' `
        (($srcApply -notmatch '@\(Get-Content [^\r\n]*ConvertFrom-Json[^\r\n]*\)') -and ($srcRestore -notmatch '@\(Get-Content [^\r\n]*ConvertFrom-Json[^\r\n]*\)')) `
        'that pattern counts every JSON array as 1 entry on PowerShell 5.1'

    Write-Host '  10. Key cleanup counts the (Default) value - a set default is data'
    $rnd = 'HKCU:\SOFTWARE\cp-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    try {
        New-Item -Path (Join-Path $rnd 'A\B') -Force | Out-Null
        Set-Item -Path (Join-Path $rnd 'A') -Value 'third-party data'   # sets (Default)
        [void](Remove-CpCreatedKeys -Entries @([pscustomobject]@{ Key = (Join-Path $rnd 'A\B'); Ancestor = $rnd }))
        Assert-That 'an empty created leaf key is removed' (-not (Test-Path (Join-Path $rnd 'A\B')))
        Assert-That 'a key whose (Default) value is set is KEPT' (Test-Path (Join-Path $rnd 'A')) `
            'GetValueNames() reports a set (Default) as an empty string; filtering it out deleted data'
    }
    finally { Remove-Item -Path $rnd -Recurse -Force -ErrorAction SilentlyContinue }
}
catch {
    $script:Failed++
    $script:Failures.Add("the test run itself threw: $($_.Exception.Message)")
    Write-Host ''
    Write-Host ("    FAIL  the test run threw before finishing: {0}" -f $_.Exception.Message)
    Write-Host '          Checks after that point did NOT run.'
}
finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    checks passed : {0}" -f $script:Passed)
Write-Host ("    checks failed : {0}" -f $script:Failed)
if ($script:Failed -gt 0) {
    Write-Host ''
    foreach ($f in $script:Failures) { Write-Host ("      {0}" -f $f) }
    Write-Host ''
    exit 1
}
Write-Host ''
Write-Host '    All safety checks passed. This shows the DECISIONS work; number 5'
Write-Host '    proves the settings-undo by performing it. Nothing proves the removals'
Write-Host '    reversible, because they are not, and no test will pretend otherwise.'
Write-Host ''
exit 0
