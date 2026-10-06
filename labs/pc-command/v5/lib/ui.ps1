$script:PcFrameLine=0
$script:PcFrameMax=34
$script:PcFrameWidth=100
$script:PcFrameHeight=40

function Start-PcFrame {
  try{
    $script:PcFrameWidth=[math]::Max(60,[Console]::WindowWidth-1)
    $script:PcFrameHeight=[math]::Max(20,[Console]::WindowHeight-1)
    $script:PcFrameMax=[math]::Max(14,$script:PcFrameHeight-5)
    [Console]::Clear()
  }catch{
    Clear-Host
    $script:PcFrameWidth=100;$script:PcFrameHeight=40;$script:PcFrameMax=35
  }
  $script:PcFrameLine=0
}

function Write-PcLine {
  param([Parameter(Position=0)]$Object='',[Parameter(Position=1)][ConsoleColor]$ForegroundColor=[ConsoleColor]::Gray)
  if($script:PcFrameLine-ge$script:PcFrameMax){return}
  $s=if($null-eq$Object){''}else{[string]$Object}
  if($s.Length-ge$script:PcFrameWidth){$s=$s.Substring(0,[math]::Max(1,$script:PcFrameWidth-4))+'...'}
  try{[Console]::ForegroundColor=$ForegroundColor;[Console]::WriteLine($s);[Console]::ResetColor()}catch{Write-Host $s -ForegroundColor $ForegroundColor}
  $script:PcFrameLine++
}

function Write-PcFooterLine {
  param([Parameter(Position=0)]$Object='',[Parameter(Position=1)][ConsoleColor]$ForegroundColor=[ConsoleColor]::Gray)
  $s=if($null-eq$Object){''}else{[string]$Object}
  if($s.Length-ge$script:PcFrameWidth){$s=$s.Substring(0,[math]::Max(1,$script:PcFrameWidth-4))+'...'}
  try{[Console]::ForegroundColor=$ForegroundColor;[Console]::WriteLine($s);[Console]::ResetColor()}catch{Write-Host $s -ForegroundColor $ForegroundColor}
}

function Get-PcBar {
  param([int]$Percent,[int]$Width=30)
  if($Percent-lt0){$Percent=0};if($Percent-gt100){$Percent=100}
  $filled=[math]::Floor(($Percent/100.0)*$Width)
  '['+('#'*$filled)+('-'*($Width-$filled))+']'
}

function Write-PcHeader {
  param($App,$Config,$Sync,$Conversation,$UpdateInfo,[string]$Spinner)
  $net=if($Sync.Online){'ONLINE'}else{'CACHE/OFFLINE'}
  Write-PcLine '================================================================================' Cyan
  Write-PcLine (" PC COMMAND  v$($Config.version)   $Spinner  MOTEUR VIVANT   |   $net") Cyan
  Write-PcLine '================================================================================' Cyan
  if($UpdateInfo -and $UpdateInfo.Available){
    Write-PcLine ("Mise a jour v$($UpdateInfo.Version) detectee; installation automatique preparee.") Yellow
  }
}

function Write-PcGeneral {
  param($Overview,$Feedback)
  Write-PcLine 'ACCUEIL' Cyan
  Write-PcLine ''
  if(-not $Overview -or @($Overview.conversations).Count-eq0){
    Write-PcLine 'Aucune conversation connectee.' Yellow
    Write-PcLine 'Ouvrez [P] Parametres pour copier un code PCCONNECT.'
    return
  }
  $count=@($Overview.conversations).Count
  $fb=if($Feedback -and $Feedback.Index){[string]$Feedback.Index.last_feedback_id}else{'-'}
  Write-PcLine ("$count conversation(s) connectee(s) | dernier feedback : $fb") DarkCyan
  Write-PcLine ''
  $i=1
  foreach($x in @($Overview.conversations|Select-Object -First 10)){
    $pct=if($null-ne$x.progress_estimate){[int]$x.progress_estimate}else{0}
    $life=Get-PcLifecycleView $x
    Write-PcLine ("[$i] $($x.label) | $($x.short_code)") Green
    Write-PcLine ('    '+(Get-PcBar $pct 36)+' '+$pct+'% | '+$life.Label) $life.Color
    if($x.current_action){Write-PcLine ('    Maintenant : '+$x.current_action)}
    if($x.next_step){Write-PcLine ('    Ensuite    : '+$x.next_step) DarkGray}
    if($x.blocker){Write-PcLine ('    Blocage    : '+$x.blocker) Red}
    Write-PcLine ''
    $i++
  }
}

