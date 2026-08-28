<#
.SYNOPSIS
    Undo the update-distribution changes. Works with no arguments at all.

.DESCRIPTION
    Run it with nothing and it puts back whatever the most recent apply changed.
    That is the case that has to work, so it is the default.

    The undo here has a wrinkle the visual-effects module never had. On a default
    machine the Delivery Optimization policy key does not exist, so applying this
    module CREATES it. Undoing therefore means DELETING the value - and removing
    the key too, if this module created it and nothing else has been written into
    it since. Writing a zero back instead would leave the machine looking
    deliberately configured when it never was, and those are different states.

    Restoring is driven by the module's own list of settings, not by whatever the
    backup file happens to contain. An entry in the file this module does not own
    is reported and ignored, never applied. Every write is read back, and a write
    that did not stick is reported as failed rather than counted as restored.

    NEEDS ADMINISTRATOR RIGHTS, for the same reason the apply script does.

.PARAMETER Original
    Go all the way back to how the machine was before this module was ever used,
    from the write-once original-state.json. That file is written once and never
    overwritten.

.PARAMETER Backup
    Restore from a specific backup file. Use -List to see them.

.PARAMETER List
    Show the available backups and exit. Changes nothing, needs no rights.

.PARAMETER WhatIf
    Say what would be restored and restore nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-UpdateDistribution.ps1
    Undo the last apply.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-UpdateDistribution.ps1 -Original
    Go back to how the machine was before this module existed.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-UpdateDistribution.ps1 -List
    List the backups without touching anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-UpdateDistribution.ps1 -Backup .\backups\state_2026-08-26_12-00-00.json
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch] $Original,
    [string] $Backup,
    [switch] $List
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$backupDir = Join-Path $here 'backups'

# --- list -------------------------------------------------------------------
if ($List) {
    Write-Host ''
    Write-Host '  Available backups'
    Write-Host ('  ' + ('-' * 74))
    $all = Get-UdBackups -Directory $backupDir
    if (-not $all.Count) {
        Write-Host '    none - this module has not been applied yet'
    } else {
        foreach ($b in $all) {
            $note = if ($b.Name -like '*pre-restore*') { '   (snapshot taken before an undo - not offered as a restore point)' } else { '' }
            Write-Host ("    {0,-46} {1}{2}" -f $b.Name, $b.LastWriteTime, $note)
        }
    }
    $orig = Join-Path $backupDir 'original-state.json'
    Write-Host ''
    if (Test-Path $orig) { Write-Host ("    original-state.json                            {0}   <- -Original uses this" -f (Get-Item $orig).LastWriteTime) }
    else                 { Write-Host '    original-state.json                            not present' }
    Write-Host ''
    return
}

Write-Host ''
Write-Host '  Update distribution - undo'
Write-Host ('  ' + ('-' * 74))

# --- pick a source ----------------------------------------------------------
$sourcePath = $null
$sourceWhat = ''

if ($Original) {
    $sourcePath = Join-Path $backupDir 'original-state.json'
    $sourceWhat = 'the original state, from before this module was ever used'
    if (-not (Test-Path $sourcePath)) {
        Write-Host ''
        Write-Host '    There is no original-state.json.'
        # Audit finding: this message used to assert "this module has never been
        # applied on this machine", which is false whenever the file was deleted,
        # failed to write, or the folder was copied without it - while ordinary
        # backups recording the true original sat alongside. Report what is
        # actually known instead of guessing.
        $others = Get-UdRestoreCandidates -Directory $backupDir
        if ($others.Count) {
            Write-Host '    However, ordinary backups DO exist, so the module has been applied and'
            Write-Host '    the write-once original record is missing (deleted, failed to write, or'
            Write-Host '    the folder was moved without it). The OLDEST ordinary backup is the'
            Write-Host '    closest thing to the original state:'
            $oldest = $others | Sort-Object LastWriteTime | Select-Object -First 1
            Write-Host ("        {0}  ({1})" -f $oldest.Name, $oldest.LastWriteTime)
            Write-Host '    Restore it explicitly with:'
            Write-Host ("        .\Restore-UpdateDistribution.ps1 -Backup '.\backups\{0}'" -f $oldest.Name)
        } else {
            Write-Host '    No ordinary backups exist either - the settings have not been applied'
            Write-Host '    by this module on this machine.'
        }
        Write-Host ''
        return
    }
}
elseif ($Backup) {
    $sourcePath = $Backup
    $sourceWhat = 'the backup you named'
    if (-not (Test-Path $sourcePath)) {
        Write-Host ''
        Write-Host "    No such file: $Backup"
        Write-Host '    Use -List to see what is available.'
        Write-Host ''
        return
    }
}
else {
    # Newest usable backup, skipping the snapshots taken just before a restore.
    # Including those is what made module 01's undo re-apply itself when run twice.
    $candidates = Get-UdRestoreCandidates -Directory $backupDir
    if (-not $candidates.Count) {
        Write-Host ''
        Write-Host '    There is nothing to undo - no backups exist.'
        Write-Host '    This module has not been applied on this machine.'
        Write-Host ''
        return
    }
    foreach ($c in $candidates) {
        try {
            $try = Get-Content $c.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if (Test-UdStateShape -State $try) { $sourcePath = $c.FullName; break }
            Write-Host ("    skipping {0} - not a usable state file" -f $c.Name)
        }
        catch { Write-Host ("    skipping {0} - will not parse" -f $c.Name) }
    }
    if (-not $sourcePath) {
        Write-Host ''
        Write-Host '    Backups exist but none of them can be read. Nothing was changed.'
        Write-Host ''
        return
    }
    $sourceWhat = 'the most recent usable backup'
}

