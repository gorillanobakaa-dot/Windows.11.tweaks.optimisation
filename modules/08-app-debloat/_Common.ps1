<#
.SYNOPSIS
    Shared core for the app de-bloat module. This is a LIBRARY.
    Dot-source it; running it directly does nothing but say so.

.DESCRIPTION
    -------------------------------------------------------------------------
    READ THIS FIRST: REMOVAL IS NOT A SETTING
    -------------------------------------------------------------------------
    Every other module in this project changes a value and can put it back.
    This one REMOVES SOFTWARE. There is no backup file that can restore an app
    package, and this module never pretends otherwise.

    There is exactly one honest undo path, and it works only sometimes:

      If the package PAYLOAD is still on disk after removal - which happens
      when the provisioned copy was left in place, or another account still
      has the app - the package can be re-registered from that payload. If the
      payload is gone, it is gone, and the only route back is the Store.

    So the module records, for every removal: the package's full name, its
    install location, whether the payload still existed a moment after the
    removal, and the Store route back. Restore-Apps.ps1 tries re-registration
    where the payload survived and says plainly where it did not. That record
    is NOT a backup and is never called one.

    -------------------------------------------------------------------------
    THE THING THAT MAKES THIS MODULE DIFFERENT FROM EVERY DEBLOAT SCRIPT
    -------------------------------------------------------------------------
    Removed apps come back. This is not a theory: on 2026-08-27 at 16:59 this
    machine's Windows Update reinstalled Microsoft.XboxGameOverlay and
    Microsoft.XboxIdentityProvider hours after the Xbox SERVICES were disabled.

    Microsoft documents exactly one mechanism that stops it - policy-based
    in-box app removal, under which "removed apps remain blocked from
    reinstallation" - and documents that it is "Only Enterprise (ENT) and
    Education (EDU) editions". This machine is Home.

    So on this edition removal is a delete, not a block. The module says so on
    every run, removes the PROVISIONED copy as well as the user's copy (which
    is what stops NEW ACCOUNTS getting it), and gives the owner a checker that
    detects the ones that have crawled back.

    -------------------------------------------------------------------------
    THREE REFUSALS, ENFORCED IN CODE
    -------------------------------------------------------------------------
      1. NEVER-REMOVE list. If a tier names one, the whole tier is REFUSED and
         the run exits 6. Not skipped - refused, because a tier that names a
         protected package is a tier somebody edited without understanding it.
      2. NonRemovable computed LIVE. Windows marks packages it will not let go
         of. The module reads that flag from the machine rather than trusting
         a list, and refuses those too.
      3. Framework and resource packages are out of scope by construction. A
         framework is a shared runtime other applications link against;
         removing one breaks software that has nothing to do with this module.

.NOTES
    Grounding is in this module's README References table, verified at the
    cited line by READ-ONLY-verification\Build-ReferenceLibrary.py.
#>

$script:AdSchemaVersion = 1

