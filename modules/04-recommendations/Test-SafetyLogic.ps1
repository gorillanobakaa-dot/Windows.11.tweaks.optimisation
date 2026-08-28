<#
.SYNOPSIS
    Test this module's own safety machinery. Changes nothing, needs no
    administrator rights, takes a couple of seconds.

.DESCRIPTION
    The round-trip test proves the WRITES work, by performing them. This proves
    the DECISIONS work, by feeding the module input it would never meet in normal
    use: a corrupt backup, a backup naming registry paths this module does not
    own, an unwritable backup folder, a tag full of illegal filename characters.

    Every check corresponds to a defect that was actually found in this project -
    most of them in module 01, by adversarial audit, and two of them in this
    module while it was being written.

.PARAMETER Detailed
    Print each check that passed, not only the failures.

.NOTES
    Exit code 0 if every check passes, 1 otherwise, so it can gate a commit.
#>

[CmdletBinding()]
param([switch]$Detailed)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$script:Passed = 0; $script:Failed = 0
$script:Failures = New-Object System.Collections.Generic.List[string]

function Assert-That {
    # [object], not [bool]. With [bool], a value that cannot be coerced fails at
    # PARAMETER BINDING before this function runs, so the assertion is recorded
    # neither as a pass nor a failure - and the run reports zero failures while
    # silently skipping checks. Module 01's self-test did exactly that.
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
Write-Host '  Recommendations - safety logic self-test'
Write-Host ('  ' + ('-' * 74))
Write-Host '  Changes nothing. Works in a temporary folder. No administrator rights.'
Write-Host ''

$tmp = Join-Path $env:TEMP ("rc-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $real = Get-RcState

    Write-Host '  1. A file that is merely JSON-shaped is rejected as a backup'
    Assert-That 'rejects $null'                    (-not (Test-RcStateShape -State $null))
    Assert-That 'rejects an empty object'          (-not (Test-RcStateShape -State ([pscustomobject]@{})))
    Assert-That 'rejects a wrong schema version'   (-not (Test-RcStateShape -State ([pscustomobject]@{ schemaVersion = 99; registry = ([pscustomobject]@{}) })))
    Assert-That 'rejects a missing registry section' (-not (Test-RcStateShape -State ([pscustomobject]@{ schemaVersion = $script:RcSchemaVersion })))
    Assert-That 'rejects a registry section that is an ARRAY' `
        (-not (Test-RcStateShape -State ([pscustomobject]@{ schemaVersion = $script:RcSchemaVersion; registry = @(1,2) }))) `
        'a backup containing "registry":[1,2] once produced eight phantom writes in module 01'
    Assert-That 'accepts a genuine state' (Test-RcStateShape -State ($real | ConvertTo-Json -Depth 8 | ConvertFrom-Json))

    Write-Host '  2. The allow-list refuses settings this module does not own'
    $owned = $script:RcDocumented[0]
    Assert-That 'owns its documented settings'  ($null -ne (Get-RcRule -Key $owned.Key -Name $owned.Name))
    Assert-That 'owns its observed settings too' ($null -ne (Get-RcRule -Key $script:RcObserved[0].Key -Name $script:RcObserved[0].Name)) `
        'the restore must cover both tiers or an -IncludeObserved run is stranded'
    Assert-That 'refuses a foreign value name'  ($null -eq (Get-RcRule -Key $owned.Key -Name 'EnableLUA'))
    Assert-That 'refuses a foreign key'         ($null -eq (Get-RcRule -Key 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name $owned.Name))
    Assert-That 'refuses a lookalike key path'  ($null -eq (Get-RcRule -Key ($owned.Key + '\Evil') -Name $owned.Name))

    Write-Host '  3. Backups are verified, not assumed'
    $good = Save-RcBackup -State $real -Directory $tmp -Tag 'selftest'
    Assert-That 'a good backup returns a path'          ($null -ne $good)
    Assert-That 'the file it names exists'              ($good -and (Test-Path $good))
    Assert-That 'it parses back into a usable state'    ($good -and (Test-RcStateShape -State (Get-Content $good -Raw -Encoding UTF8 | ConvertFrom-Json)))
    $bad = Save-RcBackup -State $real -Directory (Join-Path $tmp 'nope\<>|:') -Tag 'x' 3>$null
    Assert-That 'an unwritable folder returns $null'    ($null -eq $bad) `
        'the apply script keys off this to abort - a false success means changes with no undo'

    Write-Host '  4. Only the apply path may define "the original state"'
    $od = Join-Path $tmp 'orig'; New-Item -ItemType Directory -Path $od -Force | Out-Null
    [void](Save-RcBackup -State $real -Directory $od -Tag 'pre-restore')
    Assert-That 'a backup WITHOUT -RecordAsOriginal does not create original-state.json' `
        (-not (Test-Path (Join-Path $od 'original-state.json'))) `
        'this defect made "undo to original" restore the applied state, permanently'
    [void](Save-RcBackup -State $real -Directory $od -Tag 'apply' -RecordAsOriginal)
    Assert-That 'a backup WITH -RecordAsOriginal creates it' (Test-Path (Join-Path $od 'original-state.json'))
    $h1 = (Get-FileHash (Join-Path $od 'original-state.json') -Algorithm SHA256).Hash
    [void](Save-RcBackup -State $real -Directory $od -Tag 'apply2' -RecordAsOriginal)
    $h2 = (Get-FileHash (Join-Path $od 'original-state.json') -Algorithm SHA256).Hash
    Assert-That 'original-state.json is never overwritten' ($h1 -eq $h2)

    Write-Host '  5. The undo never offers its own pre-restore snapshots'
    $cd = Join-Path $tmp 'cands'; New-Item -ItemType Directory -Path $cd -Force | Out-Null
    foreach ($n in @('state_2026-01-01_00-00-00.json','state_2026-01-02_00-00-00_~prerestore.json',
                     'state_2026-01-03_00-00-00_apply.json','snapshot_2026-01-04_00-00-00.json',
                     'state_2026-01-05_00-00-00_pre-restore.json','original-state.json')) {
        '{}' | Set-Content (Join-Path $cd $n) -Encoding UTF8
        # distinct timestamps: files born in the same second tie on
        # LastWriteTime and made the newest-first assertion flaky
        if ($n -match 'state_2026-01-(\d\d)') { (Get-Item (Join-Path $cd $n)).LastWriteTime = Get-Date ('2026-01-' + $Matches[1]) } }
    $c = @(Get-RcRestoreCandidates -Directory $cd)
    Assert-That 'internal ~prerestore snapshots excluded' (@($c | Where-Object { $_.Name -like '*~prerestore*' }).Count -eq 0) `
        'offering them made a double-undo restore the applied state from its own snapshot'
    Assert-That 'a USER tag of pre-restore does NOT hide a backup' `
        (@($c | Where-Object { $_.Name -like '*_pre-restore*' }).Count -eq 1) `
        'audit finding 4: -Tag "pre restore" once made the apply backup invisible to the undo'
    Assert-That 'read-only snapshots excluded'   (@($c | Where-Object { $_.Name -like 'snapshot_*' }).Count -eq 0)
    Assert-That 'original-state.json excluded'   (@($c | Where-Object { $_.Name -eq 'original-state.json' }).Count -eq 0)
    Assert-That 'the ordinary backups offered'   ($c.Count -eq 3)
    Assert-That 'candidates newest first'        ($c[0].Name -like '*2026-01-05*')
    $intSnap = Save-RcBackup -State $real -Directory $cd -InternalSuffix 'prerestore'
    Assert-That 'Save-RcBackup -InternalSuffix produces the ~ marker' `
        ($intSnap -and $intSnap -like '*_~prerestore*')
    Assert-That 'and that snapshot is invisible to the candidate list' `
        (@((Get-RcRestoreCandidates -Directory $cd) | Where-Object { $_.FullName -eq $intSnap }).Count -eq 0)

    Write-Host '  6. Tags cannot produce an illegal or invisible filename'
    $t = ConvertTo-RcSafeTag 'a/b\c:d*e?f"g<h>i|j'
    Assert-That 'separators, wildcards and colons stripped' ($t -notmatch '[\\/:*?"<>|]') "got '$t'"
    Assert-That 'over-long tag truncated' ((ConvertTo-RcSafeTag ('x' * 300)).Length -le 41)
    Assert-That 'empty tag yields empty suffix' ((ConvertTo-RcSafeTag '') -eq '')

    Write-Host '  7. "Absent" and "set to zero" stay distinguishable'
    $absent = [pscustomobject]@{ value = $null; kind = $null; existed = $false; keyExisted = $false }
    $zero   = [pscustomobject]@{ value = 0; kind = 'DWord'; existed = $true; keyExisted = $true }
    Assert-That 'they differ on .existed' ($absent.existed -ne $zero.existed)
    $j = $absent | ConvertTo-Json | ConvertFrom-Json
    Assert-That 'the flag survives a JSON round trip' (($j.existed -eq $false) -and ($j.existed -isnot [string])) `
        'a $false that returned as $null would turn "delete it" into "leave it alone"'
    Assert-That 'a real reading carries keyExisted' `
        ($null -ne $real.registry["$($script:RcDocumented[0].Key)|$($script:RcDocumented[0].Name)"].keyExisted)

    Write-Host '  8. The two tiers are actually separated'
    Assert-That 'every documented setting has a citation' `
        (@($script:RcDocumented | Where-Object { -not $_.Cite }).Count -eq 0) `
        'a documented-tier setting without a citation defeats the whole split'
    Assert-That 'no observed setting claims a citation' `
        (@($script:RcObserved | Where-Object { $_.Cite }).Count -eq 0)
    Assert-That 'the default scope is documented-only' `
        ((Get-RcSettings).Count -eq $script:RcDocumented.Count)
    Assert-That '-IncludeObserved widens it to both tiers' `
        ((Get-RcSettings -IncludeObserved).Count -eq ($script:RcDocumented.Count + $script:RcObserved.Count))
}
catch {
    # An exception means checks were skipped. "0 failed" after that is a lie
    # with a green tick on it.
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
Write-Host '    All safety checks passed. What this does NOT show: that the writes'
Write-Host '    themselves work. That is what "7 - Prove the undo works" does.'
Write-Host ''
exit 0
