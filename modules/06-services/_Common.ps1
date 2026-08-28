<#
.SYNOPSIS
    Shared core for the services module. This is a LIBRARY - dot-source it.

.DESCRIPTION
    Three cumulative profiles, defined as DATA in profiles.json so they can be
    reviewed and diffed without reading any PowerShell:

      LIGHT     unused hardware, OEM bloat, third-party updaters, telemetry
      MODERATE  light + remote access, cloud sync, diagnostics, discovery
      SUPER     moderate + printing, Bluetooth, Store surface, OEM stack,
                legacy protocols and enterprise plumbing

    -------------------------------------------------------------------------
    THE THREE THINGS THAT MAKE THIS SAFE RATHER THAN RECKLESS
    -------------------------------------------------------------------------
    1. A NEVER-TOUCH LIST enforced in code, not merely in the data. If a
       profile ever names a service on that list, the apply REFUSES - it does
       not skip the entry and carry on. The list covers the RPC/COM substrate,
       sign-in, the security stack, the network substrate, and UAC elevation
       itself.

    2. A LOCKOUT-RISK LIST that no profile may contain at all. Disabling
       Windows Hello on a machine that signs in with a PIN can leave you
       unable to log in, and a backup file on a disk you cannot reach is not
       a rescue.

    3. DEPENDENCY VALIDATION COMPUTED AT APPLY TIME from the live machine,
       never read from the profile. Before a single value is written, the plan
       is checked: does anything that stays enabled depend on something this
       profile disables? If so, the apply refuses and names both services.
       A dependency break does not fail when you make it - it fails at the
       next boot, which is the worst possible time to discover it.

    On top of that: every start type on the machine is backed up (not only the
    ones being changed), the undo is proved by execution, and services are
    only ever set to DISABLED (4) - nothing is deleted, ever.

.NOTES
    Drivers are out of scope by construction: only Win32 service types are
    enumerated, so a kernel driver cannot be reached by any profile.
#>

$script:SvcSchemaVersion = 1
$script:SvcDisabled      = 4        # SERVICE_DISABLED
# 80 = SERVICE_USER_OWN_PROCESS. Its absence meant one real service on this
# machine (CredentialEnrollmentManagerUserSvc) was neither backed up nor
# restorable, which made the 'every Win32 service' claim false by one.
$script:SvcWin32Types    = @(16, 32, 80, 96, 272, 288)
$script:SvcRoot          = 'HKLM:\SYSTEM\CurrentControlSet\Services'
$script:SvcStartNames    = @{ 0 = 'boot'; 1 = 'system'; 2 = 'automatic'; 3 = 'manual'; 4 = 'disabled' }

# Preload before -WhatIf can narrate module aliases (R2.9).
$script:SvcSavedWhatIf = $WhatIfPreference
try {
    $WhatIfPreference = $false
    foreach ($m in @('CimCmdlets')) {
        if (-not (Get-Module -Name $m)) { Import-Module $m -ErrorAction SilentlyContinue -WarningAction SilentlyContinue }
    }
}
finally { $WhatIfPreference = $script:SvcSavedWhatIf }