function Write-PcConversation {
  param($Conversation,[string]$HistoryFile)
  $cp=Get-PcConversationProgress $Conversation
  $life=Get-PcLifecycleView $Conversation
  $risk=Get-PcRisk $Conversation
  $eta=Get-PcEta $HistoryFile ([string]$Conversation.conversation_id) $cp.Percent $cp.MacroCount
  Write-PcLine ('CONVERSATION : '+$Conversation.label) Cyan
  Write-PcLine ('Objectif     : '+$Conversation.objective)
  Write-PcLine ('Etat         : '+$life.Label+' | '+$life.Detail) $life.Color
  Write-PcLine ('Avancement   : '+(Get-PcBar $cp.Percent 42)+' '+$cp.Percent+'%')
  Write-PcLine ("Macro-taches : $($cp.MacroCount) | actives $($cp.Active) | attente $($cp.Waiting) | bloquees $($cp.Blocked)")
  $riskColor=if($risk.Score-ge60){'Red'}elseif($risk.Score-ge30){'Yellow'}else{'Green'}
  Write-PcLine ('Risque       : '+$risk.Level+' ('+$risk.Score+'/100) | ETA: '+$eta) $riskColor
  Write-PcLine ''
  $i=1
  foreach($m in @($Conversation.macro_tasks|Select-Object -First 9)){
    $mp=Get-PcMacroProgress $m
    $col=if($m.state-eq'BLOCKED'){'Red'}elseif($m.state-eq'WAITING'){'Yellow'}else{'Green'}
    Write-PcLine ("[$i] $($m.title) | $($m.state)") $col
    Write-PcLine ('    '+(Get-PcBar $mp.Percent 30)+' '+$mp.Percent+'% | fiabilite '+$mp.Confidence+'%')
    if($m.current_action){Write-PcLine ('    En cours : '+$m.current_action)}
    Write-PcLine ''
    $i++
  }
}

function Write-PcMacro {
  param($Macro,[int]$MaxVisible=20)
  $mp=Get-PcMacroProgress $Macro
  Write-PcLine ('MACRO-TACHE : '+$Macro.title) Cyan
  Write-PcLine ('Etat        : '+$Macro.state)
  Write-PcLine ('Avancement  : '+(Get-PcBar $mp.Percent 44)+' '+$mp.Percent+'%')
  Write-PcLine ('Fiabilite   : '+$mp.Confidence+'%')
  if($Macro.current_action){Write-PcLine ('En cours    : '+$Macro.current_action)}
  if($Macro.last_success){Write-PcLine ('Dernier OK  : '+$Macro.last_success) Green}
  if($Macro.next_step){Write-PcLine ('Prochaine   : '+$Macro.next_step)}
  if($Macro.blocker){Write-PcLine ('Blocage     : '+$Macro.blocker) Red}else{Write-PcLine 'Blocage     : aucun' Green}
  Write-PcLine ''
  $v=Get-PcVisibleMicroTasks $Macro $MaxVisible
  if($v.Total-eq0){
    Write-PcLine 'Micro-taches detaillees non publiees dans ce snapshot.' DarkGray
  }else{
    Write-PcLine ("MICRO-TACHES : $($v.Total) total | $($v.Hidden) condensee(s)") Cyan
    $i=1
    foreach($t in @($v.Items|Select-Object -First 9)){
      $mark=switch([string]$t.state){'DONE'{'OK'}'ACTIVE'{'>>'}'BLOCKED'{'!!'}default{'..'}}
      $pct=[int][math]::Round((Get-PcMicroCompletion $t)*100,0)
      Write-PcLine ("  [$i] $mark $($t.title) - $pct%")
      if($t.evidence){Write-PcLine ('      preuve: '+$t.evidence) DarkGray}
      $i++
    }
  }
}

function Write-PcMicro {
  param($Micro)
  Write-PcLine 'MICRO-TACHE / DETAIL' Cyan
  Write-PcLine ''
  if(-not$Micro){Write-PcLine 'Micro-tache indisponible.' Yellow;return}
  $pct=[int][math]::Round((Get-PcMicroCompletion $Micro)*100,0)
  Write-PcLine ('Titre       : '+$Micro.title)
  Write-PcLine ('Etat        : '+$Micro.state)
  Write-PcLine ('Avancement  : '+(Get-PcBar $pct 44)+' '+$pct+'%')
  if($Micro.weight){Write-PcLine ('Poids       : '+$Micro.weight)}
  if($Micro.evidence){Write-PcLine ('Preuve      : '+$Micro.evidence) Green}
  if($Micro.blocker){Write-PcLine ('Blocage     : '+$Micro.blocker) Red}
  if($Micro.next_step){Write-PcLine ('Prochaine   : '+$Micro.next_step)}
  Write-PcLine ''
  Write-PcLine 'DONE exige une preuve/resultat observable.' DarkGray
}

