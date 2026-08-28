<#
.SYNOPSIS
    Shared core for the update-distribution module. This is a LIBRARY.
    Dot-source it; running it directly does nothing but say so.

.DESCRIPTION
    Every script in this module reads and writes the same settings through the
    code in this file, so the checker, the applier and the undo cannot drift
    apart.

    -------------------------------------------------------------------------
    WHAT THIS MODULE TOUCHES, AND WHAT IT REFUSES TO
    -------------------------------------------------------------------------
    Touches:
      - one registry value, DODownloadMode, under the Delivery Optimization
        policy key
      - two built-in inbound firewall rules, by enabling or disabling them

    Deliberately does NOT touch:
      - the Delivery Optimization service (DoSvc) itself. Disabling it is the
        popular advice and it is wrong: Windows Update and the Microsoft Store
        use DoSvc to download, not merely to share. Setting the download mode
        to CdnOnly stops the sharing and leaves the downloading intact, which
        is the documented way to get this outcome.
      - BITS, wuauserv, UsoSvc or any other update service
      - the Delivery Optimization cache. It is managed by the service, it is
        cleaned up on its own schedule, and deleting it by hand only forces
        the machine to download again.
      - any deferral, pause or active-hours setting. Delaying updates is a
        separate decision with a security cost, and it does not belong in a
        module about peer distribution.

    -------------------------------------------------------------------------
    THE ONE CASE MODULE 01 NEVER HAD
    -------------------------------------------------------------------------
    On a default machine the Delivery Optimization policy key does not exist at
    all. Applying this module CREATES it.

    That means "undo" cannot mean "write the old value back", because there was
    no old value. It has to mean "delete the value, and delete the key too if we
    created it and nothing else has since been put in it". A restore that wrote
    a zero would leave the machine looking configured when it was never
    configured, and the two are not the same thing: an explicit 0 is a policy a
    future administrator has to reason about, while absent is absent.

    So the backup records, for every value, whether the value existed and
    whether its key existed. See Restore-UdState.

.NOTES
    Grounding:
      win32/desktop-src/delivery_optimization/downloadmode.md
        DownloadMode_CdnOnly: "This setting disables peer-to-peer caching but
        still allows Delivery Optimization to download content from Microsoft
        servers. This mode uses additional metadata provided by the Delivery
        Optimization cloud services for a peerless reliable and efficient
        download experience."
        DownloadMode_Lan: "This default operating mode for Delivery Optimization
        enables peer sharing on the same network"
      windows-itpro-docs/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services.md
        "LAN. Gets or sends updates and apps to PCs on the same NAT only."
      windows-itpro-docs/privacy/required-windows-diagnostic-data-events-and-fields-2004.md
        "The download mode used for this file download session (CdnOnly = 0,
        Lan = 1, Group = 2, Internet = 3, Simple = 99, Bypass = 100)."
      windows-itpro-docs/deployment/do/delivery-optimization-configure.md
        "Port 7680 is automatically registered and opened by the Delivery
        Optimization service. If you block port 7680, peer-to-peer functionality
        is disabled. However, devices can still download content using HTTP over
        port 80 or HTTPS over port 443."
#>

$script:UdSchemaVersion = 1
$script:UdPeerPort      = 7680

# ---------------------------------------------------------------------------
#  Load the modules we need BEFORE -WhatIf can get hold of them.
#
#  PowerShell auto-loads a module the first time one of its commands is called.
#  If that happens while -WhatIf is in effect, it narrates every alias the module
#  defines - twenty lines of "What if: Performing the operation Set Alias on
#  target Name: gcim" - and buries the actual preview underneath. The user came
#  for a list of what would change, and instead gets a wall of noise about
#  aliases nobody asked about.
#
#  Loading them here, with WhatIf explicitly off and restored afterwards, means
#  the preview shows only this module's own changes.
# ---------------------------------------------------------------------------
$script:UdSavedWhatIf = $WhatIfPreference
try {
    $WhatIfPreference = $false
    # -DisableNameChecking: the DeliveryOptimization module ships commands whose
    # verbs are not on Microsoft's approved list, and warns about it on every
    # import. That is a message for the module's authors, not for someone who
    # asked what a tweak would change.
    foreach ($m in @('CimCmdlets', 'NetTCPIP', 'NetSecurity', 'DeliveryOptimization')) {
        if (-not (Get-Module -Name $m)) {
            Import-Module $m -DisableNameChecking -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        }
    }
}
finally { $WhatIfPreference = $script:UdSavedWhatIf }

