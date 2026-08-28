<#
.SYNOPSIS
    Put every animation and visual-effect setting back the way it was. Run it
    with no arguments and it does the sensible thing.

.DESCRIPTION
    This is the undo button for Disable-VisualEffects.ps1.

    With no arguments it restores the MOST RECENT backup - that is, the state
    your machine was in immediately before the last time the disable script ran.

    If you have run the disable script more than once, or you simply want the
    machine exactly as it was before this project touched it, use -Original.
    That restores .\backups\original-state.json, which is written once on the
    very first run and never overwritten, precisely so that this route home
    always exists.

    Restoring puts back every one of the 20 settings the module manages,
    including DELETING any registry value that did not exist before, so you are
    not left with leftovers.

    This script is per-user. It needs no administrator rights and asks for none.

.PARAMETER Original
    Restore the pristine state captured on the very first run, rather than the
    most recent backup. This is the "put it back how it was before any of this"
    option.

.PARAMETER Backup
    Restore one specific backup file. Use -List to see what is available.

.PARAMETER List
    Show every available restore point with its date and a summary, then stop.
    Changes nothing.

.PARAMETER RestartExplorer
    Restart the desktop shell so taskbar and file-list settings return at once.
    Closes open File Explorer windows.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1
    Undo the last run. This is what you want in almost every case.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -Original
    Return the machine to exactly how it was before this module was ever used.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -List
    Show the available restore points without changing anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -WhatIf
    Show exactly what would be put back, and change nothing.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Original,
    [string]$Backup,
    [switch]$List,
    [switch]$RestartExplorer
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')
$backupDir = Join-Path $here 'backups'

# ---------------------------------------------------------------------------
#  Would restoring this backup actually change anything?
#
#  A backup recording the state the machine is ALREADY in restores nothing
#  while reporting "restored: 20  failed: 0". That is not a restore point, it
#  is a trap - and five of this module's had become exactly that, because an
#  earlier version of the apply wrote a fresh backup on every click even when
#  it changed nothing.
#
#  The two sides are different TYPES: a JSON-parsed backup is PSCustomObject,
#  a live reading is OrderedDictionary. Comparing them naively made every
#  registry entry look different, because one side stringified to
#  "System.Collections.Specialized.OrderedDictionary" instead of its value. So
#  the value is extracted shape-agnostically, and both the -List display and
#  the safety guard below use this one function rather than two copies.
# ---------------------------------------------------------------------------
function Get-VfxComparable {
    param($v)
    if ($null -eq $v) { return '<absent>' }
    if ($v -is [System.Collections.IDictionary]) {
        if ($v.Contains('value')) { return "$($v['value'])" }
        return (($v.Keys | Sort-Object | ForEach-Object { "$_=$($v[$_])" }) -join ';')
    }
    if ($v -is [string] -or $v -is [ValueType]) { return "$v" }
    if (@($v.PSObject.Properties.Name) -contains 'value') { return "$($v.value)" }
    return "$v"
}

function Measure-VfxRestoreEffect {
    <#  Compare a parsed backup against the machine as it is now.
        Returns Same / Diff counts. Diff = 0 with Same > 0 means restoring it
        would do nothing at all. #>
    param($State, $Live)
    $same = 0; $diff = 0
    foreach ($sect in 'spi', 'registry') {
        $b = $State.$sect; $n = $Live.$sect
        if ($null -eq $b -or $null -eq $n) { continue }
        foreach ($p in $b.PSObject.Properties) {
            if ((Get-VfxComparable $p.Value) -eq (Get-VfxComparable $n.$($p.Name))) { $same++ } else { $diff++ }
        }
    }
    [pscustomobject]@{ Same = $same; Diff = $diff }
}

