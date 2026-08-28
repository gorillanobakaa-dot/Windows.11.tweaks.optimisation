<#
.SYNOPSIS
    Turn Copilot off, and optionally remove it. Two tiers, because one of them
    can be undone from a backup file and the other cannot.

.DESCRIPTION
    -------------------------------------------------------------------------
    TIER 1 - SETTINGS. Reversible.
    -------------------------------------------------------------------------
    The taskbar button and the policy values. Backed up before anything is
    written, restored by Restore-Copilot.ps1, and proved by Test-RoundTrip.ps1.

    This is what runs by default. Nothing is removed unless you ask.

    -------------------------------------------------------------------------
    TIER 2 - REMOVAL. NOT reversible from a backup.
    -------------------------------------------------------------------------
    -RemoveApp            removes the Microsoft.Copilot package for your account
    -RemoveSystemInstall  runs the registered uninstaller for the separate,
                          roughly 1.3 GB Chromium application in Program Files

    You cannot restore 1.3 GB of deleted files from a JSON file. What this
    module records is enough to REINSTALL from Microsoft - package name, version,
    Store link, uninstall string - which is a different thing and is never
    presented as a backup.

    MODULE-STANDARD.md R4.10 covers this case: where a change cannot be reversed
    by replaying a state file, the module must say so and state the actual route
    back.

    -------------------------------------------------------------------------
    ADMINISTRATOR RIGHTS
    -------------------------------------------------------------------------
    Needed only for two things:
      - the machine-wide TurnOffWindowsCopilot policy value (HKLM)
      - -RemoveSystemInstall

    Everything else, including -RemoveApp, is per-user and needs nothing. If you
    run without elevation the script does what it can and reports precisely what
    it skipped, rather than failing or silently doing less.

    -------------------------------------------------------------------------
    A NOTE ON THE POLICY VALUE
    -------------------------------------------------------------------------
    TurnOffWindowsCopilot is DEPRECATED by Microsoft, which recommends AppLocker
    instead - and AppLocker enforcement is not available on Windows Home. The
    policy is set here as a secondary measure and labelled deprecated everywhere
    it appears. It is not presented as the answer, because Microsoft says it is
    not.

.PARAMETER RemoveApp
    Remove the Microsoft.Copilot app package for the current user, using the
    method Microsoft documents. Reinstallable from the Store afterwards.

.PARAMETER RemoveSystemInstall
    Run the registered uninstaller for the Program Files application. Needs
    administrator rights. Reinstalling means downloading it again.

.PARAMETER SkipSettings
    Do not touch the tier 1 settings. Only meaningful with a removal switch.

.PARAMETER Tag
    Label added to the backup file name.

.PARAMETER WhatIf
    Print every change that would be made and make none of them.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Remove-Copilot.ps1 -WhatIf

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Remove-Copilot.ps1
    Settings only. Fully reversible. Removes nothing.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Remove-Copilot.ps1 -RemoveApp
    Settings, plus remove the app for your account.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Remove-Copilot.ps1 -RemoveApp -RemoveSystemInstall
    Everything. Needs administrator rights for the second part.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch] $RemoveApp,
    [switch] $RemoveSystemInstall,
    [switch] $SkipSettings,
    [string] $Tag = ''
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$state = Get-CpState

Write-Host ''
Write-Host '  Copilot - turn off, and optionally remove'
Write-Host ('  ' + ('-' * 74))
Write-Host ("    running as administrator : {0}" -f $(if ($state.elevated) { 'yes' } else { 'NO - machine-wide parts will be skipped and named' }))
Write-Host ''

# ---------------------------------------------------------------------------
#  Plan - tier 1
# ---------------------------------------------------------------------------
$plan = New-Object System.Collections.Generic.List[object]
if (-not $SkipSettings) {
    foreach ($r in $script:CpRegistry) {
        $e = $state.registry["$($r.Key)|$($r.Name)"]
        # -as, not a bare [int] cast: a non-numeric value (a third-party tool
        # writing REG_SZ 'on') must read as "not the target", not throw and
        # leave $cur holding the PREVIOUS row's value.
        $cur = if ($e.existed) { $e.value -as [int] } else { $null }
        $needsAdmin = ($r.Key -like 'HKLM*')
        $blocked = ($needsAdmin -and -not $state.elevated)
        $plan.Add([pscustomobject]@{
            rule = $r
            from = $(if ($e.existed) { "$($e.value)" } else { '<not set>' })
            to   = "$($r.Target)"
            needed  = ($null -eq $cur -or $cur -ne [int]$r.Target)
            blocked = $blocked
        })
    }
}

