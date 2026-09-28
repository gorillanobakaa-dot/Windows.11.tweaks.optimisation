<#
.SYNOPSIS
    Block OneDrive from coming back, for the whole machine.

.DESCRIPTION
    Needs administrator rights. -WhatIf works without them, on purpose: a
    preview should never need elevation.

    What it does, when needed:
      1. Sets the two policies Microsoft documents for turning OneDrive off
         [R-145] DisableFileSyncNGSC = 1
                HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive
         [R-146] PreventNetworkTrafficPreUserSignIn = 1
                HKLM\SOFTWARE\Microsoft\OneDrive
      2. Moves Windows' own OneDrive installer (OneDriveSetup.exe in System32,
         and SysWOW64 where present) into this module's backups folder.
         [uncited] It is the file that puts OneDrive back.
      3. Removes the OneDriveSetup entry from the default-user hive, which
         installs OneDrive for every NEW account at its first sign-in.
         [uncited]
      4. Sends the empty machine-wide setup folder to the Recycle Bin.
         [uncited]

    Backs up first and refuses to continue without a verified backup. The
    installer is not deleted: it is moved into the backup, and the undo moves
    it back.

.PARAMETER NoFiles
    Leave the installer and the setup folder alone. The round-trip proof uses
    this for its registry-only pass.

.PARAMETER Tag
    A label added to the backup folder name.

.PARAMETER WhatIf
    Print every change and make none.

.NOTES
    Exit codes (MODULE-STANDARD section 16):
      0 applied or previewed   3 backup refused, nothing changed
      4 nothing to do, or not running as administrator
      5 completed with failures
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch] $NoFiles,
    [string] $Tag = ''
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')
$backupDir = Join-Path $here 'backups'
$elevated = Test-OdElevated

Write-Host ''
Write-Host '  OneDrive - block it from coming back (whole machine)'
Write-Host ('  ' + ('-' * 74))
if (-not $elevated -and -not $WhatIfPreference) {
    Write-Host ''
    Write-Host '    This needs administrator rights, and this window does not have them.'
    Write-Host '    Use "4 - BLOCK OneDrive on this machine.cmd", which asks Windows for'
    Write-Host '    them. Nothing was changed.'
    Write-Host ''
    exit 4
}

$state = Get-OdState

# --- plan -------------------------------------------------------------------
$planValues = @(Get-OdValues -Part Machine | Where-Object {
    $e = $state.values["$($_.Key)|$($_.Name)"]; -not $e.existed -or [string]$e.value -ne [string]$_.Target })
$planInstallers = @(); $planFolders = @()
if (-not $NoFiles) {
    $planInstallers = @(Get-OdInstallers | Where-Object { $state.installers[$_.Path].existed })
    $planFolders    = @(Get-OdFolders | Where-Object { $_.Part -eq 'Machine' -and $state.folders[$_.Path].existed })
}
$planHive = @()
if ($state.defaultHive -and $state.defaultHive.readable) {
    $planHive = @($script:OdHiveValues | Where-Object { $state.defaultHive.values[$_] -and $state.defaultHive.values[$_].existed })
}

Write-Host ''
foreach ($v in (Get-OdValues -Part Machine)) {
    $e = $state.values["$($v.Key)|$($v.Name)"]
    $mark = if ($planValues | Where-Object { $_.Name -eq $v.Name }) { '->' } else { '  ' }
    $now = if ($e.existed) { "$($e.value)" } else { '<not set>' }
    Write-Host ("    {0} policy {1,-36} {2,-10} -> {3}  [{4}]" -f $mark, $v.Name, $now, $v.Target, $v.Cite)
}
foreach ($i in (Get-OdInstallers)) {
    $has = $state.installers[$i.Path].existed
    $mark = if ($planInstallers | Where-Object { $_.Path -eq $i.Path }) { '->' } else { '  ' }
    $now = if ($has) { $(if ($NoFiles) { 'present (left alone: -NoFiles)' } else { 'present - moved into the backup' }) } else { 'not present' }
    Write-Host ("    {0} file   {1,-47} {2}  [uncited]" -f $mark, $i.Path, $now)
}
if ($state.defaultHive -and $state.defaultHive.readable) {
    foreach ($n in $script:OdHiveValues) {
        $e = $state.defaultHive.values[$n]
        $mark = if ($planHive -contains $n) { '->' } else { '  ' }
        $now = if ($e -and $e.existed) { 'present - removed' } else { 'not present' }
        Write-Host ("    {0} new-account Run value {1,-26} {2}  [uncited]" -f $mark, $n, $now)
    }
} else {
    Write-Host '       new-account Run values: cannot be read without administrator rights'
}
foreach ($f in (Get-OdFolders | Where-Object { $_.Part -eq 'Machine' })) {
    $mark = if ($planFolders | Where-Object { $_.Path -eq $f.Path }) { '->' } else { '  ' }
    $now = if ($state.folders[$f.Path].existed) { $(if ($NoFiles) { 'present (left alone: -NoFiles)' } else { 'present - to the Recycle Bin' }) } else { 'not present' }
    Write-Host ("    {0} dir    {1,-47} {2}  [uncited]" -f $mark, $f.Path, $now)
}
$total = $planValues.Count + $planInstallers.Count + $planHive.Count + $planFolders.Count

