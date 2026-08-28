<#
.SYNOPSIS
    Read-only. What app packages are installed, what each tier would remove,
    and - the point of this module - what has come back on its own.

.PARAMETER Tier
    light, moderate or super. Shows that tier in detail.

.PARAMETER Full
    List every package in the tier with its current state.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-Apps.ps1
    powershell -ExecutionPolicy Bypass -File .\Test-Apps.ps1 -Tier super -Full
#>
[CmdletBinding()]
param(
    [ValidateSet('light','moderate','super')][string]$Tier,
    [switch]$Full
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$here    = $PSScriptRoot
$records = Join-Path $here 'records'

Write-Host ""
Write-Host "  Installed apps - read only"
Write-Host "  --------------------------------------------------------------------------"

$installed = Get-AdInstalled
$all       = @($installed.Values)
$nonRem    = @($all | Where-Object { $_.NonRemovable })
$store     = @($all | Where-Object { $_.SignatureKind -eq 'Store' })
$system    = @($all | Where-Object { $_.SignatureKind -eq 'System' })

Write-Host ("    packages for this account (non-framework) : {0}" -f $all.Count)
Write-Host ("      Windows marks NonRemovable              : {0}" -f $nonRem.Count)
Write-Host ("      signed as Store                         : {0}" -f $store.Count)
Write-Host ("      signed as System                        : {0}" -f $system.Count)

if (-not (Test-AdElevated)) {
    Write-Host ""
    Write-Host "    Note: not running as administrator, so this is THIS ACCOUNT's view."
    Write-Host "    What a NEW account would receive needs elevation to read."
}

# --- what each tier would do -----------------------------------------------
Write-Host ""
Write-Host "  What each tier would remove"
Write-Host "  --------------------------------------------------------------------------"
foreach ($t in 'light','moderate','super') {
    $apps    = @(Get-AdTierApps -Tier $t)
    $present = @($apps | Where-Object { $installed.ContainsKey($_.Name) })
    $illegal = @(Test-AdTierLegal -Tier $t -Installed $installed)
    $flag    = if ($illegal.Count -gt 0) { "  ** REFUSED: $($illegal.Count) problem(s)" } else { '' }
    Write-Host ("    {0,-9} {1,3} listed  {2,3} present here{3}" -f $t.ToUpper(), $apps.Count, $present.Count, $flag)
    Write-Host ("              {0}" -f $script:AdTiers[$t].Label)
}

Write-Host ""
Write-Host ("    never-remove patterns (no tier may contain these) : {0}" -f $script:AdNever.Count)

# --- the reinstall problem -------------------------------------------------
Write-Host ""
Write-Host "  Has anything come back?"
Write-Host "  --------------------------------------------------------------------------"
$recPath = Get-AdRemovalRecordPath -Directory $records
if (-not (Test-Path $recPath)) {
    Write-Host "    Nothing has been removed by this module yet, so nothing can have"
    Write-Host "    returned. Once a removal has happened this section names anything"
    Write-Host "    that reappeared."
}
else {
    try {
        $removed = @(Get-Content $recPath -Raw | ConvertFrom-Json)
        $back = @()
        foreach ($r in $removed) { if ($installed.ContainsKey($r.name)) { $back += $r } }
        Write-Host ("    packages this module has removed : {0}" -f $removed.Count)
        if ($back.Count -eq 0) {
            Write-Host "    none of them are installed again. Good."
        }
        else {
            Write-Host ("    ! {0} HAVE COME BACK:" -f $back.Count)
            foreach ($r in $back) {
                $now = $installed[$r.name]
                Write-Host ("        {0,-46} removed {1:yyyy-MM-dd}, now v{2}" -f $r.name, [datetime]$r.removedAt, $now.Version)
            }
            Write-Host ""
            Write-Host "      This is the documented behaviour of this edition, not a fault in"
            Write-Host "      the removal. Re-run the remove to clear them again."
        }
    }
    catch { Write-Host "    the removal record will not parse: $($_.Exception.Message)" }
}

Write-AdComesBackCaveat

# --- provisioned -----------------------------------------------------------
Write-Host ""
Write-Host "  What a NEW user account on this machine would receive"
Write-Host "  --------------------------------------------------------------------------"
$prov = Get-AdProvisioned
if (-not $prov.known) {
    Write-Host ("    UNKNOWN - could not read it: {0}" -f $prov.reason)
    Write-Host "    Recorded as unknown rather than as none. This project has seen this"
    Write-Host "    read fail with 'Access is denied' even when elevated."
}
else {
    Write-Host ("    provisioned packages: {0}" -f @($prov.packages).Count)
    if ($Tier) {
        $names = @((Get-AdTierApps -Tier $Tier) | ForEach-Object { $_.Name })
        $hit = @($prov.packages | Where-Object { $n = $_.DisplayName; $names -contains $n })
        Write-Host ("    of those, named by the {0} tier: {1}" -f $Tier.ToUpper(), $hit.Count)
    }
}

# --- tier detail -----------------------------------------------------------
if ($Tier) {
    Write-Host ""
    Write-Host ("  {0} in detail" -f $Tier.ToUpper())
    Write-Host "  --------------------------------------------------------------------------"
    $illegal = @(Test-AdTierLegal -Tier $Tier -Installed $installed)
    if ($illegal.Count -gt 0) {
        Write-Host "    THIS TIER WOULD BE REFUSED:"
        foreach ($p in $illegal) { Write-Host ("      X {0}" -f $p) }
    }
    else {
        Write-Host "    legality check: no protected package is named by this tier."
    }

    if ($Full) {
        Write-Host ""
        foreach ($a in (Get-AdTierApps -Tier $Tier)) {
            $live = $installed[$a.Name]
            $state = if ($live) { "installed v$($live.Version)" } else { 'not present' }
            Write-Host ("      {0,-48} {1}" -f $a.Name, $state)
            Write-Host ("          {0}" -f $a.What)
        }
    }
    else {
        Write-Host ""
        Write-Host "    Add -Full to list every package with what it is and what you lose."
    }
}
else {
    Write-Host ""
    Write-Host "    For detail:  Test-Apps.ps1 -Tier moderate -Full"
}

Write-Host ""
Write-Host "    Nothing was changed. This script can only read."
Write-Host ""
exit 0
