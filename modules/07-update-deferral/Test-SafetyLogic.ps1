<#
.SYNOPSIS
    Read-only self-test of this module's machinery. Changes nothing on the
    machine; it exercises the logic in memory and reads this module's own source.

.DESCRIPTION
    Includes falsifiability checks - refusals fed the input they are supposed to
    reject, and required to reject it. A check that cannot fail proves nothing.

.NOTES
    Exit codes: 0 all passed   5 one or more failed
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$pass = 0; $fail = 0
function Check {
    param([string]$Name, [scriptblock]$Test)
    try {
        $r = & $Test
        if ($r) { $script:pass++ }
        else { $script:fail++; Write-Host ("      FAIL  {0}" -f $Name) }
    }
    catch { $script:fail++; Write-Host ("      FAIL  {0}  [threw: {1}]" -f $Name, $_.Exception.Message) }
}

$here      = $PSScriptRoot
$srcCommon = Get-Content (Join-Path $here '_Common.ps1') -Raw
$srcApply  = Get-Content (Join-Path $here 'Set-UpdateDeferral.ps1') -Raw
$srcUndo   = Get-Content (Join-Path $here 'Restore-UpdateDeferral.ps1') -Raw
$srcCheck  = Get-Content (Join-Path $here 'Test-UpdateDeferral.ps1') -Raw
$srcTrip   = Get-Content (Join-Path $here 'Test-RoundTrip.ps1') -Raw

Write-Host ""
Write-Host "  Safety logic - read only"
Write-Host "  --------------------------------------------------------------------------"

Write-Host "   1. The hold table is exactly what the owner asked for"
Check '3/6/12 are the only holds'        { ((@($script:UdfHolds.Keys) | Sort-Object) -join ',') -eq '3,6,12' }
Check '3 months = 90 days'               { $script:UdfHolds[3]  -eq 90 }
Check '6 months = 180 days'              { $script:UdfHolds[6]  -eq 180 }
Check '12 months = 365 days'             { $script:UdfHolds[12] -eq 365 }
Check '365 is the documented maximum'    { $script:UdfHolds[12] -le 365 }

Write-Host "   2. The plan refuses what it cannot do (falsifiability)"
Check 'rejects 1 month'   { try { [void](Get-UdfPlan -Months 1);  $false } catch { $true } }
Check 'rejects 24 months' { try { [void](Get-UdfPlan -Months 24); $false } catch { $true } }
Check 'rejects 0'         { try { [void](Get-UdfPlan -Months 0);  $false } catch { $true } }
Check 'accepts 3'         { @(Get-UdfPlan -Months 3).Count  -gt 0 }
Check 'accepts 6'         { @(Get-UdfPlan -Months 6).Count  -gt 0 }
Check 'accepts 12'        { @(Get-UdfPlan -Months 12).Count -gt 0 }

Write-Host "   3. The pin is read from the machine, never hardcoded"
$live = Get-UdfInstalledRelease
$plan3 = Get-UdfPlan -Months 3
$pin = ($plan3 | Where-Object { $_.Name -eq 'TargetReleaseVersionInfo' }).Value
Check 'pin equals the installed release'   { "$pin" -eq "$live" }
Check 'no release literal in _Common.ps1'  { $srcCommon -notmatch "'2[0-9]H[12]'" }
Check 'no release literal in the applier'  { $srcApply  -notmatch "'2[0-9]H[12]'" }
Check 'plan throws when release unreadable' {
    # Simulate by checking the guard exists and names the refusal
    $srcCommon -match 'Refusing to guess a release to pin to'
}

Write-Host "   4. Quality (security) updates are never touched"
foreach ($forbidden in 'DeferQualityUpdates','DeferQualityUpdatesPeriodInDays','PauseQualityUpdatesStartTime') {
    Check ("plan never writes $forbidden") {
        $names = @(3,6,12) | ForEach-Object { (Get-UdfPlan -Months $_) | ForEach-Object { $_.Name } }
        $names -notcontains $forbidden
    }
    Check ("allow-list excludes $forbidden") { (Get-UdfAllValueNames) -notcontains $forbidden }
}
Check 'no quality value is written anywhere in source' {
    ($srcApply + $srcUndo + $srcCommon) -notmatch 'Set-UdfValue\s+-Name\s+.DeferQuality'
}

