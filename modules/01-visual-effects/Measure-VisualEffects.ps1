<#
.SYNOPSIS
    Prove - or disprove - that turning the animations off actually saves
    anything, by measuring this machine with them on and with them off.

.DESCRIPTION
    Everything else in this repository tells you what a setting does. This tells
    you what it is worth on YOUR hardware.

    It is deliberately possible for this script to report "no measurable
    difference". That is a real answer. A tweak that costs nothing to undo and
    saves nothing is worth knowing about, and a repository that only ever
    produces flattering numbers is not measuring anything.

    -------------------------------------------------------------------------
    WHAT IT DOES TO YOUR MACHINE
    -------------------------------------------------------------------------
    This is the only script in the module that changes settings WITHOUT you
    asking for a change, because it has to: to measure both sides it must put
    the machine in both states.

    For each repeat it will:
      1. put the settings back to how they were before this module ever ran
         (the write-once original-state.json), restart Explorer, wait
      2. measure the machine idle, then measure it under a fixed workload
      3. apply the module's changes, restart Explorer, wait
      4. measure the machine idle, then measure it under the same workload

    When it finishes it LEAVES THE CHANGES APPLIED, unless you pass -LeaveOriginal.
    It says which state it left the machine in, every time.

    Nothing is lost either way: the original state is written once and never
    overwritten, and "4 - UNDO everything.cmd" still works afterwards.

    -------------------------------------------------------------------------
    WHY IT TAKES SO LONG
    -------------------------------------------------------------------------
    Because a short measurement of a desktop is a random number.

    An idle Windows machine's processor usage swings by whole percentage points
    second to second - a search indexer wakes, an app phones home, the antivirus
    looks at something. To see a change worth a few milliseconds per second, the
    measurement window has to be long enough for that noise to average out, and
    it has to be repeated so you can see how big the noise was.

    The default run is two repeats of four windows. Budget about ten minutes and
    do not touch the machine while it runs.

    -------------------------------------------------------------------------
    THE WORKLOAD
    -------------------------------------------------------------------------
    Measuring an idle desktop only captures what the compositor does at rest.
    Most of the cost of animation is paid when something animates, so the script
    also opens a window of its own and drives it: menus open and close, a
    drop-down list opens and closes, a long list scrolls, a tooltip fades in and
    out, the window minimises and restores, and the window is dragged across the
    screen.

    Those seven operations were not chosen for effect. Each one is driven by a
    specific setting this module changes - menu animation and fade, combo box
    animation, smooth list scrolling, tooltip animation and fade, minimise and
    restore animation, and full-window drag.

    The workload runs on a fixed clock, so both sides perform the same number of
    operations over the same number of seconds. That is what makes "processor
    milliseconds consumed" a fair comparison rather than a race.

.PARAMETER Seconds
    Length of each measurement window. Default 25. Shorter runs finish sooner
    and resolve less.

.PARAMETER Repeats
    How many complete before/after pairs to run. Default 2. The spread between
    repeats of the SAME condition is the noise floor, and nothing smaller than
    it is reported as a saving. One repeat produces no noise floor and the
    report will say so.

.PARAMETER LeaveOriginal
    Finish with the animations back ON (the original state) rather than applied.

.PARAMETER NoWorkload
    Idle measurements only. Faster, and does not open a window on your screen,
    but it will miss most of the effect.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Measure-VisualEffects.ps1
    The full run: two before/after pairs, roughly ten minutes, ends applied.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Measure-VisualEffects.ps1 -Repeats 3 -Seconds 40
    A slower, quieter run for a machine with noisy background activity.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Measure-VisualEffects.ps1 -LeaveOriginal
    Measure both sides, then hand the machine back with the animations ON.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Measure-VisualEffects.ps1 -NoWorkload -Seconds 60
    Long idle-only comparison - what the compositor costs at rest.

.NOTES
    Needs no administrator rights: every setting involved is per-user.
    Writes RESULTS.md next to this script, deliberately WITHOUT the machine name
    or user name, so it is safe to publish.
