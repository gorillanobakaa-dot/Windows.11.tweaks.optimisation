<#
.SYNOPSIS
    Test this module's own safety machinery. Changes nothing that stays,
    needs no administrator rights.

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
    # [object], not [bool]: a non-coercible value must count as a FAILURE,
    # not vanish at parameter binding (R2.8a, found the hard way).
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
Write-Host '  Xbox services module - safety logic self-test'
Write-Host ('  ' + ('-' * 74))
Write-Host '  Changes nothing that stays: works in a temporary folder. No admin rights.'
Write-Host ''

$tmp = Join-Path $env:TEMP ("xs-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $real = Get-XsState

    Write-Host '  1. A file that is merely JSON-shaped is rejected as a backup'
    Assert-That 'rejects $null'                        (-not (Test-XsStateShape -State $null))
    Assert-That 'rejects an empty object'              (-not (Test-XsStateShape -State ([pscustomobject]@{})))
    Assert-That 'rejects a wrong schema version'       (-not (Test-XsStateShape -State ([pscustomobject]@{ schemaVersion = 99; services = ([pscustomobject]@{}) })))
    Assert-That 'rejects a NON-NUMERIC schema version' (-not (Test-XsStateShape -State ([pscustomobject]@{ schemaVersion = 'x'; services = ([pscustomobject]@{}) })))
    Assert-That 'rejects a missing services section'   (-not (Test-XsStateShape -State ([pscustomobject]@{ schemaVersion = $script:XsSchemaVersion })))
    Assert-That 'accepts a genuine state'              (Test-XsStateShape -State ($real | ConvertTo-Json -Depth 8 | ConvertFrom-Json))

    Write-Host '  2. The allow-list refuses what it does not own'
    Assert-That 'owns its five services' (@($script:XsServices).Count -eq 5)
    Assert-That 'refuses a foreign service name' ($null -eq (Get-XsServiceRule -Name 'wuauserv'))
    Assert-That 'refuses a lookalike'            ($null -eq (Get-XsServiceRule -Name 'XblAuthManager2'))

    Write-Host '  3. Restore validation refuses garbage start types (a backup is data)'
    Assert-That 'accepts 2, 3 and 4'  ((Test-XsValidStart 2) -and (Test-XsValidStart 3) -and (Test-XsValidStart 4))
    Assert-That 'refuses 0 and 1 (DRIVER start types, not service ones)' `
        ((-not (Test-XsValidStart 0)) -and (-not (Test-XsValidStart 1))) `
        'a doctored backup must not be able to set a service to boot-start'
    Assert-That 'refuses 9'           (-not (Test-XsValidStart 9))
    Assert-That 'refuses -1'          (-not (Test-XsValidStart -1))
    Assert-That 'refuses non-numeric' (-not (Test-XsValidStart 'on'))
    Assert-That 'refuses $null ($null -as [int] coerces to 0)' (-not (Test-XsValidStart $null))

    Write-Host '  4. Backups are verified, not assumed'
    $good = Save-XsBackup -State $real -Directory $tmp -Tag 'selftest'
    Assert-That 'a good backup returns a path'       ($null -ne $good)
    Assert-That 'the file it names exists'           ($good -and (Test-Path $good))
    Assert-That 'it parses back into a usable state' ($good -and (Test-XsStateShape -State (Get-Content $good -Raw -Encoding UTF8 | ConvertFrom-Json)))
    $bad = Save-XsBackup -State $real -Directory (Join-Path $tmp 'nope\<>|:') -Tag 'x' 3>$null
    Assert-That 'an unwritable folder returns $null' ($null -eq $bad)

    Write-Host '  5. Only the apply path may define "the original state"'
    $od = Join-Path $tmp 'orig'; New-Item -ItemType Directory -Path $od -Force | Out-Null
    [void](Save-XsBackup -State $real -Directory $od -InternalSuffix 'prerestore')
    Assert-That 'an internal snapshot does not create original-state.json' (-not (Test-Path (Join-Path $od 'original-state.json')))
    [void](Save-XsBackup -State $real -Directory $od -Tag 'apply' -RecordAsOriginal)
    Assert-That 'a backup WITH -RecordAsOriginal creates it' (Test-Path (Join-Path $od 'original-state.json'))
    $h1 = (Get-FileHash (Join-Path $od 'original-state.json') -Algorithm SHA256).Hash
    [void](Save-XsBackup -State $real -Directory $od -Tag 'apply2' -RecordAsOriginal)
    $h2 = (Get-FileHash (Join-Path $od 'original-state.json') -Algorithm SHA256).Hash
    Assert-That 'original-state.json is never overwritten' ($h1 -eq $h2)

    Write-Host '  6. The undo never offers internal snapshots; user tags cannot hide backups'
    $cd = Join-Path $tmp 'cands'; New-Item -ItemType Directory -Path $cd -Force | Out-Null
    foreach ($n in @('state_2026-01-01_00-00-00.json',
                     'state_2026-01-02_00-00-00_~prerestore.json',
                     'state_2026-01-03_00-00-00_apply.json',
                     'state_2026-01-04_00-00-00_pre-restore.json',
                     'original-state.json')) {
        '{}' | Set-Content (Join-Path $cd $n) -Encoding UTF8
        if ($n -match 'state_2026-01-(\d\d)') { (Get-Item (Join-Path $cd $n)).LastWriteTime = Get-Date ('2026-01-' + $Matches[1]) }
    }
    $c = @(Get-XsRestoreCandidates -Directory $cd)
    Assert-That 'internal ~prerestore snapshots excluded' (@($c | Where-Object { $_.Name -like '*~prerestore*' }).Count -eq 0)
    Assert-That 'a USER tag of pre-restore does NOT hide a backup' (@($c | Where-Object { $_.Name -like '*_pre-restore*' }).Count -eq 1)
    Assert-That 'original-state.json excluded' (@($c | Where-Object { $_.Name -eq 'original-state.json' }).Count -eq 0)
    Assert-That 'the ordinary backups offered' ($c.Count -eq 3)
    Assert-That 'candidates newest first'      ($c[0].Name -like '*2026-01-04*')

    Write-Host '  7. The round-trip comparison is falsifiable'
    $srcRt = Get-Content (Join-Path $here 'Test-RoundTrip.ps1') -Raw
    $fnRt  = [regex]::Match($srcRt, '(?s)function Compare-XsStates \{.*?\n\}').Value
    Assert-That 'Compare-XsStates could be extracted' (-not [string]::IsNullOrWhiteSpace($fnRt))
    if ($fnRt) {
        Invoke-Expression $fnRt
        $s1 = Get-XsState
        Assert-That 'two live readings compare equal' ((Compare-XsStates -Start $s1 -End (Get-XsState)).Count -eq 0)
        $s3 = Get-XsState
        $s3.services[$script:XsServices[0].Name] = [pscustomobject]@{ name = $script:XsServices[0].Name; existed = $true; start = 9; liveState = 'Stopped'; liveStartMode = 'Manual' }
        Assert-That 'a doctored start type is detected' ((Compare-XsStates -Start $s1 -End $s3).Count -ge 1)
        Assert-That 'a null state trips the guard' ((Compare-XsStates -Start $null -End $s1).Count -eq 1)
    }

    Write-Host '  8. The exit-code contract and known defect classes stay fixed'
    $srcApply = Get-Content (Join-Path $here 'Disable-XboxServices.ps1') -Raw
    Assert-That 'apply exits 3 when the backup is refused' ($srcApply -match '(?m)^\s*exit 3\b')
    Assert-That 'apply exits 4 when there is nothing to do' ($srcApply -match '(?m)^\s*exit 4\b')
    Assert-That 'the round trip gates on exit 3' ($srcRt -match '\$applyExit -eq 3')
    Assert-That 'the round trip gates on exit 4' ($srcRt -match '\$applyExit -eq 4')
    $srcRestore = Get-Content (Join-Path $here 'Restore-XboxServices.ps1') -Raw
    Assert-That '-List annotation derives from the real candidate filter' ($srcRestore -match 'Get-XsRestoreCandidates')
    Assert-That 'the undo stops if its pre-restore snapshot fails' ($srcRestore -match 'STOPPING')
    $parsedDemo = '[{"a":1},{"a":2}]' | ConvertFrom-Json
    Assert-That 'assign-then-wrap counts JSON array entries correctly' (@($parsedDemo).Count -eq 2)
    Assert-That 'no piped-into-@() ConvertFrom-Json anywhere' `
        (($srcApply -notmatch '@\(Get-Content [^\r\n]*ConvertFrom-Json[^\r\n]*\)') -and ($srcRestore -notmatch '@\(Get-Content [^\r\n]*ConvertFrom-Json[^\r\n]*\)'))
    Assert-That 'apply exits 5 when changes failed' ($srcApply -match '(?m)^\s*exit 5\b') `
        'audit S2: exit 0 over failed writes signals success to every caller'
    Assert-That 'the round trip stops on an UNEXPECTED apply exit code' ($srcRt -match '\$applyExit -ne 0') `
        'audit S1: a crashed apply must not send the undo after a stale backup'
    Assert-That 'the round trip prints the children''s own words on failure paths' ($srcRt -match 'what the apply said')
    Assert-That 'the restore has exit codes too (3 snapshot-refusal, 5 failures)' `
        (($srcRestore -match '(?m)^\s*exit 3\b') -and ($srcRestore -match 'exit 5'))
    $srcL2 = Get-Content (Join-Path $here '2 - Preview the changes (safe).cmd') -Raw
    Assert-That 'the preview launcher uses -File, not -Command' (($srcL2 -match '-File') -and ($srcL2 -notmatch '-Command')) `
        'audit M3: -Command breaks on paths containing an apostrophe'
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
Write-Host '    All safety checks passed. This shows the DECISIONS work; number 6'
Write-Host '    proves the undo by performing it.'
Write-Host ''
exit 0
