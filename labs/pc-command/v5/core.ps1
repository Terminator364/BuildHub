$Version = '0.5.0-lab'
$StateRepo = 'Terminator364/PC-COMMAND-STATE'
$StateBranch = 'main'
$StateRoot = 'pc-command'
$StateDir = Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$CacheDir = Join-Path $StateDir 'cache'
$HistoryDir = Join-Path $StateDir 'history'
$ReportDir = Join-Path $StateDir 'reports'
$LogDir = Join-Path $StateDir 'logs'
foreach($d in @($StateDir,$CacheDir,$HistoryDir,$ReportDir,$LogDir)){New-Item -ItemType Directory -Force -Path $d|Out-Null}

$InternetSyncSeconds = 5
$EngineRecalcSeconds = 5
$DisplayRefreshSeconds = 10
$RegistryRefreshSeconds = 60
$HeartbeatSeconds = 1
$RamBudgetMB = 150
$MaxConversations = 10
$MaxMacroTasks = 10
$MaxVisibleMicro = 20
$MaxEventsLoaded = 100
$HistoryMaxBytes = 524288

$Token = $null
$Etags = @{}
$SyncFailures = 0
$LastSync = [datetime]::MinValue
$LastRegistrySync = [datetime]::MinValue
$LastRecalc = [datetime]::MinValue
$LastDisplay = [datetime]::MinValue
$LastHeartbeat = [datetime]::MinValue
$Registry = $null
$Overview = $null
$Channel = $null
$Events = @()
$View = 'overview'
$ConversationIndex = 0
$MacroIndex = 0
$Cycle = 0
$Notices = New-Object System.Collections.Generic.List[object]
$Previous = @{}
$LastStateDigest = ''
$Offline = $false
$RateRemaining = $null
$RateReset = $null

function Add-Notice([string]$Text,[string]$Level='INFO'){
  if([string]::IsNullOrWhiteSpace($Text)){return}
  $Notices.Insert(0,[pscustomobject]@{At=Get-Date;Level=$Level;Text=$Text})
  while($Notices.Count -gt 12){$Notices.RemoveAt($Notices.Count-1)}
}

function Get-GitHubToken {
  try {
    $gh = Get-Command gh.exe -ErrorAction Stop
    $t = (& $gh.Source auth token 2>$null | Select-Object -First 1)
    if($t){ return [string]$t }
  } catch {}
  return $null
}

function Get-CachePath([string]$Key){ Join-Path $CacheDir ($Key + '.json') }

function Read-Cache([string]$Key){
  $p=Get-CachePath $Key
  if(Test-Path $p){try{return(Get-Content $p -Raw|ConvertFrom-Json)}catch{}}
  return $null
}

function Save-Cache([string]$Key,[string]$Content){
  $p=Get-CachePath $Key
  $tmp=$p+'.tmp'
  $Content|Set-Content $tmp -Encoding UTF8
  Move-Item $tmp $p -Force
}

function Invoke-GitHubRaw([string]$Path,[string]$CacheKey,[bool]$Force=$false){
  if(-not $Token){return Read-Cache $CacheKey}
  $url="https://api.github.com/repos/$StateRepo/contents/$Path?ref=$StateBranch"
  $headers=@{
    'Authorization'="Bearer $Token"
    'Accept'='application/vnd.github.raw+json'
    'X-GitHub-Api-Version'='2022-11-28'
    'User-Agent'='PC-COMMAND'
  }
  if(-not $Force -and $Etags.ContainsKey($CacheKey)){$headers['If-None-Match']=$Etags[$CacheKey]}
  try {
    $resp=Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 4
    if($resp.Headers['ETag']){$Etags[$CacheKey]=[string]$resp.Headers['ETag']}
    if($resp.Headers['X-RateLimit-Remaining']){$script:RateRemaining=[int]$resp.Headers['X-RateLimit-Remaining']}
    if($resp.Headers['X-RateLimit-Reset']){$script:RateReset=[int64]$resp.Headers['X-RateLimit-Reset']}
    $content=[string]$resp.Content
    Save-Cache $CacheKey $content
    $script:SyncFailures=0
    $script:Offline=$false
    try{return($content|ConvertFrom-Json)}catch{return $content}
  } catch {
    $r=$_.Exception.Response
    if($r){
      try {
        if([int]$r.StatusCode -eq 304){
          $script:SyncFailures=0
          $script:Offline=$false
          return Read-Cache $CacheKey
        }
        if($r.Headers['X-RateLimit-Remaining']){$script:RateRemaining=[int]$r.Headers['X-RateLimit-Remaining']}
      } catch {}
    }
    $script:SyncFailures++
    $script:Offline=$true
    return Read-Cache $CacheKey
  }
}

