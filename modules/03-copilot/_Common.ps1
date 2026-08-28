<#
.SYNOPSIS
    Shared core for the Copilot module. This is a LIBRARY. Dot-source it;
    running it directly does nothing but say so.

.DESCRIPTION
    -------------------------------------------------------------------------
    WHY THIS MODULE IS SHAPED DIFFERENTLY FROM 01 AND 02
    -------------------------------------------------------------------------
    Modules 01 and 02 change settings. A setting has a previous value, so the
    undo is "put the old value back" and a state file is enough.

    Copilot is not only settings. On this machine it exists in three forms:

      1. an appx package, Microsoft.Copilot
      2. a full system-level Chromium application in Program Files (x86),
         about 1.3 GB, with its own registered uninstaller
      3. MicrosoftCopilotElevationService - a service running as LocalSystem

    Removing software is not a setting change. You cannot put 1.3 GB of files
    back from a JSON file. So this module splits into two tiers, and the split
    is enforced in code rather than described in a document:

      TIER 1 - REVERSIBLE. Registry policy values and the taskbar button.
               Backed up, restored, round-trip proved, exactly like modules
               01 and 02.

      TIER 2 - NOT REVERSIBLE HERE. Removing the appx package and running the
               system-level uninstaller. What is recorded is enough to
               reinstall from Microsoft, not enough to restore from disk.

    MODULE-STANDARD.md R4.10 covers this case: where a change is not fully
    reversible by replaying a state file, the module must say so, and say what
    the route back actually is.

    -------------------------------------------------------------------------
    THE FINDING THAT CHANGES THE USUAL ADVICE
    -------------------------------------------------------------------------
    Every "debloat Windows 11" guide sets TurnOffWindowsCopilot. Microsoft's own
    documentation says not to:

      "AppLocker policy should be used instead of the Turn Off Windows Copilot
       legacy policy setting and its MDM equivalent, TurnOffWindowsCopilot. The
       policy is subject to near-term deprecation."
        - windows-itpro-docs/client-management/manage-windows-copilot.md, line 110

    And the modern replacement is not available here either:

      "Only Enterprise (ENT) and Education (EDU) editions support this feature."
        - windows-itpro-docs/configuration/policy-based-inbox-app-removal/
          policy-based-inbox-app-removal.md, line 67

    This machine is Windows 11 Home. So:
      - AppLocker enforcement: not available on Home
      - policy-based in-box app removal: Enterprise/Education only, and needs
        MDM enrolment or domain join
      - TurnOffWindowsCopilot: available, but deprecated by its author

    What remains is the documented, supported removal path:

      "# Get the package full name of the Copilot app
       $packageFullName = Get-AppxPackage -Name "Microsoft.Copilot" | Select-Object -ExpandProperty PackageFullName
       # Remove the Copilot app
       Remove-AppxPackage -Package $packageFullName"
        - manage-windows-copilot.md, lines 124-129

    That is what this module uses. It sets the deprecated policy too, as a
    belt-and-braces measure, but it labels it as deprecated everywhere it
    appears rather than presenting it as the answer.
#>

$script:CpSchemaVersion = 1

# ---------------------------------------------------------------------------
#  Load the modules we use BEFORE -WhatIf can get hold of them. PowerShell
#  auto-loads a module on first command use; under -WhatIf that narrates every
#  alias the module defines, so the PREVIEW opened with dozens of
#  "What if: Performing the operation Set Alias" lines. Same defect was found
#  and fixed in modules 02 and 04; the module 03 audit caught this copy - and
#  its second pass caught the fix incomplete: Get-AppxProvisionedPackage lives
#  in Dism (19 aliases), reached only on the ELEVATED preview path.
# ---------------------------------------------------------------------------
$script:CpSavedWhatIf = $WhatIfPreference
try {
    $WhatIfPreference = $false
    foreach ($m in @('CimCmdlets', 'Appx', 'Dism')) {
        if (-not (Get-Module -Name $m)) {
            Import-Module $m -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        }
    }
}
finally { $WhatIfPreference = $script:CpSavedWhatIf }

