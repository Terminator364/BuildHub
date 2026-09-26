$ErrorActionPreference='Stop'
$root=Resolve-Path (Join-Path $PSScriptRoot '..')
$files=@(
  (Join-Path $root 'pc-command\v5\PC_COMMAND_V5.ps1'),
  (Join-Path $root 'pc-command\v5\PC_COMMAND_BOOTSTRAP.ps1'),
  (Join-Path $root 'pc-command\v5\lib\engine.ps1'),
  (Join-Path $root 'pc-command\v5\lib\eventbus.ps1'),
  (Join-Path $root 'pc-command\v5\lib\io.ps1'),
  (Join-Path $root 'pc-command\v5\lib\report.ps1'),
  (Join-Path $root 'pc-command\v5\lib\ui.ps1')
)
foreach($f in $files){
  if(-not(Test-Path $f)){throw "Missing $f"}
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors)
  if($errors.Count){throw "PowerShell parse errors in $f : $($errors|Out-String)"}
}
$cfg=Get-Content (Join-Path $root 'pc-command\v5\config.default.json') -Raw|ConvertFrom-Json
if([int]$cfg.cadence.internet_sync_seconds-ne5){throw 'sync must be 5s'}
if([int]$cfg.cadence.engine_recalc_seconds-ne5){throw 'engine must be 5s'}
if([int]$cfg.cadence.display_refresh_seconds-ne10){throw 'display must be 10s'}
if([int]$cfg.limits.max_conversations-ne10){throw 'max conversations must be 10'}
if([int]$cfg.limits.ram_budget_mb-ne150){throw 'ram budget must be 150MB'}
. (Join-Path $root 'pc-command\v5\lib\engine.ps1')
$m=[pscustomobject]@{state='ACTIVE';weight=1;micro_tasks=@(
 [pscustomobject]@{state='DONE';weight=1;completion=1;evidence='x'},
 [pscustomobject]@{state='ACTIVE';weight=1;completion=.5;evidence='y'}
)}
$p1=(Get-PcMacroProgress $m).Percent
if($p1-ne75){throw "expected 75 got $p1"}
$m.micro_tasks += [pscustomobject]@{state='PENDING';weight=1;completion=0}
$p2=(Get-PcMacroProgress $m).Percent
if($p2-ne50){throw "scope expansion expected 50 got $p2"}
$manifest=Get-Content (Join-Path $root 'pc-command\v5\manifest.json') -Raw|ConvertFrom-Json
if([string]$cfg.version -ne [string]$manifest.version){throw "config/manifest version mismatch: cfg=$($cfg.version) manifest=$($manifest.version)"}
if(-not(Get-Command Read-PcStateLocal -ErrorAction SilentlyContinue)){throw 'Read-PcStateLocal missing'}
if(-not(Get-Command Start-PcStatePull -ErrorAction SilentlyContinue)){throw 'Start-PcStatePull missing'}
if(-not(Get-Command Complete-PcStatePull -ErrorAction SilentlyContinue)){throw 'Complete-PcStatePull missing'}
$idxPath=Join-Path $root 'pc-command\v5\config.default.json'
if(-not(Test-Path $idxPath)){throw 'config missing'}
if(-not([bool]$cfg.feedback_ledger.enabled)){throw 'feedback ledger must be enabled'}
if(-not$cfg.feedback_ledger.ingest_before_build){throw 'feedback ingestion must happen before build'}
Write-Host 'PC_COMMAND_V5_TESTS_OK'
