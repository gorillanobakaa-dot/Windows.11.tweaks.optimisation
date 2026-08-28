<#
.SYNOPSIS
    Shared core for the recommendations / suggestions / personalisation module.
    This is a LIBRARY. Dot-source it; running it directly does nothing but say so.

.DESCRIPTION
    -------------------------------------------------------------------------
    WHAT THIS MODULE IS FOR
    -------------------------------------------------------------------------
    Settings > Privacy & security > Recommendations & offers, and the handful of
    related switches that page does not show you. Suggested apps, tips,
    "personalised" content, the language list websites can read, and the Start
    menu's recommendation list.

    Every setting here is under HKEY_CURRENT_USER. That means:

      - it applies to YOUR account only
      - it needs NO administrator rights
      - and, unlike module 02, the whole thing could be built and its rollback
        proved without anyone approving a UAC prompt

    -------------------------------------------------------------------------
    TWO TIERS, AND WHY THE SPLIT IS NOT COSMETIC
    -------------------------------------------------------------------------
    This project's rule is that a factual claim is either cited to Microsoft's
    own documentation or labelled as uncited. Applied here, the settings fall
    into two groups, and the difference is enforced in code rather than
    described in a footnote:

      DOCUMENTED  Five settings that Microsoft's own privacy documentation names
                  explicitly, gives the exact registry path for, and states the
                  intended value of. These are applied by default.

      OBSERVED    Five more under ContentDeliveryManager that are NOT in the
                  corpus at all. They are widely used, they are visibly present
                  on this machine, and their names describe their function - but
                  "everyone knows" is not a citation. They are OFF by default
                  and require -IncludeObserved to apply.

    That second group contains the most interesting one: SilentInstalledApps-
    Enabled, which governs whether Windows may install promoted apps without
    asking. It is worth knowing about, and it is still not documented, and this
    module will not pretend otherwise to make a better story.

.NOTES
    Citations for the documented tier, all in
    windows-itpro-docs/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services.md:

      line  845  HttpAcceptLanguageOptOut
      line 1263  DisableTailoredExperiencesWithDiagnosticData
      line 1598  DisableWindowsSpotlightFeatures
      line 1605  DisableCloudOptimizedContent
      line 1780  Start_TrackDocs

    Advertising ID is deliberately NOT managed here. Microsoft documents it at
    HKEY_LOCAL_MACHINE (line 835), which needs administrator rights, and the
    per-user toggle is already off on the audited machine. Mixing a machine-wide
    setting into a per-user module would force every launcher to request
    elevation for one value.
#>

$script:RcSchemaVersion = 1

# ---------------------------------------------------------------------------
#  Load CimCmdlets BEFORE -WhatIf can get hold of it. PowerShell auto-loads a
#  module on first use; under -WhatIf that narrates every alias the module
#  defines, so the SAFEST launcher - the preview - opened with twelve
#  "What if: Performing the operation Set Alias" lines (audit finding 13).
# ---------------------------------------------------------------------------
$script:RcSavedWhatIf = $WhatIfPreference
try {
    $WhatIfPreference = $false
    if (-not (Get-Module -Name CimCmdlets)) {
        Import-Module CimCmdlets -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    }
}
finally { $WhatIfPreference = $script:RcSavedWhatIf }

# ---------------------------------------------------------------------------
#  TIER 1 - DOCUMENTED. Each carries a Microsoft citation.
# ---------------------------------------------------------------------------
$script:RcDocumented = @(
    @{
        Key  = 'HKCU:\Control Panel\International\User Profile'
        Name = 'HttpAcceptLanguageOptOut'
        Target = 1; Kind = 'DWord'; Cite = 'R-92'
        Ui   = 'Allow websites to access my language list'
        Desc = 'stops websites being handed your language list, which is a fingerprinting signal'
    }
    @{
        Key  = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        Name = 'DisableTailoredExperiencesWithDiagnosticData'
        Target = 1; Kind = 'DWord'; Cite = 'R-93'
        Ui   = 'Personalized offers (tips, ads and recommendations)'
        Desc = 'stops your diagnostic data being used to tailor tips, ads and recommendations'
    }
    @{
        Key  = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        Name = 'DisableWindowsSpotlightFeatures'
        Target = 1; Kind = 'DWord'; Cite = 'R-94'
        Ui   = 'Windows Spotlight (lock screen images, tips, suggestions)'
        Desc = 'turns off the whole Spotlight family, including suggested apps and Windows tips'
    }
    @{
        Key  = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        Name = 'DisableCloudOptimizedContent'
        Target = 1; Kind = 'DWord'; Cite = 'R-95'
        Ui   = 'Cloud optimized content'
        Desc = 'stops Windows fetching cloud-chosen content to show you'
    }
    @{
        Key  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Name = 'Start_TrackDocs'
        Target = 0; Kind = 'DWord'; Cite = 'R-96'
        Ui   = 'Recommended section on the Start menu'
        Desc = 'stops recently opened items appearing in Start, Jump Lists and File Explorer'
    }
)