function Write-PcTimeline {
  param($Conversation)
  Write-PcLine 'CHRONOLOGIE / EVENEMENTS RECENTS' Cyan
  Write-PcLine ''
  foreach($e in @($Conversation.recent_events|Select-Object -Last 20)){
    Write-PcLine ('  '+$e.at+' | '+$e.type) DarkCyan
    Write-PcLine ('      '+$e.summary)
  }
}

function Write-PcSources {
  param($Config,$Sync)
  Write-PcLine 'SOURCES / ADAPTATEURS' Cyan
  Write-PcLine ''
  Write-PcLine 'Noyau local-first : cache disque + moteur PowerShell.' Green
  Write-PcLine ('Transport actif   : '+$Config.state.transport+' / '+$Config.state.repo)
  Write-PcLine ('Etat transport     : '+$(if($Sync.Online){'ONLINE'}else{'OFFLINE / CACHE'}))
  Write-PcLine ''
  Write-PcLine 'Adaptateurs disponibles/prevus :'
  Write-PcLine '  ChatGPT/PCCONNECT | GitHub | Drive | Delivery/Telegram | TLIB | Web/YouTube | WMI | Desktop Commander'
  Write-PcLine '  Notion/Todoist : miroirs de pilotage optionnels; jamais source canonique.' DarkGray
  Write-PcLine ''
  Write-PcLine 'Une source n est declaree observee que si un evenement/preuve existe.' Yellow
  Write-PcLine 'Aucun mot de passe/token ne doit etre stocke dans PC COMMAND.' Yellow
}

function Write-PcLocal {
  param($LocalEvents)
  Write-PcLine 'ACTIVITE LOCALE DU PC' Cyan
  Write-PcLine ''
  if($LocalEvents.Count-eq0){Write-PcLine 'Aucune nouvelle activite locale observee.'}
  else{foreach($e in $LocalEvents){Write-PcLine ('  '+$e.At.ToString('HH:mm:ss')+' | '+$e.Text)}}
  Write-PcLine ''
  Write-PcLine 'Observation WMI locale: aucun appel Desktop Commander requis.' DarkGray
}

function Write-PcSettings {
  param($App,$Config,$Sync,$UpdateInfo)
  $os=Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
  $free=if($os){[math]::Round($os.FreePhysicalMemory/1024,0)}else{0}
  $drive=if(Get-Process GoogleDriveFS -ErrorAction SilentlyContinue){'ACTIF'}else{'ARRETE'}
  $last=if($script:PcLastPullOkAt){$script:PcLastPullOkAt.ToString('HH:mm:ss')}else{'jamais'}
  $u=if($Config.automation.auto_update){'ACTIF'}else{'ARRETE'}
  Write-PcLine 'PARAMETRES / SANTE DU SYSTEME' Cyan
  Write-PcLine ''
  Write-PcLine ("Version locale           : $($Config.version)")
  Write-PcLine ("Mode                     : $($App.Mode) | [4] AUTO/ECO")
  Write-PcLine ("Sync Internet            : $($App.SyncSeconds) s | [1] 3/5/10/30")
  Write-PcLine ("Calcul moteur            : $($App.EngineSeconds) s | [2] 3.5/5/10/30")
  Write-PcLine ("Rafraichissement visuel  : $($App.DisplaySeconds) s | [3] 5/10/20/30")
  Write-PcLine ("Verification mise a jour : $($Config.cadence.update_check_seconds) s")
  Write-PcLine ("Mise a jour automatique  : $u | staging + hash + backup + rollback") Green
  Write-PcLine ''
  Write-PcLine ("RAM libre                : $free MB")
  Write-PcLine ("Budget PC COMMAND        : $($Config.limits.ram_budget_mb) MB")
  Write-PcLine ("Google Drive Desktop     : $drive")
  Write-PcLine ("Transport etat           : $($Config.state.transport)")
  Write-PcLine ("Derniere sync reussie    : $last")
  Write-PcLine ("Echecs sync              : $script:PcSyncFailures")
  Write-PcLine ("Conversations max        : $($Config.limits.max_conversations)")
  if($script:PcLastPullError){Write-PcLine ('Derniere erreur sync     : '+$script:PcLastPullError) Yellow}
  if($UpdateInfo){Write-PcLine ('Version distante         : '+$UpdateInfo.Version+$(if($UpdateInfo.Available){' | DISPONIBLE'}else{' | a jour'}))}
  Write-PcLine ''
  Write-PcLine 'CODE NOUVELLE CONVERSATION :' Green
  Write-PcLine 'PCCONNECT|v4|state=Terminator364/PC-COMMAND-STATE|code=Terminator364/BuildHub|slot=AUTO|max=10'
}

