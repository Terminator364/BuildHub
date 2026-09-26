$Host.UI.RawUI.WindowTitle = 'PC COMMAND - SUIVI'
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [Console]::OutputEncoding
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$feedUrl = 'https://raw.githubusercontent.com/Terminator364/BuildHub/lab/pc-command-browser-20260926/labs/pc-command/feed.json'
$stateDir = Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$cacheFile = Join-Path $stateDir 'feed-cache-v3.json'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

$remoteSyncSeconds = 10
$localRecalcSeconds = 1
$feed = $null
$lastSync = [datetime]::MinValue
$lastSyncOk = $false
$view = 'overview'
$selected = 0
$cycle = 0
$lastSnapshot = @{}
$localEvents = New-Object System.Collections.Generic.List[object]

function Add-LocalEvent([string]$text,[string]$kind='LOCAL') {
  $localEvents.Insert(0,[pscustomobject]@{ at=(Get-Date); kind=$kind; text=$text })
  while($localEvents.Count -gt 12){ $localEvents.RemoveAt($localEvents.Count-1) }
}

function Get-Feed {
  try {
    $f = Invoke-RestMethod -Uri $feedUrl -TimeoutSec 5
    ($f | ConvertTo-Json -Depth 14) | Set-Content -Path $cacheFile -Encoding UTF8
    $script:lastSyncOk = $true
    return $f
  } catch {
    $script:lastSyncOk = $false
    if(Test-Path $cacheFile){
      try { return (Get-Content $cacheFile -Raw | ConvertFrom-Json) } catch {}
    }
    return $null
  }
}

function Get-Progress($stream) {
  $total = 0.0
  $done = 0.0
  $evidence = 0
  $tasks = @($stream.tasks)
  foreach($task in $tasks){
    $w = if($null -ne $task.weight){[double]$task.weight}else{1.0}
    $c = if($null -ne $task.completion){[double]$task.completion}elseif($task.state -eq 'DONE'){1.0}else{0.0}
    if($c -lt 0){$c=0}; if($c -gt 1){$c=1}
    $total += $w
    $done += ($w*$c)
    if($task.evidence){$evidence++}
  }
  $pct = if($total -gt 0){[int][math]::Round(($done/$total)*100,0)}else{0}
  $confidence = if($tasks.Count -gt 0){[int][math]::Round(($evidence/$tasks.Count)*100,0)}else{0}
  [pscustomobject]@{
    Percent=$pct
    Confidence=$confidence
    TaskCount=$tasks.Count
    DoneCount=@($tasks|Where-Object state -eq 'DONE').Count
    ActiveCount=@($tasks|Where-Object state -eq 'ACTIVE').Count
    PendingCount=@($tasks|Where-Object state -eq 'PENDING').Count
    BlockedCount=@($tasks|Where-Object state -eq 'BLOCKED').Count
  }
}

function Get-Bar([int]$pct,[int]$width=30){
  $filled=[math]::Floor(($pct/100.0)*$width)
  if($filled-lt 0){$filled=0}; if($filled-gt $width){$filled=$width}
  '['+('#'*$filled)+('-'*($width-$filled))+']'
}

function Get-Connection {
  $dc=Get-CimInstance Win32_Process|Where-Object{
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander.*remote'
  }|Select-Object -First 1
  if($dc){
    $p=Get-Process -Id $dc.ProcessId -ErrorAction SilentlyContinue
    return [pscustomobject]@{
      Connected=$true
      Pid=$dc.ProcessId
      RamMB=if($p){[math]::Round($p.WorkingSet64/1MB,1)}else{0}
    }
  }
  [pscustomobject]@{Connected=$false;Pid=0;RamMB=0}
}

function Get-DriveState {
  $p=Get-Process GoogleDriveFS -ErrorAction SilentlyContinue
  if($p){ return 'ACTIF' }
  return 'ARRETE'
}