function Test-SvcElevated {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SvcProfileData {
    <#  Load profiles.json. A malformed or missing file is fatal, not a
        silent empty profile - an empty profile would "succeed" while doing
        nothing, which is the failure this project keeps finding. #>
    param([string]$Directory)
    $path = Join-Path $Directory 'profiles.json'
    if (-not (Test-Path $path)) { throw "profiles.json is missing from $Directory" }
    try { $doc = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "profiles.json will not parse: $($_.Exception.Message)" }
    if (($doc.schemaVersion -as [int]) -ne $script:SvcSchemaVersion) {
        throw "profiles.json has schemaVersion $($doc.schemaVersion); this module speaks $script:SvcSchemaVersion"
    }
    foreach ($t in 'light', 'moderate', 'super') {
        if ($null -eq $doc.profiles.$t) { throw "profiles.json has no '$t' profile" }
    }

    # The safety lists are DATA, and until this check existed nothing
    # validated them. A JSON typo that renamed or nulled 'never' made
    # Test-SvcProfileLegal iterate an empty collection, report zero problems,
    # and let the apply disable RpcSs. The entire enforcement layer could
    # vanish silently. It cannot now: a profile set without plausible safety
    # lists does not load at all.
    foreach ($listName in 'never', 'lockoutRisk') {
        $list = @($doc.$listName)
        if ($null -eq $doc.$listName -or $list.Count -eq 0) {
            throw "profiles.json has no '$listName' list - refusing to load. That list is the only thing standing between a profile and a service that must never be disabled."
        }
        foreach ($e in $list) {
            if ([string]::IsNullOrWhiteSpace([string]$e.service)) {
                throw "profiles.json has an entry in '$listName' with no service name - refusing to load, because a malformed entry silently truncates the list as it is built."
            }
        }
    }
    # Floor values, not exact counts: the lists may grow. What they may not do
    # is quietly shrink to nothing.
    if (@($doc.never).Count -lt 30) { throw "profiles.json declares only $(@($doc.never).Count) never-touch services; that is too few to be a real list" }
    if (@($doc.lockoutRisk).Count -lt 3) { throw "profiles.json declares only $(@($doc.lockoutRisk).Count) lockout-risk services; that is too few to be a real list" }

    # Anything on the never or lockout lists must not also appear in a
    # profile. Checked at load, so a hand-edited file cannot get past it.
    $guarded = @{}
    foreach ($listName in 'never', 'lockoutRisk') {
        foreach ($e in $doc.$listName) { $guarded[([string]$e.service).ToLower()] = $listName }
    }
    foreach ($t in 'light', 'moderate', 'super') {
        foreach ($e in $doc.profiles.$t.services) {
            $k = ([string]$e.service).ToLower()
            if ($guarded.ContainsKey($k)) {
                throw "profiles.json lists $($e.service) in profile '$t' AND on the $($guarded[$k]) list - refusing to load"
            }
        }
    }
    $doc
}

function Get-SvcProfileNames {
    <#  Cumulative by design: moderate includes light, super includes both.
        Returned as a de-duplicated, order-preserving list. #>
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)][string] $Profile)
    $order = @('light', 'moderate', 'super')
    $idx = [array]::IndexOf($order, $Profile.ToLower())
    if ($idx -lt 0) { throw "unknown profile '$Profile' - use light, moderate or super" }
    $names = New-Object System.Collections.Generic.List[string]
    $seen  = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    for ($i = 0; $i -le $idx; $i++) {
        foreach ($e in $Data.profiles.($order[$i]).services) {
            if ($seen.Add($e.service)) { $names.Add($e.service) }
        }
    }
    $names
}

function Get-SvcProfileEntry {
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)][string] $Name)
    foreach ($t in 'light', 'moderate', 'super') {
        foreach ($e in $Data.profiles.$t.services) {
            if ($e.service -eq $Name) { return $e }
        }
    }
    $null
}

function Get-SvcLiveMap {
    <#  One WMI query for the whole machine, cached.

        This exists because the first version asked Win32_Service for each
        service individually - 283 separate WMI queries - and the self-test,
        which reads the whole state several times, took minutes. Correct and
        unusably slow is still a defect: a safety check nobody waits for is a
        safety check nobody runs.

        Call with -Refresh after writing, so a re-read sees the new state. #>
    param([switch]$Refresh)
    if ($Refresh -or $null -eq $script:SvcLiveMap) {
        $script:SvcLiveMap = @{}
        try {
            foreach ($w in (Get-CimInstance Win32_Service -ErrorAction Stop)) {
                $script:SvcLiveMap[$w.Name.ToLower()] = $w
            }
        } catch { }
    }
    $script:SvcLiveMap
}

function Get-SvcEntry {
    <#  One service as this module sees it: the Start value it changes, plus
        the live picture and the dependency edges the safety check needs. #>
    param([Parameter(Mandatory)][string]$Name)
    $key = Join-Path $script:SvcRoot $Name
    $out = [ordered]@{
        name = $Name; existed = $false; start = $null; serviceType = $null
        state = $null; account = $null; displayName = $null; dependsOn = @()
    }
    if (Test-Path $key) {
        $p = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        $type = $p.Type -as [int]
        # Drivers are out of scope by construction.
        if ($null -ne $type -and $script:SvcWin32Types -contains $type) {
            $out.existed     = $true
            $out.start       = $p.Start -as [int]
            $out.serviceType = $type
            $out.dependsOn   = @([string[]]$p.DependOnService | Where-Object { $_ })
            $out.displayName = [string]$p.DisplayName
            # A key absent from the map means either 'not a registered
            # service' (per-user templates never appear) or 'we just wrote to
            # it and dropped the stale row'. Both leave state null, which the
            # callers already handle.
            $w = (Get-SvcLiveMap)[$Name.ToLower()]
            if ($w) {
                $out.state       = [string]$w.State
                $out.account     = [string]$w.StartName
                $out.displayName = [string]$w.DisplayName
            }
        }
    }
    [pscustomobject]$out
}

