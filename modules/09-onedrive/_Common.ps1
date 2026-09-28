<#
.SYNOPSIS
    Shared core for the OneDrive module. This is a LIBRARY. Dot-source it;
    running it directly does nothing but say so.

.DESCRIPTION
    -------------------------------------------------------------------------
    WHAT THIS MODULE IS FOR
    -------------------------------------------------------------------------
    Uninstalling OneDrive from Settings removes the program, but not the means
    of putting it back, and not what it left behind. On the audited machine,
    after a user-initiated uninstall:

      - Windows still carried its own 86 MB OneDrive installer in System32
      - no policy stopped OneDrive being installed or used again
      - the account still had OneDrive's registry keys, a link handler that
        pointed at the deleted OneDrive.exe, two environment variables naming
        an old account's folder, and two leftover folders

    This module removes the leftovers and blocks the way back.

    -------------------------------------------------------------------------
    TWO PARTS, BECAUSE WINDOWS DRAWS THE LINE THERE
    -------------------------------------------------------------------------
      ACCOUNT   Your own account's leftovers. No administrator rights.
                Remove-OneDriveLeftovers.ps1
      MACHINE   The two policies Microsoft documents for turning OneDrive off,
                plus the installer and the new-account setup entry.
                Needs administrator rights. Block-OneDrive.ps1

    -------------------------------------------------------------------------
    DOCUMENTED AND OBSERVED
    -------------------------------------------------------------------------
    Two items are documented by Microsoft, with a quotable registry path and
    value: DisableFileSyncNGSC and PreventNetworkTrafficPreUserSignIn. Every
    other item is observed on this machine and labelled uncited. Unlike module
    04, the observed items are applied by default: they are leftovers of a
    program the owner already removed, not settings with a choice attached.

    -------------------------------------------------------------------------
    HOW EACH KIND OF ITEM IS BACKED UP AND UNDONE
    -------------------------------------------------------------------------
      values    recorded in the state file; the undo writes back the exact
                value, or removes it if it did not exist (absent is not zero)
      keys      exported with reg.exe to a .reg file before deletion; the undo
                imports that file
      folders   sent to the Recycle Bin, never deleted outright; the route
                back is the Recycle Bin, and the undo says so
      files     OneDriveSetup.exe is MOVED into backups\files; the undo moves
                it back
      default   the Run value in the default-user hive is recorded and
                removed; the undo writes it back

.NOTES
    Citations, both in
    windows-itpro-docs/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services.md:

      line 674  DisableFileSyncNGSC                  [R-145]
      line 680  PreventNetworkTrafficPreUserSignIn   [R-146]
#>

$script:OdSchemaVersion = 1

# ---------------------------------------------------------------------------
#  VALUES. Target $null means "must not exist" - the value is removed.
# ---------------------------------------------------------------------------
$script:OdValues = @(
    @{
        Part = 'Machine'; Key = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
        Name = 'DisableFileSyncNGSC'; Target = 1; Kind = 'DWord'; Cite = 'R-145'
        Ui   = 'Prevent the usage of OneDrive for file storage'
        Desc = 'the policy Microsoft documents for turning OneDrive off'
    }
    @{
        Part = 'Machine'; Key = 'HKLM:\SOFTWARE\Microsoft\OneDrive'
        Name = 'PreventNetworkTrafficPreUserSignIn'; Target = 1; Kind = 'DWord'; Cite = 'R-146'
        Ui   = 'Prevent OneDrive from generating network traffic until the user signs in'
        Desc = 'no OneDrive network traffic before someone signs in to it'
    }
    @{
        Part = 'Account'; Key = 'HKCU:\Environment'
        Name = 'OneDrive'; Target = $null; Kind = 'String'; Cite = $null
        Ui   = 'OneDrive environment variable'
        Desc = 'handed to every program you start; points at a OneDrive folder'
    }
    @{
        Part = 'Account'; Key = 'HKCU:\Environment'
        Name = 'OneDriveConsumer'; Target = $null; Kind = 'String'; Cite = $null
        Ui   = 'OneDriveConsumer environment variable'
        Desc = 'same, for the personal (consumer) OneDrive'
    }
)

