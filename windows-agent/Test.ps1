$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path $PSScriptRoot -Parent
$readyPath = Join-Path $workspaceRoot 'build/agent-test-ready.txt'
if (Test-Path -LiteralPath $readyPath) { Remove-Item -LiteralPath $readyPath }
$testExe = Join-Path $workspaceRoot 'dist/WakeMyPcAgent/WakeMyPcAgent.exe'
$testProcess = Start-Process -FilePath $testExe -ArgumentList @('--test-server', '0', '0123456789abcdef0123456789abcdef', ('"' + $readyPath + '"')) -WindowStyle Hidden -PassThru
try {
    for ($attempt = 0; $attempt -lt 40 -and -not (Test-Path -LiteralPath $readyPath); $attempt++) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $readyPath)) { throw 'Test agent failed to start' }
    $env:WMP_TEST_PORT = (Get-Content -LiteralPath $readyPath -Raw).Trim()
    & "$env:USERPROFILE\develop\flutter\bin\flutter.bat" test
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
} finally {
    if (-not $testProcess.HasExited) { Stop-Process -Id $testProcess.Id }
    Remove-Item Env:WMP_TEST_PORT -ErrorAction SilentlyContinue
}