Write-Host '  TIER 1 - SETTINGS (reversible)'
if ($plan.Count -eq 0) { Write-Host '    skipped (-SkipSettings)' }
foreach ($p in $plan) {
    $mark = if ($p.blocked) { '!!' } elseif ($p.needed) { '->' } else { '  ' }
    $note = if ($p.blocked) { '  NEEDS ADMIN - will be skipped' } else { '' }
    Write-Host ("    {0} {1,-24} {2,-11} {3,-3} {4}{5}" -f $mark, $p.rule.Name, $p.from, $p.to, $p.rule.Desc, $note)
}

# ---------------------------------------------------------------------------
#  Plan - tier 2
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '  TIER 2 - REMOVAL (NOT reversible from a backup)'
$appTarget = $state.packages['Microsoft.Copilot']
$sysTarget = $state.systemInstall

$provPlan = $null
if ($RemoveApp) {
    if ($appTarget.present) {
        Write-Host ("    -> remove app            {0}" -f $appTarget.packageFullName)
        Write-Host  '                             route back: reinstall from the Microsoft Store'
    } else { Write-Host '       app                   not installed - nothing to remove' }
    # The provisioned copy is what NEW user accounts receive [R-91] - a
    # separate installed thing from this account's app.
    $provPlan = Get-CpProvisioned -Name 'Microsoft.Copilot'
    if (-not $provPlan.readable) { Write-Host ("       provisioned copy      unknown - {0}" -f $provPlan.reason) }
    elseif ($provPlan.present)   { Write-Host '    -> provisioned copy      removed too - what new accounts receive' }
    else                         { Write-Host '       provisioned copy      not present' }
} else { Write-Host '       app                   left alone (add -RemoveApp)' }

if ($RemoveSystemInstall) {
    if (-not $sysTarget.present) { Write-Host '       Program Files app     not present - nothing to remove' }
    elseif (-not $sysTarget.uninstallString) {
        Write-Host '    !! Program Files app     present but NO registered uninstaller found.'
        Write-Host '                             This module will NOT delete the folder by hand.'
    }
    elseif (-not $state.elevated) {
        Write-Host ("    !! Program Files app     {0:N0} MB - NEEDS ADMIN, will be skipped" -f $sysTarget.sizeMB)
    }
    else {
        Write-Host ("    -> Program Files app     {0:N0} MB, via its registered uninstaller" -f $sysTarget.sizeMB)
        Write-Host  '                             route back: download and install it again'
    }
} else { Write-Host '       Program Files app     left alone (add -RemoveSystemInstall)' }

$needed = @($plan | Where-Object { $_.needed -and -not $_.blocked })
$anyRemoval = ($RemoveApp -and ($appTarget.present -or ($provPlan -and $provPlan.readable -and $provPlan.present))) -or
              ($RemoveSystemInstall -and $sysTarget.present -and $sysTarget.uninstallString -and $state.elevated)

# ---------------------------------------------------------------------------
#  WhatIf
# ---------------------------------------------------------------------------
if ($WhatIfPreference) {
    Write-Host ''
    Write-Host ('  ' + ('-' * 74))
    Write-Host ("    PREVIEW ONLY - nothing was changed.")
    Write-Host ("      settings that would change : {0}" -f $needed.Count)
    Write-Host ("      removals that would happen  : {0}" -f $(if ($anyRemoval) { 'yes' } else { 'none' }))
    $blockedCount = @($plan | Where-Object { $_.blocked -and $_.needed }).Count
    if ($blockedCount -gt 0 -or ($RemoveSystemInstall -and -not $state.elevated)) {
        Write-Host '      some parts need administrator rights and would be skipped.'
    }
    Write-Host ''
    return
}

if ($needed.Count -eq 0 -and -not $anyRemoval) {
    Write-Host ''
    Write-Host '    Nothing to do.'
    Write-Host ''
    # Exit 4 is the contract for "nothing to do, NO backup written". A plain 0
    # here is indistinguishable from a successful apply, and the round trip
    # then "undoes" using some OLDER backup - reverting settings the user
    # deliberately applied, and blaming the undo for it.
    exit 4
}