function Show-Summary($state) {
    # Count only values that are genuinely usable: a corrupt entry is truthy and
    # would otherwise be summarised as a healthy "on", making a broken backup
    # look like a complete one.
    $on = 0; $bad = 0
    foreach ($n in $script:VfxEffects.Keys) {
        $v = ConvertTo-VfxInt $state.spi.$n
        if ($null -eq $v) { $bad++ } elseif ($v -ne 0) { $on++ }
    }
    foreach ($k in 'DragFullWindows','MenuShowDelay') {
        $v = ConvertTo-VfxInt $state.spi.$k
        if ($null -eq $v) { $bad++ } elseif ($k -eq 'DragFullWindows' -and $v -ne 0) { $on++ }
    }
    Write-Host ("      captured  : {0}   schema v{1}" -f $state.capturedUtc, $(if ($state.schemaVersion) { $state.schemaVersion } else { '1 (older)' }))
    Write-Host ("      effects on at capture : {0}" -f $on)
    Write-Host ("      menu delay at capture : {0} ms" -f $state.spi.MenuShowDelay)
    if ($bad -gt 0) {
        Write-Host ("      WARNING: {0} setting(s) in this backup are missing or unusable" -f $bad)
    }
}

# ------------------------------------------------------------------- list ----
if ($List) {
    $all = Get-VfxBackups -BackupDir $backupDir
    Write-Host ''
    if (-not $all -or $all.Count -eq 0) {
        Write-Host '  No restore points found. Nothing has been backed up yet,'
        Write-Host '  which means the disable script has not been run from this folder.'
        Write-Host ''
        return
    }
    Write-Host "  Restore points in $backupDir"
    Write-Host ('  ' + ('-' * 72))
    $liveNow = Get-VfxState
    $deadCount = 0
    foreach ($f in $all) {
        $tagline = ''
        if ($f.Name -eq 'original-state.json')  { $tagline = '   <-- pristine, use -Original' }
        elseif ($f.Name -like '*pre-restore*')  { $tagline = '   <-- written BY a restore; not used by default' }
        elseif ($f.Name -like 'snapshot_*')     { $tagline = '   <-- read-only snapshot, not a restore point' }
        elseif ($f.Name -like 'roundtrip_*')    { $tagline = '   <-- from the round-trip proof' }
        Write-Host ("    {0,-46} {1}{2}" -f $f.Name, $f.LastWriteTime, $tagline)
        try {
            $s = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $shape = Test-VfxStateShape -State $s
            if ($shape.Count) { $shape | ForEach-Object { Write-Host "      NOTE: $_" } }

            # Does this one still DO anything? Say so here rather than letting
            # somebody pick it and watch a successful-looking no-op.
            $eff = Measure-VfxRestoreEffect -State $s -Live $liveNow
            if ($eff.Diff -eq 0 -and $eff.Same -gt 0) {
                Write-Host ("      DEAD - restoring this would change NOTHING ({0} settings compared, 0 differ)." -f $eff.Same)
                $deadCount++
            }
            else {
                Write-Host ("      restoring this would change {0} setting(s)." -f $eff.Diff)
            }
            Show-Summary $s
        } catch { Write-Host '      (UNREADABLE - this file cannot be used to restore)' }
    }
    Write-Host ''
    if ($deadCount -gt 0) {
        Write-Host ("  {0} restore point(s) above are DEAD: they record the state this" -f $deadCount)
        Write-Host '  machine is already in, so restoring one would report success and do'
        Write-Host '  nothing. They are usually left over from clicking apply more than'
        Write-Host '  once. The undo refuses to use one, and tells you so.'
        Write-Host ''
    }
    Write-Host '  Restore the newest : .\Restore-VisualEffects.ps1'
    Write-Host '  Restore pristine   : .\Restore-VisualEffects.ps1 -Original'
    Write-Host ''
    return
}

