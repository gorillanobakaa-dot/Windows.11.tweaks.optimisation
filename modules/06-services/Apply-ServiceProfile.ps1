<#
.SYNOPSIS
    Apply a service profile: set the profile's services to DISABLED, with a
    verified backup of EVERY service start type taken first.

.DESCRIPTION
    Profiles are cumulative - moderate includes light, super includes both.

    Before writing anything the apply performs three refusals:
      * a profile naming a NEVER-TOUCH service is rejected outright
      * a profile naming a LOCKOUT-RISK service is rejected outright
      * a plan that would leave an enabled service depending on a disabled
        one is rejected, naming both services

    It also prints what this MACHINE actually uses that the profile would
    take away, before asking.

    Exit codes (MODULE-STANDARD sect. 16): 3 = backup refused; 4 = nothing to
    do; 5 = completed with failures; 6 = the profile is illegal or unsafe.

.PARAMETER Profile
    light, moderate or super.

.PARAMETER Force
    Skip the typed confirmation. Intended for the round-trip proof.

.PARAMETER Tag
    Label added to the backup file name.

.PARAMETER WhatIf
    Print every change that would be made and make none of them.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)][ValidateSet('light','moderate','super')][string]$Profile,
    [switch]$Force,
    [string]$Tag = ''
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$data  = Get-SvcProfileData -Directory $here
$names = Get-SvcProfileNames -Data $data -Profile $Profile
$elevated = Test-SvcElevated

Write-Host ''
Write-Host ("  Service profile: {0}" -f $Profile.ToUpper())
Write-Host ('  ' + ('-' * 74))
Write-Host ("    {0}" -f $data.profiles.$Profile.label)
Write-Host ("    running as administrator : {0}" -f $(if ($elevated) { 'yes' } else { 'NO - service start types are machine-wide; nothing can be written' }))

# ---------------------------------------------------------------------------
#  Refusals, before anything is read for a plan
# ---------------------------------------------------------------------------
$illegal = Test-SvcProfileLegal -Data $data -Names $names
if ($illegal.Count) {
    Write-Host ''
    Write-Host '    STOPPING. This profile names services that must never be disabled:'
    foreach ($p in $illegal) { Write-Host ("      X {0}" -f $p) }
    Write-Host ''
    Write-Host '    Nothing was changed. Fix profiles.json - the list is enforced here'
    Write-Host '    in code precisely so an edited profile cannot quietly do this.'
    Write-Host ''
    exit 6
}

$dep = Test-SvcDependencySafety -Names $names
if ($dep.Count) {
    Write-Host ''
    Write-Host '    STOPPING. This plan would break service dependencies:'
    foreach ($p in $dep) { Write-Host ("      X {0}" -f $p) }
    Write-Host ''
    Write-Host '    A dependency break does not fail when you make it. It fails at the'
    Write-Host '    next boot. Nothing was changed.'
    Write-Host ''
    exit 6
}

# ---------------------------------------------------------------------------
#  Plan
# ---------------------------------------------------------------------------
$plan = New-Object System.Collections.Generic.List[object]
foreach ($n in $names) {
    $e = Get-SvcEntry -Name $n
    $entry = Get-SvcProfileEntry -Data $data -Name $n
    $plan.Add([pscustomobject]@{
        name = $n
        entry = $entry
        from = $(if ($e.existed) { $script:SvcStartNames[$e.start] } else { '<not installed>' })
        needed = ($e.existed -and $e.start -ne $script:SvcDisabled)
        absent = (-not $e.existed)
        running = ($e.state -eq 'Running')
    })
}

$needed  = @($plan | Where-Object { $_.needed })
$absent  = @($plan | Where-Object { $_.absent })
$already = @($plan | Where-Object { -not $_.needed -and -not $_.absent })

Write-Host ''
Write-Host ("    services named by this profile : {0}" -f $plan.Count)
Write-Host ("      already disabled             : {0}" -f $already.Count)
Write-Host ("      not present on this machine  : {0}  (skipped, not an error)" -f $absent.Count)
Write-Host ("      TO DISABLE                   : {0}" -f $needed.Count)
Write-Host ("        of those, running right now: {0}  (they will be stopped)" -f @($needed | Where-Object { $_.running }).Count)

$warn = Get-SvcRealityWarnings -Names $names
if ($warn.Count) {
    Write-Host ''
    Write-Host '    WHAT THIS MACHINE ACTUALLY USES THAT THIS PROFILE TAKES AWAY:'
    foreach ($x in $warn) { Write-Host ("      ! {0}" -f $x) }
}

Write-Host ''
Write-Host '    dependency check passed: nothing that stays enabled depends on'
Write-Host '    anything this profile disables.'