# ---------------------------------------------------------------------------
#  TIER 2 - OBSERVED, NOT DOCUMENTED. Opt-in only.
#
#  These are not in the offline Microsoft corpus. Their names and locations are
#  well known and consistent across machines, and the values below are what the
#  Settings UI produces - but nobody at Microsoft has written that down anywhere
#  this project can quote, so they do not run unless asked for.
# ---------------------------------------------------------------------------
$script:RcObserved = @(
    @{
        Key  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        Name = 'SilentInstalledAppsEnabled'
        Target = 0; Kind = 'DWord'; Cite = $null
        Ui   = 'Silently install promoted apps'
        Desc = 'THE NOTABLE ONE - governs whether Windows may install promoted apps without asking you'
    }
    @{
        Key  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        Name = 'SystemPaneSuggestionsEnabled'
        Target = 0; Kind = 'DWord'; Cite = $null
        Ui   = 'Show suggestions occasionally in Start'
        Desc = 'app suggestions in the Start menu'
    }
    @{
        Key  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        Name = 'SubscribedContent-338389Enabled'
        Target = 0; Kind = 'DWord'; Cite = $null
        Ui   = 'Get tips and suggestions when using Windows'
        Desc = 'the tips, tricks and suggestion notifications'
    }
    @{
        Key  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        Name = 'SoftLandingEnabled'
        Target = 0; Kind = 'DWord'; Cite = $null
        Ui   = 'Windows tips'
        Desc = 'the tip notifications shown after updates'
    }
    @{
        Key  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Name = 'Start_TrackProgs'
        Target = 0; Kind = 'DWord'; Cite = $null
        Ui   = 'Improve Start and search results'
        Desc = 'stops Windows tracking which apps you open to rank Start and search'
    }
)

function Get-RcSettings {
    <#  The settings this run manages. Documented always; observed only on request. #>
    param([switch]$IncludeObserved)
    if ($IncludeObserved) { return @($script:RcDocumented) + @($script:RcObserved) }
    @($script:RcDocumented)
}

function Get-RcAllSettings { @($script:RcDocumented) + @($script:RcObserved) }

function Get-RcRule {
    <#  Allow-list lookup across BOTH tiers. A restore must be able to put back
        anything this module could have changed, including observed settings
        applied on a previous run with -IncludeObserved. Restricting the restore
        to the documented tier would strand them. #>
    param([string]$Key, [string]$Name)
    foreach ($r in (Get-RcAllSettings)) {
        if ($r.Key -eq $Key -and $r.Name -eq $Name) { return $r }
    }
    $null
}

function Get-RcExistingAncestor {
    <#  The nearest ancestor of $Key that exists right now. Audit finding 3:
        New-Item -Force creates the whole missing chain, but only the LEAF's
        prior existence was recorded, so an undo on a clean profile left
        HKCU:\SOFTWARE\Policies\Microsoft\Windows behind empty forever - and
        the round-trip comparison, which only checked leaves, called it a PASS. #>
    param([string]$Key)
    $k = $Key
    while ($k -and -not (Test-Path $k)) {
        $parent = Split-Path -Parent $k
        if (-not $parent -or $parent -eq $k) { return $null }
        $k = $parent
    }
    $k
}

function Get-RcRegEntry {
    <#  Reads a value and, importantly, whether it and its key exist at all.
        The CloudContent policy key does not exist on a default machine, so
        "absent" is a state the undo has to be able to return to. #>
    param([string]$Key, [string]$Name)
    if (-not (Test-Path $Key)) {
        return [pscustomobject]@{ value = $null; kind = $null; existed = $false; keyExisted = $false
                                  existingAncestor = (Get-RcExistingAncestor -Key $Key) }
    }
    try {
        $item = Get-ItemProperty -Path $Key -Name $Name -ErrorAction Stop
        $kind = $null
        try { $kind = (Get-Item $Key).GetValueKind($Name).ToString() } catch { }
        [pscustomobject]@{ value = $item.$Name; kind = $kind; existed = $true; keyExisted = $true }
    }
    catch { [pscustomobject]@{ value = $null; kind = $null; existed = $false; keyExisted = $true } }
}

