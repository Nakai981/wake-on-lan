param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$agentRoot = $PSScriptRoot
$agentOutput = Join-Path (Split-Path $agentRoot -Parent) 'dist/WakeMyPcAgent'
if ($OutputDirectory) { $agentOutput = [System.IO.Path]::GetFullPath($OutputDirectory) }
New-Item -ItemType Directory -Force $agentOutput | Out-Null
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /optimize+ /utf8output /win32icon:"$agentRoot\assets\WakeMyPcAgent.ico" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Security.dll /reference:"$agentRoot\vendor\QRCoder.dll" /resource:"$agentRoot\vendor\QRCoder.dll",WakeMyPc.QRCoder.dll /resource:"$agentRoot\vendor\QRCoder-LICENSE.txt",WakeMyPc.QRCoder-LICENSE.txt /out:"$agentOutput\WakeMyPcAgent.exe" "$agentRoot\src\Protocol.cs" "$agentRoot\src\Program.cs" "$agentRoot\src\PairingQrForm.cs" "$agentRoot\src\RemoteInput.cs" "$agentRoot\src\RemoteMouse.cs" "$agentRoot\src\PowerDelay.cs"
if ($LASTEXITCODE -ne 0) { throw 'Agent build failed' }
Copy-Item "$agentRoot/Enable-Firewall.ps1" $agentOutput -Force
foreach ($startupFile in @('Enable-Startup.ps1', 'Disable-Startup.ps1', 'Enable-Startup.cmd', 'Disable-Startup.cmd')) {
    Copy-Item (Join-Path $agentRoot $startupFile) $agentOutput -Force
}
Copy-Item "$agentRoot/README.md" $agentOutput -Force

# QR dependency and its MIT license are embedded in the executable.
