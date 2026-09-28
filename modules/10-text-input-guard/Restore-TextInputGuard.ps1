<#
.SYNOPSIS
    Undo the TextInputHost guard module. Works with no arguments at all.

.DESCRIPTION
    With no arguments it puts things back as they were immediately before the
    last install: normally that means the guard task is removed.

    Before it changes anything it snapshots the current state (a file ending
    _~prerestore), so this undo can itself be undone with -Backup. If that
    snapshot cannot be written, nothing is changed.

    A backup can only put back a task of the kind this module creates: one
    that runs this module's own guard script, with your normal rights, with
    settings in range. Anything else found in a backup file is refused.

    This script is per-user. It needs no administrator rights and asks for
    none.

.PARAMETER Original
    Put back backups\original-state.json: the state before this module was
    ever installed. If that file does not exist, say so and stop.

.PARAMETER Backup
    Put back one named backup. A full path, or a file name inside backups\.

.PARAMETER List
    Show every restore point with its date and what it records, then stop.

.PARAMETER WhatIf
    Say what would be put back. Change nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-TextInputGuard.ps1
    Undo the last install (normally: remove the guard).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-TextInputGuard.ps1 -Original
    Back to how things were before this module was ever used.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-TextInputGuard.ps1 -List
    Show the restore points. Changes nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-TextInputGuard.ps1 -Backup state_2026-09-28_19-00-00.json
    Put back one particular restore point.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-TextInputGuard.ps1 -WhatIf
    Preview the undo. Changes nothing.

.NOTES
    Exit codes: 0 restored (or previewed, or already as recorded),
    3 refused: the pre-restore snapshot could not be written, nothing changed,
    4 nothing to restore or an unusable backup, nothing changed,
    5 the restore failed or was refused.
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

function Describe($State) {
    if ($State.task.existed) {
        $s = Get-TigTaskSettings -Xml ([string]$State.task.xml)
        if ($s) { 'guard installed: every {0} min, {1} % for {2} s' -f $s.IntervalMinutes, $s.ThresholdPercent, $s.WindowSeconds } else { 'guard installed (definition unreadable)' }
    } else { 'no guard installed' }
}

Write-Host ''
Write-Host '  TextInputHost guard - undo'
Write-Host ('  ' + ('-' * 74))

if ($List) {
    $orig = Join-Path $backupDir 'original-state.json'
    if (Test-Path -LiteralPath $orig) {
        $o = Read-TigBackup $orig
        Write-Host ("    {0,-44} {1}" -f 'original-state.json (use -Original)', $(if ($o) { Describe $o } else { 'UNREADABLE' }))
    } else { Write-Host '    original-state.json: none yet (written by the first install)' }
    $all = @(Get-TigBackups -BackupDir $backupDir -IncludeInternal)
    foreach ($f in $all) {
        $st = Read-TigBackup $f.FullName
        $note = if ($f.Name -match '_~prerestore') { '   (taken before an undo; restore with -Backup)' } else { '' }
        Write-Host ("    {0,-44} {1}{2}" -f $f.Name, $(if ($st) { Describe $st } else { 'UNREADABLE' }), $note)
    }
    if (-not $all.Count) { Write-Host "    no state_*.json restore points in $backupDir" }
    Write-Host ''
    exit 0
}

# --- choose what to restore ------------------------------------------------------
$source = $null
if ($Original) {
    $source = Join-Path $backupDir 'original-state.json'
    if (-not (Test-Path -LiteralPath $source)) {
        Write-Host '    There is no original-state.json in'
        Write-Host "      $backupDir"
        Write-Host '    It is written by the first install, so this module has never been'
        Write-Host '    installed from this folder, or the file was removed. Nothing was'
        Write-Host '    changed, and no other backup was used in its place.'
        Write-Host ''
        exit 4
    }
} elseif ($Backup) {
    $source = if (Test-Path -LiteralPath $Backup) { (Resolve-Path -LiteralPath $Backup).Path } else { Join-Path $backupDir $Backup }
    if (-not (Test-Path -LiteralPath $source)) { Write-Host "    No such backup: $Backup"; Write-Host '    Nothing was changed.'; Write-Host ''; exit 4 }
} else {
    $cand = @(Get-TigBackups -BackupDir $backupDir)
    if (-not $cand.Count) {
        Write-Host '    Nothing to restore: no backups exist in'
        Write-Host "      $backupDir"
        Write-Host '    That means Install-TextInputGuard.ps1 has not been run from this'
        Write-Host '    folder, so there is nothing this script needs to undo.'
        Write-Host ''
        exit 4
    }
    $source = $cand[0].FullName
}

$state = Read-TigBackup $source
if (-not $state) {
    Write-Host "    $source"
    Write-Host '    is not a state file this module recognises. Nothing was changed.'
    Write-Host ''
    exit 4
}

Write-Host ("    restoring from : {0}" -f (Split-Path -Leaf $source))
Write-Host ("    recorded at    : {0} (UTC)" -f $state.capturedUtc)
Write-Host ("    it records     : {0}" -f (Describe $state))
$nowState = Get-TigState
Write-Host ("    now            : {0}" -f (Describe $nowState))

if ($state.task.existed) {
    $why = Test-TigLegitTaskXml -Xml ([string]$state.task.xml) -ModuleDir $here
    if ($why) {
        Write-Host ''
        Write-Host "    REFUSED: the task recorded in this backup is not one this module creates ($why)."
        Write-Host '    Nothing was changed.'
        Write-Host ''
        exit 5
    }
}

if ($WhatIfPreference) {
    $n = if (Test-TigSameTask -XmlA ([string]$nowState.task.xml) -XmlB ([string]$state.task.xml)) { 0 } else { 1 }
    Write-Host ''
    Write-Host ("    {0} change WOULD be made. Nothing was changed." -f $n)
    Write-Host ("    a pre-restore snapshot would be written to {0}" -f $backupDir)
    Write-Host ''
    exit 0
}

# --- snapshot first; fatal if it fails (R4.5, R16.6) -----------------------------------
$pre = Save-TigBackup -BackupDir $backupDir -InternalSuffix 'prerestore' -State $nowState
if (-not $pre) {
    Write-Host '    STOPPING. The current state could not be snapshotted, so this undo'
    Write-Host '    would itself be un-undoable. Nothing has been restored.'
    Write-Host ''
    exit 3
}
Write-Host ("    snapshot of now: {0}" -f (Split-Path -Leaf $pre))

if (-not $PSCmdlet.ShouldProcess("$($script:TigTask.TaskPath)$($script:TigTask.TaskName)", 'restore')) { exit 4 }
$r = Set-TigTaskFromState -State $state -ModuleDir $here

# --- verify by reading back ----------------------------------------------------------
$after = Get-TigState
$sameNow = Test-TigSameTask -XmlA ([string]$after.task.xml) -XmlB ([string]$state.task.xml)
Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    task: {0}" -f $r.what)
Write-Host ("    now : {0}   (read back from Task Scheduler)" -f (Describe $after))
$changed = if ($r.ok -and $r.what -notmatch '^already') { 1 } else { 0 }
$already = if ($r.ok -and $r.what -match '^already') { 1 } else { 0 }
$failed  = if ($r.ok -and $sameNow) { 0 } else { 1 }
if ($failed -and $changed) { $changed = 0 }
Write-Host ("    restored: {0}   already as recorded: {1}   failed: {2}" -f $changed, $already, $failed)
Write-Host ''
if ($failed) { exit 5 }
exit 0
