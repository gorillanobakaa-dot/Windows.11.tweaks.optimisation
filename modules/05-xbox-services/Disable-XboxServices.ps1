<#
.SYNOPSIS
    Disable the Xbox services and the XblGameSave scheduled task, with a
    verified backup first. Fully reversible via Restore-XboxServices.ps1.

.DESCRIPTION
    Sets Start = 4 (disabled) on five services Microsoft's own guidance names
    for disabling [R-98..R-104], stops any that are running, and disables the
    XblGameSaveTask scheduled task. Everything here needs administrator
    rights - the service configuration lives under HKLM\SYSTEM.

    Exit codes (MODULE-STANDARD sect. 16): 3 = backup refused, nothing
    changed; 4 = nothing to do, no backup written; 5 = completed but one or
    more changes FAILED (the backup exists; the summary names the failures).

.PARAMETER Tag
    Label added to the backup file name.

.PARAMETER WhatIf
    Print every change that would be made and make none of them.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param([string] $Tag = '')

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$state = Get-XsState

Write-Host ''
Write-Host '  Xbox services - disable the dormant-but-wakeable surface'
Write-Host ('  ' + ('-' * 74))
Write-Host ("    running as administrator : {0}" -f $(if ($state.elevated) { 'yes' } else { 'NO - service configuration needs it; nothing will be written' }))
Write-Host ''

$plan = New-Object System.Collections.Generic.List[object]
foreach ($r in $script:XsServices) {
    $e = $state.services[$r.Name]
    $plan.Add([pscustomobject]@{
        kind = 'service'; rule = $r
        from = $(if ($e.existed) { "$($e.start)" } else { '<not installed>' })
        to   = "$script:XsTargetStart"
        needed  = ($e.existed -and (($e.start -as [int]) -ne $script:XsTargetStart))
        absent  = (-not $e.existed)
        live    = $e.liveState
    })
}
foreach ($t in $script:XsTasks) {
    $e = $state.tasks["$($t.Path)$($t.Name)"]
    $plan.Add([pscustomobject]@{
        kind = 'task'; rule = $t
        from = $(if ($e.existed) { $(if ($e.enabled) { 'enabled' } else { 'disabled' }) } else { '<not present>' })
        to   = 'disabled'
        needed  = ($e.existed -and $e.enabled)
        absent  = (-not $e.existed)
        live    = $null
    })
}

foreach ($p in $plan) {
    $mark = if ($p.absent) { '  ' } elseif ($p.needed) { '->' } else { '  ' }
    $label = if ($p.kind -eq 'task') { "task $($p.rule.Name)" } else { $p.rule.Name }
    Write-Host ("    {0} {1,-28} {2,-15} {3,-9} {4}" -f $mark, $label, $p.from, $p.to, $p.rule.Desc)
}
Write-Host ''
Write-Host '    Start 3 = manual (wakes when asked), 4 = disabled. Every previous'
Write-Host '    value is backed up first; the undo writes it back and proves it.'

$needed = @($plan | Where-Object { $_.needed })

if ($WhatIfPreference) {
    Write-Host ''
    Write-Host ('  ' + ('-' * 74))
    Write-Host '    PREVIEW ONLY - nothing was changed.'
    Write-Host ("      items that would change : {0}" -f $needed.Count)
    if (-not $state.elevated) { Write-Host '      administrator rights would be required for all of them.' }
    Write-Host ''
    return
}

if ($needed.Count -eq 0) {
    Write-Host ''
    Write-Host '    Nothing to do.'
    Write-Host ''
    # Exit 4: nothing to do, NO backup written. Callers gate on this - a plain
    # 0 here let a round trip in this project restore a stale backup.
    exit 4
}

if (-not $state.elevated) {
    Write-Host ''
    Write-Host '    Everything this module changes needs administrator rights, and this'
    Write-Host '    run has none. Nothing was changed, and no backup was written. Use'
    Write-Host '    the numbered launcher, which asks Windows for elevation properly.'
    Write-Host ''
    # Exit 4 by the letter of the contract: nothing to do IN THIS RUN, no
    # backup written. The message above says why, so the two cases read apart.
    exit 4
}

