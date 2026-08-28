<#
.SYNOPSIS
    Read-only self-test of this module's machinery. Removes nothing.

.DESCRIPTION
    Includes falsifiability checks: the refusals are fed the input they exist
    to reject, and required to reject it. A check that cannot fail proves
    nothing.

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
        if (& $Test) { $script:pass++ }
        else { $script:fail++; Write-Host ("      FAIL  {0}" -f $Name) }
    }
    catch { $script:fail++; Write-Host ("      FAIL  {0}  [threw: {1}]" -f $Name, $_.Exception.Message) }
}

$here      = $PSScriptRoot
$srcCommon = Get-Content (Join-Path $here '_Common.ps1')    -Raw
$srcRemove = Get-Content (Join-Path $here 'Remove-Apps.ps1') -Raw
$srcRestore= Get-Content (Join-Path $here 'Restore-Apps.ps1') -Raw
$srcCheck  = Get-Content (Join-Path $here 'Test-Apps.ps1')  -Raw
$installed = Get-AdInstalled

Write-Host ""
Write-Host "  Safety logic - read only"
Write-Host "  --------------------------------------------------------------------------"

Write-Host "   1. The never-remove list actually refuses (falsifiability)"
foreach ($n in 'Microsoft.SecHealthUI','Microsoft.WindowsStore','Microsoft.WindowsTerminal',
               'Microsoft.HEVCVideoExtension','Microsoft.MicrosoftEdge.Stable','Claude',
               'RealtekSemiconductorCorp.RealtekAudioControl','AppUp.IntelGraphicsExperience') {
    Check ("refuses $n") { $null -ne (Test-AdNeverRemove -Name $n) }
}
Check 'wildcard patterns match'      { $null -ne (Test-AdNeverRemove -Name 'MicrosoftCorporationII.WinAppRuntime.Main.1.8') }
Check 'runtime families are covered' { $null -ne (Test-AdNeverRemove -Name 'Microsoft.VCLibs.140.00') }
Check 'an ordinary bloat app is NOT refused' { $null -eq (Test-AdNeverRemove -Name 'Microsoft.XboxGamingOverlay') }
Check 'an unknown app is NOT refused'        { $null -eq (Test-AdNeverRemove -Name 'Contoso.SomeApp') }

Write-Host "   2. No shipped tier names a protected package"
foreach ($t in 'light','moderate','super') {
    Check ("$t is legal on this machine") { @(Test-AdTierLegal -Tier $t -Installed $installed).Count -eq 0 }
}

Write-Host "   3. A doctored tier IS refused (falsifiability)"
Check 'a NonRemovable package in a tier is caught' {
    # Take a real tier app and pretend Windows marked it NonRemovable.
    $victim = (Get-AdTierApps -Tier 'light')[0].Name
    $fake = @{}
    foreach ($k in $installed.Keys) { $fake[$k] = $installed[$k] }
    $fake[$victim] = [pscustomobject]@{
        Name = $victim; PackageFullName = 'x'; Version = '1'; SignatureKind = 'Store'
        NonRemovable = $true; InstallLocation = 'x'; Publisher = 'x' }
    @(Test-AdTierLegal -Tier 'light' -Installed $fake).Count -ge 1
}
Check 'the refusal names the package' {
    $victim = (Get-AdTierApps -Tier 'light')[0].Name
    $fake = @{}
    foreach ($k in $installed.Keys) { $fake[$k] = $installed[$k] }
    $fake[$victim] = [pscustomobject]@{
        Name = $victim; PackageFullName = 'x'; Version = '1'; SignatureKind = 'Store'
        NonRemovable = $true; InstallLocation = 'x'; Publisher = 'x' }
    (@(Test-AdTierLegal -Tier 'light' -Installed $fake) -join ' ') -match [regex]::Escape($victim)
}

Write-Host "   4. Tiers are cumulative and non-empty"
$L = @(Get-AdTierApps -Tier 'light'); $M = @(Get-AdTierApps -Tier 'moderate'); $S = @(Get-AdTierApps -Tier 'super')
Check 'light is non-empty'        { $L.Count -gt 0 }
Check 'moderate includes light'   { $ln = $L.Name; @($M.Name | Where-Object { $ln -contains $_ }).Count -eq $L.Count }
Check 'super includes moderate'   { $mn = $M.Name; @($S.Name | Where-Object { $mn -contains $_ }).Count -eq $M.Count }
Check 'super is the largest'      { $S.Count -gt $M.Count -and $M.Count -gt $L.Count }
Check 'no duplicate names in super' { ($S.Name | Sort-Object -Unique).Count -eq $S.Count }
Check 'every entry has a What'    { @($S | Where-Object { [string]::IsNullOrWhiteSpace($_.What) }).Count -eq 0 }

