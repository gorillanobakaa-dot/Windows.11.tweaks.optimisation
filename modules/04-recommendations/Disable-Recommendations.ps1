<#
.SYNOPSIS
    Turn off suggestions, tips, "personalised" content and Start-menu
    recommendations for your account.

.DESCRIPTION
    Backs up first, checks the backup was really written, and only then changes
    anything. If the backup cannot be written and verified, it changes nothing
    and says so.

    Needs NO administrator rights. Every setting belongs to your account.

    By default it applies only the five settings Microsoft documents explicitly.
    The five undocumented ones - including the setting that lets Windows install
    promoted apps without asking - require -IncludeObserved. That is not
    squeamishness: this project's rule is that a claim is cited or labelled, and
    applying an uncited change by default would quietly break it.

.PARAMETER IncludeObserved
    Also apply the five ContentDeliveryManager settings that are real but not in
    Microsoft's documentation. Fully backed up and fully reversible either way -
    the only difference is whether this project can quote a source for them.

.PARAMETER Tag
    A label added to the backup file name, so you can find it later.

.PARAMETER WhatIf
    Print every change that would be made and make none of them.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Disable-Recommendations.ps1 -WhatIf
    See exactly what would change. Changes nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Disable-Recommendations.ps1
    Apply the five documented settings.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Disable-Recommendations.ps1 -IncludeObserved
    Apply all ten, including silent app installation.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Disable-Recommendations.ps1 -IncludeObserved -Tag full
    Apply all ten and label the backup.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch] $IncludeObserved,
    [string] $Tag = ''
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$settings = Get-RcSettings -IncludeObserved:$IncludeObserved
$state    = Get-RcState

Write-Host ''
Write-Host '  Recommendations and suggestions - turn them off'
Write-Host ("  scope: {0}" -f $(if ($IncludeObserved) { 'documented AND observed (10 settings)' } else { 'documented only (5 settings) - add -IncludeObserved for the rest' }))
Write-Host ('  ' + ('-' * 74))

# --- plan -------------------------------------------------------------------
$plan = New-Object System.Collections.Generic.List[object]
foreach ($r in $settings) {
    $e = $state.registry["$($r.Key)|$($r.Name)"]
    $cur = if ($e.existed) { [int]$e.value } else { $null }
    $plan.Add([pscustomobject]@{
        rule   = $r
        from   = $(if ($e.existed) { "$($e.value)" } else { '<not set>' })
        to     = "$($r.Target)"
        needed = ($null -eq $cur -or $cur -ne [int]$r.Target)
        cite   = $(if ($r.Cite) { $r.Cite } else { 'uncited' })
    })
}

Write-Host ''
foreach ($p in $plan) {
    $mark = if ($p.needed) { '->' } else { '  ' }
    Write-Host ("    {0} {1,-46} {2,-11} {3,-3} [{4}]" -f $mark, $p.rule.Name, $p.from, $p.to, $p.cite)
}
$needed = @($plan | Where-Object { $_.needed })

if ($WhatIfPreference) {
    Write-Host ''
    Write-Host ('  ' + ('-' * 74))
    Write-Host ("    PREVIEW ONLY - nothing was changed.  would change: {0}" -f $needed.Count)
    if (-not $IncludeObserved) {
        Write-Host '    Five further undocumented settings are available with -IncludeObserved.'
    }
    Write-Host ''
    return
}

if ($needed.Count -eq 0) {
    Write-Host ''
    Write-Host '    Nothing to do - already set the way this module wants it.'
    Write-Host ''
    # Exit code 4 = "nothing to do", so the round trip can tell this apart from
    # a real apply. Module 02's audit: without it, a round trip on an
    # already-applied machine ran the undo against a stale backup, un-applied
    # the machine, and blamed the undo.
    exit 4
}

# --- backup, and refuse to continue without one -----------------------------
Write-Host ''
$backupDir = Join-Path $here 'backups'
# -RecordAsOriginal: this is the apply path, reading the machine before it
# changes anything, so this is the only reading entitled to define "original".
$backup = Save-RcBackup -State $state -Directory $backupDir -Tag $Tag -RecordAsOriginal
if (-not $backup) {
    Write-Host ''
    Write-Host '    STOPPING. Nothing has been changed.'
    Write-Host ''
    Write-Host '    The backup could not be written and verified, so there would be no'
    Write-Host '    reliable way to undo these changes.'
    Write-Host ''
    # Exit code 3 = "refused: no verified backup". See the note in module 02's
    # Test-RoundTrip.ps1 for why callers must not match on output text instead.
    exit 3
}
Write-Host ("    backup written and verified: {0}" -f (Split-Path -Leaf $backup))

# --- apply ------------------------------------------------------------------
$changed = 0; $already = 0; $failed = 0; $declined = 0
Write-Host ''
Write-Host '    applying:'
foreach ($p in $plan) {
    if (-not $p.needed) { $already++; continue }
    # Audit finding 14: a declined confirmation incremented no counter at all,
    # so -Confirm with four refusals reported "changed: 6 ... failed: 0" for a
    # ten-item plan and four settings vanished from the accounting.
    if (-not $PSCmdlet.ShouldProcess($p.rule.Name, "set to $($p.to)")) { $declined++; continue }
    if (Set-RcValue -Key $p.rule.Key -Name $p.rule.Name -Value $p.rule.Target -Kind $p.rule.Kind) {
        Write-Host ("      set  {0,-46} {1} -> {2}" -f $p.rule.Name, $p.from, $p.to); $changed++
    } else { $failed++ }
}

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    changed: {0}, already as wanted: {1}, failed: {2}, declined: {3}" -f $changed, $already, $failed, $declined)
Write-Host ''
Write-Host '    Some of these take effect at your next sign-in. Start-menu and'
Write-Host '    notification behaviour in particular is read when Explorer starts.'
Write-Host ''
# Audit finding 1: this line used to say "4 - UNDO everything.cmd". In this
# module number 4 is "Apply the undocumented ones too" - so the printed undo
# instruction, shown to every user who had just applied changes, led to five
# MORE settings being applied, including silent app installation.
Write-Host '    To undo: double-click "5 - UNDO everything.cmd"'
Write-Host ''
