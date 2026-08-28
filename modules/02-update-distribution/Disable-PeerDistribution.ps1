<#
.SYNOPSIS
    Stop this machine sharing Windows updates with other machines, and stop
    other machines being able to connect to it to ask.

.DESCRIPTION
    Two changes, and it will tell you about both before it makes them.

    1. Sets the Delivery Optimization download mode to CdnOnly (0). Windows
       still downloads updates normally, from Microsoft's own servers. It stops
       serving pieces of them to anybody else.

    2. Disables the two built-in inbound firewall rules that let other machines
       open a connection to this one on port 7680.

    It does NOT disable the Delivery Optimization service. That is the popular
    advice and it is wrong - Windows Update and the Microsoft Store use that
    service to DOWNLOAD, not merely to share. Turning it off breaks updates and
    is not needed to stop the sharing.

    Backs up first, checks the backup was really written, and only then changes
    anything. If the backup cannot be written, it changes nothing and says so.

    NEEDS ADMINISTRATOR RIGHTS. These are machine-wide settings, not per-user
    ones. Use the numbered .cmd launcher and it will ask Windows for them.

.PARAMETER Steps
    Which parts to apply: DownloadMode, Firewall, or both (the default).
    Splitting them is useful if you want to stop sharing but leave the firewall
    rules alone - for example on a managed network where something else expects
    those rules to exist.

.PARAMETER Tag
    A label added to the backup file name, so you can find it later.

.PARAMETER WhatIf
    Print every change that would be made and make none of them. Needs no
    administrator rights, because it only reads.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Disable-PeerDistribution.ps1 -WhatIf
    See exactly what would change. Changes nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Disable-PeerDistribution.ps1
    Apply both changes.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Disable-PeerDistribution.ps1 -Steps DownloadMode
    Stop the sharing, but leave the firewall rules as they are.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Disable-PeerDistribution.ps1 -Tag before-travel
    Apply, and label the backup so you can find it again.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('DownloadMode', 'Firewall', 'Both')]
    [string] $Steps = 'Both',
    [string] $Tag   = ''
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$doReg = ($Steps -eq 'Both' -or $Steps -eq 'DownloadMode')
$doFw  = ($Steps -eq 'Both' -or $Steps -eq 'Firewall')

Write-Host ''
Write-Host '  Update distribution - stop sharing updates with other machines'
Write-Host ('  ' + ('-' * 74))

$state = Get-UdState

# --- elevation --------------------------------------------------------------
# Checked here rather than at the top, so that -WhatIf works for anyone.
if (-not $state.elevated -and -not $WhatIfPreference) {
    Write-Host ''
    Write-Host '    This needs administrator rights.'
    Write-Host ''
    Write-Host '    These are machine-wide settings - the download mode applies to every'
    Write-Host '    account on this PC, and firewall rules are not per-user either. That is'
    Write-Host '    why this one asks, when the visual-effects module never does.'
    Write-Host ''
    Write-Host '    Close this and double-click "3 - Apply the changes.cmd" instead. It will'
    Write-Host '    ask Windows for permission properly.'
    Write-Host ''
    Write-Host '    Or, to see what it would do without any rights at all:'
    Write-Host '        powershell -ExecutionPolicy Bypass -File .\Disable-PeerDistribution.ps1 -WhatIf'
    Write-Host ''
    return
}

# --- work out what would change --------------------------------------------
$plan = New-Object System.Collections.Generic.List[object]

if ($doReg) {
    foreach ($r in $script:UdRegistry) {
        $e = $state.registry["$($r.Key)|$($r.Name)"]
        $cur = if ($e.existed) { [int]$e.value } else { $null }
        $plan.Add([pscustomobject]@{
            kind    = 'registry'
            rule    = $r
            name    = $r.Name
            from    = $(if ($e.existed) { "$($e.value)" } else { '<not set>' })
            to      = "$($r.Target)"
            needed  = ($cur -ne $r.Target)
            note    = $r.Desc
        })
    }
}
if ($doFw) {
    foreach ($f in $script:UdFirewallRules) {
        $e = $state.firewall[$f.Name]
        if (-not $e.present) {
            $plan.Add([pscustomobject]@{ kind='firewall'; rule=$f; name=$f.Name; from='rule absent'; to='-'; needed=$false; note='not on this machine' })
            continue
        }
        if ($null -eq $e.enabled) {
            $plan.Add([pscustomobject]@{ kind='firewall'; rule=$f; name=$f.Name; from='unreadable'; to='-'; needed=$false; note='state could not be read' })
            continue
        }
        $plan.Add([pscustomobject]@{
            kind   = 'firewall'
            rule   = $f
            name   = $f.Name
            from   = $(if ($e.enabled) { 'enabled' } else { 'disabled' })
            to     = 'disabled'
            needed = ($e.enabled -ne $f.Target)
            note   = $f.Desc
        })
    }
}

Write-Host ''
foreach ($p in $plan) {
    $mark = if ($p.needed) { '->' } else { '  ' }
    Write-Host ("    {0} {1,-30} {2,-12} {3,-10} {4}" -f $mark, $p.name, $p.from, $p.to, $p.note)
}
$needed = @($plan | Where-Object { $_.needed })