Write-Host "   5. Frameworks and resource packages are out of scope by construction"
Check 'the enumerator skips frameworks' { $srcCommon -match 'if \(\$p\.IsFramework -or \$p\.IsResourcePackage\) \{ continue \}' }
Check 'no framework reached the inventory' {
    @($installed.Values | Where-Object { $_.Name -like 'Microsoft.VCLibs*' -or $_.Name -like 'Microsoft.UI.Xaml*' }).Count -eq 0
}

Write-Host "   6. The module never calls a removal reversible"
Check 'the inventory says it is not a backup'   { $srcCommon -match 'INVENTORY, NOT A BACKUP' }
Check 'the record file is named not-restorable' { (Get-AdRemovalRecordPath -Directory 'x') -match 'removed-not-restorable\.json$' }
Check 'the restore calls itself best effort'    { $srcRestore -match 'BEST EFFORT, not an undo' }
Check 'the restore separates Store-only cases'  { $srcRestore -match 'storeOnly' }
Check 'the restore never clears the record'     { $srcRestore -match 'deliberately NOT cleared' }
Check 'the remover records payload survival'    { $srcRemove -match 'payloadStillOnDisk' }

Write-Host "   7. Removal is judged by the machine, not by the absence of an error"
Check 'remove re-queries after removing'  { $srcRemove -match 'still installed after the removal returned success' }
Check 'restore re-queries after register' { $srcRestore -match 'registration returned success but it is not installed' }

Write-Host "   8. The unreadable removal record is preserved, never overwritten"
Check 'unreadable record is moved aside' { $srcCommon -match 'unreadable-' }
Check 'and the caller is told'           { $srcCommon -match 'would not parse; kept it as' }

Write-Host "   9. The come-back caveat cannot be silently dropped"
Check 'caveat helper exists'    { $srcCommon  -match 'function Write-AdComesBackCaveat' }
Check 'the checker prints it'   { $srcCheck   -match 'Write-AdComesBackCaveat' }
Check 'the remover prints it'   { $srcRemove  -match 'Write-AdComesBackCaveat' }
Check 'it names the edition gap'{ $srcCommon  -match 'Enterprise and Education only' }
Check 'it cites the observed reinstall' { $srcCommon -match '2026-08-27 at 16:59' }
Check 'the remover separates established from not' { $srcRemove -match 'NOT ESTABLISHED' }

Write-Host "  10. Provisioned state is reported as UNKNOWN, never as none"
Check 'provisioned reader returns a known flag' { (Get-AdProvisioned).PSObject.Properties.Name -contains 'known' }
Check 'the checker prints UNKNOWN when it cannot read' { $srcCheck -match 'UNKNOWN - could not read it' }
Check 'the remover records unknown rather than done'   { $srcRemove -match 'UNKNOWN     : whether new accounts' }

Write-Host "  11. Exit-code contract (MODULE-STANDARD section 16)"
Check 'remover: 3 = inventory refused' { $srcRemove -match 'exit 3' }
Check 'remover: 4 = nothing to do'     { $srcRemove -match 'exit 4' }
Check 'remover: 5 = failures'          { $srcRemove -match 'exit 5' }
Check 'remover: 6 = illegal tier'      { $srcRemove -match 'exit 6' }
Check 'remover gates on the inventory' { $srcRemove -match 'if \(-not \$invPath\)' }
Check 'remover refuses before writing anything' {
    $iLegal = $srcRemove.IndexOf('exit 6')
    $iInv   = $srcRemove.IndexOf('Save-AdInventory')
    $iLegal -gt 0 -and $iInv -gt 0 -and $iLegal -lt $iInv
}
Check 'restore: 4 and 5 present'       { $srcRestore -match 'exit 4' -and $srcRestore -match 'exit 5' }

Write-Host "  12. The preview needs no administrator rights"
Check 'WhatIf returns before the elevation gate' {
    $iWhatIf = $srcRemove.IndexOf('-WhatIf: ')
    $iElev   = $srcRemove.IndexOf('STOPPING: removing the PROVISIONED copy')
    $iWhatIf -gt 0 -and $iElev -gt 0 -and $iWhatIf -lt $iElev
}

Write-Host "  13. Tag sanitising"
Check 'tag strips separators' { (ConvertTo-AdSafeTag 'a\b/c') -notmatch '[\\/]' }
Check 'tag is capped'         { (ConvertTo-AdSafeTag ('x' * 200)).Length -le 41 }
Check 'empty tag is empty'    { (ConvertTo-AdSafeTag '') -eq '' }

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
if ($fail -gt 0) { Write-Host "    Exit code 5: one or more safety checks FAILED."; exit 5 }
Write-Host "    All safety checks passed, including the refusals proved able to fire:"
Write-Host "    a protected package name, and a package Windows marks NonRemovable."
Write-Host ""
exit 0
