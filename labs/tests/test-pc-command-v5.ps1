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
if([double]$cfg.cadence.internet_sync_seconds-ne3){throw 'sync must be 3s'}
if([double]$cfg.cadence.engine_recalc_seconds-ne3.5){throw 'engine must be 3.5s'}
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
. (Join-Path $root 'pc-command\v5\lib\io.ps1')
if(-not(Get-Command Read-PcStateLocal -ErrorAction SilentlyContinue)){throw 'Read-PcStateLocal missing'}
if(-not(Get-Command Start-PcStatePull -ErrorAction SilentlyContinue)){throw 'Start-PcStatePull missing'}
if(-not(Get-Command Complete-PcStatePull -ErrorAction SilentlyContinue)){throw 'Complete-PcStatePull missing'}
$idxPath=Join-Path $root 'pc-command\v5\config.default.json'
if(-not(Test-Path $idxPath)){throw 'config missing'}
if(-not([bool]$cfg.feedback_ledger.enabled)){throw 'feedback ledger must be enabled'}
if(-not$cfg.feedback_ledger.ingest_before_build){throw 'feedback ingestion must happen before build'}
if([double]$cfg.cadence.internet_sync_seconds -ne 3){throw 'sync must default to 3s'}
if([double]$cfg.cadence.engine_recalc_seconds -ne 3.5){throw 'engine must default to 3.5s'}
if([int]$cfg.cadence.display_refresh_seconds -ne 10){throw 'display must default to 10s'}
if(-not[bool]$cfg.automation.auto_update){throw 'auto update must be enabled'}
$uiText=Get-Content (Join-Path $root 'pc-command\v5\lib\ui.ps1') -Raw
if($uiText -notmatch "Key='A';Label='Accueil'"){throw 'A Accueil action must exist'}
if($uiText -notmatch 'PARAMETRES / SANTE DU SYSTEME'){throw 'settings health view missing'}
if($uiText -notmatch 'function Write-PcMicro'){throw 'micro detail view missing'}
$mainText=Get-Content (Join-Path $root 'pc-command\v5\PC_COMMAND_V5.ps1') -Raw
if($mainText -notmatch 'Start-PcUpdateProbe'){throw 'auto update probe not wired'}
$manifest=Get-Content (Join-Path $root 'pc-command\v5\manifest.json') -Raw|ConvertFrom-Json
foreach($f in @($manifest.files)){
  $p=Join-Path (Join-Path $root 'pc-command\v5') $f.relative_path
  if(-not(Test-Path $p)){throw "manifest file missing: $($f.relative_path)"}
  $actual=(& git hash-object $p).Trim()
  if($actual-ne[string]$f.git_blob_sha){throw "manifest integrity mismatch: $($f.relative_path)"}
}
$mainText=Get-Content (Join-Path $root 'pc-command\v5\PC_COMMAND_V5.ps1') -Raw
if($mainText -notmatch 'PC_COMMAND_SMOKE_OK'){throw 'runtime smoke gate missing'}

if(-not $cfg.input_feedback.ack_visible){throw 'input ACK must be visible'}
if(-not $cfg.input_feedback.action_matrix_per_view){throw 'button action matrix must be enabled'}
if($cfg.local_observability.process_watcher){throw 'permanent process watcher must be disabled by default'}
if(-not $cfg.interaction_state.user_preemption_visible){throw 'user preemption must be visible'}

$uiText=Get-Content (Join-Path $root 'pc-command\v5\lib\ui.ps1') -Raw
$mainText=Get-Content (Join-Path $root 'pc-command\v5\PC_COMMAND_V5.ps1') -Raw
# Footer/action availability is validated below through the canonical action matrix.
foreach($token in @('Set-PcInputAck','Get-PcAllowedKeysForView','Action: ')){
  if($mainText -notmatch [regex]::Escape($token)){throw "input feedback missing $token"}
}
if($mainText -notmatch 'USER_PREEMPTED_BY_NEW_MESSAGE' -and $uiText -notmatch 'USER_PREEMPTED_BY_NEW_MESSAGE'){throw 'preemption state not visible'}
if($uiText -notmatch "Key='A';Label='Accueil'"){throw 'global home button missing'}
Write-Host 'PC_COMMAND_BUTTON_AUDIT_OK'
Write-Host 'PC_COMMAND_V5_TESTS_OK'