# --------------------------------------------------------------- choose it ----
$chosen = $null
if ($Backup) {
    $chosen = if (Test-Path $Backup) { Get-Item $Backup } else { $null }
    if (-not $chosen) {
        $try = Join-Path $backupDir $Backup
        if (Test-Path $try) { $chosen = Get-Item $try }
    }
    if (-not $chosen) { Write-Error "Backup not found: $Backup"; return }
}
elseif ($Original) {
    $p = Join-Path $backupDir 'original-state.json'
    if (-not (Test-Path $p)) {
        Write-Host ''
        Write-Host '  No original-state.json exists, so there is no pristine state recorded.'
        Write-Host '  That file is created the first time Disable-VisualEffects.ps1 runs.'
        Write-Host ''
        return
    }
    $chosen = Get-Item $p
}
else {
    # Newest genuine restore point. Get-VfxRestoreCandidates deliberately
    # EXCLUDES the pre-restore snapshots this script itself writes: without that
    # exclusion, running restore twice would select the snapshot taken just
    # before the first restore - which holds the already-disabled state - and
    # silently re-apply the tweaks. An auditor demonstrated exactly that.
    $candidates = @(Get-VfxRestoreCandidates -BackupDir $backupDir)
    $chosen = $candidates | Select-Object -First 1
    if (-not $chosen) {
        Write-Host ''
        Write-Host '  Nothing to restore: no backups exist in'
        Write-Host "    $backupDir"
        Write-Host '  That means Disable-VisualEffects.ps1 has not been run from this folder,'
        Write-Host '  so there is nothing this script needs to undo.'
        Write-Host ''
        return
    }
}

# Read the chosen backup. If it is corrupt and we picked it automatically, fall
# back to the next-newest valid restore point rather than leaving the user with
# no way to undo because one file went bad.
$state = $null
try {
    $state = Get-Content $chosen.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Host ''
    Write-Host "  '$($chosen.Name)' could not be read: $($_.Exception.Message)"
    if ($Backup -or $Original) {
        Write-Host '  You named this file explicitly, so no other file will be used.'
        Write-Host '  Run with -List to see the other restore points available.'
        Write-Host ''
        return
    }
    Write-Host '  Looking for the next usable restore point...'
    foreach ($f in @(Get-VfxRestoreCandidates -BackupDir $backupDir)) {
        if ($f.FullName -eq $chosen.FullName) { continue }
        try {
            $state = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $chosen = $f
            Write-Host "  using '$($f.Name)' instead."
            break
        } catch { continue }
    }
    if (-not $state) {
        Write-Host '  No usable restore point could be read. Try -Original.'
        Write-Host ''
        return
    }
}

$shape = Test-VfxStateShape -State $state
if ($shape.Count) {
    Write-Host ''
    foreach ($s in $shape) { Write-Host "  NOTE: $s" }
    $fatal = $shape | Where-Object { $_ -match 'no spi section|no registry section|not an object|empty or unreadable' }
    if ($fatal) {
        Write-Host ''
        Write-Host '  This backup is not structurally usable. Nothing has been changed.'
        Write-Host '  Run with -List to choose another, or use -Original.'
        Write-Host ''
        return
    }
}

# ------------------------------------------- would this undo change anything? --
# A restore that faithfully writes back a backup identical to the current state
# is a restore that does NOTHING - and looks exactly like a successful one. The
# user clicks UNDO, sees no error, and believes the machine was put back.
#
# That is not hypothetical. Before the apply script learned to exit 4, clicking
# apply twice wrote a second backup recording the ALREADY-APPLIED state, which
# then became the newest restore point. On this machine 14 of 23 backups are
# that shape. So: say so, rather than perform a convincing no-op.
if (-not $Original) {
    # One implementation, used by both -List and this guard. Two copies of a
    # comparison is two chances for them to disagree about what "the same"
    # means, and the one that matters would be the one nobody looked at.
    $eff = Measure-VfxRestoreEffect -State $state -Live (Get-VfxState)
    $sameCount = $eff.Same; $diffCount = $eff.Diff
    if ($diffCount -eq 0 -and $sameCount -gt 0) {
        Write-Host ''
        Write-Host '  STOPPING - this undo would change nothing.'
        Write-Host ''
        Write-Host ("  The newest restore point ({0}) records" -f $chosen.Name)
        Write-Host ("  exactly the state this machine is in now ({0} settings compared, 0 differ)." -f $sameCount)
        Write-Host '  Restoring it would look like it worked and would achieve nothing.'
        Write-Host ''
        Write-Host '  This happens when the apply was run more than once: the second run'
        Write-Host '  recorded the already-applied state as a backup.'
        Write-Host ''
        Write-Host '  WHAT YOU PROBABLY WANT is the pristine state from before this module'
        Write-Host '  was ever used - the launcher named "UNDO back to the original", or:'
        Write-Host '     powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1 -Original'
        Write-Host ''
        Write-Host '  Exit code 4: nothing to do.'
        Write-Host ''
        exit 4
    }
}