# ---------------------------------------------------------------------------
#  Backup, and refuse to continue without one
# ---------------------------------------------------------------------------
Write-Host ''
$backupDir = Join-Path $here 'backups'
# -RecordAsOriginal: the apply path, reading the machine before it changes
# anything, is the only reading entitled to define "original".
$backup = Save-CpBackup -State $state -Directory $backupDir -Tag $Tag -RecordAsOriginal
if (-not $backup) {
    Write-Host ''
    Write-Host '    STOPPING. Nothing has been changed.'
    Write-Host '    The backup could not be written and verified, so the tier 1 settings'
    Write-Host '    would have no reliable undo - and tier 2 has none by nature.'
    Write-Host ''
    # Exit 3 is the contract for "backup refused, nothing changed". The round
    # trip gates on it; before this line existed that gate was dead code.
    exit 3
}
Write-Host ("    backup written and verified: {0}" -f (Split-Path -Leaf $backup))

# ---------------------------------------------------------------------------
#  Apply tier 1
# ---------------------------------------------------------------------------
$changed = 0; $already = 0; $failed = 0; $skipped = 0; $declined = 0
if ($plan.Count) {
    Write-Host ''
    Write-Host '    settings:'
    foreach ($p in $plan) {
        if ($p.blocked) { $skipped++; Write-Host ("      skip {0,-24} needs administrator rights" -f $p.rule.Name); continue }
        if (-not $p.needed) { $already++; continue }
        if (-not $PSCmdlet.ShouldProcess($p.rule.Name, "set to $($p.to)")) { $declined++; continue }
        if (Set-CpRegistryValue -Key $p.rule.Key -Name $p.rule.Name -Value $p.rule.Target -Kind $p.rule.Kind) {
            Write-Host ("      set  {0,-24} {1} -> {2}" -f $p.rule.Name, $p.from, $p.to); $changed++
        } else { $failed++ }
    }
}

# ---------------------------------------------------------------------------
#  Apply tier 2 - and record what is needed to get it back
# ---------------------------------------------------------------------------
$removals = New-Object System.Collections.Generic.List[object]

if ($RemoveApp) {
    if ($appTarget.present) {
        if ($appTarget.nonRemovable) {
            # Windows marks some packages non-removable and Remove-AppxPackage
            # fails on them. Refuse by name, before trying, not by stack trace.
            Write-Host ''
            Write-Host '    NOT removing the app: Windows marks this package non-removable.'
            Write-Host '    Nothing was attempted - a refusal, not a failure.'
            $skipped++
        }
        elseif ($PSCmdlet.ShouldProcess($appTarget.packageFullName, 'remove appx package')) {
            Write-Host ''
            Write-Host '    removing the app ...'
            # The method Microsoft documents:
            #   $packageFullName = Get-AppxPackage -Name "Microsoft.Copilot" | Select -ExpandProperty PackageFullName
            #   Remove-AppxPackage -Package $packageFullName
            try {
                Remove-AppxPackage -Package $appTarget.packageFullName -ErrorAction Stop
                $after = Get-CpPackageState -Name 'Microsoft.Copilot'
                if ($after.present) {
                    Write-Host '      FAILED - the package is still installed'
                    $failed++
                } else {
                    Write-Host ("      removed {0}" -f $appTarget.packageFullName)
                    $removals.Add([pscustomobject]@{
                        what = 'appx package'; id = $appTarget.packageFullName
                        version = $appTarget.version
                        routeBack = 'reinstall from https://apps.microsoft.com/detail/9NHT9RB2F4HD'
                    })
                }
            }
            catch { Write-Host ("      FAILED - {0}" -f $_.Exception.Message); $failed++ }
        }
        else { $declined++ }
    }

    # The provisioned copy is what NEW user accounts receive; removing the app
    # for this account does not touch it [R-91]. Elevated, remove it the way
    # Microsoft documents for keeping an app away from new accounts [R-97].
    # Unelevated it cannot even be read - say so instead of staying silent.
    $prov = Get-CpProvisioned -Name 'Microsoft.Copilot'
    if ($prov.readable -and $prov.present) {
        if ($PSCmdlet.ShouldProcess($prov.packageName, 'remove provisioned package (what new accounts receive)')) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $prov.packageName -ErrorAction Stop | Out-Null
                $provAfter = Get-CpProvisioned -Name 'Microsoft.Copilot'
                if ($provAfter.readable -and -not $provAfter.present) {
                    Write-Host '      removed the provisioned copy - new accounts will not receive it'
                    $removals.Add([pscustomobject]@{
                        what = 'provisioned package (what new accounts receive)'; id = $prov.packageName
                        version = $prov.version
                        routeBack = 'reinstall from the Store per account; provisioning returns with a Copilot reinstall or a feature update'
                    })
                } else {
                    Write-Host '      FAILED - the provisioned copy is still registered'; $failed++
                }
            }
            catch { Write-Host ("      FAILED on the provisioned copy - {0}" -f $_.Exception.Message); $failed++ }
        }
        else { $declined++ }
    }
    elseif (-not $prov.readable) {
        Write-Host ''
        Write-Host '      NOTE: the PROVISIONED copy - what new user accounts receive -'
        Write-Host ("      could not be checked: {0}" -f $prov.reason)
        Write-Host '      If one is there, new accounts still get Copilot. An elevated'
        Write-Host '      re-run of launcher 7 checks and removes it when it can.'
    }
}

