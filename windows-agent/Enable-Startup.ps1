[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$NoStart)
$ErrorActionPreference = 'Stop'
$agentExe = Join-Path $PSScriptRoot 'WakeMyPcAgent.exe'
if (-not (Test-Path -LiteralPath $agentExe -PathType Leaf)) {
    $agentExe = Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\WakeMyPcAgent\WakeMyPcAgent.exe'
}
if (-not (Test-Path -LiteralPath $agentExe -PathType Leaf)) {
    throw 'WakeMyPcAgent.exe not found. Extract the full ZIP first, or run Build.ps1 from source.'
}
$agentExe = (Resolve-Path -LiteralPath $agentExe).Path
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$startupCommand = '"' + $agentExe + '" --background'
if ($PSCmdlet.ShouldProcess('Current user: WakeMyPcAgent', 'Enable Windows sign-in startup')) {
    New-Item -Path $runKey -Force | Out-Null
    New-ItemProperty -Path $runKey -Name 'WakeMyPcAgent' -Value $startupCommand -PropertyType String -Force | Out-Null
    $saved = Get-ItemPropertyValue -Path $runKey -Name 'WakeMyPcAgent'
    if ($saved -ne $startupCommand) { throw 'Could not verify startup setting.' }
    Write-Host 'Enabled: Agent will run in the background when this Windows user signs in.'
    if (-not $NoStart) {
        Start-Process -FilePath $agentExe -ArgumentList '--background' -WorkingDirectory (Split-Path $agentExe -Parent) -WindowStyle Hidden
        Write-Host 'Agent started. Open its system-tray icon to pair your phone.'
    }
    Write-Host 'Keep this folder in its current location. No administrator privileges are needed.'
}
