<#
.SYNOPSIS
    Manually select and disable specific Lenovo and OEM background services.

.DESCRIPTION
    Lenovo business laptops rely on several privileged background services (like ImControllerService) 
    to intercept hardware buttons (Mic Mute, Plane Mode, Phone Hangup) and control brightness.
    
    By default, the 06-services optimization profiles no longer touch these services to prevent 
    crippling your laptop's hardware capabilities. 
    
    However, if you do not use these hardware buttons and want to strictly reduce your attack surface 
    and background noise, you can use this script to manually opt-in to disabling them.
#>

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "You must run this script as Administrator."
    exit
}

$oemServices = @(
    [pscustomobject]@{ Service = 'ImControllerService'; Description = 'Lenovo System Interface Foundation (Breaks Mic Mute, Phone, Plane Mode buttons)' }
    [pscustomobject]@{ Service = 'DisplayEnhancementService'; Description = 'Windows Display Enhancement (Breaks Brightness slider via Fn keys)' }
    [pscustomobject]@{ Service = 'LenovoVantageService'; Description = 'Lenovo Vantage Background Service' }
    [pscustomobject]@{ Service = 'UDCService'; Description = 'Lenovo Universal Device Client' }
    [pscustomobject]@{ Service = 'LPlatSvc'; Description = 'Lenovo Platform Service' }
    [pscustomobject]@{ Service = 'LenovoSmartStandby'; Description = 'Lenovo Smart Standby' }
    [pscustomobject]@{ Service = 'LvfInstallService'; Description = 'Lenovo View Install Helper' }
)

# Filter to only show services that actually exist on this machine
$availableServices = foreach ($svc in $oemServices) {
    if (Get-Service -Name $svc.Service -ErrorAction SilentlyContinue) {
        $svc
    }
}

if (-not $availableServices) {
    Write-Host "No Lenovo OEM services found on this machine." -ForegroundColor Cyan
    exit
}

Write-Host "WARNING: Disabling these services will lobotomize hardware capabilities on Lenovo business laptops." -ForegroundColor Yellow
$selections = $availableServices | Out-GridView -Title "Select Lenovo/OEM Services to DISABLE (Cancel to exit)" -PassThru

if ($selections) {
    foreach ($item in $selections) {
        Write-Host "Disabling and stopping $($item.Service)..." -ForegroundColor Cyan
        Set-Service -Name $item.Service -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name $item.Service -Force -ErrorAction SilentlyContinue
    }
    Write-Host "`nSelected services have been disabled." -ForegroundColor Green
} else {
    Write-Host "No services selected. Exiting."
}
