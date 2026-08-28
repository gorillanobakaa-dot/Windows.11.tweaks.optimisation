<#
.SYNOPSIS
    Read-only. What this machine's feature-update hold looks like right now.

.DESCRIPTION
    Changes nothing. Reports four separate things and never blurs them:

      1. What THIS MACHINE is running        (edition, build, release)
      2. What POLICY is set                  (what an administrator asked for)
      3. What the UPDATE CLIENT believes     (its own state, not the policy)
      4. What MICROSOFT is doing to you      (safeguard holds)

    Two and three are different questions. A policy value that is present
    proves an administrator set it. It does not prove the update client read
    it, and on Home there is documented reason to doubt it did.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-UpdateDeferral.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$here    = $PSScriptRoot
$backups = Join-Path $here 'backups'

Write-Host ""
Write-Host "  Feature-update hold - read only"
Write-Host "  --------------------------------------------------------------------------"

# --- 1. what this machine is -----------------------------------------------
$edition = Get-UdfEdition
$release = Get-UdfInstalledRelease
Write-Host ("    edition        : {0}" -f $edition)
Write-Host ("    build          : {0}" -f (Get-UdfBuildString))
Write-Host ("    release        : {0}   <- the number a hold is supposed to freeze" -f $release)

Write-UdfHomeCaveat

# --- 2. what policy is set -------------------------------------------------
Write-Host ""
Write-Host "  What an administrator has asked for"
Write-Host "  --------------------------------------------------------------------------"
Write-Host ("    key: {0}" -f $script:UdfPolicyKey)

$anySet = $false
foreach ($name in Get-UdfAllValueNames) {
    $e = Get-UdfRegEntry -Key $script:UdfPolicyKey -Name $name
    if ($e.existed) {
        $anySet = $true
        Write-Host ("      {0,-32} {1}" -f $name, $e.value)
    }
    else {
        Write-Host ("      {0,-32} (not set)" -f $name)
    }
}

if (-not $anySet) {
    Write-Host ""
    Write-Host "    Nothing is set. Feature updates are being taken as Microsoft offers them."
}
else {
    $tv = Get-UdfRegEntry -Key $script:UdfPolicyKey -Name 'TargetReleaseVersionInfo'
    if ($tv.existed) {
        if ("$($tv.value)" -eq "$release") {
            Write-Host ""
            Write-Host ("    The pin matches the installed release ({0}). That is the intended state:" -f $release)
            Write-Host "    it holds this machine where it already is."
        }
        else {
            Write-Host ""
            Write-Host ("    ! The pin says {0} but this machine is running {1}." -f $tv.value, $release)
            Write-Host "      A pin to a release you are not on is not a hold. Re-apply to correct it."
        }
    }
}

# --- 3. what the update client believes ------------------------------------
Write-Host ""
Write-Host "  What the update client itself believes"
Write-Host "  --------------------------------------------------------------------------"
$cv = Get-UdfClientView
if (-not $cv.keyExists) {
    Write-Host "    The client's own settings key is absent. Nothing to read."
}
else {
    Write-Host ("      PausedFeatureStatus            {0}" -f $(if ($null -ne $cv.PausedFeatureStatus) { $cv.PausedFeatureStatus } else { '(absent)' }))
    Write-Host ("      PausedQualityStatus            {0}" -f $(if ($null -ne $cv.PausedQualityStatus) { $cv.PausedQualityStatus } else { '(absent)' }))
    Write-Host ""
    Write-Host "    This is the client's view, not the policy. Microsoft points at these"
    Write-Host "    values as the ground truth after a pause, because the policy editor"
    Write-Host "    can show a pause that has already expired."
}

# --- 4. what Microsoft is doing to you -------------------------------------
Write-Host ""
Write-Host "  Safeguard holds - Microsoft holding this machine back"
Write-Host "  --------------------------------------------------------------------------"
$sg = Get-UdfSafeguardHold
Write-Host ("    {0}" -f $sg.text)
if ($sg.known -and $sg.status -eq 0) {
    Write-Host "    This is Microsoft's own block on a known-bad combination for this"
    Write-Host "    hardware. It is not something to work around."
}

# --- the ceiling -----------------------------------------------------------
Write-Host ""
Write-Host "  The ceiling on any hold"
Write-Host "  --------------------------------------------------------------------------"
Write-Host "    Home and Pro get 24 months of support per feature update. Past that,"
Write-Host "    Microsoft updates the machine anyway: a device is automatically"
Write-Host "    updated once it is 60 days past end of service for its edition."
Write-Host ""
Write-Host "    So a hold is a delay, never a refusal. Plan to move the pin forward"
Write-Host "    deliberately rather than discover the ceiling by being moved off it."

# --- history ---------------------------------------------------------------
Write-Host ""
Write-Host "  Release history recorded by this module"
Write-Host "  --------------------------------------------------------------------------"
$files = @(Get-UdfBackups -Directory $backups)
if ($files.Count -eq 0) {
    Write-Host "    No backups yet. Every apply and undo records the release it saw, so"
    Write-Host "    once this has run a few times there is a dated history here to prove"
    Write-Host "    the release did or did not move."
}
else {
    foreach ($f in ($files | Select-Object -First 10)) {
        try {
            $s = Get-Content $f.FullName -Raw | ConvertFrom-Json
            Write-Host ("      {0:yyyy-MM-dd HH:mm}   release {1,-8} {2}" -f $f.LastWriteTime, $s.displayVersion, $f.Name)
        }
        catch { Write-Host ("      {0,-20} (unreadable)" -f $f.Name) }
    }
    $seen = @($files | ForEach-Object {
        try { (Get-Content $_.FullName -Raw | ConvertFrom-Json).displayVersion } catch { }
    } | Where-Object { $_ } | Sort-Object -Unique)
    Write-Host ""
    if ($seen.Count -le 1) {
        Write-Host ("    Releases seen across every recorded run: {0}. The machine has not moved." -f ($seen -join ', '))
    }
    else {
        Write-Host ("    ! Releases seen across recorded runs: {0}." -f ($seen -join ', '))
        Write-Host "      The machine HAS moved between releases while this module was in use."
    }
}

Write-Host ""
Write-Host "    Nothing was changed. This script can only read."
Write-Host ""
exit 0
