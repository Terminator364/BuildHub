$Host.UI.RawUI.WindowTitle = 'PC COMMAND - SUIVI'
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [Console]::OutputEncoding
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$feedUrl = 'https://raw.githubusercontent.com/Terminator364/BuildHub/lab/pc-command-browser-20260926/labs/pc-command/feed.json'
$stateDir = Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$cacheFile = Join-Path $stateDir 'feed-cache.json'
$progressFile = Join-Path $stateDir 'progress-state.json'
$rawLog = Join-Path $stateDir 'remote.stdout.log'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

function Get-Feed {
  try {
    $feed = Invoke-RestMethod -Uri $feedUrl -TimeoutSec 6
    ($feed | ConvertTo-Json -Depth 12) | Set-Content -Path $cacheFile -Encoding UTF8
    return $feed
  } catch {
    if (Test-Path $cacheFile) { return (Get-Content $cacheFile -Raw | ConvertFrom-Json) }
    return $null
  }
}

function Get-Progress($stream) {
  $total = 0.0; $done = 0.0; $evidence = 0
  $taskCount = @($stream.tasks).Count
  foreach ($task in @($stream.tasks)) {
    $w = if ($null -ne $task.weight) { [double]$task.weight } else { 1.0 }
    $c = if ($null -ne $task.completion) { [double]$task.completion } elseif ($task.state -eq 'DONE') { 1.0 } else { 0.0 }
    if ($c -lt 0) { $c = 0 }; if ($c -gt 1) { $c = 1 }
    $total += $w; $done += ($w * $c)
    if ($task.evidence) { $evidence++ }
  }
  [pscustomobject]@{
    Percent = if ($total -gt 0) { [int][math]::Round(($done/$total)*100,0) } else { 0 }
    Confidence = if ($taskCount -gt 0) { [int][math]::Round(($evidence/$taskCount)*100,0) } else { 0 }
    TaskCount=$taskCount
    DoneCount=@($stream.tasks|Where-Object state -eq 'DONE').Count
    ActiveCount=@($stream.tasks|Where-Object state -eq 'ACTIVE').Count
    PendingCount=@($stream.tasks|Where-Object state -eq 'PENDING').Count
    BlockedCount=@($stream.tasks|Where-Object state -eq 'BLOCKED').Count
  }
}

function Get-Bar([int]$pct,[int]$width=32) {
  $filled=[math]::Floor(($pct/100.0)*$width)
  if($filled-lt 0){$filled=0};if($filled-gt $width){$filled=$width}
  '['+('#'*$filled)+('-'*($width-$filled))+']'
}

