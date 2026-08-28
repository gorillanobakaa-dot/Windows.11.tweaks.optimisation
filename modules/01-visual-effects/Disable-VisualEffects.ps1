<#
.SYNOPSIS
    Turn off UI animations, fades, shadows and frosted-glass translucency across
    all four layers Windows spreads them over. Applies immediately. Reversible.

.DESCRIPTION
    Windows' own "Adjust for best performance" button reaches only the oldest of
    four separate layers. This script addresses each layer with the mechanism
    that layer actually obeys:

      Legacy  the classic USER32 effects  (menus, tooltips, window shadows)
      Modern  animations inside modern apps AND inside web-based apps, because
              the same flag surfaces to browsers as prefers-reduced-motion
      Shell   taskbar animation, translucent selection, icon label shadows
      DWM     Aero Peek desktop preview

    Translucency is the expensive one: it is a blur recalculated every frame for
    every translucent surface. Microsoft's own documentation states that
    rendering it "is GPU-intensive, which can increase device power consumption
    and shorten battery life".

    SAFETY
      * Before changing anything, the complete current state of all 20 settings
        is written to .\backups\state_<timestamp>.json.
      * The FIRST run also writes .\backups\original-state.json, which is never
        overwritten. Running this script repeatedly can therefore never destroy
        the route back to your pristine configuration.
      * Undo at any time with Restore-VisualEffects.ps1 (no arguments needed).
      * -WhatIf shows exactly what would change and changes nothing.

    This script is per-user. It needs no administrator rights and asks for none;
    it touches only your own settings, not the machine's.

.PARAMETER Layers
    Which layers to act on: Legacy, Modern, Shell, DWM, or All. Default All.
    Example: -Layers Modern,Shell leaves the classic effects alone.

.PARAMETER KeepMenuDelay
    Leave the menu-open delay as it is. By default it is set to 0 ms, which
    removes a 400 ms wait before every menu appears on this machine.

.PARAMETER RestartExplorer
    Restart the desktop shell so the taskbar and file-list changes take effect
    at once. This closes any open File Explorer windows. Without it, those
    particular items apply at your next sign-in.

.PARAMETER Tag
    A label folded into the backup filename, e.g. -Tag before-tuning.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -WhatIf
    Preview every change without touching anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1
    Apply everything, backing up first.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -Layers Modern -KeepMenuDelay
    Turn off only the modern-app animations and frosted glass, leave classic
    effects and the menu delay untouched.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Disable-VisualEffects.ps1 -RestartExplorer
    Apply everything and restart the desktop shell so it all takes effect now.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Legacy','Modern','Shell','DWM','All')]
    [string[]]$Layers = @('All'),
    [switch]$KeepMenuDelay,
    [switch]$RestartExplorer,
    [string]$Tag = ''
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')
$backupDir = Join-Path $here 'backups'

$want = if ($Layers -contains 'All') { @('Legacy','Modern','Shell','DWM') } else { $Layers }

Write-Host ''
Write-Host '  Disable visual effects'
Write-Host ("  layers: {0}" -f ($want -join ', '))
Write-Host ('  ' + ('-' * 72))

# ---------------------------------------------------------------- 1. backup --
# A backup that silently failed to write is the one thing that must never
# happen here: it voids the undo promise while appearing to keep it. So the
# write is verified, and a failure ABORTS before anything is changed.
$before = Get-VfxState
if ($PSCmdlet.ShouldProcess($backupDir, 'write a full backup of all 20 settings')) {
    # -RecordAsOriginal: this is the apply path, reading the machine before it
    # changes anything, so this is the only reading entitled to define "original".
    $backupPath = Save-VfxBackup -BackupDir $backupDir -Tag $Tag -RecordAsOriginal
    if (-not $backupPath) {
        Write-Host ''
        Write-Host '  ABORTED - the backup could not be written and verified.'
        Write-Host '  Nothing has been changed. Without a good backup there would be'
        Write-Host '  no reliable way to undo these changes, so the script stops here.'
        Write-Host ''
        Write-Host "  Check that this folder is writable and has free space:"
        Write-Host "    $backupDir"
        Write-Host ''
        return
    }
    Write-Host "  backup written & verified : $backupPath"
} else {
    Write-Host "  backup would be written to: $backupDir"
}
Write-Host ''

# ------------------------------------------------------- 2. SPI-based effects --
$changed = 0; $already = 0; $failed = 0; $skipped = 0; $planned = 0
$master = $script:VfxMasterName