Write-Host ''
$backupDir = Join-Path $here 'backups'
$backup = Save-XsBackup -State $state -Directory $backupDir -Tag $Tag -RecordAsOriginal
if (-not $backup) {
    Write-Host ''
    Write-Host '    STOPPING. Nothing has been changed. The backup could not be written'
    Write-Host '    and verified, so there would be no reliable undo.'
    Write-Host ''
    # Exit 3: backup refused, nothing changed (sect. 16 contract).
    exit 3
}
Write-Host ("    backup written and verified: {0}" -f (Split-Path -Leaf $backup))

$changed = 0; $already = 0; $failed = 0; $declined = 0; $stopped = 0
Write-Host ''
Write-Host '    applying:'
foreach ($p in $plan) {
    if ($p.absent -or -not $p.needed) { if (-not $p.absent) { $already++ }; continue }
    if ($p.kind -eq 'service') {
        if (-not $PSCmdlet.ShouldProcess($p.rule.Name, "set Start to $script:XsTargetStart (disabled)")) { $declined++; continue }
        if (Set-XsServiceStart -Name $p.rule.Name -Value $script:XsTargetStart) {
            Write-Host ("      set  {0,-28} Start {1} -> {2}" -f $p.rule.Name, $p.from, $script:XsTargetStart); $changed++
            if ($p.live -eq 'Running') {
                try {
                    Stop-Service -Name $p.rule.Name -Force -ErrorAction Stop
                    Write-Host ("      stopped {0} (it was running)" -f $p.rule.Name); $stopped++
                }
                catch {
                    # Audit m10: a running service we could not stop is a
                    # failure of the apply's stated job, not a footnote.
                    Write-Host ("      FAILED to stop running service {0}: {1}" -f $p.rule.Name, $_.Exception.Message)
                    $failed++
                }
            }
        } else { $failed++ }
    }
    else {
        if (-not $PSCmdlet.ShouldProcess($p.rule.Name, 'disable scheduled task')) { $declined++; continue }
        try {
            Disable-ScheduledTask -TaskPath $p.rule.Path -TaskName $p.rule.Name -ErrorAction Stop | Out-Null
            $after = Get-XsTaskEntry -Path $p.rule.Path -Name $p.rule.Name
            if ($after.existed -and -not $after.enabled) {
                Write-Host ("      disabled task {0}" -f $p.rule.Name); $changed++
            } else { Write-Host ("      FAILED: task {0} still enabled after disabling" -f $p.rule.Name); $failed++ }
        }
        catch { Write-Host ("      FAILED: task {0} - {1}" -f $p.rule.Name, $_.Exception.Message); $failed++ }
    }
}

$after = Get-XsState
Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    changed: {0}, already as wanted: {1}, declined at prompt: {2}, failed: {3}" -f $changed, $already, $declined, $failed)
Write-Host ''
Write-Host '    now reading the machine back:'
foreach ($r in $script:XsServices) {
    $e = $after.services[$r.Name]
    $shown = if ($e.existed) { "Start=$($e.start), $($e.liveState)" } else { 'not installed' }
    Write-Host ("      {0,-28} {1}" -f $r.Name, $shown)
}
# Audit M4: the per-user DVR INSTANCE stamped at sign-in from the template is
# a separate registry entry this module deliberately never writes. Show it,
# so "disabled" is never read as more than the template it is.
foreach ($i in (Get-XsDvrInstances)) {
    Write-Host ("      {0,-28} Start={1}{2} - per-user instance; stamped from the template at sign-in, clears at next sign-out" -f $i.name, $i.start, $(if ($i.liveState) { ", $($i.liveState)" } else { '' }))
}
foreach ($t in $script:XsTasks) {
    $e = $after.tasks["$($t.Path)$($t.Name)"]
    $shown = if ($e.existed) { $(if ($e.enabled) { 'ENABLED' } else { 'disabled' }) } else { 'not present' }
    Write-Host ("      task {0,-23} {1}" -f $t.Name, $shown)
}
Write-Host ''
Write-Host '    To undo: double-click "4 - UNDO everything.cmd"'
Write-Host ''
if ($failed -gt 0) {
    Write-Host '    One or more changes FAILED - the lines above name them. Exit code 5'
    Write-Host '    says so to anything calling this script; exit 0 would have claimed'
    Write-Host '    success over a machine that is not in the state it reports.'
    Write-Host ''
    # Audit S2: "applied" and "applied with failures" must be different codes.
    exit 5
}
