<#
.SYNOPSIS
    Show what is going on now: is TextInputHost using the processor, and is
    the guard installed? Read-only. Changes nothing.

.DESCRIPTION
    Prints, in plain words:
      - every TextInputHost in your session: where it runs from, when it
        started, how much processor time it has used in total, and how much
        of one core it is using now (measured over a few seconds by reading
        its processor-time counter twice; nothing is sampled instantaneously);
      - whether the guard task is installed, with its settings, when it last
        ran and what it reported, and when it runs next;
      - the last lines of the guard's log.

    This script is read-only and per-user. It needs no administrator rights
    and asks for none. It ends nothing and changes no setting.

.PARAMETER MeasureSeconds
    How long to measure current use. 0 skips the measurement. Default 10.

.PARAMETER Json
    Also write the reading to backups\snapshot_<stamp>.json. A snapshot is
    not a backup and is never offered by the undo.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-TextInputGuard.ps1
    The full picture, with a 10-second measurement.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-TextInputGuard.ps1 -MeasureSeconds 0
    The same, without waiting to measure.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-TextInputGuard.ps1 -Json
    Also saves the reading as a snapshot file.
#>
[CmdletBinding()]
param(
    [ValidateRange(0, 120)][int] $MeasureSeconds = 10,
    [switch] $Json
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

Write-Host ''
Write-Host '  TextInputHost guard - what is on now (read-only)'
Write-Host ('  ' + ('-' * 74))
Write-Host ("    machine : {0}   Windows build {1}   user {2}" -f $env:COMPUTERNAME, (Get-TigOsBuild), $env:USERNAME)
Write-Host ''

# --- TextInputHost ------------------------------------------------------------
Write-Host '  TextInputHost (the touch keyboard, emoji panel and clipboard history)'
$procs = @(Get-TigProcesses)
$measured = @()
if (-not $procs.Count) {
    Write-Host '    not running in your session. Windows starts it when one of those'
    Write-Host '    panels is opened. Nothing to measure.'
} else {
    if ($MeasureSeconds -gt 0) {
        Write-Host ("    measuring for {0} s (reading its processor-time counter twice) ..." -f $MeasureSeconds)
        $measured = @(Measure-TigProcesses -WindowSeconds $MeasureSeconds)
    }
    foreach ($p in $procs) {
        $m = $measured | Where-Object Id -eq $p.Id | Select-Object -First 1
        $now = if ($m -and $null -ne $m.Percent) { '{0} % of one core' -f $m.Percent } elseif ($MeasureSeconds -gt 0) { 'unknown' } else { 'not measured' }
        $note = ''
        if ($m -and $null -ne $m.Percent) {
            if ($m.Percent -ge $script:TigDefaults.ThresholdPercent) { $note = '   <- STUCK: this is the fault the guard ends' }
            elseif ($m.Percent -lt 2) { $note = '   (idle, as it should be)' }
        }
        Write-Host ("    pid {0}" -f $p.Id)
        Write-Host ("      {0,-22} {1}" -f 'runs from', $(if ($p.Path) { $p.Path } else { 'unknown' }))
        Write-Host ("      {0,-22} {1}" -f 'the Windows one', $(if ($p.Genuine) { 'yes' } else { 'NO - the guard would leave it alone' }))
        Write-Host ("      {0,-22} {1}" -f 'started', $p.StartTime)
        Write-Host ("      {0,-22} {1:N0} s" -f 'processor time so far', $p.CpuSeconds)
        Write-Host ("      {0,-22} {1}{2}" -f 'using now', $now, $note)
    }
}
Write-Host ''

# --- the guard ------------------------------------------------------------------
Write-Host '  The guard (scheduled task)'
$task = Get-TigTask
$xml = Get-TigTaskXml
if (-not $task) {
    Write-Host ("    not installed ({0}{1} does not exist)." -f $script:TigTask.TaskPath, $script:TigTask.TaskName)
    Write-Host '    Install it with "4 - Install the guard.cmd".'
} else {
    $s = Get-TigTaskSettings -Xml $xml
    $info = Get-ScheduledTaskInfo -TaskPath $script:TigTask.TaskPath -TaskName $script:TigTask.TaskName -ErrorAction SilentlyContinue
    $legit = Test-TigLegitTaskXml -Xml $xml -ModuleDir $here
    Write-Host ("    {0,-22} {1}{2}" -f 'installed', 'yes', $(if ($task.State -eq 'Disabled') { '   (but DISABLED in Task Scheduler)' } else { '' }))
    Write-Host ("    {0,-22} every {1} minutes" -f 'runs', $s.IntervalMinutes)
    Write-Host ("    {0,-22} {1} % of one core for {2} s" -f 'ends it at', $s.ThresholdPercent, $s.WindowSeconds)
    Write-Host ("    {0,-22} {1}" -f 'with rights', $(if ($s.RunLevel -eq 'LeastPrivilege') { 'your normal rights (not administrator)' } else { $s.RunLevel }))
    if ($legit) { Write-Host ("    {0,-22} {1}" -f 'WARNING', "the task is not as this module made it: $legit") }
    if ($info) {
        # The task runs conhost.exe (for "no window"), and conhost does not pass
        # the guard's own exit code on: Task Scheduler records 0 whether or not
        # a copy was ended (observed 2026-09-28). What it did is in the log.
        $res = switch ($info.LastTaskResult) { 0 { 'ran; what it did is in the log below' } 267011 { 'has not run yet' } 267009 { 'running now' } default { 'Task Scheduler code {0}' -f $info.LastTaskResult } }
        Write-Host ("    {0,-22} {1}  ({2})" -f 'last ran', $info.LastRunTime, $res)
        Write-Host ("    {0,-22} {1}" -f 'next run', $info.NextRunTime)
    }
}
Write-Host ''

# --- the log -------------------------------------------------------------------
Write-Host '  Guard log (one line each time it ends a stuck copy or fails)'
$log = Get-TigLogPath $here
if (Test-Path -LiteralPath $log) {
    $lines = @(Get-Content -LiteralPath $log -Encoding UTF8 -Tail 5)
    $total = @(Get-Content -LiteralPath $log -Encoding UTF8).Count
    Write-Host ("    {0} line(s) in total; the last {1}:" -f $total, $lines.Count)
    foreach ($l in $lines) { Write-Host "      $l" }
} else {
    Write-Host '    empty: the guard has never had to end anything.'
}
Write-Host ''

if ($Json) {
    $snap = [ordered]@{
        takenUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); osBuild = (Get-TigOsBuild)
        processes = @($measured | Select-Object Id, Path, Genuine, StartTime, CpuSeconds, ElapsedSeconds, Percent)
        task = (Get-TigState).task
    }
    $dir = Join-Path $here 'backups'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $p = Join-Path $dir ('snapshot_{0}.json' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    $snap | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $p -Encoding UTF8
    Write-Host "  snapshot written: $p"
    Write-Host ''
}
exit 0