Write-Host '  effects:'
foreach ($name in $script:VfxEffects.Keys) {
    if ($name -eq $master) { continue }              # handled last
    $layer = $script:VfxEffects[$name][2]
    if ($want -notcontains $layer) { continue }
    $cur = $before.spi[$name]
    # Never write a setting we could not read. Doing so would change something
    # the backup has no usable record of, which the undo path could not put back.
    if ($null -eq $cur) {
        Write-Host ("    SKIPPED      {0,-28} (could not be read, so it is left alone)" -f $name)
        $skipped++; continue
    }
    if ($cur -eq 0) { Write-Host ("    already off  {0}" -f $name); $already++; continue }
    $planned++
    if ($PSCmdlet.ShouldProcess($name, 'disable')) {
        if (Set-VfxSpiValue $script:VfxEffects[$name][1] 0) {
            Write-Host ("    DISABLED     {0,-28} ({1})" -f $name, $script:VfxEffects[$name][3])
            $changed++
        } else {
            Write-Host ("    FAILED       {0}" -f $name); $failed++
        }
    }
}

if ($want -contains 'Legacy') {
    $dfw = $before.spi['DragFullWindows']
    if ($null -eq $dfw) {
        Write-Host '    SKIPPED      Drag full windows            (could not be read)'; $skipped++
    } elseif ($dfw -ne 0) {
        $planned++
        if ($PSCmdlet.ShouldProcess('Drag full windows', 'disable')) {
            if (Set-VfxSpiUiParam $script:SPI_SETDRAGFULLWINDOWS 0) {
                Write-Host '    DISABLED     Drag full windows            (window contents redraw while you drag)'
                $changed++
            } else { Write-Host '    FAILED       Drag full windows'; $failed++ }
        }
    } else { Write-Host '    already off  Drag full windows'; $already++ }

    if (-not $KeepMenuDelay) {
        $delay = $before.spi['MenuShowDelay']
        if ($null -eq $delay) {
            Write-Host '    SKIPPED      Menu show delay              (could not be read)'; $skipped++
        } elseif ($delay -ne 0) {
            $planned++
            if ($PSCmdlet.ShouldProcess("MenuShowDelay ($delay ms)", 'set to 0 ms')) {
                if (Set-VfxSpiUiParam $script:SPI_SETMENUSHOWDELAY 0) {
                    Write-Host ("    SET          Menu show delay              {0} ms -> 0 ms" -f $delay)
                    $changed++
                } else { Write-Host '    FAILED       Menu show delay'; $failed++ }
            }
        } else { Write-Host '    already 0    Menu show delay'; $already++ }
    } else {
        Write-Host '    skipped      Menu show delay (-KeepMenuDelay)'
    }

    # master gate LAST: with it off, USER32 skips the whole legacy family
    $mcur = $before.spi[$master]
    if ($null -eq $mcur) {
        Write-Host "    SKIPPED      $master (could not be read)"; $skipped++
    } elseif ($mcur -ne 0) {
        $planned++
        if ($PSCmdlet.ShouldProcess($master, 'disable')) {
            if (Set-VfxSpiValue $script:VfxEffects[$master][1] 0) {
                Write-Host ("    DISABLED     {0,-28} ({1})" -f $master, 'master gate, set last on purpose')
                $changed++
            } else { Write-Host "    FAILED       $master"; $failed++ }
        }
    } else { Write-Host "    already off  $master"; $already++ }
}

# --------------------------------------------------------- 3. registry items --
Write-Host ''
Write-Host '  shell / compositor:'
foreach ($r in $script:VfxRegistry) {
    if ($want -notcontains $r.Layer) { continue }
    $entry = $before.registry["$($r.Key)|$($r.Name)"]
    $cur   = if ($entry) { $entry.value } else { $null }

    # The comparison is inside the try as well: a non-numeric existing value
    # would otherwise throw outside this script's own error handling.
    try {
        if ($null -ne $cur -and [int]$cur -eq [int]$r.Target) {
            Write-Host ("    already set  {0,-28} = {1}" -f $r.Name, $r.Target); $already++; continue
        }
    } catch {
        Write-Host ("    SKIPPED      {0,-28} (existing value '{1}' is not a number)" -f $r.Name, $cur)
        $skipped++; continue
    }

    $planned++
    if ($PSCmdlet.ShouldProcess("$($r.Name)", "set to $($r.Target)")) {
        try {
            if (-not (Test-Path $r.Key)) { New-Item -Path $r.Key -Force -ErrorAction Stop | Out-Null }
            New-ItemProperty -Path $r.Key -Name $r.Name -Value $r.Target -PropertyType DWord -Force -ErrorAction Stop | Out-Null
            # verify rather than assume the write landed
            $back = (Get-Item $r.Key).GetValue($r.Name)
            if ("$back" -ne "$($r.Target)") { throw "wrote $($r.Target) but read back '$back'" }
            Write-Host ("    SET          {0,-28} = {1}  ({2})" -f $r.Name, $r.Target, $r.Desc)
            $changed++
        } catch {
            Write-Host ("    FAILED       {0}: {1}" -f $r.Name, $_.Exception.Message); $failed++
        }
    }
}

