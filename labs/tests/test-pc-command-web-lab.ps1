$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$lab=Join-Path $root 'pc-command\web-lab'
$server=Join-Path $lab 'server.mjs'
$ui=Join-Path $lab 'public\index.html'
$launcher=Join-Path $lab 'PC_COMMAND_WEB_LAB.ps1'
$readme=Join-Path $lab 'README.md'

foreach($p in @($server,$ui,$launcher,$readme)){if(-not(Test-Path -LiteralPath $p)){throw "missing web lab file: $p"}}

& node --check $server
if($LASTEXITCODE-ne0){throw 'node --check failed'}

$self=& node $server --selftest | Out-String
if($LASTEXITCODE-ne0){throw 'web lab selftest failed'}
$j=$self|ConvertFrom-Json
if(-not[bool]$j.ok){throw 'web lab selftest did not return ok'}
if(-not[bool]$j.readOnly){throw 'web lab selftest must stay read-only'}

$s=[IO.File]::ReadAllText($server)
$h=[IO.File]::ReadAllText($ui)
$l=[IO.File]::ReadAllText($launcher)

foreach($forbidden in @(
  "from 'electron'","require('electron')",'child_process','execSync(','spawnSync(','execFile(','writeFileSync(','rmSync(','unlinkSync(','renameSync(','mkdirSync('
)){
  if($s -match [regex]::Escape($forbidden)){throw "forbidden server primitive: $forbidden"}
}
if($s.Contains("req.method === 'POST'") -or $s.Contains('req.method === "POST"')){throw 'mutation POST endpoint found'}
if($s -notmatch "127\.0\.0\.1"){throw 'server must bind localhost'}
if($s -notmatch "READ_ONLY"){throw 'read-only mode marker missing'}
if($s -notmatch "300000"){throw '5-minute idle default missing'}

foreach($required in @(
  'id="home"','id="conversations"','id="health"','id="local"','id="sources"','id="feedback"','id="versions"','id="technical"',
  'A+B+C','PowerShell reste le moteur','WEB LAB 0.2'
)){
  if($h -notmatch [regex]::Escape($required)){throw "required UI surface missing: $required"}
}

if($h -match '<script\s+src=.*electron'){throw 'electron script forbidden'}
if($l -notmatch '/api/ping'){throw 'launcher readiness must use /api/ping'}
if($l -match 'Get-NetTCPConnection'){throw 'launcher must not depend on slow TCP enumeration'}
if($l -notmatch '300000'){throw 'launcher idle setting must be 5 minutes'}

Write-Host 'PC_COMMAND_WEB_LAB_02_TESTS_OK'
