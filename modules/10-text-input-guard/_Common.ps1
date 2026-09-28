<#
.SYNOPSIS
    Shared core for the TextInputHost guard module. This is a LIBRARY.
    Dot-source it; running it directly does nothing but say so.

.DESCRIPTION
    -------------------------------------------------------------------------
    WHAT THIS MODULE IS FOR
    -------------------------------------------------------------------------
    TextInputHost.exe is part of Windows 11. It draws the touch keyboard, the
    emoji panel (Win + .), clipboard history (Win + V), voice typing and
    typing suggestions, and it should sit idle until one of those is opened.

    On the audited machine on 2026-09-28, one thread inside it ran without
    stopping for about 12 hours and held one processor core at 99 %. Nothing
    in the machine's settings explained it. Ending the process freed the core
    and Windows started a fresh, idle copy the next time it was needed.

    This module installs a guard: a scheduled task, run as the signed-in user
    with no administrator rights, that every few minutes measures how much
    processor time TextInputHost used over one minute, and ends it only if it
    held (by default) 90 % of one core or more for that whole minute.

    It does NOT disable the feature or its service. The service behind it
    (TextInputManagementService) also carries typing into the Start menu
    search box, Settings and other modern Windows apps; switching it off
    would break typing there.

    -------------------------------------------------------------------------
    THE ONE THING THIS MODULE CHANGES
    -------------------------------------------------------------------------
    One scheduled task, \W11T\TextInputHost guard, in the current user's
    context. The backup records whether it existed and, if it did, its full
    definition (XML). The undo removes it, or puts back the recorded one.

    -------------------------------------------------------------------------
    DOCUMENTED AND OBSERVED
    -------------------------------------------------------------------------
    What TextInputHost is and why it spins is not documented by Microsoft in
    the corpus this project holds; it is engineering observation from this
    machine, stated as such in the README, with the way to check it.
#>

$script:TigSchemaVersion = 1

# ---------------------------------------------------------------------------
#  THE SETTINGS TABLE. One row: the scheduled task. Install, backup, restore,
#  test and the round trip all read this row, so they cannot drift apart
#  (MODULE-STANDARD R2.7).
# ---------------------------------------------------------------------------
$script:TigTask = @{
    TaskPath = '\W11T\'
    TaskName = 'TextInputHost guard'
    Script   = 'Invoke-TextInputGuard.ps1'
    Desc     = 'a scheduled task that ends TextInputHost only when it is stuck using a whole processor core'
}

# The guard's defaults, and the ranges the install accepts.
$script:TigDefaults = @{ IntervalMinutes = 10; ThresholdPercent = 90; WindowSeconds = 60 }
$script:TigRanges   = @{ IntervalMinutes = @(5, 60); ThresholdPercent = @(50, 100); WindowSeconds = @(30, 120) }

# The process the guard is allowed to end: this name, from this folder only.
$script:TigProcessName = 'TextInputHost'
function Get-TigGenuineRoot { Join-Path $env:SystemRoot 'SystemApps' }

# ---------------------------------------------------------------------------
#  ENVIRONMENT
# ---------------------------------------------------------------------------
function Get-TigOsBuild {
    # Read from the registry, not Get-CimInstance: CIM makes -WhatIf narrate
    # module loading and buries the preview (MODULE-STANDARD R6.3).
    (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).CurrentBuildNumber
}

function Get-TigUserId { "$env:USERDOMAIN\$env:USERNAME" }

