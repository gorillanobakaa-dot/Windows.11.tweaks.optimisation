$json = Get-Content 'profiles.json' -Raw | ConvertFrom-Json
$services = @()
$json.profiles.light | ForEach-Object { $services += $_.service }
$json.profiles.moderate | ForEach-Object { $services += $_.service }
$json.profiles.super | ForEach-Object { $services += $_.service }
$services | Sort-Object -Unique | Set-Content target_services.txt
(Get-Content target_services.txt).Count
