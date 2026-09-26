$script:PcSessionRxBytes = 0
$script:PcSyncFailures = 0
$script:PcPullProcess = $null
$script:PcPullStartedAt = $null
$script:PcLastPullOkAt = $null
$script:PcLastPullError = $null

function Initialize-PcPaths {
  param([string]$Root)
  $p=[ordered]@{}
  $p.Root=$Root
  $p.Data=Join-Path $Root 'data'
  $p.Cache=Join-Path $p.Data 'cache'
  $p.History=Join-Path $p.Data 'history'
  $p.Reports=Join-Path $Root 'reports'
  $p.Backup=Join-Path $Root 'backup'
  $p.Config=Join-Path $Root 'config'
  $p.StateRepo=Join-Path $Root 'state-repo'
  foreach($v in @($p.Data,$p.Cache,$p.History,$p.Reports,$p.Backup,$p.Config)){New-Item -ItemType Directory -Force -Path $v|Out-Null}
  $p.HistoryFile=Join-Path $p.History 'progress.jsonl'
  $p.LocalConfig=Join-Path $p.Config 'config.local.json'
  $p.SyncStatus=Join-Path $p.Cache 'state-sync.json'
  return [pscustomobject]$p
}

function Write-PcAtomic {
  param([string]$Path,[string]$Content)
  $tmp=$Path+'.tmp'
  [IO.File]::WriteAllText($tmp,$Content,[Text.UTF8Encoding]::new($false))
  Move-Item $tmp $Path -Force
}

function Initialize-PcStateRepo {
  param($Config,$Paths)
  if(Test-Path (Join-Path $Paths.StateRepo '.git')){return $true}
  $gh=(Get-Command gh.exe -ErrorAction SilentlyContinue).Source
  if(-not$gh){$script:PcLastPullError='GitHub CLI absent';return $false}
  try{
    New-Item -ItemType Directory -Force -Path (Split-Path $Paths.StateRepo -Parent)|Out-Null
    & $gh repo clone ([string]$Config.state.repo) $Paths.StateRepo -- --quiet 2>$null | Out-Null
    if(Test-Path (Join-Path $Paths.StateRepo '.git')){
      $script:PcLastPullOkAt=Get-Date
      return $true
    }
  }catch{$script:PcLastPullError=$_.Exception.Message}
  return $false
}

function Read-PcStateLocal {
  param($Config,$Paths,[int]$ConversationIndex=0,[switch]$NeedDetail)
  $result=[ordered]@{Online=$false;Registry=$null;Overview=$null;Channel=$null;Error=$null;SyncedAt=$script:PcLastPullOkAt;Source='LOCAL_STATE_REPO'}
  try{
    $regPath=Join-Path $Paths.StateRepo ([string]$Config.state.registry_path)
    $ovPath=Join-Path $Paths.StateRepo ([string]$Config.state.overview_path)
    if(Test-Path $regPath){$result.Registry=Get-Content $regPath -Raw|ConvertFrom-Json}
    if(Test-Path $ovPath){$result.Overview=Get-Content $ovPath -Raw|ConvertFrom-Json}
    if($NeedDetail -and $result.Registry -and $result.Overview -and @($result.Overview.conversations).Count-gt$ConversationIndex){
      $id=[string]$result.Overview.conversations[$ConversationIndex].id
      $ch=@($result.Registry.channels|Where-Object id -eq $id|Select-Object -First 1)
      if($ch.Count-gt0 -and $ch[0].state_path){
        $chPath=Join-Path $Paths.StateRepo ([string]$ch[0].state_path)
        if(Test-Path $chPath){$result.Channel=Get-Content $chPath -Raw|ConvertFrom-Json}
      }
    }
    if($result.Overview){$result.Online=$true}
    if(-not$result.Overview){$result.Error='Etat local absent'}
  }catch{$result.Error=$_.Exception.Message}

  if(-not$result.Overview){
    try{$result.Registry=Get-Content (Join-Path $Paths.Cache 'registry.json') -Raw|ConvertFrom-Json}catch{}
    try{$result.Overview=Get-Content (Join-Path $Paths.Cache 'overview.json') -Raw|ConvertFrom-Json}catch{}
    if($NeedDetail -and $result.Overview -and @($result.Overview.conversations).Count-gt$ConversationIndex){
      $id=[string]$result.Overview.conversations[$ConversationIndex].id
      try{$result.Channel=Get-Content (Join-Path $Paths.Cache ("channel-$id.json")) -Raw|ConvertFrom-Json}catch{}
    }
    if($result.Overview){$result.Source='CACHE';$result.Online=$false}
  }else{
    try{
      ($result.Registry|ConvertTo-Json -Depth 12)|Set-Content (Join-Path $Paths.Cache 'registry.json') -Encoding UTF8
      ($result.Overview|ConvertTo-Json -Depth 12)|Set-Content (Join-Path $Paths.Cache 'overview.json') -Encoding UTF8
      if($result.Channel){
        $id=[string]$result.Channel.conversation_id
        ($result.Channel|ConvertTo-Json -Depth 20)|Set-Content (Join-Path $Paths.Cache ("channel-$id.json")) -Encoding UTF8
      }
    }catch{}
  }
  return [pscustomobject]$result
}