# ---------------------------------------------------------------------------
#  THE GUARD'S DECISION. Pure: numbers in, a verdict out. Tested by
#  Test-SafetyLogic.ps1 with inputs normal use never produces.
# ---------------------------------------------------------------------------
function Get-TigCpuPercent {
    <#  Processor time used over a window, as a percentage of ONE core.
        Cumulative counter, differenced: never an instantaneous sample
        (MODULE-STANDARD R15.3). Returns $null when it cannot be computed. #>
    param($CpuSeconds, $ElapsedSeconds)
    # $null -as [double] is 0, not $null: an unreadable counter would read as
    # "idle". Test for missing values before converting.
    if ($null -eq $CpuSeconds -or $null -eq $ElapsedSeconds) { return $null }
    $c = $CpuSeconds -as [double]; $e = $ElapsedSeconds -as [double]
    if ($null -eq $c -or $null -eq $e -or $e -le 0 -or $c -lt 0) { return $null }
    [math]::Round(100.0 * $c / $e, 1)
}

function Get-TigVerdict {
    <#  'end'    the process used at least ThresholdPercent of one core for
                 the whole window, and was alive for the whole window
        'young'  it started during the window: not judged, left alone
        'ok'     below the threshold
        'unknown' the numbers could not be used: left alone              #>
    param($CpuSeconds, $ElapsedSeconds, $ThresholdPercent, $AgeSeconds)
    $pct = Get-TigCpuPercent -CpuSeconds $CpuSeconds -ElapsedSeconds $ElapsedSeconds
    if ($null -eq $ThresholdPercent -or $null -eq $AgeSeconds) { return 'unknown' }
    $thr = $ThresholdPercent -as [double]; $age = $AgeSeconds -as [double]
    if ($null -eq $pct -or $null -eq $thr -or $null -eq $age -or $thr -lt 50 -or $thr -gt 100) { return 'unknown' }
    if ($age -lt ($ElapsedSeconds -as [double])) { return 'young' }
    if ($pct -ge $thr) { return 'end' }
    'ok'
}

function Test-TigGenuinePath {
    <#  True only for TextInputHost.exe inside %SystemRoot%\SystemApps. A
        program of the same name anywhere else is never ended. #>
    param([string]$Path)
    if (-not $Path) { return $false }
    $root = (Get-TigGenuineRoot).TrimEnd('\') + '\'
    ($Path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and
     [IO.Path]::GetFileName($Path) -ieq 'TextInputHost.exe' -and $Path -notmatch '\.\.')
}

function Get-TigProcesses {
    <#  TextInputHost processes in THIS session only, with what the guard and
        the Test- script need. Read-only. #>
    $sid = [Diagnostics.Process]::GetCurrentProcess().SessionId
    @(Get-Process -Name $script:TigProcessName -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $sid } | ForEach-Object {
        $path = $null; $cpu = $null; $start = $null
        try { $path = $_.Path } catch { }
        try { $cpu = $_.TotalProcessorTime.TotalSeconds } catch { }
        try { $start = $_.StartTime } catch { }
        [pscustomobject]@{ Id = $_.Id; Path = $path; CpuSeconds = $cpu; StartTime = $start; Genuine = (Test-TigGenuinePath $path); Process = $_ }
    })
}

function Measure-TigProcesses {
    <#  Measure every TextInputHost in this session over one window. Read-only:
        it waits and reads counters, it ends nothing. #>
    param([int]$WindowSeconds = 60)
    # @(): in Windows PowerShell 5.1 a single object returned from a function
    # is not a list and has no dependable .Count, so without it the wait was
    # skipped and a 3 ms "window" was measured (found 2026-09-28 by running
    # the real scheduled task; the pure-logic self-test could not see it).
    $first = @(Get-TigProcesses)
    $t0 = [Diagnostics.Stopwatch]::StartNew()
    if ($first.Count -gt 0) { Start-Sleep -Seconds $WindowSeconds }
    $elapsed = $t0.Elapsed.TotalSeconds
    # a window cut short measures nothing trustworthy: report it as unknown
    $short = $elapsed -lt (0.9 * $WindowSeconds)
    foreach ($p in $first) {
        $cpu1 = $null
        try { $p.Process.Refresh(); if (-not $p.Process.HasExited) { $cpu1 = $p.Process.TotalProcessorTime.TotalSeconds } } catch { }
        $used = if ($null -ne $cpu1 -and $null -ne $p.CpuSeconds -and -not $short) { $cpu1 - $p.CpuSeconds } else { $null }
        $age = if ($p.StartTime) { ((Get-Date) - $p.StartTime).TotalSeconds } else { $null }
        [pscustomobject]@{
            Id = $p.Id; Path = $p.Path; Genuine = $p.Genuine; StartTime = $p.StartTime
            CpuSeconds = $used; ElapsedSeconds = [math]::Round($elapsed, 1); AgeSeconds = $age
            Percent = (Get-TigCpuPercent -CpuSeconds $used -ElapsedSeconds $elapsed)
            Exited = ($null -eq $cpu1)
        }
    }
}