# ---------------------------------------------------------------------------
#  NEVER REMOVE. A tier naming any of these is refused outright.
#  Wildcards are matched with -like, anchored by the pattern itself.
# ---------------------------------------------------------------------------
$script:AdNever = @(
    @{ Pattern = 'Microsoft.SecHealthUI';                 Reason = 'the Windows Security app - the interface to Defender. Removing the UI does not remove the protection, it removes your ability to SEE it.' }
    @{ Pattern = 'Microsoft.WindowsStore';                Reason = 'the Store. It is the documented route back for every app this module removes; removing it removes the undo.' }
    @{ Pattern = 'Microsoft.StorePurchaseApp';            Reason = 'Store purchase plumbing; removing it breaks the Store without removing it.' }
    @{ Pattern = 'Microsoft.DesktopAppInstaller';         Reason = 'this is winget. Marked NonRemovable by Windows in any case.' }
    @{ Pattern = 'Microsoft.WindowsTerminal';             Reason = 'the terminal these very scripts are most likely to be run from.' }
    @{ Pattern = 'MicrosoftCorporationII.WinAppRuntime.*'; Reason = 'the Windows App SDK runtime. Other installed applications link against it; removing it breaks them, not Windows.' }
    @{ Pattern = 'Microsoft.WindowsAppRuntime.*';         Reason = 'same runtime family, different naming.' }
    @{ Pattern = 'Microsoft.VCLibs.*';                    Reason = 'C++ runtime other packages depend on.' }
    @{ Pattern = 'Microsoft.UI.Xaml.*';                   Reason = 'XAML runtime other packages depend on.' }
    @{ Pattern = 'Microsoft.NET.*';                       Reason = '.NET runtime other packages depend on.' }
    @{ Pattern = 'Microsoft.HEIFImageExtension';          Reason = 'without it, ordinary phone photos stop opening.' }
    @{ Pattern = 'Microsoft.HEVCVideoExtension';          Reason = 'without it, ordinary phone video stops playing.' }
    @{ Pattern = 'Microsoft.AV1VideoExtension';           Reason = 'video codec; removal degrades playback silently.' }
    @{ Pattern = 'Microsoft.VP9VideoExtensions';          Reason = 'video codec used by most web video.' }
    @{ Pattern = 'Microsoft.MPEG2VideoExtension';         Reason = 'video codec.' }
    @{ Pattern = 'Microsoft.AVCEncoderVideoExtension';    Reason = 'video encoder used by screen recording and calls.' }
    @{ Pattern = 'Microsoft.WebMediaExtensions';          Reason = 'web media codecs.' }
    @{ Pattern = 'Microsoft.WebpImageExtension';          Reason = 'WebP images are most of the modern web.' }
    @{ Pattern = 'Microsoft.MicrosoftEdge.Stable';        Reason = 'Edge. Removing the browser is a separate decision with its own consequences, and it is not this module s to make.' }
    @{ Pattern = 'Microsoft.Winget.Source';               Reason = 'winget package source.' }
    @{ Pattern = 'Microsoft.Paint';                       Reason = 'a basic utility people expect to exist.' }
    @{ Pattern = 'Microsoft.WindowsNotepad';              Reason = 'a basic utility people expect to exist.' }
    @{ Pattern = 'Microsoft.WindowsCalculator';           Reason = 'a basic utility people expect to exist.' }
    @{ Pattern = 'Microsoft.ScreenSketch';                Reason = 'Snipping Tool; also the Print Screen handler.' }
    @{ Pattern = 'Microsoft.LanguageExperiencePack*';     Reason = 'display language packs. Removing one can leave the interface partly untranslated.' }
    @{ Pattern = 'RealtekSemiconductorCorp.*';            Reason = 'audio hardware control panel. This is not bloat, it is how the audio hardware is configured.' }
    @{ Pattern = 'AppUp.IntelGraphicsExperience';         Reason = 'Intel graphics control panel - the GPU control surface.' }
    @{ Pattern = 'AppUp.IntelArcSoftware';                Reason = 'Intel graphics control panel.' }
    @{ Pattern = 'ELANMicroelectronicsCorpo.*';           Reason = 'trackpoint / touchpad configuration for this ThinkPad.' }
    @{ Pattern = 'DolbyLaboratories.DolbyAccess';         Reason = 'audio processing tied to this machine s speakers.' }
    @{ Pattern = 'Claude';                                Reason = 'the owner s own installed application. Nothing in a de-bloat module should touch software the owner chose to install.' }
)