if ($RemoveSystemInstall -and $sysTarget.present -and $sysTarget.uninstallString -and $state.elevated) {
    if ($PSCmdlet.ShouldProcess($sysTarget.path, 'run the registered uninstaller')) {
        Write-Host ''
        Write-Host '    running the registered uninstaller ...'
        Write-Host '    (this module does NOT delete the folder by hand - see the README)'
        try {
            # The uninstall string is "<exe>" --uninstall --mscopilot ... : split
            # the quoted executable from its arguments rather than handing the
            # whole line to a shell.
            $u = $sysTarget.uninstallString
            if ($u -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $argline = $Matches[2] }
            else { $parts = $u -split '\s+', 2; $exe = $parts[0]; $argline = $(if ($parts.Count -gt 1) { $parts[1] } else { '' }) }

            if (-not (Test-Path $exe)) {
                Write-Host ("      FAILED - the uninstaller is not there: {0}" -f $exe); $failed++
            }
            else {
                # The argument line goes through as ONE string: Start-Process
                # refuses an empty -ArgumentList outright, and re-splitting on
                # whitespace mangles quoted arguments. A bare "<exe>" with no
                # arguments simply gets none.
                $sp = @{ FilePath = $exe; Wait = $true; PassThru = $true; ErrorAction = 'Stop' }
                if ($argline -and $argline.Trim()) { $sp['ArgumentList'] = $argline.Trim() }
                $p = Start-Process @sp

                # Chromium-family uninstallers can hand the work to a copy of
                # themselves and exit at once, so the process ending is not the
                # uninstall finishing. Poll the folder, up to a minute.
                $deadline = (Get-Date).AddSeconds(60)
                $afterSys = Get-CpSystemInstallState
                while ($afterSys.present -and (Get-Date) -lt $deadline) {
                    Start-Sleep -Seconds 3
                    $afterSys = Get-CpSystemInstallState
                }

                if ($afterSys.present) {
                    Write-Host ("      uninstaller exited {0}, but {1}" -f $p.ExitCode, $afterSys.path)
                    Write-Host  '      is still present a minute later. Not treating that as success,'
                    Write-Host  '      and NOT recording a removal. If it is still uninstalling in the'
                    Write-Host  '      background, "1 - Check what is on now" will show where it got.'
                    $failed++
                } else {
                    if ($p.ExitCode -ne 0) {
                        Write-Host ("      the folder is gone, but the uninstaller exited {0}, not 0." -f $p.ExitCode)
                        Write-Host  '      Recording the removal with that exit code. Check'
                        Write-Host  '      "1 - Check what is on now" for leftovers.'
                    } else {
                        Write-Host ("      removed - uninstaller exit code {0}" -f $p.ExitCode)
                    }
                    # An uninstall that leaves its LocalSystem service registered
                    # is a partial uninstall; record that, never paper over it.
                    $svcAfter = Get-CpServiceState -Name $script:CpSystemInstall.Service
                    if ($svcAfter.present) {
                        Write-Host '      WARNING: MicrosoftCopilotElevationService is STILL registered.'
                        Write-Host '      The uninstall left residue; recorded in the removal record.'
                    }
                    $removals.Add([pscustomobject]@{
                        what = 'system-level application'; id = $sysTarget.path
                        version = $sysTarget.displayVersion
                        uninstallerExitCode = $p.ExitCode
                        serviceLeftBehind   = [bool]$svcAfter.present
                        routeBack = 'download and install Copilot again from Microsoft'
                    })
                }
            }
        }
        catch { Write-Host ("      FAILED - {0}" -f $_.Exception.Message); $failed++ }
    }
    else { $declined++ }
}