# ---------------------------------------------------------------------------
#  THE TASK: build, read, check
# ---------------------------------------------------------------------------
function Get-TigTaskArguments {
    param([string]$ModuleDir, [int]$ThresholdPercent, [int]$WindowSeconds)
    $script = Join-Path $ModuleDir $script:TigTask.Script
    # conhost --headless runs PowerShell with no window: no console flashes
    # up every few minutes (observed on build 26200: MainWindowHandle 0).
    ('--headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -ThresholdPercent {1} -WindowSeconds {2} -Quiet' -f $script, $ThresholdPercent, $WindowSeconds)
}

function Get-TigTask {
    Get-ScheduledTask -TaskPath $script:TigTask.TaskPath -TaskName $script:TigTask.TaskName -ErrorAction SilentlyContinue
}

function Get-TigTaskXml {
    $t = Get-TigTask
    if (-not $t) { return $null }
    try { Export-ScheduledTask -TaskPath $script:TigTask.TaskPath -TaskName $script:TigTask.TaskName -ErrorAction Stop } catch { $null }
}

function Get-TigTaskSettings {
    <#  Read the guard's settings back out of a task definition (XML text).
        Returns $null for anything that is not a well-formed guard task. #>
    param([string]$Xml)
    if (-not $Xml) { return $null }
    try { [xml]$doc = $Xml } catch { return $null }
    $ns = New-Object Xml.XmlNamespaceManager $doc.NameTable
    $ns.AddNamespace('t', 'http://schemas.microsoft.com/windows/2004/02/mit/task')
    $execs = @($doc.SelectNodes('//t:Actions/t:Exec', $ns))
    $other = @($doc.SelectNodes('//t:Actions/*', $ns)) | Where-Object { $_.LocalName -ne 'Exec' }
    if ($execs.Count -ne 1 -or @($other).Count) { return $null }
    $cmd = [string]$execs[0].SelectSingleNode('t:Command', $ns).InnerText
    $arg = [string]$execs[0].SelectSingleNode('t:Arguments', $ns).InnerText
    $interval = [string]($doc.SelectSingleNode('//t:Triggers/*/t:Repetition/t:Interval', $ns)).InnerText
    $level = [string]($doc.SelectSingleNode('//t:Principals/t:Principal/t:RunLevel', $ns)).InnerText
    $user = [string]($doc.SelectSingleNode('//t:Principals/t:Principal/t:UserId', $ns)).InnerText
    $m = [regex]::Match($arg, '^--headless powershell\.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "([^"]+)" -ThresholdPercent (\d+) -WindowSeconds (\d+) -Quiet$')
    $minutes = $null
    $im = [regex]::Match($interval, '^PT(?:(\d+)H)?(?:(\d+)M)?$')
    if ($im.Success) { $minutes = 60 * ([int]('0' + $im.Groups[1].Value)) + [int]('0' + $im.Groups[2].Value) }
    [pscustomobject]@{
        Command = $cmd; Arguments = $arg; ScriptPath = $(if ($m.Success) { $m.Groups[1].Value } else { $null })
        ThresholdPercent = $(if ($m.Success) { [int]$m.Groups[2].Value } else { $null })
        WindowSeconds    = $(if ($m.Success) { [int]$m.Groups[3].Value } else { $null })
        IntervalMinutes  = $minutes; RunLevel = $level; UserId = $user
    }
}

