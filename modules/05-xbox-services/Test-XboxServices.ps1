<#
.SYNOPSIS
    Read-only: what Xbox is on this machine right now. Changes nothing,
    needs no administrator rights.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$state = Get-XsState

Write-Host ''
Write-Host '  Xbox on this machine - read-only'
Write-Host ('  ' + ('-' * 74))
Write-Host ''
Write-Host '  Services (Start: 2=automatic, 3=manual - wakes when asked, 4=disabled):'
foreach ($r in $script:XsServices) {
    $e = $state.services[$r.Name]
    if (-not $e.existed) { Write-Host ("    {0,-28} not installed" -f $r.Name); continue }
    $verdict = if (($e.start -as [int]) -eq 4) { 'disabled' } else { "Start=$($e.start) - CAN WAKE" }
    Write-Host ("    {0,-28} {1,-10} {2,-22} {3}" -f $r.Name, $e.liveState, $verdict, $r.Desc)
}
foreach ($i in (Get-XsDvrInstances)) {
    Write-Host ("    {0,-28} {1,-10} Start={2,-18} per-user instance - stamped from the template at sign-in, clears at next sign-out" -f $i.name, $(if ($i.liveState) { $i.liveState } else { '-' }), $i.start)
}
Write-Host ''
Write-Host '  Scheduled tasks named by the same Microsoft guidance:'
foreach ($t in $script:XsTasks) {
    $e = $state.tasks["$($t.Path)$($t.Name)"]
    $shown = if (-not $e.existed) { 'not present on this build' } elseif ($e.enabled) { 'ENABLED' } else { 'disabled' }
    Write-Host ("    {0,-28} {1}" -f $t.Name, $shown)
}
Write-Host ''
Write-Host '  Xbox app packages for this account (REPORTED ONLY - a later module'
Write-Host '  handles apps; disabling services does not remove apps):'
$apps = @(Get-AppxPackage -Name '*xbox*' -ErrorAction SilentlyContinue)
if ($apps.Count) { foreach ($a in $apps) { Write-Host ("    {0}" -f $a.Name) } }
else { Write-Host '    none' }
Write-Host ''
Write-Host '  A stopped Manual service is not an absent one: it starts when something'
Write-Host '  asks for it. That distinction is what this module closes.'
Write-Host ''
