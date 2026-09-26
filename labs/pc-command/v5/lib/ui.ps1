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

function Get-PcActionsForView {
  param([string]$View)
  switch($View){
    'general' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},
      [pscustomobject]@{Key='1-9';Label='Conversation'},
      [pscustomobject]@{Key='F';Label='Feedbacks'},
      [pscustomobject]@{Key='V';Label='Versions'},
      [pscustomobject]@{Key='X';Label='Rapports'},
      [pscustomobject]@{Key='S';Label='Sources'},
      [pscustomobject]@{Key='L';Label='Local'},
      [pscustomobject]@{Key='P';Label='Parametres'},
      [pscustomobject]@{Key='Y';Label='Sante'},
      [pscustomobject]@{Key='H';Label='Aide'},
      [pscustomobject]@{Key='R';Label='Sync'},
      [pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    'conversation' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},
      [pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='1-9';Label='Macro'},
      [pscustomobject]@{Key='C';Label='Cahier A+B+C'},
      [pscustomobject]@{Key='T';Label='Chronologie'},
      [pscustomobject]@{Key='F';Label='Feedbacks'},
      [pscustomobject]@{Key='V';Label='Versions'},
      [pscustomobject]@{Key='S';Label='Sources'},
      [pscustomobject]@{Key='P';Label='Parametres'},
      [pscustomobject]@{Key='X';Label='Rapport'},
      [pscustomobject]@{Key='R';Label='Sync'},
      [pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    'macro' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},
      [pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='1-9';Label='Micro'},
      [pscustomobject]@{Key='C';Label='Cahier'},
      [pscustomobject]@{Key='T';Label='Chronologie'},
      [pscustomobject]@{Key='F';Label='Feedbacks'},
      [pscustomobject]@{Key='V';Label='Versions'},
      [pscustomobject]@{Key='P';Label='Parametres'},
      [pscustomobject]@{Key='X';Label='Rapport'},
      [pscustomobject]@{Key='R';Label='Sync'},
      [pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    'micro' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},[pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='C';Label='Cahier'},[pscustomobject]@{Key='T';Label='Chronologie'},
      [pscustomobject]@{Key='F';Label='Feedbacks'},[pscustomobject]@{Key='V';Label='Versions'},
      [pscustomobject]@{Key='P';Label='Parametres'},[pscustomobject]@{Key='X';Label='Rapport'},
      [pscustomobject]@{Key='R';Label='Sync'},[pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    'feedback' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},[pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='V';Label='Versions'},[pscustomobject]@{Key='C';Label='Cahier'},
      [pscustomobject]@{Key='P';Label='Parametres'},[pscustomobject]@{Key='R';Label='Sync'},
      [pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    'versions' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},[pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='F';Label='Feedbacks'},[pscustomobject]@{Key='U';Label='Verifier update'},
      [pscustomobject]@{Key='P';Label='Parametres'},[pscustomobject]@{Key='R';Label='Sync'},
      [pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    'requirements' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},[pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='F';Label='Feedbacks'},[pscustomobject]@{Key='V';Label='Versions'},
      [pscustomobject]@{Key='T';Label='Chronologie'},[pscustomobject]@{Key='P';Label='Parametres'},
      [pscustomobject]@{Key='R';Label='Sync'},[pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    'timeline' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},[pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='C';Label='Cahier'},[pscustomobject]@{Key='F';Label='Feedbacks'},
      [pscustomobject]@{Key='V';Label='Versions'},[pscustomobject]@{Key='P';Label='Parametres'},
      [pscustomobject]@{Key='R';Label='Sync'},[pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    'sources' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},[pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='L';Label='Local'},[pscustomobject]@{Key='F';Label='Feedbacks'},
      [pscustomobject]@{Key='P';Label='Parametres'},[pscustomobject]@{Key='R';Label='Sync'},
      [pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    'local' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},[pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='S';Label='Sources'},[pscustomobject]@{Key='P';Label='Parametres'},
      [pscustomobject]@{Key='R';Label='Sync'},[pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    'settings' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},[pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='1';Label='Sync'},[pscustomobject]@{Key='2';Label='Moteur'},
      [pscustomobject]@{Key='3';Label='Affichage'},[pscustomobject]@{Key='4';Label='Profil'},
      [pscustomobject]@{Key='C';Label='Copier PCCONNECT'},[pscustomobject]@{Key='U';Label='Update'},
      [pscustomobject]@{Key='Y';Label='Sante'},[pscustomobject]@{Key='H';Label='Aide'},
      [pscustomobject]@{Key='R';Label='Sync'},[pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    'reports' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},[pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='G';Label='Generer PDF'},[pscustomobject]@{Key='O';Label='Ouvrir dernier'},
      [pscustomobject]@{Key='D';Label='Export Drive'},[pscustomobject]@{Key='E';Label='Dossier rapports'},
      [pscustomobject]@{Key='P';Label='Parametres'},[pscustomobject]@{Key='R';Label='Sync'},
      [pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    'health' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},[pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='P';Label='Parametres'},[pscustomobject]@{Key='R';Label='Sync'},
      [pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    'help' {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},[pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='P';Label='Parametres'},[pscustomobject]@{Key='F';Label='Feedbacks'},
      [pscustomobject]@{Key='V';Label='Versions'},[pscustomobject]@{Key='Q';Label='Fermer'}
    )}
    default {return @(
      [pscustomobject]@{Key='A';Label='Accueil'},[pscustomobject]@{Key='B';Label='Retour'},
      [pscustomobject]@{Key='P';Label='Parametres'},[pscustomobject]@{Key='R';Label='Sync'},
      [pscustomobject]@{Key='Q';Label='Fermer'}
    )}
  }
}

