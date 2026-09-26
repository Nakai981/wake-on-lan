[CmdletBinding(SupportsShouldProcess = $true)]
param()
$ErrorActionPreference = 'Stop'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
if ($PSCmdlet.ShouldProcess('Current user: WakeMyPcAgent', 'Disable Windows sign-in startup')) {
    $entry = Get-ItemProperty -Path $runKey -Name 'WakeMyPcAgent' -ErrorAction SilentlyContinue
    if ($null -ne $entry) {
        Remove-ItemProperty -Path $runKey -Name 'WakeMyPcAgent' -ErrorAction Stop
    }
    if ($null -ne (Get-ItemProperty -Path $runKey -Name 'WakeMyPcAgent' -ErrorAction SilentlyContinue)) {
        throw 'Could not verify startup was disabled.'
    }
    Write-Host 'Disabled: Agent will not start automatically at the next sign-in.'
    Write-Host 'If Agent is currently running, choose Exit Agent from its system-tray menu to stop it.'
    Write-Host 'Pairing data and firewall settings were kept.'
}