#>

[CmdletBinding()]
param(
    [double] $Seconds = 25,
    [int]    $Repeats = 2,
    [int]    $SettleSeconds = 20,
    [switch] $LeaveOriginal,
    [switch] $NoWorkload,
    [switch] $Force,
    [string] $FromJson
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- dependencies -----------------------------------------------------------
. (Join-Path $here '_Common.ps1')

$lib = Join-Path (Split-Path -Parent (Split-Path -Parent $here)) 'READ-ONLY-diagnostics\_MeasureLib.ps1'
if (-not (Test-Path $lib)) {
    Write-Host ''
    Write-Host '  Cannot find the measurement engine:'
    Write-Host "      $lib"
    Write-Host '  This script uses the shared read-only measurement library rather than'
    Write-Host '  carrying its own copy. Keep the module inside the repository, or copy'
    Write-Host '  _MeasureLib.ps1 into a READ-ONLY-diagnostics folder two levels up.'
    Write-Host ''
    return
}
. $lib

$WatchList = @('dwm', 'explorer', 'powershell')

# ---------------------------------------------------------------------------
#  Running the module's own audited scripts, rather than reimplementing them
# ---------------------------------------------------------------------------
function Invoke-VfxScript {
    param([string]$Name, [string[]]$Arguments = @())
    $path = Join-Path $here $Name
    if (-not (Test-Path $path)) { throw "missing script: $Name" }
    $argv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $path) + $Arguments
    $out = & powershell.exe @argv 2>&1
    [pscustomobject]@{ exitCode = $LASTEXITCODE; output = ($out | Out-String) }
}

function Set-VfxConditionOriginal {
    Invoke-VfxScript -Name 'Restore-VisualEffects.ps1' -Arguments @('-Original', '-RestartExplorer')
}
function Set-VfxConditionApplied {
    Invoke-VfxScript -Name 'Disable-VisualEffects.ps1' -Arguments @('-Tag', 'measure', '-RestartExplorer')
}

# ---------------------------------------------------------------------------
#  The workload window
# ---------------------------------------------------------------------------
function New-VfxWorkloadForm {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing        -ErrorAction Stop
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $f = New-Object System.Windows.Forms.Form
    $f.Text          = 'Visual effects measurement - do not touch'
    $f.Size          = New-Object System.Drawing.Size(760, 520)
    $f.StartPosition = 'Manual'
    $f.Location      = New-Object System.Drawing.Point(120, 120)
    # TopMost so the compositor never culls it as occluded. An occluded window
    # is not composited, and a measurement of a window nobody can see is a
    # measurement of nothing.
    $f.TopMost       = $true

    $menu = New-Object System.Windows.Forms.MenuStrip
    foreach ($m in @('Alpha', 'Beta', 'Gamma')) {
        $top = New-Object System.Windows.Forms.ToolStripMenuItem
        $top.Text = $m
        for ($i = 1; $i -le 10; $i++) {
            $it = New-Object System.Windows.Forms.ToolStripMenuItem
            $it.Text = "$m item $i"
            [void]$top.DropDownItems.Add($it)
        }
        [void]$menu.Items.Add($top)
    }
    $f.MainMenuStrip = $menu
    [void]$f.Controls.Add($menu)

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Location      = New-Object System.Drawing.Point(12, 34)
    $combo.Size          = New-Object System.Drawing.Size(300, 24)
    $combo.DropDownStyle = 'DropDownList'
    $combo.MaxDropDownItems = 12
    for ($i = 1; $i -le 60; $i++) { [void]$combo.Items.Add("choice $i") }
    $combo.SelectedIndex = 0
    [void]$f.Controls.Add($combo)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.Location = New-Object System.Drawing.Point(12, 70)
    $lv.Size     = New-Object System.Drawing.Size(715, 390)
    $lv.View     = 'Details'
    $lv.FullRowSelect = $true
    $lv.GridLines     = $true
    foreach ($c in @('Name', 'Kind', 'Size', 'Notes')) { [void]$lv.Columns.Add($c, 170) }
    $lv.BeginUpdate()
    for ($i = 1; $i -le 400; $i++) {
        $item = New-Object System.Windows.Forms.ListViewItem("row $i")
        [void]$item.SubItems.Add('type ' + ($i % 7))
        [void]$item.SubItems.Add(($i * 37).ToString())
        [void]$item.SubItems.Add('filler text for painting work')
        [void]$lv.Items.Add($item)
    }
    $lv.EndUpdate()
    [void]$f.Controls.Add($lv)

    $tip = New-Object System.Windows.Forms.ToolTip
    $tip.InitialDelay = 0
    $tip.ReshowDelay  = 0

    $f.Show()
    [System.Windows.Forms.Application]::DoEvents()

    [pscustomobject]@{ form = $f; menu = $menu; combo = $combo; listview = $lv; tooltip = $tip }
}