function Test-TigLegitTaskXml {
    <#  A task definition may only be written back if it is exactly the kind
        of task this module creates: one action, conhost --headless running
        THIS module's guard script with in-range settings, run with the
        user's normal rights. Anything else in a backup is refused
        (MODULE-STANDARD R16.5). Returns '' if legitimate, or the reason. #>
    param([string]$Xml, [string]$ModuleDir)
    $s = Get-TigTaskSettings -Xml $Xml
    if (-not $s) { return 'not a task definition with exactly one program to run' }
    $conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
    if ([Environment]::ExpandEnvironmentVariables($s.Command) -ine $conhost) { return "runs $($s.Command), not conhost.exe" }
    if (-not $s.ScriptPath) { return 'its arguments are not the guard''s arguments' }
    $mine = Join-Path $ModuleDir $script:TigTask.Script
    if ($s.ScriptPath -ine $mine) { return "runs $($s.ScriptPath), not this module's guard" }
    $r = $script:TigRanges
    if ($s.ThresholdPercent -lt $r.ThresholdPercent[0] -or $s.ThresholdPercent -gt $r.ThresholdPercent[1]) { return "threshold $($s.ThresholdPercent) % is out of range" }
    if ($s.WindowSeconds -lt $r.WindowSeconds[0] -or $s.WindowSeconds -gt $r.WindowSeconds[1]) { return "window $($s.WindowSeconds) s is out of range" }
    if ($null -eq $s.IntervalMinutes -or $s.IntervalMinutes -lt $r.IntervalMinutes[0] -or $s.IntervalMinutes -gt $r.IntervalMinutes[1]) { return 'the repeat interval is missing or out of range' }
    if ($s.RunLevel -and $s.RunLevel -ne 'LeastPrivilege') { return "it would run with $($s.RunLevel) rights" }
    $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
    if ($s.UserId -and $s.UserId -ne $sid -and $s.UserId -ine (Get-TigUserId) -and $s.UserId -ine $env:USERNAME) { return "it belongs to another account ($($s.UserId))" }
    ''
}

function Test-TigSameTask {
    <#  Do two task definitions (XML, or $null for "no task") describe the
        same guard? Compared by what the task DOES - program, arguments,
        interval, rights - because Task Scheduler rewrites incidental XML
        details (dates, whitespace) when it stores a definition.          #>
    param([string]$XmlA, [string]$XmlB)
    if (-not $XmlA -and -not $XmlB) { return $true }
    if (-not $XmlA -or -not $XmlB) { return $false }
    $a = Get-TigTaskSettings -Xml $XmlA; $b = Get-TigTaskSettings -Xml $XmlB
    if (-not $a -or -not $b) { return $false }
    foreach ($p in 'Command', 'Arguments', 'IntervalMinutes', 'RunLevel') { if ([string]$a.$p -ne [string]$b.$p) { return $false } }
    $true
}

function New-TigTaskDefinition {
    <#  The task as the install creates it. Returns the pieces for
        Register-ScheduledTask. #>
    param([string]$ModuleDir, [int]$IntervalMinutes, [int]$ThresholdPercent, [int]$WindowSeconds)
    $action = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\conhost.exe') `
        -Argument (Get-TigTaskArguments -ModuleDir $ModuleDir -ThresholdPercent $ThresholdPercent -WindowSeconds $WindowSeconds)
    # A one-off start with an open-ended repetition: runs every N minutes for
    # as long as the account is signed in, and carries on after a restart.
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)
    $principal = New-ScheduledTaskPrincipal -UserId (Get-TigUserId) -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew -StartWhenAvailable
    @{ Action = $action; Trigger = $trigger; Principal = $principal; Settings = $settings
       Description = 'Windows.11.tweaks.optimisation module 10. Ends TextInputHost.exe only when it has used a whole processor core for a full minute; Windows starts a fresh copy when needed. Remove with Restore-TextInputGuard.ps1.' }
}