# ---------------------------------------------------------------------------
#  TIER 1 - reversible settings. The allow-list a restore is permitted to write.
# ---------------------------------------------------------------------------
$script:CpRegistry = @(
    @{
        Key    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        Name   = 'ShowCopilotButton'
        Target = 0
        Kind   = 'DWord'
        Tier   = 1
        Desc   = 'the Copilot button on the taskbar'
    }
    @{
        Key    = 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'
        Name   = 'TurnOffWindowsCopilot'
        Target = 1
        Kind   = 'DWord'
        Tier   = 1
        Desc   = 'legacy policy - DEPRECATED by Microsoft, kept as a secondary measure only'
    }
    @{
        Key    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'
        Name   = 'TurnOffWindowsCopilot'
        Target = 1
        Kind   = 'DWord'
        Tier   = 1
        Desc   = 'same policy, machine-wide - DEPRECATED, needs administrator'
    }
)

# ---------------------------------------------------------------------------
#  TIER 2 - removals. Deliberately NOT in the restore allow-list, because a
#  restore cannot honour them and must not pretend to.
# ---------------------------------------------------------------------------
$script:CpPackages = @(
    @{
        Name     = 'Microsoft.Copilot'
        Tier     = 2
        StoreUrl = 'https://apps.microsoft.com/detail/9NHT9RB2F4HD'
        Desc     = 'the Copilot app itself'
    }
)

$script:CpSystemInstall = @{
    Path        = 'C:\Program Files (x86)\Microsoft\Copilot'
    UninstallIn = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    DisplayName = 'Copilot'
    Service     = 'MicrosoftCopilotElevationService'
    Tier        = 2
    Desc        = 'a separate, full Chromium application with its own updater and a LocalSystem service'
}

# Packages that are Copilot-adjacent and reported, but NOT removed by this
# module. Microsoft.BingSearch is what the Start menu uses for web results;
# removing it changes Start menu behaviour, which is a different decision.
$script:CpRelatedPackages = @('Microsoft.BingSearch', 'MicrosoftWindows.Client.AIX', 'Microsoft.Windows.Ai.Copilot.Provider')

function Test-CpElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { $false }
}

function Get-CpRegistryRule {
    <#  Allow-list lookup. Returns $null for anything this module does not own.
        Restore validates against this, never against a backup file's contents. #>
    param([string]$Key, [string]$Name)
    foreach ($r in $script:CpRegistry) {
        if ($r.Key -eq $Key -and $r.Name -eq $Name) { return $r }
    }
    $null
}