# ---------------------------------------------------------------------------
#  The allow-list. Restore validates against THIS, never against the backup
#  file's contents. A backup is data; data can be edited.
# ---------------------------------------------------------------------------
$script:UdRegistry = @(
    @{
        Key    = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
        Name   = 'DODownloadMode'
        Target = 0
        Kind   = 'DWord'
        Desc   = '0 = CdnOnly: still downloads from Microsoft, never shares to other machines'
    }
)

$script:UdFirewallRules = @(
    @{
        Name   = 'DeliveryOptimization-TCP-In'
        Target = $false
        Desc   = 'inbound TCP 7680 - lets other machines open a connection to this one'
    }
    @{
        Name   = 'DeliveryOptimization-UDP-In'
        Target = $false
        Desc   = 'inbound UDP 7680 - how other machines find this one'
    }
)

# Download mode numbers, for turning a reading into a sentence.
$script:UdModeNames = @{
    0   = 'CdnOnly  - Microsoft servers only, no peer sharing'
    1   = 'LAN      - shares with machines behind the same NAT (the default)'
    2   = 'Group    - shares within a configured group'
    3   = 'Internet - shares with machines on the internet'
    99  = 'Simple   - no peering, no DO cloud service'
    100 = 'Bypass   - uses BITS instead of Delivery Optimization'
}

function Get-UdModeName {
    param($Mode)
    if ($null -eq $Mode) { return 'unset  (Windows uses the default, LAN)' }
    # Audit finding: [int]$Mode throws on a non-numeric value (a REG_SZ written
    # by a GPO, or a doctored backup restored as String), after which every run
    # of the read-only checker printed two red .NET exceptions.
    $i = $null
    try { $i = [int]$Mode } catch { return "unrecognised value '$Mode' (not a number)" }
    if ($script:UdModeNames.ContainsKey($i)) { return $script:UdModeNames[$i] }
    "unrecognised value $i"
}

function Test-UdElevated {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { $false }
}

function Get-UdRegistryRule {
    <#  Allow-list lookup. Returns $null for anything this module does not own,
        which is how a tampered or foreign backup entry gets ignored instead of
        written. #>
    param([string]$Key, [string]$Name)
    foreach ($r in $script:UdRegistry) {
        if ($r.Key -eq $Key -and $r.Name -eq $Name) { return $r }
    }
    $null
}

function Get-UdFirewallRuleDef {
    param([string]$Name)
    foreach ($r in $script:UdFirewallRules) {
        if ($r.Name -eq $Name) { return $r }
    }
    $null
}

