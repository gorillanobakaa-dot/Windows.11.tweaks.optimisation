<#
.SYNOPSIS
    Shared core for the feature-update deferral module. This is a LIBRARY.
    Dot-source it; running it directly does nothing but say so.

.DESCRIPTION
    -------------------------------------------------------------------------
    READ THIS FIRST: THE HONEST POSITION
    -------------------------------------------------------------------------
    Microsoft documents every deferral, pause and release-pinning policy in
    this module as a capability of Pro, Education and Enterprise. Windows 11
    HOME IS NOT IN THAT LIST. It is also not explicitly listed as unsupported.

    This module therefore does NOT claim to defer updates on Home. It claims
    exactly three things, and each is checked:
      1. The documented policy values were written.
      2. They were read back and the machine agrees they are there.
      3. Whether the Home update client HONORS them is NOT established by
         either of the above, and the module says so on every run.

    The observable that would settle it is the machine's own release staying
    put: DisplayVersion under CurrentVersion. Test-UpdateDeferral records it
    every time so there is a dated history to compare against.

    -------------------------------------------------------------------------
    WHAT THIS TOUCHES
    -------------------------------------------------------------------------
    Five values under one key,
    HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate:

      TargetReleaseVersion             1        turn release pinning on
      TargetReleaseVersionInfo         "25H2"   READ FROM THIS MACHINE, never
                                                hardcoded - the pin holds you
                                                where you already are
      ProductVersion                   "Windows 11"
      DeferFeatureUpdates              1        legacy on Windows 11
      DeferFeatureUpdatesPeriodInDays  90/180/365

    The key does not exist on a default machine. Applying CREATES it, so the
    undo has to mean "remove the values, and remove the key if we created it
    and nothing else has been written into it" - not "write zeros back". An
    explicit 0 is a policy a future administrator has to reason about; absent
    is absent.

    -------------------------------------------------------------------------
    WHAT THIS DELIBERATELY DOES NOT TOUCH
    -------------------------------------------------------------------------
      - QUALITY UPDATES. Nothing here writes DeferQualityUpdates,
        DeferQualityUpdatesPeriodInDays, or any pause affecting them. Security
        fixes keep flowing. The owner's brief was to avoid being an early
        adopter of FEATURE updates, not to stop being patched. Microsoft:
        "Most organizations consider monthly security update releases as
        mandatory."
      - PauseFeatureUpdatesStartTime. A pause expires after 35 days and then
        silently stops protecting anything. A pin does not expire. Using the
        expiring mechanism for a 3-12 month hold would be a setting that lies.
      - NoAutoUpdate / AUOptions. Turning automatic updating off entirely is a
        different and worse decision than holding feature releases.
      - wuauserv, UsoSvc, BITS, DoSvc. All never-touch in module 06 and none of
        this module's business.
      - Safeguard holds. Read and reported, never bypassed. Microsoft: "We
        recommend that you don't attempt to manually update until issues have
        been resolved and holds released."

    -------------------------------------------------------------------------
    THE DOCUMENTED FAILSAFE, WHICH IS NOT OPTIONAL
    -------------------------------------------------------------------------
    A pin is not permanent and must not be sold as such. Microsoft: "If you
    don't update this before the device reaches end of service, the device will
    automatically be updated once it's 60 days past end of service for its
    edition." Home gets "24 months of support" per feature update. The checker
    prints both, because a hold whose ceiling the owner does not know is a trap.

.NOTES
    Grounding lives in ..\..\_research\update-deferral.md and in this module's
    README References table. Every quote is verified at its cited line by
    READ-ONLY-verification\Build-ReferenceLibrary.py.
#>

$script:UdfSchemaVersion = 1
$script:UdfPolicyKey     = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$script:UdfClientKey     = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings'
$script:UdfGwxKey        = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Appraiser\GWX'
$script:UdfCurrentVer    = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

# The three holds the owner asked for. Days are what the policy takes.
$script:UdfHolds = @{
    3  = 90
    6  = 180
    12 = 365
}

