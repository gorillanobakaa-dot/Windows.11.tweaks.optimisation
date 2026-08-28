<#
    _Common.ps1 - shared core for the 01-visual-effects module.

    Dot-sourced by Test-, Disable-, Restore- and Test-RoundTrip-VisualEffects so
    that all of them read and write the SAME settings through the SAME code. Add
    a setting here and every script picks it up at once; the backup and restore
    pair cannot drift apart.

    Nothing in this file executes on its own.

    ------------------------------------------------------------------------
    HARDENING NOTE (2026-08-26)

    This file was rewritten after two independent adversarial audits of the
    rollback path. Both returned GAPS_FOUND. The defects they demonstrated, and
    which are fixed here, were:

      * Save-VfxBackup reported success without checking the file was written,
        after which the apply script mutated all 20 settings believing a backup
        existed. The undo promise could be void while claiming to hold.
      * Restore always set the legacy master gate FIRST. That is the correct
        mirror only when restoring the gate to 1. Restoring to 0 caused the ten
        following writes to be swallowed while each was reported as restored.
      * Restore iterated the registry section of the BACKUP DATA rather than a
        known allow-list, so a corrupt or edited backup could write to arbitrary
        registry paths, and a malformed section produced phantom writes.
      * Registry writes in the undo path had no try/catch and incremented the
        success counter regardless, so a failed restore printed as a success.
      * Settings whose read failed (null) were still written by the apply path
        but skipped by the undo path - an asymmetry that loses a setting.
      * Registry value TYPE was never captured; everything was rewritten DWord.
      * There was no schema version, so an older or newer backup was replayed
        with silent losses.

    The bits of the legacy UserPreferencesMask this module does not enumerate
    still cannot be restored - that is a real limit, so the mask is captured as a
    raw blob and COMPARED, and any difference is reported rather than hidden.

    ------------------------------------------------------------------------
    THE CALLING-CONVENTION TRAP (why there are three P/Invoke signatures)

      SPI_GET*                     pvParam is a POINTER to the value
      SPI_SET* (UI-effects family) pvParam IS the value, cast to PVOID
      SPI_SETDRAGFULLWINDOWS,
      SPI_SETMENUSHOWDELAY         value travels in uiParam; pvParam NULL

    Getting this wrong yields a call that reports success and does nothing.

    The Win32 API *reference* is not part of the offline Microsoft corpus this
    project cites from, so these conventions are engineering observation,
    verifiable by running Test-VisualEffects.ps1 before and after - not a
    vendor-cited fact. What IS documented is that the client-area animation flag
    turns UI animations on or off, and that translucency is GPU-expensive.
#>

# Deliberately NOT Set-StrictMode: restore paths read JSON-deserialised objects
# where a missing property must degrade gracefully. A rollback that throws on an
# unexpected field is worse than useless.

$script:VfxSchemaVersion = 2

if (-not ('VfxNative.User32' -as [type])) {
Add-Type -Namespace VfxNative -Name User32 -MemberDefinition @'
    [DllImport("user32.dll", SetLastError=true, EntryPoint="SystemParametersInfoW")]
    public static extern bool SpiGet(uint uiAction, uint uiParam, ref int pvParam, uint fWinIni);

    [DllImport("user32.dll", SetLastError=true, EntryPoint="SystemParametersInfoW")]
    public static extern bool SpiSetPv(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);

    [DllImport("user32.dll", SetLastError=true, EntryPoint="SystemParametersInfoW")]
    public static extern bool SpiSetUi(uint uiAction, uint uiParam, IntPtr pvParam, uint fWinIni);
'@
}

# SPIF_UPDATEINIFILE | SPIF_SENDCHANGE - persist to the user profile AND
# broadcast WM_SETTINGCHANGE so running apps re-read immediately.
$script:SPIF = 0x1 -bor 0x2

