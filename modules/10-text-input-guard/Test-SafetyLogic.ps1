<#
.SYNOPSIS
    Test the logic that decides whether to end a process, whether a backup
    may be trusted, and whether a task may be written back. Changes nothing
    real: it works in a temporary folder and never touches Task Scheduler or
    any running program.

.DESCRIPTION
    Feeds the module's decision code with inputs normal use never produces:
    a process that started mid-measurement, a zero-length window, a threshold
    out of range, a lookalike TextInputHost.exe, JSON-shaped files that are
    not state files, a backup naming another task, a task definition that
    would run another program or with administrator rights, an unwritable
    backup folder, a user tag that imitates the undo's internal marker.

    This script is read-only and per-user. It needs no administrator rights.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-SafetyLogic.ps1
    Runs every check; exit 0 only if all pass.

.NOTES
    Exit code: 0 all passed, 1 any failed (including a check that threw).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$script:pass = 0; $script:fail = 0
function Check {
    # [object], not [bool]: a value that cannot become a bool must FAIL here,
    # not vanish at parameter binding (MODULE-STANDARD R2.8a).
    param([string]$What, [object]$Ok)
    $b = $false
    try { if ($Ok -is [bool]) { $b = $Ok } else { throw "not a yes/no answer: $Ok" } }
    catch { $script:fail++; Write-Host "      FAILED: $What ($($_.Exception.Message))"; return }
    if ($b) { $script:pass++ } else { $script:fail++; Write-Host "      FAILED: $What" }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('tig-selftest-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

# A task definition exactly like the ones the install creates, built as XML
# without registering anything.
function New-FakeTaskXml {
    param([string]$Command = (Join-Path $env:SystemRoot 'System32\conhost.exe'),
          [string]$Arguments = (Get-TigTaskArguments -ModuleDir $here -ThresholdPercent 90 -WindowSeconds 60),
          [string]$Interval = 'PT10M', [string]$RunLevel = 'LeastPrivilege', [string]$UserId = (Get-TigUserId),
          [string]$ExtraAction = '')
@"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers><TimeTrigger><Repetition><Interval>$Interval</Interval><StopAtDurationEnd>false</StopAtDurationEnd></Repetition><StartBoundary>2026-09-28T19:00:00</StartBoundary><Enabled>true</Enabled></TimeTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>$UserId</UserId><LogonType>InteractiveToken</LogonType><RunLevel>$RunLevel</RunLevel></Principal></Principals>
  <Actions Context="Author"><Exec><Command>$([Security.SecurityElement]::Escape($Command))</Command><Arguments>$([Security.SecurityElement]::Escape($Arguments))</Arguments></Exec>$ExtraAction</Actions>
</Task>
"@
}

Write-Host ''
Write-Host '  TextInputHost guard - safety logic self-test'
Write-Host ('  ' + ('-' * 74))
Write-Host '  Changes nothing real. Never touches Task Scheduler or a running program.'
Write-Host ''

try {
    Write-Host '  1. The guard only ends a process that was stuck for the whole window'
    Check 'measured 99 % for 60 s: end'                 ((Get-TigVerdict -CpuSeconds 59.4 -ElapsedSeconds 60 -ThresholdPercent 90 -AgeSeconds 3600) -eq 'end')
    Check 'exactly at the threshold: end'               ((Get-TigVerdict -CpuSeconds 54 -ElapsedSeconds 60 -ThresholdPercent 90 -AgeSeconds 3600) -eq 'end')
    Check 'just under the threshold: ok'                ((Get-TigVerdict -CpuSeconds 53.9 -ElapsedSeconds 60 -ThresholdPercent 90 -AgeSeconds 3600) -eq 'ok')
    Check 'idle: ok'                                    ((Get-TigVerdict -CpuSeconds 0.1 -ElapsedSeconds 60 -ThresholdPercent 90 -AgeSeconds 3600) -eq 'ok')
    Check 'started during the window: not judged'       ((Get-TigVerdict -CpuSeconds 30 -ElapsedSeconds 60 -ThresholdPercent 90 -AgeSeconds 30) -eq 'young')
    Check 'zero-length window: unknown, not end'        ((Get-TigVerdict -CpuSeconds 5 -ElapsedSeconds 0 -ThresholdPercent 90 -AgeSeconds 3600) -eq 'unknown')
    Check 'negative processor time: unknown'            ((Get-TigVerdict -CpuSeconds -1 -ElapsedSeconds 60 -ThresholdPercent 90 -AgeSeconds 3600) -eq 'unknown')
    Check 'non-numeric input: unknown'                  ((Get-TigVerdict -CpuSeconds 'lots' -ElapsedSeconds 60 -ThresholdPercent 90 -AgeSeconds 3600) -eq 'unknown')
    Check 'missing process age: unknown'                ((Get-TigVerdict -CpuSeconds 59 -ElapsedSeconds 60 -ThresholdPercent 90 -AgeSeconds $null) -eq 'unknown')
    Check 'unreadable counter: unknown, not "idle"'     ((Get-TigVerdict -CpuSeconds $null -ElapsedSeconds 60 -ThresholdPercent 90 -AgeSeconds 3600) -eq 'unknown')
    Check 'unreadable counter gives no percentage'      ($null -eq (Get-TigCpuPercent -CpuSeconds $null -ElapsedSeconds 60))
    Check 'threshold below 50 %: unknown, not end'      ((Get-TigVerdict -CpuSeconds 59 -ElapsedSeconds 60 -ThresholdPercent 10 -AgeSeconds 3600) -eq 'unknown')
    Check 'percent is of ONE core (2 cores busy = 200)' ((Get-TigCpuPercent -CpuSeconds 120 -ElapsedSeconds 60) -eq 200)

    Write-Host '  2. Only the Windows TextInputHost is ever a candidate'
    $real = Join-Path $env:SystemRoot 'SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\TextInputHost.exe'
    Check 'the SystemApps copy: genuine'                (Test-TigGenuinePath $real)
    Check 'same name elsewhere: not genuine'            (-not (Test-TigGenuinePath 'C:\Users\x\Downloads\TextInputHost.exe'))
    Check 'path climbing out with ..: not genuine'      (-not (Test-TigGenuinePath (Join-Path $env:SystemRoot 'SystemApps\..\..\Temp\TextInputHost.exe')))
    Check 'another program in SystemApps: not genuine'  (-not (Test-TigGenuinePath (Join-Path $env:SystemRoot 'SystemApps\x\explorer.exe')))
    Check 'unknown path: not genuine'                   (-not (Test-TigGenuinePath ''))

    Write-Host '  3. A file that is merely JSON-shaped is not a state file'
    $good = Get-TigState
    Check 'the real current state is accepted'          (Test-TigStateShape -State ([pscustomobject]$good))
    Check 'null rejected'                               (-not (Test-TigStateShape -State $null))
    Check 'missing task entry rejected'                 (-not (Test-TigStateShape -State ([pscustomobject]@{ schemaVersion = 1 })))
    Check 'wrong schema rejected'                       (-not (Test-TigStateShape -State ([pscustomobject]@{ schemaVersion = 9; task = [pscustomobject]$good.task })))
    Check 'non-numeric schema rejected, no crash'       (-not (Test-TigStateShape -State ([pscustomobject]@{ schemaVersion = 'one'; task = [pscustomobject]$good.task })))
    Check 'a backup naming ANOTHER task rejected'       (-not (Test-TigStateShape -State ([pscustomobject]@{ schemaVersion = 1; task = [pscustomobject]@{ path = '\Microsoft\Windows\'; name = 'Something'; existed = $false; xml = $null } })))
    Check '"existed" as text rejected'                  (-not (Test-TigStateShape -State ([pscustomobject]@{ schemaVersion = 1; task = [pscustomobject]@{ path = $script:TigTask.TaskPath; name = $script:TigTask.TaskName; existed = 'yes'; xml = $null } })))
    Check 'existed with no definition rejected'         (-not (Test-TigStateShape -State ([pscustomobject]@{ schemaVersion = 1; task = [pscustomobject]@{ path = $script:TigTask.TaskPath; name = $script:TigTask.TaskName; existed = $true; xml = '' } })))
    Check 'a JSON array rejected'                       (-not (Test-TigStateShape -State @(1, 2)))

    Write-Host '  4. A backup can only put back a task this module creates'
    Check 'our own definition: accepted'                ((Test-TigLegitTaskXml -Xml (New-FakeTaskXml) -ModuleDir $here) -eq '')
    Check 'runs another program: refused'               ((Test-TigLegitTaskXml -Xml (New-FakeTaskXml -Command 'C:\Windows\System32\cmd.exe') -ModuleDir $here) -ne '')
    Check 'runs another script: refused'                ((Test-TigLegitTaskXml -Xml (New-FakeTaskXml -Arguments '--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Temp\evil.ps1" -ThresholdPercent 90 -WindowSeconds 60 -Quiet') -ModuleDir $here) -ne '')
    Check 'extra arguments smuggled in: refused'        ((Test-TigLegitTaskXml -Xml (New-FakeTaskXml -Arguments ((Get-TigTaskArguments -ModuleDir $here -ThresholdPercent 90 -WindowSeconds 60) + ' ; calc')) -ModuleDir $here) -ne '')
    Check 'administrator rights: refused'               ((Test-TigLegitTaskXml -Xml (New-FakeTaskXml -RunLevel 'HighestAvailable') -ModuleDir $here) -ne '')
    Check 'another account: refused'                    ((Test-TigLegitTaskXml -Xml (New-FakeTaskXml -UserId 'OTHERPC\someone') -ModuleDir $here) -ne '')
    Check 'threshold out of range: refused'             ((Test-TigLegitTaskXml -Xml (New-FakeTaskXml -Arguments (Get-TigTaskArguments -ModuleDir $here -ThresholdPercent 20 -WindowSeconds 60)) -ModuleDir $here) -ne '')
    Check 'interval of 1 minute: refused'               ((Test-TigLegitTaskXml -Xml (New-FakeTaskXml -Interval 'PT1M') -ModuleDir $here) -ne '')
    Check 'a second action added: refused'              ((Test-TigLegitTaskXml -Xml (New-FakeTaskXml -ExtraAction '<Exec><Command>calc.exe</Command></Exec>') -ModuleDir $here) -ne '')
    Check 'not XML at all: refused'                     ((Test-TigLegitTaskXml -Xml 'hello' -ModuleDir $here) -ne '')
    Check 'interval read correctly (1 hour)'            ((Get-TigTaskSettings -Xml (New-FakeTaskXml -Interval 'PT1H')).IntervalMinutes -eq 60)

    Write-Host '  5. Comparing tasks by what they do'
    Check 'same definition: same'                       (Test-TigSameTask -XmlA (New-FakeTaskXml) -XmlB (New-FakeTaskXml))
    Check 'different interval: different'               (-not (Test-TigSameTask -XmlA (New-FakeTaskXml) -XmlB (New-FakeTaskXml -Interval 'PT20M')))
    Check 'task versus no task: different'              (-not (Test-TigSameTask -XmlA (New-FakeTaskXml) -XmlB ''))
    Check 'no task versus no task: same'                (Test-TigSameTask -XmlA '' -XmlB $null)

    Write-Host '  6. Backups: verified, original written once and only by the install'
    $b1 = Save-TigBackup -BackupDir $tmp -Tag 'selftest'
    Check 'backup written and proved'                   ([bool]$b1 -and (Test-Path -LiteralPath $b1))
    Check 'a plain backup does NOT create the original' (-not (Test-Path -LiteralPath (Join-Path $tmp 'original-state.json')))
    $b2 = Save-TigBackup -BackupDir $tmp -RecordAsOriginal
    $orig = Join-Path $tmp 'original-state.json'
    Check 'the install''s backup creates the original'  (Test-Path -LiteralPath $orig)
    Set-Content -LiteralPath $orig -Value '{"marker":"first"}' -Encoding UTF8
    $null = Save-TigBackup -BackupDir $tmp -RecordAsOriginal
    Check 'the original is never overwritten'           ((Get-Content -LiteralPath $orig -Raw) -match 'first')
    $blocker = Join-Path $tmp 'a-file'; Set-Content -LiteralPath $blocker -Value 'x'
    Check 'unwritable destination returns failure'      ($null -eq (Save-TigBackup -BackupDir (Join-Path $blocker 'sub') 6>$null))
    Check 'a written backup reads back as a state'      ($null -ne (Read-TigBackup $b1))
    $bad = Join-Path $tmp 'state_2000-01-01_00-00-00.json'; Set-Content -LiteralPath $bad -Value '{"schemaVersion":1}' -Encoding UTF8
    Check 'a JSON-shaped fake reads back as nothing'    ($null -eq (Read-TigBackup $bad))

    Write-Host '  7. The undo never offers its own snapshots, and tags cannot imitate them'
    $pre = Save-TigBackup -BackupDir $tmp -InternalSuffix 'prerestore'
    Check 'internal snapshot is marked _~prerestore'    ((Split-Path -Leaf $pre) -match '_~prerestore\.json$')
    Check 'not offered as a restore point'              (@(Get-TigBackups -BackupDir $tmp | Where-Object { $_.Name -match 'prerestore' }).Count -eq 0)
    Check 'listed when asked for'                       (@(Get-TigBackups -BackupDir $tmp -IncludeInternal | Where-Object { $_.Name -match 'prerestore' }).Count -eq 1)
    Check 'the original is not a "newest" candidate'    (@(Get-TigBackups -BackupDir $tmp | Where-Object { $_.Name -eq 'original-state.json' }).Count -eq 0)
    Check 'user tag "~prerestore" loses its tilde'      ((ConvertTo-TigSafeTag '~prerestore') -notmatch '~')
    $userPre = Save-TigBackup -BackupDir $tmp -Tag '~prerestore'
    Check '...so its backup IS offered'                 (@(Get-TigBackups -BackupDir $tmp | Where-Object { $_.FullName -eq $userPre }).Count -eq 1)
    Check 'colon stripped from tags'                    ((ConvertTo-TigSafeTag 'a:b') -notmatch ':')
    Check 'long tag capped'                             ((ConvertTo-TigSafeTag ('x' * 100)).Length -le 41)

    Write-Host '  8a. The measurement really waits its whole window (read-only)'
    if (@(Get-TigProcesses).Count) {
        $m = @(Measure-TigProcesses -WindowSeconds 3)
        Check 'one result per TextInputHost'            ($m.Count -ge 1)
        Check 'the window lasted about 3 s, not 0'      ($m[0].ElapsedSeconds -ge 2.7)
        Check 'a percentage came out'                   ($null -ne $m[0].Percent -or $m[0].Exited)
    } else {
        Write-Host '      (no TextInputHost running: not tested this time, and not counted as passed)'
    }

    Write-Host '  8. Restoring a refused task changes nothing'
    $evil = [pscustomobject]@{ schemaVersion = 1; task = [pscustomobject]@{ path = $script:TigTask.TaskPath; name = $script:TigTask.TaskName; existed = $true; xml = (New-FakeTaskXml -Command 'C:\Windows\System32\cmd.exe') } }
    $before = [bool](Get-TigTask)
    $r = Set-TigTaskFromState -State $evil -ModuleDir $here
    Check 'refused, and says so'                        ((-not $r.ok) -and $r.what -match '^refused')
    Check 'Task Scheduler untouched'                    ([bool](Get-TigTask) -eq $before)
}
catch {
    # an exception means every check after it never ran: that is a failure,
    # never a quiet "0 failed" (MODULE-STANDARD R2.8a)
    $script:fail++
    Write-Host "      FAILED: the self-test stopped early: $($_.Exception.Message)"
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    checks passed : {0}" -f $script:pass)
Write-Host ("    checks failed : {0}" -f $script:fail)
Write-Host ''
if ($script:fail) { exit 1 }
Write-Host '    All safety checks passed. What this does NOT show: that installing'
Write-Host '    and undoing really work. That is what "5 - Prove the undo works" does.'
Write-Host ''
exit 0