function Get-SvcAllWin32 {
    <#  Every Win32 service on the machine. The dependency check needs all of
        them, not only the ones a profile names. #>
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($k in (Get-ChildItem $script:SvcRoot -ErrorAction SilentlyContinue)) {
        $e = Get-SvcEntry -Name $k.PSChildName
        if ($e.existed) { $out.Add($e) }
    }
    $out
}

function Get-SvcAllDependents {
    <#  EVERY registry entry that declares a DependOnService - services AND
        DRIVERS.

        The module only ever WRITES to Win32 service types, and treats that as
        a safety property. It is also a hole: a kernel driver can declare a
        dependency on a service, and if that service is disabled the driver
        fails to load. The audit found a live example on this machine -
        applockerfltr (a driver) depends on AppIDSvc (a service that was in a
        profile). Filtering drivers out of the dependency scan made that edge
        invisible. This function does not filter. #>
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($k in (Get-ChildItem $script:SvcRoot -ErrorAction SilentlyContinue)) {
        $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $p.Type) { continue }
        $deps = @([string[]]$p.DependOnService | Where-Object { $_ })
        if (-not $deps.Count) { continue }
        $type = $p.Type -as [int]
        $out.Add([pscustomobject]@{
            name      = $k.PSChildName
            start     = $p.Start -as [int]
            type      = $type
            isDriver  = ($script:SvcWin32Types -notcontains $type)
            dependsOn = $deps
        })
    }
    $out
}

function Get-SvcState {
    <#  The backup subject: EVERY Win32 service's start type, not only the
        ones a profile touches. A backup that only covers the planned changes
        cannot restore a machine where something else moved in between. #>
    $services = @{}
    foreach ($e in (Get-SvcAllWin32)) { $services[$e.name] = $e }
    [pscustomobject]@{
        schemaVersion = $script:SvcSchemaVersion
        takenAt       = (Get-Date).ToString('o')
        elevated      = (Test-SvcElevated)
        services      = $services
    }
}

function Get-SvcEntries {
    <#  Enumerate a state's services as name/value pairs, whichever shape the
        state is in.

        This exists because of a real defect the self-test caught: a live
        Get-SvcState holds a HASHTABLE, while the same state read back from
        JSON is a PSCustomObject. Iterating .PSObject.Properties works for the
        second and silently yields Count/Keys/Values for the first - so a
        comparison of two live states compared NOTHING and reported PASS.
        That is this project's most-repeated defect class, and it reappeared
        here in a new disguise. #>
    param($Services)
    if ($null -eq $Services) { return @() }
    if ($Services -is [System.Collections.IDictionary]) {
        return @($Services.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Value = $Services[$_] } })
    }
    @($Services.PSObject.Properties | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Value = $_.Value } })
}

