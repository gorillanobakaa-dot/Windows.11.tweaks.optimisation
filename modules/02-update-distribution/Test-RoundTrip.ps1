<#
.SYNOPSIS
    Prove the undo works on THIS machine, by doing it: apply everything for real,
    undo it, and compare every setting one by one.

.DESCRIPTION
    A rollback that has never been executed is a claim. This executes it.

    State A is read, the changes are applied for real, state B is read, the undo
    is run, state C is read. Then A and C are compared field by field. A PASS
    means every setting came back to exactly where it started, including the
    difference between "set to zero" and "not set at all", which for this module
    is the case most likely to go wrong.

    On a PASS the net effect on your machine is nothing whatsoever.

    On a FAIL it prints which fields differ, and you should not trust the undo
    until that is explained.

    NEEDS ADMINISTRATOR RIGHTS. It asks before starting, because it is a real
    change while it runs.

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
Write-Host '  Update distribution - round-trip proof'
Write-Host ('  ' + ('=' * 74))
Write-Host '    This applies every change for real, then undoes it, then checks that'
Write-Host '    every setting came back. If it passes, the net effect is nothing.'
Write-Host ''

if (-not (Test-UdElevated)) {
    Write-Host '    This needs administrator rights.'
    Write-Host '    Close this and double-click "6 - Prove the undo works.cmd" instead.'
    Write-Host ''
    return
}

if (-not $Force) {
    $answer = Read-Host '    Type YES to run it'
    if ($answer -ne 'YES') {
        Write-Host ''
        Write-Host '    Nothing was changed.'
        Write-Host ''
        return
    }
}

