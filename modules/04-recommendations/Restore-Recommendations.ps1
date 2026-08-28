<#
.SYNOPSIS
    Undo the recommendation changes. Works with no arguments at all.

.DESCRIPTION
    Run it with nothing and it puts back whatever the most recent apply changed.
    That is the case that has to work, so it is the default.

    It restores BOTH tiers regardless of which were applied - if a previous run
    used -IncludeObserved, those settings are put back too. A restore that only
    covered the documented tier would strand the others.

    Where a setting did not exist before, this REMOVES it rather than writing a
    zero, and removes the key too if this module created it and nothing else has
    been written into it since. Most of these settings are absent on a default
    machine, so that path is the normal one here, not an edge case.

    Needs NO administrator rights.

.PARAMETER Original
    Go all the way back to how the account was before this module was ever used,
    from the write-once original-state.json.

.PARAMETER Backup
    Restore from a specific backup file. Use -List to see them.

.PARAMETER List
    Show the available backups and exit. Changes nothing.

.PARAMETER WhatIf
    Say what would be restored and restore nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-Recommendations.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-Recommendations.ps1 -Original

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-Recommendations.ps1 -List
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

if ($List) {
    Write-Host ''
    Write-Host '  Available backups'
    Write-Host ('  ' + ('-' * 74))
    $all = Get-RcBackups -Directory $backupDir
    if (-not $all.Count) { Write-Host '    none - this module has not been applied yet' }
    else {
        foreach ($b in $all) {
            $note = if ($b.Name -like '*pre-restore*') { '   (taken before an undo - not offered as a restore point)' } else { '' }
            Write-Host ("    {0,-52} {1}{2}" -f $b.Name, $b.LastWriteTime, $note)
        }
    }
    $orig = Join-Path $backupDir 'original-state.json'
    Write-Host ''
    if (Test-Path $orig) { Write-Host ("    original-state.json                                  {0}   <- -Original uses this" -f (Get-Item $orig).LastWriteTime) }
    else                 { Write-Host '    original-state.json                                  not present' }
    Write-Host ''
    return
}

Write-Host ''
Write-Host '  Recommendations and suggestions - undo'
Write-Host ('  ' + ('-' * 74))

# --- pick a source ----------------------------------------------------------
$sourcePath = $null; $sourceWhat = ''
if ($Original) {
    $sourcePath = Join-Path $backupDir 'original-state.json'
    $sourceWhat = 'the original state, from before this module was ever used'
    if (-not (Test-Path $sourcePath)) {
        Write-Host ''
        Write-Host '    There is no original-state.json.'
        Write-Host '    It is written the first time the apply script runs. If it is missing,'
        Write-Host '    this module has never been applied for this account.'
        Write-Host ''
        return
    }
}
elseif ($Backup) {
    $sourcePath = $Backup; $sourceWhat = 'the backup you named'
    if (-not (Test-Path $sourcePath)) {
        Write-Host ''; Write-Host "    No such file: $Backup"; Write-Host '    Use -List to see what is available.'; Write-Host ''
        return
    }
}
else {
    $candidates = Get-RcRestoreCandidates -Directory $backupDir
    if (-not $candidates.Count) {
        Write-Host ''
        Write-Host '    There is nothing to undo - no backups exist.'
        Write-Host ''
        return
    }
    foreach ($c in $candidates) {
        try {
            $try = Get-Content $c.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if (Test-RcStateShape -State $try) { $sourcePath = $c.FullName; break }
            Write-Host ("    skipping {0} - not a usable state file" -f $c.Name)
        }
        catch { Write-Host ("    skipping {0} - will not parse" -f $c.Name) }
    }
    if (-not $sourcePath) {
        Write-Host ''; Write-Host '    Backups exist but none can be read. Nothing was changed.'; Write-Host ''
        return
    }
    $sourceWhat = 'the most recent usable backup'
}

try { $state = Get-Content $sourcePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
catch {
    Write-Host ''; Write-Host "    Could not read $sourcePath"; Write-Host "    $($_.Exception.Message)"
    Write-Host '    Nothing was changed.'; Write-Host ''
    return
}
if (-not (Test-RcStateShape -State $state)) {
    Write-Host ''; Write-Host "    $sourcePath is not a state file this module recognises."
    Write-Host '    Nothing was changed.'; Write-Host ''
    return
}

Write-Host ''
Write-Host ("    restoring from : {0}" -f (Split-Path -Leaf $sourcePath))
Write-Host ("    which is       : {0}" -f $sourceWhat)
Write-Host ("    recorded at    : {0}" -f $state.takenAt)

$now = Get-RcState
Write-Host ''
Write-Host '    would restore:'
foreach ($r in (Get-RcAllSettings)) {
    $k = "$($r.Key)|$($r.Name)"
    $want = $state.registry.$k
    $cur  = $now.registry[$k]
    # Audit finding 9: $want is $null when the entry is MISSING from the backup,
    # and the restore then SKIPS it - the old text promised a removal that never
    # happened. The three cases are now told apart.
    $wantShown = if ($null -eq $want) { '<not in this backup - will be skipped>' }
                 elseif ($want.existed) { "$($want.value)" }
                 else { '<not set - the value gets removed>' }
    $curShown  = if ($cur.existed) { "$($cur.value)" } else { '<not set>' }
    Write-Host ("      {0,-46} {1,-11} -> {2}" -f $r.Name, $curShown, $wantShown)
}

if ($WhatIfPreference) {
    Write-Host ''; Write-Host ('  ' + ('-' * 74))
    Write-Host '    PREVIEW ONLY - nothing was changed.'; Write-Host ''
    return
}
if (-not $PSCmdlet.ShouldProcess('recommendation settings', 'restore')) { return }

# Snapshot where we are now, tagged pre-restore so it is never itself offered
# as a restore point. No -RecordAsOriginal: the undo path may not define
# "original".
$preSnap = Save-RcBackup -State $now -Directory $backupDir -InternalSuffix 'prerestore'
if (-not $preSnap) {
    Write-Host ''
    Write-Host '    STOPPING. Nothing has been restored.'
    Write-Host '    The snapshot of the CURRENT state could not be written, so going ahead'
    Write-Host '    would make this undo itself un-undoable.'
    Write-Host ''
    return
}

Write-Host ''
Write-Host '    restoring:'
$result = Restore-RcState -State $state

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    restored: {0}  skipped: {1}  failed: {2}" -f $result.Restored, $result.Skipped, $result.Failed)
if ($result.PSObject.Properties['KeyCleanupFailures'] -and $result.KeyCleanupFailures -gt 0) {
    Write-Host ("    KEY CLEANUP FAILURES: {0} - a key this module created could not be" -f $result.KeyCleanupFailures)
    Write-Host  '    removed. The values are restored, but check the FAILED lines above.'
}
foreach ($d in $result.SkippedDetail) { Write-Host ("      skipped: {0}" -f $d) }
foreach ($d in $result.FailedDetail)  { Write-Host ("      FAILED : {0}" -f $d) }
foreach ($d in $result.Ignored)       { Write-Host ("      ignored: {0} - not a setting this module owns" -f $d) }
Write-Host ''