Write-Host ''
Write-Host '  Restore visual effects'
Write-Host ("  from : {0}" -f $chosen.Name)
Write-Host ("  taken: {0}" -f $state.capturedUtc)
if ($chosen.Name -eq 'original-state.json') {
    Write-Host '  this is the pristine state recorded before this module was first used'
}
Write-Host ('  ' + ('-' * 72))

# Safety: capture where we are NOW before undoing, so a restore is itself
# reversible. Without this, restoring would destroy the current state.
if (-not $WhatIfPreference) {
    $safety = Save-VfxBackup -BackupDir $backupDir -Tag 'pre-restore'
    if ($safety) {
        Write-Host "  current state saved first : $safety"
    } else {
        Write-Host '  WARNING: could not save the current state before restoring.'
        Write-Host '  The restore will still proceed, because you asked to undo, but this'
        Write-Host '  particular undo will not itself be undoable.'
    }
    Write-Host ''
}

$result = Restore-VfxState -State $state -WhatIfMode:$WhatIfPreference

if ($RestartExplorer -and -not $WhatIfPreference) {
    if ($PSCmdlet.ShouldProcess('explorer.exe', 'restart')) {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
        Write-Host ''
        Write-Host '  desktop shell restarted'
    }
}

Write-Host ''
Write-Host ('  ' + ('-' * 72))
if ($WhatIfPreference) {
    Write-Host ("  PREVIEW ONLY - nothing was changed.")
    Write-Host ("  would restore: {0}   would skip: {1}" -f $result.Restored, $result.Skipped)
} else {
    Write-Host ("  restored: {0}   skipped: {1}   failed: {2}" -f $result.Restored, $result.Skipped, $result.Failed)
}
if ($result.Skipped -gt 0) {
    Write-Host ''
    Write-Host '  Skipped (the backup holds no usable value for these, so they were left as they are):'
    $result.SkippedDetail | ForEach-Object { Write-Host "    - $_" }
}
if ($result.Failed -gt 0) {
    Write-Host ''
    Write-Host '  FAILED to restore:'
    $result.FailedDetail | ForEach-Object { Write-Host "    - $_" }
    Write-Host '  The machine is NOT fully back to the captured state. Run'
    Write-Host '  Test-VisualEffects.ps1 to see where it actually stands.'
}
if ($result.Ignored.Count -gt 0) {
    Write-Host ''
    Write-Host '  Ignored entries in the backup that name settings this module does not manage:'
    $result.Ignored | ForEach-Object { Write-Host "    - $_" }
}

# The legacy effects live packed inside a shared 8-byte preference mask. This
# module manages ten of its bits and cannot restore the rest, so rather than
# quietly losing something, compare and say so.
if (-not $WhatIfPreference) {
    $mask = Test-VfxMaskUnchanged -State $state
    if ($mask -and -not $mask.Same) {
        Write-Host ''
        Write-Host '  NOTE: the shared legacy preference mask does not match the backup exactly:'
        Write-Host ("    captured : {0}" -f $mask.Captured)
        Write-Host ("    now      : {0}" -f $mask.Current)
        Write-Host '  The settings this module manages have been restored. Bits in that mask'
        Write-Host '  belonging to settings outside this module are not managed here, so a'
        Write-Host '  difference is expected if anything else changed them meanwhile.'
    }
}

if (-not $WhatIfPreference) {
    if (-not $RestartExplorer) {
        Write-Host ''
        Write-Host '  taskbar and file-list items return at your next sign-in,'
        Write-Host '  or immediately if you re-run with -RestartExplorer.'
    }
    Write-Host ''
    Write-Host '  Check the result with:'
    Write-Host '     powershell -ExecutionPolicy Bypass -File .\Test-VisualEffects.ps1'
}
Write-Host ''
