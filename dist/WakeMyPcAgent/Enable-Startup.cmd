@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Enable-Startup.ps1"
if errorlevel 1 (
  echo Failed to enable startup. See the error above.
  pause
  exit /b 1
)
pause
