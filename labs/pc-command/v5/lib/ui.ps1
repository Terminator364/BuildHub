function Get-PcBar {
  param([int]$Percent,[int]$Width=30)
  if($Percent-lt0){$Percent=0};if($Percent-gt100){$Percent=100}
  $filled=[math]::Floor(($Percent/100.0)*$Width)
  return '['+('#'*$filled)+('-'*($Width-$filled))+']'
}

function Write-PcHeader {
  param($App,$Config,$Sync,$Conversation,$UpdateInfo,[string]$Spinner)
  $os=Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
  $free=if($os){[math]::Round($os.FreePhysicalMemory/1024,0)}else{0}
  $drive=if(Get-Process GoogleDriveFS -ErrorAction SilentlyContinue){'ACTIF'}else{'ARRETE'}
  Write-Host '================================================================================' -ForegroundColor Cyan
  Write-Host (" PC COMMAND  v$($Config.version)   $Spinner  MOTEUR VIVANT") -ForegroundColor Cyan
  Write-Host '================================================================================' -ForegroundColor Cyan
  Write-Host ("RAM libre : $free MB | Drive : $drive | Budget PC COMMAND : $($Config.limits.ram_budget_mb) MB")
  Write-Host ("Moteur : $($App.EngineSeconds)s | Internet : $($App.SyncSeconds)s | Affichage : $($App.DisplaySeconds)s | Mode : $($App.Mode)")
  Write-Host ("Transport : $($Config.state.transport) | RX observe : $([math]::Round($script:PcSessionRxBytes/1KB,1)) KB | Echecs sync : $script:PcSyncFailures")
  if($UpdateInfo -and $UpdateInfo.Available){Write-Host ("MISE A JOUR DISPONIBLE : v$($UpdateInfo.Version)") -ForegroundColor Yellow}
  if($Conversation){
    $life=Get-PcLifecycleView $Conversation
    Write-Host ("Conversation : $($Conversation.label) | "+$life.Label+" | "+$life.Detail) -ForegroundColor $life.Color
  }
  if(-not $Sync.Online){Write-Host 'MODE OFFLINE/CACHE : dernier etat fiable affiche.' -ForegroundColor Yellow}
  Write-Host ''
}

function Write-PcGeneral {
  param($Overview)
  Write-Host 'ACCUEIL / CONVERSATIONS CONNECTEES' -ForegroundColor Cyan
  Write-Host ''
  if(-not $Overview -or @($Overview.conversations).Count-eq0){Write-Host 'Aucune conversation connectee.' -ForegroundColor Yellow;return}
  $i=1
  foreach($c in @($Overview.conversations|Select-Object -First 10)){
    $pct=if($null-ne$c.progress_estimate){[int]$c.progress_estimate}else{0}
    $life=Get-PcLifecycleView $c
    Write-Host ("[$i] $($c.label) | $($c.short_code)") -ForegroundColor Green
    Write-Host ('    '+(Get-PcBar $pct 36)+' '+$pct+'% | '+$life.Label) -ForegroundColor $life.Color
    Write-Host ('    Activite   : '+$life.Detail) -ForegroundColor $life.Color
    if($c.current_action){Write-Host ('    Maintenant : '+$c.current_action)}
    if($c.next_step){Write-Host ('    Ensuite    : '+$c.next_step) -ForegroundColor DarkGray}
    Write-Host ''
    $i++
  }
}

function Write-PcConversation {
  param($Conversation,[string]$HistoryFile)
  $cp=Get-PcConversationProgress $Conversation; $life=Get-PcLifecycleView $Conversation; $risk=Get-PcRisk $Conversation
  $eta=Get-PcEta $HistoryFile ([string]$Conversation.conversation_id) $cp.Percent $cp.MacroCount
  Write-Host ('CONVERSATION : '+$Conversation.label) -ForegroundColor Cyan
  Write-Host ('Objectif     : '+$Conversation.objective)
  Write-Host ('Etat         : '+$life.Label+' | '+$life.Detail) -ForegroundColor $life.Color
  Write-Host ('Avancement   : '+(Get-PcBar $cp.Percent 42)+' '+$cp.Percent+'%')
  Write-Host ("Macro-taches : $($cp.MacroCount) | actives $($cp.Active) | attente $($cp.Waiting) | bloquees $($cp.Blocked)")
  Write-Host ('Risque       : '+$risk.Level+' ('+$risk.Score+'/100) | ETA: '+$eta) -ForegroundColor $(if($risk.Score-ge60){'Red'}elseif($risk.Score-ge30){'Yellow'}else{'Green'})
  Write-Host ''
  $i=1
  foreach($m in @($Conversation.macro_tasks|Select-Object -First 10)){
    $mp=Get-PcMacroProgress $m
    Write-Host ("[$i] $($m.title) | $($m.state)") -ForegroundColor $(if($m.state-eq'BLOCKED'){'Red'}elseif($m.state-eq'WAITING'){'Yellow'}else{'Green'})
    Write-Host ('    '+(Get-PcBar $mp.Percent 30)+' '+$mp.Percent+'% | fiabilite '+$mp.Confidence+'%')
    if($m.current_action){Write-Host ('    En cours : '+$m.current_action)}
    Write-Host ''
    $i++
  }
}

