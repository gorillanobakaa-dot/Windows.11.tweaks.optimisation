<#
.SYNOPSIS
    Remove app packages by tier. THIS REMOVES SOFTWARE AND CANNOT BE UNDONE
    FROM A FILE.

.DESCRIPTION
    For each app in the tier it does what Microsoft documents, in that order:
      1. removes the PROVISIONED copy, so new accounts on this machine do not
         receive the app
      2. removes the package for the current user

    After each removal it checks whether the payload directory still exists,
    and records the answer. That is what decides whether Restore-Apps.ps1 can
    put the app back without the Store.

.PARAMETER Tier
    light, moderate or super. Cumulative.

.PARAMETER WhatIf
    Print every removal and perform none. Works WITHOUT administrator rights.

.PARAMETER Force
    Skip the typed confirmation.

.PARAMETER Tag
    Label the inventory file.

.NOTES
    Exit codes: 0 done   3 inventory refused   4 nothing to do / unelevated /
                declined   5 completed with failures   6 the tier is illegal
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('light','moderate','super')][string]$Tier,
    [switch]$WhatIf,
    [switch]$Force,
    [string]$Tag = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$here    = $PSScriptRoot
$records = Join-Path $here 'records'

Write-Host ""
Write-Host ("  REMOVE apps - tier {0}" -f $Tier.ToUpper())
Write-Host "  --------------------------------------------------------------------------"
Write-Host ("    {0}" -f $script:AdTiers[$Tier].Label)

$installed = Get-AdInstalled

# --- refusal 1 and 2: is this tier even legal? -----------------------------
$illegal = @(Test-AdTierLegal -Tier $Tier -Installed $installed)
if ($illegal.Count -gt 0) {
    Write-Host ""
    Write-Host "    STOPPING. This tier names packages that must never be removed:"
    foreach ($p in $illegal) { Write-Host ("      X {0}" -f $p) }
    Write-Host ""
    Write-Host "    Nothing was changed. A tier that names a protected package is a tier"
    Write-Host "    somebody edited without understanding it, and skipping the entry"
    Write-Host "    would hide that from the person who most needs to see it."
    Write-Host "    Exit code 6."
    exit 6
}

# --- what would go ---------------------------------------------------------
$apps = @(Get-AdTierApps -Tier $Tier)
$todo = @($apps | Where-Object { $installed.ContainsKey($_.Name) })
$absent = @($apps | Where-Object { -not $installed.ContainsKey($_.Name) })

Write-Host ""
Write-Host "  What would be removed"
Write-Host "  --------------------------------------------------------------------------"
foreach ($a in $todo) {
    $live = $installed[$a.Name]
    Write-Host ("      {0,-48} v{1}" -f $a.Name, $live.Version)
    Write-Host ("          {0}" -f $a.What)
}
if ($absent.Count -gt 0) {
    Write-Host ""
    Write-Host ("    already absent, nothing to do for {0}:" -f $absent.Count)
    foreach ($a in $absent) { Write-Host ("      - {0}" -f $a.Name) }
}

Write-Host ""
Write-Host "  Protected from this run"
Write-Host "  --------------------------------------------------------------------------"
Write-Host ("      {0} never-remove patterns, and every package Windows marks" -f $script:AdNever.Count)
Write-Host ("      NonRemovable ({0} on this machine) - checked live, not trusted" -f @($installed.Values | Where-Object { $_.NonRemovable }).Count)
Write-Host  "      from a list. Frameworks and resource packages are out of scope"
Write-Host  "      by construction and are never enumerated."

Write-AdComesBackCaveat

if ($todo.Count -eq 0) {
    Write-Host ""
    Write-Host "    Nothing to do - every app in this tier is already absent."
    Write-Host "    No inventory was written, because nothing was going to change."
    Write-Host "    Exit code 4."
    exit 4
}

if ($WhatIf) {
    Write-Host ""
    Write-Host ("    -WhatIf: {0} package(s) would be removed. Nothing was removed." -f $todo.Count)
    exit 0
}

if (-not (Test-AdElevated)) {
    Write-Host ""
    Write-Host "    STOPPING: removing the PROVISIONED copy needs administrator rights,"
    Write-Host "    and without it new accounts would still receive every app you"
    Write-Host "    removed. Use the numbered launcher, which asks Windows properly."
    Write-Host "    Exit code 4: nothing was changed."
    exit 4
}

# --- confirmation ----------------------------------------------------------
if (-not $Force) {
    Write-Host ""
    Write-Host ("    This REMOVES {0} app package(s). There is no undo from a file." -f $todo.Count)
    Write-Host ("    Type the tier name ({0}) to proceed, anything else to stop." -f $Tier)
    $answer = Read-Host "    >"
    if ("$answer".Trim().ToLower() -ne $Tier) {
        Write-Host "    Declined. Nothing was changed."
        Write-Host "    Exit code 4."
        exit 4
    }
}