function Get-EffectiveSyncSeconds {
  if($SyncFailures -le 0){return $InternetSyncSeconds}
  return [int][math]::Min(60,$InternetSyncSeconds*[math]::Pow(2,[math]::Min($SyncFailures,4)))
}

function Sync-Registry([bool]$Force=$false){
  if($Force -or ((Get-Date)-$LastRegistrySync).TotalSeconds -ge $RegistryRefreshSeconds -or -not $Registry){
    $r=Invoke-GitHubRaw "$StateRoot/registry.json" 'registry' $Force
    if($r){$script:Registry=$r}
    $script:LastRegistrySync=Get-Date
  }
}

function Sync-Overview([bool]$Force=$false){
  $r=Invoke-GitHubRaw "$StateRoot/overview.json" 'overview' $Force
  if($r){$script:Overview=$r}
  $script:LastSync=Get-Date
}

function Get-SelectedConversation {
  if(-not $Overview -or -not $Overview.conversations){return $null}
  $arr=@($Overview.conversations)
  if($ConversationIndex -ge $arr.Count){$script:ConversationIndex=0}
  if($arr.Count -eq 0){return $null}
  return $arr[$ConversationIndex]
}

function Sync-Channel([bool]$Force=$false){
  $c=Get-SelectedConversation
  if(-not $c){$script:Channel=$null;return}
  $path=if($c.state_path){[string]$c.state_path}else{"$StateRoot/channels/$($c.id)/state.json"}
  $key='channel-'+[string]$c.id
  $r=Invoke-GitHubRaw $path $key $Force
  if($r){$script:Channel=$r}
}

function Sync-Events([bool]$Force=$false){
  $c=Get-SelectedConversation
  if(-not $c){$script:Events=@();return}
  $path=if($c.events_path){[string]$c.events_path}else{"$StateRoot/channels/$($c.id)/events.jsonl"}
  if(-not $Token){$script:Events=@();return}
  $url="https://api.github.com/repos/$StateRepo/contents/$Path?ref=$StateBranch"
  $headers=@{'Authorization'="Bearer $Token";'Accept'='application/vnd.github.raw+json';'X-GitHub-Api-Version'='2022-11-28';'User-Agent'='PC-COMMAND'}
  try{
    $resp=Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing -TimeoutSec 5
    $lines=@(([string]$resp.Content) -split '\r?\n' | Where-Object {$_})
    $out=New-Object System.Collections.Generic.List[object]
    foreach($line in ($lines|Select-Object -Last $MaxEventsLoaded)){
      try{$out.Add(($line|ConvertFrom-Json))}catch{}
    }
    $script:Events=@($out)
  }catch{}
}

