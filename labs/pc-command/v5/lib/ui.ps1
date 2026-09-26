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
  param([Parameter(Position=0)]$Object='',[ConsoleColor]$ForegroundColor=[ConsoleColor]::Gray)
  $s=if($null-eq$Object){''}else{[string]$Object}
  if($s.Length-ge$script:PcFrameWidth){$s=$s.Substring(0,[math]::Max(1,$script:PcFrameWidth-4))+'...'}
  try{[Console]::ForegroundColor=$ForegroundColor;[Console]::WriteLine($s);[Console]::ResetColor()}catch{Write-Host $s -ForegroundColor $ForegroundColor}
}

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
  Write-PcLine '================================================================================' -ForegroundColor Cyan
  Write-PcLine (" PC COMMAND  v$($Config.version)   $Spinner  MOTEUR VIVANT") -ForegroundColor Cyan
  Write-PcLine '================================================================================' -ForegroundColor Cyan
  Write-PcLine ("RAM libre : $free MB | Drive : $drive | Budget PC COMMAND : $($Config.limits.ram_budget_mb) MB")
  Write-PcLine ("Moteur : $($App.EngineSeconds)s | Internet : $($App.SyncSeconds)s | Affichage : $($App.DisplaySeconds)s | Mode : $($App.Mode)")
  Write-PcLine ("Etat : depot prive local-sync | Echecs sync : $script:PcSyncFailures")
  if($UpdateInfo -and $UpdateInfo.Available){Write-PcLine ("MISE A JOUR DISPONIBLE : v$($UpdateInfo.Version)") -ForegroundColor Yellow}
  if($Conversation){
    $life=Get-PcLifecycleView $Conversation
    Write-PcLine ("Conversation : $($Conversation.label) | "+$life.Label+" | "+$life.Detail) -ForegroundColor $life.Color
  }
  if(-not $Sync.Online){Write-PcLine 'MODE OFFLINE/CACHE : dernier etat fiable affiche.' -ForegroundColor Yellow}
  Write-PcLine ''
}

function Write-PcGeneral {
  param($Overview)
  Write-PcLine 'ACCUEIL / CONVERSATIONS CONNECTEES' -ForegroundColor Cyan
  Write-PcLine ''
  if(-not $Overview -or @($Overview.conversations).Count-eq0){Write-PcLine 'Aucune conversation connectee.' -ForegroundColor Yellow;return}
  $i=1
  foreach($c in @($Overview.conversations|Select-Object -First 10)){
    $pct=if($null-ne$c.progress_estimate){[int]$c.progress_estimate}else{0}
    $life=Get-PcLifecycleView $c
    Write-PcLine ("[$i] $($c.label) | $($c.short_code)") -ForegroundColor Green
    Write-PcLine ('    '+(Get-PcBar $pct 36)+' '+$pct+'% | '+$life.Label) -ForegroundColor $life.Color
    Write-PcLine ('    Activite   : '+$life.Detail) -ForegroundColor $life.Color
    if($c.current_action){Write-PcLine ('    Maintenant : '+$c.current_action)}
    if($c.next_step){Write-PcLine ('    Ensuite    : '+$c.next_step) -ForegroundColor DarkGray}
    Write-PcLine ''
    $i++
  }
}

function Write-PcConversation {
  param($Conversation,[string]$HistoryFile)
  $cp=Get-PcConversationProgress $Conversation; $life=Get-PcLifecycleView $Conversation; $risk=Get-PcRisk $Conversation
  $eta=Get-PcEta $HistoryFile ([string]$Conversation.conversation_id) $cp.Percent $cp.MacroCount
  Write-PcLine ('CONVERSATION : '+$Conversation.label) -ForegroundColor Cyan
  Write-PcLine ('Objectif     : '+$Conversation.objective)
  Write-PcLine ('Etat         : '+$life.Label+' | '+$life.Detail) -ForegroundColor $life.Color
  Write-PcLine ('Avancement   : '+(Get-PcBar $cp.Percent 42)+' '+$cp.Percent+'%')
  Write-PcLine ("Macro-taches : $($cp.MacroCount) | actives $($cp.Active) | attente $($cp.Waiting) | bloquees $($cp.Blocked)")
  Write-PcLine ('Risque       : '+$risk.Level+' ('+$risk.Score+'/100) | ETA: '+$eta) -ForegroundColor $(if($risk.Score-ge60){'Red'}elseif($risk.Score-ge30){'Yellow'}else{'Green'})
  Write-PcLine ''
  $i=1
  foreach($m in @($Conversation.macro_tasks|Select-Object -First 4)){
    $mp=Get-PcMacroProgress $m
    Write-PcLine ("[$i] $($m.title) | $($m.state)") -ForegroundColor $(if($m.state-eq'BLOCKED'){'Red'}elseif($m.state-eq'WAITING'){'Yellow'}else{'Green'})
    Write-PcLine ('    '+(Get-PcBar $mp.Percent 30)+' '+$mp.Percent+'% | fiabilite '+$mp.Confidence+'%')
    if($m.current_action){Write-PcLine ('    En cours : '+$m.current_action)}
    Write-PcLine ''
    $i++
  }
}