# v0.9.4: action matrix must drive both footer and router.
. (Join-Path $root 'pc-command\v5\lib\ui.ps1')
foreach($view in @('general','conversation','macro','micro','feedback','versions','requirements','timeline','sources','local','settings','reports','health','help')){
  $actions=@(Get-PcActionsForView $view)
  if($actions.Count-eq0){throw "empty action matrix for $view"}
  $keys=@(Get-PcExpandedKeysForView $view)
  if($keys -notcontains 'A'){throw "A Accueil missing from $view"}
  if($keys -notcontains 'Q'){throw "Q Fermer missing from $view"}
}
$mainText=Get-Content (Join-Path $root 'pc-command\v5\PC_COMMAND_V5.ps1') -Raw
if($mainText -notmatch 'Get-PcExpandedKeysForView'){throw 'router is not using the canonical action matrix'}

# v0.9.4: feedback reader must not fail on Generic.List/array conversion and
# must reconcile a stale index from the machine ledger.
$tmp=Join-Path $env:TEMP ('pc-command-feedback-test-'+[guid]::NewGuid().ToString('N'))
$fb=Join-Path $tmp 'pc-command\feedback'
New-Item -ItemType Directory -Force -Path $fb|Out-Null
@'
{"schema":"pc.command.feedback.index.v1","total_feedbacks":1,"last_feedback_id":"FB-001","policy":"A+B+C -> MERGE+REFINE+PRESERVE"}
'@ | Set-Content (Join-Path $fb 'feedback-index.json') -Encoding UTF8
@'
{"schema":"pc.command.feedback.v1","feedback_id":"FB-001","at":"2026-09-26T20:00:00Z","abc":{"A":"a","B":"b","C":"c"},"status":"RECORDED"}
{"schema":"pc.command.feedback.v1","feedback_id":"FB-002","at":"2026-09-26T21:00:00Z","abc":{"A":"a2","B":"b2","C":"c2"},"status":"RECORDED"}
'@ | Set-Content (Join-Path $fb 'feedback-ledger.jsonl') -Encoding UTF8
@'
{"schema":"pc.command.version.trace.v1","versions":[{"version":"0.9.4","status":"candidate"}]}
'@ | Set-Content (Join-Path $fb 'version-trace.json') -Encoding UTF8
$paths=[pscustomobject]@{StateRepo=$tmp}
$x=Read-PcFeedbackLocal $paths
if($x.Error){throw "feedback reader error: $($x.Error)"}
if(@($x.Recent).Count-ne2){throw "feedback reader recent count wrong: $(@($x.Recent).Count)"}
if([string]$x.Index.last_feedback_id-ne'FB-002'){throw "feedback reader did not reconcile latest id"}
if(@($x.Versions.versions).Count-ne1){throw 'version trace not loaded'}
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'PC_COMMAND_V094_LEDGER_ROUTER_OK'


# v0.9.5: updater must smoke before swap, retain rollback, and report status.
$bootText=Get-Content (Join-Path $root 'pc-command\v5\PC_COMMAND_BOOTSTRAP.ps1') -Raw
foreach($token in @('SmokeTest','READY_TO_SWAP','ROLLED_BACK','RECOVERY_REQUIRED','update-status.json','Move-Item')){
  if($bootText -notmatch [regex]::Escape($token)){throw "v0.9.5 updater token missing: $token"}
}
if($bootText -notmatch 'Wait-PcViewerExit'){throw 'v0.9.5 must defer swap while viewer is still alive'}
if($bootText -notmatch 'post-launch' -and $bootText -notmatch 'post-launch'){throw 'post-launch update verification missing'}

$mainText=Get-Content (Join-Path $root 'pc-command\v5\PC_COMMAND_V5.ps1') -Raw
if($mainText -match 'lab/pc-command-v070/labs/pc-command/v5/manifest.json'){throw 'stale hard-coded manifest URL remains'}
if($mainText -notmatch 'Ensure-PcChannelDetail'){throw 'report detail gate missing'}
if($mainText -notmatch 'PDF detaille genere'){throw 'human PDF ACK missing'}
if(-not[bool]$cfg.reports.force_selected_conversation_detail){throw 'report detail policy missing'}
if([string]$cfg.updater.swap_mode -ne 'same_volume_directory_move'){throw 'updater swap mode missing'}
if(-not[bool]$cfg.updater.root_bootstrap_self_heal){throw 'root bootstrap self-heal policy missing'}
if($bootText -notmatch 'RootBootstrap'){throw 'root bootstrap self-heal implementation missing'}
if($bootText -notmatch 'Copy-Item \$appBootstrap \$RootBootstrap'){throw 'root bootstrap self-heal copy missing'}
Write-Host 'PC_COMMAND_V096_UPDATE_REPORT_OK'
