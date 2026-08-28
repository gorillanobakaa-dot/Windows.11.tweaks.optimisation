<#
.SYNOPSIS
    Prove the rollback works, on this machine, before you rely on it.

.DESCRIPTION
    A backup is a promise. This script makes the machine keep it, in front of you:

      1. records the exact state of all 20 managed settings   (state A)
      2. runs Disable-VisualEffects.ps1 for real
      3. records the state again and confirms something actually changed (state B)
      4. runs Restore-VisualEffects.ps1 for real
      5. records the state a third time (state C) and compares it to state A,
         setting by setting

    A PASS means state C is identical to state A: the round trip is lossless and
    the undo genuinely undoes. A FAIL names the exact settings that did not come
    back, which is precisely the information you would want before trusting any
    of this on a machine you care about.

    THIS SCRIPT CHANGES YOUR MACHINE AND THEN CHANGES IT BACK. Net effect on a
    PASS is nothing. It is still a real change while it runs, so it asks for
    confirmation unless you pass -Confirm:$false.

    Per-user only. No administrator rights needed or requested. The backups it
    creates are kept, and the pristine original-state.json is created on the first
    run as usual, so even a failure mid-way leaves you a documented way home.

.PARAMETER Layers
    Restrict the test to particular layers, exactly as Disable-VisualEffects.ps1
    does. Default is all of them, which is the meaningful test.

.PARAMETER KeepBackups
    Leave the state files this test creates in .\backups\. They are kept by
    default; use -KeepBackups:$false to remove the ones this run created
    (original-state.json is never removed).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1
    Run the full proof, with a confirmation prompt first.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1 -Confirm:$false
    Run it without prompting - useful in a scripted check.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1 -Layers Shell
    Prove the round trip for the shell settings only.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('Legacy','Modern','Shell','DWM','All')]
    [string[]]$Layers = @('All'),
    [switch]$KeepBackups = $true
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')
$backupDir = Join-Path $here 'backups'

function Compare-VfxStates {
    # NOTE: PowerShell variable names are CASE-INSENSITIVE. Naming a local $c
    # while a parameter is named $C overwrites the parameter on the first
    # iteration, and every later lookup indexes into nothing. The locals below
    # are deliberately named so they cannot collide with $Start / $End.
    param($Start, $End)
    $diffs = @()
    foreach ($name in $script:VfxEffects.Keys) {
        $v1 = $Start.spi[$name]; $v2 = $End.spi[$name]
        if ("$v1" -ne "$v2") { $diffs += [pscustomobject]@{ Setting=$name; Before="$v1"; After="$v2" } }
    }
    foreach ($k in 'DragFullWindows','MenuShowDelay') {
        $v1 = $Start.spi[$k]; $v2 = $End.spi[$k]
        if ("$v1" -ne "$v2") { $diffs += [pscustomobject]@{ Setting=$k; Before="$v1"; After="$v2" } }
    }
    foreach ($r in $script:VfxRegistry) {
        $key = "$($r.Key)|$($r.Name)"
        $e1 = $Start.registry[$key]; $e2 = $End.registry[$key]
        $av = if ($e1) { $e1.value } else { $null }
        $cv = if ($e2) { $e2.value } else { $null }
        $as = if ($null -eq $av) { '<unset>' } else { "$av" }
        $cs = if ($null -eq $cv) { '<unset>' } else { "$cv" }
        if ($as -ne $cs) { $diffs += [pscustomobject]@{ Setting=$r.Name; Before=$as; After=$cs } }
    }
    # The shared legacy preference mask covers bits this module does not
    # enumerate. Comparing it is the only way this test can notice a loss it was
    # never designed to look for.
    if ("$($Start.userPreferencesMask)" -ne "$($End.userPreferencesMask)") {
        $diffs += [pscustomobject]@{
            Setting = 'UserPreferencesMask (shared legacy byte mask)'
            Before  = "$($Start.userPreferencesMask)"
            After   = "$($End.userPreferencesMask)"
        }
    }
    return $diffs
}

function Get-DifferenceCount { param($X, $Y) @(Compare-VfxStates -Start $X -End $Y).Count }

Write-Host ''
Write-Host '  ROUND-TRIP PROOF - visual effects module'
Write-Host '  This will change settings and then change them back.'
Write-Host ('  ' + ('-' * 72))

if (-not $PSCmdlet.ShouldProcess('this user profile', 'apply visual-effect changes and then restore them')) {
    Write-Host '  Cancelled. Nothing was changed.'
    Write-Host ''
    return
}

$created = @()
$before = (Get-VfxBackups -BackupDir $backupDir | ForEach-Object { $_.Name })