function Write-PcMacro {
  param($Macro,[int]$MaxVisible=20)
  $mp=Get-PcMacroProgress $Macro
  Write-PcLine ('MACRO-TACHE : '+$Macro.title) -ForegroundColor Cyan
  Write-PcLine ('Etat        : '+$Macro.state)
  Write-PcLine ('Avancement  : '+(Get-PcBar $mp.Percent 44)+' '+$mp.Percent+'%')
  Write-PcLine ('Fiabilite   : '+$mp.Confidence+'%')
  if($Macro.current_action){Write-PcLine ('En cours    : '+$Macro.current_action)}
  if($Macro.last_success){Write-PcLine ('Dernier OK  : '+$Macro.last_success) -ForegroundColor Green}
  if($Macro.next_step){Write-PcLine ('Prochaine   : '+$Macro.next_step)}
  if($Macro.blocker){Write-PcLine ('Blocage     : '+$Macro.blocker) -ForegroundColor Red}else{Write-PcLine 'Blocage     : aucun' -ForegroundColor Green}
  Write-PcLine ''
  $v=Get-PcVisibleMicroTasks $Macro $MaxVisible
  if($v.Total-eq0){Write-PcLine 'Micro-taches detaillees non publiees dans ce snapshot.' -ForegroundColor DarkGray}
  else{
    Write-PcLine ("MICRO-TACHES : $($v.Total) total | $($v.Hidden) masquee(s) par condensation") -ForegroundColor Cyan
    foreach($t in @($v.Items)){
      $mark=switch([string]$t.state){'DONE'{'OK'}'ACTIVE'{'>>'}'BLOCKED'{'!!'}default{'..'}}
      $pct=[int][math]::Round((Get-PcMicroCompletion $t)*100,0)
      Write-PcLine ("  $mark $($t.title) - $pct%")
      if($t.evidence){Write-PcLine ('      preuve: '+$t.evidence) -ForegroundColor DarkGray}
    }
  }
}

function Write-PcTimeline {
  param($Conversation)
  Write-PcLine 'CHRONOLOGIE / EVENEMENTS RECENTS' -ForegroundColor Cyan
  Write-PcLine ''
  foreach($e in @($Conversation.recent_events|Select-Object -Last 20)){
    Write-PcLine ('  '+$e.at+' | '+$e.type) -ForegroundColor DarkCyan
    Write-PcLine ('      '+$e.summary)
  }
}

function Write-PcSources {
  param($Config,$Sync)
  Write-PcLine 'SOURCES / ADAPTATEURS' -ForegroundColor Cyan
  Write-PcLine ''
  Write-PcLine 'Noyau local-first : cache disque + moteur PowerShell.' -ForegroundColor Green
  Write-PcLine ('Transport actif  : '+$Config.state.transport+' / '+$Config.state.repo)
  Write-PcLine ('Etat transport    : '+$(if($Sync.Online){'ONLINE'}else{'OFFLINE / CACHE'}))
  Write-PcLine ''
  Write-PcLine 'Adaptateurs : ChatGPT/PCCONNECT, GitHub, Drive, Telegram/Delivery, TLIB, Web/YouTube, WMI Windows, Desktop Commander.'
  Write-PcLine 'Une source n est affichee comme observee que si un evenement ou une preuve existe.' -ForegroundColor Yellow
  Write-PcLine 'Aucun mot de passe ne doit etre stocke dans PC COMMAND.' -ForegroundColor Yellow
}

function Write-PcLocal {
  param($LocalEvents)
  Write-PcLine 'ACTIVITE LOCALE DU PC' -ForegroundColor Cyan
  Write-PcLine ''
  if($LocalEvents.Count-eq0){Write-PcLine 'Aucune nouvelle activite locale observee.'}
  else{foreach($e in $LocalEvents){Write-PcLine ('  '+$e.At.ToString('HH:mm:ss')+' | '+$e.Text)}}
  Write-PcLine ''
  Write-PcLine 'Observation WMI locale: aucun appel Desktop Commander requis.' -ForegroundColor DarkGray
}

