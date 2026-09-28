<#
.SYNOPSIS
    The guard itself: measure TextInputHost for one minute and end it only if
    it held a whole processor core. The scheduled task runs this; you can run
    it by hand too.

.DESCRIPTION
    Measures every TextInputHost.exe in your session over a window (60
    seconds by default), by reading how much processor time it used at the
    start and at the end. If one used at least the threshold (90 % of one
    core by default) for the whole window, it is ended, and one line is
    written to guard-log.txt in this folder. Windows starts a fresh copy
    the next time the touch keyboard, emoji panel or clipboard history is
    needed; nothing you typed is lost.

    It never ends:
      - a program called TextInputHost.exe that is not in Windows'
        SystemApps folder;
      - a copy that started during the measurement (it cannot be judged);
      - anything in another user's session.

    No administrator rights: it only ends a program running as you.

.PARAMETER ThresholdPercent
    How much of one core counts as stuck. 50 to 100, default 90.

.PARAMETER WindowSeconds
    How long to measure. 10 to 300 seconds, default 60.

.PARAMETER Quiet
    Print nothing; write to guard-log.txt only when a copy is ended or
    something fails. This is how the scheduled task runs it.

.PARAMETER WhatIf
    Measure and report, but end nothing and write nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Invoke-TextInputGuard.ps1 -WhatIf
    Measures for 60 seconds and says what it would do. Changes nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Invoke-TextInputGuard.ps1
    Measures for 60 seconds and ends TextInputHost if it is stuck.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Invoke-TextInputGuard.ps1 -WindowSeconds 20 -ThresholdPercent 80
    A shorter, stricter check.

.NOTES
    Exit codes: 0 nothing was stuck (or preview), 10 a stuck copy was ended,
    1 a stuck copy could not be ended or the measurement failed.
    Run from the scheduled task, these codes do not reach Task Scheduler: the
    task runs conhost.exe (so no window appears), and conhost reports 0. The
    record of what the guard did is guard-log.txt.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateRange(50, 100)][int] $ThresholdPercent = 90,
    [ValidateRange(10, 300)][int] $WindowSeconds = 60,
    [switch] $Quiet
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

function Say([string]$t) { if (-not $Quiet) { Write-Host $t } }

Say ''
Say '  TextInputHost guard - measure, and end it only if it is stuck'
Say ('  ' + ('-' * 74))
Say ("    threshold : {0} % of one processor core, for the whole window" -f $ThresholdPercent)
Say ("    window    : {0} seconds" -f $WindowSeconds)
Say ("    mode      : {0}" -f $(if ($WhatIfPreference) { 'PREVIEW - ends nothing, writes nothing' } else { 'real' }))

$procs = @(Get-TigProcesses)
if (-not $procs.Count) {
    Say ''
    Say '    No TextInputHost is running in your session, so there is nothing'
    Say '    to measure. Windows starts it when the touch keyboard, emoji panel'
    Say '    or clipboard history is opened. Nothing was changed.'
    Say ''
    exit 0
}

Say ("    measuring {0} process(es) for {1} s ..." -f $procs.Count, $WindowSeconds)
$results = @(Measure-TigProcesses -WindowSeconds $WindowSeconds)

$ended = 0; $failed = 0
foreach ($r in $results) {
    $verdict = Get-TigVerdict -CpuSeconds $r.CpuSeconds -ElapsedSeconds $r.ElapsedSeconds -ThresholdPercent $ThresholdPercent -AgeSeconds $r.AgeSeconds
    $pct = if ($null -ne $r.Percent) { '{0} %' -f $r.Percent } else { 'unknown' }
    if ($r.Exited) { Say ("    pid {0,-6} ended by itself during the measurement - left alone" -f $r.Id); continue }
    if (-not $r.Genuine) {
        Say ("    pid {0,-6} {1,8} of one core   NOT the Windows one ({2}) - left alone" -f $r.Id, $pct, $r.Path)
        continue
    }
    switch ($verdict) {
        'ok'      { Say ("    pid {0,-6} {1,8} of one core   fine" -f $r.Id, $pct) }
        'young'   { Say ("    pid {0,-6} {1,8} of one core   started during the measurement - not judged" -f $r.Id, $pct) }
        'unknown' { Say ("    pid {0,-6} could not be measured - left alone" -f $r.Id) }
        'end' {
            Say ("    pid {0,-6} {1,8} of one core   STUCK" -f $r.Id, $pct)
            if (-not $PSCmdlet.ShouldProcess("TextInputHost pid $($r.Id)", 'end it (Windows starts a fresh copy when needed)')) { continue }
            try {
                Stop-Process -Id $r.Id -Force -ErrorAction Stop
                $gone = $true
                try { Wait-Process -Id $r.Id -Timeout 5 -ErrorAction Stop } catch { $gone = -not (Get-Process -Id $r.Id -ErrorAction SilentlyContinue) }
                if (-not $gone -and (Get-Process -Id $r.Id -ErrorAction SilentlyContinue)) { throw 'it is still running' }
                $ended++
                Say '             ended. Windows starts a fresh copy when it is needed.'
                [void](Write-TigLog -ModuleDir $here -Line ("ended TextInputHost pid {0}: {1} % of one core for {2} s (threshold {3} %)" -f $r.Id, $r.Percent, $r.ElapsedSeconds, $ThresholdPercent))
            }
            catch {
                $failed++
                Say ("             FAILED to end it: {0}" -f $_.Exception.Message)
                [void](Write-TigLog -ModuleDir $here -Line ("FAILED to end TextInputHost pid {0} at {1} % of one core: {2}" -f $r.Id, $r.Percent, $_.Exception.Message))
            }
        }
    }
}

Say ''
Say ('  ' + ('-' * 74))
Say ("    ended: {0}   failed: {1}   measured: {2}" -f $ended, $failed, $results.Count)
if ($WhatIfPreference) { Say '    PREVIEW ONLY - nothing was ended and nothing was written.' }
Say ''
if ($failed) { exit 1 }
if ($ended) { exit 10 }
exit 0
