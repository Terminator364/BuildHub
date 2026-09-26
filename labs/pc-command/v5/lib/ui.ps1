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


function Write-PcFeedback {
  param($Feedback)
  Write-PcLine 'FEEDBACK LEDGER — BASE CANONIQUE' -ForegroundColor Cyan
  Write-PcLine ''
  if(-not$Feedback -or -not$Feedback.Index){
    Write-PcLine 'Ledger local indisponible. [R] synchroniser.' -ForegroundColor Yellow
    return
  }
  Write-PcLine ('Total feedbacks : '+$Feedback.Index.total_feedbacks)
  Write-PcLine ('Dernier          : '+$Feedback.Index.last_feedback_id)
  Write-PcLine ('Politique        : '+$Feedback.Index.policy)
  Write-PcLine 'Regle            : aucun feedback pertinent ne doit etre perdu entre deux versions.' -ForegroundColor Green
  Write-PcLine ''
  Write-PcLine 'DERNIERS FEEDBACKS' -ForegroundColor Cyan
  foreach($f in @($Feedback.Recent|Select-Object -Last 8)){
    $id=if($f.feedback_id){$f.feedback_id}else{'?'}
    $phase=if($f.phase){$f.phase}else{'-'}
    Write-PcLine ('  '+$id+' | '+$phase) -ForegroundColor Green
    if($f.evidence){Write-PcLine ('      '+$f.evidence)}
    if($f.abc -and $f.abc.C){Write-PcLine ('      C: '+$f.abc.C) -ForegroundColor DarkGray}
  }
}

function Write-PcVersions {
  param($Feedback,$Config)
  Write-PcLine 'HISTORIQUE / TRACE DES VERSIONS' -ForegroundColor Cyan
  Write-PcLine ''
  Write-PcLine ('Version locale : '+$Config.version) -ForegroundColor Green
  if(-not$Feedback -or -not$Feedback.Versions){
    Write-PcLine 'Version trace local indisponible. [R] synchroniser.' -ForegroundColor Yellow
    return
  }
  foreach($v in @($Feedback.Versions.versions|Select-Object -Last 8)){
    $col=if($v.status -match 'regress'){'Red'}elseif($v.status -match 'current|target|proven'){'Green'}else{'Gray'}
    Write-PcLine ('  '+$v.version+' | '+$v.status+' | '+$v.intent) -ForegroundColor $col
    if($v.terrain){Write-PcLine ('      terrain: '+$v.terrain)}
  }
  Write-PcLine ''
  Write-PcLine 'Promotion: une version n est meilleure que si les fonctions precedentes restent prouvees.' -ForegroundColor Yellow
}


function Write-PcMicro {
  param($Micro)
  Write-PcLine 'MICRO-TACHE / DETAIL' -ForegroundColor Cyan
  Write-PcLine ''
  if(-not$Micro){Write-PcLine 'Micro-tache indisponible.' -ForegroundColor Yellow;return}
  $pct=[int][math]::Round((Get-PcMicroCompletion $Micro)*100,0)
  Write-PcLine ('Titre       : '+$Micro.title)
  Write-PcLine ('Etat        : '+$Micro.state)
  Write-PcLine ('Avancement  : '+(Get-PcBar $pct 44)+' '+$pct+'%')
  if($Micro.weight){Write-PcLine ('Poids       : '+$Micro.weight)}
  if($Micro.evidence){Write-PcLine ('Preuve      : '+$Micro.evidence) -ForegroundColor Green}
  if($Micro.blocker){Write-PcLine ('Blocage     : '+$Micro.blocker) -ForegroundColor Red}
  if($Micro.next_step){Write-PcLine ('Prochaine   : '+$Micro.next_step)}
  Write-PcLine ''
  Write-PcLine 'DONE exige une preuve/resultat observable.' -ForegroundColor DarkGray
}

function Write-PcHelp {
  Write-PcLine 'AIDE / NAVIGATION' -ForegroundColor Cyan
  Write-PcLine ''
  Write-PcLine '[A] Accueil          : revenir a la vue principale.'
  Write-PcLine '[B] Retour           : remonter d un niveau.'
  Write-PcLine '[1-9]                : ouvrir conversation, macro ou micro selon la vue.'
  Write-PcLine '[C] Cahier A+B+C     : exigences, recherche, terrain.'
  Write-PcLine '[F] Feedbacks        : registre canonique.'
  Write-PcLine '[V] Versions         : historique, regressions, cible.'
  Write-PcLine '[T] Chronologie      : evenements observables.'
  Write-PcLine '[S] Sources          : adaptateurs/transports.'
  Write-PcLine '[L] Local            : activite observee sur le PC.'
  Write-PcLine '[P] Parametres       : cadences, RAM, Drive, sync, update.'
  Write-PcLine '[X] Rapport          : rapport detaille.'
  Write-PcLine '[R] Sync             : synchronisation non bloquante.'
  Write-PcLine '[U] Update           : verifier une nouvelle version.'
  Write-PcLine '[Q] Fermer           : fermer proprement.'
  Write-PcLine ''
  Write-PcLine 'Les commandes affichees changent selon la fenetre.' -ForegroundColor Green
}
