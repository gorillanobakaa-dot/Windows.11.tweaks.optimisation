<#
.SYNOPSIS
    Prove the undo works, by doing it: install for real, undo, compare.

.DESCRIPTION
    A rollback that has never been executed is a claim. This executes it:
      [A] reads the state (is the guard task there, and what does it do)
      [B] runs Install-TextInputGuard.ps1 for real, with the tag "roundtrip"
      [C] runs Restore-TextInputGuard.ps1 with no arguments
    and compares [A] with [C]. On a PASS the net effect is nothing, and the
    backup files this test created are removed (a later "UNDO" must not find
    them). On a FAIL they are kept, and the test says so.

    If the guard is already installed with the default settings, the install
    has nothing to do (exit 4) and this test stops before its undo, reporting
    INCONCLUSIVE: an undo after an install that changed nothing proves
    nothing. To get a real test, run "7 - UNDO back to the original" first.

    Per-user: no administrator rights needed or asked for.

.PARAMETER Force
    Skip the confirmation prompt.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1
    Asks for YES, then runs the proof.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-RoundTrip.ps1 -Force
    Runs the proof without asking.

.NOTES
    Exit codes: 0 PASS, 1 FAIL, 2 INCONCLUSIVE (nothing moved), 4 refused.
#>
[CmdletBinding()]
param([switch] $Force)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')
$backupDir = Join-Path $here 'backups'

Write-Host ''
Write-Host '  TextInputHost guard - round-trip proof'
Write-Host ('  ' + ('=' * 74))
if (-not $Force) {
    Write-Host '    This installs the guard for real, then undoes it, then compares.'
    $answer = Read-Host '    Type YES to run it'
    if ($answer -ne 'YES') { Write-Host '    Nothing was changed.'; Write-Host ''; exit 4 }
}

function Get-Reading {
    $s = Get-TigState
    $t = Get-TigTask
    [pscustomobject]@{ existed = [bool]$s.task.existed; xml = [string]$s.task.xml; enabled = [bool]($t -and $t.State -ne 'Disabled') }
}
function Compare-Readings {
    # $Start/$End, never $A/$a: PowerShell names are case-insensitive, and
    # that once destroyed a test's input and produced a false PASS (module 01).
    param($Start, $End)
    $d = New-Object System.Collections.Generic.List[string]
    if ($Start.existed -ne $End.existed) { $d.Add("task existed: $($Start.existed) -> $($End.existed)") }
    elseif ($Start.existed -and -not (Test-TigSameTask -XmlA $Start.xml -XmlB $End.xml)) { $d.Add('task definition differs') }
    if ($Start.existed -and $End.existed -and $Start.enabled -ne $End.enabled) { $d.Add("task enabled: $($Start.enabled) -> $($End.enabled)") }
    $d   # emitted item by item; callers wrap in @() to count
}

$before = @(Get-TigBackups -BackupDir $backupDir -IncludeInternal | ForEach-Object Name)
$origExisted = Test-Path -LiteralPath (Join-Path $backupDir 'original-state.json')

Write-Host '    [A] reading the state before anything happens ...'
$startReading = Get-Reading
Write-Host ("        guard installed: {0}" -f $startReading.existed)

Write-Host '    [B] installing for real ...'
$null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Install-TextInputGuard.ps1') -Tag roundtrip 2>&1
$code = $LASTEXITCODE
if ($code -eq 3) { Write-Host '    The install refused: no verified backup. Nothing changed.'; Write-Host ''; exit 4 }
if ($code -eq 4) {
    Write-Host '    INCONCLUSIVE - the guard is already installed with these settings, so'
    Write-Host '    the install changed nothing and an undo would prove nothing. The'
    Write-Host '    undo was NOT run and the machine was not touched. For a real test,'
    Write-Host '    run "7 - UNDO back to the original" first, then this again.'
    Write-Host ''
    exit 2
}
if ($code -ne 0) { Write-Host "    WARNING: the install reported exit $code. The undo still runs." }
$midReading = Get-Reading
$moved = @(Compare-Readings -Start $startReading -End $midReading).Count
Write-Host ("        items that changed: {0}" -f $moved)

Write-Host '    [C] undoing (Restore-TextInputGuard.ps1 with no arguments) ...'
$null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Restore-TextInputGuard.ps1') 2>&1
$undoCode = $LASTEXITCODE
$endReading = Get-Reading

Write-Host ''
Write-Host ('  ' + ('-' * 74))
$diffs = @(Compare-Readings -Start $startReading -End $endReading)
$result = 1
if ($undoCode -ne 0) { Write-Host "    the undo reported exit $undoCode" }
if ($diffs.Count -eq 0 -and $moved -eq 0) {
    Write-Host '    INCONCLUSIVE - nothing moved, so nothing was proved.'
    Write-Host '    For a real test, run "7 - UNDO back to the original" first.'
    $result = 2
}
elseif ($diffs.Count -eq 0 -and $undoCode -eq 0) {
    Write-Host '    PASS - everything came back to exactly where it started.'
    Write-Host ("    {0} item(s) changed and all came back, compared by what the task does" -f $moved)
    Write-Host '    (program, arguments, interval, rights) and whether it is enabled.'
    Write-Host ''
    Write-Host '    The net effect of this test is nothing.'
    $result = 0
}
else {
    Write-Host ("    FAIL - {0} item(s) did not come back:" -f $diffs.Count)
    foreach ($x in $diffs) { Write-Host "      $x" }
    Write-Host '    Do not rely on the undo until this is explained. The backups this'
    Write-Host '    test made are kept for the investigation.'
}

# A passed test's backups record an intermediate state that a later "UNDO"
# would faithfully restore (MODULE-STANDARD R16.4). Never the original,
# unless this very test created it.
if ($result -eq 0) {
    $new = @(Get-TigBackups -BackupDir $backupDir -IncludeInternal | Where-Object { $_.Name -notin $before })
    foreach ($n in $new) { Remove-Item -LiteralPath $n.FullName -Force -ErrorAction SilentlyContinue }
    $origNow = Join-Path $backupDir 'original-state.json'
    if (-not $origExisted -and (Test-Path -LiteralPath $origNow)) {
        # this test wrote the original from state [A]; that IS the true
        # original (nothing installed), so it is kept, and said so
        Write-Host '    original-state.json was created by this test from state [A]; kept.'
    }
    if ($new.Count) { Write-Host ("    cleaned up {0} backup file(s) this test created" -f $new.Count) }
}
Write-Host ''
exit $result