# Friendly name -> @(GET, SET, layer, plain-English description)
$script:VfxEffects = [ordered]@{
    'Menu animation'            = @(0x1002, 0x1003, 'Legacy', 'menus slide or fade open')
    'Combo box animation'       = @(0x1004, 0x1005, 'Legacy', 'drop-down lists animate')
    'List box smooth scrolling' = @(0x1006, 0x1007, 'Legacy', 'lists glide instead of jumping')
    'Gradient window captions'  = @(0x1008, 0x1009, 'Legacy', 'title bars painted as a colour gradient')
    'Menu fade'                 = @(0x1012, 0x1013, 'Legacy', 'menus fade out when closing')
    'Selection fade'            = @(0x1014, 0x1015, 'Legacy', 'menu selections fade after clicking')
    'Tooltip animation'         = @(0x1016, 0x1017, 'Legacy', 'tooltips slide into view')
    'Tooltip fade'              = @(0x1018, 0x1019, 'Legacy', 'tooltips fade in and out')
    'Cursor shadow'             = @(0x101A, 0x101B, 'Legacy', 'the mouse pointer casts a shadow')
    'Drop shadow (windows)'     = @(0x1024, 0x1025, 'Legacy', 'windows cast a shadow on what is behind them')
    'Client area animation'     = @(0x1042, 0x1043, 'Modern', 'ALL animations inside modern apps, and inside web-based apps via prefers-reduced-motion')
    'UI effects (master)'       = @(0x103E, 0x103F, 'Legacy', 'master gate for the legacy effect family')
}
$script:VfxMasterName = 'UI effects (master)'

$script:SPI_GETDRAGFULLWINDOWS = 0x0026
$script:SPI_SETDRAGFULLWINDOWS = 0x0025
$script:SPI_GETMENUSHOWDELAY   = 0x006A
$script:SPI_SETMENUSHOWDELAY   = 0x006B

# The ONLY registry values this module is permitted to read or write. The restore
# path validates every entry in a backup against this list, so an edited or
# corrupt backup cannot direct writes elsewhere.
$script:VfxRegistry = @(
    @{ Key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Name='EnableTransparency'; Layer='Modern'; Target=0; Desc='frosted-glass translucency (acrylic/Mica) - the most GPU-expensive item here' }
    @{ Key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name='TaskbarAnimations';  Layer='Shell';  Target=0; Desc='taskbar buttons animate' }
    @{ Key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name='ListviewAlphaSelect';Layer='Shell';  Target=0; Desc='translucent selection rectangle in file lists' }
    @{ Key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';  Name='ListviewShadow';     Layer='Shell';  Target=0; Desc='drop shadows under desktop icon labels' }
    @{ Key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name='VisualFXSetting';Layer='Shell';  Target=3; Desc='makes the Performance Options dialog read "Custom" so it agrees with these settings' }
    @{ Key='HKCU:\Software\Microsoft\Windows\DWM';                               Name='EnableAeroPeek';     Layer='DWM';    Target=0; Desc='desktop preview when hovering the corner of the taskbar' }
)

function Get-VfxRegistryRule {
    param([string]$Key, [string]$Name)
    foreach ($r in $script:VfxRegistry) {
        if ($r.Key -eq $Key -and $r.Name -eq $Name) { return $r }
    }
    return $null
}

# ------------------------------------------------------------------ reads ----

function Get-VfxSpi {
    param([uint32]$Code)
    $v = 0
    if ([VfxNative.User32]::SpiGet($Code, 0, [ref]$v, 0)) { return $v }
    return $null      # null means UNREADABLE, which is not the same as 0
}

function Get-VfxRegEntry {
    param([string]$Key, [string]$Name)
    $out = @{ value = $null; kind = $null }
    try {
        $item = Get-Item -Path $Key -ErrorAction Stop
        if ($item.GetValueNames() -contains $Name) {
            $out.value = $item.GetValue($Name)
            $out.kind  = "$($item.GetValueKind($Name))"
        }
    } catch { }
    return $out
}

function Get-VfxUserPreferencesMask {
    try {
        $b = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'UserPreferencesMask' -ErrorAction Stop).UserPreferencesMask
        if ($b) { return (($b | ForEach-Object { $_.ToString('X2') }) -join ' ') }
    } catch { }
    return $null
}

<#  Complete current state of everything this module touches. This is what a
    backup file contains. #>