function Get-MacroProgress($Macro){
  if($Macro.micro_tasks){
    $total=0.0;$done=0.0;$evidence=0;$tasks=@($Macro.micro_tasks)
    foreach($t in $tasks){
      $w=if($null-ne $t.weight){[double]$t.weight}else{1}
      $c=if($t.state-eq'DONE'){1.0}elseif($null-ne $t.completion){[double]$t.completion}else{0}
      if($c-lt 0){$c=0};if($c-gt 1){$c=1}
      $total+=$w;$done+=($w*$c)
      if($t.evidence){$evidence++}
    }
    return [pscustomobject]@{
      Percent=if($total-gt 0){[int][math]::Round(($done/$total)*100,0)}else{0}
      Confidence=if($tasks.Count-gt 0){[int][math]::Round(($evidence/$tasks.Count)*100,0)}else{0}
      Count=$tasks.Count
      Done=@($tasks|Where-Object state -eq 'DONE').Count
      Active=@($tasks|Where-Object state -eq 'ACTIVE').Count
      Pending=@($tasks|Where-Object state -eq 'PENDING').Count
      Blocked=@($tasks|Where-Object state -eq 'BLOCKED').Count
    }
  }
  $pct=if($null-ne $Macro.completion){[int][math]::Round(([double]$Macro.completion)*100,0)}elseif($Macro.progress){[int]$Macro.progress}else{0}
  $conf=if($null-ne $Macro.confidence){[int][math]::Round(([double]$Macro.confidence)*100,0)}else{0}
  return [pscustomobject]@{Percent=$pct;Confidence=$conf;Count=0;Done=0;Active=0;Pending=0;Blocked=0}
}

function Get-ConversationProgress($C){
  if(-not $C){return [pscustomobject]@{Percent=0;MacroCount=0;Confidence=0}}
  if($Channel -and $Channel.conversation_id -eq $C.id -and $Channel.macro_tasks){
    $total=0.0;$done=0.0;$conf=0.0;$count=0
    foreach($m in @($Channel.macro_tasks)){
      $w=if($null-ne $m.weight){[double]$m.weight}else{1}
      $p=Get-MacroProgress $m
      $total+=$w;$done+=($w*($p.Percent/100.0));$conf+=$p.Confidence;$count++
    }
    return [pscustomobject]@{
      Percent=if($total-gt 0){[int][math]::Round(($done/$total)*100,0)}else{0}
      MacroCount=$count
      Confidence=if($count){[int][math]::Round($conf/$count,0)}else{0}
    }
  }
  if($C.macros){
    $ms=@($C.macros)
    $avg=if($ms.Count){[int][math]::Round((($ms|Measure-Object progress -Average).Average),0)}else{0}
    return [pscustomobject]@{Percent=if($C.progress_estimate){[int]$C.progress_estimate}else{$avg};MacroCount=$ms.Count;Confidence=0}
  }
  return [pscustomobject]@{Percent=if($C.progress_estimate){[int]$C.progress_estimate}else{0};MacroCount=if($C.macro_count){[int]$C.macro_count}else{0};Confidence=0}
}

function Get-Bar([int]$Pct,[int]$Width=30){
  $filled=[math]::Floor(($Pct/100.0)*$Width)
  if($filled-lt 0){$filled=0}
  if($filled-gt $Width){$filled=$Width}
  return '['+('#'*$filled)+('-'*($Width-$filled))+']'
}

function Get-Elapsed([string]$Iso){
  if(-not $Iso){return ''}
  try{$d=[datetimeoffset]::Parse($Iso);$s=[int]([datetimeoffset]::Now-$d).TotalSeconds}catch{return ''}
  if($s-lt 0){$s=0}
  if($s-lt 60){return "$s s"}
  $m=[math]::Floor($s/60);$sec=$s%60
  return ("{0}m {1:00}s" -f $m,$sec)
}

function Get-LifeState($C){
  $l=if($Channel -and $Channel.lifecycle){$Channel.lifecycle}else{$C.lifecycle}
  if(-not $l){return [pscustomobject]@{State='UNKNOWN';Phase='';Elapsed='';Network='UNKNOWN'}}
  $state=[string]$l.state
  $phase=[string]$l.phase
  $elapsed=if($state -match 'PROCESSING|TOOL_RUNNING|WAITING'){Get-Elapsed ([string]$l.started_at)}else{''}
  $network=if($l.network){[string]$l.network}else{'UNKNOWN'}
  return [pscustomobject]@{State=$state;Phase=$phase;Elapsed=$elapsed;Network=$network}
}

