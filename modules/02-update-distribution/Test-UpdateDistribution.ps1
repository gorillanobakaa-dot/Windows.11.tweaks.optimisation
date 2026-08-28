<#
.SYNOPSIS
    Show whether this machine shares Windows updates with other machines, and
    whether anything can connect to it to ask for them. Changes nothing.

.DESCRIPTION
    Reads four separate things, because they can disagree and the disagreement
    is the interesting part:

      1. What the download mode is CONFIGURED to be (registry policy)
      2. What Delivery Optimization says it is ACTUALLY using (the service's
         own reading). On Windows Home in particular, a policy value can be
         written and ignored, and this is where that shows up.
      3. Whether anything is LISTENING on the peer port right now
      4. Whether the firewall is letting other machines reach it

    A machine can be configured not to share and still be listening. It can also
    have shared nothing at all and still be reachable. Neither fact substitutes
    for the other.

    Safe to run at any time. Reads more if run as administrator, and says which
    fields it could not read if not.

.PARAMETER Json
    Also write a timestamped JSON snapshot into .\backups\ for comparison later.
    A snapshot is a record, not a backup - the apply script writes real backups.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-UpdateDistribution.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Test-UpdateDistribution.ps1 -Json
#>

[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here '_Common.ps1')

$state = Get-UdState

Write-Host ''
Write-Host '  Update distribution - current state'
Write-Host ("  {0}  |  Windows build {1}  |  {2}" -f $state.host, $state.osBuild,
            $(if ($state.elevated) { 'running as administrator' } else { 'NOT elevated - some fields may be limited' }))
Write-Host ('  ' + ('-' * 74))

# --- 1. configured ----------------------------------------------------------
Write-Host ''
Write-Host '  1. WHAT IT IS SET TO  (registry policy)'
foreach ($r in $script:UdRegistry) {
    $e = $state.registry["$($r.Key)|$($r.Name)"]
    $shown = if ($e.existed) { "$($e.value)" } else { '<not set>' }
    Write-Host ("     {0,-18} {1,-12} {2}" -f $r.Name, $shown, (Get-UdModeName $(if ($e.existed) { $e.value } else { $null })))
    if (-not $e.keyExisted) {
        Write-Host '                        the policy key does not exist at all - this machine has'
        Write-Host '                        never been configured either way'
    }
}

# --- 2. actual --------------------------------------------------------------
Write-Host ''
Write-Host '  2. WHAT IT IS ACTUALLY DOING  (Delivery Optimization service - authoritative)'
if ($state.runtime.available) {
    Write-Host ("     {0,-18} {1}" -f 'download mode', $state.runtime.effectiveModeName)
    Write-Host ("     {0,-18} {1:N0}" -f 'files uploaded', $state.runtime.filesUploaded)
    Write-Host ("     {0,-18} {1:N1} MB" -f 'bytes uploaded', ($state.runtime.bytesUploaded / 1MB))
    Write-Host ("     {0,-18} {1}" -f 'peers right now', $state.runtime.numberOfPeers)
    Write-Host ("     {0,-18} {1:N0} MB held on disk" -f 'cache', ($state.runtime.cacheBytes / 1MB))
    Write-Host ("     {0,-18} {1}%  of upload bandwidth available to peers" -f 'upload rate cap', $state.runtime.uploadRatePct)
} else {
    Write-Host '     unavailable - the Delivery Optimization PowerShell module did not answer'
}

# --- 3. listening -----------------------------------------------------------
Write-Host ''
Write-Host ("  3. IS ANYTHING LISTENING ON PORT {0}?" -f $script:UdPeerPort)
if (-not $state.listener.checked) {
    Write-Host '     could not check'
} elseif ($state.listener.listening) {
    Write-Host ("     YES - {0}" -f $state.listener.process)
    Write-Host ("     bound to: {0}" -f ($state.listener.addresses -join ', '))
    Write-Host '     Other machines can open a connection to this one on that port.'
} else {
    Write-Host '     no - nothing is accepting connections on the peer port'
}

# --- 4. firewall ------------------------------------------------------------
Write-Host ''
Write-Host '  4. IS THE FIREWALL LETTING THEM IN?'
foreach ($f in $script:UdFirewallRules) {
    $e = $state.firewall[$f.Name]
    if (-not $e.present) {
        Write-Host ("     {0,-30} rule not present on this machine" -f $f.Name)
        continue
    }
    $flag = if ($e.enabled) { 'ENABLED ' } else { 'disabled' }
    Write-Host ("     {0,-30} {1}  {2}  profile: {3}" -f $f.Name, $flag, $e.action, $e.profile)
    if ($e.enabled -and $e.profile -match 'Any|Public') {
        Write-Host '                                    ^ includes PUBLIC networks - hotel, cafe, airport'
    }
}

# --- services ---------------------------------------------------------------
Write-Host ''
Write-Host '  SERVICES  (this module changes none of them)'
foreach ($n in @('DoSvc', 'BITS', 'wuauserv', 'UsoSvc')) {
    $s = $state.services[$n]
    if ($s.present) { Write-Host ("     {0,-12} {1,-9} {2,-8} {3}" -f $n, $s.status, $s.startType, $s.account) }
    else            { Write-Host ("     {0,-12} absent" -f $n) }
}

# --- summary ----------------------------------------------------------------
$pending = @()
foreach ($r in $script:UdRegistry) {
    $e = $state.registry["$($r.Key)|$($r.Name)"]
    $cur = if ($e.existed) { [int]$e.value } else { $null }
    if ($cur -ne $r.Target) { $pending += $r.Name }
}
foreach ($f in $script:UdFirewallRules) {
    $e = $state.firewall[$f.Name]
    if ($e.present -and $null -ne $e.enabled -and $e.enabled -ne $f.Target) { $pending += $f.Name }
}

Write-Host ''
Write-Host ('  ' + ('-' * 74))
Write-Host ("    would change : {0}" -f $(if ($pending.Count) { $pending -join ', ' } else { 'nothing - already as this module wants it' }))
if ($state.runtime.available -and $state.runtime.bytesUploaded -eq 0) {
    Write-Host '    note        : this machine has uploaded 0 bytes to peers so far. The'
    Write-Host '                  exposure here is that it is reachable and permitted to,'
    Write-Host '                  not that it has been.'
}
Write-Host ''

if ($Json) {
    $dir = Join-Path $here 'backups'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $p = Join-Path $dir ("snapshot_{0}.json" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    $state | ConvertTo-Json -Depth 8 | Set-Content $p -Encoding UTF8
    Write-Host "    snapshot written : $p"
    Write-Host ''
}
