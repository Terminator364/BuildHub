param([string]$Root = (Split-Path -Parent $PSScriptRoot),[switch]$SmokeTest)
$ErrorActionPreference='SilentlyContinue'
$createdNew=$true
$mutex=$null
if(-not$SmokeTest){
  $createdNew=$false
  $mutex=New-Object Threading.Mutex($true,'Local\PC_COMMAND_SINGLE_INSTANCE',[ref]$createdNew)
  if(-not$createdNew){exit 0}
}
[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$OutputEncoding=[Console]::OutputEncoding

$Lib=Join-Path $PSScriptRoot 'lib'
. (Join-Path $Lib 'engine.ps1')
. (Join-Path $Lib 'io.ps1')
. (Join-Path $Lib 'report.ps1')
. (Join-Path $Lib 'ui.ps1')

$Defaults=Get-Content (Join-Path $PSScriptRoot 'config.default.json') -Raw -Encoding UTF8|ConvertFrom-Json
$Paths=Initialize-PcPaths $Root
[void](Initialize-PcStateRepo $Defaults $Paths)

$App=[pscustomobject]@{
  SyncSeconds=[double]$Defaults.cadence.internet_sync_seconds
  EngineSeconds=[double]$Defaults.cadence.engine_recalc_seconds
  DisplaySeconds=[int]$Defaults.cadence.display_refresh_seconds
  Mode='AUTO'
}
if(Test-Path $Paths.LocalConfig){
  try{
    $lc=Get-Content $Paths.LocalConfig -Raw -Encoding UTF8|ConvertFrom-Json
    if($lc.internet_sync_seconds){$App.SyncSeconds=[double]$lc.internet_sync_seconds}
    if($lc.engine_recalc_seconds){$App.EngineSeconds=[double]$lc.engine_recalc_seconds}
    if($lc.display_refresh_seconds){$App.DisplaySeconds=[int]$lc.display_refresh_seconds}
    if($lc.mode){$App.Mode=[string]$lc.mode}
  }catch{}
}

$View='general';$BackView='general';$ConversationIndex=0;$MacroIndex=0;$MicroIndex=0
$NeedDetail=$false
$Sync=Read-PcStateLocal $Defaults $Paths $ConversationIndex
$Feedback=Read-PcFeedbackLocal $Paths
$LastPullStart=[datetime]::MinValue
$LastCalc=[datetime]::MinValue
$LastDisplay=[datetime]::MinValue
$LastSpinner=[datetime]::MinValue
$LastUpdateCheck=[datetime]::MinValue
$UpdateInfo=$null
$SpinnerIndex=0
$Cycle=0
$LocalEvents=New-Object System.Collections.Generic.List[object]
$script:LastInputAck='Pret.'
$script:LastInputAckOk=$true
$script:LastInputAckAt=Get-Date
$EnableProcessWatcher=($Defaults.local_observability -and [bool]$Defaults.local_observability.process_watcher)
$ManifestUrl='https://raw.githubusercontent.com/Terminator364/BuildHub/lab/pc-command-v070/labs/pc-command/v5/manifest.json'

if($EnableProcessWatcher){
  try{
    Unregister-Event -SourceIdentifier PcCommandV5Proc -ErrorAction SilentlyContinue
    Register-WmiEvent -Class Win32_ProcessStartTrace -SourceIdentifier PcCommandV5Proc|Out-Null
  }catch{}
}

function Add-LocalPcEvent([string]$Text){
  if(-not$Text){return}
  $LocalEvents.Insert(0,[pscustomobject]@{At=Get-Date;Text=$Text})
  while($LocalEvents.Count-gt15){$LocalEvents.RemoveAt($LocalEvents.Count-1)}
}

function Drain-LocalPcEvents{
  if(-not$EnableProcessWatcher){return}
  foreach($ev in @(Get-Event -SourceIdentifier PcCommandV5Proc -ErrorAction SilentlyContinue)){
    $pid2=[int]$ev.SourceEventArgs.NewEvent.ProcessID
    $name=[string]$ev.SourceEventArgs.NewEvent.ProcessName
    $p=Get-CimInstance Win32_Process -Filter "ProcessId=$pid2" -ErrorAction SilentlyContinue
    $cmd=if($p){[string]$p.CommandLine}else{''}
    $h=$null
    if($cmd-match'PC_COMMAND'){ }
    elseif($cmd-match'firefox|msedge|brave|falkon|qutebrowser|helium'){$h='Navigateur/test web lance'}
    elseif($cmd-match'node|npm|npx'){$h='Processus Node/Desktop Commander'}
    elseif($name-match'powershell|pwsh|cmd'){$h='Commande Windows locale'}
    if($h){Add-LocalPcEvent $h}
    Remove-Event -EventIdentifier $ev.EventIdentifier -ErrorAction SilentlyContinue
  }
}

function Refresh-PcLocalState {
  $detail=($View -in @('conversation','macro','micro','timeline','requirements'))
  $script:Sync=Read-PcStateLocal $Defaults $Paths $ConversationIndex -NeedDetail:$detail
  if($script:PcLastPullOkAt){
    $age=((Get-Date)-$script:PcLastPullOkAt).TotalSeconds
    $script:Sync.Online=($age -le [math]::Max(20,$App.SyncSeconds*4))
    $script:Sync.SyncedAt=$script:PcLastPullOkAt
  }
}



function Set-PcInputAck {
  param([string]$Key,[string]$Message,[bool]$Ok=$true)
  $script:LastInputAck='['+$Key+'] '+$(if($Ok){'OK'}else{'NON DISPONIBLE'})+' - '+$Message
  $script:LastInputAckOk=$Ok
  $script:LastInputAckAt=Get-Date
  $script:LastDisplay=[datetime]::MinValue
}

function Get-PcAllowedKeysForView {
  param([string]$CurrentView)
  switch($CurrentView){
    'general'      {return @('A','1','2','3','4','5','6','7','8','9','F','V','X','S','L','P','Y','H','R','Q')}
    'conversation' {return @('A','B','1','2','3','4','5','6','7','8','9','C','T','F','V','S','P','X','R','Q')}
    'macro'        {return @('A','B','1','2','3','4','5','6','7','8','9','C','T','F','V','P','X','R','Q')}
    'micro'        {return @('A','B','C','T','F','V','P','X','R','Q')}
    'feedback'     {return @('A','B','V','C','P','R','Q')}
    'versions'     {return @('A','B','F','U','P','R','Q')}
    'requirements' {return @('A','B','F','V','T','P','R','Q')}
    'timeline'     {return @('A','B','C','F','V','P','R','Q')}
    'sources'      {return @('A','B','L','F','P','R','Q')}
    'local'        {return @('A','B','S','P','R','Q')}
    'settings'     {return @('A','B','1','2','3','4','C','U','Y','H','R','Q')}
    'reports'      {return @('A','B','G','O','D','E','P','R','Q')}
    'health'       {return @('A','B','P','R','Q')}
    'help'         {return @('A','B','P','F','V','Q')}
    default        {return @('A','B','P','R','Q')}
  }
}

function Ensure-PcChannelDetail {
  if($script:Sync.Channel){return $true}
  try{
    $d=Read-PcStateLocal $Defaults $Paths $ConversationIndex -NeedDetail
    if($d.Channel){$script:Sync=$d;return $true}
  }catch{}
  return $false
}

function Process-PcKey {
  if(-not[Console]::KeyAvailable){return $false}
  $k=[Console]::ReadKey($true).KeyChar.ToString().ToUpperInvariant()
  $allowed=@(Get-PcAllowedKeysForView $View)
  if($allowed -notcontains $k){
    Set-PcInputAck $k ("action absente de la fenetre "+$View) $false
    return $true
  }
  Set-PcInputAck $k ("commande recue dans "+$View) $true

  if($k-eq'Q'){
    Unregister-Event -SourceIdentifier PcCommandV5Proc -ErrorAction SilentlyContinue
    try{$mutex.ReleaseMutex()}catch{}
    exit 0
  }

  if($k-eq'A'){
    $script:View='general'
    $script:BackView='general'
  }
  elseif($k-eq'B'){
    if($View-eq'micro'){$script:View='macro'}
    elseif($View -in @('macro','timeline','requirements')){$script:View='conversation'}
    elseif($View -in @('feedback','versions','sources','local','settings','help','reports','health')){$script:View=$script:BackView}
    elseif($View-eq'conversation'){$script:View='general'}
    else{$script:View='general'}
  }
  elseif($k-eq'R'){
    [void](Start-PcStatePull $Defaults $Paths)
    $script:LastPullStart=Get-Date
    Add-LocalPcEvent 'Synchronisation demandee; interface reste interactive.'
  }
  elseif($k-eq'H'){$script:BackView=$View;$script:View='help'}
  elseif($k-eq'F'){$script:BackView=$View;$script:View='feedback'}
  elseif($k-eq'V'){$script:BackView=$View;$script:View='versions'}
  elseif($k-eq'S'){$script:BackView=$View;$script:View='sources'}
  elseif($k-eq'L'){$script:BackView=$View;$script:View='local'}
  elseif($k-eq'P'){$script:BackView=$View;$script:View='settings'}
  elseif($k-eq'T' -and $Sync.Channel){$script:BackView=$View;$script:View='timeline'}
  elseif($k-eq'C' -and $View-eq'settings'){
    Set-Clipboard 'PCCONNECT|v4|state=Terminator364/PC-COMMAND-STATE|code=Terminator364/BuildHub|slot=AUTO|max=10'
    Add-LocalPcEvent 'Code PCCONNECT copie.'
    Set-PcInputAck $k 'code PCCONNECT copie dans le presse-papiers' $true
  }
  elseif($k-eq'C'){
    if(Ensure-PcChannelDetail){
      $script:BackView=$View;$script:View='requirements'
      Set-PcInputAck $k 'cahier A+B+C ouvert' $true
    }else{
      Set-PcInputAck $k 'aucune conversation detaillee disponible' $false
    }
  }
  elseif($k-eq'X'){
    $script:BackView=$View
    $script:View='reports'
  }
  elseif($k-eq'Y'){
    $script:BackView=$View
    $script:View='health'
  }
  elseif($k-eq'G' -and $View-eq'reports'){
    $rep=New-PcReport $Defaults $Sync.Overview $Sync.Channel $Paths
    $made=$(if($rep.Pdf){$rep.Pdf}else{$rep.Html})
    Add-LocalPcEvent ("Rapport cree: "+$made)
    Set-PcInputAck $k ("rapport genere: "+[IO.Path]::GetFileName($made)) ([bool]$made)
  }
  elseif($k-eq'O' -and $View-eq'reports'){
    $last=Get-ChildItem $Paths.Reports -File -ErrorAction SilentlyContinue|Where-Object Extension -eq '.pdf'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
    if($last){Start-Process $last.FullName;Add-LocalPcEvent ('Ouverture '+$last.Name);Set-PcInputAck $k ('ouverture '+$last.Name) $true}
    else{Set-PcInputAck $k 'aucun PDF disponible' $false}
  }
  elseif($k-eq'D' -and $View-eq'reports'){
    $last=Get-ChildItem $Paths.Reports -File -ErrorAction SilentlyContinue|Where-Object Extension -eq '.pdf'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
    if($last){$ex=Export-PcReportToDrive $last.FullName;Add-LocalPcEvent $ex.Message;Set-PcInputAck $k $ex.Message ([bool]$ex.Success)}
    else{Set-PcInputAck $k 'aucun PDF a exporter' $false}
  }
  elseif($k-eq'E' -and $View-eq'reports'){
    Start-Process explorer.exe -ArgumentList $Paths.Reports
    Set-PcInputAck $k 'dossier des rapports ouvert' $true
  }
  elseif($k-eq'D' -and $View-eq'settings'){
    $last=Get-ChildItem $Paths.Reports -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
    if($last){$ex=Export-PcReportToDrive $last.FullName;Add-LocalPcEvent $ex.Message}
  }
  elseif($k-eq'U'){
    if(Start-PcUpdateProbe $Defaults $Paths){
      $script:LastUpdateCheck=Get-Date
      Add-LocalPcEvent 'Verification mise a jour lancee en arriere-plan.'
      Set-PcInputAck $k 'verification update lancee en arriere-plan' $true
    }else{
      Set-PcInputAck $k 'verification update deja active ou indisponible' $false
    }
  }
  elseif($View-eq'settings' -and $k-match'^[1-4]$'){
    if($k-eq'1'){
      $vals=@([double]3,[double]5,[double]10,[double]30)
      $cur=[array]::IndexOf($vals,[double]$App.SyncSeconds)
      if($cur-lt0){$cur=0};$App.SyncSeconds=$vals[($cur+1)%$vals.Count]
    }
    elseif($k-eq'2'){
      $vals=@([double]3.5,[double]5,[double]10,[double]30)
      $cur=[array]::IndexOf($vals,[double]$App.EngineSeconds)
      if($cur-lt0){$cur=0};$App.EngineSeconds=$vals[($cur+1)%$vals.Count]
    }
    elseif($k-eq'3'){
      $vals=@(5,10,20,30)
      $cur=[array]::IndexOf($vals,[int]$App.DisplaySeconds)
      if($cur-lt0){$cur=1};$App.DisplaySeconds=$vals[($cur+1)%$vals.Count]
    }
    elseif($k-eq'4'){
      $profiles=@('AUTO','ECO','RAPIDE')
      $cur=[array]::IndexOf($profiles,[string]$App.Mode)
      if($cur-lt0){$cur=0}
      $App.Mode=$profiles[($cur+1)%$profiles.Count]
      if($App.Mode-eq'ECO'){$App.SyncSeconds=10;$App.EngineSeconds=10;$App.DisplaySeconds=20}
      elseif($App.Mode-eq'RAPIDE'){$App.SyncSeconds=3;$App.EngineSeconds=3.5;$App.DisplaySeconds=10}
      else{$App.SyncSeconds=[double]$Defaults.cadence.internet_sync_seconds;$App.EngineSeconds=[double]$Defaults.cadence.engine_recalc_seconds;$App.DisplaySeconds=[int]$Defaults.cadence.display_refresh_seconds}
    }
    Save-PcLocalSettings $Paths $App.SyncSeconds $App.EngineSeconds $App.DisplaySeconds $App.Mode
    Set-PcInputAck $k ("parametre applique: sync "+$App.SyncSeconds+"s, moteur "+$App.EngineSeconds+"s, affichage "+$App.DisplaySeconds+"s, profil "+$App.Mode) $true
  }
  elseif($k-match'^[1-9]$' -and $Sync.Overview){
    $idx=[int]$k-1
    if($View-eq'general' -and $idx-lt@($Sync.Overview.conversations).Count){
      $script:ConversationIndex=$idx
      $id=[string]$Sync.Overview.conversations[$idx].id
      $cache=Join-Path $Paths.Cache ("channel-$id.json")
      if(Test-Path $cache){try{$script:Sync.Channel=Get-Content $cache -Raw -Encoding UTF8|ConvertFrom-Json}catch{}}
      $script:View='conversation'
      Set-PcInputAck $k 'conversation ouverte' $true
    }
    elseif($View-eq'conversation' -and $Sync.Channel -and $idx-lt@($Sync.Channel.macro_tasks).Count){
      $script:MacroIndex=$idx;$script:View='macro';Set-PcInputAck $k 'macro-tache ouverte' $true
    }
    elseif($View-eq'macro' -and $Sync.Channel -and @($Sync.Channel.macro_tasks).Count-gt$MacroIndex){
      $m=$Sync.Channel.macro_tasks[$MacroIndex]
      if($idx-lt@($m.micro_tasks).Count){$script:MicroIndex=$idx;$script:View='micro';Set-PcInputAck $k 'micro-tache ouverte' $true}
      else{Set-PcInputAck $k 'aucune micro-tache a ce numero' $false}
    }
    else{Set-PcInputAck $k 'aucun element a ce numero dans cette vue' $false}
  }

  Refresh-PcLocalState
  $script:Feedback=Read-PcFeedbackLocal $Paths
  $script:LastDisplay=[datetime]::MinValue
  return $true
}

if($SmokeTest){
  try{
    Start-PcFrame
    $conv=$Sync.Channel
    Write-PcHeader $App $Defaults $Sync $conv $UpdateInfo '|'
    Write-PcGeneral $Sync.Overview $Feedback $Defaults $Sync $UpdateInfo
    Write-PcFooter 'general'
    Write-Output 'PC_COMMAND_SMOKE_OK'
    Unregister-Event -SourceIdentifier PcCommandV5Proc -ErrorAction SilentlyContinue
    exit 0
  }catch{
    Write-Error ('PC_COMMAND_SMOKE_FAIL: '+$_.Exception.Message)
    Unregister-Event -SourceIdentifier PcCommandV5Proc -ErrorAction SilentlyContinue
    exit 41
  }
}

while($true){
  $now=Get-Date
  Drain-LocalPcEvents

  # Input first: navigation never waits for Internet.
  [void](Process-PcKey)

  # Complete any background git pull without blocking the UI.
  $pull=Complete-PcStatePull $Paths
  if($pull.Completed){
    if($pull.Success){Refresh-PcLocalState;$script:Feedback=Read-PcFeedbackLocal $Paths;Add-LocalPcEvent 'Etat distant synchronise.'}
    else{Add-LocalPcEvent 'Synchronisation impossible: dernier etat local conserve.'}
    $LastDisplay=[datetime]::MinValue
  }

  # Launch a tiny background git pull every requested interval.
  if(($now-$LastPullStart).TotalSeconds-ge$App.SyncSeconds -or $LastPullStart-eq[datetime]::MinValue){
    if(Start-PcStatePull $Defaults $Paths){$LastPullStart=$now}
  }

  # Nonblocking auto-update probe. A newer validated manifest triggers bootstrap+restart.
  $up=Complete-PcUpdateProbe $Defaults
  if($up.Completed){
    $script:UpdateInfo=$up
    if($up.Success -and $up.Available -and [bool]$Defaults.automation.auto_update){
      Add-LocalPcEvent ("Mise a jour automatique vers v"+$up.Version)
      $boot=Join-Path $Root 'PC_COMMAND_BOOTSTRAP.ps1'
      if(Test-Path $boot){
        Unregister-Event -SourceIdentifier PcCommandV5Proc -ErrorAction SilentlyContinue
        try{$mutex.ReleaseMutex()}catch{}
        Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$boot
        exit 0
      }
    }
  }
  if(($now-$LastUpdateCheck).TotalSeconds-ge[double]$Defaults.cadence.update_check_seconds -or $LastUpdateCheck-eq[datetime]::MinValue){
    if(Start-PcUpdateProbe $Defaults $Paths){$LastUpdateCheck=$now}
  }

  if(($now-$LastCalc).TotalSeconds-ge$App.EngineSeconds){
    $Cycle++
    if($Sync.Overview){Save-PcHistory $Sync.Overview $Paths.HistoryFile ([int]$Defaults.limits.history_max_bytes)}
    $LastCalc=$now
  }

  if(($now-$LastSpinner).TotalSeconds-ge1){
    $sp=@('|','/','-','\')[$SpinnerIndex%4];$SpinnerIndex++;$LastSpinner=$now
    $pct=0;$st='CACHE'
    if($Sync.Overview -and @($Sync.Overview.conversations).Count-gt0){
      $c=$Sync.Overview.conversations[[math]::Min($ConversationIndex,@($Sync.Overview.conversations).Count-1)]
      if($null-ne$c.progress_estimate){$pct=[int]$c.progress_estimate}
      if($c.lifecycle.state){$st=[string]$c.lifecycle.state}
    }
    $Host.UI.RawUI.WindowTitle="PC COMMAND v$($Defaults.version) $sp $st $pct%"
  }

  if(($now-$LastDisplay).TotalSeconds-ge$App.DisplaySeconds -or $LastDisplay-eq[datetime]::MinValue){
    try{
      Start-PcFrame
      $conv=$Sync.Channel
      Write-PcHeader $App $Defaults $Sync $conv $UpdateInfo @('|','/','-','\')[$SpinnerIndex%4]
      switch($View){
        'general'{Write-PcGeneral $Sync.Overview $Feedback $Defaults $Sync $UpdateInfo}
        'conversation'{if($conv){Write-PcConversation $conv $Paths.HistoryFile}else{Write-PcLine 'Detail local indisponible; [R] synchroniser.' -ForegroundColor Yellow}}
        'macro'{if($conv -and @($conv.macro_tasks).Count-gt$MacroIndex){Write-PcMacro $conv.macro_tasks[$MacroIndex] ([int]$Defaults.limits.max_visible_microtasks)}}
        'micro'{if($conv -and @($conv.macro_tasks).Count-gt$MacroIndex -and @($conv.macro_tasks[$MacroIndex].micro_tasks).Count-gt$MicroIndex){Write-PcMicro $conv.macro_tasks[$MacroIndex].micro_tasks[$MicroIndex]}}
        'timeline'{if($conv){Write-PcTimeline $conv}}
        'requirements'{if($conv){Write-PcRequirements $conv}}
        'feedback'{Write-PcFeedback $Feedback}
        'versions'{Write-PcVersions $Feedback $Defaults}
        'sources'{Write-PcSources $Defaults $Sync}
        'local'{Write-PcLocal $LocalEvents}
        'settings'{Write-PcSettings $App $Defaults $Sync $UpdateInfo}
        'reports'{Write-PcReportCenter $Defaults $Paths $conv}
        'health'{Write-PcHealth $Defaults $Sync $UpdateInfo}
        'help'{Write-PcHelp}
      }
      Write-PcFooter $View
      $ackColor=if($script:LastInputAckOk){'Green'}else{'Yellow'}
      Write-PcFooterLine ('Action: '+$script:LastInputAck) $ackColor
      Write-PcFooterLine ("Cycle $Cycle | etat local immediat | dernier pull: "+$(if($script:PcLastPullOkAt){$script:PcLastPullOkAt.ToString('HH:mm:ss')}else{'jamais'})) DarkGray
    }catch{
      Start-PcFrame
      Write-PcLine 'PC COMMAND - MODE SECOURS' -ForegroundColor Red
      Write-PcLine ('Erreur affichage: '+$_.Exception.Message) -ForegroundColor Yellow
      Write-PcFooterLine '[R] Resynchroniser  [A] Accueil  [Q] Fermer' Yellow
      Add-Content -Path (Join-Path $Root 'runtime-errors.log') -Value ((Get-Date).ToString('o')+' '+$_.Exception.Message)
    }
    $LastDisplay=$now
  }

  Start-Sleep -Milliseconds 100
}