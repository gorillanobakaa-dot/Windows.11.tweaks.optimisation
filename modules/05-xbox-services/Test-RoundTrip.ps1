<#
.SYNOPSIS
    Prove the undo works, by doing it: apply for real, undo, compare every
    reading. Needs administrator rights (so does everything it tests).

.PARAMETER Force
    Skip the confirmation prompt.
#>

[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

Write-Host ''
Write-Host '  Xbox services - round-trip proof (apply, undo, compare)'
Write-Host ('  ' + ('=' * 74))

if (-not (Test-XsElevated)) {
    Write-Host '    This proof exercises service configuration, which needs administrator'
    Write-Host '    rights on every side. Run it via the numbered launcher.'
    Write-Host ''
    return
}

if (-not $Force) {
    $answer = Read-Host '    Type YES to run it'
    if ($answer -ne 'YES') { Write-Host ''; Write-Host '    Nothing was changed.'; Write-Host ''; return }
}

function Compare-XsStates {
    # $Start/$End with $v1/$v2 locals - never param($A,$C) with $a/$c lookups:
    # case-insensitive variable names made that comparison pass while comparing
    # nothing, THREE times in this project.
    param($Start, $End)
    $diffs = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Start -or $null -eq $Start.services -or
        $null -eq $End   -or $null -eq $End.services) {
        $diffs.Add('COMPARISON BROKEN: a state was missing its services section; nothing was compared')
        return $diffs
    }
    foreach ($r in $script:XsServices) {
        $v1 = $Start.services.($r.Name)
        $v2 = $End.services.($r.Name)
        if ($null -eq $v1 -or $null -eq $v2) { $diffs.Add(("{0}: missing from a reading" -f $r.Name)); continue }
        if ($v1.existed -ne $v2.existed) { $diffs.Add(("{0}: existed={1} -> existed={2}" -f $r.Name, $v1.existed, $v2.existed)); continue }
        if ($v1.existed -and (($v1.start -as [int]) -ne ($v2.start -as [int]))) {
            $diffs.Add(("{0}: Start {1} -> {2}" -f $r.Name, $v1.start, $v2.start))
        }
    }
    foreach ($t in $script:XsTasks) {
        $k = "$($t.Path)$($t.Name)"
        $v1 = $Start.tasks.$k
        $v2 = $End.tasks.$k
        if ($null -eq $v1 -or $null -eq $v2) { $diffs.Add(("task {0}: missing from a reading" -f $t.Name)); continue }
        if ($v1.existed -ne $v2.existed) { $diffs.Add(("task {0}: existed changed" -f $t.Name)); continue }
        if ($v1.existed -and ($v1.enabled -ne $v2.enabled)) {
            $diffs.Add(("task {0}: enabled {1} -> {2}" -f $t.Name, $v1.enabled, $v2.enabled))
        }
    }
    $diffs
}

$script:PreexistingBackups = @(Get-ChildItem -Path (Join-Path $here 'backups') -Filter 'state_*.json' -File -ErrorAction SilentlyContinue | ForEach-Object Name)

Write-Host ''
Write-Host '    [A] reading the state before anything happens ...'
$A = Get-XsState

Write-Host '    [B] applying for real ...'
$applyOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Disable-XboxServices.ps1') -Tag 'roundtrip' 2>&1
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
    Write-Host '    backup and mutate the machine mid-proof. The module is already'
    Write-Host '    applied: run "4 - UNDO everything.cmd" first, then this again.'
    Write-Host ''
    return
}
if ($applyExit -eq 5) {
    # 5 = completed WITH failures. The backup was written (failures happen
    # after it), so the undo is the SAFE move - run it, and let the A-vs-C
    # comparison say whether the machine came back.
    Write-Host ''
    Write-Host '    WARNING - the apply reported failures (exit 5). Its backup exists,'
    Write-Host '    so the undo will still run to bring the machine back. What the'
    Write-Host '    apply said:'
    $applyOut | ForEach-Object { Write-Host ("      | {0}" -f $_) }
}
elseif ($applyExit -ne 0) {
    # Audit S1: an apply that CRASHES (parse error, killed, missing library)
    # exits with some other code - or $LASTEXITCODE is not even set. With no
    # fresh backup guaranteed, running the undo would restore a STALE backup
    # and mutate the machine mid-proof. Stop, and show the evidence instead
    # of swallowing it.
    Write-Host ''
    Write-Host ("    STOPPING - the apply exited with unexpected code '{0}'. The undo was" -f $applyExit)
    Write-Host '    NOT run: without a guaranteed fresh backup it would restore some'
    Write-Host '    OLDER backup and mutate the machine mid-proof. What the apply said:'
    $applyOut | ForEach-Object { Write-Host ("      | {0}" -f $_) }
    Write-Host ''
    return
}
$B = Get-XsState
$movedCount = (Compare-XsStates -Start $A -End $B).Count
Write-Host ("        readings moved between A and B: {0}" -f $movedCount)

Write-Host '    [C] undoing ...'
$undoOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Restore-XboxServices.ps1') 2>&1
$undoText = $undoOut | Out-String
if ($undoText -match 'restored:\s*(\d+)\s+skipped:\s*(\d+)\s+failed:\s*(\d+)') {
    Write-Host ("        restored: {0}  skipped: {1}  failed: {2}" -f $Matches[1], $Matches[2], $Matches[3])
}
$C = Get-XsState

Write-Host ''
Write-Host ('  ' + ('-' * 74))
$diffs = Compare-XsStates -Start $A -End $C

if ($diffs.Count -eq 0 -and $movedCount -eq 0) {
    Write-Host '    INCONCLUSIVE - nothing moved, so nothing was proved.'
    Write-Host ''
}
elseif ($diffs.Count -eq 0) {
    Write-Host '    PASS - every reading came back to exactly where it started.'
    Write-Host ("    {0} reading(s) moved and every one returned." -f $movedCount)
    Write-Host ''
    Write-Host '    The net effect of this test on your machine is nothing.'
}
else {
    Write-Host ("    FAIL - {0} reading(s) did not come back:" -f $diffs.Count)
    foreach ($d in $diffs) { Write-Host ("      {0}" -f $d) }
    Write-Host ''
    Write-Host '    Do not rely on the undo until this is explained.'
    # Audit M1: the children's own words are the forensics - print them, do
    # not discard them.
    Write-Host ''
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