function Write-PcRequirements {
  param($Conversation)
  Write-PcLine 'CAHIER DES CHARGES A+B+C' Cyan
  Write-PcLine ''
  $abc=$Conversation.cahier_des_charges
  if(-not$abc){Write-PcLine 'Aucun cahier A+B+C publie.' Yellow;return}
  $rq=Get-PcRequirementCoverage $Conversation
  Write-PcLine ('Version : '+$abc.version+' | '+$abc.method)
  Write-PcLine ('Couverture : '+(Get-PcBar $rq.Percent 30)+' '+$rq.Percent+'% | P0 ouvertes '+$rq.P0Open) Green
  Write-PcLine ('Dernier delta : '+$abc.last_delta)
  Write-PcLine ''
  Write-PcLine 'A - BESOIN / PROMESSE' Cyan
  foreach($x in @($abc.A_user_need|Select-Object -First 5)){Write-PcLine ('  - '+$x)}
  Write-PcLine 'B - ARCHITECTURE / RECHERCHE' Cyan
  foreach($x in @($abc.B_architecture|Select-Object -First 5)){Write-PcLine ('  - '+$x)}
  Write-PcLine 'C - TERRAIN / PREUVES' Cyan
  foreach($x in @($abc.C_field_evidence|Select-Object -First 4)){Write-PcLine ('  - '+$x)}
  Write-PcLine 'EXIGENCES PRIORITAIRES' Cyan
  foreach($r in @($abc.requirements|Sort-Object priority,id|Select-Object -First 8)){
    $pct=[int][math]::Round(([double]$r.coverage)*100,0)
    $col=if($r.status-eq'IMPLEMENTED'){'Green'}elseif($r.priority-eq'P0'){'Yellow'}else{'Gray'}
    Write-PcLine ('  '+$r.id+' '+$r.priority+' | '+$r.status+' | '+$pct+'% | '+$r.title) $col
  }
}

function Write-PcFeedback {
  param($Feedback)
  Write-PcLine 'FEEDBACK LEDGER / BASE CANONIQUE' Cyan
  Write-PcLine ''
  if(-not$Feedback -or -not$Feedback.Index){
    Write-PcLine 'Ledger local indisponible. [R] synchroniser.' Yellow
    return
  }
  Write-PcLine ('Total feedbacks : '+$Feedback.Index.total_feedbacks)
  Write-PcLine ('Dernier          : '+$Feedback.Index.last_feedback_id)
  Write-PcLine ('Politique        : '+$Feedback.Index.policy)
  Write-PcLine 'Regle            : aucun feedback pertinent ne doit etre perdu entre deux versions.' Green
  Write-PcLine ''
  Write-PcLine 'DERNIERS FEEDBACKS' Cyan
  foreach($f in @($Feedback.Recent|Select-Object -Last 8)){
    $id=if($f.feedback_id){$f.feedback_id}else{'?'}
    $phase=if($f.phase){$f.phase}else{'-'}
    Write-PcLine ('  '+$id+' | '+$phase) Green
    if($f.evidence){Write-PcLine ('      '+$f.evidence)}
    if($f.abc -and $f.abc.C){Write-PcLine ('      C: '+$f.abc.C) DarkGray}
  }
}

function Write-PcVersions {
  param($Feedback,$Config)
  Write-PcLine 'HISTORIQUE / TRACE DES VERSIONS' Cyan
  Write-PcLine ''
  Write-PcLine ('Version locale : '+$Config.version) Green
  if(-not$Feedback -or -not$Feedback.Versions){
    Write-PcLine 'Version trace local indisponible. [R] synchroniser.' Yellow
    return
  }
  foreach($v in @($Feedback.Versions.versions|Select-Object -Last 9)){
    $col=if($v.status -match 'regress'){'Red'}elseif($v.status -match 'current|target|proven|field'){'Green'}else{'Gray'}
    Write-PcLine ('  '+$v.version+' | '+$v.status+' | '+$v.intent) $col
    if($v.terrain){Write-PcLine ('      terrain: '+$v.terrain)}
  }
  Write-PcLine ''
  Write-PcLine 'Une version n est meilleure que si les acquis precedents restent prouves.' Yellow
}