function Get-PcExpandedKeysForView {
  param([string]$View)
  $keys=@()
  foreach($a in @(Get-PcActionsForView $View)){
    if($a.Key-eq'1-9'){$keys+=@('1','2','3','4','5','6','7','8','9')}
    else{$keys+=[string]$a.Key}
  }
  return @($keys|Select-Object -Unique)
}

function Write-PcFooter {
  param([string]$View)
  Write-PcFooterLine ''
  Write-PcFooterLine '--------------------------------------------------------------------------------' DarkGray
  $line=''
  foreach($a in @(Get-PcActionsForView $View)){
    $item='['+$a.Key+'] '+$a.Label
    if([string]::IsNullOrWhiteSpace($line)){$line=$item}
    elseif(($line.Length+2+$item.Length)-ge[math]::Max(50,$script:PcFrameWidth-2)){
      Write-PcFooterLine $line
      $line=$item
    }else{$line+='  '+$item}
  }
  if(-not[string]::IsNullOrWhiteSpace($line)){Write-PcFooterLine $line}
}


function Write-PcReportCenter {
  param($Config,$Paths,$Conversation)
  Write-PcLine 'CENTRE DE RAPPORTS' -ForegroundColor Cyan
  Write-PcLine ''
  $files=@(Get-ChildItem $Paths.Reports -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending)
  $pdf=@($files|Where-Object Extension -eq '.pdf')
  $html=@($files|Where-Object Extension -eq '.html')
  Write-PcLine ('Conversation : '+$(if($Conversation){$Conversation.label}else{'vue generale'}))
  Write-PcLine ('PDF locaux    : '+$pdf.Count+' | HTML : '+$html.Count)
  if($pdf.Count-gt0){
    Write-PcLine ('Dernier PDF   : '+$pdf[0].Name) -ForegroundColor Green
    Write-PcLine ('Date           : '+$pdf[0].LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-PcLine ('Taille         : '+[math]::Round($pdf[0].Length/1KB,1)+' KB')
  }else{
    Write-PcLine 'Aucun PDF genere pour le moment.' -ForegroundColor Yellow
  }
  Write-PcLine ''
  Write-PcLine 'Chaque nouveau PDF est aussi copie automatiquement dans Telechargements.' -ForegroundColor DarkGray
  Write-PcLine 'Export Drive disponible sans bloquer le moteur.' -ForegroundColor DarkGray
}

function Write-PcHealth {
  param($Config,$Sync,$UpdateInfo)
  $h=Get-PcHealthScore $Config $Sync $UpdateInfo
  Write-PcLine 'SANTE / DIAGNOSTIC' -ForegroundColor Cyan
  Write-PcLine ''
  Write-PcLine ('Score : '+$h.Score+'/100 | '+$h.Level) -ForegroundColor $h.Color
  Write-PcLine ('RAM libre : '+$h.FreeRamMb+' MB')
  if(@($h.Reasons).Count-eq0){Write-PcLine 'Aucune anomalie prioritaire detectee.' -ForegroundColor Green}
  else{
    Write-PcLine 'Points a surveiller :' -ForegroundColor Yellow
    foreach($x in @($h.Reasons)){Write-PcLine ('  - '+$x)}
  }
}