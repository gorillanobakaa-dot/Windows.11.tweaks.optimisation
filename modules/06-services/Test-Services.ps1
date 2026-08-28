<#
.SYNOPSIS
    Read-only: what services are on this machine, and what each profile would
    do to them. Changes nothing, needs no administrator rights.

.PARAMETER Profile
    Show the detail for one profile: light, moderate or super.

.PARAMETER Full
    List every service a profile would disable, not just the summary.
#>

[CmdletBinding()]
param([ValidateSet('light','moderate','super')][string]$Profile, [switch]$Full)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$data = Get-SvcProfileData -Directory $here
$all  = Get-SvcAllWin32

Write-Host ''
Write-Host '  Services on this machine - read only'
Write-Host ('  ' + ('-' * 74))
Write-Host ("    Win32 services (drivers are out of scope)  : {0}" -f $all.Count)
Write-Host ("      automatic {0}   manual {1}   disabled {2}" -f
    @($all | Where-Object { $_.start -eq 2 }).Count,
    @($all | Where-Object { $_.start -eq 3 }).Count,
    @($all | Where-Object { $_.start -eq 4 }).Count)
Write-Host ("      running right now                        : {0}" -f @($all | Where-Object { $_.state -eq 'Running' }).Count)
Write-Host ("      running as LocalSystem                   : {0}" -f @($all | Where-Object { $_.account -eq 'LocalSystem' }).Count)
Write-Host ''
Write-Host '    "Manual" does not mean off. It means Windows starts it when'
Write-Host '    something asks - a device arriving, a network event, a policy'
Write-Host '    refresh. That is the surface these profiles close.'

Write-Host ''
Write-Host '  What each profile would do'
Write-Host ('  ' + ('-' * 74))
foreach ($t in 'light','moderate','super') {
    $names = Get-SvcProfileNames -Data $data -Profile $t
    $present = @($names | Where-Object { (Get-SvcEntry -Name $_).existed })
    $todo    = @($present | Where-Object { (Get-SvcEntry -Name $_).start -ne 4 })
    Write-Host ("    {0,-9} {1,3} listed   {2,3} present here   {3,3} still to disable   {4}" -f
        $t.ToUpper(), $names.Count, $present.Count, $todo.Count, $data.profiles.$t.label)
}
Write-Host ''
Write-Host ("    never-touch (no profile may contain these) : {0}" -f @($data.never).Count)
Write-Host ("    lockout-risk (excluded from all profiles)  : {0}" -f @($data.lockoutRisk).Count)

if ($Profile) {
    $names = Get-SvcProfileNames -Data $data -Profile $Profile
    Write-Host ''
    Write-Host ("  {0} in detail" -f $Profile.ToUpper())
    Write-Host ('  ' + ('-' * 74))

    $warn = Get-SvcRealityWarnings -Names $names
    if ($warn.Count) {
        Write-Host '    THINGS THIS MACHINE ACTUALLY USES THAT THIS PROFILE TOUCHES:'
        foreach ($x in $warn) { Write-Host ("      ! {0}" -f $x) }
        Write-Host ''
    }
    $dep = Test-SvcDependencySafety -Names $names
    if ($dep.Count) {
        Write-Host '    DEPENDENCY PROBLEMS (the apply would refuse):'
        foreach ($x in $dep) { Write-Host ("      X {0}" -f $x) }
    } else {
        Write-Host '    dependency check: nothing that stays enabled depends on anything'
        Write-Host '    this profile disables.'
    }

    if ($Full) {
        Write-Host ''
        $byCat = @{}
        foreach ($n in $names) {
            $e = Get-SvcProfileEntry -Data $data -Name $n
            $cat = if ($e) { $e.category } else { 'other' }
            if (-not $byCat.ContainsKey($cat)) { $byCat[$cat] = New-Object System.Collections.Generic.List[object] }
            $byCat[$cat].Add($n)
        }
        foreach ($cat in ($byCat.Keys | Sort-Object)) {
            Write-Host ("    [{0}]" -f $cat)
            foreach ($n in $byCat[$cat]) {
                $cur = Get-SvcEntry -Name $n
                $shown = if (-not $cur.existed) { 'not present' } else { "$($script:SvcStartNames[$cur.start]), $($cur.state)" }
                Write-Host ("      {0,-34} {1}" -f $n, $shown)
            }
        }
    } else {
        Write-Host ''
        Write-Host '    Add -Full to list every service, grouped by category.'
    }
}
else {
    Write-Host ''
    Write-Host '    For detail:  Test-Services.ps1 -Profile moderate -Full'
}
Write-Host ''
Write-Host '    Nothing was changed. This script can only read.'
Write-Host ''