function Invoke-VfxPump {
    <#  Let Windows do its work without burning our own processor time doing it.
        A tight DoEvents loop would add more CPU than the thing being measured. #>
    param([int]$Milliseconds)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $Milliseconds) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 8
    }
}

function Invoke-VfxWorkloadCycle {
    <#  One cycle: seven operations, each in a fixed time slot.
        Fixed slots mean both sides do the same work over the same duration,
        which is the whole point. #>
    param($Ui, [int]$Slot = 260, [int]$Index = 0)

    $f = $Ui.form
    $ops = 0

    # 1. menu open / close  - menu animation, menu fade
    try { $Ui.menu.Items[$Index % $Ui.menu.Items.Count].ShowDropDown(); $ops++ } catch { }
    Invoke-VfxPump $Slot
    try { $Ui.menu.Items[$Index % $Ui.menu.Items.Count].HideDropDown() } catch { }
    Invoke-VfxPump ([int]($Slot / 2))

    # 2. drop-down list open / close - combo box animation
    try { $Ui.combo.DroppedDown = $true; $ops++ } catch { }
    Invoke-VfxPump $Slot
    try { $Ui.combo.DroppedDown = $false } catch { }
    Invoke-VfxPump ([int]($Slot / 2))

    # 3. long list scroll - smooth scrolling
    try {
        $n = $Ui.listview.Items.Count
        foreach ($target in @(0, [int]($n * 0.5), $n - 1, [int]($n * 0.25))) {
            $Ui.listview.EnsureVisible($target)
            [System.Windows.Forms.Application]::DoEvents()
        }
        $ops++
    } catch { }
    Invoke-VfxPump $Slot

    # 4. selection - listview alpha-blended selection, selection fade
    try {
        $Ui.listview.Items[($Index * 7) % $Ui.listview.Items.Count].Selected = $true
        $Ui.listview.Select()
        $ops++
    } catch { }
    Invoke-VfxPump ([int]($Slot / 2))

    # 5. tooltip - tooltip animation, tooltip fade
    try { $Ui.tooltip.Show('measurement tooltip', $f, 400, 40, 1200); $ops++ } catch { }
    Invoke-VfxPump $Slot
    try { $Ui.tooltip.Hide($f) } catch { }
    Invoke-VfxPump ([int]($Slot / 2))

    # 6. minimise / restore - the minimise-restore animation, composited by DWM
    try { $f.WindowState = 'Minimized'; $ops++ } catch { }
    Invoke-VfxPump $Slot
    try { $f.WindowState = 'Normal'; $f.Activate() } catch { }
    Invoke-VfxPump $Slot

    # 7. drag - "show window contents while dragging"
    try {
        $x = 120; $y = 120
        foreach ($step in 1..8) {
            $f.Location = New-Object System.Drawing.Point(($x + $step * 14), ($y + $step * 8))
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 12
        }
        $f.Location = New-Object System.Drawing.Point($x, $y)
        $ops++
    } catch { }
    Invoke-VfxPump ([int]($Slot / 2))

    $ops
}

