<#
.SYNOPSIS
    Undo the OneDrive module. Works with no arguments at all.

.DESCRIPTION
    With no arguments it undoes the most recent ACCOUNT run: it writes back the
    environment variables and imports the exported registry keys. Folders are
    in the Recycle Bin; this script lists them and tells you to restore them
    from there, because moving files back out of the Recycle Bin is yours to do.

    -Part Machine undoes the most recent MACHINE run and needs administrator
    rights: it removes the two policies (or writes back what was there),
    moves OneDriveSetup.exe back where it came from, and writes back the
    new-account Run value.

    Undoing does NOT reinstall OneDrive. It puts back what this module
    changed, which is the means of reinstalling it.

.PARAMETER Part
    Account (default) or Machine.

.PARAMETER Run
    Restore from a specific backup run folder. Use -List to see them.

.PARAMETER List
    Show the available backup runs and exit. Changes nothing.

.PARAMETER WhatIf
    Say what would be restored and restore nothing.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Account', 'Machine')][string] $Part = 'Account',
    [string] $Run,
    [switch] $List
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')
$backupDir = Join-Path $here 'backups'

if ($List) {
    Write-Host ''; Write-Host '  Available backup runs'; Write-Host ('  ' + ('-' * 74))
    foreach ($p in 'Account', 'Machine') {
        $runs = Get-OdRuns -Directory $backupDir -Part $p -IncludeInternal
        foreach ($r in $runs) {
            $note = if ($r.Name -match '_~prerestore') { '   (taken before an undo - not offered)' } else { '' }
            Write-Host ("    {0}{1}" -f $r.Name, $note)
        }
        if (-not $runs.Count) { Write-Host ("    none for the {0} part" -f $p.ToLower()) }
    }
    Write-Host ''
    return
}

Write-Host ''
Write-Host ("  OneDrive - undo the {0} part" -f $Part.ToLower())
Write-Host ('  ' + ('-' * 74))

if ($Part -eq 'Machine' -and -not (Test-OdElevated) -and -not $WhatIfPreference) {
    Write-Host ''
    Write-Host '    Undoing the machine block needs administrator rights. Use'
    Write-Host '    "8 - UNDO the machine block.cmd", which asks Windows for them.'
    Write-Host '    Nothing was changed.'; Write-Host ''
    exit 4
}