# ---------------------------------------------------------------------------
#  KEYS. Exported, then deleted. Guard = a check that must pass before the
#  key is touched, so a key another program shares is never removed.
# ---------------------------------------------------------------------------
$script:OdKeys = @(
    @{ Part = 'Account'; Key = 'HKCU:\Software\Microsoft\OneDrive'; Guard = 'none'
       Desc = "OneDrive's own settings, including the account and computer name it recorded" }
    @{ Part = 'Account'; Key = 'HKCU:\Software\SyncEngines'; Guard = 'syncengines-onedrive-only'
       Desc = 'the cloud-sync provider list; removed only if no other sync provider is registered in it' }
    @{ Part = 'Account'; Key = 'HKCU:\Software\Classes\grvopen'; Guard = 'grvopen-points-at-onedrive'
       Desc = 'a link handler for OneDrive-for-work links; removed only if it points at OneDrive.exe' }
)

# ---------------------------------------------------------------------------
#  FOLDERS. Sent to the Recycle Bin.
# ---------------------------------------------------------------------------
function Get-OdFolders {
    @(
        @{ Part = 'Account'; Path = (Join-Path $env:USERPROFILE 'OneDrive')
           Desc = 'the old OneDrive folder in your user folder' }
        @{ Part = 'Account'; Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive')
           Desc = 'what the uninstall left of the program: an app stub and install logs' }
        @{ Part = 'Machine'; Path = (Join-Path $env:ProgramData 'Microsoft OneDrive')
           Desc = 'the machine-wide setup folder' }
    )
}