function Get-VfxState {
    $spi = [ordered]@{}
    foreach ($name in $script:VfxEffects.Keys) { $spi[$name] = Get-VfxSpi $script:VfxEffects[$name][0] }
    $spi['DragFullWindows'] = Get-VfxSpi $script:SPI_GETDRAGFULLWINDOWS
    $spi['MenuShowDelay']   = Get-VfxSpi $script:SPI_GETMENUSHOWDELAY

    $reg = [ordered]@{}
    foreach ($r in $script:VfxRegistry) {
        $e = Get-VfxRegEntry $r.Key $r.Name
        $reg["$($r.Key)|$($r.Name)"] = [ordered]@{ value = $e.value; kind = $e.kind }
    }

    $modern = [ordered]@{ AnimationsEnabled = $null; AdvancedEffectsEnabled = $null }
    try {
        [void][Windows.UI.ViewManagement.UISettings, Windows.UI.ViewManagement, ContentType=WindowsRuntime]
        $ui = New-Object Windows.UI.ViewManagement.UISettings
        $modern.AnimationsEnabled      = [bool]$ui.AnimationsEnabled
        $modern.AdvancedEffectsEnabled = [bool]$ui.AdvancedEffectsEnabled
    } catch { }

    [ordered]@{
        schemaVersion = $script:VfxSchemaVersion
        module        = '01-visual-effects'
        capturedUtc   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        host          = $env:COMPUTERNAME
        user          = $env:USERNAME
        osBuild       = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).CurrentBuildNumber
        spi           = $spi
        registry      = $reg
        uiSettings    = $modern
        # Captured for DETECTION only. The legacy effects live packed inside this
        # 8-byte mask; this module enumerates ten of its bits and cannot restore
        # the others. Comparing it after a restore is how we notice, and say so,
        # rather than quietly losing something.
        userPreferencesMask = Get-VfxUserPreferencesMask
    }
}

# ----------------------------------------------------------------- backup ----

function ConvertTo-VfxSafeTag {
    param([string]$Tag)
    if (-not $Tag) { return '' }
    # A colon would create an NTFS alternate data stream: the file appears to
    # write, is 0 bytes, and is invisible to the undo path. Strip anything that
    # is not plainly safe in a file name.
    $clean = ($Tag -replace '[^A-Za-z0-9\-_.]', '-').Trim('-')
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    return $clean
}

<#  Write a backup and PROVE it was written.

    Returns the path on success, or $null on failure. Callers MUST treat $null as
    fatal and refuse to make changes: a mutation without a backup is precisely
    the situation this module exists to avoid.

    The first backup written into a folder is also preserved as
    original-state.json and never overwritten, so repeated runs can never destroy
    the route back to the pristine configuration. #>
function Save-VfxBackup {
    <#
    .PARAMETER RecordAsOriginal
        Permit this backup to establish original-state.json, if that file does
        not exist yet. ONLY the apply path may pass this.

        Without the switch, the restore script's own pre-restore snapshot would
        create original-state.json when none existed - recording the CURRENT
        state as "original". Because that file is deliberately never overwritten,
        a machine that had already been modified would have "before any of this"
        permanently defined as "after all of this", and -Original would restore
        to the applied state forever with nothing to reveal it.

        This was documented as a known consequence before it was fixed. Documenting
        a defect is not the same as fixing it, and this one was cheap to fix.

        The rule: original-state.json may only be written by a script that is
        about to change something, from the reading it took beforehand.
    #>
    param([string]$BackupDir, [string]$Tag = '', [switch]$RecordAsOriginal)

    # -ErrorAction Stop on Test-Path too, not only New-Item: Test-Path throws a
    # non-terminating error on a path with illegal characters, which under
    # $ErrorActionPreference = 'Continue' prints a raw .NET argument exception in
    # red and then carries on past the catch.
    try {
        if (-not (Test-Path $BackupDir -ErrorAction Stop)) {
            New-Item -ItemType Directory -Path $BackupDir -Force -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-Warning "Could not use the backup folder '$BackupDir': $($_.Exception.Message)"
        return $null
    }

    $state = Get-VfxState
    $json  = $state | ConvertTo-Json -Depth 8

    $safeTag = ConvertTo-VfxSafeTag $Tag
    $stamp   = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $base    = if ($safeTag) { "state_$stamp`_$safeTag" } else { "state_$stamp" }
    $path    = Join-Path $BackupDir "$base.json"
    # One-second stamp resolution: two runs in the same second would otherwise
    # silently overwrite one another.
    $n = 1
    while (Test-Path $path) { $path = Join-Path $BackupDir ("{0}_{1}.json" -f $base, $n); $n++ }

    try {
        Set-Content -Path $path -Value $json -Encoding UTF8 -ErrorAction Stop
    } catch {
        Write-Warning "Backup write FAILED for '$path': $($_.Exception.Message)"
        return $null
    }

    # Prove it: the file must exist, be non-trivial, and parse back with the
    # fields a restore depends on.
    try {
        if (-not (Test-Path $path)) { throw 'file does not exist after writing' }
        $len = (Get-Item $path).Length
        if ($len -lt 200) { throw "file is only $len bytes" }
        $check = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $check.spi -or $null -eq $check.registry) { throw 'parsed file has no spi/registry section' }
    } catch {
        Write-Warning "Backup verification FAILED for '$path': $($_.Exception.Message)"
        return $null
    }

    # Only the apply path may establish the pristine record. See -RecordAsOriginal.
    if ($RecordAsOriginal) {
        $original = Join-Path $BackupDir 'original-state.json'
        if (-not (Test-Path $original)) {
            try {
                Set-Content -Path $original -Value $json -Encoding UTF8 -ErrorAction Stop
                Write-Host "  pristine state preserved : $original"
                Write-Host "  (written once, never overwritten)"
            } catch {
                Write-Warning "Could not write original-state.json: $($_.Exception.Message)"
            }
        }
    }
    return $path
}