function Compare-UdStates {
    # $Start/$End with $v1/$v2 locals, NOT $A/$C with $a/$c. PowerShell variable
    # names are case-insensitive, so "$a = $A.registry[$k]" assigns to the very
    # variable it reads: $A is destroyed on the first row, every later row throws
    # "Cannot index into a null array", the diffs list stays empty - and the test
    # prints PASS having compared nothing. This module shipped with that bug and
    # produced exactly that false PASS on a real elevated run, AFTER the same bug
    # had already been found and fixed twice elsewhere in this project.
    param($Start, $End)
    $diffs = New-Object System.Collections.Generic.List[string]

    if ($null -eq $Start -or $null -eq $Start.registry -or
        $null -eq $End   -or $null -eq $End.registry) {
        $diffs.Add('COMPARISON BROKEN: a state was missing its registry section; nothing was compared')
        return $diffs
    }

    foreach ($r in $script:UdRegistry) {
        $k = "$($r.Key)|$($r.Name)"
        $v1 = $Start.registry[$k]; $v2 = $End.registry[$k]
        if ($null -eq $v1 -or $null -eq $v2) { $diffs.Add(("{0}: missing from a reading" -f $r.Name)); continue }
        # "absent" and "present with value 0" are different states and this is
        # the whole reason this module needed its own restore logic.
        if ($v1.existed -ne $v2.existed) {
            $diffs.Add(("{0}: existed={1} -> existed={2}" -f $r.Name, $v1.existed, $v2.existed))
            continue
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
    }

    foreach ($f in $script:UdFirewallRules) {
        $v1 = $Start.firewall[$f.Name]; $v2 = $End.firewall[$f.Name]
        if ($null -eq $v1 -or $null -eq $v2) { $diffs.Add(("{0}: missing from a reading" -f $f.Name)); continue }
        if ($v1.present -ne $v2.present) { $diffs.Add(("{0}: present={1} -> present={2}" -f $f.Name, $v1.present, $v2.present)); continue }
        if ($v1.enabled -ne $v2.enabled) { $diffs.Add(("{0}: enabled={1} -> enabled={2}" -f $f.Name, $v1.enabled, $v2.enabled)) }
        if ([string]$v1.profile -ne [string]$v2.profile) { $diffs.Add(("{0}: profile {1} -> {2}" -f $f.Name, $v1.profile, $v2.profile)) }
    }

    # Services are not touched by this module, so any change here is a finding
    # about the module, not about the machine.
    foreach ($n in @('DoSvc', 'BITS', 'wuauserv', 'UsoSvc')) {
        $v1 = $Start.services[$n]; $v2 = $End.services[$n]
        if ($null -eq $v1 -or $null -eq $v2) { $diffs.Add(("service {0}: missing from a reading" -f $n)); continue }
        if ($v1.present -ne $v2.present)     { $diffs.Add(("service {0}: present {1} -> {2}" -f $n, $v1.present, $v2.present)); continue }
        if ($v1.startType -ne $v2.startType) { $diffs.Add(("service {0}: start type {1} -> {2}  (this module must not change this)" -f $n, $v1.startType, $v2.startType)) }
    }

    $diffs
}

Write-Host ''
$script:PreexistingBackups = @(Get-ChildItem -Path (Join-Path $here 'backups') -Filter 'state_*.json' -File -ErrorAction SilentlyContinue | ForEach-Object Name)
Write-Host '    [A] reading the state before anything happens ...'
$A = Get-UdState

Write-Host '    [B] applying for real ...'
$applyOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Disable-PeerDistribution.ps1') -Tag 'roundtrip' 2>&1
$applyExit = $LASTEXITCODE
$applyText = $applyOut | Out-String
# Exit code 3 means the apply refused for want of a verified backup.
#
# This used to be "if ($applyText -match 'STOPPING')" - searching the child's
# free text for a word. It produced a false positive on a run where the backup
# had actually SUCCEEDED and all three settings had been applied: the round trip
# concluded nothing had happened, skipped the undo, and left the machine changed
# by a test whose whole promise is that it changes nothing. Text in output is a
# message for a human; an exit code is a signal for a program.
if ($applyExit -eq 3) {
    Write-Host ''
    Write-Host '    The apply step refused to run - it could not write a verified backup.'
    Write-Host '    Nothing was changed, so there is nothing to undo. That is the safety'
    Write-Host '    behaviour working, but it means this test cannot complete.'
    Write-Host ''
    return
}
if ($applyExit -eq 4) {
    # Audit finding: without this, a round trip on an already-applied machine
    # sailed past "Nothing to do" (which wrote NO backup), ran the real undo
    # against the newest OLD backup, un-applied the machine, and then reported
    # FAIL against an undo that had worked perfectly.
    Write-Host ''
    Write-Host '    INCONCLUSIVE - the settings are already where the apply wants them,'
    Write-Host '    so the apply changed nothing, wrote no backup, and there is nothing'
    Write-Host '    for the undo to prove against. The machine was not touched.'
    Write-Host ''
    Write-Host '    For a real test, go back to the original state first:'
    Write-Host '        double-click "5 - UNDO back to the original.cmd"'
    Write-Host '    then run this again.'
    Write-Host ''
    return
}
$B = Get-UdState

$applied = 0
foreach ($r in $script:UdRegistry) {
    $e = $B.registry["$($r.Key)|$($r.Name)"]
    if ($e.existed -and [int]$e.value -eq $r.Target) { $applied++ }
}
foreach ($f in $script:UdFirewallRules) {
    $e = $B.firewall[$f.Name]
    if ($e.present -and $e.enabled -eq $f.Target) { $applied++ }
}
Write-Host ("        applied state reached on {0} of {1} settings" -f $applied, ($script:UdRegistry.Count + $script:UdFirewallRules.Count))
# What actually MOVED is the A-to-B difference, read from the machine itself.
# The previous proxy - "did the value exist in A" - made the PASS verdict
# unreachable forever on any machine where DODownloadMode had been configured
# to some other value before this module arrived (audit finding: a 3->0->3
# round trip that restored perfectly printed INCONCLUSIVE, and its own advice
# could never change that).
$movedDiffs = Compare-UdStates -Start $A -End $B
$movedCount = $movedDiffs.Count

Write-Host '    [C] undoing ...'
# -Command rather than -File: under -File, PowerShell hands everything after the
# script path over as plain strings, so -Confirm:$false arrives as the text
# "$false" and the child dies on a type conversion. Proved by running it.
$restorePath = Join-Path $here 'Restore-UpdateDistribution.ps1'
$undoOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '$restorePath' -Confirm:`$false" 2>&1
$undoText = $undoOut | Out-String
if ($undoText -match 'restored:\s*(\d+)\s+skipped:\s*(\d+)\s+failed:\s*(\d+)') {
    Write-Host ("        restored: {0}  skipped: {1}  failed: {2}" -f $Matches[1], $Matches[2], $Matches[3])
}
$C = Get-UdState

Write-Host ''
Write-Host ('  ' + ('-' * 74))
$diffs = Compare-UdStates -Start $A -End $C
$total = $script:UdRegistry.Count + $script:UdFirewallRules.Count
if ($diffs.Count -eq 0 -and $movedCount -eq 0) {
    # Already applied before the test started: the apply step had nothing to do,
    # so the undo had nothing to reverse, so nothing was tested. A pass here is
    # a journey of zero distance, and reporting it as proof would be dishonest.
    Write-Host '    INCONCLUSIVE - nothing moved, so nothing was proved.'
    Write-Host ''
    Write-Host '    The settings were already where the apply script wanted them, so it'
    Write-Host '    changed nothing and the undo had nothing to reverse. The comparison'
    Write-Host '    passed because both ends of a journey of zero distance are the same'
    Write-Host '    place. That is not evidence that the undo works.'
    Write-Host ''
    Write-Host '    For a real test, go back to the original state first:'
    Write-Host '        double-click "5 - UNDO back to the original.cmd"'
    Write-Host '    then run this again.'
}
elseif ($diffs.Count -eq 0) {
    Write-Host '    PASS - every setting came back to exactly where it started.'
    Write-Host '    The net effect of this test on your machine is nothing.'
    Write-Host ("    {0} reading(s) moved between A and B and every one came back," -f $movedCount)
    Write-Host '    including the difference between "set to zero" and "not set at all".'
} else {
    Write-Host ("    FAIL - {0} setting(s) did not come back:" -f $diffs.Count)
    foreach ($d in $diffs) { Write-Host ("      {0}" -f $d) }
    Write-Host ''
    Write-Host '    Do not rely on the undo until this is explained.'
}
Write-Host ''
Write-Host '    Machine is left in the state it started in (assuming PASS above).'

# The backups this test caused are litter once it has passed: its net effect is
# nothing, and the newest of them records an intermediate (applied) state that a
# later "UNDO everything" would faithfully restore, undoing nothing while
# reporting success (audit finding). On a FAIL they are kept for forensics.
if ($diffs.Count -eq 0) {
    $newFiles = @(Get-ChildItem -Path (Join-Path $here 'backups') -Filter 'state_*.json' -File -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -notin $script:PreexistingBackups })
    foreach ($f in $newFiles) { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue }
    if ($newFiles.Count) { Write-Host ("    cleaned up {0} backup file(s) this test created (original-state.json is never touched)" -f $newFiles.Count) }
} else {
    Write-Host '    NOTE: backup files created during this FAILED test were kept for'
    Write-Host '    forensics. The newest may record a partly-applied state - do not'
    Write-Host '    restore from it blindly.'
}

Write-Host ''
