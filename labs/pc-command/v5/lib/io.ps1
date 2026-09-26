$script:PcSessionRxBytes = 0
$script:PcSyncFailures = 0

function Initialize-PcPaths {
  param([string]$Root)
  $p=[ordered]@{}
  $p.Root=$Root; $p.Data=Join-Path $Root 'data'; $p.Cache=Join-Path $p.Data 'cache'; $p.History=Join-Path $p.Data 'history'
  $p.Reports=Join-Path $Root 'reports'; $p.Backup=Join-Path $Root 'backup'; $p.Config=Join-Path $Root 'config'
  foreach($v in $p.Values){New-Item -ItemType Directory -Force -Path $v|Out-Null}
  $p.HistoryFile=Join-Path $p.History 'progress.jsonl'; $p.LocalConfig=Join-Path $p.Config 'config.local.json'
  return [pscustomobject]$p
}

function Invoke-PcGhRaw {
  param([string]$Repo,[string]$Path,[string]$Ref='main')
  $gh=(Get-Command gh.exe -ErrorAction SilentlyContinue).Source
  if(-not $gh){throw 'GitHub CLI absent'}
  $args=@('api','-H','Accept: application/vnd.github.raw+json',("repos/$Repo/contents/$Path?ref=$Ref"))
  $psi=New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName=$gh; $psi.UseShellExecute=$false; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
  foreach($a in $args){[void]$psi.ArgumentList.Add($a)}
  $p=[Diagnostics.Process]::Start($psi)
  $out=$p.StandardOutput.ReadToEnd(); $err=$p.StandardError.ReadToEnd(); $p.WaitForExit()
  if($p.ExitCode -ne 0){throw ($err.Trim())}
  $script:PcSessionRxBytes += [Text.Encoding]::UTF8.GetByteCount($out)
  return $out
}

function Write-PcAtomic {
  param([string]$Path,[string]$Content)
  $tmp=$Path+'.tmp'
  [IO.File]::WriteAllText($tmp,$Content,[Text.UTF8Encoding]::new($false))
  Move-Item $tmp $Path -Force
}

function Sync-PcState {
  param($Config,$Paths,[int]$ConversationIndex=0,[switch]$NeedDetail)
  $result=[ordered]@{Online=$false;Registry=$null;Overview=$null;Channel=$null;Error=$null;SyncedAt=(Get-Date)}
  $stateRepo=[string]$Config.state.repo; $stateBranch=[string]$Config.state.branch
  try {
    $regRaw=Invoke-PcGhRaw $stateRepo ([string]$Config.state.registry_path) $stateBranch
    $ovRaw=Invoke-PcGhRaw $stateRepo ([string]$Config.state.overview_path) $stateBranch
    Write-PcAtomic (Join-Path $Paths.Cache 'registry.json') $regRaw
    Write-PcAtomic (Join-Path $Paths.Cache 'overview.json') $ovRaw
    $result.Registry=$regRaw|ConvertFrom-Json; $result.Overview=$ovRaw|ConvertFrom-Json
    if($NeedDetail -and @($result.Overview.conversations).Count -gt $ConversationIndex){
      $id=[string]$result.Overview.conversations[$ConversationIndex].id
      $ch=@($result.Registry.channels|Where-Object id -eq $id|Select-Object -First 1)
      if($ch.Count -gt 0 -and $ch[0].state_path){
        $chRaw=Invoke-PcGhRaw $stateRepo ([string]$ch[0].state_path) $stateBranch
        Write-PcAtomic (Join-Path $Paths.Cache ("channel-$id.json")) $chRaw
        $result.Channel=$chRaw|ConvertFrom-Json
      }
    }
    $result.Online=$true; $script:PcSyncFailures=0
  } catch {
    $script:PcSyncFailures++; $result.Error=$_.Exception.Message
    try {$result.Registry=(Get-Content (Join-Path $Paths.Cache 'registry.json') -Raw)|ConvertFrom-Json}catch{}
    try {$result.Overview=(Get-Content (Join-Path $Paths.Cache 'overview.json') -Raw)|ConvertFrom-Json}catch{}
    if($NeedDetail -and $result.Overview -and @($result.Overview.conversations).Count -gt $ConversationIndex){
      $id=[string]$result.Overview.conversations[$ConversationIndex].id
      try {$result.Channel=(Get-Content (Join-Path $Paths.Cache ("channel-$id.json")) -Raw)|ConvertFrom-Json}catch{}
    }
  }
  return [pscustomobject]$result
}

function Save-PcHistory {
  param($Overview,[string]$HistoryFile,[int]$MaxBytes=524288)
  if(-not $Overview){return}
  $row=[ordered]@{at=(Get-Date).ToString('o');conversations=@()}
  foreach($c in @($Overview.conversations)){
    $row.conversations += [ordered]@{id=$c.id;percent=if($null-ne $c.progress_estimate){[int]$c.progress_estimate}else{0};macro_count=if($null-ne $c.macro_count){[int]$c.macro_count}else{0};state=$c.lifecycle.state}
  }
  ($row|ConvertTo-Json -Compress -Depth 8) | Add-Content -Path $HistoryFile -Encoding UTF8
  try{
    $f=Get-Item $HistoryFile
    if($f.Length -gt $MaxBytes){
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
    $raw=(Invoke-WebRequest -Uri $ManifestUrl -TimeoutSec 5 -UseBasicParsing).Content
    $script:PcSessionRxBytes += [Text.Encoding]::UTF8.GetByteCount($raw)
    $m=$raw|ConvertFrom-Json
    return [pscustomobject]@{Available=([version]$m.version -gt [version]$CurrentVersion);Version=[string]$m.version;Manifest=$m;Error=$null}
  }catch{return [pscustomobject]@{Available=$false;Version=$CurrentVersion;Manifest=$null;Error=$_.Exception.Message}}
}