function Get-VfxBackups {
    param([string]$BackupDir)
    if (-not (Test-Path $BackupDir)) { return @() }
    Get-ChildItem $BackupDir -Filter '*.json' -File | Sort-Object LastWriteTime -Descending
}

<#  Backups eligible for the DEFAULT undo.

    Excludes the snapshots the restore path itself writes. Without this, running
    restore twice selects the snapshot taken just before the first restore -
    which holds the ALREADY-DISABLED state - and cheerfully re-applies the
    tweaks. An auditor demonstrated exactly that. #>
function Get-VfxRestoreCandidates {
    param([string]$BackupDir)
    Get-VfxBackups -BackupDir $BackupDir |
        Where-Object { $_.Name -like 'state_*' -and $_.Name -notlike '*pre-restore*' }
}

function Test-VfxStateShape {
    param([object]$State)
    $problems = @()
    if ($null -eq $State)          { return @('backup is empty or unreadable') }
    if ($null -eq $State.spi)      { $problems += 'no spi section' }
    if ($null -eq $State.registry) { $problems += 'no registry section' }
    elseif ($State.registry -isnot [System.Management.Automation.PSCustomObject]) {
        $problems += 'registry section is not an object'
    }
    if ($null -eq $State.schemaVersion) {
        $problems += 'no schemaVersion (written by an older build; restore will still proceed)'
    } elseif (-not ($State.schemaVersion -as [int])) {
        # Module 04 audit finding 12, present here too: [int] on a non-numeric
        # value throws. -as returns $null instead of throwing.
        $problems += "schemaVersion '$($State.schemaVersion)' is not a number - not a state file this module wrote"
    } elseif ([int]$State.schemaVersion -gt $script:VfxSchemaVersion) {
        $problems += "schemaVersion $($State.schemaVersion) is newer than this script understands ($script:VfxSchemaVersion); unknown settings will NOT be restored"
    }
    return $problems
}

# ---------------------------------------------------------------- restore ----

function Set-VfxSpiValue { param([uint32]$Code, [int]$Value)
    [VfxNative.User32]::SpiSetPv($Code, 0, [IntPtr]$Value, $script:SPIF) }

function Set-VfxSpiUiParam { param([uint32]$Code, [int]$Value)
    [VfxNative.User32]::SpiSetUi($Code, [uint32]$Value, [IntPtr]::Zero, $script:SPIF) }