function Get-UdRegEntry {
    <#  Reads one value and, importantly, whether it and its key exist at all.
        "absent" is a state this module has to be able to restore to. #>
    param([string]$Key, [string]$Name)
    $keyExists = Test-Path $Key
    if (-not $keyExists) {
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

function Get-UdFirewallState {
    <#  Rules are looked up by Name, never by DisplayName: the display name is
        localised and would not match on a non-English Windows. #>
    param([string]$Name)
    try {
        $r = Get-NetFirewallRule -Name $Name -ErrorAction Stop
        [pscustomobject]@{
            present   = $true
            enabled   = ([string]$r.Enabled -eq 'True')
            direction = [string]$r.Direction
            profile   = [string]$r.Profile
            action    = [string]$r.Action
            display   = [string]$r.DisplayName
        }
    }
    catch {
        [pscustomobject]@{ present = $false; enabled = $null; direction = $null; profile = $null; action = $null; display = $null }
    }
}

function Get-UdRuntime {
    <#  What Delivery Optimization is actually doing, as opposed to what it is
        configured to do. Both matter, and they can disagree - a policy that the
        edition ignores shows up precisely here. #>
    $out = [pscustomobject]@{
        effectiveMode      = $null
        effectiveModeName  = 'unavailable'
        filesUploaded      = $null
        bytesUploaded      = $null
        bytesFromPeers     = $null
        numberOfPeers      = $null
        cacheBytes         = $null
        uploadRatePct      = $null
        available          = $false
    }
    try {
        $snap = Get-DeliveryOptimizationPerfSnap -ErrorAction Stop
        if ($snap) {
            $out.effectiveMode     = [string]$snap.DownloadMode
            $out.effectiveModeName = [string]$snap.DownloadMode
            $out.filesUploaded     = [int]   $snap.FilesUploaded
            $out.bytesUploaded     = [int64] $snap.TotalBytesUploaded
            $out.bytesFromPeers    = $null
            $out.numberOfPeers     = [int]   $snap.NumberOfPeers
            $out.cacheBytes        = [int64] $snap.CacheSizeBytes
            $out.uploadRatePct     = [int]   $snap.UploadRatePct
            $out.available         = $true
        }
    } catch { }
    $out
}

function Get-UdListener {
    <#  Is anything actually listening on the peer port right now? This is the
        claim the module is really making, so it is read rather than assumed. #>
    $res = [pscustomobject]@{ listening = $false; addresses = @(); process = $null; checked = $true }
    try {
        $conns = @(Get-NetTCPConnection -State Listen -ErrorAction Stop |
                   Where-Object { $_.LocalPort -eq $script:UdPeerPort })
        if ($conns.Count) {
            $res.listening = $true
            $res.addresses = @($conns | ForEach-Object { [string]$_.LocalAddress } | Sort-Object -Unique)
            $procId = $conns[0].OwningProcess
            $p = Get-Process -Id $procId -ErrorAction SilentlyContinue
            $res.process = if ($p) { "$($p.ProcessName) (pid $procId)" } else { "pid $procId" }
        }
    } catch { $res.checked = $false }
    $res
}

function Get-UdServiceState {
    param([string]$Name)
    try {
        $s = Get-Service -Name $Name -ErrorAction Stop
        $w = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
        [pscustomobject]@{
            present   = $true
            status    = [string]$s.Status
            startType = if ($w) { [string]$w.StartMode } else { 'unknown' }
            account   = if ($w) { [string]$w.StartName } else { 'unknown' }
        }
    }
    catch { [pscustomobject]@{ present = $false; status = $null; startType = $null; account = $null } }
}

function Get-UdState {
    <#  One complete reading. This is what gets backed up and what gets compared. #>
    $registry = @{}
    foreach ($r in $script:UdRegistry) {
        $registry["$($r.Key)|$($r.Name)"] = Get-UdRegEntry -Key $r.Key -Name $r.Name
    }

    $firewall = @{}
    foreach ($f in $script:UdFirewallRules) {
        $firewall[$f.Name] = Get-UdFirewallState -Name $f.Name
    }

    $services = @{}
    foreach ($n in @('DoSvc', 'BITS', 'wuauserv', 'UsoSvc')) {
        $services[$n] = Get-UdServiceState -Name $n
    }

    [pscustomobject]@{
        schemaVersion = $script:UdSchemaVersion
        takenAt       = (Get-Date).ToString('o')
        host          = $env:COMPUTERNAME
        user          = $env:USERNAME
        osBuild       = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).BuildNumber
        elevated      = (Test-UdElevated)
        registry      = $registry
        firewall      = $firewall
        services      = $services
        runtime       = Get-UdRuntime
        listener      = Get-UdListener
    }
}

function Test-UdStateShape {
    <#  Does this object look like something this module wrote? A restore driven
        by a file that is merely JSON-shaped is a restore that writes anything. #>
    param($State)
    if ($null -eq $State)                                    { return $false }
    if (-not $State.PSObject.Properties['schemaVersion'])    { return $false }
    # Module 04 audit finding 12, present here too: [int] on a non-numeric
    # schemaVersion throws instead of returning $false.
    $ver = $null
    try { $ver = [int]$State.schemaVersion } catch { return $false }
    if ($ver -ne $script:UdSchemaVersion)                     { return $false }
    if (-not $State.PSObject.Properties['registry'])         { return $false }
    if (-not $State.PSObject.Properties['firewall'])         { return $false }
    $true
}

function ConvertTo-UdSafeTag {
    param([string]$Tag)
    if ([string]::IsNullOrWhiteSpace($Tag)) { return '' }
    $clean = ($Tag -replace '[^\w\-]', '-')
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    "_$clean"
}

function Save-UdBackup {
    <#
    .SYNOPSIS
        Write a backup and PROVE it was written. Returns the path, or $null.
    .DESCRIPTION
        Module 01's audit found a backup routine that reported success without
        checking anything had reached the disk, after which the applier changed
        twenty settings believing an undo existed. This one writes the file,
        then reads it back, parses it, and confirms the parsed object still has
        the sections a restore needs. Anything less is a claim, not a backup.

        A caller that gets $null MUST NOT proceed to change anything.

    .PARAMETER RecordAsOriginal
        Permit this backup to become original-state.json, if that file does not
        exist yet. ONLY the apply path may pass this.

        This switch exists because of a real defect. Without it, the restore
        script's own pre-restore snapshot would create original-state.json when
        none existed - recording the CURRENT state as "original". Since that file
        is deliberately never overwritten, a machine that was already modified
        would have "how it looked before any of this" permanently defined as
        "how it looked after all of this", and "undo back to the original" would
        quietly restore to the applied state forever, with nothing to reveal it.

        The rule is: original-state.json may only be written by a script that is
        about to change something, from the reading it took beforehand.
    #>
    param(
        [Parameter(Mandatory)] $State,
        [Parameter(Mandatory)][string] $Directory,
        [string] $Tag = '',
        [string] $InternalSuffix = '',
        [switch] $RecordAsOriginal
    )

    # -ErrorAction Stop on BOTH calls. Test-Path throws a non-terminating error
    # on a path containing illegal characters, and with $ErrorActionPreference =
    # 'Continue' that error prints in red and execution carries on into the
    # catch-less path. The user then sees a raw .NET argument exception before
    # the friendly message, which is exactly the sort of output that makes people
    # assume something is broken beyond repair.
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
    $suffix = if ($InternalSuffix) { "_~$InternalSuffix" } else { ConvertTo-UdSafeTag $Tag }
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $path  = Join-Path $Directory ("state_{0}{1}.json" -f $stamp, $suffix)
    # One-second stamp resolution: two backups in the same second would
    # otherwise silently overwrite one another.
    $n = 1
    while (Test-Path $path) { $path = Join-Path $Directory ("state_{0}{1}_{2}.json" -f $stamp, $suffix, $n); $n++ }

    try   { $State | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop }
    catch { Write-Host "    BACKUP FAILED: could not write $path - $($_.Exception.Message)"; return $null }

    if (-not (Test-Path $path)) { Write-Host "    BACKUP FAILED: $path is not there after writing it"; return $null }

    $len = (Get-Item $path).Length
    if ($len -lt 200) { Write-Host "    BACKUP FAILED: $path is only $len bytes"; return $null }

    try {
        $back = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-UdStateShape -State $back)) {
            Write-Host "    BACKUP FAILED: $path parsed but is not a usable state file"
            return $null
        }
    }
    catch {
        Write-Host "    BACKUP FAILED: $path cannot be read back - $($_.Exception.Message)"
        return $null
    }

    # Write-once record of the machine before this module ever ran. Only the
    # apply path is allowed to establish it - see the -RecordAsOriginal notes.
    if ($RecordAsOriginal) {
        $original = Join-Path $Directory 'original-state.json'
        if (-not (Test-Path $original)) {
            try {
                Copy-Item -Path $path -Destination $original -ErrorAction Stop
                Write-Host "    original state preserved: original-state.json (written once, never overwritten)"
            }
            catch {
                Write-Host "    WARNING: could not write original-state.json - $($_.Exception.Message)"
                Write-Host "             The apply will proceed, but 'UNDO back to the original' will"
                Write-Host "             not work until a run succeeds in writing that file. The"
                Write-Host "             ordinary backups still cover 'UNDO everything'."
            }
        }
    }

    $path
}