function Write-PcHelp {
  Write-PcLine 'AIDE / NAVIGATION CONTEXTUELLE' Cyan
  Write-PcLine ''
  Write-PcLine '[A] Accueil      : revenir directement a l accueil.'
  Write-PcLine '[B] Retour       : remonter d un niveau.'
  Write-PcLine '[1-9]            : ouvrir conversation, macro ou micro selon la vue.'
  Write-PcLine '[C] Cahier A+B+C : exigences + recherche + terrain.'
  Write-PcLine '[F] Feedbacks    : registre canonique des retours.'
  Write-PcLine '[V] Versions     : historique, regressions et cible.'
  Write-PcLine '[T] Chronologie  : evenements observables.'
  Write-PcLine '[S] Sources      : adaptateurs et transports.'
  Write-PcLine '[L] Local        : activite observee sur le PC.'
  Write-PcLine '[P] Parametres   : cadence, RAM, sync, Drive et updates.'
  Write-PcLine '[X] Rapport      : rapport detaille.'
  Write-PcLine '[R] Sync         : synchronisation non bloquante.'
  Write-PcLine '[U] Update       : verifier les mises a jour.'
  Write-PcLine '[Q] Fermer       : fermer proprement.'
  Write-PcLine ''
  Write-PcLine 'Seules les actions pertinentes a la fenetre sont affichees dans le pied de page.' Green
}

function Write-PcFooter {
  param([string]$View)
  Write-PcFooterLine ''
  Write-PcFooterLine '--------------------------------------------------------------------------------' DarkGray
  switch($View){
    'general'{
      Write-PcFooterLine '[A] Accueil  [1-9] Conversation  [F] Feedbacks  [V] Versions'
      Write-PcFooterLine '[S] Sources  [L] Local  [P] Parametres  [H] Aide  [R] Sync  [Q] Fermer'
    }
    'conversation'{
      Write-PcFooterLine '[A] Accueil  [B] Retour  [1-9] Macro  [C] Cahier A+B+C  [T] Chronologie'
      Write-PcFooterLine '[F] Feedbacks  [V] Versions  [S] Sources  [P] Parametres  [X] Rapport  [R] Sync  [Q] Fermer'
    }
    'macro'{
      Write-PcFooterLine '[A] Accueil  [B] Retour  [1-9] Micro  [C] Cahier  [T] Chronologie'
      Write-PcFooterLine '[F] Feedbacks  [V] Versions  [P] Parametres  [X] Rapport  [R] Sync  [Q] Fermer'
    }
    'micro'{
      Write-PcFooterLine '[A] Accueil  [B] Retour  [C] Cahier  [T] Chronologie  [F] Feedbacks  [V] Versions'
      Write-PcFooterLine '[P] Parametres  [X] Rapport  [R] Sync  [Q] Fermer'
    }
    'feedback'{
      Write-PcFooterLine '[A] Accueil  [B] Retour  [V] Versions  [C] Cahier  [P] Parametres  [R] Sync  [Q] Fermer'
    }
    'versions'{
      Write-PcFooterLine '[A] Accueil  [B] Retour  [F] Feedbacks  [U] Verifier update  [P] Parametres  [R] Sync  [Q] Fermer'
    }
    'requirements'{
      Write-PcFooterLine '[A] Accueil  [B] Retour  [F] Feedbacks  [V] Versions  [T] Chronologie  [P] Parametres  [R] Sync  [Q] Fermer'
    }
    'timeline'{
      Write-PcFooterLine '[A] Accueil  [B] Retour  [C] Cahier  [F] Feedbacks  [V] Versions  [P] Parametres  [R] Sync  [Q] Fermer'
    }
    'sources'{
      Write-PcFooterLine '[A] Accueil  [B] Retour  [L] Local  [F] Feedbacks  [P] Parametres  [R] Sync  [Q] Fermer'
    }
    'local'{
      Write-PcFooterLine '[A] Accueil  [B] Retour  [S] Sources  [P] Parametres  [R] Sync  [Q] Fermer'
    }
    'settings'{
      Write-PcFooterLine '[A] Accueil  [B] Retour  [1] Sync  [2] Moteur  [3] Affichage  [4] Mode'
      Write-PcFooterLine '[C] Copier PCCONNECT  [D] Export Drive  [U] Update  [H] Aide  [R] Sync  [Q] Fermer'
    }
    'help'{
      Write-PcFooterLine '[A] Accueil  [B] Retour  [P] Parametres  [F] Feedbacks  [V] Versions  [Q] Fermer'
    }
    default{
      Write-PcFooterLine '[A] Accueil  [B] Retour  [P] Parametres  [R] Sync  [Q] Fermer'
    }
  }
}