function ConvertTo-VfxInt {
    <# Returns $null rather than guessing. A JSON non-integer would otherwise be
       silently rounded by [int], restoring a value that was never captured. #>
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [bool]) { return [int]$Value }
    try {
        $d = [decimal]$Value
        if ($d -ne [decimal][int64]$d) { return $null }   # not a whole number
        if ($d -gt [int]::MaxValue -or $d -lt [int]::MinValue) { return $null }
        return [int]$d
    } catch { return $null }
}

<#  Put a captured state back.

    Returns a result object: Restored / Skipped / Failed counts plus details.
    Never reports a write as successful without checking it.

    Ordering: the legacy master gate is a gate. Writes to the individual legacy
    effects are ignored while it is off. So we OPEN the gate, restore every
    individual effect, then set the gate to its captured value LAST. That is
    correct whichever value the gate is being restored to - the previous
    implementation set it first unconditionally, which silently discarded ten
    writes whenever the captured gate was 0. #>
function Restore-VfxState {
    param([object]$State, [switch]$WhatIfMode)

    $res = [ordered]@{
        Restored = 0; Skipped = 0; Failed = 0
        SkippedDetail = @(); FailedDetail = @(); Ignored = @()
    }

    # ---- 1. open the gate so individual legacy writes are honoured ----------
    $masterCaptured = $null
    if ($State.spi) { $masterCaptured = ConvertTo-VfxInt $State.spi.$($script:VfxMasterName) }
    if (-not $WhatIfMode) {
        [void](Set-VfxSpiValue $script:VfxEffects[$script:VfxMasterName][1] 1)
    }

    # ---- 2. individual SPI effects -----------------------------------------
    foreach ($name in $script:VfxEffects.Keys) {
        if ($name -eq $script:VfxMasterName) { continue }
        $raw = if ($State.spi) { $State.spi.$name } else { $null }
        $val = ConvertTo-VfxInt $raw
        if ($null -eq $val) {
            $res.Skipped++
            $res.SkippedDetail += "$name (not usable in backup: '$raw')"
            Write-Host ("  {0,-28} -> SKIPPED (was not readable when the backup was taken)" -f $name)
            continue
        }
        if ($WhatIfMode) {
            Write-Host ("  {0,-28} -> {1}" -f $name, [bool]$val); $res.Restored++
        } else {
            if (Set-VfxSpiValue $script:VfxEffects[$name][1] $val) {
                Write-Host ("  {0,-28} -> {1}" -f $name, [bool]$val); $res.Restored++
            } else {
                $res.Failed++; $res.FailedDetail += "$name (SystemParametersInfo returned failure)"
                Write-Host ("  {0,-28} -> FAILED" -f $name)
            }
        }
    }

    # ---- 3. uiParam-family settings ----------------------------------------
    foreach ($pair in @(
        @{ Name='Drag full windows'; Key='DragFullWindows'; Code=$script:SPI_SETDRAGFULLWINDOWS; Bool=$true },
        @{ Name='Menu show delay';   Key='MenuShowDelay';   Code=$script:SPI_SETMENUSHOWDELAY;   Bool=$false })) {
        $raw = if ($State.spi) { $State.spi.$($pair.Key) } else { $null }
        $val = ConvertTo-VfxInt $raw
        if ($null -eq $val) {
            $res.Skipped++; $res.SkippedDetail += "$($pair.Name) (not usable in backup: '$raw')"
            Write-Host ("  {0,-28} -> SKIPPED (not readable when the backup was taken)" -f $pair.Name)
            continue
        }
        $shown = if ($pair.Bool) { [bool]$val } else { "$val ms" }
        if ($WhatIfMode) {
            Write-Host ("  {0,-28} -> {1}" -f $pair.Name, $shown); $res.Restored++
        } else {
            if (Set-VfxSpiUiParam $pair.Code $val) {
                Write-Host ("  {0,-28} -> {1}" -f $pair.Name, $shown); $res.Restored++
            } else {
                $res.Failed++; $res.FailedDetail += $pair.Name
                Write-Host ("  {0,-28} -> FAILED" -f $pair.Name)
            }
        }
    }

    # ---- 4. registry values, STRICTLY against the allow-list ---------------
    if ($State.registry -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $State.registry.PSObject.Properties) {
            $key, $name = $p.Name -split '\|', 2
            $rule = Get-VfxRegistryRule -Key $key -Name $name
            if (-not $rule) {
                # A backup naming a path this module does not own is not
                # restored. Backups are plain JSON in a writable folder; without
                # this check an edited file could direct writes anywhere.
                $res.Ignored += $p.Name
                Write-Host ("  IGNORED (not a setting this module manages): {0}" -f $p.Name)
                continue
            }

            $entry = $p.Value
            $val  = $null; $kind = 'DWord'
            if ($entry -is [System.Management.Automation.PSCustomObject]) {
                $val  = $entry.value
                if ($entry.kind) { $kind = "$($entry.kind)" }
            } else {
                $val = $entry          # schema v1 backup: bare value
            }

            $isUnset = ($null -eq $val)
            if ($WhatIfMode) {
                if ($isUnset) { Write-Host ("  {0,-28} -> would be removed (was not set originally)" -f $name) }
                else          { Write-Host ("  {0,-28} -> {1}" -f $name, $val) }
                $res.Restored++
                continue
            }

            try {
                if ($isUnset) {
                    if ((Test-Path $key) -and ((Get-Item $key).GetValueNames() -contains $name)) {
                        Remove-ItemProperty -Path $key -Name $name -ErrorAction Stop
                        Write-Host ("  {0,-28} -> removed (was not set originally)" -f $name)
                    } else {
                        Write-Host ("  {0,-28} -> already absent" -f $name)
                    }
                } else {
                    $iv = ConvertTo-VfxInt $val
                    if ($null -eq $iv -and $kind -in @('DWord','QWord')) {
                        throw "captured value '$val' is not a whole number"
                    }
                    if (-not (Test-Path $key)) { New-Item -Path $key -Force -ErrorAction Stop | Out-Null }
                    $writeVal = if ($null -ne $iv) { $iv } else { $val }
                    New-ItemProperty -Path $key -Name $name -Value $writeVal -PropertyType $kind -Force -ErrorAction Stop | Out-Null
                    # verify rather than assume
                    $back = (Get-Item $key).GetValue($name)
                    if ("$back" -ne "$writeVal") { throw "wrote '$writeVal' but read back '$back'" }
                    Write-Host ("  {0,-28} -> {1}" -f $name, $writeVal)
                }
                $res.Restored++
            } catch {
                $res.Failed++
                $res.FailedDetail += "$name ($($_.Exception.Message))"
                Write-Host ("  {0,-28} -> FAILED: {1}" -f $name, $_.Exception.Message)
            }
        }
    } else {
        Write-Warning 'The backup has no usable registry section; no registry values were restored.'
    }

    # ---- 5. the gate LAST, now that the individual values are in place ------
    if ($null -eq $masterCaptured) {
        $res.Skipped++
        $res.SkippedDetail += "$($script:VfxMasterName) (not usable in backup)"
        Write-Host ("  {0,-28} -> SKIPPED (left ON, so the effects above take effect)" -f $script:VfxMasterName)
    } else {
        if ($WhatIfMode) {
            Write-Host ("  {0,-28} -> {1}  (set last, on purpose)" -f $script:VfxMasterName, [bool]$masterCaptured)
            $res.Restored++
        } elseif (Set-VfxSpiValue $script:VfxEffects[$script:VfxMasterName][1] $masterCaptured) {
            Write-Host ("  {0,-28} -> {1}  (set last, on purpose)" -f $script:VfxMasterName, [bool]$masterCaptured)
            $res.Restored++
        } else {
            $res.Failed++; $res.FailedDetail += $script:VfxMasterName
            Write-Host ("  {0,-28} -> FAILED" -f $script:VfxMasterName)
        }
    }

    return [pscustomobject]$res
}

<#  Compare the shared legacy preference mask against what a backup captured.
    This module manages ten of its bits and cannot restore the rest, so the
    honest thing is to notice and report a difference, not to hide it. #>
function Test-VfxMaskUnchanged {
    param([object]$State)
    $captured = $State.userPreferencesMask
    if (-not $captured) { return $null }        # older backup: nothing to compare
    $now = Get-VfxUserPreferencesMask
    return [pscustomobject]@{
        Captured = $captured
        Current  = $now
        Same     = ($captured -eq $now)
    }
}
