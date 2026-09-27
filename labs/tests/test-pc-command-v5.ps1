$ErrorActionPreference='Stop'
$root=Resolve-Path (Join-Path $PSScriptRoot '..')
$files=@(
  (Join-Path $root 'pc-command\v5\PC_COMMAND_V5.ps1'),
  (Join-Path $root 'pc-command\v5\PC_COMMAND_BOOTSTRAP.ps1'),
  (Join-Path $root 'pc-command\v5\lib\engine.ps1'),
  (Join-Path $root 'pc-command\v5\lib\eventbus.ps1'),
  (Join-Path $root 'pc-command\v5\lib\io.ps1'),
  (Join-Path $root 'pc-command\v5\lib\policy.ps1'),
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
. (Join-Path $root 'pc-command\v5\lib\policy.ps1')
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

# v0.9.7: updater must require a promoted stable manifest and restore the root launcher on rollback.
$bootText=Get-Content (Join-Path $root 'pc-command\v5\PC_COMMAND_BOOTSTRAP.ps1') -Raw
if($bootText -notmatch "RequiredChannel='stable'"){throw 'stable manifest channel gate missing'}
if($bootText -notmatch 'Canal manifest refuse'){throw 'manifest channel rejection status missing'}
if($bootText -notmatch 'Sync-PcRootBootstrap'){throw 'root bootstrap sync helper missing'}
if($bootText -notmatch 'postVersion'){throw 'post-launch version proof missing'}
if($bootText -notmatch '\[regex\]::Escape\(\$Root\)'){throw 'viewer-exit scope must be tied to the PC Command root'}
if(-not[bool]$cfg.updater.require_manifest_channel){throw 'manifest channel gate policy missing'}
if([string]$cfg.updater.required_manifest_channel -ne 'stable'){throw 'required manifest channel must be stable'}
if(-not[bool]$cfg.updater.post_launch_version_match){throw 'post-launch version match policy missing'}
if(-not[bool]$cfg.updater.rollback_restores_root_bootstrap){throw 'rollback launcher restore policy missing'}
Write-Host 'PC_COMMAND_V097_PROMOTION_ROLLBACK_OK'

# v0.9.7: recover the previously valid local tree if a crash/power loss lands between directory renames.
$bootText=Get-Content (Join-Path $root 'pc-command\v5\PC_COMMAND_BOOTSTRAP.ps1') -Raw
if($bootText -notmatch 'Recover-PcInterruptedSwap'){throw 'interrupted-swap recovery missing'}
if($bootText -notmatch 'Test-PcInstalledTree'){throw 'local backup validation missing'}
if($bootText -notmatch 'RECOVERED_PREVIOUS'){throw 'offline recovery status missing'}
if($bootText -notmatch 'Application precedente restauree avant acces reseau'){throw 'recovery must happen before network dependency'}
if(-not[bool]$cfg.updater.recover_interrupted_swap_offline){throw 'offline interrupted-swap recovery policy missing'}
if(-not[bool]$cfg.updater.validate_local_backup_before_recovery){throw 'local backup validation policy missing'}
Write-Host 'PC_COMMAND_V097_POWERLOSS_RECOVERY_OK'

# FB-034 / v0.9.7: the declared 10-conversation capacity and 20 visible microtasks must be navigable.
if((Get-PcSlotKey 10) -ne '0'){throw '10th slot must render on key 0'}
if((Get-PcSlotIndexFromKey '0') -ne 9){throw 'key 0 must route to the 10th slot'}
foreach($view in @('general','conversation','macro')){
  $keys=@(Get-PcExpandedKeysForView $view)
  if($keys -notcontains '0'){throw "10th-slot key missing from $view"}
}
$macroKeys=@(Get-PcExpandedKeysForView 'macro')
if($macroKeys -notcontains 'N'){throw 'microtask page key N missing from macro view'}
$micro20=@()
for($n=1;$n-le20;$n++){
  $micro20 += [pscustomobject]@{title=("micro-"+$n);state='PENDING';weight=1;completion=0;evidence=$null}
}
$macro20=[pscustomobject]@{title='macro-20';state='ACTIVE';micro_tasks=$micro20}
$page0=Get-PcMicroPage $macro20 20 0 10
$page1=Get-PcMicroPage $macro20 20 1 10
if(@($page0.Items).Count-ne10 -or @($page1.Items).Count-ne10){throw '20 microtasks must expose two full pages'}
if($page0.Pages-ne2 -or $page1.Pages-ne2){throw 'microtask page count must be 2'}
if([int]$page0.RawIndexes[9]-ne9){throw 'page 1 key 0 must resolve raw micro index 9'}
if([int]$page1.RawIndexes[0]-ne10 -or [int]$page1.RawIndexes[9]-ne19){throw 'page 2 must resolve raw micro indexes 10..19'}
$mainText=Get-Content (Join-Path $root 'pc-command\v5\PC_COMMAND_V5.ps1') -Raw
if($mainText -notmatch "\^\[0-9\]\$"){throw 'router must accept digit 0'}
if($mainText -notmatch 'Get-PcMicroPage'){throw 'router must use the shared microtask page model'}
if($mainText -notmatch 'MicroPage'){throw 'microtask page state missing'}
Write-Host 'PC_COMMAND_V097_TEN_SLOT_PAGING_OK'

# FB-035 / v0.9.7: 10 conversations must fit the minimum frame and active labels must not invent "TRAVAIL EN COURS".
$engineText=Get-Content (Join-Path $root 'pc-command\v5\lib\engine.ps1') -Raw
if($engineText -match 'TRAVAIL EN COURS'){throw 'forbidden inferred active-state label remains'}
$nowIso=[datetimeoffset]::Now.ToString('o')
$assistantProbe=[pscustomobject]@{lifecycle=[pscustomobject]@{state='ASSISTANT_PROCESSING';phase='TEST';last_signal_at=$nowIso}}
$toolProbe=[pscustomobject]@{lifecycle=[pscustomobject]@{state='TOOL_RUNNING';phase='TEST';last_signal_at=$nowIso}}
if([string](Get-PcLifecycleView $assistantProbe).Label -ne 'ASSISTANT_PROCESSING'){throw 'ASSISTANT_PROCESSING label mismatch'}
if([string](Get-PcLifecycleView $toolProbe).Label -ne 'TOOL_RUNNING'){throw 'TOOL_RUNNING label mismatch'}
$script:PcFrameMax=14
if(-not(Get-PcHomeCompactMode 10)){throw '10-conversation home must use compact mode at minimum frame'}
if((4+10)-gt$script:PcFrameMax){throw 'compact 10-conversation layout exceeds minimum frame budget'}
$script:PcFrameMax=34
if(Get-PcHomeCompactMode 3){throw 'small conversation sets should keep rich layout when space permits'}
Write-Host 'PC_COMMAND_V097_ADAPTIVE_HOME_STATE_LABELS_OK'

# FB-037 / v0.9.8: PowerShell repository integration must remain zero-resident and native-first.
$catalogPath=Join-Path $root 'pc-command\v5\powershell-sources.json'
if(-not(Test-Path $catalogPath)){throw 'PowerShell source catalog missing'}
$catalog=Get-Content $catalogPath -Raw -Encoding UTF8|ConvertFrom-Json
$entries=@($catalog.entries)
if($entries.Count-ne41){throw "PowerShell source catalog must contain 41 entries; got $($entries.Count)"}
$validClasses=@('CORE','ON-DEMAND','SOURCE-ONLY','EXTERNAL-TOOL','REJECT')
foreach($e in $entries){
  if($validClasses -notcontains [string]$e.class){throw "invalid PowerShell source class: $($e.repo) / $($e.class)"}
}
function Assert-PcSourceClass([string]$Repo,[string]$Class){
  $x=@($entries|Where-Object repo -eq $Repo|Select-Object -First 1)
  if($x.Count-ne1){throw "PowerShell source missing: $Repo"}
  if([string]$x[0].class-ne$Class){throw "PowerShell source class mismatch: $Repo expected $Class got $($x[0].class)"}
}
Assert-PcSourceClass 'PowerShell/PowerShell' 'CORE'
Assert-PcSourceClass 'PowerShell/PSScriptAnalyzer' 'CORE'
Assert-PcSourceClass 'pester/Pester' 'CORE'
Assert-PcSourceClass 'microsoft/winget-cli' 'CORE'
Assert-PcSourceClass 'Badgerati/Pode' 'REJECT'
Assert-PcSourceClass 'ChrisTitusTech/winutil' 'SOURCE-ONLY'
Assert-PcSourceClass 'farag2/Sophia-Script-for-Windows' 'SOURCE-ONLY'
Assert-PcSourceClass 'Raphire/Win11Debloat' 'SOURCE-ONLY'
if(-not[bool]$catalog.policy.native_first){throw 'PowerShell catalog must be native-first'}
if(-not[bool]$catalog.policy.no_runtime_auto_install){throw 'runtime auto-install must be forbidden'}
if(-not[bool]$catalog.policy.no_permanent_watchers){throw 'permanent watchers must be forbidden'}
if(-not(Get-Command Get-PcPowerShellCapabilitySnapshot -ErrorAction SilentlyContinue)){throw 'PowerShell capability probe missing'}
if(-not(Get-Command Get-PcPowerShellSourceCatalog -ErrorAction SilentlyContinue)){throw 'PowerShell catalog reader missing'}
$caps=Get-PcPowerShellCapabilitySnapshot -TtlSeconds 0
if([bool]$caps.InstallPerformed){throw 'capability probe must not install anything'}
if([bool]$caps.ResidentDependencyAdded){throw 'capability probe must not add resident dependency'}
$catalogRuntime=Get-PcPowerShellSourceCatalog -TtlSeconds 0
if([int]$catalogRuntime.Total-ne41){throw 'runtime PowerShell catalog count mismatch'}
foreach($runtimeFile in @(
  (Join-Path $root 'pc-command\v5\PC_COMMAND_V5.ps1'),
  (Join-Path $root 'pc-command\v5\lib\io.ps1'),
  (Join-Path $root 'pc-command\v5\lib\ui.ps1')
)){
  $runtimeText=Get-Content $runtimeFile -Raw -Encoding UTF8
  if($runtimeText -match '(?im)^\s*(Install-Module|Install-PSResource)\b'){
    throw "runtime auto-install command forbidden: $runtimeFile"
  }
}
if([int]$cfg.pslib_audit.catalog_entries-ne41){throw 'config PowerShell catalog count must be 41'}
if([bool]$cfg.pslib_audit.runtime_auto_install){throw 'config must forbid runtime auto-install'}
if([string]$cfg.pslib_audit.capability_probe_mode-ne'on_demand_cached'){throw 'PowerShell capability probe must be on-demand cached'}
if([string]$cfg.pslib_audit.pwsh7_install-ne'DEFERRED_UNTIL_MEASURED_GAP'){throw 'pwsh7 install must remain deferred'}
Write-Host 'PC_COMMAND_V098_PSLIB_ZERO_RESIDENT_OK'

# FB-038 / v0.9.9: lot 2 diagnostics must remain bounded, read-only and native-first.
if(-not(Get-Command Get-PcReadOnlyDiagnostics -ErrorAction SilentlyContinue)){throw 'bounded native diagnostics function missing'}
$diag=Get-PcReadOnlyDiagnostics -TtlSeconds 0 -RecentErrorHours 6 -MaxRecentErrors 5
if(-not[bool]$diag.ReadOnly){throw 'diagnostics must be read-only'}
if([bool]$diag.NetworkTrafficGenerated){throw 'diagnostics must not generate network traffic'}
if([bool]$diag.DnsCacheModified){throw 'diagnostics must not modify DNS cache'}
if([bool]$diag.ExternalModuleRequired){throw 'diagnostics must not require external modules'}
if([int]$diag.MaxRecentErrors-ne5){throw 'recent error probe must remain bounded to 5'}
if([int]$diag.RecentErrorHours-ne6){throw 'recent error window must remain 6h by default'}
if(@($diag.RecentSystemErrors).Count-gt5){throw 'recent error probe returned more than 5 records'}
$ioText=Get-Content (Join-Path $root 'pc-command\v5\lib\io.ps1') -Raw -Encoding UTF8
foreach($forbidden in @('Clear-DnsClientCache','Install-WindowsUpdate','Reset-WUComponents','Install-Module EventViewerX','Install-Module PSEventViewer')){
  if($ioText -match [regex]::Escape($forbidden)){throw "forbidden lot2 operation present: $forbidden"}
}
if(-not[bool]$cfg.pslib_audit.lot2.read_only){throw 'lot2 config must be read-only'}
if([bool]$cfg.pslib_audit.lot2.dns_cache_modification){throw 'lot2 must forbid DNS cache modification'}
if([bool]$cfg.pslib_audit.lot2.dns_mass_benchmark){throw 'lot2 must forbid mass DNS benchmark'}
if([bool]$cfg.pslib_audit.lot2.windows_update_actions){throw 'lot2 must not execute Windows Update actions'}
if([bool]$cfg.pslib_audit.lot2.eventviewerx_dependency){throw 'lot2 must not depend on EventViewerX'}
if(@($cfg.pslib_audit.lot2.external_modules_installed).Count-ne0){throw 'lot2 must not install external modules'}
Write-Host 'PC_COMMAND_V099_NATIVE_DIAGNOSTICS_OK'

# FB-039 / v1.0.0: L0-L3 policy engine must gate actions without executing them.
if(-not(Get-Command Test-PcActionPolicy -ErrorAction SilentlyContinue)){throw 'action policy evaluator missing'}
if(-not(Get-Command Get-PcActionPolicySummary -ErrorAction SilentlyContinue)){throw 'action policy summary missing'}
if([bool]$cfg.action_policy.execution_enabled){throw 'v1.0.0 policy layer must remain non-executing'}
if([string]$cfg.action_policy.default_unknown-ne'DENY'){throw 'unknown actions must default DENY'}

$l0=[pscustomobject]@{Name='read-health';Level='L0';ReadOnly=$true;Bounded=$true;ModifiesSystem=$false}
$r0=Test-PcActionPolicy $l0
if([string]$r0.Decision-ne'ALLOW_AUTO' -or -not[bool]$r0.Auto){throw 'bounded L0 read should auto-allow'}

$l1=[pscustomobject]@{Name='generate-report';Level='L1';ReadOnly=$false;Bounded=$true;ModifiesSystem=$false}
$r1=Test-PcActionPolicy $l1
if([string]$r1.Decision-ne'ALLOW_AUTO' -or -not[bool]$r1.Auto){throw 'bounded L1 safe action should auto-allow'}

$l2Missing=[pscustomobject]@{Name='install-module';Level='L2';Bounded=$true;ModifiesSystem=$true;Preconditions=$true;ExpectedChanges=$true;Rollback=$false;PostVerification=$true}
$r2m=Test-PcActionPolicy $l2Missing
if([string]$r2m.Decision-ne'DENY'){throw 'L2 without rollback must be denied'}
if(@($r2m.Missing)-notcontains'Rollback'){throw 'L2 denial must report missing rollback'}

$l2=[pscustomobject]@{Name='install-module';Level='L2';Bounded=$true;ModifiesSystem=$true;Preconditions=$true;ExpectedChanges=$true;Rollback=$true;PostVerification=$true}
$r2=Test-PcActionPolicy $l2
if([string]$r2.Decision-ne'ALLOW_GATED' -or [bool]$r2.Auto){throw 'fully gated L2 must be non-auto ALLOW_GATED'}

$l3=[pscustomobject]@{Name='system-repair';Level='L3';Bounded=$true;ModifiesSystem=$true;Preconditions=$true;ExpectedChanges=$true;Backup=$true;Rollback=$true;PostVerification=$true;ManualApproval=$true}
$r3=Test-PcActionPolicy $l3
if([string]$r3.Decision-ne'REQUIRE_EXPLICIT_APPROVAL' -or [bool]$r3.Auto){throw 'L3 must require explicit approval and never auto-run'}

$pipe=[pscustomobject]@{Name='remote-iex';Level='L1';Bounded=$true;RemotePipeExecute=$true}
$rp=Test-PcActionPolicy $pipe
if([string]$rp.Decision-ne'DENY'){throw 'remote pipe-to-execute must be hard denied'}

$preset=[pscustomobject]@{Name='debloat-preset';Level='L2';Bounded=$true;GlobalPreset=$true;Preconditions=$true;ExpectedChanges=$true;Rollback=$true;PostVerification=$true}
$rg=Test-PcActionPolicy $preset
if([string]$rg.Decision-ne'DENY'){throw 'global debloat/tweak preset must be hard denied'}

$ext=[pscustomobject]@{Name='external-script';Level='L1';Bounded=$true;ExternalSource=$true;ExternalSourcePinned=$false}
$re=Test-PcActionPolicy $ext
if([string]$re.Decision-ne'DENY' -or @($re.Missing)-notcontains'ExternalSourcePinned'){throw 'un-pinned external source must be denied'}

$mainText=Get-Content (Join-Path $root 'pc-command\v5\PC_COMMAND_V5.ps1') -Raw -Encoding UTF8
if($mainText -notmatch 'policy\.ps1'){throw 'policy engine not loaded by runtime'}
Write-Host 'PC_COMMAND_V100_ACTION_POLICY_OK'

# FB-040 / v1.0.1: local network snapshot must remain zero-traffic and dependency-free.
if(-not(Get-Command Get-PcLocalNetworkSnapshot -ErrorAction SilentlyContinue)){throw 'local network snapshot missing'}
$net=Get-PcLocalNetworkSnapshot -TtlSeconds 0
if(-not[bool]$net.ReadOnly){throw 'network snapshot must be read-only'}
if([bool]$net.NetworkTrafficGenerated){throw 'network snapshot must generate zero network traffic'}
if([bool]$net.ExternalLookup){throw 'network snapshot must not use external lookup'}
if([bool]$net.DnsCacheModified){throw 'network snapshot must not modify DNS cache'}
if([bool]$net.ActiveProbeUsed){throw 'network snapshot must not use active probes'}
if([bool]$net.ExternalModuleRequired){throw 'network snapshot must not require external modules'}
if($net.Primary){
  if([string]$net.Primary.Status-ne'Up'){throw 'primary network adapter must be Up'}
  if(@($net.Primary.IPv4).Count-eq0){throw 'primary network adapter must have IPv4'}
  foreach($ip in @($net.Primary.IPv4)){
    if([string]$ip -match '^169\.254\.' -or [string]$ip -match '^127\.'){throw 'primary network adapter must exclude APIPA/loopback'}
  }
}
$ioText=Get-Content (Join-Path $root 'pc-command\v5\lib\io.ps1') -Raw -Encoding UTF8
$netStart=$ioText.IndexOf('function Get-PcLocalNetworkSnapshot')
if($netStart-lt0){throw 'network snapshot source block not found'}
$netFn=$ioText.Substring($netStart)
foreach($forbidden in @('Test-Connection','Test-NetConnection','Resolve-DnsName','tracert','nmap','Clear-DnsClientCache')){
  if($netFn -match [regex]::Escape($forbidden)){throw "active network primitive forbidden in snapshot: $forbidden"}
}
if([bool]$cfg.pslib_audit.lot4_network.active_probe){throw 'lot4 active probes must be disabled'}
if([bool]$cfg.pslib_audit.lot4_network.ping){throw 'lot4 ping must be disabled'}
if([bool]$cfg.pslib_audit.lot4_network.traceroute){throw 'lot4 traceroute must be disabled'}
if([bool]$cfg.pslib_audit.lot4_network.port_scan){throw 'lot4 port scan must be disabled'}
if([bool]$cfg.pslib_audit.lot4_network.external_dns_lookup){throw 'lot4 external DNS lookup must be disabled'}
if([bool]$cfg.pslib_audit.lot4_network.dns_cache_modification){throw 'lot4 DNS cache modification must be disabled'}
if([bool]$cfg.pslib_audit.lot4_network.external_module_required){throw 'lot4 external module must be disabled'}
Write-Host 'PC_COMMAND_V101_ZERO_TRAFFIC_NETWORK_OK'

# FB-041 / v1.0.2: startup/RAM snapshot must remain bounded and read-only.
if(-not(Get-Command Get-PcStartupRamSnapshot -ErrorAction SilentlyContinue)){throw 'startup RAM snapshot missing'}
$sr=Get-PcStartupRamSnapshot -TtlSeconds 0 -TopProcessGroups 6
if(-not[bool]$sr.ReadOnly){throw 'startup RAM snapshot must be read-only'}
if([bool]$sr.ProcessChangePerformed){throw 'startup RAM snapshot must not change processes'}
if([bool]$sr.ServiceChangePerformed){throw 'startup RAM snapshot must not change services'}
if([bool]$sr.RegistryChangePerformed){throw 'startup RAM snapshot must not change registry'}
if([bool]$sr.ScheduledTaskEnumerationPerformed){throw 'startup RAM snapshot must not enumerate scheduled tasks in baseline'}
if([bool]$sr.ServiceEnumerationPerformed){throw 'startup RAM snapshot must not enumerate services in baseline'}
if([bool]$sr.WatcherStarted){throw 'startup RAM snapshot must not start a watcher'}
if(@($sr.TopMemoryProcesses).Count-gt6){throw 'startup RAM snapshot must remain bounded to 6 process groups'}
$ioText=Get-Content (Join-Path $root 'pc-command\v5\lib\io.ps1') -Raw -Encoding UTF8
$start=$ioText.IndexOf('function Get-PcStartupRamSnapshot')
if($start-lt0){throw 'startup RAM source block missing'}
$fn=$ioText.Substring($start)
foreach($forbidden in @('Stop-Process','Set-Service','Remove-ItemProperty','Set-ItemProperty','Disable-ScheduledTask','Unregister-ScheduledTask','Get-ScheduledTask','Win32_Service')){
  if($fn -match [regex]::Escape($forbidden)){throw "forbidden startup/RAM primitive present: $forbidden"}
}
if(-not[bool]$cfg.pslib_audit.lot5_startup_ram.read_only){throw 'lot5 must be read-only'}
if([bool]$cfg.pslib_audit.lot5_startup_ram.process_change){throw 'lot5 process changes must be false'}
if([bool]$cfg.pslib_audit.lot5_startup_ram.service_change){throw 'lot5 service changes must be false'}
if([bool]$cfg.pslib_audit.lot5_startup_ram.registry_change){throw 'lot5 registry changes must be false'}
if([bool]$cfg.pslib_audit.lot5_startup_ram.scheduled_task_enumeration){throw 'lot5 task enumeration must be false'}
if([bool]$cfg.pslib_audit.lot5_startup_ram.service_enumeration){throw 'lot5 service enumeration must be false'}
if([bool]$cfg.pslib_audit.lot5_startup_ram.watcher){throw 'lot5 watcher must be false'}
Write-Host 'PC_COMMAND_V102_STARTUP_RAM_OK'

# FB-042 / v1.0.3: dependency requests must default DENY unless exact-pinned and approved.
$depPath=Join-Path $root 'pc-command\v5\dependency-lock.json'
if(-not(Test-Path $depPath)){throw 'dependency lock missing'}
$depRaw=Get-Content $depPath -Raw -Encoding UTF8|ConvertFrom-Json
if([string]$depRaw.schema-ne'pc.command.dependencies.v1'){throw 'dependency lock schema mismatch'}
if(@($depRaw.runtime_dependencies).Count-ne0){throw 'runtime dependency set must remain empty'}
if([bool]$depRaw.policy.runtime_auto_install){throw 'runtime auto-install must remain disabled'}
if(-not[bool]$depRaw.policy.exact_version_required){throw 'exact version must be required'}
if([bool]$depRaw.policy.latest_keyword_allowed){throw 'latest keyword must be forbidden'}
if(@($depRaw.policy.approved_repositories)-notcontains'PSGallery'){throw 'PSGallery approved repository missing'}

$dep=Get-PcDependencyLock
if($dep.Error){throw "dependency lock reader failed: $($dep.Error)"}
if(@($dep.RuntimeDependencies).Count-ne0){throw 'runtime dependency reader count must be zero'}
$deferred=Test-PcDependencyRequest -Lock $dep -Name 'ImportExcel' -Version '1.2.3' -Repository 'PSGallery'
if([string]$deferred.Decision-ne'DENY'){throw 'deferred dependency request must be denied'}
$latest=Test-PcDependencyRequest -Lock $dep -Name 'ImportExcel' -Version 'latest' -Repository 'PSGallery'
if([string]$latest.Decision-ne'DENY'){throw 'floating latest dependency request must be denied'}
$unknown=Test-PcDependencyRequest -Lock $dep -Name 'Unknown.Module' -Version '1.0.0' -Repository 'PSGallery'
if([string]$unknown.Decision-ne'DENY'){throw 'unknown dependency request must be denied'}
$auto=Test-PcDependencyRequest -Lock $dep -Name 'ImportExcel' -Version '1.2.3' -Repository 'PSGallery' -AutoInstall $true
if([string]$auto.Decision-ne'DENY'){throw 'runtime automatic dependency request must be denied'}

$synthetic=[pscustomobject]@{
  Error=$null
  Policy=[pscustomobject]@{runtime_auto_install=$false;approved_repositories=@('PSGallery')}
  ApprovedOnDemand=@([pscustomobject]@{name='Pinned.Module';repository='PSGallery';exact_version='2.4.6';state='APPROVED'})
}
$ok=Test-PcDependencyRequest -Lock $synthetic -Name 'Pinned.Module' -Version '2.4.6' -Repository 'PSGallery'
if([string]$ok.Decision-ne'ALLOW_GATED' -or [string]$ok.Level-ne'L2'){throw 'exact pinned approved dependency must reach L2 gate'}
$wrong=Test-PcDependencyRequest -Lock $synthetic -Name 'Pinned.Module' -Version '2.4.7' -Repository 'PSGallery'
if([string]$wrong.Decision-ne'DENY'){throw 'wrong dependency version must be denied'}
if([int]$cfg.pslib_audit.lot6_dependency_lock.runtime_dependencies-ne0){throw 'lot6 runtime dependency count must be zero'}
if([bool]$cfg.pslib_audit.lot6_dependency_lock.runtime_auto_install){throw 'lot6 auto-install must be false'}
if(-not[bool]$cfg.pslib_audit.lot6_dependency_lock.exact_version_required){throw 'lot6 exact version requirement missing'}
Write-Host 'PC_COMMAND_V103_DEPENDENCY_LOCK_OK'

# FB-043 / v1.0.4: power snapshot must remain read-only and dependency-free.
if(-not(Get-Command Get-PcPowerSnapshot -ErrorAction SilentlyContinue)){throw 'power snapshot missing'}
$pw=Get-PcPowerSnapshot -TtlSeconds 0
if(-not[bool]$pw.ReadOnly){throw 'power snapshot must be read-only'}
if([bool]$pw.NetworkTrafficGenerated){throw 'power snapshot must generate zero network traffic'}
if([bool]$pw.PowerPlanChanged){throw 'power snapshot must not change power plan'}
if([bool]$pw.BatteryChanged){throw 'power snapshot must not change battery state'}
if([bool]$pw.ExternalModuleRequired){throw 'power snapshot must not require external modules'}
if([bool]$pw.WinFormsLoaded){throw 'power snapshot must not load WinForms'}
if($pw.BatteryPresent -and $null-ne$pw.ChargePercent){
  if([int]$pw.ChargePercent-lt0 -or [int]$pw.ChargePercent-gt100){throw 'battery percentage out of range'}
}
$ioText=Get-Content (Join-Path $root 'pc-command\v5\lib\io.ps1') -Raw -Encoding UTF8
$powerStart=$ioText.IndexOf('function Get-PcPowerSnapshot')
if($powerStart-lt0){throw 'power snapshot source block missing'}
$powerFn=$ioText.Substring($powerStart)
foreach($forbidden in @('/setactive','/change','Set-CimInstance','System.Windows.Forms','Set-ItemProperty','/setacvalueindex','/setdcvalueindex')){
  if($powerFn -match [regex]::Escape($forbidden)){throw "forbidden power primitive present: $forbidden"}
}
if(-not[bool]$cfg.pslib_audit.lot7_power.read_only){throw 'lot7 power must be read-only'}
if([bool]$cfg.pslib_audit.lot7_power.winforms){throw 'lot7 WinForms must be false'}
if([bool]$cfg.pslib_audit.lot7_power.power_plan_change){throw 'lot7 power-plan changes must be false'}
if([bool]$cfg.pslib_audit.lot7_power.battery_change){throw 'lot7 battery changes must be false'}
if([bool]$cfg.pslib_audit.lot7_power.network_traffic){throw 'lot7 network traffic must be false'}
if([bool]$cfg.pslib_audit.lot7_power.external_module_required){throw 'lot7 external module must be false'}
Write-Host 'PC_COMMAND_V104_POWER_SNAPSHOT_OK'

# FB-044 / v1.0.5: local software inventory must remain registry-only, zero-traffic and read-only.
if(-not(Get-Command Get-PcLocalSoftwareInventory -ErrorAction SilentlyContinue)){throw 'local software inventory missing'}
$sw=Get-PcLocalSoftwareInventory -TtlSeconds 0 -MaxItems 20
if(-not[bool]$sw.ReadOnly){throw 'software inventory must be read-only'}
if([bool]$sw.NetworkTrafficGenerated){throw 'software inventory must generate zero network traffic'}
if([bool]$sw.WingetListExecuted){throw 'software inventory must not execute winget list'}
if([bool]$sw.AppxEnumerated){throw 'software inventory must not enumerate AppX in baseline'}
if([bool]$sw.InstallActionPerformed){throw 'software inventory must not install packages'}
if([bool]$sw.UninstallActionPerformed){throw 'software inventory must not uninstall packages'}
if([bool]$sw.UpdateActionPerformed){throw 'software inventory must not update packages'}
if([bool]$sw.ExternalModuleRequired){throw 'software inventory must not require external modules'}
if([int]$sw.RegistryPathsRead-ne3){throw 'software inventory must read exactly 3 Uninstall registry paths'}
if(@($sw.Items).Count-gt20){throw 'software inventory result must remain bounded'}
$ioText=Get-Content (Join-Path $root 'pc-command\v5\lib\io.ps1') -Raw -Encoding UTF8
$softStart=$ioText.IndexOf('function Get-PcLocalSoftwareInventory')
if($softStart-lt0){throw 'software inventory source block missing'}
$softFn=$ioText.Substring($softStart)
foreach($forbidden in @('winget list','Get-AppxPackage','Install-Package','Uninstall-Package','Install-Module','Install-PSResource','Start-BitsTransfer','Invoke-WebRequest','Invoke-RestMethod')){
  if($softFn -match [regex]::Escape($forbidden)){throw "forbidden software inventory primitive present: $forbidden"}
}
if(-not[bool]$cfg.pslib_audit.lot8_local_software.read_only){throw 'lot8 must be read-only'}
if([bool]$cfg.pslib_audit.lot8_local_software.winget_list){throw 'lot8 winget list must be false'}
if([bool]$cfg.pslib_audit.lot8_local_software.appx_baseline){throw 'lot8 AppX baseline must be false'}
if([bool]$cfg.pslib_audit.lot8_local_software.network_traffic){throw 'lot8 network traffic must be false'}
if([bool]$cfg.pslib_audit.lot8_local_software.install_action){throw 'lot8 install action must be false'}
if([bool]$cfg.pslib_audit.lot8_local_software.uninstall_action){throw 'lot8 uninstall action must be false'}
if([bool]$cfg.pslib_audit.lot8_local_software.update_action){throw 'lot8 update action must be false'}
if([bool]$cfg.pslib_audit.lot8_local_software.external_module_required){throw 'lot8 external module must be false'}
if(-not[bool]$cfg.pslib_audit.lot8_local_software.local_view_only){throw 'lot8 must remain Local-view only'}
Write-Host 'PC_COMMAND_V105_LOCAL_SOFTWARE_OK'