# ---------------------------------------------------------------------------
#  The tiers. Cumulative: MODERATE includes LIGHT, SUPER includes both.
#  Held as DATA so they can be read and diffed without reading PowerShell.
# ---------------------------------------------------------------------------
$script:AdTiers = [ordered]@{
    light = @{
        Label = 'LIGHT - things nothing else depends on and no hardware needs'
        Apps  = @(
            @{ Name = 'Microsoft.XboxGamingOverlay';       What = 'Game Bar - the Win+G overlay' }
            @{ Name = 'Microsoft.XboxGameOverlay';         What = 'Game Bar overlay component. REINSTALLED ITSELF on this machine 2026-08-27 16:59' }
            @{ Name = 'Microsoft.XboxIdentityProvider';    What = 'Xbox sign-in broker. REINSTALLED ITSELF on this machine 2026-08-27 16:59' }
            @{ Name = 'Microsoft.XboxSpeechToTextOverlay'; What = 'Xbox game-chat transcription overlay' }
            @{ Name = 'Microsoft.MixedReality.Portal';     What = 'Windows Mixed Reality portal - the platform itself is retired' }
            @{ Name = 'Microsoft.WindowsFeedbackHub';      What = 'Feedback Hub - sends feedback to Microsoft' }
            @{ Name = 'Microsoft.GetHelp';                 What = 'Get Help - the support-contact app' }
            @{ Name = 'Microsoft.OneConnect';              What = 'Mobile Plans - cellular data plan sign-up' }
            @{ Name = 'Microsoft.MicrosoftJournal';        What = 'Journal - pen note-taking app' }
            @{ Name = 'Microsoft.PowerAutomateDesktop';    What = 'Power Automate Desktop' }
            @{ Name = 'Microsoft.Windows.DevHome';         What = 'Dev Home dashboard' }
            @{ Name = 'Microsoft.StartExperiencesApp';     What = 'Start menu recommendations surface' }
            @{ Name = 'Clipchamp.Clipchamp';               What = 'Clipchamp video editor' }
            @{ Name = 'Microsoft.Messaging';               What = 'the legacy Messaging app' }
            @{ Name = 'Microsoft.People';                  What = 'the People contacts app' }
            @{ Name = 'Microsoft.ApplicationCompatibilityEnhancements'; What = 'app-compat shim delivery channel' }
        )
    }
    moderate = @{
        Label = 'MODERATE - light, plus communication, media and sync apps'
        Apps  = @(
            @{ Name = 'MicrosoftTeams';                        What = 'Teams (personal)' }
            @{ Name = 'MSTeams';                               What = 'Teams (new)' }
            @{ Name = 'Microsoft.YourPhone';                   What = 'Phone Link' }
            @{ Name = 'MicrosoftWindows.CrossDevice';          What = 'Cross Device experiences - phone camera and screen sharing' }
            @{ Name = 'microsoft.windowscommunicationsapps';   What = 'Mail and Calendar' }
            @{ Name = 'Microsoft.ZuneMusic';                   What = 'Media Player' }
            @{ Name = 'Microsoft.ZuneVideo';                   What = 'Films and TV' }
            @{ Name = 'MicrosoftWindows.Client.WebExperience'; What = 'the Widgets board itself' }
            @{ Name = 'Microsoft.WidgetsPlatformRuntime';      What = 'the Widgets runtime' }
            @{ Name = 'Microsoft.BingSearch';                  What = 'web results inside Start menu search. Start still searches locally without it' }
            @{ Name = 'Microsoft.OneDriveSync';                What = 'the OneDrive sync app package' }
            @{ Name = 'Microsoft.WindowsSoundRecorder';        What = 'Sound Recorder' }
            @{ Name = 'Microsoft.WindowsAlarms';               What = 'Clock and alarms' }
            @{ Name = 'MicrosoftCorporationII.QuickAssist';    What = 'Quick Assist - remote assistance. A live remote-control surface' }
        )
    }
    super = @{
        Label = 'SUPER - moderate, plus third-party Store apps and the remaining first-party extras'
        Apps  = @(
            @{ Name = '5319275A.WhatsAppDesktop';                       What = 'WhatsApp' }
            @{ Name = 'AdobeSystemsIncorporated.AdobeCreativeCloudExpress'; What = 'Adobe Express (preinstalled promo)' }
            @{ Name = 'MirametrixInc.GlancebyMirametrix';               What = 'Glance - webcam attention tracking. Reads the camera continuously by design' }
            @{ Name = 'E046963F.LenovoSettingsforEnterprise';           What = 'Lenovo Settings for Enterprise' }
            @{ Name = 'Microsoft.OutlookForWindows';                    What = 'the new Outlook web wrapper' }
            @{ Name = 'Microsoft.WindowsCamera';                        What = 'the Camera app. The camera still works for other apps' }
            @{ Name = 'Microsoft.Windows.Photos';                       What = 'Photos. REMOVING THIS LEAVES NO DEFAULT IMAGE VIEWER unless you install one' }
        )
    }
}