Write-Host "   5. The expiring mechanisms are refused"
foreach ($forbidden in 'PauseFeatureUpdatesStartTime','NoAutoUpdate','AUOptions') {
    Check ("allow-list excludes $forbidden") { (Get-UdfAllValueNames) -notcontains $forbidden }
}
Check 'the applier explains why pause is refused' { $srcApply -match 'a pause expires in 35 days' }

Write-Host "   6. The allow-list covers everything any plan writes"
Check 'every planned name is on the allow-list' {
    $allowed = Get-UdfAllValueNames
    $missing = @()
    foreach ($m in 3,6,12) {
        foreach ($p in (Get-UdfPlan -Months $m)) { if ($allowed -notcontains $p.Name) { $missing += $p.Name } }
    }
    $missing.Count -eq 0
}
Check 'allow-list has exactly 5 names' { @(Get-UdfAllValueNames).Count -eq 5 }

Write-Host "   7. Backup shape validation rejects damaged input (falsifiability)"
Check 'rejects null'                 { -not (Test-UdfStateShape $null) }
Check 'rejects an empty object'      { -not (Test-UdfStateShape ([pscustomobject]@{})) }
Check 'rejects missing values'       { -not (Test-UdfStateShape ([pscustomobject]@{ schemaVersion=1; takenAt='x'; displayVersion='25H2' })) }
Check 'rejects a partial values map' {
    $partial = [pscustomobject]@{ schemaVersion=1; takenAt='x'; displayVersion='25H2'
                                  values=[pscustomobject]@{ TargetReleaseVersion=@{} } }
    -not (Test-UdfStateShape $partial)
}
Check 'accepts a complete state'     { Test-UdfStateShape (Get-UdfState) }

Write-Host "   8. Internal snapshots cannot be produced by a user tag"
Check 'safe tag strips the tilde'       { (ConvertTo-UdfSafeTag '~prerestore') -notmatch '~' }
Check 'safe tag strips path separators' { (ConvertTo-UdfSafeTag 'a\b/c') -notmatch '[\\/]' }
Check 'safe tag caps the length'        { (ConvertTo-UdfSafeTag ('x' * 200)).Length -le 41 }
Check 'empty tag yields empty string'   { (ConvertTo-UdfSafeTag '') -eq '' }
Check 'the exclusion filter is derived, not duplicated' {
    $srcUndo -match 'Get-UdfRestoreCandidates' -and $srcUndo -notmatch "notmatch\s+'_~prerestore"
}

Write-Host "   9. Restore validates against the module, not the backup"
Check 'restore iterates the allow-list' { $srcCommon -match 'foreach \(\$name in Get-UdfAllValueNames\)' }
Check 'restore rejects unknown value kinds' { $srcCommon -match "unknown value kind" }
Check 'restore can return a value to ABSENT' { $srcCommon -match 'Remove-UdfValue -Name \$name' }
Check 'key removal respects other writers' { $srcCommon -match 'something else has written to it' }
Check 'key removal counts the default value' { $srcCommon -match 'GetValueNames' }

Write-Host "  10. The Home caveat cannot be silently dropped"
Check 'caveat helper exists'            { $srcCommon -match 'function Write-UdfHomeCaveat' }
Check 'the checker prints it'           { $srcCheck -match 'Write-UdfHomeCaveat' }
Check 'the applier prints it'           { $srcApply -match 'Write-UdfHomeCaveat' }
Check 'caveat names the edition gap'    { $srcCommon -match 'Home is NOT in that list' }
Check 'applier separates established from not' { $srcApply -match 'NOT ESTABLISHED' }

