<#
.SYNOPSIS
    Prove the undo of the SETTINGS works, by doing it: apply tier 1 for real,
    undo it, and compare every setting one by one.

.DESCRIPTION
    This tests TIER 1 ONLY - the taskbar button and the policy values. It never
    removes any software; the removals are tier 2, they are not reversible, and
    a test that "proves" an undo by removing 1.3 GB of software would be a
    demolition, not a proof.

    State A is read, the settings are applied for real, state B is read, the
    undo runs, state C is read. A and C are compared field by field - value,
    type, whether the value existed, whether its key existed, and how far up
    the created key chain goes.

    Unelevated, the HKLM policy value is skipped by both the apply and the undo,
    and the comparison still holds for the rest. Elevated, all three settings
    are exercised.

    On a PASS the net effect on your machine is nothing, and the backup files
    the test created are removed.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1
#>

[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

Write-Host ''
Write-Host '  Copilot settings - round-trip proof (tier 1 only, removes nothing)'
Write-Host ('  ' + ('=' * 74))
Write-Host ("    running as administrator : {0}" -f $(if (Test-CpElevated) { 'yes - all 3 settings will be exercised' } else { 'no - the HKLM value will be skipped on both sides' }))
Write-Host ''

if (-not $Force) {
    $answer = Read-Host '    Type YES to run it'
    if ($answer -ne 'YES') { Write-Host ''; Write-Host '    Nothing was changed.'; Write-Host ''; return }
}

function Compare-CpStates {
    # $Start/$End with $v1/$v2 locals. PowerShell variable names are
    # case-insensitive: param($A,$C) with "$a = $A.registry[$k]" destroys $A on
    # the first row and the comparison passes having compared nothing. That
    # exact bug shipped in TWO earlier modules of this project.
    param($Start, $End)
    $diffs = New-Object System.Collections.Generic.List[string]

    if ($null -eq $Start -or $null -eq $Start.registry -or
        $null -eq $End   -or $null -eq $End.registry) {
        $diffs.Add('COMPARISON BROKEN: a state was missing its registry section; nothing was compared')
        return $diffs
    }

    $elevated = Test-CpElevated
    foreach ($r in $script:CpRegistry) {
        if ($r.Key -like 'HKLM*' -and -not $elevated) { continue }   # not exercised unelevated
        $k  = "$($r.Key)|$($r.Name)"
        $v1 = $Start.registry[$k]
        $v2 = $End.registry[$k]
        if ($null -eq $v1 -or $null -eq $v2) { $diffs.Add(("{0}: missing from a reading" -f $r.Name)); continue }
        if ($v1.existed -ne $v2.existed) {
            $diffs.Add(("{0}: existed={1} -> existed={2}" -f $r.Name, $v1.existed, $v2.existed)); continue
        }
        if ($v1.existed -and ([string]$v1.value -ne [string]$v2.value)) {
            $diffs.Add(("{0}: {1} -> {2}" -f $r.Name, $v1.value, $v2.value))
        }
        if ($v1.existed -and ([string]$v1.kind -ne [string]$v2.kind)) {
            $diffs.Add(("{0}: kind {1} -> {2}" -f $r.Name, $v1.kind, $v2.kind))
        }
        if ($v1.keyExisted -ne $v2.keyExisted) {
            $diffs.Add(("{0}: key existed={1} -> key existed={2}" -f $r.Name, $v1.keyExisted, $v2.keyExisted))
        }
        # When both sides are absent the created-key CHAIN matters too.
        if (-not $v1.existed -and -not $v2.existed) {
            $a1 = if ($v1.PSObject.Properties['existingAncestor']) { [string]$v1.existingAncestor } else { $null }
            $a2 = if ($v2.PSObject.Properties['existingAncestor']) { [string]$v2.existingAncestor } else { $null }
            if ($null -ne $a1 -and $null -ne $a2 -and $a1 -ne $a2) {
                $diffs.Add(("{0}: nearest existing ancestor key changed: {1} -> {2}" -f $r.Name, $a1, $a2))
            }
        }
    }
    # Tier 2 must not have moved: this test does not remove software, so any
    # movement there is a defect in this test, not in the machine.
    if ($Start.packages['Microsoft.Copilot'].present -ne $End.packages['Microsoft.Copilot'].present) {
        $diffs.Add('Microsoft.Copilot package presence CHANGED - this test must never do that')
    }
    if ($Start.systemInstall.present -ne $End.systemInstall.present) {
        $diffs.Add('Program Files install presence CHANGED - this test must never do that')
    }
    $diffs
}

$script:PreexistingBackups = @(Get-ChildItem -Path (Join-Path $here 'backups') -Filter 'state_*.json' -File -ErrorAction SilentlyContinue | ForEach-Object Name)

Write-Host ''
Write-Host '    [A] reading the state before anything happens ...'
$A = Get-CpState

Write-Host '    [B] applying the settings for real (no removals) ...'
$applyOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Remove-Copilot.ps1') -Tag 'roundtrip' 2>&1
$applyExit = $LASTEXITCODE
if ($applyExit -eq 3) {
    Write-Host ''
    Write-Host '    The apply step refused - it could not write a verified backup. Nothing'
    Write-Host '    was changed, so there is nothing to undo and this test cannot complete.'
    Write-Host ''
    return
}
if ($applyExit -eq 4) {
    Write-Host ''
    Write-Host '    INCONCLUSIVE - the apply found nothing to do, wrote no backup, and'
    Write-Host '    changed nothing. Running the undo anyway would restore some OLDER'
    Write-Host '    backup and mutate the machine mid-proof - the exact defect this'
    Write-Host '    exit-code contract exists to prevent.'
    Write-Host ''
    Write-Host '    The settings are already applied. Run "4 - UNDO the settings.cmd"'
    Write-Host '    first, then run this proof again.'
    Write-Host ''
    return
}
$B = Get-CpState
$movedCount = (Compare-CpStates -Start $A -End $B).Count
Write-Host ("        readings moved between A and B: {0}" -f $movedCount)

Write-Host '    [C] undoing ...'
$undoOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Restore-Copilot.ps1') 2>&1
$undoText = $undoOut | Out-String
if ($undoText -match 'restored:\s*(\d+)\s+skipped:\s*(\d+)\s+failed:\s*(\d+)') {
    Write-Host ("        restored: {0}  skipped: {1}  failed: {2}" -f $Matches[1], $Matches[2], $Matches[3])
}
$C = Get-CpState

Write-Host ''
Write-Host ('  ' + ('-' * 74))
$diffs = Compare-CpStates -Start $A -End $C

if ($diffs.Count -eq 0 -and $movedCount -eq 0) {
    Write-Host '    INCONCLUSIVE - nothing moved, so nothing was proved.'
    Write-Host ''
    Write-Host '    The settings were already where the apply wanted them, so the undo had'
    Write-Host '    nothing to reverse. For a real test, run "4 - UNDO the settings.cmd"'
    Write-Host '    first, then run this again.'
}
elseif ($diffs.Count -eq 0) {
    Write-Host '    PASS - every exercised setting came back to exactly where it started.'
    Write-Host ("    {0} reading(s) moved and every one came back, including whether the" -f $movedCount)
    Write-Host '    value and its key existed at all, and no software moved.'
    Write-Host ''
    Write-Host '    The net effect of this test on your machine is nothing.'
}
else {
    Write-Host ("    FAIL - {0} reading(s) did not come back:" -f $diffs.Count)
    foreach ($d in $diffs) { Write-Host ("      {0}" -f $d) }
    Write-Host ''
    Write-Host '    Do not rely on the undo until this is explained.'
}

# Clean up the backups this test caused, on PASS only.
if ($diffs.Count -eq 0) {
    $newFiles = @(Get-ChildItem -Path (Join-Path $here 'backups') -Filter 'state_*.json' -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -notin $script:PreexistingBackups })
    foreach ($f in $newFiles) { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue }
    if ($newFiles.Count) { Write-Host ("    cleaned up {0} backup file(s) this test created (original-state.json is never touched)" -f $newFiles.Count) }
} else {
    Write-Host '    NOTE: backup files created during this FAILED test were kept for forensics.'
}
Write-Host ''