function Get-CpRegEntry {
    param([string]$Key, [string]$Name)
    $keyExists = Test-Path $Key
    if (-not $keyExists) {
        # existingAncestor: the nearest key above this one that DOES exist. The
        # apply creates the whole missing chain; the undo uses this to know how
        # far up it is entitled to delete.
        return [pscustomobject]@{ value = $null; kind = $null; existed = $false; keyExisted = $false
                                  existingAncestor = (Get-CpExistingAncestor -Key $Key) }
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

function Get-CpPackageState {
    param([string]$Name)
    try {
        $p = Get-AppxPackage -Name $Name -ErrorAction Stop | Select-Object -First 1
        if (-not $p) { return [pscustomobject]@{ present = $false } }
        [pscustomobject]@{
            present         = $true
            name            = [string]$p.Name
            packageFullName = [string]$p.PackageFullName
            version         = [string]$p.Version
            installLocation = [string]$p.InstallLocation
            nonRemovable    = [bool]$p.NonRemovable
            publisher       = [string]$p.Publisher
        }
    }
    catch { [pscustomobject]@{ present = $false } }
}

function Get-CpProvisioned {
    <#  Provisioned packages are what NEW user accounts get. Removing the app for
        yourself does not stop it arriving for the next account created on this
        machine - which is why this is read separately. Needs administrator. #>
    param([string]$Name)
    if (-not (Test-CpElevated)) {
        return [pscustomobject]@{ readable = $false; present = $null; packageName = $null
                                  reason = 'needs administrator rights' }
    }
    try {
        $p = Get-AppxProvisionedPackage -Online -ErrorAction Stop |
             Where-Object { $_.DisplayName -eq $Name } | Select-Object -First 1
        [pscustomobject]@{
            readable    = $true
            present     = ($null -ne $p)
            packageName = if ($p) { [string]$p.PackageName } else { $null }
            version     = if ($p) { [string]$p.Version } else { $null }
            reason      = $null
        }
    }
    catch {
        # Seen for real on this machine: the DISM provisioning read is denied
        # even elevated. "Needs admin" would be the WRONG message then - carry
        # the true reason so the caller can print what actually happened.
        [pscustomobject]@{ readable = $false; present = $null; packageName = $null
                           reason = "the provisioning database could not be read: $($_.Exception.Message.Trim())" }
    }
}

function Get-CpSystemInstallState {
    $s = $script:CpSystemInstall
    $out = [pscustomobject]@{
        present         = $false
        path            = $s.Path
        sizeMB          = 0
        fileCount       = 0
        displayVersion  = $null
        uninstallString = $null
        installLocation = $null
        uninstallKey    = $null
    }
    if (Test-Path $s.Path) {
        $out.present = $true
        try {
            $m = Get-ChildItem $s.Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum
            $out.sizeMB    = [math]::Round($m.Sum / 1MB, 1)
            $out.fileCount = [int]$m.Count
        } catch { }
    }
    # The registered uninstaller is the supported way to remove it. Find it by
    # DisplayName rather than by a guessed key name, which changes between builds.
    if (Test-Path $s.UninstallIn) {
        try {
            Get-ChildItem $s.UninstallIn -ErrorAction Stop | ForEach-Object {
                $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if ($p.DisplayName -eq $s.DisplayName) {
                    $out.displayVersion  = [string]$p.DisplayVersion
                    $out.uninstallString = [string]$p.UninstallString
                    $out.installLocation = [string]$p.InstallLocation
                    $out.uninstallKey    = [string]$_.PSChildName
                }
            }
        } catch { }
    }
    $out
}

function Get-CpServiceState {
    param([string]$Name)
    try {
        $w = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction Stop
        if (-not $w) { return [pscustomobject]@{ present = $false } }
        [pscustomobject]@{
            present     = $true
            state       = [string]$w.State
            startMode   = [string]$w.StartMode
            account     = [string]$w.StartName
            path        = [string]$w.PathName
            displayName = [string]$w.DisplayName
        }
    }
    catch { [pscustomobject]@{ present = $false } }
}

function Get-CpState {
    <#  One complete reading. Tier 1 is what a backup can restore; tier 2 is
        recorded so that a person knows what was removed and where to get it
        again, which is not the same thing and is never presented as if it were. #>

    $registry = @{}
    foreach ($r in $script:CpRegistry) {
        $registry["$($r.Key)|$($r.Name)"] = Get-CpRegEntry -Key $r.Key -Name $r.Name
    }

    $packages = @{}
    foreach ($p in $script:CpPackages) {
        $packages[$p.Name] = Get-CpPackageState -Name $p.Name
    }

    $provisioned = @{}
    foreach ($p in $script:CpPackages) {
        $provisioned[$p.Name] = Get-CpProvisioned -Name $p.Name
    }

    $related = @{}
    foreach ($n in $script:CpRelatedPackages) {
        $related[$n] = Get-CpPackageState -Name $n
    }

    $procs = @()
    try {
        $procs = @(Get-Process -ErrorAction SilentlyContinue |
                   Where-Object { $_.ProcessName -match 'copilot' } |
                   ForEach-Object { [pscustomobject]@{ name = $_.ProcessName; id = $_.Id; wsMB = [math]::Round($_.WorkingSet64 / 1MB, 1) } })
    } catch { }

    [pscustomobject]@{
        schemaVersion = $script:CpSchemaVersion
        takenAt       = (Get-Date).ToString('o')
        host          = $env:COMPUTERNAME
        user          = $env:USERNAME
        osBuild       = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).BuildNumber
        osEdition     = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        elevated      = (Test-CpElevated)
        registry      = $registry
        packages      = $packages
        provisioned   = $provisioned
        related       = $related
        systemInstall = Get-CpSystemInstallState
        service       = Get-CpServiceState -Name $script:CpSystemInstall.Service
        processes     = $procs
    }
}

function Test-CpStateShape {
    param($State)
    if ($null -eq $State)                                       { return $false }
    if (-not $State.PSObject.Properties['schemaVersion'])        { return $false }
    # Module 04 audit finding 12: [int] on a non-numeric schemaVersion THROWS
    # instead of returning $false - crashing the restore with a raw exception at
    # exactly the call site this guard protects. Found here by this module's own
    # self-test before it could ship.
    $ver = $null
    try { $ver = [int]$State.schemaVersion } catch { return $false }
    if ($ver -ne $script:CpSchemaVersion)                        { return $false }
    if (-not $State.PSObject.Properties['registry'])             { return $false }
    if (-not $State.PSObject.Properties['packages'])             { return $false }
    $true
}


# ---------------------------------------------------------------------------
#  Backup / restore machinery for the TIER 1 settings. Same contract as
#  modules 02 and 04: verified backups, -RecordAsOriginal gate, reserved-tag
#  protection, allow-list-driven restore, read-back on every write, and
#  ancestor-chain tracking so keys created by the apply are removed by the undo.
# ---------------------------------------------------------------------------
function ConvertTo-CpSafeTag {
    param([string]$Tag)
    if (-not $Tag) { return '' }
    # A colon would create an NTFS alternate data stream: the file appears to
    # write, is zero bytes, and is invisible to the undo path.
    $clean = ($Tag -replace '[^A-Za-z0-9\-_.]', '-').Trim('-')
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    if ($clean) { "_$clean" } else { '' }
}

function Get-CpExistingAncestor {
    <#  The nearest ancestor of $Key that exists right now. Recorded at backup
        time so the undo can remove every key the apply created, not only the
        leaf. New-Item -Force creates the whole missing chain; an undo that
        removes only the leaf leaves empty policy keys behind forever, and a
        round-trip comparison that only checks the leaf calls that a PASS. #>
    param([string]$Key)
    $k = $Key
    while ($k -and -not (Test-Path $k)) {
        $parent = Split-Path -Parent $k
        if (-not $parent -or $parent -eq $k) { return $null }
        $k = $parent
    }
    $k
}

function Save-CpBackup {
    <#  Write a backup and PROVE it was written. Returns the path, or $null.
        -RecordAsOriginal: only the apply path may pass this - without the gate,
        the restore script's pre-restore snapshot would define "original" as the
        already-modified state, permanently. #>
    param(
        [Parameter(Mandatory)] $State,
        [Parameter(Mandatory)][string] $Directory,
        [string] $Tag = '',
        [string] $InternalSuffix = '',
        [switch] $RecordAsOriginal
    )
    # -ErrorAction Stop on BOTH: Test-Path throws a NON-terminating error on an
    # illegal path and execution otherwise sails past the catch.
    try {
        if (-not (Test-Path $Directory -ErrorAction Stop)) {
            New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop | Out-Null
        }
    }
    catch {
        Write-Host "    BACKUP FAILED: cannot use the backup folder - $($_.Exception.Message)"
        return $null
    }

    # Internal snapshots carry a '~' marker no user tag can produce: the
    # safe-tag charset strips '~'. The first fix for the tag-collision audit
    # finding transformed reserved TAGS instead - which renamed the INTERNAL
    # pre-restore snapshot too, freeing it to appear as a restore candidate,
    # and a double-undo then restored the applied state from its own snapshot.
    $suffix = if ($InternalSuffix) { "_~$InternalSuffix" } else { ConvertTo-CpSafeTag $Tag }
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $path  = Join-Path $Directory ("state_{0}{1}.json" -f $stamp, $suffix)
    $n = 1
    while (Test-Path $path) { $path = Join-Path $Directory ("state_{0}{1}_{2}.json" -f $stamp, $suffix, $n); $n++ }

    try   { $State | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop }
    catch { Write-Host "    BACKUP FAILED: could not write $path - $($_.Exception.Message)"; return $null }

    if (-not (Test-Path $path)) { Write-Host "    BACKUP FAILED: $path is not there after writing it"; return $null }
    if ((Get-Item $path).Length -lt 200) { Write-Host "    BACKUP FAILED: $path is suspiciously small"; return $null }
    try {
        $back = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-CpStateShape -State $back)) { Write-Host "    BACKUP FAILED: $path parsed but is not usable"; return $null }
    }
    catch { Write-Host "    BACKUP FAILED: $path cannot be read back - $($_.Exception.Message)"; return $null }

    if ($RecordAsOriginal) {
        $original = Join-Path $Directory 'original-state.json'
        if (-not (Test-Path $original)) {
            try {
                Copy-Item -Path $path -Destination $original -ErrorAction Stop
                Write-Host '    original state preserved: original-state.json (written once, never overwritten)'
            }
            catch { Write-Host "    could not write original-state.json: $($_.Exception.Message)" }
        }
    }
    $path
}