function Test-AdElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-AdInstalled {
    <#  Every non-framework, non-resource package for the current user, with
        the properties the module needs to decide and to record. #>
    $out = @{}
    foreach ($p in @(Get-AppxPackage -ErrorAction SilentlyContinue)) {
        if ($p.IsFramework -or $p.IsResourcePackage) { continue }
        $out[$p.Name] = [pscustomobject]@{
            Name            = $p.Name
            PackageFullName = $p.PackageFullName
            Version         = "$($p.Version)"
            SignatureKind   = "$($p.SignatureKind)"
            NonRemovable    = [bool]$p.NonRemovable
            InstallLocation = "$($p.InstallLocation)"
            Publisher       = "$($p.Publisher)"
        }
    }
    $out
}

function Get-AdProvisioned {
    <#  What a NEWLY CREATED user account would receive. Needs elevation, and
        this project has seen it return "Access is denied" even when elevated -
        so the failure reason is reported rather than blamed on rights. #>
    if (-not (Test-AdElevated)) {
        return [pscustomobject]@{ known = $false; reason = 'needs administrator rights'; packages = @() }
    }
    try {
        $p = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop)
        [pscustomobject]@{ known = $true; reason = ''; packages = $p }
    }
    catch {
        [pscustomobject]@{ known = $false; reason = $_.Exception.Message; packages = @() }
    }
}

function Test-AdNeverRemove {
    <#  Returns the reason string if the name is protected, otherwise $null. #>
    param([Parameter(Mandatory)][string]$Name)
    foreach ($n in $script:AdNever) {
        if ($Name -like $n.Pattern) { return $n.Reason }
    }
    $null
}

function Get-AdTierApps {
    <#  Cumulative. MODERATE = light + moderate. SUPER = all three. #>
    param([Parameter(Mandatory)][ValidateSet('light','moderate','super')][string]$Tier)
    $order = @('light','moderate','super')
    $take  = $order[0..([array]::IndexOf($order, $Tier))]
    $apps  = New-Object System.Collections.Generic.List[object]
    foreach ($t in $take) { foreach ($a in $script:AdTiers[$t].Apps) { $apps.Add($a) } }
    $apps
}

function Test-AdTierLegal {
    <#
    .SYNOPSIS
        Refuse an illegal tier outright rather than skipping entries.
    .DESCRIPTION
        Two independent refusals:
          - a name on the NEVER-REMOVE list
          - a package Windows itself marks NonRemovable, read LIVE
        Returns a list of problem strings. Empty means the tier is legal.
    #>
    param([Parameter(Mandatory)][string]$Tier, $Installed)
    if ($null -eq $Installed) { $Installed = Get-AdInstalled }
    $problems = New-Object System.Collections.Generic.List[string]

    foreach ($a in (Get-AdTierApps -Tier $Tier)) {
        $why = Test-AdNeverRemove -Name $a.Name
        if ($why) { $problems.Add(("{0} is on the NEVER-REMOVE list: {1}" -f $a.Name, $why)); continue }

        $live = $Installed[$a.Name]
        if ($live -and $live.NonRemovable) {
            $problems.Add(("{0} is marked NonRemovable by Windows itself" -f $a.Name))
        }
    }
    $problems
}

