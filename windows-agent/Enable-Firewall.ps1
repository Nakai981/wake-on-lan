# Run as Administrator. Only Private networks and local subnet are allowed.
# No router changes or Internet-facing ports are needed.
$ErrorActionPreference = 'Stop'
$agentExe = (Resolve-Path (Join-Path $PSScriptRoot 'WakeMyPcAgent.exe')).Path
if (-not (Get-NetFirewallRule -Name 'WakeMyPcAgent-Private' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'WakeMyPcAgent-Private' -DisplayName 'Wake My PC Agent (Private LAN)' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 47991 -Program $agentExe -Profile Private -RemoteAddress LocalSubnet
} else {
    Set-NetFirewallRule -Name 'WakeMyPcAgent-Private' -Program $agentExe -Profile Private -RemoteAddress LocalSubnet -Enabled True
}