if ($WhatIfPreference) {
    Write-Host ''; Write-Host ('  ' + ('-' * 74))
    Write-Host ("    PREVIEW ONLY - nothing was changed.  would change: {0}" -f $total)
    Write-Host ''
    exit 0
}
if ($total -eq 0) {
    Write-Host ''; Write-Host '    Nothing to do - OneDrive is already blocked on this machine.'; Write-Host ''
    exit 4
}

# --- backup, and refuse to continue without one -----------------------------
Write-Host ''
$run = New-OdBackupFolder -Directory $backupDir -Part 'Machine' -Tag $Tag
if (-not $run -or -not (Save-OdState -State $state -RunFolder $run)) {
    Write-Host '    STOPPING. Nothing has been changed.'; Write-Host ''
    if ($run) { Remove-Item $run -Recurse -Force -ErrorAction SilentlyContinue }
    exit 3
}
Write-Host ("    backup written and verified: {0}" -f (Split-Path -Leaf $run))

# --- apply ------------------------------------------------------------------
$done = 0; $failed = 0; $declined = 0
Write-Host ''
Write-Host '    applying:'
foreach ($v in $planValues) {
    if (-not $PSCmdlet.ShouldProcess($v.Name, "set to $($v.Target)")) { $declined++; continue }
    if (Set-OdValue -Key $v.Key -Name $v.Name -Value $v.Target -Kind $v.Kind) {
        Write-Host ("      policy {0} = {1}" -f $v.Name, $v.Target); $done++
    } else { $failed++ }
}

if ($planInstallers.Count) {
    $stashDir = Join-Path $run 'files'
    New-Item -ItemType Directory -Path $stashDir -Force | Out-Null
}
foreach ($i in $planInstallers) {
    if (-not $PSCmdlet.ShouldProcess($i.Path, 'move into the backup')) { $declined++; continue }
    $dest = Join-Path $stashDir $i.Stash
    # The file belongs to TrustedInstaller. Administrators take ownership, grant
    # themselves full control, then MOVE it - it is kept, not deleted.
    $null = & takeown.exe /f $i.Path /a 2>&1
    $null = & icacls.exe $i.Path /grant '*S-1-5-32-544:F' 2>&1
    try {
        $hashBefore = (Get-FileHash $i.Path -Algorithm SHA256).Hash
        Move-Item -Path $i.Path -Destination $dest -Force -ErrorAction Stop
        $hashAfter = (Get-FileHash $dest -Algorithm SHA256).Hash
        if ($hashBefore -ne $hashAfter -or (Test-Path $i.Path)) { throw 'the moved copy does not match' }
        $state.installers[$i.Path].stash = "files\$($i.Stash)"
        Write-Host ("      file   {0} -> backup (SHA-256 checked)" -f $i.Path); $done++
    }
    catch { Write-Host ("      FAILED: {0} - {1}" -f $i.Path, $_.Exception.Message); $failed++ }
}

if ($planHive.Count) {
    try {
        $removed = Invoke-OdDefaultHive {
            $n2 = 0
            foreach ($n in $planHive) {
                if (-not $PSCmdlet.ShouldProcess("default-user Run\$n", 'remove')) { continue }
                Remove-ItemProperty -Path $script:OdHiveRunKey -Name $n -Force -ErrorAction SilentlyContinue
                if ($null -eq (Get-ItemProperty $script:OdHiveRunKey -Name $n -ErrorAction SilentlyContinue)) {
                    Write-Host ("      new-account Run value {0} removed" -f $n); $n2++
                } else { Write-Host ("      FAILED: new-account Run value {0} is still present" -f $n) }
            }
            $n2
        }
        $done += $removed; $failed += ($planHive.Count - $removed)
    }
    catch { Write-Host "      FAILED: $($_.Exception.Message)"; $failed += $planHive.Count }
}

foreach ($f in $planFolders) {
    if (-not $PSCmdlet.ShouldProcess($f.Path, 'send to the Recycle Bin')) { $declined++; continue }
    if (Send-OdToRecycleBin -Path $f.Path) { Write-Host ("      dir    {0} -> Recycle Bin" -f $f.Path); $done++ } else { $failed++ }
}

# Re-save: the state now records where each installer was stashed.
if (-not (Save-OdState -State $state -RunFolder $run)) {
    Write-Host '    WARNING: could not update the backup with the installer location.'
    Write-Host ("             The installer is in {0}\files." -f $run)
    $failed++
}

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    changed: {0}, failed: {1}, declined: {2}" -f $done, $failed, $declined)
Write-Host ''
Write-Host '    To undo: double-click "8 - UNDO the machine block.cmd"'
Write-Host ''
if ($failed) { exit 5 }
exit 0
