<#
.SYNOPSIS
    Undo the feature-update hold. Puts every value back to what a backup
    recorded - including back to absent, which is not the same as zero.

.PARAMETER Original
    Restore from the write-once original-state.json: the machine as it was
    before this module was ever used.

.PARAMETER Backup
    Restore from a specific file. Use -List to see what exists.

.PARAMETER List
    Show every backup and stop.

.NOTES
    Exit codes: 0 restored   3 pre-restore snapshot refused
                4 nothing to do / unelevated / no usable backup
                5 completed with failures
#>
[CmdletBinding()]
param(
    [switch]$Original,
    [string]$Backup = '',
    [switch]$List
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '_Common.ps1')

$here    = $PSScriptRoot
$backups = Join-Path $here 'backups'

Write-Host ""
Write-Host "  Undo the feature-update hold"
Write-Host "  --------------------------------------------------------------------------"

# --- list ------------------------------------------------------------------
if ($List) {
    $all = @(Get-UdfBackups -Directory $backups)
    if ($all.Count -eq 0) { Write-Host "    No backups exist yet."; exit 4 }

    # Derived from the REAL filter, not a second hand-written pattern. In
    # another module a duplicated pattern annotated this list exactly backwards.
    $offered = @(Get-UdfRestoreCandidates -Directory $backups | ForEach-Object { $_.FullName })
    foreach ($f in $all) {
        $note = if ($offered -contains $f.FullName) { '' } else { '   (internal snapshot - not offered as a restore point)' }
        try {
            $s = Get-Content $f.FullName -Raw | ConvertFrom-Json
            Write-Host ("    {0:yyyy-MM-dd HH:mm}  release {1,-7} {2}{3}" -f $f.LastWriteTime, $s.displayVersion, $f.Name, $note)
        }
        catch { Write-Host ("    {0,-46} (unreadable){1}" -f $f.Name, $note) }
    }
    $orig = Join-Path $backups 'original-state.json'
    if (Test-Path $orig) { Write-Host "    original-state.json                            (use -Original)" }
    exit 0
}

# --- choose a backup -------------------------------------------------------
$path = $null
if ($Original) {
    $path = Join-Path $backups 'original-state.json'
    if (-not (Test-Path $path)) {
        Write-Host "    There is no original-state.json - this module has never been applied."
        Write-Host "    Exit code 4."
        exit 4
    }
}
elseif ($Backup) {
    $path = $Backup
    if (-not (Test-Path $path)) { Write-Host "    No such backup: $Backup"; exit 4 }
}
else {
    $candidates = @(Get-UdfRestoreCandidates -Directory $backups)
    if ($candidates.Count -eq 0) {
        Write-Host "    No usable backup found. Nothing to restore from."
        Write-Host "    Exit code 4."
        exit 4
    }
    $path = $candidates[0].FullName
}

try {
    $state = Get-Content -Path $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}
catch {
    Write-Host ("    That backup will not parse: {0}" -f $_.Exception.Message)
    Write-Host "    Exit code 4."
    exit 4
}

if (-not (Test-UdfStateShape $state)) {
    Write-Host "    That backup parses but is missing sections a restore needs."
    Write-Host "    Exit code 4."
    exit 4
}

Write-Host ("    restoring from : {0}" -f (Split-Path $path -Leaf))
Write-Host ("    taken          : {0}" -f $state.takenAt)
Write-Host ("    release then   : {0}" -f $state.displayVersion)
$nowRelease = Get-UdfInstalledRelease
Write-Host ("    release now    : {0}" -f $nowRelease)
if ("$($state.displayVersion)" -ne "$nowRelease") {
    Write-Host ""
    Write-Host "    ! The machine has changed release since that backup was taken."
    Write-Host "      The undo will still put the POLICY values back as recorded."
}

if (-not (Test-UdfElevated)) {
    Write-Host ""
    Write-Host "    STOPPING: this writes under HKLM and needs administrator rights."
    Write-Host "    Exit code 4: nothing was changed."
    exit 4
}

# --- snapshot before restoring ---------------------------------------------
# Deliberately NOT passed -RecordAsOriginal: this snapshot must never be
# allowed to become "the original state" on a machine already modified.
Write-Host ""
$snap = Save-UdfBackup -Directory $backups -Tag '~prerestore'
if (-not $snap) {
    Write-Host "    STOPPING: could not snapshot the current state before restoring."
    Write-Host "    Exit code 3."
    exit 3
}
Write-Host ("    snapshot before restoring: {0}" -f (Split-Path $snap -Leaf))

# --- restore ---------------------------------------------------------------
Write-Host ""
Write-Host "  Restoring"
Write-Host "  --------------------------------------------------------------------------"
$r = Restore-UdfState -State $state

Write-Host ""
Write-Host ("    restored: {0}   skipped: {1}   failed: {2}" -f $r.restored, $r.skipped, $r.failed)

if ($r.failed -gt 0) {
    Write-Host "    Exit code 5: completed with failures."
    exit 5
}

Write-Host ""
Write-Host "    Done. Run check 1 to confirm what the machine now reports."
Write-Host ""
exit 0