# ---------------------------------------------------------------- state A ---
Write-Host ''
Write-Host '  [1/5] recording starting state (A)'
$A = Get-VfxState
$stateAPath = Join-Path $backupDir ("roundtrip_A_{0}.json" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
$A | ConvertTo-Json -Depth 6 | Set-Content $stateAPath -Encoding UTF8
$created += $stateAPath
Write-Host "        saved: $(Split-Path $stateAPath -Leaf)"

# ---------------------------------------------------------------- apply ----
Write-Host ''
Write-Host '  [2/5] running Disable-VisualEffects.ps1 for real'
$disable = Join-Path $here 'Disable-VisualEffects.ps1'
# Capture rather than discard: swallowing the streams would hide the very
# failure messages this proof exists to catch.
$applyLog = & $disable -Layers $Layers -Tag 'roundtrip' -Confirm:$false 2>&1 | Out-String
$applyBad = ($applyLog -split "`n") | Where-Object { $_ -match 'FAILED|ABORTED|WARNING' }
if ($applyBad) {
    Write-Host '        the apply step reported problems:'
    $applyBad | ForEach-Object { Write-Host ("          {0}" -f $_.Trim()) }
} else {
    Write-Host '        done, no failures reported'
}

# ---------------------------------------------------------------- state B ---
Write-Host ''
Write-Host '  [3/5] recording changed state (B) and checking something moved'
$B = Get-VfxState
$movedCount = Get-DifferenceCount -X $A -Y $B
Write-Host ("        settings that changed: {0}" -f $movedCount)
if ($movedCount -eq 0) {
    Write-Host ''
    Write-Host '        NOTE: nothing changed, so this run cannot prove the undo works.'
    Write-Host '        That usually means everything was already disabled. Re-run the'
    Write-Host '        proof after restoring some effects, or trust the state comparison'
    Write-Host '        below only as far as it goes.'
}

# ---------------------------------------------------------------- restore --
Write-Host ''
Write-Host '  [4/5] running Restore-VisualEffects.ps1 for real'
$restore = Join-Path $here 'Restore-VisualEffects.ps1'
$restoreLog = & $restore -Confirm:$false 2>&1 | Out-String
$restoreBad = ($restoreLog -split "`n") | Where-Object { $_ -match 'FAILED|SKIPPED|WARNING|IGNORED' }
if ($restoreBad) {
    Write-Host '        the restore step reported:'
    $restoreBad | ForEach-Object { Write-Host ("          {0}" -f $_.Trim()) }
} else {
    Write-Host '        done, no failures reported'
}
$summary = ($restoreLog -split "`n") | Where-Object { $_ -match 'restored:' } | Select-Object -First 1
if ($summary) { Write-Host ("        {0}" -f $summary.Trim()) }

# ---------------------------------------------------------------- state C ---
Write-Host ''
Write-Host '  [5/5] recording final state (C) and comparing with A'
$C = Get-VfxState
$diffs = Compare-VfxStates -Start $A -End $C

Write-Host ''
Write-Host ('  ' + ('-' * 72))
if ($diffs.Count -eq 0 -and $movedCount -eq 0) {
    # A round trip that moved nothing has not exercised the undo at all. Calling
    # that a PASS is technically true and practically worthless: the apply step
    # found everything already at its target, so the restore had nothing to
    # reverse and nothing was tested. Say so, rather than banking the reassurance.
    Write-Host '  INCONCLUSIVE - nothing moved, so nothing was proved.'
    Write-Host ''
    Write-Host '  Every setting was already at the value the apply script wanted, so it'
    Write-Host '  changed nothing, so the undo had nothing to reverse. The comparison'
    Write-Host '  passed because both ends of a journey of zero distance are the same'
    Write-Host '  place. That is not evidence that the undo works.'
    Write-Host ''
    Write-Host '  To get a real test, put the machine back to its original state first:'
    Write-Host '      double-click "5 - UNDO back to the original.cmd"'
    Write-Host '  then run this again. It will then have 12 or so settings to move.'
    $exit = 0
}
elseif ($diffs.Count -eq 0) {
    Write-Host '  PASS - every one of the managed settings returned to its starting value.'
    Write-Host ("         {0} setting(s) were changed and all {0} came back." -f $movedCount)
    $exit = 0
} else {
    Write-Host ("  FAIL - {0} setting(s) did NOT return to their starting value:" -f $diffs.Count)
    Write-Host ''
    $diffs | ForEach-Object {
        Write-Host ("    {0,-28} was {1,-10} now {2}" -f $_.Setting, $_.Before, $_.After)
    }
    Write-Host ''
    Write-Host '  The starting state is saved at:'
    Write-Host "    $stateAPath"
    Write-Host '  Restore it explicitly with:'
    Write-Host ("    .\Restore-VisualEffects.ps1 -Backup `"{0}`"" -f (Split-Path $stateAPath -Leaf))
    $exit = 1
}
Write-Host ''

if (-not $KeepBackups) {
    Get-VfxBackups -BackupDir $backupDir |
        Where-Object { $_.Name -notin $before -and $_.Name -ne 'original-state.json' } |
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
    Write-Host '  backups created by this run were removed (-KeepBackups:$false)'
    Write-Host ''
}

Write-Host '  What this proof can and cannot see: it compares the 20 settings this'
Write-Host '  module manages, plus the shared legacy byte mask. It cannot detect a'
Write-Host '  change to something the module does not know about.'
Write-Host ''

# Deliberately NOT calling `exit`: that terminates the hosting PowerShell
# process, which closes the window of anyone running this interactively. The
# result is returned instead, and $LASTEXITCODE is set for scripted callers.
$global:LASTEXITCODE = $exit
if ($exit -eq 0) { return $true } else { return $false }