function Get-SvcEntryByName {
    param($Services, [string]$Name)
    if ($null -eq $Services) { return $null }
    if ($Services -is [System.Collections.IDictionary]) { return $Services[$Name] }
    $p = $Services.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

function Test-SvcStateShape {
    param([object]$State)
    if ($null -eq $State) { return $false }
    $sv = $null
    try { $sv = $State.schemaVersion -as [int] } catch { return $false }
    if ($sv -ne $script:SvcSchemaVersion) { return $false }
    if ($null -eq $State.PSObject.Properties['services'] -or $null -eq $State.services) { return $false }
    # A state file with no services is shaped like a backup and is not one.
    ((Get-SvcEntries -Services $State.services).Count -gt 0)
}

function Test-SvcValidStart {
    <#  A SERVICE start type is 2, 3 or 4. 0 and 1 are DRIVER start types: a
        backup that would set a service to boot-start is doctored or corrupt.
        Explicit null guard first - $null -as [int] is 0, which would sail
        through a naive range check. #>
    param($Value)
    if ($null -eq $Value) { return $false }
    $v = $Value -as [int]
    ($null -ne $v -and $v -ge 2 -and $v -le 4)
}

function Test-SvcProfileLegal {
    <#  Enforce the never-touch and lockout lists IN CODE.

        This deliberately REFUSES rather than filtering. A profile that names
        a forbidden service is a profile someone edited without understanding
        it, and quietly dropping the entry would hide that. #>
    param([Parameter(Mandatory)] $Data, [Parameter(Mandatory)] $Names)
    $problems = New-Object System.Collections.Generic.List[string]
    $never = @{}
    foreach ($n in $Data.never) { $never[$n.service.ToLower()] = $n.reason }
    $lock = @{}
    foreach ($n in $Data.lockoutRisk) { $lock[$n.service.ToLower()] = $n.reason }
    foreach ($n in $Names) {
        $k = $n.ToLower()
        if ($never.ContainsKey($k)) { $problems.Add("$n is on the NEVER-TOUCH list: $($never[$k])") }
        if ($lock.ContainsKey($k))  { $problems.Add("$n is on the LOCKOUT-RISK list: $($lock[$k])") }
    }
    $problems
}

function Test-SvcDependencySafety {
    <#  THE check. Computed from the LIVE machine every time, never read from
        the profile: does anything that stays enabled depend on something this
        plan disables?

        A dependency break does not announce itself when you make it. It
        announces itself at the next boot. #>
    param([Parameter(Mandatory)] $Names)
    $disable = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($n in $Names) { [void]$disable.Add($n) }

    $problems = New-Object System.Collections.Generic.List[string]
    # Get-SvcAllDependents, not Get-SvcAllWin32: DRIVERS declare dependencies
    # on services too, and a driver whose service dependency is unmet fails to
    # load. Filtering them out hid a real edge on this machine.
    foreach ($s in (Get-SvcAllDependents)) {
        if ($disable.Contains($s.name)) { continue }        # being disabled itself
        if ($s.start -eq $script:SvcDisabled) { continue }  # already disabled
        $what = if ($s.isDriver) { 'DRIVER' } else { 'service' }
        foreach ($dep in $s.dependsOn) {
            # Load-order GROUP dependencies are prefixed '+' and can never name
            # a service. Skip them rather than reporting a phantom.
            if ($dep.StartsWith('+')) { continue }
            if ($disable.Contains($dep)) {
                $problems.Add(("{0} {1} (start {2}) stays enabled but depends on {3}, which this profile disables" -f $what, $s.name, $s.start, $dep))
            }
        }
    }
    $problems
}

function Get-SvcRealityWarnings {
    <#  A profile is a policy; this machine is a fact. Where the two disagree,
        say so BEFORE writing anything, naming the evidence. These are
        warnings, not refusals - the owner may genuinely want the trade. #>
    param([Parameter(Mandatory)] $Names)
    $warn = New-Object System.Collections.Generic.List[string]
    $has = { param($n) $Names -contains $n }

    if (& $has 'bthserv') {
        $bt = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })
        if ($bt.Count) { $warn.Add("Bluetooth: $($bt.Count) device(s) are present and working. Disabling bthserv ends Bluetooth on this machine.") }
    }
    if (& $has 'Spooler') {
        $pr = @(Get-Printer -ErrorAction SilentlyContinue)
        if ($pr.Count) { $warn.Add("Printing: $($pr.Count) printer(s) installed, including '$($pr[0].Name)'. Disabling Spooler removes printing entirely - including Microsoft Print to PDF.") }
    }
    if (& $has 'WSearch') {
        $warn.Add("Search: disabling WSearch stops Start-menu and File Explorer content indexing. Search still works, but becomes noticeably slower. This is the most user-visible entry in the SUPER profile.")
    }
    # Added after FrameServer was disabled on a machine with two working cameras
    # and the owner found the camera dead - having first tried the privacy
    # slider, which grants PERMISSION and cannot start a disabled service.
    # "Lets multiple apps share the camera" undersold it: without FrameServer no
    # app gets the camera at all.
    if ((& $has 'FrameServer') -or (& $has 'FrameServerMonitor')) {
        $cams = @(Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })
        if ($cams.Count) {
            $ir = @($cams | Where-Object { $_.FriendlyName -match 'IR|Infrared' })
            $msg = "Camera: $($cams.Count) working camera(s) present. Disabling FrameServer ends camera access for EVERY app - Teams, Zoom, browser video calls and the Camera app. The privacy slider will still say Allow; it grants permission, it cannot start a disabled service."
            if ($ir.Count) { $msg += " One is an IR camera, which is what Windows Hello face sign-in uses." }
            $warn.Add($msg)
        }
    }
    if (& $has 'CaptureService') {
        $warn.Add("Screen capture: disabling CaptureService breaks Win+Shift+S and screen capture in Store apps, silently - no error, the overlay simply never appears.")
    }
    if ((& $has 'WwanSvc') -or (& $has 'QServiceEM05G')) {
        $cell = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceDescription -match 'WWAN|Mobile|Quectel' -and $_.Status -eq 'Up' })
        if ($cell.Count) { $warn.Add("Cellular: a WWAN adapter is UP. This profile disables the cellular stack.") }
    }
    if (& $has 'TermService') {
        $rdp = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -ErrorAction SilentlyContinue).fDenyTSConnections
        if ($rdp -eq 0) { $warn.Add("Remote Desktop: RDP is ENABLED on this machine (fDenyTSConnections=0) and this profile disables it. You would lose remote access - do not apply this over an RDP session.") }
    }
    if (& $has 'Netlogon') {
        if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
            $warn.Add("Domain: this machine IS domain-joined and the profile disables Netlogon. Do not apply - domain authentication would break.")
        }
    }
    if (& $has 'seclogon') { $warn.Add("Secondary Logon: 'run as a different user' will stop working.") }
    if (& $has 'vds')      { $warn.Add("Virtual Disk: Disk Management and diskpart need this service; re-enable it before partitioning work.") }
    $warn
}