function Get-UdBackups {
    param([Parameter(Mandatory)][string]$Directory)
    if (-not (Test-Path $Directory)) { return @() }
    @(Get-ChildItem -Path $Directory -Filter 'state_*.json' -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending)
}

function Get-UdRestoreCandidates {
    <#  Excludes two kinds of internal snapshot, matched by their exact reserved
        suffixes (ConvertTo-UdSafeTag prevents a user tag from producing either):
          _pre-restore  taken by the undo before it runs; offering these made a
                        second undo re-apply what the first one reversed
          _roundtrip    taken by the round-trip test's apply step; after
                        apply-then-roundtrip these record the APPLIED state, so
                        the default undo restored the applied state and reported
                        success while undoing nothing (module 04 audit) #>
    param([Parameter(Mandatory)][string]$Directory)
    @(Get-UdBackups -Directory $Directory |
      Where-Object { $_.Name -notmatch '_~prerestore(_\d+)?\.json$' })
}

function Set-UdRegistryValue {
    <#  Write one value and read it back. Returns $true only if the machine
        agrees the write happened. #>
    param([string]$Key, [string]$Name, $Value, [string]$Kind = 'DWord')
    try {
        if (-not (Test-Path $Key)) { New-Item -Path $Key -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $Key -Name $Name -Value $Value -PropertyType $Kind -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "      failed: $Name - $($_.Exception.Message)"
        return $false
    }
    $check = Get-UdRegEntry -Key $Key -Name $Name
    if (-not $check.existed) { Write-Host "      failed: $Name did not stick"; return $false }
    if ([string]$check.value -ne [string]$Value) {
        Write-Host "      failed: $Name reads back as $($check.value), not $Value"
        return $false
    }
    $true
}

function Remove-UdRegistryValue {
    <#  Return a value to genuinely absent, and remove the key as well if this
        module created it and nothing else has been added to it since. #>
    param([string]$Key, [string]$Name, [bool]$RemoveKeyIfEmpty)
    try {
        if (Test-Path $Key) {
            Remove-ItemProperty -Path $Key -Name $Name -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Host "      failed to remove $Name - $($_.Exception.Message)"
        return $false
    }

    $check = Get-UdRegEntry -Key $Key -Name $Name
    if ($check.existed) { Write-Host "      failed: $Name is still present"; return $false }

    if ($RemoveKeyIfEmpty -and (Test-Path $Key)) {
        try {
            $item = Get-Item $Key -ErrorAction Stop
            # GetValueNames() reports the (Default) value as ''. It counts: a key
            # whose only content is a default value set by someone else is NOT
            # empty, and deleting it would destroy that value (audit finding).
            $otherValues = @($item.GetValueNames())
            $subKeys     = @($item.GetSubKeyNames())
            if ($otherValues.Count -eq 0 -and $subKeys.Count -eq 0) {
                Remove-Item -Path $Key -Force -ErrorAction Stop
            }
            else {
                Write-Host "      key kept: something else has written to it ($($otherValues.Count) value(s), $($subKeys.Count) subkey(s))"
            }
        }
        catch { Write-Host "      key kept: $($_.Exception.Message)" }
    }
    $true
}

function Set-UdFirewallRuleEnabled {
    param([string]$Name, [bool]$Enabled)
    try {
        Set-NetFirewallRule -Name $Name -Enabled $(if ($Enabled) { 'True' } else { 'False' }) -ErrorAction Stop
    }
    catch {
        Write-Host "      failed: $Name - $($_.Exception.Message)"
        return $false
    }
    $check = Get-UdFirewallState -Name $Name
    if (-not $check.present)            { Write-Host "      failed: $Name disappeared"; return $false }
    if ($check.enabled -ne $Enabled)    { Write-Host "      failed: $Name reads back as enabled=$($check.enabled)"; return $false }
    $true
}

function Restore-UdState {
    <#
    .SYNOPSIS
        Put the machine back to a recorded state. Reports honestly.
    .DESCRIPTION
        Iterates the module's OWN allow-list, not the backup's contents, and
        looks each entry up in the backup. An entry in the file that this module
        does not own is counted as Ignored and never written - which is what
        stops an edited backup file from becoming an arbitrary registry writer.

        Every write is read back. A write that did not stick is counted as
        Failed, never as Restored.
    #>
    param([Parameter(Mandatory)] $State)

    $restored = 0; $skipped = 0; $failed = 0
    $skippedDetail = @(); $failedDetail = @(); $ignored = @()

    # --- registry -----------------------------------------------------------
    foreach ($rule in $script:UdRegistry) {
        $k = "$($rule.Key)|$($rule.Name)"
        $entry = $null
        if ($State.registry -and $State.registry.PSObject.Properties[$k]) { $entry = $State.registry.$k }
        elseif ($State.registry -is [hashtable] -and $State.registry.ContainsKey($k)) { $entry = $State.registry[$k] }

        if ($null -eq $entry) {
            $skipped++; $skippedDetail += "$($rule.Name) (not in this backup)"
            continue
        }

        if (-not $entry.existed) {
            # It was absent. Absent is what it must go back to.
            $removeKey = (-not $entry.keyExisted)
            if (Remove-UdRegistryValue -Key $rule.Key -Name $rule.Name -RemoveKeyIfEmpty $removeKey) { $restored++ }
            else { $failed++; $failedDetail += "$($rule.Name) (could not remove)" }
        }
        else {
            # Audit finding: Key and Name came from the allow-list but Value and
            # Kind came straight from the JSON - an edited backup could restore
            # DODownloadMode=3 (Internet peering, WORSE than the default) or
            # write it as a REG_SZ, and be reported as restored. Both are now
            # validated against what this module knows to be legitimate.
            $vOk = $false
            try { $vOk = ($script:UdModeNames.ContainsKey([int]$entry.value)) } catch { $vOk = $false }
            $kOk = ((-not $entry.kind) -or ([string]$entry.kind -eq $rule.Kind))
            if (-not $vOk -or -not $kOk) {
                $failed++
                $failedDetail += "$($rule.Name) (backup holds an illegitimate value '$($entry.value)' kind '$($entry.kind)' - refused)"
            }
            elseif (Set-UdRegistryValue -Key $rule.Key -Name $rule.Name -Value ([int]$entry.value) -Kind $rule.Kind) { $restored++ }
            else { $failed++; $failedDetail += "$($rule.Name) (write did not stick)" }
        }
    }

    # Anything in the file we do not own is reported, not obeyed.
    if ($State.registry) {
        $names = @()
        if ($State.registry -is [hashtable]) { $names = @($State.registry.Keys) }
        else { $names = @($State.registry.PSObject.Properties.Name) }
        foreach ($n in $names) {
            $parts = $n -split '\|', 2
            if ($parts.Count -ne 2 -or -not (Get-UdRegistryRule -Key $parts[0] -Name $parts[1])) { $ignored += $n }
        }
    }

    # --- firewall -----------------------------------------------------------
    foreach ($rule in $script:UdFirewallRules) {
        $entry = $null
        if ($State.firewall -and $State.firewall.PSObject.Properties[$rule.Name]) { $entry = $State.firewall.$($rule.Name) }
        elseif ($State.firewall -is [hashtable] -and $State.firewall.ContainsKey($rule.Name)) { $entry = $State.firewall[$rule.Name] }

        if ($null -eq $entry) {
            $skipped++; $skippedDetail += "$($rule.Name) (not in this backup)"
            continue
        }
        if (-not $entry.present) {
            $skipped++; $skippedDetail += "$($rule.Name) (rule did not exist when the backup was taken)"
            continue
        }
        if ($null -eq $entry.enabled) {
            $skipped++; $skippedDetail += "$($rule.Name) (state was unreadable when the backup was taken)"
            continue
        }
        $now = Get-UdFirewallState -Name $rule.Name
        if (-not $now.present) {
            $failed++; $failedDetail += "$($rule.Name) (rule is not on this machine any more)"
            continue
        }
        if (Set-UdFirewallRuleEnabled -Name $rule.Name -Enabled ([bool]$entry.enabled)) { $restored++ }
        else { $failed++; $failedDetail += "$($rule.Name) (could not set)" }
    }

    [pscustomobject]@{
        Restored      = $restored
        Skipped       = $skipped
        Failed        = $failed
        SkippedDetail = $skippedDetail
        FailedDetail  = $failedDetail
        Ignored       = $ignored
    }
}

if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.\s') {
    Write-Host ''
    Write-Host '  _Common.ps1 is shared code, not a script to run.'
    Write-Host '  Use the numbered .cmd files in this folder instead.'
    Write-Host ''
}
