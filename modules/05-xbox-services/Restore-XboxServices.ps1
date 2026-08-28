<#
.SYNOPSIS
    Undo: put the Xbox services and the scheduled task back from a backup.
    Works with no arguments at all.

.DESCRIPTION
    Restores every service start type and the task state from the most recent
    usable backup (or -Original, or a named -Backup). Values are validated
    against what a start type can legally be before anything is written - a
    backup is data, and data can be edited.

    Needs administrator rights for the same reason the apply does.

.PARAMETER Original
    Restore from the write-once original-state.json.

.PARAMETER Backup
    Restore from a specific backup file. Use -List to see them.

.PARAMETER List
    Show the available backups and exit.

.PARAMETER WhatIf
    Say what would be restored and restore nothing.

.NOTES
    Exit codes, so a caller can gate on outcomes instead of parsing text:
    0 = restored (or legitimately nothing to restore); 3 = the pre-restore
    snapshot could not be written, nothing touched; 5 = completed but one or
    more restores FAILED.
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
    $all = Get-XsBackups -Directory $backupDir
    if (-not $all.Count) { Write-Host '    none - the module has never been applied' }
    else {
        # Annotation derived from the real candidate filter, never a second
        # hand-written pattern (module 03 audit: the copy annotated backwards).
        $offered = @(Get-XsRestoreCandidates -Directory $backupDir | ForEach-Object Name)
        foreach ($b in $all) {
            $note = if ($offered -notcontains $b.Name) { '   (internal snapshot - not offered as a restore point)' } else { '' }
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
Write-Host '  Xbox services - undo'
Write-Host ('  ' + ('-' * 74))

$elevated = Test-XsElevated
if (-not $elevated) {
    Write-Host '    not running as administrator: nothing can be restored. Use the'
    Write-Host '    numbered launcher, which asks Windows for elevation properly.'
    Write-Host ''
    return
}

$sourcePath = $null; $sourceWhat = ''
if ($Original) {
    $sourcePath = Join-Path $backupDir 'original-state.json'
    $sourceWhat = 'the original state, from before this module was ever used'
    if (-not (Test-Path $sourcePath)) {
        Write-Host ''
        Write-Host '    There is no original-state.json. It is written the first time the'
        Write-Host '    apply script runs; if it is missing, the module was never applied.'
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
    $candidates = Get-XsRestoreCandidates -Directory $backupDir
    if (-not $candidates.Count) {
        Write-Host ''; Write-Host '    There is nothing to undo - no backups exist.'; Write-Host ''
        return
    }
    foreach ($c in $candidates) {
        try {
            $try = Get-Content $c.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if (Test-XsStateShape -State $try) { $sourcePath = $c.FullName; break }
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
    Write-Host ''; Write-Host "    Could not read $sourcePath : $($_.Exception.Message)"
    Write-Host '    Nothing was changed.'; Write-Host ''
    return
}
if (-not (Test-XsStateShape -State $state)) {
    Write-Host ''; Write-Host "    $sourcePath is not a state file this module recognises. Nothing was changed."; Write-Host ''
    return
}

Write-Host ''
Write-Host ("    restoring from : {0}" -f (Split-Path -Leaf $sourcePath))
Write-Host ("    which is       : {0}" -f $sourceWhat)
Write-Host ("    recorded at    : {0}" -f $state.takenAt)

$now = Get-XsState
Write-Host ''
Write-Host '    would restore:'
foreach ($r in $script:XsServices) {
    $want = $state.services.($r.Name)
    $cur  = $now.services[$r.Name]
    $wantShown = if ($want -and $want.existed) { "Start=$($want.start)" } else { '<not recorded / not installed>' }
    $curShown  = if ($cur.existed) { "Start=$($cur.start)" } else { '<not installed>' }
    Write-Host ("      {0,-28} {1,-16} -> {2}" -f $r.Name, $curShown, $wantShown)
}
foreach ($t in $script:XsTasks) {
    $k = "$($t.Path)$($t.Name)"
    $want = $state.tasks.$k
    $cur  = $now.tasks[$k]
    $wantShown = if ($want -and $want.existed) { $(if ($want.enabled) { 'enabled' } else { 'disabled' }) } else { '<not recorded>' }
    $curShown  = if ($cur.existed) { $(if ($cur.enabled) { 'enabled' } else { 'disabled' }) } else { '<not present>' }
    Write-Host ("      task {0,-23} {1,-16} -> {2}" -f $t.Name, $curShown, $wantShown)
}

if ($WhatIfPreference) {
    Write-Host ''; Write-Host ('  ' + ('-' * 74)); Write-Host '    PREVIEW ONLY - nothing was changed.'; Write-Host ''
    return
}
if (-not $PSCmdlet.ShouldProcess('Xbox services', 'restore')) {
    Write-Host ''
    Write-Host '    Declined at the prompt. Nothing was changed.'
    Write-Host ''
    return
}

# Pre-restore snapshot: internal marker, never offered as a candidate, and
# FATAL if it cannot be written - the undo holds itself to the apply's rule.
$preSnap = Save-XsBackup -State $now -Directory $backupDir -InternalSuffix 'prerestore'
if (-not $preSnap) {
    Write-Host ''
    Write-Host '    STOPPING. Nothing has been restored. The pre-restore snapshot could'
    Write-Host '    not be written and verified, and the apply refuses to run without a'
    Write-Host '    verified backup - the undo holds itself to the same rule.'
    Write-Host ''
    exit 3
}

Write-Host ''
Write-Host '    restoring:'
$result = Restore-XsState -State $state

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    restored: {0}  skipped: {1}  failed: {2}" -f $result.Restored, $result.Skipped, $result.Failed)
foreach ($d in $result.SkippedDetail) { Write-Host ("      skipped: {0}" -f $d) }
foreach ($d in $result.FailedDetail)  { Write-Host ("      FAILED : {0}" -f $d) }
Write-Host ''
if ($result.Failed -gt 0) { exit 5 }