# --- inventory FIRST -------------------------------------------------------
Write-Host ""
Write-Host "  Inventory (not a backup - it cannot restore anything)"
Write-Host "  --------------------------------------------------------------------------"
$invPath = Save-AdInventory -Directory $records -Tag $(if ($Tag) { $Tag } else { $Tier })
if (-not $invPath) {
    Write-Host "    STOPPING: could not write and read back the inventory."
    Write-Host "    Exit code 3."
    exit 3
}
Write-Host ("    written and read back: {0}" -f (Split-Path $invPath -Leaf))

$prov = Get-AdProvisioned
if (-not $prov.known) {
    Write-Host ""
    Write-Host ("    NOTE: the provisioned list could not be read ({0})." -f $prov.reason)
    Write-Host "    User-scope removals will still happen. New accounts may still"
    Write-Host "    receive these apps, and that is recorded as unknown, not as done."
}

# --- remove ----------------------------------------------------------------
Write-Host ""
Write-Host "  Removing"
Write-Host "  --------------------------------------------------------------------------"
$removed = 0; $failed = 0; $provRemoved = 0

foreach ($a in $todo) {
    $live = $installed[$a.Name]
    $loc  = $live.InstallLocation

    # 1. provisioned copy - what a NEW account would get
    $provOk = $null
    if ($prov.known) {
        $match = @($prov.packages | Where-Object { $_.DisplayName -eq $a.Name })
        foreach ($m in $match) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $m.PackageName -ErrorAction Stop | Out-Null
                $provOk = $true; $provRemoved++
            }
            catch { $provOk = $false; Write-Host ("      provisioned removal failed for {0}: {1}" -f $a.Name, $_.Exception.Message) }
        }
    }

    # 2. this user's copy
    $ok = $false
    try {
        Get-AppxPackage -Name $a.Name -ErrorAction Stop | Remove-AppxPackage -ErrorAction Stop
        $ok = $true
    }
    catch {
        Write-Host ("      FAILED {0}: {1}" -f $a.Name, $_.Exception.Message)
        $failed++
    }

    if ($ok) {
        # Did it actually go? Judge by the machine, not by the absence of an error.
        $still = @(Get-AppxPackage -Name $a.Name -ErrorAction SilentlyContinue)
        if ($still.Count -gt 0) {
            Write-Host ("      FAILED {0}: still installed after the removal returned success" -f $a.Name)
            $failed++
            continue
        }
        $payloadLeft = $false
        if ($loc -and (Test-Path -LiteralPath $loc)) { $payloadLeft = $true }

        $removed++
        Write-Host ("      removed {0,-44} payload {1}" -f $a.Name, $(if ($payloadLeft) { 'still on disk - re-registerable' } else { 'gone - Store only' }))

        [void](Add-AdRemovalRecord -Directory $records -Entry ([pscustomobject]@{
            removedAt        = (Get-Date).ToString('o')
            name             = $a.Name
            packageFullName  = $live.PackageFullName
            version          = $live.Version
            publisher        = $live.Publisher
            what             = $a.What
            tier             = $Tier
            installLocation  = $loc
            payloadStillOnDisk = $payloadLeft
            provisionedRemoved = $provOk
            routeBack        = if ($payloadLeft) { 'Restore-Apps.ps1 can re-register it from the payload still on disk' }
                               else { 'reinstall from the Microsoft Store' }
        }))
    }
}

Write-Host ""
Write-Host ("    removed: {0}   provisioned copies removed: {1}   failed: {2}" -f $removed, $provRemoved, $failed)

Write-Host ""
Write-Host "  What this run has and has not established"
Write-Host "  --------------------------------------------------------------------------"
Write-Host ("    ESTABLISHED : {0} package(s) removed and confirmed absent afterwards." -f $removed)
if ($prov.known) {
    Write-Host ("    ESTABLISHED : {0} provisioned copy/copies removed - new accounts will" -f $provRemoved)
    Write-Host  "                  not receive those."
}
else {
    Write-Host  "    UNKNOWN     : whether new accounts still receive these - the provisioned"
    Write-Host  "                  list could not be read."
}
Write-Host  "    NOT ESTABLISHED : that they stay gone. On this edition Windows Update"
Write-Host  "                  can reinstall them. Check 1 names anything that returns."

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "    One or more removals FAILED - the lines above name them."
    Write-Host "    Exit code 5: completed with failures."
    exit 5
}

Write-Host ""
Write-Host "    Done. Launcher 9 shows exactly what was removed and the route back."
Write-Host ""
exit 0