function Measure-VfxResponsiveness {
    <#
    .SYNOPSIS
        How long the in-process animated operations actually block for.
    .DESCRIPTION
        Menus and drop-downs are animated by USER32/comctl32 inside the calling
        application, using AnimateWindow, which is synchronous - the call does
        not return until the animation has finished. So timing the call is a
        legitimate latency measurement.

        Minimise and restore are NOT included here. Those are composited by DWM
        out of process; the call returns immediately and the animation plays
        afterwards, so timing the call would measure nothing. Their cost shows
        up in the processor and GPU figures instead.
    #>
    param($Ui, [int]$Iterations = 30)

    $menuMs  = New-Object System.Collections.Generic.List[double]
    $comboMs = New-Object System.Collections.Generic.List[double]

    # Warm up: first call pays for JIT and for loading the drop-down.
    try { $Ui.menu.Items[0].ShowDropDown(); $Ui.menu.Items[0].HideDropDown() } catch { }
    Invoke-VfxPump 200

    for ($i = 0; $i -lt $Iterations; $i++) {
        $item = $Ui.menu.Items[$i % $Ui.menu.Items.Count]
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try { $item.ShowDropDown() } catch { }
        $sw.Stop(); $menuMs.Add($sw.Elapsed.TotalMilliseconds)
        Invoke-VfxPump 40
        try { $item.HideDropDown() } catch { }
        Invoke-VfxPump 40

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try { $Ui.combo.DroppedDown = $true } catch { }
        $sw.Stop(); $comboMs.Add($sw.Elapsed.TotalMilliseconds)
        Invoke-VfxPump 40
        try { $Ui.combo.DroppedDown = $false } catch { }
        Invoke-VfxPump 40
    }

    function Get-Median([object]$Values) {
        $s = @($Values | Sort-Object)
        if ($s.Count -eq 0) { return $null }
        if ($s.Count % 2) { return $s[[int]($s.Count / 2)] }
        return (($s[$s.Count / 2 - 1] + $s[$s.Count / 2]) / 2)
    }

    [pscustomobject]@{
        iterations     = $Iterations
        menuOpenMs     = [math]::Round((Get-Median $menuMs), 2)
        menuOpenMaxMs  = [math]::Round((($menuMs  | Measure-Object -Maximum).Maximum), 2)
        comboOpenMs    = [math]::Round((Get-Median $comboMs), 2)
        comboOpenMaxMs = [math]::Round((($comboMs | Measure-Object -Maximum).Maximum), 2)
    }
}

# ---------------------------------------------------------------------------
#  One side of the comparison
# ---------------------------------------------------------------------------
function Measure-VfxCondition {
    param([string]$Name, [double]$Sec, [switch]$SkipWorkload)

    $result = [pscustomobject]@{
        condition      = $Name
        idle           = $null
        workload       = $null
        responsiveness = $null
        state          = $null
    }

    $result.state = Get-VfxState

    Write-Host ("      idle {0} s ..." -f $Sec) -NoNewline
    $result.idle = Invoke-MeasPhase -Seconds $Sec -Label "$Name / idle" -Watch $WatchList
    Write-Host ' done'

    if (-not $SkipWorkload) {
        $ui = $null
        try {
            $ui = New-VfxWorkloadForm
            Invoke-VfxPump 800   # let the window settle before the clock starts

            Write-Host ("      workload {0} s ..." -f $Sec) -NoNewline
            $cycles = 0
            $result.workload = Invoke-MeasPhase -Seconds $Sec -Label "$Name / workload" -Watch $WatchList -Body {
                param($deadline)
                $i = 0
                while ((Get-Date) -lt $deadline) {
                    [void](Invoke-VfxWorkloadCycle -Ui $ui -Index $i)
                    $i++
                }
                $i
            }
            $cycles = $result.workload.workload
            Write-Host (" done ({0} cycles)" -f $cycles)

            Write-Host '      responsiveness ...' -NoNewline
            $result.responsiveness = Measure-VfxResponsiveness -Ui $ui -Iterations 25
            Write-Host ' done'
        }
        catch {
            Write-Host ''
            Write-Host ("      workload failed: {0}" -f $_.Exception.Message)
        }
        finally {
            if ($ui -and $ui.form) { try { $ui.form.Close(); $ui.form.Dispose() } catch { } }
            try { [System.Windows.Forms.Application]::DoEvents() } catch { }
        }
    }
    $result
}

