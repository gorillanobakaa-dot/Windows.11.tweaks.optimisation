# Fix for Windows 11 Power & Battery Menu Crash
# This script re-enables the Sensor Services which are required by the Settings app 
# to render the Energy Recommendations page without hard-crashing.

Write-Host "Applying fix for Power & Battery Settings crash..." -ForegroundColor Cyan

$sensors = @('SensorService', 'SensorDataService', 'SensrSvc')
foreach ($svc in $sensors) {
    # Attempt via native SCM first
    Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
    
    # Fallback to registry if permissions are weird (must be run as Admin)
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$svc" -Name "Start" -Value 3 -ErrorAction SilentlyContinue
    
    Start-Service -Name $svc -ErrorAction SilentlyContinue
}

Write-Host "Sensor services restored to Manual.
" -ForegroundColor Green
Write-Host "The Power & battery menu should now open successfully." -ForegroundColor Green