function ConvertTo-SvcSafeTag {
    param([string]$Tag)
    if (-not $Tag) { return '' }
    $safe = ($Tag -replace '[^A-Za-z0-9-]', '')
    if ($safe.Length -gt 24) { $safe = $safe.Substring(0, 24) }
    if ($safe) { "_$safe" } else { '' }
}

function Save-SvcBackup {
    <#  Verified or it did not happen. Internal snapshots carry '_~', which
        the safe-tag charset cannot produce. #>
    param(
        [Parameter(Mandatory)] $State,
        [Parameter(Mandatory)][string] $Directory,
        [string] $Tag = '', [string] $InternalSuffix = '', [switch] $RecordAsOriginal
    )
    try {
        if (-not (Test-Path $Directory -ErrorAction Stop)) {
            New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop | Out-Null
        }
    }
    catch { Write-Host "    BACKUP FAILED: cannot use the backup folder - $($_.Exception.Message)"; return $null }

    $suffix = if ($InternalSuffix) { "_~$InternalSuffix" } else { ConvertTo-SvcSafeTag $Tag }
    $stamp  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $path   = Join-Path $Directory ("state_{0}{1}.json" -f $stamp, $suffix)
    $n = 1
    while (Test-Path $path) { $path = Join-Path $Directory ("state_{0}{1}_{2}.json" -f $stamp, $suffix, $n); $n++ }

    try   { $State | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop }
    catch { Write-Host "    BACKUP FAILED: could not write $path - $($_.Exception.Message)"; return $null }

    if (-not (Test-Path $path)) { Write-Host "    BACKUP FAILED: $path is not there after writing it"; return $null }
    if ((Get-Item $path).Length -lt 500) { Write-Host "    BACKUP FAILED: $path is suspiciously small for a full service inventory"; return $null }
    try {
        $back = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-SvcStateShape -State $back)) { Write-Host "    BACKUP FAILED: $path parsed but is not usable"; return $null }
        # Count the entries, do not trust the byte size. A truncated file with
        # three services passed the old size floor and the shape check, and
        # would have restored three services while reporting success.
        $wrote = (Get-SvcEntries -Services $State.services).Count
        $read  = (Get-SvcEntries -Services $back.services).Count
        if ($read -ne $wrote) {
            Write-Host "    BACKUP FAILED: $path holds $read services, but $wrote were written"
            return $null
        }
    }
    catch { Write-Host "    BACKUP FAILED: $path cannot be read back - $($_.Exception.Message)"; return $null }

    if ($RecordAsOriginal) {
        $original = Join-Path $Directory 'original-state.json'
        if (-not (Test-Path $original)) {
            try { Copy-Item -Path $path -Destination $original -ErrorAction Stop
                  Write-Host '    original state preserved: original-state.json (written once, never overwritten)' }
            catch { Write-Host "    could not write original-state.json: $($_.Exception.Message)" }
        }
    }
    $path
}

