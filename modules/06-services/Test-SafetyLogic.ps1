<#
.SYNOPSIS
    Test this module's own safety machinery, especially the three refusals.
    Changes nothing, needs no administrator rights.

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
    param([string]$Name, [object]$Condition, [string]$Because = '')
    $ok = $false
    try { $ok = [bool]$Condition }
    catch { $script:Failed++; $script:Failures.Add("$Name  (condition was not boolean)")
            Write-Host ("    FAIL  {0}" -f $Name); return }
    if ($ok) { $script:Passed++; if ($Detailed) { Write-Host ("    pass  {0}" -f $Name) } }
    else {
        $script:Failed++; $script:Failures.Add($Name + $(if ($Because) { "  ($Because)" } else { '' }))
        Write-Host ("    FAIL  {0}" -f $Name)
        if ($Because) { Write-Host ("          {0}" -f $Because) }
    }
}

Write-Host ''
Write-Host '  Services module - safety logic self-test'
Write-Host ('  ' + ('-' * 74))
Write-Host '  Changes nothing that stays. No administrator rights.'
Write-Host ''

$tmp = Join-Path $env:TEMP ("svc-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $data = Get-SvcProfileData -Directory $here

    Write-Host '  1. The profile data is well formed and cumulative'
    Assert-That 'profiles.json loads'            ($null -ne $data)
    Assert-That 'it declares all three profiles' (($null -ne $data.profiles.light) -and ($null -ne $data.profiles.moderate) -and ($null -ne $data.profiles.super))
    $l = Get-SvcProfileNames -Data $data -Profile 'light'
    $m = Get-SvcProfileNames -Data $data -Profile 'moderate'
    $s = Get-SvcProfileNames -Data $data -Profile 'super'
    Assert-That 'light is a subset of moderate'  (@($l | Where-Object { $m -notcontains $_ }).Count -eq 0)
    Assert-That 'moderate is a subset of super'  (@($m | Where-Object { $s -notcontains $_ }).Count -eq 0)
    Assert-That 'each profile is strictly bigger' (($l.Count -lt $m.Count) -and ($m.Count -lt $s.Count))

    # Those three assert properties of the ACCESSOR: Get-SvcProfileNames
    # de-duplicates through a case-insensitive HashSet and builds each tier
    # cumulatively, so they hold however broken the data is. The audit proved
    # it with a deliberately duplicated profile set. These read the RAW rows.
    $rawAll = @()
    foreach ($t in 'light','moderate','super') {
        $rawAll += @($data.profiles.$t.services | ForEach-Object { ([string]$_.service).ToLower() })
    }
    Assert-That 'the RAW profile rows contain no duplicates at all' `
        ($rawAll.Count -eq (@($rawAll | Sort-Object -Unique).Count)) `
        'de-duplication in the accessor would hide a duplicated or mistyped row'
    Assert-That 'every RAW row names a service' `
        (@($rawAll | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -eq 0)
    Assert-That 'an unknown profile name throws' (& {
        try { [void](Get-SvcProfileNames -Data $data -Profile 'nonsense'); $false } catch { $true } })

    Write-Host '  2. The never-touch and lockout lists are enforced IN CODE'
    Assert-That 'the never list is populated'    (@($data.never).Count -ge 30)
    Assert-That 'UAC elevation is protected'     (@($data.never | Where-Object { $_.service -eq 'Appinfo' }).Count -eq 1) `
        'disabling Appinfo would make it impossible to run this module''s own undo as administrator'
    Assert-That 'the RPC substrate is protected' (@($data.never | Where-Object { $_.service -eq 'RpcSs' }).Count -eq 1)
    Assert-That 'the firewall is protected'      (@($data.never | Where-Object { $_.service -eq 'mpssvc' }).Count -eq 1)
    Assert-That 'Windows Update is protected'    (@($data.never | Where-Object { $_.service -eq 'wuauserv' }).Count -eq 1)
    Assert-That 'sign-in services are lockout-flagged' (@($data.lockoutRisk | Where-Object { $_.service -eq 'NgcSvc' }).Count -eq 1)
    foreach ($t in 'light','moderate','super') {
        $names = Get-SvcProfileNames -Data $data -Profile $t
        Assert-That "profile $t contains nothing forbidden" ((Test-SvcProfileLegal -Data $data -Names $names).Count -eq 0)
    }
    Assert-That 'a doctored profile naming RpcSs is REFUSED' `
        ((Test-SvcProfileLegal -Data $data -Names @('RpcSs')).Count -ge 1) `
        'the check must be able to FAIL, or it proves nothing'
    Assert-That 'a doctored profile naming NgcSvc is REFUSED' `
        ((Test-SvcProfileLegal -Data $data -Names @('NgcSvc')).Count -ge 1)
    Assert-That 'a clean name is not refused' `
        ((Test-SvcProfileLegal -Data $data -Names @('RetailDemo')).Count -eq 0)

    Write-Host '  3. Dependency safety is computed from the live machine'
    foreach ($t in 'light','moderate','super') {
        $names = Get-SvcProfileNames -Data $data -Profile $t
        Assert-That "profile $t breaks no dependency on THIS machine" ((Test-SvcDependencySafety -Names $names).Count -eq 0)
    }
    Assert-That 'the dependency check can FAIL' `
        ((Test-SvcDependencySafety -Names @('RpcSs')).Count -ge 1) `
        'disabling RpcSs must be seen to strand its 150+ dependents'

    Write-Host '  4. Start-type validation refuses what a service may not be'
    Assert-That 'accepts 2, 3 and 4'  ((Test-SvcValidStart 2) -and (Test-SvcValidStart 3) -and (Test-SvcValidStart 4))
    Assert-That 'refuses 0 and 1 (DRIVER start types)' ((-not (Test-SvcValidStart 0)) -and (-not (Test-SvcValidStart 1)))
    Assert-That 'refuses 9'           (-not (Test-SvcValidStart 9))
    Assert-That 'refuses non-numeric' (-not (Test-SvcValidStart 'on'))
    Assert-That 'refuses $null ($null -as [int] is 0)' (-not (Test-SvcValidStart $null))

    Write-Host '  5. Drivers are out of scope by construction'
    $drv = Get-SvcEntry -Name 'xboxgip'
    Assert-That 'a kernel driver reads as not-a-service' (-not $drv.existed) `
        'if drivers could be enumerated here, a profile could disable one'

    Write-Host '  6. The state file is a full inventory, and shape-checked'
    $real = Get-SvcState
    Assert-That 'the state covers the whole machine' (@($real.services.Keys).Count -gt 100)
    Assert-That 'rejects $null'                      (-not (Test-SvcStateShape -State $null))
    Assert-That 'rejects a wrong schema version'     (-not (Test-SvcStateShape -State ([pscustomobject]@{ schemaVersion = 99; services = ([pscustomobject]@{ a = 1 }) })))
    Assert-That 'rejects a NON-NUMERIC schema version' (-not (Test-SvcStateShape -State ([pscustomobject]@{ schemaVersion = 'x'; services = ([pscustomobject]@{ a = 1 }) })))
    Assert-That 'rejects an EMPTY services section'  (-not (Test-SvcStateShape -State ([pscustomobject]@{ schemaVersion = $script:SvcSchemaVersion; services = ([pscustomobject]@{}) }))) `
        'an empty inventory is shaped like a backup and would restore nothing'
    Assert-That 'accepts a genuine state'            (Test-SvcStateShape -State ($real | ConvertTo-Json -Depth 8 | ConvertFrom-Json))

    Write-Host '  7. Backups are verified, not assumed'
    $good = Save-SvcBackup -State $real -Directory $tmp -Tag 'selftest'
    Assert-That 'a good backup returns a path'       ($null -ne $good)
    Assert-That 'it parses back into a usable state' ($good -and (Test-SvcStateShape -State (Get-Content $good -Raw -Encoding UTF8 | ConvertFrom-Json)))
    $bad = Save-SvcBackup -State $real -Directory (Join-Path $tmp 'nope\<>|:') -Tag 'x' 3>$null
    Assert-That 'an unwritable folder returns $null' ($null -eq $bad)
    $od = Join-Path $tmp 'orig'; New-Item -ItemType Directory -Path $od -Force | Out-Null
    [void](Save-SvcBackup -State $real -Directory $od -InternalSuffix 'prerestore')
    Assert-That 'an internal snapshot does not create original-state.json' (-not (Test-Path (Join-Path $od 'original-state.json')))
    [void](Save-SvcBackup -State $real -Directory $od -Tag 'apply' -RecordAsOriginal)
    Assert-That 'a backup WITH -RecordAsOriginal creates it' (Test-Path (Join-Path $od 'original-state.json'))
    $h1 = (Get-FileHash (Join-Path $od 'original-state.json') -Algorithm SHA256).Hash
    [void](Save-SvcBackup -State $real -Directory $od -Tag 'apply2' -RecordAsOriginal)
    Assert-That 'original-state.json is never overwritten' ($h1 -eq (Get-FileHash (Join-Path $od 'original-state.json') -Algorithm SHA256).Hash)

    Write-Host '  8. The undo never offers internal snapshots'
    $cd = Join-Path $tmp 'cands'; New-Item -ItemType Directory -Path $cd -Force | Out-Null
    foreach ($n in @('state_2026-01-01_00-00-00.json',
                     'state_2026-01-02_00-00-00_~prerestore.json',
                     'state_2026-01-03_00-00-00_light.json',
                     'state_2026-01-04_00-00-00_pre-restore.json')) {
        '{}' | Set-Content (Join-Path $cd $n) -Encoding UTF8
        if ($n -match 'state_2026-01-(\d\d)') { (Get-Item (Join-Path $cd $n)).LastWriteTime = Get-Date ('2026-01-' + $Matches[1]) }
    }
    $c = @(Get-SvcRestoreCandidates -Directory $cd)
    Assert-That 'internal ~prerestore snapshots excluded' (@($c | Where-Object { $_.Name -like '*~prerestore*' }).Count -eq 0)
    Assert-That 'a USER tag of pre-restore does NOT hide a backup' (@($c | Where-Object { $_.Name -like '*_pre-restore*' }).Count -eq 1)
    Assert-That 'the ordinary backups are offered' ($c.Count -eq 3)
    Assert-That 'candidates newest first' ($c[0].Name -like '*2026-01-04*')

    Write-Host '  9. The round-trip comparison is falsifiable'
    $srcRt = Get-Content (Join-Path $here 'Test-RoundTrip.ps1') -Raw
    $fnRt  = [regex]::Match($srcRt, '(?s)function Compare-SvcStates \{.*?\n\}').Value
    Assert-That 'Compare-SvcStates could be extracted' (-not [string]::IsNullOrWhiteSpace($fnRt))
    if ($fnRt) {
        Invoke-Expression $fnRt
        $s1 = Get-SvcState
        Assert-That 'two live readings compare equal' ((Compare-SvcStates -Start $s1 -End (Get-SvcState)).Count -eq 0)
        $s3 = Get-SvcState
        $victim = @($s3.services.Keys)[0]
        $s3.services[$victim] = [pscustomobject]@{ name = $victim; existed = $true; start = 9 }
        Assert-That 'a doctored start type is detected' ((Compare-SvcStates -Start $s1 -End $s3).Count -ge 1)
        Assert-That 'a null state trips the guard' ((Compare-SvcStates -Start $null -End $s1).Count -eq 1)
        # The specific disguise this defect wore here: a LIVE state holds a
        # hashtable, so .PSObject.Properties enumerated Count/Keys/Values and
        # the comparison compared nothing while reporting PASS.
        Assert-That 'the comparison enumerates a LIVE (hashtable) state correctly' `
            ((Get-SvcEntries -Services $s1.services).Count -gt 100) `
            'iterating .PSObject.Properties on a hashtable yields Count/Keys/Values, not services'
        Assert-That 'the comparison enumerates a JSON-parsed state correctly' `
            ((Get-SvcEntries -Services ($s1 | ConvertTo-Json -Depth 8 | ConvertFrom-Json).services).Count -gt 100)
        Assert-That 'the round trip does not use .PSObject.Properties on services' `
            ($srcRt -cnotmatch '\.services\.PSObject\.Properties')
    }

    Write-Host ' 10. The exit-code contract and known defect classes stay fixed'
    $srcApply = Get-Content (Join-Path $here 'Apply-ServiceProfile.ps1') -Raw
    $srcRestore = Get-Content (Join-Path $here 'Restore-Services.ps1') -Raw
    Assert-That 'apply exits 3 when the backup is refused' ($srcApply -match '(?m)^\s*exit 3\b')
    Assert-That 'apply exits 4 when there is nothing to do' ($srcApply -match '(?m)^\s*exit 4\b')
    Assert-That 'apply exits 5 on failed writes'            ($srcApply -match '(?m)^\s*exit 5\b')
    Assert-That 'apply exits 6 on an illegal or unsafe profile' ($srcApply -match '(?m)^\s*exit 6\b')
    Assert-That 'the round trip gates on 3, 4, 5, 6 and anything unexpected' `
        (($srcRt -match '\$applyExit -eq 3') -and ($srcRt -match '\$applyExit -eq 4') -and
         ($srcRt -match '\$applyExit -eq 5') -and ($srcRt -match '\$applyExit -eq 6') -and
         ($srcRt -match '\$applyExit -ne 0'))
    Assert-That 'the undo stops if its pre-restore snapshot fails' ($srcRestore -match 'STOPPING')
    $parsedDemo = '[{"a":1},{"a":2}]' | ConvertFrom-Json
    Assert-That 'assign-then-wrap counts JSON array entries correctly' (@($parsedDemo).Count -eq 2)
    Assert-That 'no piped-into-@() ConvertFrom-Json anywhere' `
        (($srcApply -notmatch '@\(Get-Content [^\r\n]*ConvertFrom-Json[^\r\n]*\)') -and
         ($srcRestore -notmatch '@\(Get-Content [^\r\n]*ConvertFrom-Json[^\r\n]*\)'))
    Assert-That 'the round trip uses the LIGHT profile, not super' ($srcRt -match "-Profile light")

    # The guard for the hashtable/PSCustomObject class scanned only the file
    # where the bug was first found. Scan the class, everywhere.
    Assert-That 'no .PSObject.Properties on services in the round trip' ($srcRt -cnotmatch '\.services\.PSObject\.Properties')
    Assert-That 'no .PSObject.Properties on services in the apply'      ($srcApply -cnotmatch '\.services\.PSObject\.Properties')
    Assert-That 'no .PSObject.Properties on services in the restore'    ($srcRestore -cnotmatch '\.services\.PSObject\.Properties') `
        'the restore used the banned pattern and the guard did not cover that file'
    $srcCommon = Get-Content (Join-Path $here '_Common.ps1') -Raw
    Assert-That 'no .PSObject.Properties on services in the library'    ($srcCommon -cnotmatch '\.services\.PSObject\.Properties')
    Assert-That 'no hashtable-only .services.Keys anywhere' `
        ((($srcApply + $srcRestore + $srcRt) -notmatch '\.services\.Keys')) `
        '.Keys yields $null on a PSCustomObject, and @($null).Count is 1 - a full backup would report 1 service'

    Write-Host ' 11. The safety LISTS are validated, not merely present'
    # Audit S2: the never list was unvalidated data. A JSON typo that nulled
    # it removed the whole enforcement layer, silently.
    $tmpProf = Join-Path $tmp 'prof'
    New-Item -ItemType Directory -Path $tmpProf -Force | Out-Null
    $raw = Get-Content (Join-Path $here 'profiles.json') -Raw -Encoding UTF8
    function Test-Refuses { param([string]$Json)
        $Json | Set-Content (Join-Path $tmpProf 'profiles.json') -Encoding UTF8
        try { [void](Get-SvcProfileData -Directory $tmpProf); $false } catch { $true } }

    $doc = $raw | ConvertFrom-Json
    $noNever = $doc | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $noNever.never = @()
    Assert-That 'a profile set with an EMPTY never list is REFUSED' `
        (Test-Refuses ($noNever | ConvertTo-Json -Depth 12)) `
        'with never empty, Test-SvcProfileLegal found zero problems and the apply would disable RpcSs'
    $noLock = $doc | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $noLock.lockoutRisk = @()
    Assert-That 'a profile set with an EMPTY lockout list is REFUSED' (Test-Refuses ($noLock | ConvertTo-Json -Depth 12))
    $shortNever = $doc | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $shortNever.never = @($doc.never | Select-Object -First 3)
    Assert-That 'an implausibly SHORT never list is REFUSED' (Test-Refuses ($shortNever | ConvertTo-Json -Depth 12))
    $collide = $doc | ConvertTo-Json -Depth 12 | ConvertFrom-Json
    $collide.profiles.light.services = @($collide.profiles.light.services) + @([pscustomobject]@{
        service = 'RpcSs'; category = 'doctored'; reason = 'audit test'; microsoft_disposition = $null; tier = 'light' })
    Assert-That 'a profile naming a never-touch service is REFUSED AT LOAD' `
        (Test-Refuses ($collide | ConvertTo-Json -Depth 12)) `
        'caught before any code path can reach a write'
    Assert-That 'the real profiles.json still loads' `
        (& { try { [void](Get-SvcProfileData -Directory $here); $true } catch { $false } })

    Write-Host ' 12. The undo is guarded on BOTH lists, and drivers are visible'
    # Audit S3: the restore guarded never but not lockoutRisk, so a stale
    # backup could disable Windows Hello through the undo itself.
    Assert-That 'the restore guards the lockout list too' ($srcCommon -match 'Data\.lockoutRisk') `
        'a doctored backup could otherwise set NgcSvc to disabled via the undo'
    # Audit S20: the dependency check filtered drivers out, hiding a real edge.
    Assert-That 'a driver-aware dependency scan exists' ($srcCommon -match 'Get-SvcAllDependents')
    Assert-That 'the dependency check USES it' ($srcCommon -match 'foreach \(\$s in \(Get-SvcAllDependents\)\)')
    $drivers = @(Get-SvcAllDependents | Where-Object { $_.isDriver })
    Assert-That 'drivers declaring service dependencies are found on this machine' ($drivers.Count -ge 1) `
        'applockerfltr depends on AppIDSvc here - the edge the old scan could not see'
    Assert-That 'Type 80 (user-own-process) is enumerated' ($script:SvcWin32Types -contains 80)

    Write-Host ' 13. Failures reach the exit code'
    Assert-That 'stop failures are counted, not narrated' ($srcApply -match '\$stopFailed')
    Assert-That 'stop failures gate the exit code'        ($srcApply -match '\$stopFailed -gt 0')
    Assert-That 'declining the confirmation does not exit 0' ($srcApply -match '(?s)Nothing was changed.*?exit 4')
    Assert-That 'the apply names the RIGHT undo launcher' ($srcApply -match '8 - UNDO everything') `
        'it named launcher 4, which is Preview SUPER'
    Assert-That 'the restore refuses with a code when unelevated' ($srcRestore -match '(?m)^\s*exit 4\b')
    Assert-That 'the restore signals an unreadable backup with a code' ($srcRestore -match '(?m)^\s*exit 3\b')
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
Write-Host '    All safety checks passed, including the three REFUSALS proved able'
Write-Host '    to fire: a forbidden service, a lockout-risk service, and a plan'
Write-Host '    that would strand a dependency.'
Write-Host ''
exit 0