# ---------------------------------------------------------------------------
#  Record the irreversible part, separately and honestly
# ---------------------------------------------------------------------------
if ($removals.Count) {
    $recPath = Join-Path $backupDir 'removed-not-restorable.json'
    $existing = @()
    if (Test-Path $recPath) {
        try {
            # Assign FIRST, then wrap: PowerShell 5.1's ConvertFrom-Json emits
            # a JSON array as ONE pipeline object, so @(pipeline) counts 1
            # whatever the file holds. Assignment keeps the real array; @() on
            # the variable then counts its elements. Proved live: the read-back
            # check below false-alarmed on a correct 2-entry file.
            $parsedExisting = Get-Content $recPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $existing = @($parsedExisting)
        }
        catch {
            # This file is the only inventory of software already removed. A
            # copy that will not parse is PRESERVED under another name - it is
            # never silently zeroed and written over.
            $keep = "$recPath.unreadable-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
            try {
                Copy-Item -Path $recPath -Destination $keep -ErrorAction Stop
                Write-Host  '    WARNING: the existing removal record would not parse. It is kept as'
                Write-Host ("    {0}; a fresh record starts alongside it." -f (Split-Path -Leaf $keep))
            }
            catch {
                # Cannot even copy it aside: leave the original untouched and
                # put this run's record in a separate file instead.
                Write-Host ("    WARNING: the existing removal record would not parse and could not be copied aside ({0})." -f $_.Exception.Message)
                $recPath = "$recPath.new-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"
                Write-Host ("    The unreadable original is left untouched; this run's record goes to {0}." -f (Split-Path -Leaf $recPath))
            }
            $existing = @()
        }
    }
    $doc = @($existing) + @($removals | ForEach-Object {
        $rec = [ordered]@{ removedAt = (Get-Date).ToString('o'); what = $_.what; id = $_.id; version = $_.version; routeBack = $_.routeBack }
        if ($null -ne $_.PSObject.Properties['uninstallerExitCode']) { $rec['uninstallerExitCode'] = $_.uninstallerExitCode }
        if ($null -ne $_.PSObject.Properties['serviceLeftBehind'])   { $rec['serviceLeftBehind']   = $_.serviceLeftBehind }
        [pscustomobject]$rec
    })
    try {
        $doc | ConvertTo-Json -Depth 6 | Set-Content $recPath -Encoding UTF8 -ErrorAction Stop
        # Read-back verification, same doctrine as the backups: a record that
        # cannot be read back does not count as written.
        $parsedBack = Get-Content $recPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        $verify = @($parsedBack)
        if (@($verify).Count -ne @($doc).Count) {
            throw ("read-back holds {0} entries, expected {1}" -f @($verify).Count, @($doc).Count)
        }
        Write-Host ''
        Write-Host ("    what was removed is recorded in: {0}" -f (Split-Path -Leaf $recPath))
        Write-Host  '    That file is NOT a backup. It records what to reinstall and where'
        Write-Host  '    from, because the software itself cannot be restored from disk.'
    }
    catch {
        Write-Host ("    WARNING: could not write and verify the removal record - {0}" -f $_.Exception.Message)
        Write-Host  '    So that it is at least on screen, this is what was removed:'
        foreach ($r in $removals) { Write-Host ("      {0}: {1} (v{2}) - route back: {3}" -f $r.what, $r.id, $r.version, $r.routeBack) }
    }
}

# ---------------------------------------------------------------------------
#  Report
# ---------------------------------------------------------------------------
$after = Get-CpState
Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    settings changed: {0}, already as wanted: {1}, skipped: {2}, declined at prompt: {3}, failed: {4}" -f $changed, $already, $skipped, $declined, $failed)
Write-Host ("    app present now      : {0}" -f $(if ($after.packages['Microsoft.Copilot'].present) { 'yes' } else { 'no' }))
Write-Host ("    Program Files app now: {0}" -f $(if ($after.systemInstall.present) { "yes ({0:N0} MB)" -f $after.systemInstall.sizeMB } else { 'no' }))
Write-Host ("    elevation service now: {0}" -f $(if ($after.service.present) { "$($after.service.state), $($after.service.startMode)" } else { 'not present' }))
if ($RemoveApp) {
    $provNow = Get-CpProvisioned -Name 'Microsoft.Copilot'
    Write-Host ("    provisioned copy now : {0}" -f $(
        if (-not $provNow.readable) { "unknown - $($provNow.reason)" }
        elseif ($provNow.present)   { 'PRESENT - new user accounts will still receive Copilot' }
        else                        { 'not present' }))
}

if ($skipped -gt 0) {
    Write-Host ''
    Write-Host '    Some parts were skipped for want of administrator rights. Re-run via'
    Write-Host '    the numbered .cmd launcher, which asks Windows for them properly.'
}
Write-Host ''
Write-Host '    To undo the SETTINGS: double-click "4 - UNDO the settings.cmd"'
if ($removals.Count) {
    Write-Host '    The removals cannot be undone by this module. See'
    Write-Host '    backups\removed-not-restorable.json for what to reinstall.'
}
Write-Host ''