function Humanize-Process([string]$name,[string]$cmd){
  if($cmd -match 'PC_COMMAND_STATUS_V3'){return $null}
  if($cmd -match 'browser-resource|browser-smoke|firefox|msedge|brave|falkon|qutebrowser|helium'){return 'Test ou mesure de navigateur lance localement'}
  if($cmd -match 'Invoke-WebRequest|Invoke-RestMethod|curl|wget'){return 'Acces Internet ou telechargement local'}
  if($cmd -match 'Get-Process|Get-CimInstance|tasklist'){return 'Inspection des processus et ressources du PC'}
  if($cmd -match 'Remove-Item|del |erase '){return 'Nettoyage local en cours'}
  if($cmd -match 'Set-Content|Add-Content|Out-File'){return 'Fichier local mis a jour'}
  if($cmd -match 'Start-Process'){return 'Application ou page ouverte sur le PC'}
  if($cmd -match 'node|npm|npx'){return 'Execution Node / Desktop Commander'}
  if($name -match 'powershell|pwsh|cmd'){return 'Commande Windows executee'}
  return $null
}

try {
  Unregister-Event -SourceIdentifier PCCommandProcessStart -ErrorAction SilentlyContinue
  Register-WmiEvent -Class Win32_ProcessStartTrace -SourceIdentifier PCCommandProcessStart | Out-Null
} catch {}

function Drain-LocalEvents {
  $events=@(Get-Event -SourceIdentifier PCCommandProcessStart -ErrorAction SilentlyContinue)
  foreach($ev in $events){
    $pid2=[int]$ev.SourceEventArgs.NewEvent.ProcessID
    $name=[string]$ev.SourceEventArgs.NewEvent.ProcessName
    $proc=Get-CimInstance Win32_Process -Filter "ProcessId=$pid2" -ErrorAction SilentlyContinue
    $cmd=if($proc){[string]$proc.CommandLine}else{''}
    $human=Humanize-Process $name $cmd
    if($human){ Add-LocalEvent $human 'LOCAL' }
    Remove-Event -EventIdentifier $ev.EventIdentifier -ErrorAction SilentlyContinue
  }
}

function Get-Snapshot($feed){
  $snap=@{}
  if($feed){
    foreach($s in @($feed.streams)){
      $p=Get-Progress $s
      $snap[$s.id]=[pscustomobject]@{Percent=$p.Percent;TaskCount=$p.TaskCount}
    }
  }
  return $snap
}

function Get-DeltaText($stream,$progress){
  if(-not $lastSnapshot.ContainsKey($stream.id)){return ''}
  $prev=$lastSnapshot[$stream.id]
  $dp=$progress.Percent-[int]$prev.Percent
  $dt=$progress.TaskCount-[int]$prev.TaskCount
  if($dt -gt 0){return " | PLAN +$dt tache(s), recalcul"}
  if($dt -lt 0){return " | PLAN $dt tache(s), recalcul"}
  if($dp -gt 0){return " | +$dp pt"}
  if($dp -lt 0){return " | $dp pt"}
  return ''
}

function Get-Forecast($stream,$progress){
  if($stream.blocker){return 'Bloque: la progression depend d une action ou d une dependance externe.'}
  if($progress.Percent -ge 95 -and $progress.Confidence -ge 70){return 'Projection: phase de cloture probable, sous reserve de nouvelles taches.'}
  if($progress.Percent -ge 75){return 'Projection: phase avancee; le plan peut encore evoluer.'}
  if($progress.Percent -ge 40){return 'Projection: milieu de parcours; plusieurs etapes restent ouvertes.'}
  return 'Projection: phase initiale ou plan encore fortement evolutif.'
}