function Start-PcStatePull {
  param($Config,$Paths)
  if(-not(Test-Path (Join-Path $Paths.StateRepo '.git'))){return $false}
  if($script:PcPullProcess -and -not$script:PcPullProcess.HasExited){return $false}
  try{
    $git=(Get-Command git.exe -ErrorAction SilentlyContinue).Source
    if(-not$git){$script:PcLastPullError='git.exe absent';return $false}
    $env:GIT_TERMINAL_PROMPT='0'
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$git
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true
    $psi.RedirectStandardError=$true
    # Windows PowerShell 5.1/.NET Framework has no ProcessStartInfo.ArgumentList.
    # Quote the repo path explicitly and use Arguments for compatibility.
    $repoArg='"'+([string]$Paths.StateRepo).Replace('"','\"')+'"'
    $psi.Arguments='-C '+$repoArg+' pull --ff-only --quiet'
    $script:PcPullProcess=[Diagnostics.Process]::Start($psi)
    $script:PcPullStartedAt=Get-Date
    return $true
  }catch{$script:PcLastPullError=$_.Exception.Message;$script:PcSyncFailures++;return $false}
}

function Complete-PcStatePull {
  param($Paths)
  if(-not$script:PcPullProcess){return [pscustomobject]@{Completed=$false;Success=$false;Changed=$false}}
  if(-not$script:PcPullProcess.HasExited){return [pscustomobject]@{Completed=$false;Success=$false;Changed=$false}}
  $out=$script:PcPullProcess.StandardOutput.ReadToEnd()
  $err=$script:PcPullProcess.StandardError.ReadToEnd()
  $code=$script:PcPullProcess.ExitCode
  $script:PcPullProcess.Dispose()
  $script:PcPullProcess=$null
  if($code-eq0){
    $script:PcLastPullOkAt=Get-Date
    $script:PcLastPullError=$null
    $script:PcSyncFailures=0
    ([ordered]@{last_success=$script:PcLastPullOkAt.ToString('o');last_error=$null}|ConvertTo-Json)|Set-Content $Paths.SyncStatus -Encoding UTF8
    return [pscustomobject]@{Completed=$true;Success=$true;Changed=$true;Output=$out}
  }
  $script:PcSyncFailures++
  $script:PcLastPullError=$err
  ([ordered]@{last_success=if($script:PcLastPullOkAt){$script:PcLastPullOkAt.ToString('o')}else{$null};last_error=$err;failed_at=(Get-Date).ToString('o')}|ConvertTo-Json)|Set-Content $Paths.SyncStatus -Encoding UTF8
  return [pscustomobject]@{Completed=$true;Success=$false;Changed=$false;Error=$err}
}

function Save-PcHistory {
  param($Overview,[string]$HistoryFile,[int]$MaxBytes=524288)
  if(-not$Overview){return}
  $row=[ordered]@{at=(Get-Date).ToString('o');conversations=@()}
  foreach($c in @($Overview.conversations)){
    $row.conversations += [ordered]@{
      id=$c.id
      percent=if($null-ne$c.progress_estimate){[int]$c.progress_estimate}else{0}
      macro_count=if($null-ne$c.macro_count){[int]$c.macro_count}else{0}
      state=if($c.lifecycle){$c.lifecycle.state}else{'UNKNOWN'}
    }
  }
  ($row|ConvertTo-Json -Compress -Depth 8)|Add-Content -Path $HistoryFile -Encoding UTF8
  try{
    if((Get-Item $HistoryFile).Length-gt$MaxBytes){
      $lines=Get-Content $HistoryFile -Tail 1500
      [IO.File]::WriteAllLines($HistoryFile,$lines,[Text.UTF8Encoding]::new($false))
    }
  }catch{}
}

function Save-PcLocalSettings {
  param($Paths,[int]$Sync,[int]$Calc,[int]$Display,[string]$Mode)
  $o=[ordered]@{internet_sync_seconds=$Sync;engine_recalc_seconds=$Calc;display_refresh_seconds=$Display;mode=$Mode;updated_at=(Get-Date).ToString('o')}
  ($o|ConvertTo-Json)|Set-Content $Paths.LocalConfig -Encoding UTF8
}

function Get-PcUpdateInfo {
  param([string]$ManifestUrl,[string]$CurrentVersion)
  try{
    $raw=(Invoke-WebRequest -Uri ($ManifestUrl+'?n='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -TimeoutSec 3 -UseBasicParsing -Headers @{'Cache-Control'='no-cache'}).Content
    $script:PcSessionRxBytes += [Text.Encoding]::UTF8.GetByteCount($raw)
    $m=$raw|ConvertFrom-Json
    return [pscustomobject]@{Available=([version]$m.version -gt[version]$CurrentVersion);Version=[string]$m.version;Manifest=$m;Error=$null}
  }catch{return [pscustomobject]@{Available=$false;Version=$CurrentVersion;Manifest=$null;Error=$_.Exception.Message}}
}


function Read-PcFeedbackLocal {
  param($Paths)
  $base=Join-Path $Paths.StateRepo 'pc-command\feedback'
  $result=[ordered]@{Index=$null;Recent=@();Versions=$null;Error=$null}
  try{
    $idx=Join-Path $base 'feedback-index.json'
    if(Test-Path $idx){$result.Index=Get-Content $idx -Raw|ConvertFrom-Json}
    $ledger=Join-Path $base 'feedback-ledger.jsonl'
    if(Test-Path $ledger){
      $tmp=New-Object System.Collections.Generic.List[object]
      foreach($line in @(Get-Content $ledger -Tail 12 -ErrorAction SilentlyContinue)){
        try{$tmp.Add(($line|ConvertFrom-Json))}catch{}
      }
      $result.Recent=@($tmp)
    }
    $vt=Join-Path $base 'version-trace.json'
    if(Test-Path $vt){$result.Versions=Get-Content $vt -Raw|ConvertFrom-Json}
  }catch{$result.Error=$_.Exception.Message}
  return [pscustomobject]$result
}