# ---------------------------------------------------------------------------
#  INSTALLER FILES. Moved into backups\files. They are owned by
#  TrustedInstaller, so the move takes ownership first.
# ---------------------------------------------------------------------------
function Get-OdInstallers {
    @(
        @{ Path = (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'); Stash = 'System32_OneDriveSetup.exe' }
        @{ Path = (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe'); Stash = 'SysWOW64_OneDriveSetup.exe' }
    )
}

# ---------------------------------------------------------------------------
#  DEFAULT-USER HIVE. New accounts copy this hive; a Run value named
#  OneDriveSetup in it installs OneDrive for every new account at first sign-in.
# ---------------------------------------------------------------------------
$script:OdDefaultHive  = 'C:\Users\Default\NTUSER.DAT'
$script:OdHiveMount    = 'HKU\W11T_OdDefault'
$script:OdHiveRunKey   = 'Registry::HKEY_USERS\W11T_OdDefault\Software\Microsoft\Windows\CurrentVersion\Run'
$script:OdHiveValues   = @('OneDriveSetup', 'OneDrive')

function Get-OdValues { param([string]$Part) @($script:OdValues | Where-Object { -not $Part -or $_.Part -eq $Part }) }
function Get-OdKeys   { param([string]$Part) @($script:OdKeys   | Where-Object { -not $Part -or $_.Part -eq $Part }) }

function Test-OdElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-OdExistingAncestor {
    param([string]$Key)
    $k = $Key
    while ($k -and -not (Test-Path $k)) {
        $parent = Split-Path -Parent $k
        if (-not $parent -or $parent -eq $k) { return $null }
        $k = $parent
    }
    $k
}

function Get-OdRegEntry {
    <#  A value, plus whether it and its key exist at all. "Absent" is a state
        the undo has to be able to return to. #>
    param([string]$Key, [string]$Name)
    if (-not (Test-Path $Key)) {
        return [pscustomobject]@{ value = $null; kind = $null; existed = $false; keyExisted = $false
                                  existingAncestor = (Get-OdExistingAncestor -Key $Key) }
    }
    try {
        $item = Get-ItemProperty -Path $Key -Name $Name -ErrorAction Stop
        $kind = $null
        try { $kind = (Get-Item $Key).GetValueKind($Name).ToString() } catch { }
        [pscustomobject]@{ value = $item.$Name; kind = $kind; existed = $true; keyExisted = $true }
    }
    catch { [pscustomobject]@{ value = $null; kind = $null; existed = $false; keyExisted = $true } }
}

function Test-OdKeyGuard {
    <#  Returns $null if the key may be removed, or a reason string if not. #>
    param([hashtable]$Rule)
    if (-not (Test-Path $Rule.Key)) { return $null }
    switch ($Rule.Guard) {
        'syncengines-onedrive-only' {
            $prov = Join-Path $Rule.Key 'Providers'
            $others = @(Get-ChildItem $prov -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -notmatch 'OneDrive' })
            $topOthers = @(Get-ChildItem $Rule.Key -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -ne 'Providers' })
            if ($others.Count -or $topOthers.Count) {
                return ("kept: another sync provider is registered here ({0})" -f (@($others + $topOthers) | ForEach-Object PSChildName) -join ', ')
            }
        }
        'grvopen-points-at-onedrive' {
            $cmd = (Get-ItemProperty (Join-Path $Rule.Key 'shell\open\command') -ErrorAction SilentlyContinue).'(default)'
            if ("$cmd" -notmatch 'OneDrive\.exe') { return "kept: it does not point at OneDrive.exe ($cmd)" }
        }
    }
    $null
}

$script:OdHiveMountPs = 'Registry::HKEY_USERS\W11T_OdDefault'

function Mount-OdDefaultHive {
    <#  Load the default-user hive. Returns @{ ok; ownLoad; reason }.
        Keeps reg.exe's own error text: until 2026-09-28 a failed load was
        reported only as "cannot be read", which made the cause unfindable.
        If a previous run left the hive loaded, it is reused, not refused. #>
    if (-not (Test-Path -LiteralPath $script:OdDefaultHive)) { return @{ ok = $false; ownLoad = $false; reason = "no template at $script:OdDefaultHive" } }
    if (-not (Test-OdElevated)) { return @{ ok = $false; ownLoad = $false; reason = 'needs administrator rights' } }
    if (Test-Path $script:OdHiveMountPs) { return @{ ok = $true; ownLoad = $false; reason = 'already loaded by an earlier run - reused' } }
    $out = (& reg.exe load $script:OdHiveMount $script:OdDefaultHive 2>&1 | Out-String).Trim()
    $code = $LASTEXITCODE
    if ($code -ne 0 -or -not (Test-Path $script:OdHiveMountPs)) {
        return @{ ok = $false; ownLoad = $false; reason = ("reg load failed (exit {0}): {1}" -f $code, $out) }
    }
    @{ ok = $true; ownLoad = $true; reason = '' }
}

function Dismount-OdDefaultHive {
    <#  Unload, and CHECK it unloaded. Registry handles held by this process
        can make the first unload fail ("Access is denied"); collect and
        retry. Returns '' on success or the last error text. #>
    $last = ''
    for ($i = 0; $i -lt 5; $i++) {
        [gc]::Collect(); [gc]::WaitForPendingFinalizers()
        $last = (& reg.exe unload $script:OdHiveMount 2>&1 | Out-String).Trim()
        if (-not (Test-Path $script:OdHiveMountPs)) { return '' }
        Start-Sleep -Milliseconds 500
    }
    "reg unload failed: $last"
}

function Get-OdDefaultHiveState {
    <#  Reads the default-user Run values. Returns readable = $false with the
        exact reason when it cannot, so callers report UNKNOWN, never "gone". #>
    $r = [ordered]@{ readable = $false; reason = ''; values = @{} }
    if (-not (Test-Path -LiteralPath $script:OdDefaultHive)) { $r.readable = $true; $r.reason = 'no template file'; return [pscustomobject]$r }
    $m = Mount-OdDefaultHive
    if (-not $m.ok) { $r.reason = $m.reason; return [pscustomobject]$r }
    try {
        foreach ($n in $script:OdHiveValues) {
            $key = Get-Item -LiteralPath $script:OdHiveRunKey -ErrorAction SilentlyContinue
            $v = $null; $kind = $null
            if ($key -and ($key.GetValueNames() -contains $n)) {
                $v = $key.GetValue($n, $null, 'DoNotExpandEnvironmentNames')
                $kind = $key.GetValueKind($n).ToString()
            }
            if ($key) { $key.Close() }
            $r.values[$n] = [pscustomobject]@{ existed = ($null -ne $v); value = $v; kind = $kind }
        }
        $r.readable = $true
    }
    catch { $r.reason = "reading the template failed: $($_.Exception.Message)" }
    finally {
        if ($m.ownLoad) { $u = Dismount-OdDefaultHive; if ($u) { $r.reason = ($r.reason + ' ' + $u).Trim() } }
    }
    [pscustomobject]$r
}

function Invoke-OdDefaultHive {
    <#  Load the default-user hive, run $Action against it, always unload.
        Returns the action's result, or throws with reg.exe's own reason. #>
    param([Parameter(Mandatory)][scriptblock]$Action)
    $m = Mount-OdDefaultHive
    if (-not $m.ok) { throw "could not load the new-account template: $($m.reason)" }
    try { & $Action }
    finally { if ($m.ownLoad) { $u = Dismount-OdDefaultHive; if ($u) { Write-Host "      WARNING: $u" } } }
}

function Get-OdState {
    param([switch]$SkipHive)
    $values = @{}
    foreach ($v in $script:OdValues) { $values["$($v.Key)|$($v.Name)"] = Get-OdRegEntry -Key $v.Key -Name $v.Name }
    $keys = @{}
    foreach ($k in $script:OdKeys) { $keys[$k.Key] = [pscustomobject]@{ existed = (Test-Path $k.Key); export = $null } }
    $folders = @{}
    foreach ($f in (Get-OdFolders)) { $folders[$f.Path] = [pscustomobject]@{ existed = (Test-Path $f.Path) } }
    $installers = @{}
    foreach ($i in (Get-OdInstallers)) { $installers[$i.Path] = [pscustomobject]@{ existed = (Test-Path $i.Path); stash = $null } }
    [pscustomobject]@{
        schemaVersion = $script:OdSchemaVersion
        takenAt       = (Get-Date).ToString('o')
        values        = $values
        keys          = $keys
        folders       = $folders
        installers    = $installers
        defaultHive   = $(if ($SkipHive) { $null } else { Get-OdDefaultHiveState })
    }
}

function Test-OdStateShape {
    param($State)
    if ($null -eq $State) { return $false }
    foreach ($p in 'schemaVersion', 'values', 'keys') { if (-not $State.PSObject.Properties[$p]) { return $false } }
    $ver = $null
    try { $ver = [int]$State.schemaVersion } catch { return $false }
    if ($ver -ne $script:OdSchemaVersion) { return $false }
    if ($State.values -is [System.Array] -or $State.keys -is [System.Array]) { return $false }
    $true
}

function ConvertTo-OdSafeTag {
    param([string]$Tag)
    if (-not $Tag) { return '' }
    $clean = ($Tag -replace '[^A-Za-z0-9\-_.]', '-').Trim('-')
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    if ($clean) { "_$clean" } else { '' }
}

function New-OdBackupFolder {
    <#  One folder per run: state.json plus any .reg exports and stashed files.
        Returns the folder path or $null. #>
    param([Parameter(Mandatory)][string]$Directory, [string]$Part, [string]$Tag = '', [string]$InternalSuffix = '')
    $suffix = if ($InternalSuffix) { "_~$InternalSuffix" } else { ConvertTo-OdSafeTag $Tag }
    $name = "run_{0}_{1}{2}" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'), $Part.ToLower(), $suffix
    $path = Join-Path $Directory $name
    $n = 1
    while (Test-Path $path) { $path = Join-Path $Directory ("{0}_{1}" -f $name, $n); $n++ }
    try { New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null; $path }
    catch { Write-Host "    BACKUP FAILED: cannot create $path - $($_.Exception.Message)"; $null }
}

function Save-OdState {
    <#  Write state.json into a run folder and PROVE it: exists, big enough,
        parses, right shape. Returns $true or $false. #>
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$RunFolder)
    $p = Join-Path $RunFolder 'state.json'
    try { $State | ConvertTo-Json -Depth 8 | Set-Content -Path $p -Encoding UTF8 -ErrorAction Stop }
    catch { Write-Host "    BACKUP FAILED: could not write $p - $($_.Exception.Message)"; return $false }
    if (-not (Test-Path $p) -or (Get-Item $p).Length -lt 200) { Write-Host "    BACKUP FAILED: $p is missing or too small"; return $false }
    try {
        $back = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-OdStateShape -State $back)) { Write-Host "    BACKUP FAILED: $p is not a usable state file"; return $false }
    }
    catch { Write-Host "    BACKUP FAILED: $p cannot be read back - $($_.Exception.Message)"; return $false }
    $true
}

