<#
.SYNOPSIS
    Show every trace of OneDrive this module knows about. Changes nothing.

.DESCRIPTION
    Reads only. Works without administrator rights; with them, it can also read
    the new-account (default-user) Run entry.

    Also reports the things a user would notice: whether OneDrive is running,
    and whether any OneDrive program is registered as installed.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$s = Get-OdState
$left = 0; $open = 0

Write-Host ''
Write-Host '  OneDrive - what is on this machine now'
Write-Host ('  ' + ('-' * 74))

Write-Host ''
Write-Host '  Is OneDrive installed or running?'
$proc = @(Get-Process -Name 'OneDrive*' -ErrorAction SilentlyContinue)
$inst = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
          'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' |
          ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
          Where-Object { $_.DisplayName -like '*OneDrive*' })
$appx = @(Get-AppxPackage -Name '*OneDrive*' -ErrorAction SilentlyContinue)
Write-Host ("    running now           : {0}" -f $(if ($proc.Count) { "YES ($($proc.Count) process(es))" } else { 'no' }))
Write-Host ("    installed program     : {0}" -f $(if ($inst.Count) { 'YES - ' + ($inst.DisplayName -join ', ') } else { 'no' }))
Write-Host ("    Store package (yours) : {0}" -f $(if ($appx.Count) { 'YES - ' + ($appx.Name -join ', ') } else { 'no' }))
$open += $proc.Count + $inst.Count + $appx.Count

Write-Host ''
Write-Host '  Machine block (needs administrator rights to change)'
foreach ($v in (Get-OdValues -Part Machine)) {
    $e = $s.values["$($v.Key)|$($v.Name)"]
    $ok = $e.existed -and [string]$e.value -eq [string]$v.Target
    if (-not $ok) { $open++ }
    Write-Host ("    {0,-8} {1,-36} {2}  [{3}]" -f $(if ($ok) { 'BLOCKED' } else { 'open' }), $v.Name, $(if ($e.existed) { $e.value } else { '<not set>' }), $v.Cite)
    Write-Host ("             {0}" -f $v.Ui)
}
foreach ($i in (Get-OdInstallers)) {
    if ($s.installers[$i.Path].existed) { $open++ }
    Write-Host ("    {0,-8} {1}  [uncited]" -f $(if ($s.installers[$i.Path].existed) { 'present' } else { 'gone' }), $i.Path)
}
if ($s.defaultHive -and $s.defaultHive.readable) {
    foreach ($n in $script:OdHiveValues) {
        $e = $s.defaultHive.values[$n]
        if ($e -and $e.existed) { $open++ }
        Write-Host ("    {0,-8} new-account Run value {1}  [uncited]" -f $(if ($e -and $e.existed) { 'present' } else { 'gone' }), $n)
    }
} else {
    Write-Host '    ?        new-account Run value - run this as administrator to read it'
}
foreach ($f in (Get-OdFolders | Where-Object { $_.Part -eq 'Machine' })) {
    if ($s.folders[$f.Path].existed) { $left++ }
    Write-Host ("    {0,-8} {1}" -f $(if ($s.folders[$f.Path].existed) { 'present' } else { 'gone' }), $f.Path)
}

Write-Host ''
Write-Host '  Leftovers in your account (no administrator rights needed)'
foreach ($v in (Get-OdValues -Part Account)) {
    $e = $s.values["$($v.Key)|$($v.Name)"]
    if ($e.existed) { $left++ }
    Write-Host ("    {0,-8} environment variable {1,-18} {2}" -f $(if ($e.existed) { 'present' } else { 'gone' }), $v.Name, $(if ($e.existed) { $e.value } else { '' }))
}
foreach ($k in (Get-OdKeys -Part Account)) {
    $has = $s.keys[$k.Key].existed
    $guard = if ($has) { Test-OdKeyGuard -Rule $k } else { $null }
    if ($has -and -not $guard) { $left++ }
    Write-Host ("    {0,-8} {1}{2}" -f $(if ($has) { 'present' } else { 'gone' }), $k.Key, $(if ($guard) { "  ($guard)" } else { '' }))
}
foreach ($f in (Get-OdFolders | Where-Object { $_.Part -eq 'Account' })) {
    if ($s.folders[$f.Path].existed) { $left++ }
    Write-Host ("    {0,-8} {1}" -f $(if ($s.folders[$f.Path].existed) { 'present' } else { 'gone' }), $f.Path)
}

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    ways back still open : {0}" -f $open)
Write-Host ("    leftovers remaining  : {0}" -f $left)
if ($open -eq 0 -and $left -eq 0) { Write-Host '    OneDrive is gone from this account and blocked on this machine.' }
Write-Host ''
