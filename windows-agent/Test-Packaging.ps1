param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $workspace 'build/agent-packaging-test' }
$testOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
& (Join-Path $PSScriptRoot 'Build.ps1') -OutputDirectory $testOutput
if (Test-Path -LiteralPath (Join-Path $testOutput 'QRCoder.dll')) {
    throw 'Packaging test must run without an external QRCoder.dll'
}
$ready = Join-Path $testOutput 'qr-test-ready.txt'
if (Test-Path -LiteralPath $ready) { Remove-Item -LiteralPath $ready }
$process = Start-Process -FilePath (Join-Path $testOutput 'WakeMyPcAgent.exe') -ArgumentList @('--test-qr', ('"' + $ready + '"')) -WindowStyle Hidden -PassThru
try {
    if (-not $process.WaitForExit(15000)) { throw 'QR packaging smoke test timed out' }
    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $ready)) { throw 'QR packaging smoke test failed' }
    if ((Get-Content -LiteralPath $ready -Raw) -ne 'qr-ready') { throw 'QR was not rendered' }
    Write-Output 'Standalone EXE rendered its pairing QR without an external DLL.'
} finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id }
}
