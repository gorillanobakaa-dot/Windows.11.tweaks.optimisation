<#
.SYNOPSIS
    Undo: put every service start type back from a backup. Works with no
    arguments at all.

.DESCRIPTION
    The backup covers EVERY Win32 service on the machine, not only the ones a
    profile changed, so this restores the machine's service configuration as
    a whole. Values are validated against what a service start type can
    legally be before anything is written.

    Exit codes: 0 = restored (or nothing to do); 3 = the pre-restore snapshot
    could not be written, nothing touched; 5 = completed with failures.

.PARAMETER Original
    Restore from the write-once original-state.json.

.PARAMETER Backup
    Restore from a specific backup file. Use -List to see them.

.PARAMETER List
    Show the available backups and exit.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$Original, [string]$Backup, [switch]$List)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')
$backupDir = Join-Path $here 'backups'
$data = Get-SvcProfileData -Directory $here

if ($List) {
    Write-Host ''
    Write-Host '  Available backups'
    Write-Host ('  ' + ('-' * 74))
    $all = Get-SvcBackups -Directory $backupDir
    if (-not $all.Count) { Write-Host '    none - no profile has ever been applied' }
    else {
        $offered = @(Get-SvcRestoreCandidates -Directory $backupDir | ForEach-Object Name)
        foreach ($b in $all) {
            $note = if ($offered -notcontains $b.Name) { '   (internal snapshot - not offered as a restore point)' } else { '' }
            Write-Host ("    {0,-52} {1}{2}" -f $b.Name, $b.LastWriteTime, $note)
        }
    }
    $orig = Join-Path $backupDir 'original-state.json'
    Write-Host ''
    if (Test-Path $orig) { Write-Host ("    original-state.json   {0}   <- -Original uses this" -f (Get-Item $orig).LastWriteTime) }
    else                 { Write-Host '    original-state.json   not present' }
    Write-Host ''
    return
}

Write-Host ''
Write-Host '  Services - undo'
Write-Host ('  ' + ('-' * 74))

if (-not (Test-SvcElevated)) {
    Write-Host '    Service start types are machine-wide: this needs administrator rights.'
    Write-Host '    Nothing was changed. Use the numbered launcher.'
    Write-Host ''
    exit 4     # not 0: 'could not run' must not read as 'restored'
}

$sourcePath = $null; $sourceWhat = ''
if ($Original) {
    $sourcePath = Join-Path $backupDir 'original-state.json'
    $sourceWhat = 'the original state, from before this module was ever used'
    if (-not (Test-Path $sourcePath)) {
        Write-Host ''; Write-Host '    There is no original-state.json - no profile has ever been applied.'; Write-Host ''
        return
    }
}
elseif ($Backup) {
    $sourcePath = $Backup; $sourceWhat = 'the backup you named'
    if (-not (Test-Path $sourcePath)) {
        Write-Host ''; Write-Host "    No such file: $Backup"; Write-Host ''
        return
    }
}
else {
    $candidates = Get-SvcRestoreCandidates -Directory $backupDir
    if (-not $candidates.Count) {
        Write-Host ''; Write-Host '    There is nothing to undo - no backups exist.'; Write-Host ''
        return
    }
    foreach ($c in $candidates) {
        try {
            $try = Get-Content $c.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if (Test-SvcStateShape -State $try) { $sourcePath = $c.FullName; break }
            Write-Host ("    skipping {0} - not a usable state file" -f $c.Name)
        }
        catch { Write-Host ("    skipping {0} - will not parse" -f $c.Name) }
    }
    if (-not $sourcePath) {
        Write-Host ''; Write-Host '    Backups exist but none can be read. Nothing was changed.'; Write-Host ''
        exit 3
    }
    $sourceWhat = 'the most recent usable backup'
}

try { $state = Get-Content $sourcePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
catch {
    Write-Host ''; Write-Host "    Could not read $sourcePath : $($_.Exception.Message)"; Write-Host ''
    return
}
if (-not (Test-SvcStateShape -State $state)) {
    Write-Host ''; Write-Host "    $sourcePath is not a state file this module recognises. Nothing was changed."; Write-Host ''
    exit 3
}

Write-Host ''
Write-Host ("    restoring from : {0}" -f (Split-Path -Leaf $sourcePath))
Write-Host ("    which is       : {0}" -f $sourceWhat)
Write-Host ("    recorded at    : {0}" -f $state.takenAt)

# What would move
$moves = 0
foreach ($prop in (Get-SvcEntries -Services $state.services)) {
    $cur = Get-SvcEntry -Name $prop.Name
    if ($cur.existed -and $prop.Value.existed -and (Test-SvcValidStart $prop.Value.start) -and
        ($cur.start -as [int]) -ne ($prop.Value.start -as [int])) { $moves++ }
}
Write-Host ("    services whose start type would change : {0}" -f $moves)

if ($WhatIfPreference) {
    Write-Host ''; Write-Host '    PREVIEW ONLY - nothing was changed.'; Write-Host ''
    return
}
if (-not $PSCmdlet.ShouldProcess('service start types', 'restore')) {
    Write-Host ''; Write-Host '    Declined at the prompt. Nothing was changed.'; Write-Host ''
    exit 4
}

$now = Get-SvcState
$preSnap = Save-SvcBackup -State $now -Directory $backupDir -InternalSuffix 'prerestore'
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
$result = Restore-SvcState -State $state -Data $data

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    restored: {0}  skipped: {1}  failed: {2}" -f $result.Restored, $result.Skipped, $result.Failed)
foreach ($d in $result.FailedDetail) { Write-Host ("      FAILED : {0}" -f $d) }
# SkippedDetail was built and then discarded, so 'not installed on this
# machine' reasons never reached anyone. Summarised rather than dumped: on a
# full restore the list runs to ~90 lines.
if ($result.SkippedDetail.Count -and $VerbosePreference -ne 'SilentlyContinue') {
    foreach ($d in $result.SkippedDetail) { Write-Host ("      skipped: {0}" -f $d) }
} elseif ($result.SkippedDetail.Count) {
    Write-Host ("      ({0} skipped - run with -Verbose to see why each one)" -f $result.SkippedDetail.Count)
}
Write-Host ''
Write-Host '    Services that were stopped are not restarted here - a restart does'
Write-Host '    that cleanly, and starting 100 services by hand is how you find out'
Write-Host '    which ones did not like it.'
Write-Host ''
if ($result.Failed -gt 0) { exit 5 }
