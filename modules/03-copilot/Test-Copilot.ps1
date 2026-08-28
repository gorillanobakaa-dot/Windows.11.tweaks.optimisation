<#
.SYNOPSIS
    Show every form Copilot takes on this machine, and which of them can be
    undone if you remove them. Changes nothing.

.DESCRIPTION
    Copilot is not one thing. On a current Windows 11 machine it can be present
    as an app, as a separate full application in Program Files with its own
    updater and a privileged service, as a provisioned package waiting for the
    next user account, and as a handful of settings.

    This reports all of them, and - more usefully - reports which ones this
    module could put back if you changed your mind, and which ones it could not.

    Safe to run at any time. Reads more if run as administrator: the provisioned
    package list, which is what NEW accounts on this machine will get, needs
    elevation to enumerate. The report says so rather than reporting a blank.

.PARAMETER Json
    Also write a timestamped JSON snapshot into .\backups\ for comparison later.
    A snapshot is a record, not a backup.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-Copilot.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-Copilot.ps1 -Json
#>

[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$s = Get-CpState

Write-Host ''
Write-Host '  Copilot - what is actually on this machine'
Write-Host ("  {0}  |  build {1}" -f $s.osEdition, $s.osBuild)
Write-Host ("  {0}" -f $(if ($s.elevated) { 'running as administrator' } else { 'NOT elevated - the provisioned-package check will be skipped' }))
Write-Host ('  ' + ('-' * 74))

# --- 1. the app -------------------------------------------------------------
Write-Host ''
Write-Host '  1. THE APP  (removable, and reinstallable from the Store)'
foreach ($p in $script:CpPackages) {
    $e = $s.packages[$p.Name]
    if ($e.present) {
        Write-Host ("     {0,-24} PRESENT  v{1}" -f $p.Name, $e.version)
        Write-Host ("     {0,-24} {1}" -f '', $e.packageFullName)
        if ($e.nonRemovable) { Write-Host ("     {0,-24} marked NON-REMOVABLE by Windows" -f '') }
    }
    else {
        Write-Host ("     {0,-24} not installed for this user" -f $p.Name)
    }
}

# --- 2. provisioned ---------------------------------------------------------
Write-Host ''
Write-Host '  2. PROVISIONED  (what a NEW user account on this PC would get)'
foreach ($p in $script:CpPackages) {
    $e = $s.provisioned[$p.Name]
    if (-not $e.readable) {
        Write-Host ("     {0,-24} not readable without administrator rights" -f $p.Name)
    }
    elseif ($e.present) {
        Write-Host ("     {0,-24} PROVISIONED - {1}" -f $p.Name, $e.packageName)
        Write-Host ("     {0,-24} removing it for yourself does not stop it arriving for the next account" -f '')
    }
    else {
        Write-Host ("     {0,-24} not provisioned" -f $p.Name)
    }
}

# --- 3. the separate application -------------------------------------------
Write-Host ''
Write-Host '  3. THE SEPARATE APPLICATION IN PROGRAM FILES'
$si = $s.systemInstall
if ($si.present) {
    Write-Host ("     {0,-24} {1}" -f 'path', $si.path)
    Write-Host ("     {0,-24} {1:N0} files, {2:N1} MB on disk" -f 'size', $si.fileCount, $si.sizeMB)
    Write-Host ("     {0,-24} {1}" -f 'version', $(if ($si.displayVersion) { $si.displayVersion } else { 'unknown' }))
    if ($si.uninstallString) {
        Write-Host ("     {0,-24} registered - this is the supported way to remove it" -f 'uninstaller')
        Write-Host ("     {0,-24} {1}" -f '', $si.uninstallString)
    }
    else {
        Write-Host ("     {0,-24} NOT registered - no supported uninstall route found" -f 'uninstaller')
    }
    Write-Host ''
    Write-Host '     This is not the Store app. It is a full Chromium application with its'
    Write-Host '     own copy of the browser engine and its own updater, installed'
    Write-Host '     machine-wide. It is the larger of the two by a wide margin.'
}
else {
    Write-Host ("     {0,-24} not present" -f $si.path)
}

# --- 4. the service ---------------------------------------------------------
Write-Host ''
Write-Host '  4. THE SERVICE'
$sv = $s.service
if ($sv.present) {
    Write-Host ("     {0,-24} {1}" -f 'name', $script:CpSystemInstall.Service)
    Write-Host ("     {0,-24} {1}, start type {2}" -f 'state', $sv.state, $sv.startMode)
    Write-Host ("     {0,-24} {1}" -f 'runs as', $sv.account)
    if ($sv.account -match 'LocalSystem' -and $sv.startMode -eq 'Manual') {
        Write-Host ''
        Write-Host '     This is the part worth pausing on. It runs as LocalSystem - the highest'
        Write-Host '     privilege level on the machine - and it is set to Manual, which does not'
        Write-Host '     mean "off". It means it is not running until something asks for it, and'
        Write-Host '     then it runs with full control of the machine. A stopped service is not'
        Write-Host '     an absent one.'
    }
}
else {
    Write-Host ("     {0,-24} not present" -f $script:CpSystemInstall.Service)
}

# --- 5. settings ------------------------------------------------------------
Write-Host ''
Write-Host '  5. SETTINGS  (these are the reversible ones)'
foreach ($r in $script:CpRegistry) {
    $e = $s.registry["$($r.Key)|$($r.Name)"]
    $shown = if ($e.existed) { "$($e.value)" } else { '<not set>' }
    $hive  = if ($r.Key -like 'HKLM*') { 'machine' } else { 'user   ' }
    Write-Host ("     {0,-24} {1,-11} {2}  {3}" -f $r.Name, $shown, $hive, $r.Desc)
}

# --- 6. related, deliberately untouched -------------------------------------
Write-Host ''
Write-Host '  6. RELATED, AND DELIBERATELY LEFT ALONE'
foreach ($n in $script:CpRelatedPackages) {
    $e = $s.related[$n]
    Write-Host ("     {0,-38} {1}" -f $n, $(if ($e.present) { "present  v$($e.version)" } else { 'not installed' }))
}
Write-Host '     Microsoft.BingSearch is what the Start menu uses for web results. Removing'
Write-Host '     it changes how Start behaves, which is a different decision from removing'
Write-Host '     Copilot, so this module does not make it for you.'

# --- 7. running now ---------------------------------------------------------
Write-Host ''
Write-Host '  7. RUNNING RIGHT NOW'
if ($s.processes.Count) {
    foreach ($p in $s.processes) { Write-Host ("     {0,-24} pid {1,-8} {2:N1} MB" -f $p.name, $p.id, $p.wsMB) }
}
else {
    Write-Host '     nothing - which tells you about this moment, not about what is installed'
}

# --- summary ----------------------------------------------------------------
Write-Host ''
Write-Host ('  ' + ('=' * 74))
Write-Host '    WHAT COULD BE UNDONE, IF YOU CHANGED YOUR MIND'
Write-Host ''
Write-Host '    Reversible by this module, from a backup file:'
foreach ($r in $script:CpRegistry) { Write-Host ("      - {0}" -f $r.Name) }
Write-Host ''
Write-Host '    NOT reversible by this module:'
if ($s.packages['Microsoft.Copilot'].present) {
    Write-Host '      - removing the Copilot app. Route back: reinstall from the Microsoft'
    Write-Host '        Store. The module records the exact package name so you can.'
}
if ($si.present) {
    Write-Host ("      - removing the {0:N1} MB application in Program Files. Route back:" -f $si.sizeMB)
    Write-Host '        download and install it again from Microsoft.'
}
Write-Host ''
Write-Host '    That distinction is the whole reason this module is split in two. A'
Write-Host '    settings change has an old value to put back. Deleted software does not.'
Write-Host ''

if ($Json) {
    $dir = Join-Path $here 'backups'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $p = Join-Path $dir ("snapshot_{0}.json" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    $s | ConvertTo-Json -Depth 8 | Set-Content $p -Encoding UTF8
    Write-Host "    snapshot written : $p"
    Write-Host ''
}