function Get-LocalRam {
  $self=Get-Process -Id $PID -ErrorAction SilentlyContinue
  $dc=Get-CimInstance Win32_Process|Where-Object{$_.Name-eq'node.exe' -and $_.CommandLine-match'desktop-commander.*remote'}|Select-Object -First 1
  $dcRam=0
  if($dc){$p=Get-Process -Id $dc.ProcessId -ErrorAction SilentlyContinue;if($p){$dcRam=[math]::Round($p.WorkingSet64/1MB,1)}}
  $selfRam=if($self){[math]::Round($self.WorkingSet64/1MB,1)}else{0}
  return [pscustomobject]@{Viewer=$selfRam;DC=$dcRam;Total=[math]::Round($selfRam+$dcRam,1)}
}

function Get-DriveState {
  if(Get-Process GoogleDriveFS -ErrorAction SilentlyContinue){return 'ACTIF'}
  return 'ARRETE'
}

function Get-Eta($ConversationId,[int]$CurrentPct,[int]$ScopeCount){
  $p=Join-Path $HistoryDir ($ConversationId+'.jsonl')
  if(-not(Test-Path$p)){return 'ETA: donnees insuffisantes'}
  $rows=@(Get-Content $p -Tail 30|ForEach-Object{try{$_|ConvertFrom-Json}catch{}})
  $samples=@($rows|Where-Object{$_.scope_count-eq$ScopeCount}|Select-Object -Last 8)
  if($samples.Count-lt 4){return 'ETA: portee stable insuffisante'}
  try{
    $a=$samples[0];$b=$samples[-1]
    $mins=([datetimeoffset]::Parse($b.at)-[datetimeoffset]::Parse($a.at)).TotalMinutes
    $delta=[double]$b.percent-[double]$a.percent
    if($mins-le 0 -or $delta-le 0){return 'ETA: tendance insuffisante'}
    $rate=$delta/$mins
    if($rate-lt 0.05){return 'ETA: tendance trop faible'}
    $remain=(100-$CurrentPct)/$rate
    if($remain-gt 1440){return 'ETA: >24h, confiance faible'}
    return ('ETA indicative: ~'+[math]::Round($remain,0)+' min si la portee reste stable')
  }catch{return 'ETA: calcul indisponible'}
}

function Save-HistoryIfChanged {
  $c=Get-SelectedConversation
  if(-not$c){return}
  $p=Get-ConversationProgress $c
  $life=Get-LifeState $c
  $scope=$p.MacroCount
  $digest="$($c.id)|$($p.Percent)|$scope|$($life.State)|$($life.Phase)"
  if($digest-eq$LastStateDigest){return}
  $script:LastStateDigest=$digest
  $path=Join-Path $HistoryDir ($c.id+'.jsonl')
  ([ordered]@{at=(Get-Date).ToString('o');percent=$p.Percent;scope_count=$scope;state=$life.State;phase=$life.Phase}|ConvertTo-Json -Compress)|Add-Content $path -Encoding UTF8
  if((Get-Item $path).Length-gt$HistoryMaxBytes){
    @(Get-Content $path -Tail 500)|Set-Content $path -Encoding UTF8
  }
}

function Detect-Changes {
  if(-not$Overview){return}
  foreach($c in @($Overview.conversations)){
    $p=Get-ConversationProgress $c
    $key=[string]$c.id
    $life=Get-LifeState $c
    if($Previous.ContainsKey($key)){
      $old=$Previous[$key]
      if([int]$old.MacroCount-ne$p.MacroCount){
        Add-Notice ("$($c.label): portee $($old.MacroCount) -> $($p.MacroCount) macro-tache(s); progression recalculee.") 'SCOPE'
      }
      if([int]$old.Percent-ne$p.Percent){
        $d=$p.Percent-[int]$old.Percent
        $prefix=if($d-gt0){'+'}else{''}
        Add-Notice ("$($c.label): progression $prefix$d point(s).") 'PROGRESS'
      }
      if($old.State-ne$life.State){Add-Notice("$($c.label): etat $($old.State) -> $($life.State).") 'STATE'}
    }
    $Previous[$key]=[pscustomobject]@{Percent=$p.Percent;MacroCount=$p.MacroCount;State=$life.State}
  }
}
