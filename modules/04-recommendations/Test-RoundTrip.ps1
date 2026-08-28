<#
.SYNOPSIS
    Prove the undo works on THIS account, by doing it: apply everything for real,
    undo it, and compare every setting one by one.

.DESCRIPTION
    A rollback that has never been executed is a claim. This executes it.

    State A is read, the changes are applied for real, state B is read, the undo
    is run, state C is read. A and C are then compared field by field - value,
    type, whether the value existed at all, and whether its key existed.

    That last pair matters more here than in most modules. Nearly every setting
    this module manages is ABSENT on a default machine, so applying it creates
    both the value and, for the CloudContent policy settings, the key itself.
    An undo that wrote a zero instead of removing them would leave the account
    looking deliberately configured when it never was.

    On a PASS the net effect on your account is nothing whatsoever.

    Needs NO administrator rights.

.PARAMETER IncludeObserved
    Test all ten settings rather than the five documented ones. Recommended -
    a round trip that exercises more of the module proves more of it.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1 -IncludeObserved
#>

[CmdletBinding()]
param([switch]$IncludeObserved, [switch]$Force)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

Write-Host ''
Write-Host '  Recommendations - round-trip proof'
Write-Host ('  ' + ('=' * 74))
Write-Host '    Applies every change for real, then undoes it, then checks that every'
Write-Host '    setting came back. If it passes, the net effect is nothing.'
Write-Host ("    scope: {0}" -f $(if ($IncludeObserved) { 'all 10 settings' } else { 'the 5 documented settings' }))
Write-Host ''

if (-not $Force) {
    $answer = Read-Host '    Type YES to run it'
    if ($answer -ne 'YES') { Write-Host ''; Write-Host '    Nothing was changed.'; Write-Host ''; return }
}

function Compare-RcStates {
    # Parameters are $Start and $End, NOT $A and $C.
    #
    # PowerShell variable names are CASE-INSENSITIVE. With param($A, $C), the
    # line "$a = $A.registry[$k]" assigns to the very same variable it just read
    # from - $A is destroyed on the first iteration and every row afterwards
    # throws "Cannot index into a null array". The comparison then finds no
    # differences, because it never compares anything, and reports PASS.
    #
    # This exact bug was found and fixed in module 01, and reproduced here from
    # memory of the wrong lesson. Distinct names are the fix; the guard below is
    # the belt to its braces.
    param($Start, $End)

    $diffs = New-Object System.Collections.Generic.List[string]

    if ($null -eq $Start -or $null -eq $Start.registry -or
        $null -eq $End   -or $null -eq $End.registry) {
        $diffs.Add('COMPARISON BROKEN: one of the states had no registry section, so nothing was compared')
        return $diffs
    }

    foreach ($r in (Get-RcAllSettings)) {
        $k  = "$($r.Key)|$($r.Name)"
        $v1 = $Start.registry[$k]
        $v2 = $End.registry[$k]
        if ($null -eq $v1 -or $null -eq $v2) {
            $diffs.Add(("{0}: missing from one of the two readings" -f $r.Name)); continue
        }
        # "absent" and "present with value 0" are different states. This is the
        # comparison the whole module hinges on.
        if ($v1.existed -ne $v2.existed) {
            $diffs.Add(("{0}: existed={1} -> existed={2}" -f $r.Name, $v1.existed, $v2.existed)); continue
        }
        if ($v1.existed -and ([string]$v1.value -ne [string]$v2.value)) {
            $diffs.Add(("{0}: {1} -> {2}" -f $r.Name, $v1.value, $v2.value))
        }
        if ($v1.existed -and ([string]$v1.kind -ne [string]$v2.kind)) {
            $diffs.Add(("{0}: type {1} -> {2}" -f $r.Name, $v1.kind, $v2.kind))
        }
        if ($v1.keyExisted -ne $v2.keyExisted) {
            $diffs.Add(("{0}: key existed={1} -> key existed={2}" -f $r.Name, $v1.keyExisted, $v2.keyExisted))
        }
        # Audit finding 3: when both sides are absent, the CHAIN matters too. If
        # the apply created ancestor keys and the undo removed only the leaf,
        # the nearest existing ancestor differs - a real difference the old
        # leaf-only comparison called a PASS.
        if (-not $v1.existed -and -not $v2.existed) {
            $a1 = if ($v1.PSObject.Properties['existingAncestor']) { [string]$v1.existingAncestor } else { $null }
            $a2 = if ($v2.PSObject.Properties['existingAncestor']) { [string]$v2.existingAncestor } else { $null }
            if ($null -ne $a1 -and $null -ne $a2 -and $a1 -ne $a2) {
                $diffs.Add(("{0}: nearest existing ancestor key changed: {1} -> {2}" -f $r.Name, $a1, $a2))
            }
        }
    }
    $diffs
}

Write-Host ''
$script:PreexistingBackups = @(Get-ChildItem -Path (Join-Path $here 'backups') -Filter 'state_*.json' -File -ErrorAction SilentlyContinue | ForEach-Object Name)
Write-Host '    [A] reading the state before anything happens ...'
$A = Get-RcState