# ---------------------------------------------------------------------------
#  Re-analysis of a run already on disk. Changes nothing, measures nothing.
# ---------------------------------------------------------------------------
if ($FromJson) {
    if (-not (Test-Path $FromJson)) {
        Write-Host ''
        Write-Host "    No such file: $FromJson"
        Write-Host '    Saved runs live in measurements\ next to this script.'
        Write-Host ''
        return
    }
    Write-Host ''
    Write-Host '  Visual effects - re-analysing a saved run'
    Write-Host ('  ' + ('=' * 74))
    Write-Host "    source: $FromJson"
    Write-Host '    Nothing is measured and nothing is changed. The readings below were'
    Write-Host '    taken when that file was written.'
    Write-Host ''

    $doc = Get-Content $FromJson -Raw -Encoding UTF8 | ConvertFrom-Json
    $envInfo    = $doc.environment
    $Seconds    = $doc.seconds
    $Repeats    = $doc.repeats
    $NoWorkload = [bool]$doc.noWorkload
    $startState = $doc.startState
    $endState   = $doc.endState
    $finalState = $doc.finalState

    # ConvertFrom-Json produces PSCustomObjects where hashtables were stored.
    $pairs = @()
    foreach ($p in $doc.pairs) {
        foreach ($side in @('before', 'after')) {
            foreach ($phase in @('idle', 'workload')) {
                if ($p.$side.$phase) { [void](ConvertFrom-MeasJsonDelta -Delta $p.$side.$phase) }
            }
        }
        $pairs += $p
    }
}
else {

# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------
$envInfo = Get-MeasEnvironment
$startState = Get-VfxState

$phasesPerPair = if ($NoWorkload) { 2 } else { 4 }
$estMin = [math]::Ceiling((($Seconds * $phasesPerPair * $Repeats) + ($Repeats * 2 * 45)) / 60)

Write-Host ''
Write-Host '  Visual effects - before and after measurement'
Write-Host ('  ' + ('=' * 74))
Write-Host ("    processor : {0}  ({1} cores / {2} threads)" -f $envInfo.cpuName, $envInfo.cpuCores, $envInfo.cpuLogical)
foreach ($g in $envInfo.gpus) { Write-Host ("    graphics  : {0}" -f $g.name) }
Write-Host ("    memory    : {0:N0} MB   |   Windows build {1}" -f $envInfo.ramTotalMB, $envInfo.osBuild)
Write-Host ("    power     : {0}  |  scheme {1}" -f $envInfo.powerSource, $envInfo.powerScheme)
Write-Host ''

$blockers = @()
if ($envInfo.powerSource -eq 'ON BATTERY') {
    $blockers += 'The machine is on battery. Processor clocks are reduced and vary with charge level; the two halves of the comparison would not be measured at the same speed. Plug it in.'
}
$busy = Get-Process -ErrorAction SilentlyContinue |
        Group-Object ProcessName |
        ForEach-Object { [pscustomobject]@{ n = $_.Name; c = $_.Count } } |
        Where-Object { $_.n -in @('msedgewebview2', 'msedge', 'chrome', 'firefox') }
foreach ($b in $busy) {
    Write-Host ("    note: {0} is running ({1} processes). It will add background noise." -f $b.n, $b.c)
}
if ($busy) {
    Write-Host '          The report separates it out, but closing it gives a cleaner result.'
    Write-Host ''
}

Write-Host '    This script WILL change settings on this machine, repeatedly:'
Write-Host ("      - {0} times back to the original state (animations ON), Explorer restarted" -f $Repeats)
Write-Host ("      - {0} times to the module's applied state (animations OFF), Explorer restarted" -f $Repeats)
if ($LeaveOriginal) {
    Write-Host '      - it will finish with the ORIGINAL state restored (animations ON)'
} else {
    Write-Host '      - it will finish with the changes APPLIED (animations OFF)'
}
if (-not $NoWorkload) {
    Write-Host '    A window will open and drive itself. Do not click on it.'
}
Write-Host ("    Estimated time: about {0} minutes. Leave the machine alone." -f $estMin)
Write-Host ''

foreach ($b in $blockers) { Write-Host ("    !! {0}" -f $b) }
if ($blockers) { Write-Host '' }

if (-not $Force) {
    $answer = Read-Host '    Type YES to run the measurement'
    if ($answer -ne 'YES') {
        Write-Host ''
        Write-Host '    Nothing was changed and nothing was measured.'
        Write-Host ''
        return
    }
    Write-Host ''
}

# The original state must exist, or "before" cannot be reached.
$originalPath = Join-Path $here 'backups\original-state.json'
if (-not (Test-Path $originalPath)) {
    Write-Host '    There is no original-state.json in backups\.'
    Write-Host '    That file is written the first time Disable-VisualEffects.ps1 runs, and'
    Write-Host '    it is the only record of how this machine looked before the module'
    Write-Host '    touched it. Without it there is no "before" to measure.'
    Write-Host ''
    return
}

$pairs = @()
# Explorer needs time to finish starting after a restart, and the shell settles
# for a while afterwards. Measuring into that tail would charge the restart to
# the setting under test. Both sides wait the same amount, so the wait is fair
# even where it is not sufficient.
$settle = $SettleSeconds

for ($r = 1; $r -le $Repeats; $r++) {
    Write-Host ("    --- pair {0} of {1} " -f $r, $Repeats) -NoNewline
    Write-Host ('-' * 50)

    Write-Host '    [before]  restoring the original state, restarting Explorer ...'
    $rc = Set-VfxConditionOriginal
    if ($rc.exitCode -ne 0) { Write-Host ("      restore reported exit code {0}" -f $rc.exitCode) }
    Start-Sleep -Seconds $settle
    $before = Measure-VfxCondition -Name 'animations ON' -Sec $Seconds -SkipWorkload:$NoWorkload

    Write-Host '    [after]   applying the module, restarting Explorer ...'
    $ac = Set-VfxConditionApplied
    if ($ac.exitCode -ne 0) { Write-Host ("      apply reported exit code {0}" -f $ac.exitCode) }
    Start-Sleep -Seconds $settle
    $after = Measure-VfxCondition -Name 'animations OFF' -Sec $Seconds -SkipWorkload:$NoWorkload

    $pairs += [pscustomobject]@{ pair = $r; before = $before; after = $after }
    Write-Host ''
}

# --- leave the machine in a stated condition --------------------------------
if ($LeaveOriginal) {
    Write-Host '    restoring the original state as requested ...'
    [void](Set-VfxConditionOriginal)
    $finalState = 'ORIGINAL - animations are ON'
} else {
    $finalState = 'APPLIED - animations are OFF'
}
$endState = Get-VfxState

}   # end of the measuring branch