if ($WhatIfPreference) {
    Write-Host ''
    Write-Host ('  ' + ('-' * 74))
    Write-Host '    PREVIEW ONLY - nothing was changed.'
    Write-Host ("      services that would be disabled : {0}" -f $needed.Count)
    Write-Host ''
    return
}

if ($needed.Count -eq 0) {
    Write-Host ''
    Write-Host '    Nothing to do - every service this profile names is already disabled'
    Write-Host '    or not present.'
    Write-Host ''
    exit 4
}

if (-not $elevated) {
    Write-Host ''
    Write-Host '    Service start types are machine-wide and this run has no administrator'
    Write-Host '    rights. Nothing was changed and no backup was written. Use the numbered'
    Write-Host '    launcher, which asks Windows for elevation properly.'
    Write-Host ''
    exit 4
}

if (-not $Force) {
    Write-Host ''
    Write-Host ("    This will disable {0} services. Every start type on this machine is" -f $needed.Count)
    Write-Host '    backed up first, and "UNDO everything" puts them all back.'
    $answer = Read-Host ("    Type the profile name ({0}) to proceed" -f $Profile)
    if ($answer -ne $Profile) {
        Write-Host ''; Write-Host '    Nothing was changed.'; Write-Host ''
        exit 4     # not 0: a caller must not read a refusal as a successful apply
    }
}

# ---------------------------------------------------------------------------
#  Backup EVERY service, not only the ones being changed
# ---------------------------------------------------------------------------
Write-Host ''
$backupDir = Join-Path $here 'backups'
$state = Get-SvcState
$backup = Save-SvcBackup -State $state -Directory $backupDir -Tag $(if ($Tag) { $Tag } else { $Profile }) -RecordAsOriginal
if (-not $backup) {
    Write-Host ''
    Write-Host '    STOPPING. Nothing has been changed. The backup could not be written'
    Write-Host '    and verified, so there would be no reliable undo.'
    Write-Host ''
    exit 3
}
Write-Host ("    backup written and verified: {0}  ({1} services recorded)" -f (Split-Path -Leaf $backup), (Get-SvcEntries -Services $state.services).Count)

# ---------------------------------------------------------------------------
#  Apply
# ---------------------------------------------------------------------------
$changed = 0; $failed = 0; $declined = 0; $stopped = 0; $stopFailed = 0
Write-Host ''
Write-Host '    applying:'
foreach ($p in $plan) {
    if (-not $p.needed) { continue }
    if (-not $PSCmdlet.ShouldProcess($p.name, 'set start type to disabled')) { $declined++; continue }
    if (Set-SvcStart -Name $p.name -Value $script:SvcDisabled) {
        $changed++
        Write-Host ("      disabled {0,-32} was {1}" -f $p.name, $p.from)
        if ($p.running) {
            try { Stop-Service -Name $p.name -Force -ErrorAction Stop; $stopped++ }
            catch {
                # Counted, not narrated. The previous version's comment said a
                # failed stop was 'not a footnote' and then made it one: no
                # counter, so a run where every stop failed reported success.
                Write-Host ("        COULD NOT STOP: {0} - {1}" -f $p.name, $_.Exception.Message)
                Write-Host  '        (the start type IS set, so it will not start again after a restart)'
                $stopFailed++
            }
        }
    } else { $failed++ }
}

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    disabled: {0}   stopped now: {1}   could not stop: {2}   declined: {3}   failed: {4}" -f $changed, $stopped, $stopFailed, $declined, $failed)

$after = Get-SvcAllWin32
Write-Host ''
Write-Host '    the machine now reports:'
Write-Host ("      services disabled  : {0}" -f @($after | Where-Object { $_.start -eq 4 }).Count)
Write-Host ("      still manual/auto  : {0}" -f @($after | Where-Object { $_.start -in 2,3 }).Count)
Write-Host ("      running right now  : {0}" -f @($after | Where-Object { $_.state -eq 'Running' }).Count)
Write-Host ''
Write-Host '    A RESTART is the honest test. Some services are already running and'
Write-Host '    keep running until then; the change is what happens at next boot.'
Write-Host ''
Write-Host '    To undo: double-click "8 - UNDO everything.cmd"'
Write-Host ''
if ($failed -gt 0 -or $stopFailed -gt 0) {
    if ($failed -gt 0)     { Write-Host '    One or more writes FAILED - the lines above name them.' }
    if ($stopFailed -gt 0) { Write-Host '    One or more running services could not be stopped now (start types ARE set).' }
    Write-Host '    Exit code 5: completed with failures.'
    Write-Host ''
    exit 5
}
if ($declined -gt 0 -and $changed -eq 0) {
    # Everything was declined at the prompt: nothing happened, and exit 0
    # would have told a caller the profile was applied.
    Write-Host '    Every change was declined at the prompt. Nothing was changed.'
    Write-Host ''
    exit 4
}