Write-Host '    [B] applying for real ...'
$applyArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $here 'Disable-Recommendations.ps1'),'-Tag','roundtrip')
if ($IncludeObserved) { $applyArgs += '-IncludeObserved' }
$applyOut = & powershell.exe @applyArgs 2>&1
$applyExit = $LASTEXITCODE
$applyText = $applyOut | Out-String
# Exit code 3 = the apply refused for want of a verified backup. Matching the
# word "STOPPING" in the child's output instead produced a false positive in
# module 02: a successful apply was read as a refusal, the undo was skipped, and
# a net-zero test left the machine changed.
if ($applyExit -eq 3) {
    Write-Host ''
    Write-Host '    The apply step refused to run - it could not write a verified backup.'
    Write-Host '    Nothing was changed, so there is nothing to undo. That is the safety'
    Write-Host '    behaviour working, but it means this test cannot complete.'
    Write-Host ''
    return
}
if ($applyExit -eq 4) {
    # Module 02 audit finding 1: without this gate, a round trip on an
    # already-applied machine sailed past "Nothing to do" (which wrote NO
    # backup), ran the real undo against the newest OLD backup, un-applied the
    # machine, and then blamed the undo.
    Write-Host ''
    Write-Host '    INCONCLUSIVE - the settings are already where the apply wants them, so'
    Write-Host '    it changed nothing, wrote no backup, and there is nothing to prove.'
    Write-Host '    The machine was not touched. For a real test, run'
    Write-Host '    "6 - UNDO back to the original.cmd" first, then run this again.'
    Write-Host ''
    return
}
$failedCount = 0
if ($applyText -match 'changed:\s*(\d+),\s*already as wanted:\s*(\d+),\s*failed:\s*(\d+)') {
    Write-Host ("        changed: {0}  already: {1}  failed: {2}" -f $Matches[1], $Matches[2], $Matches[3])
    $failedCount = [int]$Matches[3]
}
$B = Get-RcState
# What moved is read from the machine itself - the A-to-B difference - not
# scraped from the child's stdout. Audit finding 7: $B was captured and never
# used, while the verdict hung on a regex over free text - the exact mechanism
# that had already produced a false result in module 02 and been replaced there.
$movedCount = (Compare-RcStates -Start $A -End $B).Count

Write-Host '    [C] undoing ...'
$restorePath = Join-Path $here 'Restore-Recommendations.ps1'
# -File, with no -Confirm:$false. The restore declares no ConfirmImpact, so
# ShouldProcess never prompts under the default preference and the flag was dead
# weight - and the -Command form it forced (audit finding 16) broke on any
# install path containing an apostrophe, e.g. C:\Users\O'Brien\.
$undoOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $restorePath 2>&1
$undoText = $undoOut | Out-String
if ($undoText -match 'restored:\s*(\d+)\s+skipped:\s*(\d+)\s+failed:\s*(\d+)') {
    Write-Host ("        restored: {0}  skipped: {1}  failed: {2}" -f $Matches[1], $Matches[2], $Matches[3])
}
$C = Get-RcState

Write-Host ''
Write-Host ('  ' + ('-' * 74))
$diffs = Compare-RcStates -Start $A -End $C

if ($failedCount -gt 0) {
    # Audit finding 8: a run where every write FAILED used to fall into the
    # nothing-moved branch and print "INCONCLUSIVE - every setting was already
    # at the value the apply script wanted" - the exact opposite of the truth.
    Write-Host ("    FAIL - the apply step reported {0} failed write(s)." -f $failedCount)
    Write-Host '    Something on this machine is refusing these registry writes. The'
    Write-Host '    round trip cannot prove anything until that is resolved.'
}
elseif ($diffs.Count -eq 0 -and $movedCount -eq 0) {
    # A round trip that moved nothing has not exercised the undo at all.
    Write-Host '    INCONCLUSIVE - nothing moved, so nothing was proved.'
    Write-Host ''
    Write-Host '    Every setting was already at the value the apply script wanted, so it'
    Write-Host '    changed nothing and the undo had nothing to reverse. Both ends of a'
    Write-Host '    journey of zero distance are the same place; that is not evidence.'
    Write-Host ''
    # Audit finding 1 (same class): this used to name "5 - UNDO back to the
    # original.cmd"; in this module 5 is "UNDO everything" and 6 is the original.
    Write-Host '    For a real test, run "6 - UNDO back to the original.cmd" first.'
}
elseif ($diffs.Count -eq 0) {
    Write-Host '    PASS - every setting came back to exactly where it started.'
    Write-Host ("    {0} setting(s) were changed and all {0} came back, including the" -f $movedCount)
    Write-Host '    difference between "set to zero" and "not set at all", and whether'
    Write-Host '    the policy key itself existed.'
    Write-Host ''
    Write-Host '    The net effect of this test on your account is nothing.'
}
else {
    Write-Host ("    FAIL - {0} setting(s) did not come back:" -f $diffs.Count)
    foreach ($d in $diffs) { Write-Host ("      {0}" -f $d) }
    Write-Host ''
    Write-Host '    Do not rely on the undo until this is explained.'
}

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
