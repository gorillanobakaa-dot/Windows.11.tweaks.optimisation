<#
.SYNOPSIS
    Try to put back what was removed. This is a BEST EFFORT, not an undo, and
    the difference is stated rather than glossed.

.DESCRIPTION
    An app package can be re-registered from its payload on disk. If the
    payload was deleted with the package - which is what happens when the
    provisioned copy went too - there is nothing to register and the only
    route back is the Microsoft Store.

    So this script sorts the removal record into two piles and reports both
    honestly. It never claims to have restored something it could not.

.PARAMETER List
    Show what was removed and what the route back is for each. Changes nothing.

.PARAMETER Name
    Try just one package.

.NOTES
    Exit codes: 0 done   4 nothing to do / unelevated / no record
                5 completed with failures
#>
[CmdletBinding()]
param(
    [switch]$List,
    [string]$Name = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$here    = $PSScriptRoot
$records = Join-Path $here 'records'
$recPath = Get-AdRemovalRecordPath -Directory $records

Write-Host ""
Write-Host "  Put back removed apps - best effort"
Write-Host "  --------------------------------------------------------------------------"

if (-not (Test-Path $recPath)) {
    Write-Host "    Nothing has been removed by this module, so there is nothing to put back."
    Write-Host "    Exit code 4."
    exit 4
}

try { $removed = @(Get-Content $recPath -Raw | ConvertFrom-Json) }
catch {
    Write-Host ("    the removal record will not parse: {0}" -f $_.Exception.Message)
    Write-Host "    It has NOT been overwritten - it is the only inventory of what was"
    Write-Host "    removed. Exit code 4."
    exit 4
}

$installed = Get-AdInstalled
$targets = @($removed)
if ($Name) { $targets = @($removed | Where-Object { $_.name -eq $Name }) }

$reRegisterable = @($targets | Where-Object { $_.payloadStillOnDisk -and -not $installed.ContainsKey($_.name) })
$storeOnly      = @($targets | Where-Object { -not $_.payloadStillOnDisk -and -not $installed.ContainsKey($_.name) })
$alreadyBack    = @($targets | Where-Object { $installed.ContainsKey($_.name) })

Write-Host ("    recorded removals            : {0}" -f $targets.Count)
Write-Host ("      already installed again    : {0}" -f $alreadyBack.Count)
Write-Host ("      payload on disk, can retry : {0}" -f $reRegisterable.Count)
Write-Host ("      payload gone, Store only   : {0}" -f $storeOnly.Count)

if ($List) {
    Write-Host ""
    foreach ($r in $targets) {
        $state = if ($installed.ContainsKey($r.name)) { 'installed again' }
                 elseif ($r.payloadStillOnDisk)       { 'removable payload present' }
                 else                                  { 'payload gone' }
        Write-Host ("      {0,-46} {1,-26} {2:yyyy-MM-dd}" -f $r.name, $state, [datetime]$r.removedAt)
        Write-Host ("          route back: {0}" -f $r.routeBack)
    }
    Write-Host ""
    Write-Host "    Nothing was changed."
    exit 0
}

if ($reRegisterable.Count -eq 0) {
    Write-Host ""
    if ($storeOnly.Count -gt 0) {
        Write-Host "    Nothing can be re-registered. The packages below were removed"
        Write-Host "    payload and all, and the Microsoft Store is the only route back:"
        foreach ($r in $storeOnly) { Write-Host ("      {0}   (was v{1})" -f $r.name, $r.version) }
    }
    else {
        Write-Host "    Nothing to put back."
    }
    Write-Host "    Exit code 4."
    exit 4
}

if (-not (Test-AdElevated)) {
    Write-Host ""
    Write-Host "    STOPPING: re-registering a package needs administrator rights."
    Write-Host "    Exit code 4: nothing was changed."
    exit 4
}

Write-Host ""
Write-Host "  Re-registering"
Write-Host "  --------------------------------------------------------------------------"
$ok = 0; $bad = 0
foreach ($r in $reRegisterable) {
    $manifest = Join-Path $r.installLocation 'AppXManifest.xml'
    if (-not (Test-Path -LiteralPath $manifest)) {
        Write-Host ("      cannot: {0} - no manifest at the recorded location" -f $r.name)
        $bad++; continue
    }
    try {
        Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
        # judge by the machine, not by the absence of an error
        if (@(Get-AppxPackage -Name $r.name -ErrorAction SilentlyContinue).Count -gt 0) {
            Write-Host ("      restored {0}" -f $r.name); $ok++
        }
        else {
            Write-Host ("      FAILED {0}: registration returned success but it is not installed" -f $r.name); $bad++
        }
    }
    catch { Write-Host ("      FAILED {0}: {1}" -f $r.name, $_.Exception.Message); $bad++ }
}

Write-Host ""
Write-Host ("    restored: {0}   failed: {1}" -f $ok, $bad)
if ($storeOnly.Count -gt 0) {
    Write-Host ""
    Write-Host ("    {0} package(s) cannot be restored this way at all - Store only:" -f $storeOnly.Count)
    foreach ($r in $storeOnly) { Write-Host ("      {0}" -f $r.name) }
}

Write-Host ""
Write-Host "    The removal record is deliberately NOT cleared. It is the history of"
Write-Host "    what this module removed, and check 1 uses it to spot apps that come"
Write-Host "    back on their own."

if ($bad -gt 0) { Write-Host "    Exit code 5: completed with failures."; exit 5 }
Write-Host ""
exit 0