# --- load and validate ------------------------------------------------------
try   { $state = Get-Content $sourcePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
catch {
    Write-Host ''
    Write-Host "    Could not read $sourcePath"
    Write-Host "    $($_.Exception.Message)"
    Write-Host '    Nothing was changed.'
    Write-Host ''
    return
}
if (-not (Test-UdStateShape -State $state)) {
    Write-Host ''
    Write-Host "    $sourcePath is not a state file this module recognises."
    Write-Host '    Nothing was changed.'
    Write-Host ''
    return
}

Write-Host ''
Write-Host ("    restoring from : {0}" -f (Split-Path -Leaf $sourcePath))
Write-Host ("    which is       : {0}" -f $sourceWhat)
Write-Host ("    recorded at    : {0}" -f $state.takenAt)

# --- show the plan ----------------------------------------------------------
$now = Get-UdState
Write-Host ''
Write-Host '    would restore:'
foreach ($r in $script:UdRegistry) {
    $k = "$($r.Key)|$($r.Name)"
    $want = $state.registry.$k
    $cur  = $now.registry[$k]
    $wantShown = if ($want -and $want.existed) { "$($want.value)" } else { '<not set - the value gets removed>' }
    $curShown  = if ($cur.existed) { "$($cur.value)" } else { '<not set>' }
    Write-Host ("      {0,-30} {1,-12} -> {2}" -f $r.Name, $curShown, $wantShown)
}
foreach ($f in $script:UdFirewallRules) {
    $want = $state.firewall.$($f.Name)
    $cur  = $now.firewall[$f.Name]
    $wantShown = if ($want -and $want.present -and $null -ne $want.enabled) { $(if ($want.enabled) { 'enabled' } else { 'disabled' }) } else { '<not recorded>' }
    $curShown  = if (-not $cur.present) { 'absent' } elseif ($cur.enabled) { 'enabled' } else { 'disabled' }
    Write-Host ("      {0,-30} {1,-12} -> {2}" -f $f.Name, $curShown, $wantShown)
}

if ($WhatIfPreference) {
    Write-Host ''
    Write-Host ('  ' + ('-' * 74))
    Write-Host '    PREVIEW ONLY - nothing was changed.'
    Write-Host ''
    return
}

if (-not $now.elevated) {
    Write-Host ''
    Write-Host '    This needs administrator rights, for the same reason applying does.'
    Write-Host '    Close this and double-click "4 - UNDO everything.cmd" instead.'
    Write-Host ''
    return
}

if (-not $PSCmdlet.ShouldProcess('update distribution settings', 'restore')) { return }

# --- snapshot where we are now, before undoing ------------------------------
# Tagged pre-restore so it is never itself offered as a restore point.
$preSnap = Save-UdBackup -State $now -Directory $backupDir -InternalSuffix 'prerestore'
if (-not $preSnap) {
    # Audit finding: the apply path treats a failed backup as fatal, but the
    # undo path discarded the same signal with [void](...) and restored anyway -
    # so if backups\ had gone read-only, the applied state became unrecoverable
    # mid-undo with only a buried BACKUP FAILED line to show for it.
    Write-Host ''
    Write-Host '    STOPPING. Nothing has been restored.'
    Write-Host '    The snapshot of the CURRENT state could not be written, so going ahead'
    Write-Host '    would make this undo itself un-undoable.'
    Write-Host ''
    return
}

Write-Host ''
Write-Host '    restoring:'
$result = Restore-UdState -State $state

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    restored: {0}  skipped: {1}  failed: {2}" -f $result.Restored, $result.Skipped, $result.Failed)
foreach ($d in $result.SkippedDetail) { Write-Host ("      skipped: {0}" -f $d) }
foreach ($d in $result.FailedDetail)  { Write-Host ("      FAILED : {0}" -f $d) }
foreach ($d in $result.Ignored)       { Write-Host ("      ignored: {0} - not a setting this module owns" -f $d) }

$after = Get-UdState
Write-Host ''
Write-Host '    reading the machine back:'
foreach ($r in $script:UdRegistry) {
    $e = $after.registry["$($r.Key)|$($r.Name)"]
    Write-Host ("      {0,-30} {1}" -f $r.Name, $(if ($e.existed) { "$($e.value)" } else { '<not set>' }))
}
foreach ($f in $script:UdFirewallRules) {
    $e = $after.firewall[$f.Name]
    Write-Host ("      {0,-30} {1}" -f $f.Name, $(if (-not $e.present) { 'absent' } elseif ($e.enabled) { 'enabled' } else { 'disabled' }))
}
Write-Host ''
