function Invoke-PcGhJson {
  param([string[]]$Args)
  $gh=(Get-Command gh.exe -ErrorAction SilentlyContinue).Source
  if(-not$gh){throw 'GitHub CLI absent'}
  $old=$ErrorActionPreference;$ErrorActionPreference='Continue'
  $out=@(& $gh @Args 2>&1);$code=$LASTEXITCODE;$ErrorActionPreference=$old
  $txt=$out -join [Environment]::NewLine
  if($code-ne0){throw $txt}
  $script:PcSessionRxBytes += [Text.Encoding]::UTF8.GetByteCount($txt)
  return $txt|ConvertFrom-Json
}

function Limit-PcJsonl {
  param([string]$Path,[int]$MaxBytes=1048576,[int]$TailLines=2000)
  try{
    if((Get-Item $Path -ErrorAction Stop).Length-gt$MaxBytes){
      $lines=Get-Content $Path -Tail $TailLines
      [IO.File]::WriteAllLines($Path,$lines,[Text.UTF8Encoding]::new($false))
    }
  }catch{}
}

function Sync-PcEventBus {
  param($Config,$Paths,$Overview,$Channel)
  $result=[ordered]@{Overview=$Overview;Channel=$Channel;NewEvents=0;LastId=0;Error=$null}
  if(-not$Config.event_bus -or -not$Config.event_bus.enabled){return [pscustomobject]$result}
  $cursorPath=Join-Path $Paths.Cache 'eventbus-cursor.json'
  $eventPath=Join-Path $Paths.History 'events.jsonl'
  $lastId=0
  $since=[DateTimeOffset]::Now.AddHours(-2).UtcDateTime.ToString('o')
  if(Test-Path $cursorPath){
    try{
      $cur=Get-Content $cursorPath -Raw|ConvertFrom-Json
      if($cur.last_id){$lastId=[int64]$cur.last_id}
      if($cur.since){$since=[string]$cur.since}
    }catch{}
  }
  try{
    $repo=[string]$Config.event_bus.repo
    $issue=[int]$Config.event_bus.issue_number
    $endpoint="repos/$repo/issues/$issue/comments"
    $comments=@(Invoke-PcGhJson @('api','--method','GET','-f','per_page=100','-f',("since=$since"),$endpoint))
    $maxId=$lastId;$maxTime=$since
    foreach($cm in $comments|Sort-Object created_at,id){
      $cid=[int64]$cm.id
      if($cid-le$lastId){continue}
      $body=[string]$cm.body
      if(-not$body.StartsWith('[PCEVENT v1] ')){continue}
      try{$ev=$body.Substring(13)|ConvertFrom-Json}catch{continue}
      $wrapped=[ordered]@{comment_id=$cid;received_at=(Get-Date).ToString('o');event=$ev}
      ($wrapped|ConvertTo-Json -Compress -Depth 12)|Add-Content $eventPath -Encoding UTF8
      $result.NewEvents++
      if($cid-gt$maxId){$maxId=$cid}
      if($cm.updated_at -and ([datetimeoffset]$cm.updated_at -gt [datetimeoffset]$maxTime)){$maxTime=[string]$cm.updated_at}
      if($Overview){
        $oc=@($Overview.conversations|Where-Object id -eq $ev.conversation_id|Select-Object -First 1)
        if($oc.Count){
          $o=$oc[0]
          if(-not$o.lifecycle){$o|Add-Member -Force NoteProperty lifecycle ([pscustomobject]@{})}
          if($ev.state){$o.lifecycle|Add-Member -Force NoteProperty state ([string]$ev.state)}
          if($ev.phase){$o.lifecycle|Add-Member -Force NoteProperty phase ([string]$ev.phase)}
          if($ev.time){$o.lifecycle|Add-Member -Force NoteProperty last_signal_at ([string]$ev.time)}
          if($ev.lease_until){$o.lifecycle|Add-Member -Force NoteProperty lease_until ([string]$ev.lease_until)}
          if($ev.summary){$o|Add-Member -Force NoteProperty current_action ([string]$ev.summary)}
        }
      }
      if($Channel -and [string]$Channel.conversation_id -eq [string]$ev.conversation_id){
        if(-not$Channel.current_turn){$Channel|Add-Member -Force NoteProperty current_turn ([pscustomobject]@{})}
        if($ev.turn_id){$Channel.current_turn|Add-Member -Force NoteProperty turn_id ([string]$ev.turn_id)}
        if($ev.state){$Channel.current_turn|Add-Member -Force NoteProperty state ([string]$ev.state)}
        if($ev.phase){$Channel.current_turn|Add-Member -Force NoteProperty phase ([string]$ev.phase)}
        if($ev.time){$Channel.current_turn|Add-Member -Force NoteProperty last_signal_at ([string]$ev.time)}
        if($ev.lease_until){$Channel.current_turn|Add-Member -Force NoteProperty lease_until ([string]$ev.lease_until)}
      }
    }
    if($maxId-gt$lastId){
      $nextSince=try{([datetimeoffset]$maxTime).AddSeconds(-1).UtcDateTime.ToString('o')}catch{[DateTimeOffset]::Now.AddMinutes(-5).UtcDateTime.ToString('o')}
      ([ordered]@{last_id=$maxId;since=$nextSince;updated_at=(Get-Date).ToString('o')}|ConvertTo-Json)|Set-Content $cursorPath -Encoding UTF8
      Limit-PcJsonl $eventPath ([int]$Config.event_bus.history_max_bytes) 2000
    }
    $result.LastId=$maxId
  }catch{$result.Error=$_.Exception.Message}
  return [pscustomobject]$result
}
