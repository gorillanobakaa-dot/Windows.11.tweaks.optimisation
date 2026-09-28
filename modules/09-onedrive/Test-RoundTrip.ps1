<#
.SYNOPSIS
    Prove the undo works, by doing it: remove for real, undo, compare.

.DESCRIPTION
    A rollback that has never been executed is a claim. This executes it.

    -Part Account (default, no administrator rights): removes the account's
    environment variables and registry keys, undoes, and compares every value
    AND the full exported contents of every key. Folders are left alone
    (-NoFolders): a folder in the Recycle Bin cannot be put back by a script.

    -Part Machine (administrator rights): sets the two policies and removes the
    new-account Run value, undoes, and compares. The installer file is left
    alone (-NoFiles) so the test never depends on moving a system file twice.

    On a PASS the net effect is nothing whatsoever.

.PARAMETER Force
    Skip the confirmation prompt.

.NOTES
    Exit codes: 0 PASS, 1 FAIL, 2 INCONCLUSIVE (nothing to move), 4 refused.
#>
[CmdletBinding()]
param(
    [ValidateSet('Account', 'Machine')][string] $Part = 'Account',
    [switch] $Force
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')
$backupDir = Join-Path $here 'backups'

Write-Host ''
Write-Host ("  OneDrive - round-trip proof ({0} part)" -f $Part.ToLower())
Write-Host ('  ' + ('=' * 74))
if ($Part -eq 'Machine' -and -not (Test-OdElevated)) {
    Write-Host '    The machine part needs administrator rights. Nothing was changed.'; Write-Host ''
    exit 4
}
if (-not $Force) {
    $answer = Read-Host '    Type YES to run it'
    if ($answer -ne 'YES') { Write-Host '    Nothing was changed.'; Write-Host ''; exit 4 }
}

function Get-KeyFingerprint {
    <#  The full contents of a key, as reg.exe exports it, minus nothing. Two
        equal fingerprints mean every value and subkey came back. #>
    param([string]$Key)
    if (-not (Test-Path $Key)) { return '<absent>' }
    $native = $Key -replace '^HKCU:\\', 'HKCU\' -replace '^HKLM:\\', 'HKLM\'
    $tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), "od_fp_$([guid]::NewGuid().ToString('N')).reg")
    $null = & reg.exe export $native $tmp /y 2>&1
    $t = if (Test-Path $tmp) { [IO.File]::ReadAllText($tmp) } else { '<export failed>' }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $t
}

function Get-Reading {
    $st = Get-OdState -SkipHive:($Part -eq 'Account')
    $fp = @{}
    foreach ($k in (Get-OdKeys -Part $Part)) { $fp[$k.Key] = Get-KeyFingerprint -Key $k.Key }
    [pscustomobject]@{ state = $st; fp = $fp }
}

function Compare-Readings {
    # $Start/$End, never $A/$C: PowerShell names are case-insensitive, and
    # "$a = $A..." once destroyed the input and produced a false PASS (module 01).
    param($Start, $End)
    $d = New-Object System.Collections.Generic.List[string]
    foreach ($v in (Get-OdValues -Part $Part)) {
        $k = "$($v.Key)|$($v.Name)"
        $x = $Start.state.values[$k]; $y = $End.state.values[$k]
        if ($x.existed -ne $y.existed) { $d.Add("$($v.Name): existed $($x.existed) -> $($y.existed)"); continue }
        if ($x.existed -and ([string]$x.value -ne [string]$y.value)) { $d.Add("$($v.Name): $($x.value) -> $($y.value)") }
        if ($x.existed -and ([string]$x.kind -ne [string]$y.kind)) { $d.Add("$($v.Name): type $($x.kind) -> $($y.kind)") }
        if ($x.keyExisted -ne $y.keyExisted) { $d.Add("$($v.Name): key existed $($x.keyExisted) -> $($y.keyExisted)") }
        if (-not $x.existed -and -not $y.existed -and [string]$x.existingAncestor -ne [string]$y.existingAncestor) {
            $d.Add("$($v.Name): nearest existing key $($x.existingAncestor) -> $($y.existingAncestor)")
        }
    }
    foreach ($k in (Get-OdKeys -Part $Part)) {
        if ($Start.fp[$k.Key] -ne $End.fp[$k.Key]) { $d.Add("$($k.Key): contents differ") }
    }
    if ($Part -eq 'Machine') {
        foreach ($n in $script:OdHiveValues) {
            $x = $Start.state.defaultHive.values[$n]; $y = $End.state.defaultHive.values[$n]
            if ([bool]($x -and $x.existed) -ne [bool]($y -and $y.existed) -or ($x -and $x.existed -and [string]$x.value -ne [string]$y.value)) {
                $d.Add("new-account Run value ${n}: differs")
            }
        }
    }
    $d
}