# ---------------------------------------------------------------------------
#  Report
# ---------------------------------------------------------------------------
function Get-VfxNoiseFloor {
    <#  Per-row spread between repeats of the SAME condition, taking whichever
        side moved more for each row.

        An earlier version returned one number - the worst spread across every
        watched process - and applied it to every row. On this machine that let
        the workload driver's own variability decide the bar for the compositor,
        and printed a repeated, same-signed 17-24 ms/s reduction in dwm.exe as
        "within noise". Each row is now judged against its own variability. #>
    param($Pairs, [string]$Phase)
    if ($Pairs.Count -lt 2) { return @{} }
    $b = Get-MeasNoiseFloors -Deltas @($Pairs | ForEach-Object { $_.before.$Phase } | Where-Object { $_ })
    $a = Get-MeasNoiseFloors -Deltas @($Pairs | ForEach-Object { $_.after.$Phase  } | Where-Object { $_ })
    Merge-MeasNoiseFloors -A $b -B $a
}

$lines = New-Object System.Collections.Generic.List[string]
function Emit([string]$s) { $lines.Add($s); Write-Host $s }

Emit ''
Emit ('  ' + ('=' * 74))
Emit '    RESULTS'
Emit ('  ' + ('=' * 74))

foreach ($phase in @('idle', 'workload')) {
    $usable = @($pairs | Where-Object { $_.before.$phase -and $_.after.$phase })
    if (-not $usable.Count) { continue }

    $noise = Get-VfxNoiseFloor -Pairs $usable -Phase $phase

    Emit ''
    Emit ("    {0} {1}" -f $phase.ToUpper(), $(if ($phase -eq 'idle') { '- the machine sitting still' } else { '- menus, lists, tooltips, minimise/restore, dragging' }))
    Emit ''
    if ($noise.Count -gt 0) {
        Emit ("    Noise floor from {0} repeats, per row, in the 'noise' column: how far that" -f $usable.Count)
        Emit '    figure moved between repeats when nothing changed. A change smaller than'
        Emit '    its own row noise is not a result and is marked so.'
    } else {
        Emit '    noise floor: UNKNOWN (only one repeat). Nothing below can be'
        Emit '    distinguished from background variation. Re-run with -Repeats 2 or more.'
    }
    Emit ''

    # Compare the last pair in full; repeats exist to size the noise, not to be averaged
    # into a single number that hides how much they differed.
    $last = $usable[-1]
    Compare-MeasDelta -Before $last.before.$phase -After $last.after.$phase -NoiseFloor $noise -Indent '    ' |
        ForEach-Object { Emit $_ }

    if ($usable.Count -gt 1) {
        Emit ''
        Emit '    every repeat, dwm CPU ms/s:'
        foreach ($p in $usable) {
            $b = $p.before.$phase; $a = $p.after.$phase
            $bs = $b.elapsedMs / 1000.0; $as = $a.elapsedMs / 1000.0
            Emit ("      pair {0}:  ON {1,7:N2}   OFF {2,7:N2}   change {3,7:N2}" -f `
                $p.pair, ($b.watched['dwm'].cpuMs / $bs), ($a.watched['dwm'].cpuMs / $as),
                (($a.watched['dwm'].cpuMs / $as) - ($b.watched['dwm'].cpuMs / $bs)))
        }
    }
}

# --- responsiveness ---------------------------------------------------------
$respPairs = @($pairs | Where-Object { $_.before.responsiveness -and $_.after.responsiveness })
if ($respPairs.Count) {
    Emit ''
    Emit '    RESPONSIVENESS - how long an animated open blocks the application'
    Emit '    (median of 25 opens; these calls are synchronous, so this is real waiting)'
    Emit ''
    Emit ("    {0,-26} {1,11} {2,11} {3,11}" -f 'operation', 'ON', 'OFF', 'change')
    Emit ("    {0}" -f ('-' * 62))
    foreach ($p in $respPairs) {
        Emit ("    pair {0}" -f $p.pair)
        Emit ("      {0,-24} {1,11:N2} {2,11:N2} {3,11:N2} ms" -f 'menu opens in', $p.before.responsiveness.menuOpenMs,  $p.after.responsiveness.menuOpenMs,  ($p.after.responsiveness.menuOpenMs  - $p.before.responsiveness.menuOpenMs))
        Emit ("      {0,-24} {1,11:N2} {2,11:N2} {3,11:N2} ms" -f 'drop-down opens in', $p.before.responsiveness.comboOpenMs, $p.after.responsiveness.comboOpenMs, ($p.after.responsiveness.comboOpenMs - $p.before.responsiveness.comboOpenMs))
    }
}

# --- the one number that needs no measurement -------------------------------
# Dot notation, not ['key']: this has to work both on a live hashtable and on
# the PSCustomObject that ConvertFrom-Json produces when re-analysing a saved run.
$delayBefore = $pairs[0].before.state.spi.MenuShowDelay
$delayAfter  = $pairs[-1].after.state.spi.MenuShowDelay
Emit ''
Emit '    MENU SHOW DELAY - not measured, read from the setting itself'
Emit ("      before {0} ms, after {1} ms" -f $delayBefore, $delayAfter)
Emit '      This is a pure wait with no work behind it. It is subtracted from every'
Emit '      hover-opened menu for as long as the machine is used.'

Emit ''
Emit ('  ' + ('-' * 74))
Emit ("    machine left in state: {0}" -f $finalState)
Emit ''

# ---------------------------------------------------------------------------
#  Persist
# ---------------------------------------------------------------------------
$stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$measDir = Join-Path $here 'measurements'
if (-not (Test-Path $measDir)) { New-Item -ItemType Directory -Path $measDir -Force | Out-Null }

# Re-analysis measures nothing, so it must not manufacture a new set of raw
# readings. It rewrites the write-up from the readings it was given, and that is
# all. A measurements folder that fills up with copies of one run is a folder
# nobody can audit.
$jsonPath = $FromJson
if (-not $FromJson) {
    $doc = [pscustomobject]@{
        schemaVersion = 1
        takenAt       = (Get-Date).ToString('o')
        seconds       = $Seconds
        repeats       = $Repeats
        noWorkload    = [bool]$NoWorkload
        environment   = $envInfo
        pairs         = $pairs
        finalState    = $finalState
        startState    = $startState
        endState      = $endState
    }
    $jsonPath = Join-Path $measDir ("vfx_measurement_{0}.json" -f $stamp)
    $doc | ConvertTo-Json -Depth 10 | Set-Content $jsonPath -Encoding UTF8
}

# RESULTS.md deliberately omits the computer name and the user name so that it
# can be published. The hardware description stays, because without it the
# numbers mean nothing.
$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Measured results - visual effects')
$md.Add('')
$md.Add('Generated by `Measure-VisualEffects.ps1`. Regenerate it rather than editing it.')
$md.Add('')
$md.Add('## The machine these numbers came from')
$md.Add('')
$md.Add('| | |')
$md.Add('|---|---|')
$md.Add("| Processor | $($envInfo.cpuName) - $($envInfo.cpuCores) cores, $($envInfo.cpuLogical) threads, $($envInfo.cpuMaxMHz) MHz base |")
foreach ($g in $envInfo.gpus) { $md.Add("| Graphics | $($g.name), driver $($g.driverVersion) |") }
$md.Add("| Memory | $('{0:N0}' -f $envInfo.ramTotalMB) MB |")
$md.Add("| Windows | build $($envInfo.osBuild) |")
$md.Add("| Power | $($envInfo.powerSource), scheme $($envInfo.powerScheme) |")
$md.Add("| Method | $Repeats repeats, $Seconds s per window |")
$md.Add('')
$md.Add('Your figures will differ. What should reproduce is the direction and the')
$md.Add('rough scale, not the digits.')
$md.Add('')
$md.Add('## Results')
$md.Add('')
$md.Add('```')
foreach ($l in $lines) { $md.Add($l) }
$md.Add('```')
$md.Add('')
$md.Add('## How to reproduce this')
$md.Add('')
$md.Add('```')
$md.Add("powershell -ExecutionPolicy Bypass -File .\Measure-VisualEffects.ps1 -Repeats $Repeats -Seconds $Seconds")
$md.Add('```')
$md.Add('')
$md.Add('The raw counter readings, including every process on the machine at the time,')
$md.Add('are in `measurements\` next to this file. That folder is excluded from version')
$md.Add('control because it records the machine name and the full process list.')
$md | Set-Content (Join-Path $here 'RESULTS.md') -Encoding UTF8

Write-Host ("    raw data : {0}" -f $jsonPath)
Write-Host ("    write-up : {0}" -f (Join-Path $here 'RESULTS.md'))
Write-Host ''
