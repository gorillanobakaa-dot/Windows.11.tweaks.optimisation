<#
.SYNOPSIS
    Undo the Copilot SETTINGS. Works with no arguments at all.

.DESCRIPTION
    Restores the tier 1 settings - the taskbar button and the policy values -
    from the most recent backup. Where a value did not exist before, it is
    REMOVED rather than set to zero, and a key this module created is removed
    too if nothing else has been written into it.

    -------------------------------------------------------------------------
    WHAT THIS CANNOT DO, STATED PLAINLY
    -------------------------------------------------------------------------
    It cannot reinstall removed software. If Remove-Copilot.ps1 was run with
    -RemoveApp or -RemoveSystemInstall, those removals are recorded in
    backups\removed-not-restorable.json with the route back (the Store link,
    the version). This script reports that file's contents so you know, but
    restoring 1.3 GB of deleted software from a JSON file is not a thing, and
    this script will never claim otherwise.

    The HKLM policy value needs administrator rights to restore; the rest does
    not. Unelevated, the HKLM part is skipped and named.

.PARAMETER Original
    Restore from the write-once original-state.json rather than the most recent
    backup.

.PARAMETER Backup
    Restore from a specific backup file. Use -List to see them.

.PARAMETER List
    Show the available backups and exit.

.PARAMETER WhatIf
    Say what would be restored and restore nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-Copilot.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-Copilot.ps1 -Original
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
    $all = Get-CpBackups -Directory $backupDir
    if (-not $all.Count) { Write-Host '    none - the settings have never been applied' }
    else {
        # Derived from the real candidate filter, not a second hand-written
        # pattern: the audit caught '*pre-restore*' here annotating BACKWARDS -
        # internal snapshots unmarked, an honest user tag marked as hidden.
        $offered = @(Get-CpRestoreCandidates -Directory $backupDir | ForEach-Object Name)
        foreach ($b in $all) {
            $note = if ($offered -notcontains $b.Name) { '   (internal snapshot - not offered as a restore point)' } else { '' }
            Write-Host ("    {0,-52} {1}{2}" -f $b.Name, $b.LastWriteTime, $note)
        }
    }
    $orig = Join-Path $backupDir 'original-state.json'
    Write-Host ''
    if (Test-Path $orig) { Write-Host ("    original-state.json                                  {0}   <- -Original uses this" -f (Get-Item $orig).LastWriteTime) }
    else                 { Write-Host '    original-state.json                                  not present' }
    $rec = Join-Path $backupDir 'removed-not-restorable.json'
    if (Test-Path $rec) {
        Write-Host ''
        Write-Host '    removed-not-restorable.json exists: software has been REMOVED and'
        Write-Host '    cannot be restored by this script. Its contents name the route back.'
    }
    Write-Host ''
    return
}

Write-Host ''
Write-Host '  Copilot - undo the settings'
Write-Host ('  ' + ('-' * 74))

$elevated = Test-CpElevated
if (-not $elevated) {
    Write-Host '    not running as administrator: the machine-wide policy value will be'
    Write-Host '    skipped and named. Use the numbered launcher for the full restore.'
}

# --- pick a source ----------------------------------------------------------
$sourcePath = $null; $sourceWhat = ''
if ($Original) {
    $sourcePath = Join-Path $backupDir 'original-state.json'
    $sourceWhat = 'the original state, from before this module was ever used'
    if (-not (Test-Path $sourcePath)) {
        Write-Host ''
        Write-Host '    There is no original-state.json. It is written the first time the'
        Write-Host '    apply script runs; if it is missing, the settings were never applied.'
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
    $candidates = Get-CpRestoreCandidates -Directory $backupDir
    if (-not $candidates.Count) {
        Write-Host ''; Write-Host '    There is nothing to undo - no backups exist.'; Write-Host ''
        return
    }
    foreach ($c in $candidates) {
        try {
            $try = Get-Content $c.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if (Test-CpStateShape -State $try) { $sourcePath = $c.FullName; break }
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
if (-not (Test-CpStateShape -State $state)) {
    Write-Host ''; Write-Host "    $sourcePath is not a state file this module recognises. Nothing was changed."; Write-Host ''
    return
}

Write-Host ''
Write-Host ("    restoring from : {0}" -f (Split-Path -Leaf $sourcePath))
Write-Host ("    which is       : {0}" -f $sourceWhat)
Write-Host ("    recorded at    : {0}" -f $state.takenAt)

$now = Get-CpState
Write-Host ''
Write-Host '    would restore:'
foreach ($r in $script:CpRegistry) {
    $k = "$($r.Key)|$($r.Name)"
    $want = $state.registry.$k
    $cur  = $now.registry[$k]
    $wantShown = if ($want -and $want.existed) { "$($want.value)" } else { '<not set - the value gets removed>' }
    $curShown  = if ($cur.existed) { "$($cur.value)" } else { '<not set>' }
    $adm = if ($r.Key -like 'HKLM*' -and -not $elevated) { '   NEEDS ADMIN - will be skipped' } else { '' }
    Write-Host ("      {0,-24} {1,-11} -> {2}{3}" -f $r.Name, $curShown, $wantShown, $adm)
}

if ($WhatIfPreference) {
    Write-Host ''; Write-Host ('  ' + ('-' * 74)); Write-Host '    PREVIEW ONLY - nothing was changed.'; Write-Host ''
    return
}
if (-not $PSCmdlet.ShouldProcess('Copilot settings', 'restore')) { return }

# Snapshot where we are now, tagged pre-restore so it is never offered as a
# restore point. No -RecordAsOriginal: the undo path may not define "original".
$preSnap = Save-CpBackup -State $now -Directory $backupDir -InternalSuffix 'prerestore'
if (-not $preSnap) {
    Write-Host ''
    Write-Host '    STOPPING. Nothing has been restored.'
    Write-Host '    The pre-restore snapshot could not be written and verified. The apply'
    Write-Host '    refuses to run without a verified backup, and the undo holds itself'
    Write-Host '    to the same rule.'
    Write-Host ''
    return
}

Write-Host ''
Write-Host '    restoring:'
$result = Restore-CpState -State $state

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    restored: {0}  skipped: {1}  failed: {2}" -f $result.Restored, $result.Skipped, $result.Failed)
foreach ($d in $result.SkippedDetail) { Write-Host ("      skipped: {0}" -f $d) }
foreach ($d in $result.FailedDetail)  { Write-Host ("      FAILED : {0}" -f $d) }
foreach ($d in $result.Ignored)       { Write-Host ("      ignored: {0} - not a setting this module owns" -f $d) }

# --- the honest part --------------------------------------------------------
$rec = Join-Path $backupDir 'removed-not-restorable.json'
if (Test-Path $rec) {
    Write-Host ''
    Write-Host '    SOFTWARE THIS SCRIPT CANNOT PUT BACK:'
    try {
        $parsedRec = Get-Content $rec -Raw -Encoding UTF8 | ConvertFrom-Json
        $doc = @($parsedRec)
        foreach ($e in $doc) {
            Write-Host ("      {0}  (v{1}, removed {2:yyyy-MM-dd})" -f $e.what, $e.version, [datetime]$e.removedAt)
            Write-Host ("        route back: {0}" -f $e.routeBack)
        }
    }
    catch { Write-Host "      (the record could not be read: $rec)" }
}
Write-Host ''