function Export-OdKey {
    <#  reg.exe export, verified: the file exists and names the key. #>
    param([string]$Key, [string]$RunFolder)
    $native = $Key -replace '^HKCU:\\', 'HKCU\' -replace '^HKLM:\\', 'HKLM\'
    $file = Join-Path $RunFolder (($native -replace '[\\: ]', '_') + '.reg')
    $null = & reg.exe export $native $file /y 2>&1
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $file)) { return $null }
    $head = Get-Content $file -TotalCount 5 -ErrorAction SilentlyContinue | Out-String
    if ($head -notmatch [regex]::Escape(($native -replace '^HKCU', 'HKEY_CURRENT_USER' -replace '^HKLM', 'HKEY_LOCAL_MACHINE'))) { return $null }
    $file
}

function Send-OdToRecycleBin {
    param([string]$Path)
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic
        if (Test-Path $Path -PathType Container) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
        } else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
        }
    }
    catch { Write-Host "      failed: $Path - $($_.Exception.Message)"; return $false }
    -not (Test-Path $Path)
}

function Set-OdValue {
    param([string]$Key, [string]$Name, $Value, [string]$Kind)
    try {
        if (-not (Test-Path $Key)) { New-Item -Path $Key -Force -ErrorAction Stop | Out-Null }
        New-ItemProperty -Path $Key -Name $Name -Value $Value -PropertyType $Kind -Force -ErrorAction Stop | Out-Null
    }
    catch { Write-Host "      failed: $Name - $($_.Exception.Message)"; return $false }
    $check = Get-OdRegEntry -Key $Key -Name $Name
    if (-not $check.existed -or [string]$check.value -ne [string]$Value) { Write-Host "      failed: $Name did not stick"; return $false }
    $true
}

