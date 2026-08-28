<#
.SYNOPSIS
    Prove the undo works, by doing it: apply the LIGHT profile for real, undo
    it, and compare every service start type on the machine.

.DESCRIPTION
    Deliberately uses LIGHT, not super. The point is to prove the backup and
    restore machinery round-trips faithfully; doing that with 197 services
    instead of 65 proves nothing extra and leaves a much worse machine if it
    fails halfway.

.PARAMETER Force
    Skip the confirmation prompt.
#>

[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

Write-Host ''
Write-Host '  Services - round-trip proof (LIGHT profile, apply then undo)'
Write-Host ('  ' + ('=' * 74))

if (-not (Test-SvcElevated)) {
    Write-Host '    This proof writes service start types, which needs administrator'
    Write-Host '    rights on every side. Run it via the numbered launcher.'
    Write-Host ''
    return
}

if (-not $Force) {
    $answer = Read-Host '    Type YES to run it'
    if ($answer -ne 'YES') { Write-Host ''; Write-Host '    Nothing was changed.'; Write-Host ''; return }
}

function Compare-SvcStates {
    # $Start/$End with $v1/$v2 locals - never param($A,$C) with $a/$c lookups.
    param($Start, $End)
    $diffs = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Start -or $null -eq $Start.services -or
        $null -eq $End   -or $null -eq $End.services) {
        $diffs.Add('COMPARISON BROKEN: a state was missing its services section; nothing was compared')
        return $diffs
    }
    # Get-SvcEntries, never .PSObject.Properties: a LIVE state holds a
    # hashtable and a state read back from JSON holds a PSCustomObject.
    # Iterating properties on the hashtable yields Count/Keys/Values, so this
    # comparison passed having compared nothing until the self-test caught it.
    foreach ($prop in (Get-SvcEntries -Services $Start.services)) {
        $name = $prop.Name
        $v1 = $prop.Value
        $v2 = Get-SvcEntryByName -Services $End.services -Name $name
        if ($null -eq $v2) { $diffs.Add(("{0}: missing from the second reading" -f $name)); continue }
        if ($v1.existed -ne $v2.existed) { $diffs.Add(("{0}: existed {1} -> {2}" -f $name, $v1.existed, $v2.existed)); continue }
        if ($v1.existed -and (($v1.start -as [int]) -ne ($v2.start -as [int]))) {
            $diffs.Add(("{0}: Start {1} -> {2}" -f $name, $v1.start, $v2.start))
        }
    }
    foreach ($prop in (Get-SvcEntries -Services $End.services)) {
        if ($null -eq (Get-SvcEntryByName -Services $Start.services -Name $prop.Name)) {
            $diffs.Add(("{0}: appeared in the second reading" -f $prop.Name))
        }
    }
    $diffs
}

$script:PreexistingBackups = @(Get-ChildItem -Path (Join-Path $here 'backups') -Filter 'state_*.json' -File -ErrorAction SilentlyContinue | ForEach-Object Name)

Write-Host ''
Write-Host '    [A] reading every service start type before anything happens ...'
$A = Get-SvcState
Write-Host ("        {0} services recorded" -f (Get-SvcEntries -Services $A.services).Count)

Write-Host '    [B] applying the LIGHT profile for real ...'
$applyOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Apply-ServiceProfile.ps1') -Profile light -Force -Tag 'roundtrip' 2>&1
$applyExit = $LASTEXITCODE
if ($applyExit -eq 3) {
    Write-Host ''; Write-Host '    The apply refused - no verified backup. Nothing to undo.'; Write-Host ''
    return
}
if ($applyExit -eq 6) {
    Write-Host ''
    Write-Host '    The apply REFUSED the profile as illegal or unsafe. That is the'
    Write-Host '    safety machinery working. What it said:'
    $applyOut | ForEach-Object { Write-Host ("      | {0}" -f $_) }
    Write-Host ''
    return
}
if ($applyExit -eq 4) {
    Write-Host ''
    Write-Host '    INCONCLUSIVE - the apply found nothing to do and wrote no backup.'
    Write-Host '    The profile is already applied: run "4 - UNDO everything.cmd"'
    Write-Host '    first, then run this proof again.'
    Write-Host ''
    return
}
if ($applyExit -eq 5) {
    Write-Host ''
    Write-Host '    WARNING - the apply reported failures (exit 5). Its backup exists,'
    Write-Host '    so the undo will still run. What the apply said:'
    $applyOut | ForEach-Object { Write-Host ("      | {0}" -f $_) }
}
elseif ($applyExit -ne 0) {
    Write-Host ''
    Write-Host ("    STOPPING - the apply exited with unexpected code '{0}'. The undo was" -f $applyExit)
    Write-Host '    NOT run: without a guaranteed fresh backup it would restore some older'
    Write-Host '    backup and mutate the machine mid-proof. What the apply said:'
    $applyOut | ForEach-Object { Write-Host ("      | {0}" -f $_) }
    Write-Host ''
    return
}

$B = Get-SvcState
$movedCount = (Compare-SvcStates -Start $A -End $B).Count
Write-Host ("        start types that moved between A and B: {0}" -f $movedCount)

Write-Host '    [C] undoing ...'
$undoOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Restore-Services.ps1') 2>&1
$undoText = $undoOut | Out-String
if ($undoText -match 'restored:\s*(\d+)\s+skipped:\s*(\d+)\s+failed:\s*(\d+)') {
    Write-Host ("        restored: {0}  skipped: {1}  failed: {2}" -f $Matches[1], $Matches[2], $Matches[3])
}
$C = Get-SvcState

Write-Host ''
Write-Host ('  ' + ('-' * 74))
$diffs = Compare-SvcStates -Start $A -End $C

if ($diffs.Count -eq 0 -and $movedCount -eq 0) {
    Write-Host '    INCONCLUSIVE - nothing moved, so nothing was proved.'
}
elseif ($diffs.Count -eq 0) {
    Write-Host '    PASS - every service start type came back to exactly where it started.'
    Write-Host ("    {0} start type(s) moved and every one returned." -f $movedCount)
    Write-Host ''
    Write-Host '    The net effect of this test on your machine is nothing.'
}
else {
    Write-Host ("    FAIL - {0} start type(s) did not come back:" -f $diffs.Count)
    foreach ($d in $diffs) { Write-Host ("      {0}" -f $d) }
    Write-Host ''
    Write-Host '    Do not rely on the undo until this is explained.'
    Write-Host '    what the apply said:'
    $applyOut | ForEach-Object { Write-Host ("      | {0}" -f $_) }
    Write-Host '    what the undo said:'
    $undoOut | ForEach-Object { Write-Host ("      | {0}" -f $_) }
}

if ($diffs.Count -eq 0) {
    $newFiles = @(Get-ChildItem -Path (Join-Path $here 'backups') -Filter 'state_*.json' -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -notin $script:PreexistingBackups })
    foreach ($f in $newFiles) { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue }
    if ($newFiles.Count) { Write-Host ("    cleaned up {0} backup file(s) this test created (original-state.json is never touched)" -f $newFiles.Count) }
} else {
    Write-Host '    NOTE: backup files created during this FAILED test were kept for forensics.'
}
Write-Host ''