function Get-LocalConnection {
  $dc=Get-CimInstance Win32_Process|Where-Object{$_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander.*remote'}|Select-Object -First 1
  if($dc){$p=Get-Process -Id $dc.ProcessId;return [pscustomobject]@{Connected=$true;Pid=$dc.ProcessId;RamMB=[math]::Round($p.WorkingSet64/1MB,1)}}
  [pscustomobject]@{Connected=$false;Pid=0;RamMB=0}
}

function Get-HumanTool([string]$name) {
  switch ($name) {
    'start_process' {'Commande Windows lancee'}
    'write_file' {'Fichier local modifie'}
    'read_file' {'Fichier local lu'}
    'list_directory' {'Dossier inspecte'}
    'read_process_output' {'Resultat de commande verifie'}
    'interact_with_process' {'Processus local pilote'}
    'kill_process' {'Processus local arrete'}
    'start_search' {'Recherche locale lancee'}
    default { if($name){'Action locale: '+$name}else{$null} }
  }
}

function Get-RecentLocalActivity {
  $out=New-Object System.Collections.Generic.List[string]
  if(Test-Path $rawLog){
    foreach($line in (Get-Content $rawLog -Tail 180)){
      if($line -match 'Received tool call [^:]+:\s*([a-zA-Z0-9_]+)'){
        $h=Get-HumanTool $Matches[1];if($h){$out.Add($h)}
      } elseif($line -match 'Tool call ([a-zA-Z0-9_]+) completed'){
        $h=Get-HumanTool $Matches[1];if($h){$out.Add($h+' - termine')}
      }
    }
  }
  @($out|Select-Object -Last 5)
}

function Load-Previous {
  if(Test-Path $progressFile){try{return(Get-Content $progressFile -Raw|ConvertFrom-Json)}catch{}}
  [pscustomobject]@{streams=@{}}
}

function Save-Progress($feed) {
  $map=[ordered]@{}
  foreach($s in @($feed.streams)){
    $p=Get-Progress $s
    $map[$s.id]=[ordered]@{percent=$p.Percent;tasks=$p.TaskCount;saved_at=(Get-Date).ToString('o')}
  }
  ([ordered]@{streams=$map}|ConvertTo-Json -Depth 6)|Set-Content $progressFile -Encoding UTF8
}

function Show-Sources($feed) {
  Write-Host 'SOURCES / CONNEXIONS' -ForegroundColor Cyan
  foreach($src in @($feed.sources)){
    $color=if($src.state -match 'CONNECTED|KEEP_RUNNING|LOCAL_DETECT'){'Green'}elseif($src.state -match 'AVAILABLE|WAIT'){'Yellow'}else{'Gray'}
    Write-Host ('  '+$src.label.PadRight(24)+' : '+$src.state+' | '+$src.detail) -ForegroundColor $color
  }
  Write-Host ''
}

function Show-Overview($feed,$previous) {
  Show-Sources $feed
  Write-Host 'FLUX DE TRAVAIL / CONVERSATIONS CONNECTEES' -ForegroundColor Cyan
  Write-Host ''
  $i=1
  foreach($s in @($feed.streams)){
    $p=Get-Progress $s;$prev=$null
    if($previous.streams){$prev=$previous.streams.($s.id)}
    $delta=''
    if($prev){
      $dp=$p.Percent-[int]$prev.percent;$dt=$p.TaskCount-[int]$prev.tasks
      if($dt-gt 0){$delta=" | plan +$dt tache(s), recalcul"}
      elseif($dp-gt 0){$delta=" | +$dp pt"}
      elseif($dp-lt 0){$delta=" | $dp pt, plan recalcule"}
    }
    $color=if($s.state -eq 'ACTIVE'){'Green'}elseif($s.state -eq 'WAITING'){'Yellow'}else{'Gray'}
    Write-Host ("[$i] "+$s.title) -ForegroundColor $color
    Write-Host ('    '+(Get-Bar $p.Percent 28)+' '+$p.Percent+'% | '+$s.stage+$delta)
    Write-Host ('    '+$s.current_action)
    Write-Host ''
    $i++
  }
  $local=@(Get-RecentLocalActivity)
  if($local.Count-gt 0){
    Write-Host 'ACTIVITE LOCALE RECENTE' -ForegroundColor Cyan
    foreach($x in $local){Write-Host ('  - '+$x)}
    Write-Host ''
  }
}

function Show-Details($stream,$previous) {
  $p=Get-Progress $stream;$prev=$null
  if($previous.streams){$prev=$previous.streams.($stream.id)}
  Write-Host 'MISSION / FLUX SELECTIONNE' -ForegroundColor Cyan
  Write-Host ('  '+$stream.title) -ForegroundColor White
  Write-Host ('  Objectif : '+$stream.objective)
  Write-Host ''
  Write-Host ('AVANCEMENT ADAPTATIF : '+(Get-Bar $p.Percent 38)+' '+$p.Percent+'%') -ForegroundColor Green
  Write-Host ('FIABILITE DU SUIVI   : '+$p.Confidence+'% des taches portent une preuve')
  if($prev){
    $dt=$p.TaskCount-[int]$prev.tasks;$dp=$p.Percent-[int]$prev.percent
    if($dt-gt 0){Write-Host ("PLAN ELARGI : +$dt tache(s). Pourcentage recalcule automatiquement.") -ForegroundColor Yellow}
    elseif($dp-ne 0){Write-Host ("EVOLUTION : "+$(if($dp-gt 0){'+'}else{''})+$dp+" point(s)")}
  }
  Write-Host ''
  Write-Host ('ETAPE ACTUELLE : '+$stream.stage) -ForegroundColor Cyan
  Write-Host ('EN COURS        : '+$stream.current_action)
  Write-Host ('DERNIER SUCCES  : '+$stream.last_success) -ForegroundColor Green
  Write-Host ('PROCHAINE ETAPE : '+$stream.next_step)
  if($stream.blocker){Write-Host ('BLOCAGE         : '+$stream.blocker) -ForegroundColor Red}else{Write-Host 'BLOCAGE         : aucun' -ForegroundColor Green}
  Write-Host ''
  Write-Host ("TACHES : $($p.DoneCount) terminee(s) | $($p.ActiveCount) active(s) | $($p.PendingCount) attente | $($p.BlockedCount) bloquee(s)")
  foreach($t in @($stream.tasks)){
    $mark=switch($t.state){'DONE'{'OK'}'ACTIVE'{'>>'}'BLOCKED'{'!!'}default{'..'}}
    $pct=[math]::Round(([double]$t.completion)*100,0)
    Write-Host ("  $mark "+$t.title+" - "+$pct+"%")
  }
  Write-Host ''
  $local=@(Get-RecentLocalActivity)
  if($local.Count-gt 0){
    Write-Host 'CE QUE LE PC A FAIT RECEMMENT' -ForegroundColor Cyan
    foreach($x in $local){Write-Host ('  - '+$x)}
  }
}

$selected=0;$view='overview';$feed=$null;$previous=Load-Previous
$lastFetch=[datetime]::MinValue;$refreshSeconds=50
while($true){
  if(((Get-Date)-$lastFetch).TotalSeconds-ge $refreshSeconds -or -not $feed){
    $feed=Get-Feed;$lastFetch=Get-Date
    if($feed -and $feed.refresh_seconds){$refreshSeconds=[int]$feed.refresh_seconds}
  }
  Clear-Host
  Write-Host '================================================================' -ForegroundColor Cyan
  Write-Host ' PC COMMAND - CENTRE DE SUIVI HUMAIN' -ForegroundColor Cyan
  Write-Host '================================================================' -ForegroundColor Cyan
  $conn=Get-LocalConnection;$os=Get-CimInstance Win32_OperatingSystem;$free=[math]::Round($os.FreePhysicalMemory/1024,0)
  if($conn.Connected){Write-Host ("Connexion ChatGPT-PC : CONNECTEE | PID $($conn.Pid) | RAM $($conn.RamMB) MB") -ForegroundColor Green}else{Write-Host 'Connexion ChatGPT-PC : DECONNECTEE' -ForegroundColor Yellow}
  Write-Host ("RAM libre : $free MB | Mise a jour : toutes les $refreshSeconds s")
  Write-Host ''
  if(-not $feed){Write-Host 'Flux Internet indisponible et aucun cache local.' -ForegroundColor Red}
  elseif($view -eq 'overview'){Show-Overview $feed $previous}
  else{if($selected-ge @($feed.streams).Count){$selected=0};Show-Details @($feed.streams)[$selected] $previous}
  Write-Host '----------------------------------------------------------------' -ForegroundColor DarkGray
  Write-Host '[A] Vue generale  [1-9] Detail flux  [R] Actualiser maintenant  [Q] Fermer'
  Write-Host ('Synchro : '+$lastFetch.ToString('HH:mm:ss')+' | Prochaine : '+$lastFetch.AddSeconds($refreshSeconds).ToString('HH:mm:ss')) -ForegroundColor DarkGray

  for($sec=0;$sec-lt $refreshSeconds;$sec++){
    Start-Sleep 1
    if([Console]::KeyAvailable){
      $k=[Console]::ReadKey($true).KeyChar.ToString().ToUpperInvariant()
      if($k-eq'Q'){if($feed){Save-Progress $feed};exit}
      if($k-eq'R'){$lastFetch=[datetime]::MinValue;break}
      if($k-eq'A'){$view='overview';break}
      if($k-match'^[1-9]$' -and $feed){$idx=[int]$k-1;if($idx-lt @($feed.streams).Count){$selected=$idx;$view='detail';break}}
    }
    if(((Get-Date)-$lastFetch).TotalSeconds-ge $refreshSeconds){break}
  }
  if($feed){Save-Progress $feed;$previous=Load-Previous}
}
