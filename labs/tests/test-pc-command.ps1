$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = @(
  (Join-Path $root 'pc-command\PC_COMMAND_DASHBOARD.ps1'),
  (Join-Path $root 'pc-command\PC_COMMAND_CONNECT.ps1'),
  (Join-Path $root 'pc-command\PC_COMMAND_STATUS.ps1'),
  (Join-Path $root 'pc-command\PC_COMMAND_STATUS_V2.ps1'),
  (Join-Path $root 'pc-command\PC_COMMAND_START.ps1')
)
$failed = $false
foreach ($file in $files) {
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
  if ($errors.Count -gt 0) {
    Write-Host "SYNTAX FAIL: $file"
    $errors | ForEach-Object { Write-Host $_.Message }
    $failed = $true
  } else {
    Write-Host "SYNTAX OK: $file"
  }
}
$json = Join-Path $root 'browser-bench\candidates.json'
$data = Get-Content $json -Raw | ConvertFrom-Json
if ($data.schema -ne 'browser4g.candidates.v1') { throw 'Bad browser candidate schema' }
if ($data.candidates.Count -lt 5) { throw 'Candidate set too small' }

$feedPath = Join-Path $root 'pc-command\feed.json'
$feed = Get-Content $feedPath -Raw | ConvertFrom-Json
if ($feed.schema -ne 'pc_command.feed.v2') { throw 'Bad PC Command feed schema' }
if ([int]$feed.refresh_seconds -ne 50) { throw 'Refresh must be 50 seconds' }
if (@($feed.streams).Count -lt 2) { throw 'Need multiple workstreams' }
foreach ($s in @($feed.streams)) {
  if (-not $s.objective) { throw "Missing objective in $($s.id)" }
  if (@($s.tasks).Count -lt 1) { throw "Missing tasks in $($s.id)" }
  foreach ($t in @($s.tasks)) {
    if ($null -eq $t.weight) { throw "Missing weight in $($s.id)/$($t.id)" }
    if ($null -eq $t.completion) { throw "Missing completion in $($s.id)/$($t.id)" }
    if ([double]$t.completion -lt 0 -or [double]$t.completion -gt 1) { throw "Bad completion in $($s.id)/$($t.id)" }
  }
}

if ($failed) { exit 1 }
Write-Host ('CANDIDATES OK: ' + $data.candidates.Count)
Write-Host ('PC COMMAND STREAMS OK: ' + @($feed.streams).Count)