Write-Host "  11. Exit-code contract (MODULE-STANDARD section 16)"
Check 'applier: 3 = backup refused'      { $srcApply -match 'exit 3' }
Check 'applier: 4 = nothing to do'       { $srcApply -match 'exit 4' }
Check 'applier: 5 = failures'            { $srcApply -match 'exit 5' }
Check 'applier gates on backup being null' { $srcApply -match 'if \(-not \$backupPath\)' }
Check 'undo: 3 = snapshot refused'       { $srcUndo  -match 'exit 3' }
Check 'undo: 4 = nothing usable'         { $srcUndo  -match 'exit 4' }
Check 'undo: 5 = failures'               { $srcUndo  -match 'exit 5' }
Check 'round trip gates on the apply exit code' { $srcTrip -match '\$applyExit -ne 0' }
Check 'round trip gates on the undo exit code'  { $srcTrip -match '\$undoExit -ne 0' }
Check 'round trip treats no-movement as inconclusive' { $srcTrip -match 'INCONCLUSIVE' }
Check 'round trip compares the key existence too'     { $srcTrip -match 'keyExistedBefore -ne \$keyExistsAfter' }

Write-Host "  12. The module writes to exactly one key"
Check 'only one policy key is defined'  { $script:UdfPolicyKey -eq 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' }
Check 'the writer hardcodes that key'   { $srcCommon -match 'New-ItemProperty -Path \$script:UdfPolicyKey' }
Check 'no writes to the client key'     { $srcCommon -notmatch 'Set-ItemProperty[^\r\n]*UdfClientKey' }
Check 'no writes to the GWX key'        { ($srcCommon + $srcApply + $srcUndo) -notmatch 'Set-ItemProperty[^\r\n]*GWX' }
Check 'safeguard holds are read only'   { $srcCommon -match 'function Get-UdfSafeguardHold' -and $srcCommon -notmatch 'Set-.*GStatus' }

Write-Host "  13. The ceiling is surfaced, not hidden"
Check 'checker names the 24-month support window' { $srcCheck -match '24 months of support' }
Check 'checker names the 60-day forced update'    { $srcCheck -match '60 days past end of service' }
Check 'checker calls a hold a delay, not a refusal' { $srcCheck -match 'a delay, never a refusal' }

Write-Host "  14. The launchers can actually start the scripts"
$launcherFiles = Get-ChildItem $here -Filter '*.cmd' -File
Check 'arguments live OUTSIDE the -File quotes in every launcher' {
    $bad = foreach ($c in $launcherFiles) { if ((Get-Content $c.FullName -Raw) -match '-File "[^"]*\.ps1 [^"]*"') { $c.Name } }
    @($bad).Count -eq 0
}
Check 'no launcher starts a script with -Command "& ..."' {
    $bad = foreach ($c in $launcherFiles) { if ((Get-Content $c.FullName -Raw) -match '-Command "&') { $c.Name } }
    @($bad).Count -eq 0
}
Check 'every script a launcher names exists on disk' {
    $missing = foreach ($c in $launcherFiles) {
        foreach ($m in [regex]::Matches((Get-Content $c.FullName -Raw), '-File "%~dp0([^"]*?\.ps1)')) {
            if (-not (Test-Path (Join-Path $here $m.Groups[1].Value))) { $c.Name }
        }
    }
    @($missing).Count -eq 0
}

Write-Host ""
Write-Host "  --------------------------------------------------------------------------"
Write-Host ("    checks passed : {0}" -f $pass)
Write-Host ("    checks failed : {0}" -f $fail)
Write-Host ""
if ($fail -gt 0) {
    Write-Host "    Exit code 5: one or more safety checks FAILED."
    exit 5
}
Write-Host "    All safety checks passed, including the refusals proved able to fire:"
Write-Host "    an unsupported hold length, a damaged backup, and a tag trying to"
Write-Host "    impersonate an internal snapshot."
Write-Host ""
exit 0