# --- pick a source ----------------------------------------------------------
$runPath = $null
if ($Run) {
    $runPath = if (Test-Path $Run) { (Resolve-Path $Run).Path } else { Join-Path $backupDir $Run }
    if (-not (Test-Path (Join-Path $runPath 'state.json'))) { Write-Host "    No usable backup run at $Run"; Write-Host ''; exit 4 }
} else {
    $cand = Get-OdRuns -Directory $backupDir -Part $Part
    if (-not $cand.Count) { Write-Host '    There is nothing to undo - no backups exist for this part.'; Write-Host ''; exit 4 }
    $runPath = $cand[0].FullName
}
try { $state = Get-Content (Join-Path $runPath 'state.json') -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
catch { Write-Host "    Could not read the backup: $($_.Exception.Message)"; Write-Host '    Nothing was changed.'; Write-Host ''; exit 4 }
if (-not (Test-OdStateShape -State $state)) { Write-Host '    The backup is not a state file this module recognises. Nothing was changed.'; Write-Host ''; exit 4 }

Write-Host ("    restoring from : {0}" -f (Split-Path -Leaf $runPath))
Write-Host ("    recorded at    : {0}" -f $state.takenAt)

# What would be restored, per kind.
$keyImports = @()
if ($Part -eq 'Account') {
    foreach ($k in (Get-OdKeys -Part Account)) {
        $e = $state.keys.($k.Key)
        if ($e -and $e.existed -and $e.export -and -not (Test-Path $k.Key)) {
            # The export name comes from the backup, so it is checked: a bare
            # file name, inside this run folder, and a .reg file - nothing else.
            $leaf = [string]$e.export
            if ($leaf -ne (Split-Path -Leaf $leaf) -or $leaf -notmatch '\.reg$') { Write-Host "    refused: odd export name in backup for $($k.Key)"; continue }
            $keyImports += @{ Key = $k.Key; File = (Join-Path $runPath $leaf) }
        }
    }
}
$fileMoves = @()
if ($Part -eq 'Machine' -and $state.PSObject.Properties['installers'] -and $state.installers) {
    foreach ($i in (Get-OdInstallers)) {
        $e = $state.installers.($i.Path)
        if ($e -and $e.existed -and $e.stash -and -not (Test-Path $i.Path)) {
            $src = Join-Path $runPath ("files\" + $i.Stash)
            if (Test-Path $src) { $fileMoves += @{ From = $src; To = $i.Path } }
            else { Write-Host "    note: the stashed copy of $($i.Path) is missing from this backup" }
        }
    }
}
$hiveWrites = @()
if ($Part -eq 'Machine' -and $state.PSObject.Properties['defaultHive'] -and $state.defaultHive -and $state.defaultHive.readable) {
    foreach ($n in $script:OdHiveValues) {
        $e = $state.defaultHive.values.$n
        if ($e -and $e.existed -and ([string]$e.value).Length -le 400 -and [string]$e.value -match 'OneDrive') {
            $hiveWrites += @{ Name = $n; Value = [string]$e.value; Kind = $(if ($e.kind -eq 'ExpandString') { 'ExpandString' } else { 'String' }) }
        }
    }
}

Write-Host ''
Write-Host '    would restore:'
foreach ($v in (Get-OdValues -Part $Part)) {
    $e = $state.values."$($v.Key)|$($v.Name)"
    $want = if ($null -eq $e) { '<not in this backup - skipped>' } elseif ($e.existed) { "$($e.value)" } else { '<not set - removed>' }
    Write-Host ("      value  {0,-36} -> {1}" -f $v.Name, $want)
}
foreach ($k in $keyImports) { Write-Host ("      key    {0} <- {1}" -f $k.Key, (Split-Path -Leaf $k.File)) }
foreach ($m in $fileMoves)  { Write-Host ("      file   {0} <- backup" -f $m.To) }
foreach ($h in $hiveWrites) { Write-Host ("      new-account Run value {0}" -f $h.Name) }

if ($WhatIfPreference) { Write-Host ''; Write-Host '    PREVIEW ONLY - nothing was changed.'; Write-Host ''; exit 0 }
if (-not $PSCmdlet.ShouldProcess("OneDrive $Part part", 'restore')) { exit 4 }

# Snapshot where we are now, marked internal so it is never offered as a
# restore point (MODULE-STANDARD R16.3).
$pre = New-OdBackupFolder -Directory $backupDir -Part $Part -InternalSuffix 'prerestore'
if (-not $pre -or -not (Save-OdState -State (Get-OdState -SkipHive:($Part -eq 'Account')) -RunFolder $pre)) {
    Write-Host '    STOPPING. The current state could not be snapshotted, so this undo'
    Write-Host '    would itself be un-undoable. Nothing has been restored.'; Write-Host ''
    exit 3
}

Write-Host ''
Write-Host '    restoring:'
$r = Restore-OdValues -State $state -Part $Part
$restored = $r.Restored; $failed = $r.Failed
foreach ($d in $r.Detail) { Write-Host "      $d" }
foreach ($k in $keyImports) {
    $null = & reg.exe import $k.File 2>&1
    if (Test-Path $k.Key) { Write-Host ("      key    {0}" -f $k.Key); $restored++ } else { Write-Host ("      FAILED: could not import {0}" -f $k.File); $failed++ }
}
if ($Part -eq 'Account') { Send-OdEnvironmentChange }
foreach ($m in $fileMoves) {
    try { Move-Item -Path $m.From -Destination $m.To -ErrorAction Stop; Write-Host ("      file   {0}" -f $m.To); $restored++ }
    catch { Write-Host ("      FAILED: {0} - {1}" -f $m.To, $_.Exception.Message); $failed++ }
}
if ($hiveWrites.Count) {
    try {
        $n = Invoke-OdDefaultHive {
            $c = 0
            foreach ($h in $hiveWrites) {
                if (-not (Test-Path $script:OdHiveRunKey)) { New-Item -Path $script:OdHiveRunKey -Force | Out-Null }
                New-ItemProperty -Path $script:OdHiveRunKey -Name $h.Name -Value $h.Value -PropertyType $h.Kind -Force | Out-Null
                if ((Get-ItemProperty $script:OdHiveRunKey -Name $h.Name -ErrorAction SilentlyContinue).($h.Name) -eq $h.Value) { $c++ }
            }
            $c
        }
        $restored += $n; $failed += ($hiveWrites.Count - $n)
        Write-Host ("      new-account Run values written back: {0}" -f $n)
    }
    catch { Write-Host "      FAILED: $($_.Exception.Message)"; $failed += $hiveWrites.Count }
}

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    restored: {0}  skipped: {1}  failed: {2}" -f $restored, $r.Skipped, $failed)
if ($Part -eq 'Account') {
    $binned = @(Get-OdFolders | Where-Object { $_.Part -eq 'Account' -and $state.folders.($_.Path).existed -and -not (Test-Path $_.Path) })
    if ($binned.Count) {
        Write-Host ''
        Write-Host '    These folders went to the Recycle Bin. To get them back, open the'
        Write-Host '    Recycle Bin, right-click each one, and choose Restore:'
        foreach ($f in $binned) { Write-Host ("      {0}" -f $f.Path) }
    }
}
Write-Host ''
if ($failed) { exit 5 }
exit 0