# ---------------------------------------------------------------------------
#  STATE, BACKUPS AND RESTORE POINTS
# ---------------------------------------------------------------------------
function Get-TigState {
    $xml = Get-TigTaskXml
    [ordered]@{
        schemaVersion = $script:TigSchemaVersion
        capturedUtc   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        host          = $env:COMPUTERNAME
        user          = $env:USERNAME
        osBuild       = (Get-TigOsBuild)
        task          = [ordered]@{ path = $script:TigTask.TaskPath; name = $script:TigTask.TaskName
                                    existed = [bool]$xml; xml = $xml }
    }
}

function Test-TigStateShape {
    <#  A state file must have the right schema, as a number, and a task
        entry naming THIS module's task. A merely JSON-shaped file is not a
        state file. #>
    param($State)
    if ($null -eq $State) { return $false }
    foreach ($p in 'schemaVersion', 'task') { if (-not $State.PSObject.Properties[$p] -and -not ($State -is [Collections.IDictionary] -and $State.Contains($p))) { return $false } }
    $ver = $State.schemaVersion -as [int]
    if ($null -eq $ver -or $ver -ne $script:TigSchemaVersion) { return $false }
    $t = $State.task
    if ($null -eq $t -or $t -is [Array]) { return $false }
    if ([string]$t.path -ne $script:TigTask.TaskPath -or [string]$t.name -ne $script:TigTask.TaskName) { return $false }
    if ($null -eq ($t.existed -as [bool]) -or ($t.existed -isnot [bool])) { return $false }
    if ($t.existed -and -not [string]$t.xml) { return $false }
    $true
}

function ConvertTo-TigSafeTag {
    param([string]$Tag)
    if (-not $Tag) { return '' }
    $clean = ($Tag -replace '[^A-Za-z0-9\-_.]', '-').Trim('-')
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    if ($clean) { "_$clean" } else { '' }
}

function Save-TigBackup {
    <#  Write the full state to backups\state_<stamp>[_tag].json and PROVE
        it: exists, parses, right shape. Returns the path, or $null on any
        failure. Only the install may pass -RecordAsOriginal (R4.4a); the
        original is written once and nothing overwrites it (R4.4).
        -InternalSuffix is for the undo's own snapshot (R16.3).           #>
    param([Parameter(Mandatory)][string]$BackupDir, [string]$Tag = '', [string]$InternalSuffix = '',
          [switch]$RecordAsOriginal, $State)
    if ($null -eq $State) { $State = Get-TigState }
    try { if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force -ErrorAction Stop | Out-Null } }
    catch { Write-Host "    BACKUP FAILED: cannot create $BackupDir - $($_.Exception.Message)"; return $null }
    $suffix = if ($InternalSuffix) { "_~$InternalSuffix" } else { ConvertTo-TigSafeTag $Tag }
    $name = 'state_{0}{1}.json' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'), $suffix
    $path = Join-Path $BackupDir $name
    $n = 1
    while (Test-Path -LiteralPath $path) { $path = Join-Path $BackupDir ('state_{0}{1}_{2}.json' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'), $suffix, $n); $n++ }
    $json = $State | ConvertTo-Json -Depth 6
    try { Set-Content -LiteralPath $path -Value $json -Encoding UTF8 -ErrorAction Stop }
    catch { Write-Host "    BACKUP FAILED: could not write $path - $($_.Exception.Message)"; return $null }
    try {
        $back = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-TigStateShape -State $back)) { Write-Host "    BACKUP FAILED: $path is not a usable state file"; return $null }
    }
    catch { Write-Host "    BACKUP FAILED: $path cannot be read back - $($_.Exception.Message)"; return $null }
    if ($RecordAsOriginal) {
        $orig = Join-Path $BackupDir 'original-state.json'
        if (-not (Test-Path -LiteralPath $orig)) {
            try { Set-Content -LiteralPath $orig -Value $json -Encoding UTF8 -ErrorAction Stop }
            catch { Write-Host "    BACKUP FAILED: could not write $orig - $($_.Exception.Message)"; return $null }
        }
    }
    $path
}

