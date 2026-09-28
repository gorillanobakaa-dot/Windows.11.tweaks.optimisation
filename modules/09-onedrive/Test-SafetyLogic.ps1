<#
.SYNOPSIS
    Test the machinery that decides whether to write, remove or refuse.
    Changes nothing real: it works in a temporary folder and in a throwaway
    registry key under HKCU\Software\W11T_OdSelfTest, which it removes.

.NOTES
    Exit code: 0 all passed, 1 any failed.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$pass = 0; $fail = 0
function Check {
    # [object], not [bool] (MODULE-STANDARD R2.8a). With [bool], a check whose
    # expression returned a list or text failed at parameter binding: it was
    # counted neither passed nor failed, and it ended the whole try block, so
    # every check after it silently never ran - shown 2026-09-28 with four
    # checks reporting "passed 1, failed 0".
    param([string]$What, [object]$Ok)
    $b = $false
    try { if ($Ok -is [bool]) { $b = $Ok } else { throw "not a yes/no answer: $Ok" } }
    catch { $script:fail++; Write-Host "      FAILED: $What ($($_.Exception.Message))"; return }
    if ($b) { $script:pass++ } else { $script:fail++; Write-Host "      FAILED: $What" }
}

$tmp  = Join-Path ([IO.Path]::GetTempPath()) ("od-selftest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$test = 'HKCU:\Software\W11T_OdSelfTest'
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

Write-Host ''
Write-Host '  OneDrive - safety logic self-test'
Write-Host ('  ' + ('-' * 74))
Write-Host '  Changes nothing real. Works in a temporary folder and a throwaway key.'
Write-Host ''

try {
    Write-Host '  1. The settings table is what the documentation says it is'
    Check 'exactly two cited values'           (@($script:OdValues | Where-Object Cite).Count -eq 2)
    Check 'both cited values are Machine'      (@($script:OdValues | Where-Object Cite | Where-Object { $_.Part -ne 'Machine' }).Count -eq 0)
    Check 'R-145 is DisableFileSyncNGSC = 1'    (@($script:OdValues | Where-Object { $_.Cite -eq 'R-145' -and $_.Name -eq 'DisableFileSyncNGSC' -and $_.Target -eq 1 -and $_.Key -eq 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' }).Count -eq 1)
    Check 'R-146 is PreventNetworkTraffic... = 1' (@($script:OdValues | Where-Object { $_.Cite -eq 'R-146' -and $_.Name -eq 'PreventNetworkTrafficPreUserSignIn' -and $_.Target -eq 1 -and $_.Key -eq 'HKLM:\SOFTWARE\Microsoft\OneDrive' }).Count -eq 1)
    Check 'no Account item touches HKLM'       (@(Get-OdValues -Part Account | Where-Object { $_.Key -like 'HKLM:*' }).Count -eq 0)
    Check 'no Account key touches HKLM'        (@(Get-OdKeys -Part Account | Where-Object { $_.Key -like 'HKLM:*' }).Count -eq 0)

    Write-Host '  2. A file that is merely JSON-shaped is rejected as a backup'
    Check 'null state rejected'                (-not (Test-OdStateShape -State $null))
    Check 'missing values rejected'            (-not (Test-OdStateShape -State ([pscustomobject]@{ schemaVersion = 1; keys = @{} })))
    Check 'wrong schema rejected'              (-not (Test-OdStateShape -State ([pscustomobject]@{ schemaVersion = 9; values = @{}; keys = @{} })))
    Check 'non-numeric schema rejected'        (-not (Test-OdStateShape -State ([pscustomobject]@{ schemaVersion = 'x'; values = @{}; keys = @{} })))
    Check 'array values rejected'              (-not (Test-OdStateShape -State ([pscustomobject]@{ schemaVersion = 1; values = @(1, 2); keys = @{} })))
    Check 'real state accepted'                (Test-OdStateShape -State (Get-OdState -SkipHive))

    Write-Host '  3. A backup can only restore legitimate values'
    $dw = @{ Kind = 'DWord' }; $sz = @{ Kind = 'String' }
    Check 'DWord 1 allowed'                    (Test-OdLegitValue -Rule $dw -Entry ([pscustomobject]@{ value = 1; kind = 'DWord' }))
    Check 'DWord 7 refused'                    (-not (Test-OdLegitValue -Rule $dw -Entry ([pscustomobject]@{ value = 7; kind = 'DWord' })))
    Check 'DWord given as text refused'        (-not (Test-OdLegitValue -Rule $dw -Entry ([pscustomobject]@{ value = 'abc'; kind = 'DWord' })))
    Check 'wrong kind refused'                 (-not (Test-OdLegitValue -Rule $dw -Entry ([pscustomobject]@{ value = 1; kind = 'String' })))
    Check 'path string allowed'                (Test-OdLegitValue -Rule $sz -Entry ([pscustomobject]@{ value = 'C:\Users\x\OneDrive'; kind = 'String' }))
    Check 'multi-line string refused'          (-not (Test-OdLegitValue -Rule $sz -Entry ([pscustomobject]@{ value = "a`nb"; kind = 'String' })))
    Check 'empty string refused'               (-not (Test-OdLegitValue -Rule $sz -Entry ([pscustomobject]@{ value = ''; kind = 'String' })))
    Check 'oversized string refused'           (-not (Test-OdLegitValue -Rule $sz -Entry ([pscustomobject]@{ value = ('x' * 300); kind = 'String' })))

    Write-Host '  4. The restore iterates its own allow-list, never the backup'
    $evil = [pscustomobject]@{ schemaVersion = 1; keys = @{}
        values = @{ 'HKCU:\Software\W11T_OdSelfTest|Injected' = [pscustomobject]@{ existed = $true; value = 1; kind = 'DWord'; keyExisted = $true } } }
    $r = Restore-OdValues -State $evil -Part Account
    Check 'foreign entry not written'          (-not (Test-Path $test))
    Check 'own entries reported as skipped'    ($r.Skipped -eq @(Get-OdValues -Part Account).Count -and $r.Restored -eq 0)

    Write-Host '  5. "Absent" and "present" stay distinguishable, and undo removes, not zeroes'
    New-Item -Path $test -Force | Out-Null
    $e = Get-OdRegEntry -Key $test -Name 'Nope'
    Check 'absent value: existed false, key true' (-not $e.existed -and $e.keyExisted)
    $e2 = Get-OdRegEntry -Key "$test\Deeper\Still" -Name 'Nope'
    Check 'absent key: nearest ancestor found' ($e2.existingAncestor -eq $test)
    Check 'Set-OdValue writes and reads back'  (Set-OdValue -Key "$test\Deeper\Still" -Name 'V' -Value 1 -Kind DWord)
    Check 'Remove-OdValue removes'             ((Remove-OdValue -Key "$test\Deeper\Still" -Name 'V') -and -not (Get-OdRegEntry -Key "$test\Deeper\Still" -Name 'V').existed)
    Check 'created chain removed up to ancestor' ((Remove-OdCreatedKey -Key "$test\Deeper\Still" -Ancestor $test) -and -not (Test-Path "$test\Deeper") -and (Test-Path $test))

    Write-Host '  6. Shared keys are never removed'
    $se = @{ Key = "$test\SyncEngines"; Guard = 'syncengines-onedrive-only' }
    New-Item -Path "$($se.Key)\Providers\OneDrive" -Force | Out-Null
    Check 'OneDrive-only provider list: may remove' ($null -eq (Test-OdKeyGuard -Rule $se))
    New-Item -Path "$($se.Key)\Providers\Dropbox" -Force | Out-Null
    Check 'another provider present: kept'     ($null -ne (Test-OdKeyGuard -Rule $se))
    $gv = @{ Key = "$test\grvopen"; Guard = 'grvopen-points-at-onedrive' }
    New-Item -Path "$($gv.Key)\shell\open\command" -Force | Out-Null
    Set-ItemProperty -Path "$($gv.Key)\shell\open\command" -Name '(default)' -Value '"C:\Program Files\Other\Groove.exe" "%1"'
    Check 'handler for another program: kept'  ($null -ne (Test-OdKeyGuard -Rule $gv))
    Set-ItemProperty -Path "$($gv.Key)\shell\open\command" -Name '(default)' -Value '"C:\x\OneDrive.exe" /url:"%1"'
    Check 'handler for OneDrive.exe: may remove' ($null -eq (Test-OdKeyGuard -Rule $gv))

    Write-Host '  7. Key exports are verified before anything is removed'
    $run = New-OdBackupFolder -Directory $tmp -Part 'Account' -Tag 'selftest'
    Check 'run folder created'                 ([bool]$run -and (Test-Path $run))
    $exp = Export-OdKey -Key "$test\grvopen" -RunFolder $run
    Check 'export written and names the key'   ([bool]$exp -and (Get-Content $exp -Raw) -match 'W11T_OdSelfTest')
    Check 'export of a missing key refused'    ($null -eq (Export-OdKey -Key "$test\DoesNotExist" -RunFolder $run))
    Check 'state saved and proved'             (Save-OdState -State (Get-OdState -SkipHive) -RunFolder $run)

    Write-Host '  8. The undo never offers its own pre-restore snapshots'
    $pre = New-OdBackupFolder -Directory $tmp -Part 'Account' -InternalSuffix 'prerestore'
    Save-OdState -State (Get-OdState -SkipHive) -RunFolder $pre | Out-Null
    $runs = Get-OdRuns -Directory $tmp -Part Account
    Check 'pre-restore excluded'               (@($runs | Where-Object { $_.Name -match 'prerestore' }).Count -eq 0)
    Check 'real run offered'                   (@($runs).Count -eq 1)
    Check 'pre-restore listed when asked'      (@(Get-OdRuns -Directory $tmp -Part Account -IncludeInternal).Count -eq 2)

    Write-Host '  9. Tags cannot produce an illegal or invisible folder name'
    Check 'colon stripped (no NTFS stream)'    ((ConvertTo-OdSafeTag 'a:b') -notmatch ':')
    Check 'tilde stripped (reserved marker)'   ((ConvertTo-OdSafeTag '~prerestore') -notmatch '~')
    Check 'long tag capped'                    ((ConvertTo-OdSafeTag ('x' * 100)).Length -le 41)

    Write-Host ' 10. The machine part refuses to run without administrator rights'
    if (-not (Test-OdElevated)) {
        $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Block-OneDrive.ps1') 2>&1
        Check 'unelevated Block exits 4'       ($LASTEXITCODE -eq 4)
        $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Block-OneDrive.ps1') -WhatIf 2>&1
        Check 'unelevated preview exits 0'     ($LASTEXITCODE -eq 0)
    } else {
        Write-Host '      (running elevated - the refusal check only applies without rights; skipped)'
    }
}
catch {
    # an exception means every check after it never ran: a failure, never a
    # quiet "0 failed" (MODULE-STANDARD R2.8a)
    $script:fail++
    Write-Host "      FAILED: the self-test stopped early: $($_.Exception.Message)"
}
finally {
    Remove-Item $test -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    checks passed : {0}" -f $pass)
Write-Host ("    checks failed : {0}" -f $fail)
Write-Host ''
if ($fail) { exit 1 }
Write-Host '    All safety checks passed. What this does NOT show: that the real'
Write-Host '    removal and undo work. That is what "5 - Prove the undo works" does.'
Write-Host ''
exit 0