function Get-CpBackups {
    param([Parameter(Mandatory)][string]$Directory)
    if (-not (Test-Path $Directory)) { return @() }
    @(Get-ChildItem -Path $Directory -Filter 'state_*.json' -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending)
}

function Get-CpRestoreCandidates {
    <#  Excludes exactly ONE kind of file: internal snapshots, whose suffix is
        the reserved '_~prerestore' marker (ConvertTo-CpSafeTag strips '~', so
        no user tag can produce it). Offering those makes a second undo
        re-apply what the first reversed.

        Backups tagged 'roundtrip' are NOT internal and are NOT excluded. The
        round trip's apply step writes one through the ordinary user-tag path,
        and the round trip's own undo step restores from that very file -
        "restoring" an exclusion for them here would break that undo into
        restoring stale state. On a PASS the round trip deletes the backups it
        caused; they record the PRE-apply state, so even a kept one is safe. #>
    param([Parameter(Mandatory)][string]$Directory)
    @(Get-CpBackups -Directory $Directory |
      Where-Object { $_.Name -notmatch '_~prerestore(_\d+)?\.json$' })
}

function Set-CpRegistryValue {
    <#  Write one value and read it back. $true only if the machine agrees. #>
    param([string]$Key, [string]$Name, $Value, [string]$Kind = 'DWord')
    try {
        if (-not (Test-Path $Key)) { New-Item -Path $Key -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $Key -Name $Name -Value $Value -PropertyType $Kind -Force -ErrorAction Stop | Out-Null
    }
    catch { Write-Host "      failed: $Name - $($_.Exception.Message)"; return $false }
    $check = Get-CpRegEntry -Key $Key -Name $Name
    if (-not $check.existed) { Write-Host "      failed: $Name did not stick"; return $false }
    if ([string]$check.value -ne [string]$Value) { Write-Host "      failed: $Name reads back as $($check.value)"; return $false }
    $true
}

function Remove-CpRegistryValue {
    <#  Return a value to genuinely absent. Key cleanup is a SEPARATE pass -
        see Remove-CpCreatedKeys - so that removing three values that share a
        key does not print two false "something else wrote here" warnings. #>
    param([string]$Key, [string]$Name)
    try { if (Test-Path $Key) { Remove-ItemProperty -Path $Key -Name $Name -Force -ErrorAction SilentlyContinue } }
    catch { Write-Host "      failed to remove $Name - $($_.Exception.Message)"; return $false }
    if ((Get-CpRegEntry -Key $Key -Name $Name).existed) { Write-Host "      failed: $Name is still present"; return $false }
    $true
}

function Remove-CpCreatedKeys {
    <#  Second pass of a restore: remove keys the APPLY created, walking from
        each leaf up to (but never including) the ancestor that already existed
        when the backup was taken. A key that still holds values or subkeys is
        left, with a neutral message. Returns the number of failures, so the
        caller can report them instead of printing a clean summary over them. #>
    param([Parameter(Mandatory)] $Entries)   # list of @{ Key; Ancestor }

    $failures = 0
    foreach ($e in ($Entries | Sort-Object { $_.Key.Length } -Descending)) {
        $k = $e.Key
        while ($k -and $e.Ancestor -and $k -ne $e.Ancestor -and $k.Length -gt $e.Ancestor.Length) {
            if (-not (Test-Path $k)) { $k = Split-Path -Parent $k; continue }
            try {
                $item = Get-Item $k -ErrorAction Stop
                # GetValueNames() reports a set (Default) value as '' - and it
                # COUNTS. An empty key returns an empty array, so there is
                # nothing to filter; filtering '' out dropped a set (Default)
                # and deleted a key that still held someone's data.
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

function Restore-CpState {
    <#  Put the TIER 1 settings back. Iterates the module's OWN allow-list, not
        the backup file's contents; foreign entries are Ignored, never written.
        Every write is read back. HKLM entries are Skipped (and named) when not
        elevated. Key cleanup runs as a second pass after all value work, and
        its failures are counted, not buried. #>
    param([Parameter(Mandatory)] $State)

    $elevated = Test-CpElevated
    $restored = 0; $skipped = 0; $failed = 0
    $skippedDetail = @(); $failedDetail = @(); $ignored = @()
    $keysToClean = New-Object System.Collections.Generic.List[object]

    foreach ($rule in $script:CpRegistry) {
        $k = "$($rule.Key)|$($rule.Name)"
        $entry = $null
        if ($State.registry -is [hashtable]) { if ($State.registry.ContainsKey($k)) { $entry = $State.registry[$k] } }
        elseif ($State.registry.PSObject.Properties[$k]) { $entry = $State.registry.$k }

        if ($null -eq $entry) { $skipped++; $skippedDetail += "$($rule.Name) (not in this backup)"; continue }
        if ($rule.Key -like 'HKLM*' -and -not $elevated) {
            $skipped++; $skippedDetail += "$($rule.Name) (machine-wide - needs administrator rights)"; continue
        }

        if (-not $entry.existed) {
            if (Remove-CpRegistryValue -Key $rule.Key -Name $rule.Name) {
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
            $kind = if ($entry.kind) { [string]$entry.kind } else { $rule.Kind }
            if (Set-CpRegistryValue -Key $rule.Key -Name $rule.Name -Value $entry.value -Kind $kind) { $restored++ }
            else { $failed++; $failedDetail += "$($rule.Name) (write did not stick)" }
        }
    }

    $keyFailures = 0
    if ($keysToClean.Count) { $keyFailures = Remove-CpCreatedKeys -Entries $keysToClean }

    if ($State.registry) {
        $names = if ($State.registry -is [hashtable]) { @($State.registry.Keys) } else { @($State.registry.PSObject.Properties.Name) }
        foreach ($n in $names) {
            $parts = $n -split '\|', 2
            if ($parts.Count -ne 2 -or -not (Get-CpRegistryRule -Key $parts[0] -Name $parts[1])) { $ignored += $n }
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