$before = @(Get-OdRuns -Directory $backupDir -Part $Part -IncludeInternal | ForEach-Object Name)

Write-Host '    [A] reading everything before anything happens ...'
$A = Get-Reading

Write-Host '    [B] removing for real ...'
$apply = if ($Part -eq 'Account') { 'Remove-OneDriveLeftovers.ps1' } else { 'Block-OneDrive.ps1' }
$flag  = if ($Part -eq 'Account') { '-NoFolders' } else { '-NoFiles' }
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here $apply) $flag -Tag roundtrip 2>&1
$code = $LASTEXITCODE
if ($code -eq 3) { Write-Host '    The apply refused: no verified backup. Nothing changed.'; Write-Host ''; exit 4 }
if ($code -eq 4) {
    Write-Host '    INCONCLUSIVE - there was nothing to change, so nothing can be proved.'
    Write-Host '    The machine was not touched.'; Write-Host ''
    exit 2
}
if ($code -eq 5) { Write-Host '    WARNING: the apply reported failed steps. The undo still runs.' }
$B = Get-Reading
$moved = (Compare-Readings -Start $A -End $B).Count
Write-Host ("        items that changed: {0}" -f $moved)

Write-Host '    [C] undoing ...'
$null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Restore-OneDrive.ps1') -Part $Part 2>&1
$C = Get-Reading

Write-Host ''
Write-Host ('  ' + ('-' * 74))
$diffs = @(Compare-Readings -Start $A -End $C)
$result = 1
if ($diffs.Count -eq 0 -and $moved -eq 0) {
    Write-Host '    INCONCLUSIVE - nothing moved, so nothing was proved.'; $result = 2
}
elseif ($diffs.Count -eq 0) {
    Write-Host '    PASS - everything came back to exactly where it started.'
    Write-Host ("    {0} item(s) changed and all came back, compared value by value and," -f $moved)
    Write-Host '    for registry keys, by their full exported contents.'
    Write-Host ''
    Write-Host '    The net effect of this test is nothing.'
    $result = 0
}
else {
    Write-Host ("    FAIL - {0} item(s) did not come back:" -f $diffs.Count)
    foreach ($x in $diffs) { Write-Host "      $x" }
    Write-Host '    Do not rely on the undo until this is explained.'
}
# The machine part includes the new-account template. If it could not be read
# at either end, that part was never exercised - say so, and do not call the
# run a full PASS (2026-09-28: a run reported PASS with it silently skipped).
if ($Part -eq 'Machine') {
    $hs = @($A, $C) | ForEach-Object { $_.state.defaultHive } | Where-Object { -not $_ -or -not $_.readable }
    if ($hs.Count) {
        $why = (@($A, $C) | ForEach-Object { $_.state.defaultHive.reason } | Where-Object { $_ } | Select-Object -First 1)
        Write-Host ''
        Write-Host '    NOT TESTED: the new-account template could not be read, so its'
        Write-Host '    entry was never removed or put back by this test.'
        Write-Host ("    reason: {0}" -f $(if ($why) { $why } else { 'unknown' }))
        if ($result -eq 0) { $result = 2 }
    }
}

# Litter from a passing test: its runs record an intermediate state that a
# later undo would faithfully restore (module 04 audit finding). Kept on FAIL.
if ($result -eq 0) {
    $new = @(Get-OdRuns -Directory $backupDir -Part $Part -IncludeInternal | Where-Object { $_.Name -notin $before })
    foreach ($n in $new) { Remove-Item $n.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    if ($new.Count) { Write-Host ("    cleaned up {0} backup run(s) this test created" -f $new.Count) }
}
Write-Host ''
exit $result