function Write-PcMacro {
  param($Macro,[int]$MaxVisible=20)
  $mp=Get-PcMacroProgress $Macro
  Write-Host ('MACRO-TACHE : '+$Macro.title) -ForegroundColor Cyan
  Write-Host ('Etat        : '+$Macro.state)
  Write-Host ('Avancement  : '+(Get-PcBar $mp.Percent 44)+' '+$mp.Percent+'%')
  Write-Host ('Fiabilite   : '+$mp.Confidence+'%')
  if($Macro.current_action){Write-Host ('En cours    : '+$Macro.current_action)}
  if($Macro.last_success){Write-Host ('Dernier OK  : '+$Macro.last_success) -ForegroundColor Green}
  if($Macro.next_step){Write-Host ('Prochaine   : '+$Macro.next_step)}
  if($Macro.blocker){Write-Host ('Blocage     : '+$Macro.blocker) -ForegroundColor Red}else{Write-Host 'Blocage     : aucun' -ForegroundColor Green}
  Write-Host ''
  $v=Get-PcVisibleMicroTasks $Macro $MaxVisible
  if($v.Total-eq0){Write-Host 'Micro-taches detaillees non publiees dans ce snapshot.' -ForegroundColor DarkGray}
  else{
    Write-Host ("MICRO-TACHES : $($v.Total) total | $($v.Hidden) masquee(s) par condensation") -ForegroundColor Cyan
    foreach($t in @($v.Items)){
      $mark=switch([string]$t.state){'DONE'{'OK'}'ACTIVE'{'>>'}'BLOCKED'{'!!'}default{'..'}}
      $pct=[int][math]::Round((Get-PcMicroCompletion $t)*100,0)
      Write-Host ("  $mark $($t.title) - $pct%")
      if($t.evidence){Write-Host ('      preuve: '+$t.evidence) -ForegroundColor DarkGray}
    }
  }
}

function Write-PcTimeline {
  param($Conversation)
  Write-Host 'CHRONOLOGIE / EVENEMENTS RECENTS' -ForegroundColor Cyan
  Write-Host ''
  foreach($e in @($Conversation.recent_events|Select-Object -Last 20)){
    Write-Host ('  '+$e.at+' | '+$e.type) -ForegroundColor DarkCyan
    Write-Host ('      '+$e.summary)
  }
}

function Write-PcSources {
  param($Config,$Sync)
  Write-Host 'SOURCES / ADAPTATEURS' -ForegroundColor Cyan
  Write-Host ''
  Write-Host 'Noyau local-first : cache disque + moteur PowerShell.' -ForegroundColor Green
  Write-Host ('Transport actif  : '+$Config.state.transport+' / '+$Config.state.repo)
  Write-Host ('Etat transport    : '+$(if($Sync.Online){'ONLINE'}else{'OFFLINE / CACHE'}))
  Write-Host ''
  Write-Host 'Adaptateurs : ChatGPT/PCCONNECT, GitHub, Drive, Telegram/Delivery, TLIB, Web/YouTube, WMI Windows, Desktop Commander.'
  Write-Host 'Une source n est affichee comme observee que si un evenement ou une preuve existe.' -ForegroundColor Yellow
  Write-Host 'Aucun mot de passe ne doit etre stocke dans PC COMMAND.' -ForegroundColor Yellow
}

function Write-PcLocal {
  param($LocalEvents)
  Write-Host 'ACTIVITE LOCALE DU PC' -ForegroundColor Cyan
  Write-Host ''
  if($LocalEvents.Count-eq0){Write-Host 'Aucune nouvelle activite locale observee.'}
  else{foreach($e in $LocalEvents){Write-Host ('  '+$e.At.ToString('HH:mm:ss')+' | '+$e.Text)}}
  Write-Host ''
  Write-Host 'Observation WMI locale: aucun appel Desktop Commander requis.' -ForegroundColor DarkGray
}

function Write-PcSettings {
  param($App,$Config)
  Write-Host 'PARAMETRES' -ForegroundColor Cyan
  Write-Host ''
  Write-Host ("Version               : $($Config.version)")
  Write-Host ("Sync Internet          : $($App.SyncSeconds) s  | [1] alterner 5/10/30")
  Write-Host ("Calcul moteur          : $($App.EngineSeconds) s | [2] alterner 5/10/30")
  Write-Host ("Rafraichissement ecran : $($App.DisplaySeconds) s | [3] alterner 10/20/30")
  Write-Host ("Mode                   : $($App.Mode) | [4] AUTO/ECO")
  Write-Host ("RAM budget             : $($Config.limits.ram_budget_mb) MB")
  Write-Host ("Conversations max      : $($Config.limits.max_conversations)")
  Write-Host ''
  Write-Host 'CODE NOUVELLE CONVERSATION :' -ForegroundColor Green
  Write-Host 'PCCONNECT|v3|state=Terminator364/PC-COMMAND-STATE|code=Terminator364/BuildHub|slot=AUTO|max=10'
  Write-Host ''
  Write-Host '[C] Copier code  [X] Rapport PDF  [D] Export Drive  [U] Verifier update'
}

function Write-PcFooter {
  param([string]$View)
  Write-Host ''
  Write-Host '--------------------------------------------------------------------------------' -ForegroundColor DarkGray
  switch($View){
    'general'{Write-Host '[1-9] Conversation  [S] Sources  [L] Local  [P] Parametres  [X] Rapport  [R] Sync  [Q] Fermer'}
    'conversation'{Write-Host '[1-9] Macro-tache  [T] Chronologie  [B] Retour  [P] Parametres  [X] Rapport  [R] Sync  [Q] Fermer'}
    'macro'{Write-Host '[B] Retour  [T] Chronologie  [P] Parametres  [X] Rapport  [R] Sync  [Q] Fermer'}
    default{Write-Host '[A] Accueil  [B] Retour  [P] Parametres  [R] Sync  [Q] Fermer'}
  }
}
