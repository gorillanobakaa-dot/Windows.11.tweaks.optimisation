<#
.SYNOPSIS
    Shared core for the xbox-services module. This is a LIBRARY - dot-source it.

.DESCRIPTION
    Five services and one scheduled task, all Xbox, none needed on a machine
    that does not play Xbox games. All five services are Manual-start today:
    stopped, but woken the moment anything asks - the activated surface this
    repository exists to close. This module DISABLES them (Start = 4) and can
    put every one back exactly as it was, from a verified backup.

    What this module deliberately does NOT do:
      - remove any Xbox app package (Game Bar and friends are a REMOVAL, a
        different class of change - a later module handles apps)
      - touch GamingServices/GamingServicesNet (Store gaming plumbing, absent
        on this machine anyway)
      - delete anything. Disabling a service is a registry value with a
        recorded previous value; every part of this is reversible.

    Grounding (verbatim, verifiable against the offline corpus):
      windowsserverdocs/.../security-guidelines-for-disabling-system-services-in-windows-server.md
        "We recommend you disable the following services and their related
        scheduled tasks on Windows Server 2016 with Desktop Experience:"
        - Xbox Live Auth Manager (XblAuthManager): "Should be disabled"
        - Xbox Live Game Save (XblGameSave):       "Should be disabled"
        - task \Microsoft\XblGameSave\XblGameSaveTask
      windowsserverdocs/.../remote-desktop-services-vdi-optimize-configuration.md
        XboxGipSvc, XboxNetApiSvc and BcastDVRUserService listed among the
        services Microsoft's own VDI optimization guidance disables; for the
        per-user BcastDVRUserService: "the template service must be disabled".
    Caveat, stated rather than hidden: both documents are Windows SERVER
    documentation ("Only with Desktop Experience" - the same services this
    client machine runs). Microsoft publishes no per-service disable guidance
    for client Windows in this corpus. These are the vendor's own words about
    these exact service names, and they are the closest grounding that exists.
#>

$script:XsSchemaVersion = 1

# ---------------------------------------------------------------------------
#  Preload before -WhatIf can narrate module aliases (R2.9).
# ---------------------------------------------------------------------------
$script:XsSavedWhatIf = $WhatIfPreference
try {
    $WhatIfPreference = $false
    foreach ($m in @('CimCmdlets', 'ScheduledTasks')) {
        if (-not (Get-Module -Name $m)) {
            Import-Module $m -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        }
    }
}
finally { $WhatIfPreference = $script:XsSavedWhatIf }

# ---------------------------------------------------------------------------
#  The allow-list. Restore validates against THIS, never against backup data.
#  TargetStart 4 = SERVICE_DISABLED. BcastDVRUserService is a per-user
#  TEMPLATE: instances (BcastDVRUserService_xxxxx) inherit from it.
# ---------------------------------------------------------------------------
$script:XsServices = @(
    @{ Name = 'XblAuthManager';      Desc = 'Xbox Live auth - Microsoft: "Should be disabled" [R-99]' }
    @{ Name = 'XblGameSave';         Desc = 'Xbox Live game-save sync - Microsoft: "Should be disabled" [R-100]' }
    @{ Name = 'XboxGipSvc';          Desc = 'Xbox accessory management [R-102]' }
    @{ Name = 'XboxNetApiSvc';       Desc = 'Xbox Live networking API [R-103]' }
    @{ Name = 'BcastDVRUserService'; Desc = 'Game DVR / broadcast per-user TEMPLATE [R-104]' }
)
$script:XsTargetStart = 4    # SERVICE_DISABLED

