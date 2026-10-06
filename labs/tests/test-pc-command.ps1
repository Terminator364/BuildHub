$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = @(
  (Join-Path $root 'pc-command\PC_COMMAND_DASHBOARD.ps1'),
  (Join-Path $root 'pc-command\PC_COMMAND_CONNECT.ps1'),
  (Join-Path $root 'pc-command\PC_COMMAND_STATUS.ps1'),
  (Join-Path $root 'pc-command\PC_COMMAND_STATUS_V2.ps1'),
  (Join-Path $root 'pc-command\PC_COMMAND_STATUS_V3.ps1'),
  (Join-Path $root 'pc-command\PC_COMMAND_STATUS_V4.ps1'),
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

$feedPath = Join-Path $root 'pc-command\feed-v3.json'
$feed = Get-Content $feedPath -Raw | ConvertFrom-Json
if ($feed.schema -ne 'pc_command.feed.v3') { throw 'Bad PC Command feed schema' }
if ([int]$feed.engine.remote_sync_seconds -ne 5) { throw 'Remote sync must be 5 seconds' }
if ([int]$feed.engine.local_recalc_seconds -ne 5) { throw 'Engine recalculation must be 5 seconds' }
if ([int]$feed.engine.display_refresh_seconds -ne 10) { throw 'Display refresh must be 10 seconds' }
if ([int]$feed.engine.max_connected_conversations -ne 10) { throw 'Conversation cap must be 10' }
if (@($feed.conversations).Count -lt 1) { throw 'Need at least one connected conversation' }
foreach ($c in @($feed.conversations)) {
  if (-not $c.objective) { throw "Missing conversation objective in $($c.id)" }
  if (@($c.macro_tasks).Count -gt 10) { throw "Too many macro tasks in $($c.id)" }
  foreach ($m in @($c.macro_tasks)) {
    if (@($m.micro_tasks).Count -lt 1) { throw "Missing micro tasks in $($c.id)/$($m.id)" }
    foreach ($t in @($m.micro_tasks)) {
      if ($null -eq $t.weight) { throw "Missing weight in $($c.id)/$($m.id)/$($t.id)" }
      if ($null -eq $t.completion) { throw "Missing completion in $($c.id)/$($m.id)/$($t.id)" }
      if ([double]$t.completion -lt 0 -or [double]$t.completion -gt 1) { throw "Bad completion in $($c.id)/$($m.id)/$($t.id)" }
    }
  }
}

if ($failed) { exit 1 }
Write-Host ('CANDIDATES OK: ' + $data.candidates.Count)
Write-Host ('PC COMMAND CONVERSATIONS OK: ' + @($feed.conversations).Count)