function Read-TigBackup {
    <#  Read and check a state file. Returns the state, or $null. #>
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    try { $s = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if (Test-TigStateShape -State $s) { $s } else { $null }
}

function Get-TigBackups {
    <#  Restore points, newest first. The undo's own pre-restore snapshots
        are excluded unless asked for (R16.3); original-state.json is never
        a candidate for "newest".                                         #>
    param([Parameter(Mandatory)][string]$BackupDir, [switch]$IncludeInternal)
    if (-not (Test-Path -LiteralPath $BackupDir)) { return @() }
    @(Get-ChildItem -LiteralPath $BackupDir -Filter 'state_*.json' -File -ErrorAction SilentlyContinue |
      Where-Object { $IncludeInternal -or $_.Name -notmatch '_~prerestore' } |
      Sort-Object Name -Descending)
}

function Set-TigTaskFromState {
    <#  Make the machine match a state: remove the task, or register the
        recorded definition after checking it (R16.5). Iterates the module's
        own one-row table, never names taken from the backup.
        Returns @{ ok; what }.                                            #>
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$ModuleDir)
    $t = $State.task
    $now = Get-TigTask
    if (-not $t.existed) {
        if (-not $now) { return @{ ok = $true; what = 'already absent' } }
        try { Unregister-ScheduledTask -TaskPath $script:TigTask.TaskPath -TaskName $script:TigTask.TaskName -Confirm:$false -ErrorAction Stop }
        catch { return @{ ok = $false; what = "could not remove the task: $($_.Exception.Message)" } }
        if (Get-TigTask) { return @{ ok = $false; what = 'the task is still there after removal' } }
        return @{ ok = $true; what = 'removed (it did not exist in that backup)' }
    }
    $why = Test-TigLegitTaskXml -Xml ([string]$t.xml) -ModuleDir $ModuleDir
    if ($why) { return @{ ok = $false; what = "refused: the recorded task is not one this module creates ($why)" } }
    if ($now -and (Test-TigSameTask -XmlA (Get-TigTaskXml) -XmlB ([string]$t.xml)) -and $now.State -ne 'Disabled') { return @{ ok = $true; what = 'already as recorded' } }
    try {
        Register-ScheduledTask -TaskPath $script:TigTask.TaskPath -TaskName $script:TigTask.TaskName -Xml ([string]$t.xml) -Force -ErrorAction Stop | Out-Null
    }
    catch { return @{ ok = $false; what = "could not register the recorded task: $($_.Exception.Message)" } }
    if (-not (Get-TigTask)) { return @{ ok = $false; what = 'the task is not there after registering it' } }
    @{ ok = $true; what = 'put back as recorded' }
}

# ---------------------------------------------------------------------------
#  THE GUARD'S LOG (only actions and errors; one line each)
# ---------------------------------------------------------------------------
function Get-TigLogPath { param([string]$ModuleDir) Join-Path $ModuleDir 'guard-log.txt' }

function Write-TigLog {
    param([string]$ModuleDir, [string]$Line)
    try { Add-Content -LiteralPath (Get-TigLogPath $ModuleDir) -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Line) -Encoding UTF8 -ErrorAction Stop; $true }
    catch { $false }
}

if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.\s') {
    Write-Host ''
    Write-Host '  _Common.ps1 is shared code, not a script to run.'
    Write-Host '  Use the numbered .cmd files in this folder instead.'
    Write-Host ''
}