function ConvertTo-AdSafeTag {
    param([string]$Tag)
    if ([string]::IsNullOrWhiteSpace($Tag)) { return '' }
    $clean = ($Tag -replace '[^\w\-]', '-')
    if ($clean.Length -gt 40) { $clean = $clean.Substring(0, 40) }
    "_$clean"
}

function Save-AdInventory {
    <#  A dated inventory of what is installed. This is NOT a backup - it
        cannot restore anything - and the file name says so. It exists so the
        owner can prove later which apps came back. #>
    param([Parameter(Mandatory)][string]$Directory, [string]$Tag = '')
    try {
        if (-not (Test-Path $Directory)) { New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop | Out-Null }
    }
    catch { Write-Host "    could not create the record folder: $($_.Exception.Message)"; return $null }

    $inv = Get-AdInstalled
    $obj = [pscustomobject]@{
        schemaVersion = $script:AdSchemaVersion
        takenAt       = (Get-Date).ToString('o')
        elevated      = Test-AdElevated
        note          = 'INVENTORY, NOT A BACKUP. Removing an app package cannot be undone from this file.'
        packages      = $inv
    }
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $path  = Join-Path $Directory ("inventory_{0}{1}.json" -f $stamp, (ConvertTo-AdSafeTag $Tag))
    try { $obj | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop }
    catch { Write-Host "    could not write the inventory: $($_.Exception.Message)"; return $null }

    try { [void](Get-Content $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) }
    catch { Write-Host "    the inventory did not read back: $($_.Exception.Message)"; return $null }
    $path
}

function Get-AdRemovalRecordPath {
    param([Parameter(Mandatory)][string]$Directory)
    Join-Path $Directory 'removed-not-restorable.json'
}

function Add-AdRemovalRecord {
    <#
    .SYNOPSIS
        Append one removal to the module's central honesty artifact.
    .DESCRIPTION
        This is the only inventory of software already removed, so an
        unreadable file is PRESERVED under another name rather than
        overwritten - the same rule module 03 arrived at the hard way.
    #>
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)]$Entry)
    $path = Get-AdRemovalRecordPath -Directory $Directory
    $list = @()
    if (Test-Path $path) {
        try {
            $raw = Get-Content $path -Raw -ErrorAction Stop
            if ($raw.Trim()) { $list = @($raw | ConvertFrom-Json -ErrorAction Stop) }
        }
        catch {
            $keep = "$path.unreadable-$(Get-Date -Format 'yyyyMMdd_HHmmss')"
            try { Move-Item $path $keep -Force -ErrorAction Stop
                  Write-Host "    the removal record would not parse; kept it as $(Split-Path $keep -Leaf)" }
            catch { Write-Host "    the removal record would not parse and could not be preserved: $($_.Exception.Message)"; return $false }
            $list = @()
        }
    }
    $list += $Entry
    try { $list | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding UTF8 -ErrorAction Stop; return $true }
    catch { Write-Host "    could not write the removal record: $($_.Exception.Message)"; return $false }
}

function Write-AdComesBackCaveat {
    Write-Host ""
    Write-Host "    ------------------------------------------------------------------"
    Write-Host "    REMOVED APPS COME BACK ON THIS EDITION."
    Write-Host "    Microsoft documents one mechanism that blocks reinstallation, and"
    Write-Host "    documents it as Enterprise and Education only. This is Home."
    Write-Host "    On 2026-08-27 at 16:59 this machine's own Windows Update"
    Write-Host "    reinstalled two Xbox packages by itself."
    Write-Host "    Removing the PROVISIONED copy stops NEW ACCOUNTS getting the app."
    Write-Host "    It does not stop Windows Update putting it back for you."
    Write-Host "    Re-run check 1 periodically; it names anything that returned."
    Write-Host "    ------------------------------------------------------------------"
}

if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "  This file is a library. Dot-source it; there is nothing to run here."
}