function Get-RcState {
    $registry = @{}
    foreach ($r in (Get-RcAllSettings)) {
        $registry["$($r.Key)|$($r.Name)"] = Get-RcRegEntry -Key $r.Key -Name $r.Name
    }
    [pscustomobject]@{
        schemaVersion = $script:RcSchemaVersion
        takenAt       = (Get-Date).ToString('o')
        host          = $env:COMPUTERNAME
        user          = $env:USERNAME
        osBuild       = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).BuildNumber
        registry      = $registry
    }
}

function Test-RcStateShape {
    param($State)
    if ($null -eq $State)                                     { return $false }
    if (-not $State.PSObject.Properties['schemaVersion'])      { return $false }
    # Audit finding 12: [int] on a non-numeric schemaVersion THREW instead of
    # returning $false, so a corrupt file crashed the restore with a raw .NET
    # exception at exactly the call site this guard exists to protect.
    $ver = $null
    try { $ver = [int]$State.schemaVersion } catch { return $false }
    if ($ver -ne $script:RcSchemaVersion)                      { return $false }
    if (-not $State.PSObject.Properties['registry'])           { return $false }
    # A registry section that is an array rather than an object is the shape that
    # once produced eight phantom writes in module 01.
    if ($State.registry -is [System.Array])                    { return $false }
    $true
}

function ConvertTo-RcSafeTag {
    param([string]$Tag)
    if (-not $Tag) { return '' }
    # A colon would create an NTFS alternate data stream: the file appears to
    # write, is zero bytes, and is invisible to the undo path.
    $clean = ($Tag -replace '[^A-Za-z0-9\-_.]', '-').Trim('-')
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    if ($clean) { "_$clean" } else { '' }
}

function Save-RcBackup {
    <#
    .SYNOPSIS
        Write a backup and PROVE it was written. Returns the path, or $null.
    .PARAMETER RecordAsOriginal
        Permit this backup to establish original-state.json. ONLY the apply path
        may pass this. Without the switch, the restore script's own pre-restore
        snapshot would create original-state.json from the CURRENT state when
        none existed, and "undo to original" would restore the applied state
        forever. That was a real defect in modules 01 and 02.
    #>
    param(
        [Parameter(Mandatory)] $State,
        [Parameter(Mandatory)][string] $Directory,
        [string] $Tag = '',
        [string] $InternalSuffix = '',
        [switch] $RecordAsOriginal
    )

    # -ErrorAction Stop on BOTH: Test-Path throws a non-terminating error on a
    # path with illegal characters, printing a raw .NET exception in red and
    # carrying on past the catch.
    try {
        if (-not (Test-Path $Directory -ErrorAction Stop)) {
            New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop | Out-Null
        }
    }
    catch {
        Write-Host "    BACKUP FAILED: cannot use the backup folder - $($_.Exception.Message)"
        Write-Host "                   path: $Directory"
        return $null
    }

    # Internal snapshots carry a '~' marker no user tag can produce: the
    # safe-tag charset strips '~'. The first fix for the tag-collision audit
    # finding transformed reserved TAGS instead - which renamed the INTERNAL
    # pre-restore snapshot too, freeing it to appear as a restore candidate,
    # and a double-undo then restored the applied state from its own snapshot.
    $suffix = if ($InternalSuffix) { "_~$InternalSuffix" } else { ConvertTo-RcSafeTag $Tag }
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $path  = Join-Path $Directory ("state_{0}{1}.json" -f $stamp, $suffix)
    $n = 1
    while (Test-Path $path) {
        $path = Join-Path $Directory ("state_{0}{1}_{2}.json" -f $stamp, $suffix, $n); $n++
    }

    try   { $State | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop }
    catch { Write-Host "    BACKUP FAILED: could not write $path - $($_.Exception.Message)"; return $null }

    if (-not (Test-Path $path)) { Write-Host "    BACKUP FAILED: $path is not there after writing it"; return $null }
    $len = (Get-Item $path).Length
    if ($len -lt 200) { Write-Host "    BACKUP FAILED: $path is only $len bytes"; return $null }

    try {
        $back = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-RcStateShape -State $back)) {
            Write-Host "    BACKUP FAILED: $path parsed but is not a usable state file"; return $null
        }
    }
    catch { Write-Host "    BACKUP FAILED: $path cannot be read back - $($_.Exception.Message)"; return $null }

    if ($RecordAsOriginal) {
        $original = Join-Path $Directory 'original-state.json'
        if (-not (Test-Path $original)) {
            try {
                Copy-Item -Path $path -Destination $original -ErrorAction Stop
                Write-Host '    original state preserved: original-state.json (written once, never overwritten)'
            }
            catch {
                Write-Host "    WARNING: could not write original-state.json - $($_.Exception.Message)"
                Write-Host "             'UNDO back to the original' will not work until a run"
                Write-Host "             succeeds in writing that file."
            }
        }
    }
    $path
}