# --- WhatIf -----------------------------------------------------------------
if ($WhatIfPreference) {
    Write-Host ''
    Write-Host ('  ' + ('-' * 74))
    Write-Host ("    PREVIEW ONLY - nothing was changed.  would change: {0}" -f $needed.Count)
    Write-Host ''
    if ($needed.Count -and -not $state.elevated) {
        Write-Host '    Applying these for real will need administrator rights.'
        Write-Host ''
    }
    return
}

if ($needed.Count -eq 0) {
    Write-Host ''
    Write-Host '    Nothing to do - already set the way this module wants it.'
    Write-Host ''
    # Exit code 4 = "nothing to do". Audit finding: with a bare return (exit 0),
    # a round trip on an ALREADY-APPLIED machine sailed on, ran the real undo
    # against the newest old backup, un-applied the machine, then reported FAIL
    # against the undo - which had worked perfectly. Callers need to know that
    # no backup was written and nothing was moved.
    exit 4
}

# --- backup, and refuse to continue without one -----------------------------
Write-Host ''
$backupDir = Join-Path $here 'backups'
# -RecordAsOriginal: this is the apply path, reading the machine before it
# changes anything, so this is the only reading entitled to define "original".
$backup = Save-UdBackup -State $state -Directory $backupDir -Tag $Tag -RecordAsOriginal
if (-not $backup) {
    Write-Host ''
    Write-Host '    STOPPING. Nothing has been changed.'
    Write-Host ''
    Write-Host '    The backup could not be written and verified, so there would be no'
    Write-Host '    reliable way to undo these changes. Changing settings without a'
    Write-Host '    working undo is how people end up stuck.'
    Write-Host ''
    # Exit code 3 means "refused: no verified backup". Callers MUST key off this
    # rather than searching the output for a word. Test-RoundTrip.ps1 previously
    # matched the text "STOPPING" in this script's output, which produced a
    # FALSE POSITIVE: the backup had in fact succeeded and the settings had been
    # applied, but the round trip believed nothing had happened and skipped the
    # undo - leaving the machine changed when the test is supposed to be net zero.
    exit 3
}
Write-Host ("    backup written and verified: {0}" -f (Split-Path -Leaf $backup))

# --- apply ------------------------------------------------------------------
$changed = 0; $already = 0; $failed = 0
Write-Host ''
Write-Host '    applying:'

foreach ($p in $plan) {
    if (-not $p.needed) { $already++; continue }

    if ($p.kind -eq 'registry') {
        if (-not $PSCmdlet.ShouldProcess($p.name, "set to $($p.to)")) { continue }
        if (Set-UdRegistryValue -Key $p.rule.Key -Name $p.rule.Name -Value $p.rule.Target -Kind $p.rule.Kind) {
            Write-Host ("      set  {0,-30} {1} -> {2}" -f $p.name, $p.from, $p.to); $changed++
        } else { $failed++ }
    }
    else {
        if (-not $PSCmdlet.ShouldProcess($p.name, 'disable inbound rule')) { continue }
        if (Set-UdFirewallRuleEnabled -Name $p.rule.Name -Enabled $p.rule.Target) {
            Write-Host ("      set  {0,-30} {1} -> {2}" -f $p.name, $p.from, $p.to); $changed++
        } else { $failed++ }
    }
}

# --- verify against the machine, not against our own intentions -------------
Start-Sleep -Milliseconds 500
$after = Get-UdState

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    changed: {0}, already as wanted: {1}, failed: {2}" -f $changed, $already, $failed)
Write-Host ''
Write-Host '    now reading the machine back:'
Write-Host ("      download mode (service says) : {0}" -f $(if ($after.runtime.available) { $after.runtime.effectiveModeName } else { 'unavailable' }))
Write-Host ("      listening on port {0}        : {1}" -f $script:UdPeerPort, $(if ($after.listener.listening) { 'YES - ' + ($after.listener.addresses -join ', ') } else { 'no' }))
foreach ($f in $script:UdFirewallRules) {
    $e = $after.firewall[$f.Name]
    Write-Host ("      {0,-28}: {1}" -f $f.Name, $(if (-not $e.present) { 'absent' } elseif ($e.enabled) { 'still enabled' } else { 'disabled' }))
}

if ($after.runtime.available -and $after.runtime.effectiveModeName -notmatch 'CdnOnly|Simple' -and $doReg) {
    Write-Host ''
    Write-Host '    NOTE: the service still reports a peer-capable mode. Delivery Optimization'
    Write-Host '    re-reads its configuration periodically rather than instantly, so this can'
    Write-Host '    simply be a stale reading. Run "1 - Check what is on now.cmd" again in a'
    Write-Host '    few minutes. If it still disagrees with the registry value after a reboot,'
    Write-Host '    that is a real finding and worth reporting - it would mean this edition of'
    Write-Host '    Windows is ignoring the policy.'
}

if ($after.listener.listening) {
    Write-Host ''
    Write-Host '    NOTE: the port is still open. The firewall rules decide whether anything'
    Write-Host '    can REACH it; the service decides whether it is listening at all. With the'
    Write-Host '    inbound rules disabled, an open socket behind a closed door is not the same'
    Write-Host '    exposure - but it is not nothing either, and this script does not pretend'
    Write-Host '    otherwise. Stopping the listener entirely would mean stopping DoSvc, which'
    Write-Host '    would break Windows Update downloads.'
}

Write-Host ''
Write-Host '    To undo: double-click "4 - UNDO everything.cmd"'
Write-Host ''
