$ErrorActionPreference = 'Stop'
$stateDir = Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$stdout = Join-Path $stateDir 'remote.stdout.log'
$stderr = Join-Path $stateDir 'remote.stderr.log'
$dashboard = Join-Path $PSScriptRoot 'PC_COMMAND_DASHBOARD.ps1'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

$existing = Get-CimInstance Win32_Process | Where-Object {
  $_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander.*remote'
} | Select-Object -First 1

if (-not $existing) {
  $npx = (Get-Command npx.cmd -ErrorAction Stop).Source
  $p = Start-Process -FilePath $npx -ArgumentList @(
    '--yes',
    '@wonderwhy-er/desktop-commander@latest',
    'remote'
  ) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
  Set-Content -Path (Join-Path $stateDir 'launcher.pid') -Value $p.Id -Encoding ASCII
}

if (Test-Path $dashboard) {
  Start-Process powershell.exe -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy','Bypass',
    '-File',('"' + $dashboard + '"')
  )
}
