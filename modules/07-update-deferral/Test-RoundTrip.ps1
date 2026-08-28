<#
.SYNOPSIS
    Prove the undo by executing it: apply a 3-month hold for real, undo it, and
    compare every value this module can touch.

.DESCRIPTION
    Uses the 3-month hold deliberately. It writes exactly the same five values
    as 6 or 12 - only one number differs - so proving the machinery round-trips
    does not require the longest hold.

    A pass deletes the backups it created. A failure keeps them and prints what
    the apply and the undo actually said.

.NOTES
    Exit codes: 0 PASS   4 unelevated / inconclusive   5 FAIL
#>
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$here    = $PSScriptRoot
$backups = Join-Path $here 'backups'

function Read-AllValues {
    $h = @{}
    foreach ($n in Get-UdfAllValueNames) {
        $e = Get-UdfRegEntry -Key $script:UdfPolicyKey -Name $n
        $h[$n] = if ($e.existed) { "present:$($e.value)" } else { 'absent' }
    }
    $h
}

function Compare-Snapshots {
    param($A, $B)
    $moved = @()
    foreach ($n in Get-UdfAllValueNames) {
        if ($A[$n] -ne $B[$n]) { $moved += ("{0}: {1} -> {2}" -f $n, $A[$n], $B[$n]) }
    }
    $moved
}

Write-Host ""
Write-Host "  Round trip - apply for real, undo, compare"
Write-Host "  --------------------------------------------------------------------------"

if (-not (Test-UdfElevated)) {
    Write-Host "    This proof writes under HKLM and needs administrator rights."
    Write-Host "    Exit code 4."
    exit 4
}

$before = @(Get-UdfBackups -Directory $backups | ForEach-Object { $_.FullName })

# --- A ---------------------------------------------------------------------
Write-Host ""
Write-Host "    [A] reading every value this module can touch ..."
$A = Read-AllValues
$keyExistedBefore = Test-Path $script:UdfPolicyKey
Write-Host ("        {0} values recorded; policy key exists: {1}" -f $A.Count, $keyExistedBefore)

# --- B ---------------------------------------------------------------------
Write-Host ""
Write-Host "    [B] applying the 3-month hold for real ..."
$applyOut = & powershell.exe -ExecutionPolicy Bypass -NoProfile -File (Join-Path $here 'Set-UpdateDeferral.ps1') -Months 3 -Force -Tag '~prerestore' 2>&1 | Out-String
$applyExit = $LASTEXITCODE

if ($applyExit -eq 4) {
    Write-Host "        the apply had nothing to do."
    Write-Host ""
    Write-Host "    INCONCLUSIVE - nothing moved, so nothing was proved."
    Write-Host "    A hold is already applied. Undo it first (launcher 5), then re-run."
    Write-Host "    Exit code 4."
    exit 4
}
if ($applyExit -ne 0) {
    Write-Host ("        the apply exited {0}, which is not success." -f $applyExit)
    Write-Host $applyOut
    Write-Host "    Exit code 5."
    exit 5
}

$B = Read-AllValues
$movedAB = Compare-Snapshots -A $A -B $B
Write-Host ("        values that moved between A and B: {0}" -f $movedAB.Count)
foreach ($m in $movedAB) { Write-Host ("          {0}" -f $m) }

if ($movedAB.Count -eq 0) {
    Write-Host ""
    Write-Host "    INCONCLUSIVE - the apply reported success but nothing moved."
    Write-Host "    Exit code 4."
    exit 4
}

# --- C ---------------------------------------------------------------------
Write-Host ""
Write-Host "    [C] undoing ..."
$undoOut = & powershell.exe -ExecutionPolicy Bypass -NoProfile -File (Join-Path $here 'Restore-UpdateDeferral.ps1') 2>&1 | Out-String
$undoExit = $LASTEXITCODE
if ($undoExit -ne 0) {
    Write-Host ("        the undo exited {0}, which is not success." -f $undoExit)
    Write-Host $undoOut
    Write-Host "    Exit code 5."
    exit 5
}

$C = Read-AllValues
$movedAC = Compare-Snapshots -A $A -B $C
$keyExistsAfter = Test-Path $script:UdfPolicyKey

Write-Host ""
Write-Host "  Result"
Write-Host "  --------------------------------------------------------------------------"

$fail = $false
if ($movedAC.Count -ne 0) {
    $fail = $true
    Write-Host ("    FAIL - {0} value(s) did not come back:" -f $movedAC.Count)
    foreach ($m in $movedAC) { Write-Host ("      {0}" -f $m) }
}
if ($keyExistedBefore -ne $keyExistsAfter) {
    $fail = $true
    Write-Host ("    FAIL - the policy key existed={0} before and existed={1} after." -f $keyExistedBefore, $keyExistsAfter)
    Write-Host "           Absent and present-but-empty are different states."
}

if ($fail) {
    Write-Host ""
    Write-Host "    Backups kept for inspection."
    Write-Host "    --- what the apply said ---"; Write-Host $applyOut
    Write-Host "    --- what the undo said ----"; Write-Host $undoOut
    Write-Host "    Exit code 5."
    exit 5
}

Write-Host "    PASS - every value came back to exactly where it started,"
Write-Host ("           including the policy key itself (existed={0} before and after)." -f $keyExistedBefore)

# clean up only what this proof created
$after = @(Get-UdfBackups -Directory $backups | ForEach-Object { $_.FullName })
$mine  = @($after | Where-Object { $before -notcontains $_ })
foreach ($f in $mine) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
Write-Host ("           {0} backup file(s) created by this proof were removed." -f $mine.Count)
Write-Host ""
exit 0