function Write-PcSettings {
  param($App,$Config)
  Write-PcLine 'PARAMETRES' -ForegroundColor Cyan
  Write-PcLine ''
  Write-PcLine ("Version               : $($Config.version)")
  Write-PcLine ("Sync Internet          : $($App.SyncSeconds) s  | [1] alterner 5/10/30")
  Write-PcLine ("Calcul moteur          : $($App.EngineSeconds) s | [2] alterner 5/10/30")
  Write-PcLine ("Rafraichissement ecran : $($App.DisplaySeconds) s | [3] alterner 10/20/30")
  Write-PcLine ("Mode                   : $($App.Mode) | [4] AUTO/ECO")
  Write-PcLine ("RAM budget             : $($Config.limits.ram_budget_mb) MB")
  Write-PcLine ("Conversations max      : $($Config.limits.max_conversations)")
  Write-PcLine ("Depot etat local       : state-repo (pull asynchrone)")
  Write-PcLine ''
  Write-PcLine 'CODE NOUVELLE CONVERSATION :' -ForegroundColor Green
  Write-PcLine 'PCCONNECT|v3|state=Terminator364/PC-COMMAND-STATE|code=Terminator364/BuildHub|slot=AUTO|max=10'
  Write-PcLine ''
  Write-PcLine '[C] Copier code  [X] Rapport PDF  [D] Export Drive  [U] Verifier update'
}

function Write-PcFooter {
  param([string]$View)
  Write-PcFooterLine ''
  Write-PcFooterLine '--------------------------------------------------------------------------------' DarkGray
  switch($View){
    'general'{Write-PcFooterLine '[1-9] Conversation  [S] Sources  [L] Local  [P] Parametres  [X] Rapport  [R] Sync  [Q] Fermer'}
    'conversation'{Write-PcFooterLine '[1-9] Macro  [C] Cahier A+B+C  [T] Chronologie  [B] Retour  [P] Parametres  [X] PDF  [R] Sync  [Q] Fermer'}
    'macro'{Write-PcFooterLine '[C] Cahier A+B+C  [B] Retour  [T] Chronologie  [P] Parametres  [X] PDF  [R] Sync  [Q] Fermer'}
    default{Write-PcFooterLine '[A] Accueil  [B] Retour  [P] Parametres  [R] Sync  [Q] Fermer'}
  }
}

function Write-PcRequirements {
  param($Conversation)
  Write-PcLine 'CAHIER DES CHARGES A+B+C' -ForegroundColor Cyan
  Write-PcLine ''
  $abc=$Conversation.cahier_des_charges
  if(-not$abc){Write-PcLine 'Aucun cahier A+B+C publie.' -ForegroundColor Yellow;return}
  $rq=Get-PcRequirementCoverage $Conversation
  Write-PcLine ('Version : '+$abc.version+' | '+$abc.method)
  Write-PcLine ('Couverture : '+(Get-PcBar $rq.Percent 30)+' '+$rq.Percent+'% | P0 ouvertes '+$rq.P0Open) -ForegroundColor Green
  Write-PcLine ('Dernier delta : '+$abc.last_delta)
  Write-PcLine ''
  Write-PcLine 'A - BESOIN / PROMESSE' -ForegroundColor Cyan
  foreach($x in @($abc.A_user_need|Select-Object -First 5)){Write-PcLine ('  - '+$x)}
  Write-PcLine 'B - ARCHITECTURE / RECHERCHE' -ForegroundColor Cyan
  foreach($x in @($abc.B_architecture|Select-Object -First 5)){Write-PcLine ('  - '+$x)}
  Write-PcLine 'C - TERRAIN / PREUVES' -ForegroundColor Cyan
  foreach($x in @($abc.C_field_evidence|Select-Object -First 4)){Write-PcLine ('  - '+$x)}
  Write-PcLine 'EXIGENCES PRIORITAIRES' -ForegroundColor Cyan
  foreach($r in @($abc.requirements|Sort-Object priority,id|Select-Object -First 8)){
    $pct=[int][math]::Round(([double]$r.coverage)*100,0)
    $col=if($r.status-eq'IMPLEMENTED'){'Green'}elseif($r.priority-eq'P0'){'Yellow'}else{'Gray'}
    Write-PcLine ('  '+$r.id+' '+$r.priority+' | '+$r.status+' | '+$pct+'% | '+$r.title) -ForegroundColor $col
  }
}