function Get-SvcBackups {
    param([Parameter(Mandatory)][string]$Directory)
    if (-not (Test-Path $Directory)) { return @() }
    @(Get-ChildItem -Path $Directory -Filter 'state_*.json' -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending)
}

function Get-SvcRestoreCandidates {
    <#  Excludes exactly one kind of file: internal '_~prerestore' snapshots. #>
    param([Parameter(Mandatory)][string]$Directory)
    @(Get-SvcBackups -Directory $Directory | Where-Object { $_.Name -notmatch '_~prerestore(_\d+)?\.json$' })
}

function Set-SvcStart {
    <#  Write one Start value and read it back. $true only if the machine agrees. #>
    param([string]$Name, [int]$Value)
    $key = Join-Path $script:SvcRoot $Name
    try { Set-ItemProperty -Path $key -Name Start -Value $Value -Type DWord -ErrorAction Stop }
    catch { Write-Host "      failed: $Name - $($_.Exception.Message)"; return $false }
    $check = (Get-ItemProperty -Path $key -Name Start -ErrorAction SilentlyContinue).Start -as [int]
    if ($check -ne $Value) { Write-Host "      failed: $Name reads back $check, wanted $Value"; return $false }
    # The live map's STATE column is now stale for this service. Patch that
    # one entry rather than dropping the whole map: dropping it forced a full
    # WMI rebuild (~730 ms) on the next read, and the restore reads on every
    # iteration - projected at over two minutes for a SUPER undo. A safety
    # step nobody waits for is a safety step nobody runs.
    if ($null -ne $script:SvcLiveMap) {
        $k = $Name.ToLower()
        if ($script:SvcLiveMap.ContainsKey($k)) { [void]$script:SvcLiveMap.Remove($k) }
    }
    $true
}

$script:SvcUserInstanceTypes = @(208, 224)   # 0xD0 / 0xE0 - per-user service INSTANCES

function Restore-SvcUserInstances {
    <#
    .SYNOPSIS
        After restoring templates, put their live per-user INSTANCES back too.

    .DESCRIPTION
        Some services are per-user: a TEMPLATE (type 80/96) from which Windows
        stamps a per-session INSTANCE (type 208/224) named <Template>_<suffix>.
        This module writes only to templates, which is what Microsoft's guidance
        says to do - and for the APPLY that is right, because the instance is
        recreated from the template at the next sign-in anyway.

        For the UNDO it is wrong, and it made the undo quietly incomplete.
        Restoring the template does NOT re-enable the copy already running in
        this session, so the feature stays broken until the user signs out - and
        the undo reports success either way. That is exactly what happened with
        CaptureService: the template was put back, Win+Shift+S stayed dead, and
        the only clue was that nothing happened when you pressed it.

        Instance types are deliberately NOT in $script:SvcWin32Types. Templates
        remain the only thing this module chooses; instances are only ever
        dragged along to match the template that was just restored. The
        never-touch and lockout-risk lists are checked against the TEMPLATE
        name, so an instance cannot become a way around them.
    #>
    param([Parameter(Mandatory)] $State, [Parameter(Mandatory)] $Data)

    $never = @{}
    foreach ($n in $Data.never) { $never[([string]$n.service).ToLower()] = 'never-touch' }
    foreach ($n in $Data.lockoutRisk) { $never[([string]$n.service).ToLower()] = 'lockout-risk' }

    # Only templates the backup actually covers may drag an instance with them.
    $covered = @{}
    foreach ($prop in (Get-SvcEntries -Services $State.services)) { $covered[$prop.Name.ToLower()] = $true }

    $fixed = 0; $skipped = 0; $failed = 0
    $detail = New-Object System.Collections.Generic.List[string]

    foreach ($k in Get-ChildItem -Path $script:SvcRoot -ErrorAction SilentlyContinue) {
        $p = $k | Get-ItemProperty -ErrorAction SilentlyContinue
        if ($null -eq $p -or $null -eq $p.Type -or $null -eq $p.Start) { continue }
        if ($script:SvcUserInstanceTypes -notcontains ($p.Type -as [int])) { continue }

        $inst = $k.PSChildName
        if ($inst -notmatch '^(?<t>.+)_[^_]+$') { continue }
        $tpl = $Matches['t']

        if (-not $covered.ContainsKey($tpl.ToLower())) { continue }
        if ($never.ContainsKey($tpl.ToLower())) {
            $skipped++
            $detail.Add("$inst : its template $tpl is on the $($never[$tpl.ToLower()]) list")
            continue
        }

        $tplNow = Get-SvcEntry -Name $tpl
        if (-not $tplNow.existed) { continue }
        $target = $tplNow.start -as [int]
        if (-not (Test-SvcValidStart $target)) { continue }
        if (($p.Start -as [int]) -eq $target) { continue }

        try {
            Set-ItemProperty -Path $k.PSPath -Name Start -Value $target -Type DWord -ErrorAction Stop
            $check = (Get-ItemProperty -Path $k.PSPath -Name Start -ErrorAction SilentlyContinue).Start -as [int]
            if ($check -eq $target) {
                Write-Host ("      instance {0,-30} Start -> {1}  (matched to its template)" -f $inst, $target)
                $fixed++
            }
            else { $failed++; $detail.Add("$inst : reads back $check, wanted $target") }
        }
        catch { $failed++; $detail.Add("$inst : $($_.Exception.Message)") }
    }

    [pscustomobject]@{ Fixed = $fixed; Skipped = $skipped; Failed = $failed; Detail = $detail }
}

