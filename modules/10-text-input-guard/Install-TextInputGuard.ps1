<#
.SYNOPSIS
    Install the TextInputHost guard: a scheduled task that ends TextInputHost
    only when it is stuck using a whole processor core.

.DESCRIPTION
    Creates one scheduled task, \W11T\TextInputHost guard, that runs every
    10 minutes as you, with your normal rights, with no window. Each run
    measures TextInputHost for one minute and ends it only if it held 90 %
    of one core or more for that whole minute (Invoke-TextInputGuard.ps1).

    SAFETY
      - Before anything is changed, the current state (whether the task
        exists, and its full definition if it does) is written to
        backups\state_<date>.json and read back to prove it. If that fails,
        nothing is changed (exit 3).
      - The first run also writes backups\original-state.json, once. Nothing
        ever overwrites it.
      - -WhatIf shows what would happen, including where the backup would go,
        and changes nothing.
      - After installing, the task is read back from Task Scheduler and
        checked; the result reports what is really in effect.

    This script is per-user. It needs no administrator rights and asks for
    none: a user may create scheduled tasks that run as themselves.

    It does not switch off the touch keyboard, emoji panel, clipboard
    history, or the service behind them.

.PARAMETER IntervalMinutes
    How often the guard runs. 5 to 60, default 10.

.PARAMETER ThresholdPercent
    How much of one core counts as stuck. 50 to 100, default 90.

.PARAMETER WindowSeconds
    How long each run measures. 30 to 120 seconds, default 60.

.PARAMETER Tag
    A label folded into the backup file name.

.PARAMETER WhatIf
    Preview: say what would be installed and where the backup would go.
    Change nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-TextInputGuard.ps1 -WhatIf
    Preview. Changes nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-TextInputGuard.ps1
    Install with the defaults: every 10 minutes, 90 % of one core for 60 s.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-TextInputGuard.ps1 -IntervalMinutes 5 -ThresholdPercent 80
    Check more often, and act at 80 %. Run again with other values to change them.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-TextInputGuard.ps1 -Tag before-holiday
    Install, with "before-holiday" in the backup file name.

.NOTES
    Exit codes: 0 installed (or previewed), 3 refused: no verified backup,
    nothing changed, 4 nothing to do: already installed with these settings,
    no backup written, 5 installed but the check afterwards found a problem.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateRange(5, 60)][int] $IntervalMinutes = 10,
    [ValidateRange(50, 100)][int] $ThresholdPercent = 90,
    [ValidateRange(30, 120)][int] $WindowSeconds = 60,
    [string] $Tag = ''
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')
$backupDir = Join-Path $here 'backups'
$full = "$($script:TigTask.TaskPath)$($script:TigTask.TaskName)"

Write-Host ''
Write-Host '  TextInputHost guard - install'
Write-Host ('  ' + ('-' * 74))
Write-Host ("    task      : {0}" -f $full)
Write-Host ("    runs      : every {0} minutes, as {1}, normal rights, no window" -f $IntervalMinutes, (Get-TigUserId))
Write-Host ("    ends it at: {0} % of one core for {1} s" -f $ThresholdPercent, $WindowSeconds)
Write-Host ("    mode      : {0}" -f $(if ($WhatIfPreference) { 'PREVIEW - nothing will be changed' } else { 'real' }))
Write-Host ''

# --- already as wanted? ------------------------------------------------------
$nowXml = Get-TigTaskXml
if ($nowXml) {
    $s = Get-TigTaskSettings -Xml $nowXml
    $same = $s -and -not (Test-TigLegitTaskXml -Xml $nowXml -ModuleDir $here) -and
            $s.IntervalMinutes -eq $IntervalMinutes -and $s.ThresholdPercent -eq $ThresholdPercent -and $s.WindowSeconds -eq $WindowSeconds -and
            (Get-TigTask).State -ne 'Disabled'
    if ($same) {
        Write-Host '    Nothing to do: the guard is already installed with exactly these'
        Write-Host '    settings and is enabled. No backup was written, because nothing'
        Write-Host '    would change.'
        Write-Host ''
        exit 4
    }
    Write-Host ('    the task exists with other settings ({0} min, {1} %, {2} s); it will be replaced' -f $s.IntervalMinutes, $s.ThresholdPercent, $s.WindowSeconds)
} else {
    Write-Host '    the task does not exist yet; it will be created'
}

# --- backup first (R4.1) -------------------------------------------------------
if ($PSCmdlet.ShouldProcess($backupDir, 'write a verified backup of the task state')) {
    $backupPath = Save-TigBackup -BackupDir $backupDir -Tag $Tag -RecordAsOriginal
    if (-not $backupPath) {
        Write-Host ''
        Write-Host '    STOPPING. No verified backup could be written, so nothing was changed.'
        Write-Host ''
        exit 3
    }
    Write-Host "    backup written           : $backupPath"
} else {
    Write-Host "    backup would be written to: $backupDir"
}

# --- the change ------------------------------------------------------------------
$changed = 0; $already = 0; $failed = 0
if ($PSCmdlet.ShouldProcess($full, 'register the guard task')) {
    $d = New-TigTaskDefinition -ModuleDir $here -IntervalMinutes $IntervalMinutes -ThresholdPercent $ThresholdPercent -WindowSeconds $WindowSeconds
    try {
        Register-ScheduledTask -TaskPath $script:TigTask.TaskPath -TaskName $script:TigTask.TaskName `
            -Action $d.Action -Trigger $d.Trigger -Principal $d.Principal -Settings $d.Settings `
            -Description $d.Description -Force -ErrorAction Stop | Out-Null
        $changed++
    }
    catch { $failed++; Write-Host "    FAILED to register the task: $($_.Exception.Message)" }
} else {
    Write-Host ''
    Write-Host '    1 change WOULD be made (the task created or replaced). Nothing was changed.'
    Write-Host ''
    exit 0
}

# --- verify by reading back (R6.8) ---------------------------------------------
Write-Host ''
Write-Host '    verification (read back from Task Scheduler, not from what we just sent):'
$back = Get-TigTaskXml
$problems = @()
if (-not $back) { $problems += 'the task is not there' }
else {
    $s = Get-TigTaskSettings -Xml $back
    $why = Test-TigLegitTaskXml -Xml $back -ModuleDir $here
    if ($why) { $problems += $why }
    if ($s.IntervalMinutes -ne $IntervalMinutes) { $problems += "interval reads $($s.IntervalMinutes) min" }
    if ($s.ThresholdPercent -ne $ThresholdPercent) { $problems += "threshold reads $($s.ThresholdPercent) %" }
    if ($s.WindowSeconds -ne $WindowSeconds) { $problems += "window reads $($s.WindowSeconds) s" }
    if ((Get-TigTask).State -eq 'Disabled') { $problems += 'the task is disabled' }
}
if ($problems.Count) {
    Write-Host '    STILL WRONG:'
    foreach ($p in $problems) { Write-Host "      $p" }
    $failed++; if ($changed) { $changed-- }
} else {
    Write-Host ("      installed: every {0} min, ends TextInputHost at {1} % of one core for {2} s," -f $IntervalMinutes, $ThresholdPercent, $WindowSeconds)
    Write-Host '      normal rights, no window. The first run is about one minute from now.'
}

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    changed: {0}   already as wanted: {1}   failed: {2}" -f $changed, $already, $failed)
Write-Host ''
Write-Host '  TO UNDO EVERYTHING:'
Write-Host '     powershell -ExecutionPolicy Bypass -File .\Restore-TextInputGuard.ps1'
Write-Host ''
if ($failed) { exit 5 }
exit 0
