<#
.SYNOPSIS
    Show which suggestions, tips, "personalised" content and recommendation
    features are switched on for your account. Changes nothing.

.DESCRIPTION
    Covers Settings > Privacy & security > Recommendations & offers, plus the
    related switches that page does not show you.

    The report is split the same way the module is: settings Microsoft documents
    explicitly, and settings that are real but undocumented. The split is the
    point - you should be able to see which of these this project can back up
    with a quotation and which it cannot.

    Needs no administrator rights. Every setting here belongs to your account.

.PARAMETER Json
    Also write a timestamped JSON snapshot into .\backups\ for later comparison.
    A snapshot is a record, not a backup.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-Recommendations.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-Recommendations.ps1 -Json
#>

[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$state = Get-RcState

function Show-Row {
    param($Rule, $Entry)
    $shown = if ($Entry.existed) { "$($Entry.value)" } else { '<not set>' }
    $wanted = "$($Rule.Target)"
    $at = if ($Entry.existed -and [int]$Entry.value -eq [int]$Rule.Target) { 'as wanted' } else { 'WOULD CHANGE' }
    Write-Host ("     {0,-46} {1,-11} -> {2,-3} {3}" -f $Rule.Name, $shown, $wanted, $at)
    Write-Host ("     {0,-46} {1}" -f '', $Rule.Ui)
}

Write-Host ''
Write-Host '  Recommendations, suggestions and personalised content'
Write-Host ("  account: {0}   |   Windows build {1}" -f $state.user, $state.osBuild)
Write-Host '  Everything here is per-account. No administrator rights needed.'
Write-Host ('  ' + ('-' * 74))

Write-Host ''
Write-Host '  DOCUMENTED  - Microsoft names these, gives the registry path, and states'
Write-Host '                the value. Applied by default.'
Write-Host ''
foreach ($r in $script:RcDocumented) {
    Show-Row -Rule $r -Entry $state.registry["$($r.Key)|$($r.Name)"]
    Write-Host ("     {0,-46} cited as [{1}]" -f '', $r.Cite)
    Write-Host ''
}

Write-Host '  OBSERVED    - real, present on this machine, and NOT in the Microsoft'
Write-Host '                documentation corpus. Not applied unless you ask.'
Write-Host ''
foreach ($r in $script:RcObserved) {
    Show-Row -Rule $r -Entry $state.registry["$($r.Key)|$($r.Name)"]
    Write-Host ("     {0,-46} no citation available" -f '')
    Write-Host ''
}

# --- summary ----------------------------------------------------------------
$pendDoc = @(); $pendObs = @()
foreach ($r in $script:RcDocumented) {
    $e = $state.registry["$($r.Key)|$($r.Name)"]
    if (-not $e.existed -or [int]$e.value -ne [int]$r.Target) { $pendDoc += $r.Name }
}
foreach ($r in $script:RcObserved) {
    $e = $state.registry["$($r.Key)|$($r.Name)"]
    if (-not $e.existed -or [int]$e.value -ne [int]$r.Target) { $pendObs += $r.Name }
}

Write-Host ('  ' + ('-' * 74))
Write-Host ("    documented, would change : {0}" -f $(if ($pendDoc.Count) { $pendDoc.Count } else { 'none - already set' }))
Write-Host ("    observed,   would change : {0}  (only with -IncludeObserved)" -f $(if ($pendObs.Count) { $pendObs.Count } else { 'none - already set' }))

$silent = $state.registry["HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager|SilentInstalledAppsEnabled"]
if ($silent.existed -and [int]$silent.value -eq 1) {
    Write-Host ''
    Write-Host '    Worth a second look: SilentInstalledAppsEnabled is 1, which is the'
    Write-Host '    setting that lets Windows install promoted apps without asking you.'
    Write-Host '    It is in the OBSERVED tier because Microsoft has not documented it,'
    Write-Host '    not because it is unimportant.'
}
Write-Host ''

if ($Json) {
    $dir = Join-Path $here 'backups'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $p = Join-Path $dir ("snapshot_{0}.json" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    # Audit finding 10: this write was unverified - on a read-only backups
    # folder it printed "snapshot written" over a red error, naming a file that
    # did not exist.
    try { $state | ConvertTo-Json -Depth 8 | Set-Content $p -Encoding UTF8 -ErrorAction Stop } catch { }
    if (Test-Path $p) { Write-Host "    snapshot written : $p" }
    else              { Write-Host "    SNAPSHOT FAILED  : could not write $p" }
    Write-Host ''
}