function Restore-SvcState {
    <#  Restore every service the backup covers, validating each value against
        what a start type can legally be. The backup is data; data can be
        edited. Services on the never-touch list are skipped even here - a
        doctored backup must not be able to reach them. #>
    param([Parameter(Mandatory)] $State, [Parameter(Mandatory)] $Data)
    $restored = 0; $skipped = 0; $failed = 0
    $skippedDetail = New-Object System.Collections.Generic.List[string]
    $failedDetail  = New-Object System.Collections.Generic.List[string]

    # BOTH lists, not just never. A stale or doctored backup could otherwise
    # set NgcSvc to disabled through the undo - the five services the module
    # itself says will lock you out of the machine, reachable by the very
    # script you run when you are already in trouble.
    $never = @{}
    foreach ($n in $Data.never)       { $never[([string]$n.service).ToLower()] = 'never-touch' }
    foreach ($n in $Data.lockoutRisk) { $never[([string]$n.service).ToLower()] = 'lockout-risk' }

    foreach ($prop in (Get-SvcEntries -Services $State.services)) {
        $name = $prop.Name
        $want = $prop.Value
        if ($never.ContainsKey($name.ToLower())) {
            # Counted and named, not silent: 'silently out of scope' meant ~90
            # entries vanished from the reported totals with no accounting.
            $skipped++
            $skippedDetail.Add("$name : on the $($never[$name.ToLower()]) list - out of scope for this module in both directions")
            continue
        }
        $cur = Get-SvcEntry -Name $name
        if (-not $cur.existed) { $skipped++; $skippedDetail.Add("$name : not installed on this machine"); continue }
        if (-not $want.existed) { $skipped++; $skippedDetail.Add("$name : backup records it as not installed"); continue }
        if (-not (Test-SvcValidStart $want.start)) {
            $failed++; $failedDetail.Add("$name : backup start value '$($want.start)' is not a valid service start type - refused")
            continue
        }
        $target = $want.start -as [int]
        if (($cur.start -as [int]) -eq $target) { $skipped++; continue }
        if (Set-SvcStart -Name $name -Value $target) {
            Write-Host ("      restored {0,-32} Start -> {1}" -f $name, $target); $restored++
        } else { $failed++; $failedDetail.Add("$name : write failed") }
    }
    [pscustomobject]@{ Restored = $restored; Skipped = $skipped; Failed = $failed
                       SkippedDetail = $skippedDetail; FailedDetail = $failedDetail }
}

if ($MyInvocation.InvocationName -ne '.') {
    Write-Host ''
    Write-Host '  This is a library. Dot-source it; running it directly does nothing.'
    Write-Host ''
}