# ---------------------------------------------------------------------------
#  Values this module is allowed to write. The restore validates against THIS
#  list, never against a backup file's contents. A backup is data; data can be
#  edited, and a doctored backup must not be able to steer the undo into
#  writing something this module would never write.
# ---------------------------------------------------------------------------
function Get-UdfPlan {
    <#  Build the write plan for a given hold. TargetReleaseVersionInfo is read
        from the live machine so the pin holds the release you are ON. #>
    param([Parameter(Mandatory)][int]$Months)

    if (-not $script:UdfHolds.ContainsKey($Months)) {
        throw "Unsupported hold: $Months. Valid: 3, 6, 12."
    }
    $days    = $script:UdfHolds[$Months]
    $release = Get-UdfInstalledRelease
    if ([string]::IsNullOrWhiteSpace($release)) {
        throw "Could not read this machine's DisplayVersion. Refusing to guess a release to pin to."
    }

    @(
        @{ Name = 'TargetReleaseVersion'
           Value = 1; Kind = 'DWord'
           Desc = 'turn release pinning on' }
        @{ Name = 'TargetReleaseVersionInfo'
           Value = $release; Kind = 'String'
           Desc = "pin to $release - the release THIS machine is already running" }
        @{ Name = 'ProductVersion'
           Value = 'Windows 11'; Kind = 'String'
           Desc = 'the product the pin applies to' }
        @{ Name = 'DeferFeatureUpdates'
           Value = 1; Kind = 'DWord'
           Desc = 'enable the day-count deferral [LEGACY on Windows 11]' }
        @{ Name = 'DeferFeatureUpdatesPeriodInDays'
           Value = $days; Kind = 'DWord'
           Desc = "$days days = $Months months [LEGACY on Windows 11]" }
    )
}

function Get-UdfAllValueNames {
    <#  Every value this module may ever write, across all holds. The undo
        works from this, so a hold applied at 3 months is fully removed even if
        the undo is asked for while a 12-month hold is configured. #>
    @('TargetReleaseVersion','TargetReleaseVersionInfo','ProductVersion',
      'DeferFeatureUpdates','DeferFeatureUpdatesPeriodInDays')
}

function Test-UdfElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-UdfInstalledRelease {
    (Get-ItemProperty -Path $script:UdfCurrentVer -ErrorAction SilentlyContinue).DisplayVersion
}