function Get-RcBackups {
    param([Parameter(Mandatory)][string]$Directory)
    if (-not (Test-Path $Directory)) { return @() }
    @(Get-ChildItem -Path $Directory -Filter 'state_*.json' -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending)
}

function Get-RcRestoreCandidates {
    <#  Excludes two kinds of internal snapshot by their exact reserved suffixes
        (ConvertTo-RcSafeTag prevents a user tag from producing either):
          _pre-restore  taken by the undo before it runs; offering these makes a
                        second undo re-apply what the first one reversed
          _roundtrip    taken by the round-trip test's apply step; audit finding
                        2: after apply-then-roundtrip, the roundtrip backup
                        recorded the APPLIED state as the newest candidate, so
                        "UNDO everything" restored the applied state and printed
                        "restored: 10 failed: 0" while undoing nothing #>
    param([Parameter(Mandatory)][string]$Directory)
    @(Get-RcBackups -Directory $Directory |
      Where-Object { $_.Name -notmatch '_~prerestore(_\d+)?\.json$' })
}

function Set-RcValue {
    <#  Write one value and read it back. Returns $true only if it stuck. #>
    param([string]$Key, [string]$Name, $Value, [string]$Kind = 'DWord')
    try {
        if (-not (Test-Path $Key)) { New-Item -Path $Key -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $Key -Name $Name -Value $Value -PropertyType $Kind -Force -ErrorAction Stop | Out-Null
    }
    catch { Write-Host "      failed: $Name - $($_.Exception.Message)"; return $false }

    $check = Get-RcRegEntry -Key $Key -Name $Name
    if (-not $check.existed) { Write-Host "      failed: $Name did not stick"; return $false }
    if ([string]$check.value -ne [string]$Value) {
        Write-Host "      failed: $Name reads back as $($check.value), not $Value"; return $false
    }
    $true
}

function Remove-RcValue {
    <#  Return a value to genuinely absent. Key cleanup is a SEPARATE second
        pass - Remove-RcCreatedKeys - so that removing three values that share
        one key does not print two false "something else has written to it"
        warnings on the way (audit finding 6), and so a failed key removal is
        COUNTED rather than swallowed (audit finding 5). #>
    param([string]$Key, [string]$Name)
    try {
        if (Test-Path $Key) { Remove-ItemProperty -Path $Key -Name $Name -Force -ErrorAction SilentlyContinue }
    }
    catch { Write-Host "      failed to remove $Name - $($_.Exception.Message)"; return $false }
    if ((Get-RcRegEntry -Key $Key -Name $Name).existed) {
        Write-Host "      failed: $Name is still present"; return $false
    }
    $true
}

function Remove-RcCreatedKeys {
    <#  Second pass of a restore: remove keys the APPLY created, walking from
        each leaf up to (but never including) the ancestor that already existed
        when the backup was taken. Returns the number of FAILURES so the caller
        reports them instead of printing a clean summary over them.

        Honesty note (audit finding 11): "created by this module" is judged
        from the backup - keyExisted / existingAncestor at backup time - plus an
        emptiness check now. A key someone else created in between, that happens
        to be empty at this moment, is indistinguishable from ours and would be
        removed. An empty policy key sets nothing, so the cost of that residual
        case is zero configuration, but it is stated here rather than hidden. #>
    param([Parameter(Mandatory)] $Entries)   # list of @{ Key; Ancestor }

    $failures = 0
    foreach ($e in ($Entries | Sort-Object { $_.Key.Length } -Descending)) {
        $k = $e.Key
        while ($k -and $e.Ancestor -and $k -ne $e.Ancestor -and $k.Length -gt $e.Ancestor.Length) {
            if (-not (Test-Path $k)) { $k = Split-Path -Parent $k; continue }
            try {
                $item = Get-Item $k -ErrorAction Stop
                # GetValueNames() reports the (Default) value as '' and it COUNTS:
                # a key whose only content is someone's default value is not empty.
                $vals = @($item.GetValueNames())
                $subs = @($item.GetSubKeyNames())
                if ($vals.Count -gt 0 -or $subs.Count -gt 0) {
                    Write-Host "      key kept: $k still holds $($vals.Count) value(s) and $($subs.Count) subkey(s)"
                    break
                }
                Remove-Item -Path $k -Force -ErrorAction Stop
            }
            catch {
                Write-Host "      FAILED to remove created key $k - $($_.Exception.Message)"
                $failures++
                break
            }
            $k = Split-Path -Parent $k
        }
    }
    $failures
}

function Restore-RcState {
    <#
    .SYNOPSIS
        Put the machine back to a recorded state. Reports honestly.
    .DESCRIPTION
        Iterates the module's OWN allow-list, not the backup's contents, and
        looks each entry up in the backup. An entry in the file this module does
        not own is counted as Ignored and never written - which is what stops an
        edited backup file becoming an arbitrary registry writer.

        Every write is read back. A write that did not stick is Failed, never
        Restored.
    #>
    param([Parameter(Mandatory)] $State)

    $restored = 0; $skipped = 0; $failed = 0
    $skippedDetail = @(); $failedDetail = @(); $ignored = @()
    $keysToClean = New-Object System.Collections.Generic.List[object]

    foreach ($rule in (Get-RcAllSettings)) {
        $k = "$($rule.Key)|$($rule.Name)"
        $entry = $null
        if ($State.registry -is [hashtable]) {
            if ($State.registry.ContainsKey($k)) { $entry = $State.registry[$k] }
        }
        elseif ($State.registry.PSObject.Properties[$k]) { $entry = $State.registry.$k }

        if ($null -eq $entry) { $skipped++; $skippedDetail += "$($rule.Name) (not in this backup)"; continue }

        if (-not $entry.existed) {
            if (Remove-RcValue -Key $rule.Key -Name $rule.Name) {
                $restored++
                if (-not $entry.keyExisted) {
                    $anc = $null
                    if ($entry.PSObject.Properties['existingAncestor']) { $anc = $entry.existingAncestor }
                    $keysToClean.Add(@{ Key = $rule.Key; Ancestor = $anc })
                }
            }
            else { $failed++; $failedDetail += "$($rule.Name) (could not remove)" }
        }
        else {
            # Kind is validated against the allow-list, not trusted from the file
            # (see module 02 audit finding 2); the value for these toggles must be
            # a whole number 0 or 1 - anything else in a backup is not a state
            # this module ever wrote, and is refused rather than restored.
            $vOk = $false
            try { $iv = [int]$entry.value; $vOk = ($iv -eq 0 -or $iv -eq 1) } catch { $vOk = $false }
            $kOk = ((-not $entry.kind) -or ([string]$entry.kind -eq $rule.Kind))
            if (-not $vOk -or -not $kOk) {
                $failed++
                $failedDetail += "$($rule.Name) (backup holds an illegitimate value '$($entry.value)' kind '$($entry.kind)' - refused)"
            }
            elseif (Set-RcValue -Key $rule.Key -Name $rule.Name -Value ([int]$entry.value) -Kind $rule.Kind) { $restored++ }
            else { $failed++; $failedDetail += "$($rule.Name) (write did not stick)" }
        }
    }

    $keyFailures = 0
    if ($keysToClean.Count) { $keyFailures = Remove-RcCreatedKeys -Entries $keysToClean }

    if ($State.registry) {
        $names = if ($State.registry -is [hashtable]) { @($State.registry.Keys) }
                 else { @($State.registry.PSObject.Properties.Name) }
        foreach ($n in $names) {
            $parts = $n -split '\|', 2
            if ($parts.Count -ne 2 -or -not (Get-RcRule -Key $parts[0] -Name $parts[1])) { $ignored += $n }
        }
    }

    [pscustomobject]@{
        Restored = $restored; Skipped = $skipped; Failed = $failed
        KeyCleanupFailures = $keyFailures
        SkippedDetail = $skippedDetail; FailedDetail = $failedDetail; Ignored = $ignored
    }
}

if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.\s') {
    Write-Host ''
    Write-Host '  _Common.ps1 is shared code, not a script to run.'
    Write-Host '  Use the numbered .cmd files in this folder instead.'
    Write-Host ''
}