function Remove-OdValue {
    param([string]$Key, [string]$Name)
    if (Test-Path $Key) { Remove-ItemProperty -Path $Key -Name $Name -Force -ErrorAction SilentlyContinue }
    if ((Get-OdRegEntry -Key $Key -Name $Name).existed) { Write-Host "      failed: $Name is still present"; return $false }
    $true
}

function Remove-OdCreatedKey {
    <#  Remove a key the apply created, walking up to (never including) the
        ancestor that existed before, and only while each key is empty. #>
    param([string]$Key, [string]$Ancestor)
    $k = $Key
    while ($k -and $Ancestor -and $k -ne $Ancestor -and $k.Length -gt $Ancestor.Length) {
        if (-not (Test-Path $k)) { $k = Split-Path -Parent $k; continue }
        $item = Get-Item $k
        if (@($item.GetValueNames()).Count -or @($item.GetSubKeyNames()).Count) { break }
        try { Remove-Item -Path $k -Force -ErrorAction Stop } catch { Write-Host "      FAILED to remove created key $k"; return $false }
        $k = Split-Path -Parent $k
    }
    $true
}

function Test-OdLegitValue {
    <#  An allow-listed value may only be restored to a value of its own kind
        and a sane shape. Anything else in a backup is refused. #>
    param([hashtable]$Rule, $Entry)
    if ($Entry.kind -and [string]$Entry.kind -ne [string]$Rule.Kind -and -not ($Rule.Kind -eq 'String' -and $Entry.kind -eq 'ExpandString')) { return $false }
    if ($Rule.Kind -eq 'DWord') {
        try { $iv = [int]$Entry.value; return ($iv -eq 0 -or $iv -eq 1) } catch { return $false }
    }
    $s = [string]$Entry.value
    ($s.Length -gt 0 -and $s.Length -le 260 -and $s -notmatch '[\r\n]')
}

