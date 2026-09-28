<#
.SYNOPSIS
    Remove what OneDrive left behind in YOUR account after it was uninstalled.

.DESCRIPTION
    Backs up first, checks the backup was really written, and only then changes
    anything. If the backup cannot be written and verified, it changes nothing
    and says so.

    Needs NO administrator rights. Everything here belongs to your account.

    What it removes, when present:
      - the OneDrive and OneDriveConsumer environment variables
      - HKCU\Software\Microsoft\OneDrive
      - HKCU\Software\SyncEngines, only if OneDrive is the only sync provider in it
      - HKCU\Software\Classes\grvopen, only if it points at OneDrive.exe
      - your old OneDrive folder and the program's leftover folder, which go to
        the Recycle Bin, never deleted outright

    Registry keys are exported to .reg files in the backup before removal.
    The machine-wide block is a separate script: Block-OneDrive.ps1.

.PARAMETER NoFolders
    Leave the folders alone. The round-trip proof uses this, because a folder
    in the Recycle Bin cannot be put back automatically.

.PARAMETER Tag
    A label added to the backup folder name.

.PARAMETER WhatIf
    Print every change that would be made and make none of them.

.NOTES
    Exit codes (MODULE-STANDARD section 16):
      0 applied or previewed   3 backup refused, nothing changed
      4 nothing to do          5 completed with failures
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch] $NoFolders,
    [string] $Tag = ''
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')
$backupDir = Join-Path $here 'backups'

Write-Host ''
Write-Host '  OneDrive - remove the leftovers in your account'
Write-Host ('  ' + ('-' * 74))

$state = Get-OdState -SkipHive

# --- plan -------------------------------------------------------------------
$planValues = @(Get-OdValues -Part Account | Where-Object { $state.values["$($_.Key)|$($_.Name)"].existed })
$planKeys = @(); $keptKeys = @()
foreach ($k in (Get-OdKeys -Part Account)) {
    if (-not $state.keys[$k.Key].existed) { continue }
    $why = Test-OdKeyGuard -Rule $k
    if ($why) { $keptKeys += "$($k.Key) - $why" } else { $planKeys += $k }
}
$planFolders = @()
if (-not $NoFolders) { $planFolders = @(Get-OdFolders | Where-Object { $_.Part -eq 'Account' -and $state.folders[$_.Path].existed }) }

Write-Host ''
foreach ($v in (Get-OdValues -Part Account)) {
    $e = $state.values["$($v.Key)|$($v.Name)"]
    $mark = if ($e.existed) { '->' } else { '  ' }
    $now = if ($e.existed) { "$($e.value)" } else { '<not set>' }
    Write-Host ("    {0} env  {1,-18} {2}" -f $mark, $v.Name, $now)
}
foreach ($k in (Get-OdKeys -Part Account)) {
    $mark = if ($planKeys | Where-Object { $_.Key -eq $k.Key }) { '->' } else { '  ' }
    $now = if ($state.keys[$k.Key].existed) { 'present' } else { 'not present' }
    Write-Host ("    {0} key  {1,-45} {2}" -f $mark, $k.Key, $now)
}
foreach ($f in (Get-OdFolders | Where-Object { $_.Part -eq 'Account' })) {
    $mark = if ($planFolders | Where-Object { $_.Path -eq $f.Path }) { '->' } else { '  ' }
    $now = if ($state.folders[$f.Path].existed) { $(if ($NoFolders) { 'present (left alone: -NoFolders)' } else { 'present' }) } else { 'not present' }
    Write-Host ("    {0} dir  {1,-45} {2}" -f $mark, $f.Path, $now)
}
foreach ($k in $keptKeys) { Write-Host "       $k" }
$total = $planValues.Count + $planKeys.Count + $planFolders.Count

if ($WhatIfPreference) {
    Write-Host ''; Write-Host ('  ' + ('-' * 74))
    Write-Host ("    PREVIEW ONLY - nothing was changed.  would remove: {0}" -f $total)
    Write-Host ''
    exit 0
}
if ($total -eq 0) {
    Write-Host ''; Write-Host '    Nothing to do - no OneDrive leftovers in this account.'; Write-Host ''
    exit 4
}

# --- backup, and refuse to continue without one -----------------------------
Write-Host ''
$run = New-OdBackupFolder -Directory $backupDir -Part 'Account' -Tag $Tag
if (-not $run) { Write-Host '    STOPPING. Nothing has been changed.'; Write-Host ''; exit 3 }
foreach ($k in $planKeys) {
    $file = Export-OdKey -Key $k.Key -RunFolder $run
    if (-not $file) {
        Write-Host "    BACKUP FAILED: could not export and verify $($k.Key)"
        Write-Host '    STOPPING. Nothing has been changed.'; Write-Host ''
        Remove-Item $run -Recurse -Force -ErrorAction SilentlyContinue
        exit 3
    }
    $state.keys[$k.Key].export = Split-Path -Leaf $file
}
if (-not (Save-OdState -State $state -RunFolder $run)) {
    Write-Host '    STOPPING. Nothing has been changed.'; Write-Host ''
    Remove-Item $run -Recurse -Force -ErrorAction SilentlyContinue
    exit 3
}
Write-Host ("    backup written and verified: {0} ({1} key export(s))" -f (Split-Path -Leaf $run), $planKeys.Count)

# --- apply ------------------------------------------------------------------
$done = 0; $failed = 0; $declined = 0
Write-Host ''
Write-Host '    removing:'
foreach ($v in $planValues) {
    if (-not $PSCmdlet.ShouldProcess($v.Name, 'remove environment variable')) { $declined++; continue }
    if (Remove-OdValue -Key $v.Key -Name $v.Name) { Write-Host ("      env  {0}" -f $v.Name); $done++ } else { $failed++ }
}
if ($planValues.Count) { Send-OdEnvironmentChange }
foreach ($k in $planKeys) {
    if (-not $PSCmdlet.ShouldProcess($k.Key, 'remove key')) { $declined++; continue }
    Remove-Item -Path $k.Key -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $k.Key) { Write-Host "      FAILED: $($k.Key) is still present"; $failed++ }
    else { Write-Host ("      key  {0}" -f $k.Key); $done++ }
}
foreach ($f in $planFolders) {
    if (-not $PSCmdlet.ShouldProcess($f.Path, 'send to the Recycle Bin')) { $declined++; continue }
    if (Send-OdToRecycleBin -Path $f.Path) { Write-Host ("      dir  {0}  -> Recycle Bin" -f $f.Path); $done++ } else { $failed++ }
}

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    removed: {0}, failed: {1}, declined: {2}" -f $done, $failed, $declined)
Write-Host ''
if ($planFolders.Count) {
    Write-Host '    The folders are in the Recycle Bin. They stay recoverable until you'
    Write-Host '    empty it.'
}
Write-Host '    Programs that are already open keep the old environment variables until'
Write-Host '    they are restarted. New windows no longer see them.'
Write-Host ''
Write-Host '    To undo: double-click "7 - UNDO my account.cmd"'
Write-Host ''
if ($failed) { exit 5 }
exit 0
