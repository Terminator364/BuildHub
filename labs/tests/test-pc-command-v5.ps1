$ErrorActionPreference='Stop'
$root=Resolve-Path (Join-Path $PSScriptRoot '..')
$files=@(
  (Join-Path $root 'pc-command\v5\PC_COMMAND_V5.ps1'),
  (Join-Path $root 'pc-command\v5\PC_COMMAND_BOOTSTRAP.ps1'),
  (Join-Path $root 'pc-command\v5\lib\engine.ps1'),
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
Write-Host 'PC_COMMAND_V5_TESTS_OK'