function Restore-OdValues {
    <#  Iterates the module's OWN allow-list for the given part, never the
        backup's contents, so an edited backup cannot write arbitrary values. #>
    param([Parameter(Mandatory)]$State, [string]$Part)
    $res = [ordered]@{ Restored = 0; Skipped = 0; Failed = 0; Detail = @() }
    foreach ($rule in (Get-OdValues -Part $Part)) {
        $k = "$($rule.Key)|$($rule.Name)"
        $entry = $null
        if ($State.values -is [hashtable]) { $entry = $State.values[$k] }
        elseif ($State.values.PSObject.Properties[$k]) { $entry = $State.values.$k }
        if ($null -eq $entry) { $res.Skipped++; $res.Detail += "skipped: $($rule.Name) (not in this backup)"; continue }
        if (-not $entry.existed) {
            if (Remove-OdValue -Key $rule.Key -Name $rule.Name) {
                $ok = $true
                if (-not $entry.keyExisted -and $entry.PSObject.Properties['existingAncestor']) {
                    $ok = Remove-OdCreatedKey -Key $rule.Key -Ancestor $entry.existingAncestor
                }
                if ($ok) { $res.Restored++ } else { $res.Failed++; $res.Detail += "FAILED: $($rule.Name) key cleanup" }
            }
            else { $res.Failed++; $res.Detail += "FAILED: $($rule.Name) (could not remove)" }
        }
        elseif (-not (Test-OdLegitValue -Rule $rule -Entry $entry)) {
            $res.Failed++; $res.Detail += "FAILED: $($rule.Name) (backup holds an illegitimate value - refused)"
        }
        else {
            $val = if ($rule.Kind -eq 'DWord') { [int]$entry.value } else { [string]$entry.value }
            $kind = if ($entry.kind -eq 'ExpandString') { 'ExpandString' } else { $rule.Kind }
            if (Set-OdValue -Key $rule.Key -Name $rule.Name -Value $val -Kind $kind) { $res.Restored++ }
            else { $res.Failed++; $res.Detail += "FAILED: $($rule.Name) (write did not stick)" }
        }
    }
    [pscustomobject]$res
}

function Get-OdRuns {
    <#  Backup run folders for a part, newest first, excluding the undo's own
        pre-restore snapshots (MODULE-STANDARD R16.3). #>
    param([Parameter(Mandatory)][string]$Directory, [string]$Part, [switch]$IncludeInternal)
    if (-not (Test-Path $Directory)) { return @() }
    @(Get-ChildItem $Directory -Directory -Filter ("run_*_{0}*" -f $Part.ToLower()) -ErrorAction SilentlyContinue |
      Where-Object { $IncludeInternal -or $_.Name -notmatch '_~prerestore' } |
      Where-Object { Test-Path (Join-Path $_.FullName 'state.json') } |
      Sort-Object Name -Descending)
}

function Send-OdEnvironmentChange {
    <#  Tell running programs that environment variables changed, so new
        windows stop inheriting the removed ones before the next sign-in. #>
    try {
        if (-not ('W11T.OdEnv' -as [type])) {
            Add-Type -Namespace W11T -Name OdEnv -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
        }
        $out = [UIntPtr]::Zero
        [void][W11T.OdEnv]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$out)
    } catch { }
}

if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '^\s*\.\s') {
    Write-Host ''
    Write-Host '  _Common.ps1 is shared code, not a script to run.'
    Write-Host '  Use the numbered .cmd files in this folder instead.'
    Write-Host ''
}
