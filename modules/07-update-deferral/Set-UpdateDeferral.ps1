<#
.SYNOPSIS
    Hold FEATURE updates back by 3, 6 or 12 months. Leaves security updates
    flowing.

.DESCRIPTION
    Writes five documented policy values and reads every one of them back.
    The pin is set to the release THIS MACHINE IS ALREADY RUNNING, read live -
    never a hardcoded version, because pinning to a release you are not on is
    not a hold.

    What it will not do:
      - touch quality (security) updates
      - use the 35-day pause, which expires silently
      - claim the Home update client obeys any of this

.PARAMETER Months
    3, 6 or 12. Sets the legacy day-count deferral to 90, 180 or 365 days and
    pins the release.

.PARAMETER WhatIf
    Print every change and make none. Works WITHOUT administrator rights on
    purpose - a preview should never need elevation.

.PARAMETER Force
    Skip the typed confirmation. Intended for the round-trip proof.

.PARAMETER Tag
    Label the backup file.

.NOTES
    Exit codes (MODULE-STANDARD section 16):
      0 applied   3 backup refused   4 nothing to do / unelevated / declined
      5 completed with failures
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet(3, 6, 12)][int]$Months,
    [switch]$WhatIf,
    [switch]$Force,
    [string]$Tag = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$here    = $PSScriptRoot
$backups = Join-Path $here 'backups'

Write-Host ""
Write-Host ("  Hold feature updates for {0} months" -f $Months)
Write-Host "  --------------------------------------------------------------------------"

try { $plan = Get-UdfPlan -Months $Months }
catch {
    Write-Host ("    STOPPING: {0}" -f $_.Exception.Message)
    Write-Host "    Exit code 4: nothing was changed."
    exit 4
}

$release = Get-UdfInstalledRelease
Write-Host ("    edition : {0}" -f (Get-UdfEdition))
Write-Host ("    release : {0}   <- the pin will hold you here" -f $release)
Write-UdfHomeCaveat

# --- what would change -----------------------------------------------------
Write-Host ""
Write-Host "  Planned changes"
Write-Host "  --------------------------------------------------------------------------"
$todo = @()
foreach ($p in $plan) {
    $cur = Get-UdfRegEntry -Key $script:UdfPolicyKey -Name $p.Name
    $isSame = $cur.existed -and ([string]$cur.value -eq [string]$p.Value)
    $was = if ($cur.existed) { "$($cur.value)" } else { '(not set)' }
    if ($isSame) {
        Write-Host ("      {0,-32} already {1}" -f $p.Name, $p.Value)
    }
    else {
        Write-Host ("      {0,-32} {1}  ->  {2}" -f $p.Name, $was, $p.Value)
        Write-Host ("        {0}" -f $p.Desc)
        $todo += $p
    }
}

Write-Host ""
Write-Host "  Left alone on purpose"
Write-Host "  --------------------------------------------------------------------------"
Write-Host "      quality / security updates       untouched - they keep arriving"
Write-Host "      PauseFeatureUpdatesStartTime     untouched - a pause expires in 35 days"
Write-Host "      NoAutoUpdate / AUOptions         untouched - not this module's decision"
Write-Host "      wuauserv / UsoSvc / BITS         untouched - never-touch services"

if ($todo.Count -eq 0) {
    Write-Host ""
    Write-Host ("    Nothing to do - the {0}-month hold is already exactly as wanted." -f $Months)
    Write-Host "    No backup was written, because nothing was going to change."
    Write-Host "    Exit code 4."
    exit 4
}

if ($WhatIf) {
    Write-Host ""
    Write-Host ("    -WhatIf: {0} value(s) would change. Nothing was written." -f $todo.Count)
    exit 0
}

if (-not (Test-UdfElevated)) {
    Write-Host ""
    Write-Host "    STOPPING: this writes under HKLM and needs administrator rights."
    Write-Host "    Use the numbered launcher, which asks Windows for elevation properly."
    Write-Host "    Exit code 4: nothing was changed."
    exit 4
}

# --- confirmation ----------------------------------------------------------
if (-not $Force) {
    Write-Host ""
    Write-Host ("    This holds FEATURE updates for {0} months. Security updates keep coming." -f $Months)
    Write-Host ("    Type the number of months ({0}) to proceed, anything else to stop." -f $Months)
    $answer = Read-Host "    >"
    if ("$answer".Trim() -ne "$Months") {
        Write-Host "    Declined. Nothing was changed."
        Write-Host "    Exit code 4."
        exit 4
    }
}

# --- backup FIRST ----------------------------------------------------------
Write-Host ""
Write-Host "  Backup"
Write-Host "  --------------------------------------------------------------------------"
$backupPath = Save-UdfBackup -Directory $backups -Tag $(if ($Tag) { $Tag } else { "${Months}mo" }) -RecordAsOriginal
if (-not $backupPath) {
    Write-Host "    STOPPING: no verified backup, so nothing will be changed."
    Write-Host "    Exit code 3."
    exit 3
}
Write-Host ("    written and read back: {0}" -f (Split-Path $backupPath -Leaf))

# --- write -----------------------------------------------------------------
Write-Host ""
Write-Host "  Applying"
Write-Host "  --------------------------------------------------------------------------"
$changed = 0; $failed = 0
foreach ($p in $todo) {
    if (Set-UdfValue -Name $p.Name -Value $p.Value -Kind $p.Kind) {
        Write-Host ("      set {0,-30} {1}" -f $p.Name, $p.Value)
        $changed++
    }
    else { $failed++ }
}

Write-Host ""
Write-Host ("    changed: {0}   failed: {1}" -f $changed, $failed)

# --- what was actually established -----------------------------------------
Write-Host ""
Write-Host "  What this run has and has not established"
Write-Host "  --------------------------------------------------------------------------"
Write-Host ("    ESTABLISHED : {0} policy value(s) written and read back from the registry." -f $changed)
Write-Host ("    ESTABLISHED : the pin names {0}, which is the release now installed." -f $release)
Write-Host "    NOT ESTABLISHED : that the update client on this edition obeys them."
Write-Host ""
Write-Host "    The test is time. Run check 1 again after the next Patch Tuesday and"
Write-Host "    after the next feature release: if the release line still reads"
Write-Host ("    {0}, the hold is doing its job. If it has moved, it is not." -f $release)
Write-Host ""
Write-Host "    Security updates were not touched and should continue to arrive. If they"
Write-Host "    stop, undo this immediately - that would not be the intended effect."

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "    One or more writes FAILED - the lines above name them."
    Write-Host "    Exit code 5: completed with failures."
    exit 5
}

Write-Host ""
Write-Host "    Done. Undo with launcher 6, or 7 to go back to the original state."
Write-Host ""
exit 0
