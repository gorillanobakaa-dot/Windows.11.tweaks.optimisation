<#
.SYNOPSIS
    Show what every animation and visual-effect setting on this machine is set
    to right now. Changes nothing.

.DESCRIPTION
    Run this before and after the other two scripts to see exactly what moved.
    It reads each setting through the same interface Windows and applications
    use, rather than guessing from the registry, because on current builds the
    modern animation flag has no standalone registry value - it is packed into
    an undocumented block of bytes. Asking the API is the only honest read.

    Safe to run at any time. Requires no administrator rights. Makes no changes.

.PARAMETER Json
    Also write a timestamped JSON snapshot into .\backups\ for later comparison.
    (A snapshot is not a backup of intent - it is just a record. The disable
    script writes the real backups.)

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-VisualEffects.ps1
    Show the current state of all four layers.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-VisualEffects.ps1 -Json
    Show it and also save a JSON snapshot you can diff against later.
#>

[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$state = Get-VfxState

Write-Host ''
Write-Host '  Visual effects - current state'
Write-Host ("  {0}  |  Windows build {1}  |  user {2}" -f $state.host, $state.osBuild, $state.user)
Write-Host ('  ' + ('-' * 72))

Write-Host ''
Write-Host '  LAYER 1+2  effects read through SystemParametersInfo'
foreach ($name in $script:VfxEffects.Keys) {
    $v = $state.spi[$name]
    $shown = if ($null -eq $v) { 'unreadable' } elseif ($v) { 'ON ' } else { 'off' }
    $flag  = if ($v) { '  <- costs cycles' } else { '' }
    Write-Host ("    {0,-28} {1}{2}" -f $name, $shown, $flag)
}
$dfw = $state.spi['DragFullWindows']
Write-Host ("    {0,-28} {1}{2}" -f 'Drag full windows', $(if ($dfw) {'ON '} else {'off'}), $(if ($dfw) {'  <- costs cycles'} else {''}))
Write-Host ("    {0,-28} {1} ms" -f 'Menu show delay', $state.spi['MenuShowDelay'])

Write-Host ''
Write-Host '  LAYER 2  what modern apps actually see (WinRT UISettings - authoritative)'
$a = $state.uiSettings.AnimationsEnabled
$b = $state.uiSettings.AdvancedEffectsEnabled
Write-Host ("    {0,-28} {1}" -f 'AnimationsEnabled', $(if ($null -eq $a) {'unavailable'} elseif ($a) {'True   <- modern apps animate'} else {'False  (already off)'}))
Write-Host ("    {0,-28} {1}" -f 'AdvancedEffectsEnabled', $(if ($null -eq $b) {'unavailable'} elseif ($b) {'True   <- frosted glass is being rendered'} else {'False  (already off)'}))

Write-Host ''
Write-Host '  LAYER 3+4  shell and compositor settings (registry)'
foreach ($r in $script:VfxRegistry) {
    $e = $state.registry["$($r.Key)|$($r.Name)"]
    $v = if ($e) { $e.value } else { $null }
    $shown = if ($null -eq $v) { '<not set>' } else { "$v" }
    Write-Host ("    {0,-28} {1,-10} {2}" -f $r.Name, $shown, $r.Desc)
}

# --- what is left to do ------------------------------------------------------
$onLegacy = @()
foreach ($name in $script:VfxEffects.Keys) {
    if ($state.spi[$name]) { $onLegacy += $name }
}
if ($state.spi['DragFullWindows']) { $onLegacy += 'Drag full windows' }

$onShell = @()
foreach ($r in $script:VfxRegistry) {
    $e = $state.registry["$($r.Key)|$($r.Name)"]
    $v = if ($e) { $e.value } else { $null }
    if ($null -ne $v -and $v -ne $r.Target) { $onShell += $r.Name }
    if ($null -eq $v -and $r.Target -eq 0) { $onShell += "$($r.Name) (unset = on)" }
}

Write-Host ''
Write-Host ('  ' + ('-' * 72))
Write-Host ("    effects still on   : {0}" -f $(if ($onLegacy.Count) { $onLegacy -join ', ' } else { 'none' }))
Write-Host ("    shell/DWM to change: {0}" -f $(if ($onShell.Count) { $onShell -join ', ' } else { 'none' }))
Write-Host ("    menu delay         : {0} ms" -f $state.spi['MenuShowDelay'])

$dwm = Get-Process dwm -ErrorAction SilentlyContinue
if ($dwm) { Write-Host ("    dwm.exe            : {0:N0} MB resident" -f ($dwm.WorkingSet64/1MB)) }
$wv = Get-Process msedgewebview2 -ErrorAction SilentlyContinue
if ($wv) { Write-Host ("    web-based apps     : {0} processes, {1:N0} MB (each animates its own interface)" -f $wv.Count, (($wv | Measure-Object WorkingSet64 -Sum).Sum/1MB)) }

if ($Json) {
    $dir = Join-Path $here 'backups'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $p = Join-Path $dir ("snapshot_{0}.json" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    $state | ConvertTo-Json -Depth 6 | Set-Content $p -Encoding UTF8
    Write-Host ''
    Write-Host "    snapshot written   : $p"
}
Write-Host ''