$script:XsTasks = @(
    @{ Path = '\Microsoft\XblGameSave\'; Name = 'XblGameSaveTask';      Desc = 'named by the same Microsoft guidance [R-101]' }
    @{ Path = '\Microsoft\XblGameSave\'; Name = 'XblGameSaveTaskLogon'; Desc = 'named by the same guidance; absent on this build - handled' }
)

function Test-XsElevated {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-XsServiceRule {
    param([string]$Name)
    foreach ($r in $script:XsServices) { if ($r.Name -eq $Name) { return $r } }
    $null
}

function Test-XsValidStart {
    <#  A SERVICE start type is 2 (automatic), 3 (manual) or 4 (disabled).
        0 and 1 are boot/system DRIVER start types - a backup that "restores"
        a service to boot-start is doctored or corrupt, and is refused.
        Explicit null guard first: $null -as [int] coerces to 0, which the
        self-test caught trying to sneak boot-start past the range check. #>
    param($Value)
    if ($null -eq $Value) { return $false }
    $v = $Value -as [int]
    ($null -ne $v -and $v -ge 2 -and $v -le 4)
}

function Get-XsServiceEntry {
    <#  One service's state: the registry Start value (the thing this module
        changes) plus the live picture for reporting. existed=false when the
        service is not installed on this machine at all - handled, not fatal. #>
    param([string]$Name)
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    $out = [ordered]@{ name = $Name; existed = $false; start = $null
                       liveState = $null; liveStartMode = $null }
    if (Test-Path $key) {
        $out.existed = $true
        try { $out.start = (Get-ItemProperty -Path $key -Name Start -ErrorAction Stop).Start -as [int] } catch {}
        try {
            $w = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction Stop
            if ($w) { $out.liveState = [string]$w.State; $out.liveStartMode = [string]$w.StartMode }
        } catch {}
    }
    [pscustomobject]$out
}

function Get-XsTaskEntry {
    param([string]$Path, [string]$Name)
    $out = [ordered]@{ path = $Path; name = $Name; existed = $false; enabled = $null }
    try {
        $t = Get-ScheduledTask -TaskPath $Path -TaskName $Name -ErrorAction Stop
        $out.existed = $true
        $out.enabled = ($t.State -ne 'Disabled')
    } catch {}
    [pscustomobject]$out
}

function Get-XsDvrInstances {
    <#  Per-user DVR service INSTANCES (BcastDVRUserService_xxxxx) - stamped
        from the template at sign-in, deleted at sign-out. This module never
        writes them (the template is the documented control point [R-104]);
        they are read so no report can overclaim what "disabled" covers. #>
    $out = @()
    foreach ($k in (Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction SilentlyContinue |
                    Where-Object { $_.PSChildName -like 'BcastDVRUserService_*' })) {
        $name = $k.PSChildName
        $start = (Get-ItemProperty $k.PSPath -Name Start -ErrorAction SilentlyContinue).Start -as [int]
        $live = $null
        try {
            $w = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction Stop
            if ($w) { $live = [string]$w.State }
        } catch {}
        $out += [pscustomobject]@{ name = $name; start = $start; liveState = $live }
    }
    $out
}

function Get-XsState {
    $services = @{}
    foreach ($r in $script:XsServices) { $services[$r.Name] = Get-XsServiceEntry -Name $r.Name }
    $tasks = @{}
    foreach ($t in $script:XsTasks) { $tasks["$($t.Path)$($t.Name)"] = Get-XsTaskEntry -Path $t.Path -Name $t.Name }
    [pscustomobject]@{
        schemaVersion = $script:XsSchemaVersion
        takenAt       = (Get-Date).ToString('o')
        elevated      = (Test-XsElevated)
        services      = $services
        tasks         = $tasks
    }
}

function Test-XsStateShape {
    <#  Backup files are data; data can be edited, truncated or wrong. Nothing
        is restored from a file that fails this. [object] param + -as [int]:
        both defect classes were shipped and caught in this project (R2.8). #>
    param([object]$State)
    if ($null -eq $State) { return $false }
    $sv = $null
    try { $sv = $State.schemaVersion -as [int] } catch { return $false }
    if ($sv -ne $script:XsSchemaVersion) { return $false }
    if ($null -eq $State.PSObject.Properties['services']) { return $false }
    if ($null -eq $State.services) { return $false }
    foreach ($r in $script:XsServices) {
        $e = $State.services.($r.Name)
        if ($null -eq $e) { return $false }
        if ($null -eq $e.PSObject.Properties['existed']) { return $false }
    }
    $true
}

function ConvertTo-XsSafeTag {
    param([string]$Tag)
    if (-not $Tag) { return '' }
    $safe = ($Tag -replace '[^A-Za-z0-9-]', '').Substring(0, [Math]::Min(24, ($Tag -replace '[^A-Za-z0-9-]', '').Length))
    if ($safe) { "_$safe" } else { '' }
}

function Save-XsBackup {
    <#  Verified or it did not happen: written, present, plausibly sized,
        parsed back, shape-checked. Internal snapshots carry '_~' which the
        safe-tag charset cannot produce (the reserved-tag collision was a real
        audit finding in this project). -RecordAsOriginal: only the APPLY path
        may define "original", and only once. #>
    param(
        [Parameter(Mandatory)] $State,
        [Parameter(Mandatory)][string] $Directory,
        [string] $Tag = '',
        [string] $InternalSuffix = '',
        [switch] $RecordAsOriginal
    )
    try {
        if (-not (Test-Path $Directory -ErrorAction Stop)) {
            New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop | Out-Null
        }
    }
    catch { Write-Host "    BACKUP FAILED: cannot use the backup folder - $($_.Exception.Message)"; return $null }

    $suffix = if ($InternalSuffix) { "_~$InternalSuffix" } else { ConvertTo-XsSafeTag $Tag }
    $stamp  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $path   = Join-Path $Directory ("state_{0}{1}.json" -f $stamp, $suffix)
    $n = 1
    while (Test-Path $path) { $path = Join-Path $Directory ("state_{0}{1}_{2}.json" -f $stamp, $suffix, $n); $n++ }

    try   { $State | ConvertTo-Json -Depth 8 | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop }
    catch { Write-Host "    BACKUP FAILED: could not write $path - $($_.Exception.Message)"; return $null }

    if (-not (Test-Path $path)) { Write-Host "    BACKUP FAILED: $path is not there after writing it"; return $null }
    if ((Get-Item $path).Length -lt 150) { Write-Host "    BACKUP FAILED: $path is suspiciously small"; return $null }
    try {
        $back = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-XsStateShape -State $back)) { Write-Host "    BACKUP FAILED: $path parsed but is not usable"; return $null }
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

function Get-XsBackups {
    param([Parameter(Mandatory)][string]$Directory)
    if (-not (Test-Path $Directory)) { return @() }
    @(Get-ChildItem -Path $Directory -Filter 'state_*.json' -File -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending)
}

function Get-XsRestoreCandidates {
    <#  Excludes exactly ONE kind of file: internal '_~prerestore' snapshots
        (the safe-tag charset strips '~', so no user tag can produce the
        marker). Backups tagged 'roundtrip' are ordinary user-tag backups and
        MUST stay candidates - the round trip's own undo restores from one. #>
    param([Parameter(Mandatory)][string]$Directory)
    @(Get-XsBackups -Directory $Directory |
      Where-Object { $_.Name -notmatch '_~prerestore(_\d+)?\.json$' })
}

function Set-XsServiceStart {
    <#  Write the Start value and read it back. $true only if the machine
        agrees. #>
    param([string]$Name, [int]$Value)
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    try { Set-ItemProperty -Path $key -Name Start -Value $Value -Type DWord -ErrorAction Stop }
    catch { Write-Host "      failed: $Name - $($_.Exception.Message)"; return $false }
    $check = (Get-ItemProperty -Path $key -Name Start -ErrorAction SilentlyContinue).Start -as [int]
    if ($check -ne $Value) { Write-Host "      failed: $Name reads back $check, wanted $Value"; return $false }
    $true
}

function Restore-XsState {
    <#  Driven by the ALLOW-LIST, never by the backup's keys. Values are
        validated (Test-XsValidStart) before a single write: a backup is data.
        Absent-on-this-machine services are skipped and named. Returns counts
        plus detail lists so the caller cannot print a clean summary over a
        failure. #>
    param([Parameter(Mandatory)] $State)
    $restored = 0; $skipped = 0; $failed = 0
    $skippedDetail = New-Object System.Collections.Generic.List[string]
    $failedDetail  = New-Object System.Collections.Generic.List[string]

    foreach ($r in $script:XsServices) {
        $want = $State.services.($r.Name)
        $cur  = Get-XsServiceEntry -Name $r.Name
        if ($null -eq $want) { $skipped++; $skippedDetail.Add("$($r.Name): not in this backup"); continue }
        if (-not $cur.existed) { $skipped++; $skippedDetail.Add("$($r.Name): service not installed on this machine"); continue }
        if (-not $want.existed) { $skipped++; $skippedDetail.Add("$($r.Name): backup records it as not installed; leaving the installed service alone"); continue }
        if (-not (Test-XsValidStart $want.start)) { $failed++; $failedDetail.Add("$($r.Name): backup start value '$($want.start)' is not a valid start type - refused"); continue }
        $target = $want.start -as [int]
        if (($cur.start -as [int]) -eq $target) { $skipped++; $skippedDetail.Add("$($r.Name): already $target"); continue }
        if (Set-XsServiceStart -Name $r.Name -Value $target) {
            Write-Host ("      restored {0,-24} Start -> {1}" -f $r.Name, $target); $restored++
        } else { $failed++; $failedDetail.Add("$($r.Name): write failed") }
    }

    foreach ($t in $script:XsTasks) {
        $k = "$($t.Path)$($t.Name)"
        $want = $State.tasks.$k
        $cur  = Get-XsTaskEntry -Path $t.Path -Name $t.Name
        if ($null -eq $want) { $skipped++; $skippedDetail.Add("task $($t.Name): not in this backup"); continue }
        if (-not $cur.existed) { $skipped++; $skippedDetail.Add("task $($t.Name): not present on this machine"); continue }
        if (-not $want.existed) { $skipped++; $skippedDetail.Add("task $($t.Name): backup records it as absent; leaving it"); continue }
        if ($cur.enabled -eq $want.enabled) { $skipped++; $skippedDetail.Add("task $($t.Name): already as recorded"); continue }
        try {
            if ($want.enabled) { Enable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop | Out-Null }
            else               { Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction Stop | Out-Null }
            $after = Get-XsTaskEntry -Path $t.Path -Name $t.Name
            if ($after.enabled -eq $want.enabled) {
                Write-Host ("      restored task {0,-19} enabled -> {1}" -f $t.Name, $want.enabled); $restored++
            } else { $failed++; $failedDetail.Add("task $($t.Name): state did not stick") }
        }
        catch { $failed++; $failedDetail.Add("task $($t.Name): $($_.Exception.Message)") }
    }

    [pscustomobject]@{
        Restored = $restored; Skipped = $skipped; Failed = $failed
        SkippedDetail = $skippedDetail; FailedDetail = $failedDetail
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Write-Host ''
    Write-Host '  This is a library. Dot-source it; running it directly does nothing.'
    Write-Host ''
}