function Get-UdfEdition {
    (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
}

function Test-UdfIsHome {
    $c = Get-UdfEdition
    if (-not $c) { return $false }
    $c -match '\bHome\b'
}

function Get-UdfBuildString {
    $cv  = Get-ItemProperty -Path $script:UdfCurrentVer -ErrorAction SilentlyContinue
    $ver = [Environment]::OSVersion.Version
    "{0}.{1}.{2}.{3}" -f $ver.Major, $ver.Minor, $ver.Build, $cv.UBR
}

function Get-UdfRegEntry {
    <#  Reads one value AND whether it and its key exist at all. "Absent" is a
        state this module must be able to restore to. #>
    param([string]$Key, [string]$Name)
    if (-not (Test-Path $Key)) {
        return [pscustomobject]@{ value = $null; kind = $null; existed = $false; keyExisted = $false }
    }
    try {
        $item = Get-ItemProperty -Path $Key -Name $Name -ErrorAction Stop
        $kind = $null
        try { $kind = (Get-Item $Key).GetValueKind($Name).ToString() } catch { }
        [pscustomobject]@{ value = $item.$Name; kind = $kind; existed = $true; keyExisted = $true }
    }
    catch {
        [pscustomobject]@{ value = $null; kind = $null; existed = $false; keyExisted = $true }
    }
}

function Get-UdfSafeguardHold {
    <#  Documented, edition-agnostic, read-only. GStatus 2 = no hold, 0 = hold. #>
    $g = Get-ItemProperty -Path $script:UdfGwxKey -ErrorAction SilentlyContinue
    if ($null -eq $g -or $null -eq $g.GStatus) {
        return [pscustomobject]@{ known = $false; status = $null; text = 'no appraiser state recorded on this machine' }
    }
    $s = [int]$g.GStatus
    $t = switch ($s) {
        2 { 'no safeguard hold is in effect' }
        0 { 'A SAFEGUARD HOLD IS IN EFFECT - Microsoft is already holding this machine back' }
        default { "GStatus reports $s, which is not one of the two values Microsoft documents" }
    }
    [pscustomobject]@{ known = $true; status = $s; text = $t }
}

function Get-UdfClientView {
    <#  The update CLIENT's own state, as opposed to the policy an admin set.
        This is the only local surface that reflects what the client believes,
        which is why it is recorded on every run. #>
    $k = Get-ItemProperty -Path $script:UdfClientKey -ErrorAction SilentlyContinue
    [pscustomobject]@{
        keyExists           = [bool]$k
        PausedFeatureStatus = if ($k) { $k.PausedFeatureStatus } else { $null }
        PausedQualityStatus = if ($k) { $k.PausedQualityStatus } else { $null }
    }
}

function Get-UdfState {
    <#  The backup subject: every value this module may write, plus the context
        needed to judge a restore later. #>
    $values = @{}
    foreach ($n in Get-UdfAllValueNames) {
        $e = Get-UdfRegEntry -Key $script:UdfPolicyKey -Name $n
        $values[$n] = @{
            name       = $n
            value      = $e.value
            kind       = $e.kind
            existed    = $e.existed
            keyExisted = $e.keyExisted
        }
    }
    [pscustomobject]@{
        schemaVersion   = $script:UdfSchemaVersion
        takenAt         = (Get-Date).ToString('o')
        elevated        = Test-UdfElevated
        edition         = Get-UdfEdition
        build           = Get-UdfBuildString
        displayVersion  = Get-UdfInstalledRelease
        policyKeyExists = (Test-Path $script:UdfPolicyKey)
        values          = $values
        clientView      = Get-UdfClientView
        safeguardHold   = Get-UdfSafeguardHold
    }
}

function Test-UdfStateShape {
    <#  A backup that parses but has lost its sections is not a backup. #>
    param($State)
    if ($null -eq $State) { return $false }
    # @(...) -contains, NOT .Name.Contains(): an object with no properties at
    # all yields a null .Name, and calling .Contains on it THROWS rather than
    # returning false. A shape check that throws on the most malformed input it
    # will ever see is not a shape check. Caught by this module's own suite.
    $present = @($State.PSObject.Properties.Name)
    foreach ($p in 'schemaVersion','takenAt','values','displayVersion') {
        if ($present -notcontains $p) { return $false }
    }
    $v = $State.values
    if ($null -eq $v) { return $false }
    foreach ($n in Get-UdfAllValueNames) {
        $entry = if ($v -is [hashtable]) { $v[$n] } else { $v.$n }
        if ($null -eq $entry) { return $false }
    }
    $true
}

function ConvertTo-UdfSafeTag {
    param([string]$Tag)
    if ([string]::IsNullOrWhiteSpace($Tag)) { return '' }
    $clean = ($Tag -replace '[^\w\-]', '-')
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    "_$clean"
}

function Save-UdfBackup {
    <#
    .SYNOPSIS
        Write a backup and PROVE it reached the disk. Returns the path, or $null.
    .DESCRIPTION
        A caller that gets $null MUST NOT proceed to change anything. The file
        is written, then read back, parsed, and checked for the sections a
        restore needs. Anything less is a claim, not a backup.
    .PARAMETER RecordAsOriginal
        Only the APPLY path may pass this. Without the switch, the restore
        script's own pre-restore snapshot could create original-state.json when
        none existed - recording the CURRENT state as "original" on a machine
        that had already been changed.
    #>
    param(
        [Parameter(Mandatory)][string]$Directory,
        [string]$Tag = '',
        [switch]$RecordAsOriginal
    )
    try {
        if (-not (Test-Path $Directory)) {
            New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop | Out-Null
        }
    }
    catch { Write-Host "    could not create the backup folder: $($_.Exception.Message)"; return $null }

    $state = Get-UdfState
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $path  = Join-Path $Directory ("state_{0}{1}.json" -f $stamp, (ConvertTo-UdfSafeTag $Tag))

    try { $state | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop }
    catch { Write-Host "    could not write the backup: $($_.Exception.Message)"; return $null }

    # Read it back. A write that reports success and produced nothing readable
    # is the exact failure this check exists for.
    try {
        $raw    = Get-Content -Path $path -Raw -ErrorAction Stop
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch { Write-Host "    the backup did not read back: $($_.Exception.Message)"; return $null }

    if (-not (Test-UdfStateShape $parsed)) {
        Write-Host "    the backup read back but is missing sections a restore needs."
        return $null
    }

    if ($RecordAsOriginal) {
        $orig = Join-Path $Directory 'original-state.json'
        if (-not (Test-Path $orig)) {
            try { Copy-Item -Path $path -Destination $orig -ErrorAction Stop }
            catch { Write-Host "    note: could not record original-state.json: $($_.Exception.Message)" }
        }
    }
    $path
}

function Get-UdfBackups {
    param([Parameter(Mandatory)][string]$Directory)
    if (-not (Test-Path $Directory)) { return @() }
    @(Get-ChildItem -Path $Directory -Filter 'state_*.json' -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending)
}

function Get-UdfRestoreCandidates {
    <#  Excludes exactly one kind of file: internal '_~prerestore' snapshots.
        The '~' cannot be produced by ConvertTo-UdfSafeTag, so a user-supplied
        tag can never collide with an internal one. #>
    param([Parameter(Mandatory)][string]$Directory)
    @(Get-UdfBackups -Directory $Directory | Where-Object { $_.Name -notmatch '_~prerestore(_\d+)?\.json$' })
}

function Set-UdfValue {
    <#  Write one value and read it back. $true only if the machine agrees. #>
    param([string]$Name, $Value, [string]$Kind = 'DWord')
    try {
        if (-not (Test-Path $script:UdfPolicyKey)) {
            New-Item -Path $script:UdfPolicyKey -Force -ErrorAction Stop | Out-Null
        }
        New-ItemProperty -Path $script:UdfPolicyKey -Name $Name -Value $Value `
            -PropertyType $Kind -Force -ErrorAction Stop | Out-Null
    }
    catch { Write-Host "      failed: $Name - $($_.Exception.Message)"; return $false }

    $check = Get-UdfRegEntry -Key $script:UdfPolicyKey -Name $Name
    if (-not $check.existed) { Write-Host "      failed: $Name did not stick"; return $false }
    if ([string]$check.value -ne [string]$Value) {
        Write-Host "      failed: $Name reads back as '$($check.value)', not '$Value'"
        return $false
    }
    $true
}

function Remove-UdfValue {
    <#  Return a value to genuinely absent. #>
    param([string]$Name)
    try {
        if (Test-Path $script:UdfPolicyKey) {
            Remove-ItemProperty -Path $script:UdfPolicyKey -Name $Name -Force -ErrorAction SilentlyContinue
        }
    }
    catch { Write-Host "      failed to remove $Name - $($_.Exception.Message)"; return $false }

    $check = Get-UdfRegEntry -Key $script:UdfPolicyKey -Name $Name
    if ($check.existed) { Write-Host "      failed: $Name is still present"; return $false }
    $true
}

function Remove-UdfKeyIfEmpty {
    <#  Remove the policy key only if this module created it and nothing else
        has been written into it since. GetValueNames() reports the (Default)
        value as '' and it COUNTS - a key whose only content is someone else's
        default value is not empty, and deleting it would destroy that value. #>
    if (-not (Test-Path $script:UdfPolicyKey)) { return $true }
    try {
        $item        = Get-Item $script:UdfPolicyKey -ErrorAction Stop
        $otherValues = @($item.GetValueNames())
        $subKeys     = @($item.GetSubKeyNames())
        if ($otherValues.Count -eq 0 -and $subKeys.Count -eq 0) {
            Remove-Item -Path $script:UdfPolicyKey -Force -ErrorAction Stop
            return $true
        }
        Write-Host "      key kept: something else has written to it ($($otherValues.Count) value(s), $($subKeys.Count) subkey(s))"
        return $true
    }
    catch { Write-Host "      key kept: $($_.Exception.Message)"; return $true }
}

function Restore-UdfState {
    <#  Restore every value the backup covers, validated against the module's
        OWN allow-list rather than against the backup's contents. #>
    param([Parameter(Mandatory)]$State)

    $restored = 0; $failed = 0; $skipped = 0
    $values = $State.values

    foreach ($name in Get-UdfAllValueNames) {
        $entry = if ($values -is [hashtable]) { $values[$name] } else { $values.$name }
        if ($null -eq $entry) {
            Write-Host "      skipped $name - the backup does not cover it"
            $skipped++; continue
        }

        if ($entry.existed) {
            $kind = if ($entry.kind) { $entry.kind } else { 'DWord' }
            if ($kind -notin @('DWord','String','ExpandString','QWord','MultiString','Binary')) {
                Write-Host "      skipped $name - backup names an unknown value kind '$kind'"
                $skipped++; continue
            }
            if (Set-UdfValue -Name $name -Value $entry.value -Kind $kind) { $restored++ } else { $failed++ }
        }
        else {
            if (Remove-UdfValue -Name $name) { $restored++ } else { $failed++ }
        }
    }

    # If the whole key did not exist when the backup was taken, take it away
    # again - but only if nothing else has moved in.
    if (-not $State.policyKeyExists) { [void](Remove-UdfKeyIfEmpty) }

    [pscustomobject]@{ restored = $restored; failed = $failed; skipped = $skipped }
}

function Write-UdfHomeCaveat {
    <#  Printed by every script that touches this policy family. It is not
        decoration: a module that quietly implies Home support would be making
        exactly the claim the corpus does not support. #>
    if (Test-UdfIsHome) {
        Write-Host ""
        Write-Host "    ------------------------------------------------------------------"
        Write-Host "    THIS IS WINDOWS 11 HOME."
        Write-Host "    Microsoft documents these policies for Pro, Education and"
        Write-Host "    Enterprise. Home is NOT in that list - and is not listed as"
        Write-Host "    unsupported either. Writing the values is proved by read-back;"
        Write-Host "    whether the Home update client OBEYS them is NOT proved by"
        Write-Host "    anything this module can do in one run."
        Write-Host "    The observable is your release staying put. Check 1 records it."
        Write-Host "    ------------------------------------------------------------------"
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "  This file is a library. Dot-source it; there is nothing to run here."
}