function Show-Header {
  $conn=Get-Connection
  $os=Get-CimInstance Win32_OperatingSystem
  $free=[math]::Round($os.FreePhysicalMemory/1024,0)
  $drive=Get-DriveState
  $syncAge=if($lastSync -eq [datetime]::MinValue){'jamais'}else{[math]::Round(((Get-Date)-$lastSync).TotalSeconds,0).ToString()+' s'}
  $spinner=@('|','/','-','\')[$cycle % 4]

  Write-Host '====================================================================' -ForegroundColor Cyan
  Write-Host ' PC COMMAND - CENTRE DE SUIVI HUMAIN' -ForegroundColor Cyan
  Write-Host '====================================================================' -ForegroundColor Cyan
  if($conn.Connected){
    Write-Host ("ChatGPT-PC : CONNECTE | PID $($conn.Pid) | Desktop Commander $($conn.RamMB) MB") -ForegroundColor Green
  } else {
    Write-Host 'ChatGPT-PC : DECONNECTE' -ForegroundColor Yellow
  }
  Write-Host ("RAM libre : $free MB | Google Drive : $drive | Moteur $spinner cycle $cycle")
  Write-Host ("Recalcul local : 1 s | Synchro Internet : 10 s | age synchro : $syncAge")
  if(-not $lastSyncOk -and $lastSync -ne [datetime]::MinValue){
    Write-Host 'Internet/feed: dernier cycle distant en echec, cache local utilise.' -ForegroundColor Yellow
  }
  Write-Host ''
}

function Show-Tabs($feed){
  if(-not $feed){return}
  $parts=New-Object System.Collections.Generic.List[string]
  $i=1
  foreach($s in @($feed.streams)){
    $p=Get-Progress $s
    $name=$s.title
    if($name.Length -gt 22){$name=$name.Substring(0,22)}
    $parts.Add("[$i $name $($p.Percent)%]")
    $i++
  }
  Write-Host ('ONGLETS / FLUX : '+($parts -join '  ')) -ForegroundColor DarkCyan
  Write-Host ''
}

function Show-Sources($feed){
  Write-Host 'SOURCES ET CONNEXIONS' -ForegroundColor Cyan
  foreach($src in @($feed.sources)){
    $c=if($src.state -match 'CONNECTED|KEEP_RUNNING|LOCAL_DETECT'){'Green'}elseif($src.state -match 'AVAILABLE|WAIT'){'Yellow'}else{'Gray'}
    Write-Host ('  '+$src.label.PadRight(25)+' : '+$src.state+' | '+$src.detail) -ForegroundColor $c
  }
  Write-Host ''
  Write-Host 'Le moteur ne pretend pas suivre une source qui ne publie pas d evenement.' -ForegroundColor DarkGray
}

function Show-Overview($feed){
  Write-Host 'VUE GENERALE DES CONVERSATIONS / MISSIONS' -ForegroundColor Cyan
  Write-Host ''
  $i=1
  foreach($s in @($feed.streams)){
    $p=Get-Progress $s
    $delta=Get-DeltaText $s $p
    $color=if($s.state -eq 'ACTIVE'){'Green'}elseif($s.state -eq 'WAITING'){'Yellow'}else{'Gray'}
    Write-Host ("[$i] "+$s.title) -ForegroundColor $color
    Write-Host ('    '+(Get-Bar $p.Percent 30)+' '+$p.Percent+'%'+$delta)
    Write-Host ('    Etape : '+$s.stage)
    Write-Host ('    En cours : '+$s.current_action)
    Write-Host ('    '+(Get-Forecast $s $p)) -ForegroundColor DarkGray
    Write-Host ''
    $i++
  }

  if($localEvents.Count -gt 0){
    Write-Host 'ACTIVITE LOCALE RECENTE' -ForegroundColor Cyan
    foreach($e in @($localEvents|Select-Object -First 5)){
      Write-Host ('  '+$e.at.ToString('HH:mm:ss')+' | '+$e.text)
    }
    Write-Host ''
  }
}

function Show-Detail($stream){
  $p=Get-Progress $stream
  Write-Host 'DETAIL DE LA MISSION' -ForegroundColor Cyan
  Write-Host ('Titre    : '+$stream.title) -ForegroundColor White
  Write-Host ('Objectif : '+$stream.objective)
  Write-Host ''
  Write-Host ('AVANCEMENT ESTIME : '+(Get-Bar $p.Percent 40)+' '+$p.Percent+'%') -ForegroundColor Green
  Write-Host ('FIABILITE DU SUIVI: '+$p.Confidence+'% des taches ont une preuve/evidence')
  Write-Host ('PORTEE DU PLAN     : '+$p.TaskCount+' tache(s)')
  Write-Host ('ANALYSE            : '+(Get-Forecast $stream $p)) -ForegroundColor Yellow
  Write-Host ''
  Write-Host ('ETAPE ACTUELLE     : '+$stream.stage) -ForegroundColor Cyan
  Write-Host ('EN COURS            : '+$stream.current_action)
  Write-Host ('DERNIER SUCCES      : '+$stream.last_success) -ForegroundColor Green
  Write-Host ('PROCHAINE ETAPE     : '+$stream.next_step)
  if($stream.blocker){Write-Host ('BLOCAGE             : '+$stream.blocker) -ForegroundColor Red}
  else{Write-Host 'BLOCAGE             : aucun' -ForegroundColor Green}
  Write-Host ''
  Write-Host ("TACHES : $($p.DoneCount) terminee(s) | $($p.ActiveCount) active(s) | $($p.PendingCount) attente | $($p.BlockedCount) bloquee(s)")
  foreach($t in @($stream.tasks)){
    $mark=switch($t.state){'DONE'{'OK'}'ACTIVE'{'>>'}'BLOCKED'{'!!'}default{'..'}}
    $pct=[math]::Round(([double]$t.completion)*100,0)
    Write-Host ("  $mark "+$t.title+" - "+$pct+"%")
  }
  if($stream.events){
    Write-Host ''
    Write-Host 'EVENEMENTS RECENTS DE CE FLUX' -ForegroundColor Cyan
    foreach($e in @($stream.events|Select-Object -Last 8)){
      Write-Host ('  '+$e.at+' | '+$e.kind+' | '+$e.text)
    }
  }
}

function Show-Local {
  Write-Host 'ACTIVITE LOCALE DETECTEE SUR LE PC' -ForegroundColor Cyan
  Write-Host ''
  if($localEvents.Count -eq 0){Write-Host 'Aucune nouvelle action locale detectee depuis le lancement.'}
  else{
    foreach($e in $localEvents){Write-Host ('  '+$e.at.ToString('HH:mm:ss')+' | '+$e.kind+' | '+$e.text)}
  }
  Write-Host ''
  Write-Host 'Cette vue est locale et ne consomme pas un appel Desktop Commander.' -ForegroundColor DarkGray
}

while($true){
  $cycle++
  Drain-LocalEvents

  if(((Get-Date)-$lastSync).TotalSeconds -ge $remoteSyncSeconds -or -not $feed){
    $before=Get-Snapshot $feed
    if($before.Count -gt 0){$lastSnapshot=$before}
    $newFeed=Get-Feed
    if($newFeed){$feed=$newFeed}
    $lastSync=Get-Date
    if($feed -and $feed.remote_sync_seconds){$remoteSyncSeconds=[int]$feed.remote_sync_seconds}
    elseif($feed -and $feed.engine.remote_sync_seconds){$remoteSyncSeconds=[int]$feed.engine.remote_sync_seconds}
  }

  Clear-Host
  Show-Header
  Show-Tabs $feed

  if(-not $feed){
    Write-Host 'Aucun flux disponible. Le moteur local reste actif et retentera automatiquement.' -ForegroundColor Red
  } elseif($view -eq 'overview'){
    Show-Overview $feed
  } elseif($view -eq 'sources'){
    Show-Sources $feed
  } elseif($view -eq 'local'){
    Show-Local
  } else {
    if($selected -ge @($feed.streams).Count){$selected=0}
    Show-Detail @($feed.streams)[$selected]
  }

  Write-Host '--------------------------------------------------------------------' -ForegroundColor DarkGray
  Write-Host '[A] General  [1-9] Flux  [S] Sources  [L] Local  [R] Sync  [Q] Fermer'
  $next=$lastSync.AddSeconds($remoteSyncSeconds)
  Write-Host ('Recalcul: maintenant | prochaine synchro distante: '+$next.ToString('HH:mm:ss')) -ForegroundColor DarkGray

  for($i=0;$i-lt $localRecalcSeconds;$i++){
    Start-Sleep -Seconds 1
    if([Console]::KeyAvailable){
      $k=[Console]::ReadKey($true).KeyChar.ToString().ToUpperInvariant()
      if($k-eq'Q'){Unregister-Event -SourceIdentifier PCCommandProcessStart -ErrorAction SilentlyContinue;exit}
      if($k-eq'R'){$lastSync=[datetime]::MinValue;break}
      if($k-eq'A'){$view='overview';break}
      if($k-eq'S'){$view='sources';break}
      if($k-eq'L'){$view='local';break}
      if($k-match'^[1-9]$' -and $feed){
        $idx=[int]$k-1
        if($idx-lt @($feed.streams).Count){$selected=$idx;$view='detail';break}
      }
    }
  }
}