# ------------------------------------------------------------ 4. shell restart --
if ($RestartExplorer) {
    if ($PSCmdlet.ShouldProcess('explorer.exe', 'restart so shell changes apply now')) {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
        Write-Host ''
        Write-Host '  desktop shell restarted'
    }
}

# ---------------------------------------------------------------- 5. verify --
if (-not $WhatIfPreference) {
    Write-Host ''
    Write-Host '  verification (re-read from the API, not from what we just wrote):'
    $after = Get-VfxState
    $stillOn = @()
    foreach ($name in $script:VfxEffects.Keys) {
        if ($want -notcontains $script:VfxEffects[$name][2]) { continue }
        if ($after.spi[$name]) { $stillOn += $name }
    }
    if ($want -contains 'Legacy' -and $after.spi['DragFullWindows']) { $stillOn += 'Drag full windows' }
    if ($stillOn.Count) {
        Write-Host ("    STILL ON: {0}" -f ($stillOn -join ', '))
    } else {
        Write-Host '    every targeted effect reads back as off'
    }
    Write-Host ("    menu show delay          : {0} ms" -f $after.spi['MenuShowDelay'])
    if ($null -ne $after.uiSettings.AnimationsEnabled) {
        Write-Host ("    UISettings.Animations    : {0}" -f $after.uiSettings.AnimationsEnabled)
        Write-Host ("    UISettings.AdvancedFx    : {0}" -f $after.uiSettings.AdvancedEffectsEnabled)
    }
}

Write-Host ''
Write-Host ('  ' + ('-' * 72))
if ($WhatIfPreference) {
    # Under -WhatIf the counters never move, because nothing runs. Reporting
    # "changed: 0" here would read as "this would change nothing", which is the
    # opposite of what the preview above just listed.
    Write-Host ("  PREVIEW ONLY - nothing was changed.")
    Write-Host ("  would change: {0}   already as wanted: {1}   would skip: {2}" -f $planned, $already, $skipped)
} else {
    Write-Host ("  changed: {0}   already as wanted: {1}   skipped: {2}   failed: {3}" -f $changed, $already, $skipped, $failed)
    if ($failed -gt 0) {
        Write-Host '  Some settings did NOT apply. Re-run Test-VisualEffects.ps1 to see the current state.'
    }
}

# ------------------------------------------------- nothing-to-do, after the fact --
# MODULE-STANDARD section 16: a run that changed nothing must exit 4 and must
# NOT leave a backup behind. This module predates that rule and was the only
# one of the eight without it. The cost was not untidiness - it was a BROKEN
# UNDO:
#
#   click apply  -> backup A records the ORIGINAL state          (correct)
#   click again  -> backup B records the ALREADY-APPLIED state   (useless)
#   click undo   -> restores from the NEWEST backup, which is B  -> does nothing
#
# Two clicks of a button, and the undo silently stopped working. Found by
# clicking apply three times, exactly as a person would.
#
# The check is made AFTER the work rather than before it, deliberately: the
# plan is computed inline with the writes, so a pre-flight check would be a
# second copy of that logic and the two would drift. Judging by the actual
# result cannot drift from the actual result.
if (-not $WhatIfPreference -and $changed -eq 0 -and $failed -eq 0) {
    if ($backupPath -and (Test-Path -LiteralPath $backupPath)) {
        try {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction Stop
            Write-Host ''
            Write-Host '  Nothing to do - every setting was already as this module wants it.'
            Write-Host '  The backup just written has been REMOVED, because keeping it would'
            Write-Host '  overwrite your real undo point with a copy of the current state.'
        }
        catch {
            Write-Host ''
            Write-Host ("  Nothing to do, but the redundant backup could not be removed: {0}" -f $_.Exception.Message)
            Write-Host '  Use "UNDO back to the original" rather than "UNDO everything".'
        }
    }
    else {
        Write-Host ''
        Write-Host '  Nothing to do - every setting was already as this module wants it.'
    }
    Write-Host ''
    Write-Host '  Exit code 4: nothing to do.'
    Write-Host ''
    exit 4
}
if (-not $RestartExplorer -and -not $WhatIfPreference) {
    Write-Host '  taskbar and file-list items apply at your next sign-in,'
    Write-Host '  or immediately if you re-run with -RestartExplorer.'
}
Write-Host ''
Write-Host '  TO UNDO EVERYTHING:'
Write-Host '     powershell -ExecutionPolicy Bypass -File .\Restore-VisualEffects.ps1'
Write-Host ''
