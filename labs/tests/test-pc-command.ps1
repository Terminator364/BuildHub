$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = @(
  (Join-Path $root 'pc-command\PC_COMMAND_DASHBOARD.ps1'),
  (Join-Path $root 'pc-command\PC_COMMAND_CONNECT.ps1'),
  (Join-Path $root 'pc-command\PC_COMMAND_STATUS.ps1')
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
if ($failed) { exit 1 }
Write-Host ('CANDIDATES OK: ' + $data.candidates.Count)
