$script:PcSessionRxBytes = 0
$script:PcSyncFailures = 0
$script:PcPullProcess = $null
$script:PcPullStartedAt = $null
$script:PcPullBranch = $null
$script:PcLastPullOkAt = $null
$script:PcLastPullError = $null
$script:PcUpdateProcess = $null
$script:PcUpdateStartedAt = $null
$script:PcLastUpdateError = $null
$script:PcIoScriptRoot = $PSScriptRoot
$script:PcPowerShellCapsCache = $null
$script:PcPowerShellCapsCacheAt = [datetime]::MinValue
$script:PcPowerShellCatalogCache = $null
$script:PcPowerShellCatalogCacheAt = [datetime]::MinValue
$script:PcReadOnlyDiagCache = $null
$script:PcReadOnlyDiagCacheAt = [datetime]::MinValue
$script:PcNetworkSnapshotCache = $null
$script:PcNetworkSnapshotCacheAt = [datetime]::MinValue

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
    if(Test-Path $regPath){$result.Registry=Get-Content $regPath -Raw -Encoding UTF8|ConvertFrom-Json}
    if(Test-Path $ovPath){$result.Overview=Get-Content $ovPath -Raw -Encoding UTF8|ConvertFrom-Json}
    if($NeedDetail -and $result.Registry -and $result.Overview -and @($result.Overview.conversations).Count-gt$ConversationIndex){
      $id=[string]$result.Overview.conversations[$ConversationIndex].id
      $ch=@($result.Registry.channels|Where-Object id -eq $id|Select-Object -First 1)
      if($ch.Count-gt0 -and $ch[0].state_path){
        $chPath=Join-Path $Paths.StateRepo ([string]$ch[0].state_path)
        if(Test-Path $chPath){$result.Channel=Get-Content $chPath -Raw -Encoding UTF8|ConvertFrom-Json}
      }
    }
    if($result.Overview){$result.Online=$true}
    if(-not$result.Overview){$result.Error='Etat local absent'}
  }catch{$result.Error=$_.Exception.Message}

  if(-not$result.Overview){
    try{$result.Registry=Get-Content (Join-Path $Paths.Cache 'registry.json') -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
    try{$result.Overview=Get-Content (Join-Path $Paths.Cache 'overview.json') -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
    if($NeedDetail -and $result.Overview -and @($result.Overview.conversations).Count-gt$ConversationIndex){
      $id=[string]$result.Overview.conversations[$ConversationIndex].id
      try{$result.Channel=Get-Content (Join-Path $Paths.Cache ("channel-$id.json")) -Raw -Encoding UTF8|ConvertFrom-Json}catch{}
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
    $branch=if($Config.state.branch){[string]$Config.state.branch}else{'main'}
    $script:PcPullBranch=$branch
    $psi.Arguments='-C '+$repoArg+' fetch origin '+$branch+' --quiet'
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
    try{
      $git=(Get-Command git.exe -ErrorAction Stop).Source
      $branch=if($script:PcPullBranch){$script:PcPullBranch}else{'main'}
      $mergeOut=& $git -C $Paths.StateRepo merge --ff-only ("origin/"+$branch) --quiet 2>&1
      if($LASTEXITCODE-ne0){throw (($mergeOut|Out-String).Trim())}
      $script:PcLastPullOkAt=Get-Date
      $script:PcLastPullError=$null
      $script:PcSyncFailures=0
      ([ordered]@{last_success=$script:PcLastPullOkAt.ToString('o');last_error=$null;branch=$branch}|ConvertTo-Json)|Set-Content $Paths.SyncStatus -Encoding UTF8
      return [pscustomobject]@{Completed=$true;Success=$true;Changed=$true;Output=(($out+[Environment]::NewLine+($mergeOut|Out-String)).Trim())}
    }catch{
      $script:PcSyncFailures++
      $script:PcLastPullError=$_.Exception.Message
      ([ordered]@{last_success=if($script:PcLastPullOkAt){$script:PcLastPullOkAt.ToString('o')}else{$null};last_error=$script:PcLastPullError;failed_at=(Get-Date).ToString('o')}|ConvertTo-Json)|Set-Content $Paths.SyncStatus -Encoding UTF8
      return [pscustomobject]@{Completed=$true;Success=$false;Changed=$false;Error=$script:PcLastPullError}
    }
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
      $lines=Get-Content $HistoryFile -Encoding UTF8 -Tail 1500
      [IO.File]::WriteAllLines($HistoryFile,$lines,[Text.UTF8Encoding]::new($false))
    }
  }catch{}
}

function Save-PcLocalSettings {
  param($Paths,[double]$Sync,[double]$Calc,[int]$Display,[string]$Mode)
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
  $errors=@()
  $index=$null
  $versions=$null
  $events=@()

  $idx=Join-Path $base 'feedback-index.json'
  if(Test-Path $idx){
    try{$index=Get-Content $idx -Raw -Encoding UTF8|ConvertFrom-Json}
    catch{$errors+=('index: '+$_.Exception.Message)}
  }

  $ledger=Join-Path $base 'feedback-ledger.jsonl'
  if(Test-Path $ledger){
    try{
      foreach($line in @(Get-Content $ledger -Encoding UTF8 -ErrorAction Stop)){
        if([string]::IsNullOrWhiteSpace([string]$line)){continue}
        try{$events+=($line|ConvertFrom-Json)}
        catch{$errors+=('ledger-line: '+$_.Exception.Message)}
      }
    }catch{$errors+=('ledger: '+$_.Exception.Message)}
  }

  $vt=Join-Path $base 'version-trace.json'
  if(Test-Path $vt){
    try{$versions=Get-Content $vt -Raw -Encoding UTF8|ConvertFrom-Json}
    catch{$errors+=('versions: '+$_.Exception.Message)}
  }

  # Reconcile the human pointer from the machine ledger instead of trusting
  # a stale index. The ledger remains the source of truth for chronology.
  if($events.Count-gt0){
    $latest=@($events|Sort-Object {
      try{[datetimeoffset]::Parse([string]$_.at)}catch{[datetimeoffset]::MinValue}
    }|Select-Object -Last 1)
    if(-not$index){
      $index=[pscustomobject]@{
        schema='pc.command.feedback.index.derived.v1'
        total_feedbacks=$events.Count
        unique_feedback_ids=@($events.feedback_id|Sort-Object -Unique).Count
        last_feedback_id=[string]$latest[0].feedback_id
        last_feedback_at=[string]$latest[0].at
        policy='A+B+C -> MERGE+REFINE+PRESERVE'
      }
    }else{
      $index.total_feedbacks=$events.Count
      if($index.PSObject.Properties.Name -contains 'unique_feedback_ids'){
        $index.unique_feedback_ids=@($events.feedback_id|Sort-Object -Unique).Count
      }
      $index.last_feedback_id=[string]$latest[0].feedback_id
      if($index.PSObject.Properties.Name -contains 'last_feedback_at'){
        $index.last_feedback_at=[string]$latest[0].at
      }else{
        $index|Add-Member -NotePropertyName last_feedback_at -NotePropertyValue ([string]$latest[0].at) -Force
      }
    }
  }

  $recent=@($events|Sort-Object {
    try{[datetimeoffset]::Parse([string]$_.at)}catch{[datetimeoffset]::MinValue}
  }|Select-Object -Last 12)

  return [pscustomobject]@{
    Index=$index
    Recent=$recent
    Versions=$versions
    Error=if($errors.Count){$errors -join ' | '}else{$null}
  }
}

function Start-PcUpdateProbe {
  param($Config,$Paths)
  if($script:PcUpdateProcess -and -not$script:PcUpdateProcess.HasExited){return $false}
  try{
    $gh=(Get-Command gh.exe -ErrorAction SilentlyContinue).Source
    if(-not$gh){$script:PcLastUpdateError='GitHub CLI absent';return $false}
    $repo=[string]$Config.code.repo
    $branch=if($Config.updater.manifest_ref){[string]$Config.updater.manifest_ref}else{[string]$Config.code.branch}
    $base=[string]$Config.code.base_path
    $endpoint='repos/'+$repo+'/contents/'+$base+'/manifest.json?ref='+[uri]::EscapeDataString($branch)
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$gh
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true
    $psi.RedirectStandardError=$true
    $psi.Arguments='api "'+$endpoint+'"'
    $script:PcUpdateProcess=[Diagnostics.Process]::Start($psi)
    $script:PcUpdateStartedAt=Get-Date
    return $true
  }catch{
    $script:PcLastUpdateError=$_.Exception.Message
    return $false
  }
}

function Complete-PcUpdateProbe {
  param($Config)
  if(-not$script:PcUpdateProcess){
    return [pscustomobject]@{Completed=$false;Success=$false;Available=$false;Version=[string]$Config.version;Manifest=$null;Error=$null}
  }
  if(-not$script:PcUpdateProcess.HasExited){
    return [pscustomobject]@{Completed=$false;Success=$false;Available=$false;Version=[string]$Config.version;Manifest=$null;Error=$null}
  }
  $out=$script:PcUpdateProcess.StandardOutput.ReadToEnd()
  $err=$script:PcUpdateProcess.StandardError.ReadToEnd()
  $code=$script:PcUpdateProcess.ExitCode
  $script:PcUpdateProcess.Dispose()
  $script:PcUpdateProcess=$null
  if($code-ne0){
    $script:PcLastUpdateError=$err
    return [pscustomobject]@{Completed=$true;Success=$false;Available=$false;Version=[string]$Config.version;Manifest=$null;Error=$err}
  }
  try{
    $meta=$out|ConvertFrom-Json
    $bytes=[Convert]::FromBase64String(([string]$meta.content -replace '\s',''))
    $manifest=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
    $available=([version]$manifest.version -gt [version]$Config.version)
    $script:PcLastUpdateError=$null
    return [pscustomobject]@{Completed=$true;Success=$true;Available=$available;Version=[string]$manifest.version;Manifest=$manifest;Error=$null}
  }catch{
    $script:PcLastUpdateError=$_.Exception.Message
    return [pscustomobject]@{Completed=$true;Success=$false;Available=$false;Version=[string]$Config.version;Manifest=$null;Error=$_.Exception.Message}
  }
}

function Get-PcModuleVersion {
  param([string]$Name)
  # Avoid Get-Module -ListAvailable here: it can populate the module analysis
  # cache and create a noticeable first-use RAM spike on a 4 GB PC.
  foreach($root in @($env:PSModulePath -split ';' | Where-Object {$_} | Select-Object -Unique)){
    try{
      $dir=Join-Path $root $Name
      if(-not(Test-Path -LiteralPath $dir -PathType Container)){continue}
      $versions=New-Object System.Collections.Generic.List[version]
      foreach($child in @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue)){
        try{$versions.Add([version]$child.Name)}catch{}
      }
      if($versions.Count-gt0){
        return [string](@($versions|Sort-Object -Descending)[0])
      }
      $manifest=Join-Path $dir ($Name+'.psd1')
      if(Test-Path -LiteralPath $manifest){
        $line=Select-String -LiteralPath $manifest -Pattern '^\s*ModuleVersion\s*=\s*[''"]?([^''"\s]+)' -ErrorAction SilentlyContinue | Select-Object -First 1
        if($line -and $line.Matches.Count){
          return [string]$line.Matches[0].Groups[1].Value
        }
      }
      return 'present'
    }catch{}
  }
  return $null
}

function Get-PcPowerShellCapabilitySnapshot {
  param([int]$TtlSeconds=60)
  $now=Get-Date
  if($script:PcPowerShellCapsCache -and $TtlSeconds -gt 0 -and
     (($now-$script:PcPowerShellCapsCacheAt).TotalSeconds -lt $TtlSeconds)){
    return $script:PcPowerShellCapsCache
  }

  $pwsh=Get-Command pwsh.exe -ErrorAction SilentlyContinue
  $winget=Get-Command winget.exe -ErrorAction SilentlyContinue
  $git=Get-Command git.exe -ErrorAction SilentlyContinue
  $pwshVersion=$null
  $pwshPath=$null
  $wingetPath=$null
  if($pwsh){
    $pwshPath=[string]$pwsh.Source
    try{$pwshVersion=(Get-Item $pwsh.Source -ErrorAction Stop).VersionInfo.ProductVersion}catch{}
  }
  if($winget){$wingetPath=[string]$winget.Source}

  $mods=[ordered]@{
    PSResourceGet=(Get-PcModuleVersion 'Microsoft.PowerShell.PSResourceGet')
    PSScriptAnalyzer=(Get-PcModuleVersion 'PSScriptAnalyzer')
    Pester=(Get-PcModuleVersion 'Pester')
    EventViewerX=(Get-PcModuleVersion 'EventViewerX')
    PSWindowsUpdate=(Get-PcModuleVersion 'PSWindowsUpdate')
    PSWriteHTML=(Get-PcModuleVersion 'PSWriteHTML')
    PowerShellYaml=(Get-PcModuleVersion 'powershell-yaml')
    ScheduledTaskManagement=(Get-PcModuleVersion 'ScheduledTaskManagement')
  }

  # Check the backing Windows modules on disk instead of calling Get-Command
  # for module-backed cmdlets. Get-Command can warm NetTCPIP/ScheduledTasks
  # discovery caches and add tens of MB to the first Sources view.
  $diagAvailable=[bool](Get-PcModuleVersion 'Microsoft.PowerShell.Diagnostics')
  $scheduledAvailable=[bool](Get-PcModuleVersion 'ScheduledTasks')
  $netTcpAvailable=[bool](Get-PcModuleVersion 'NetTCPIP')
  $managementAvailable=[bool](Get-PcModuleVersion 'Microsoft.PowerShell.Management')
  $native=[ordered]@{
    GetWinEvent=$diagAvailable
    GetScheduledTask=$scheduledAvailable
    GetNetTCPConnection=$netTcpAvailable
    GetComputerInfo=$managementAvailable
    TestNetConnection=$netTcpAvailable
  }

  $result=[pscustomobject]@{
    ObservedAt=$now
    Engine=('Windows PowerShell '+$PSVersionTable.PSVersion.ToString())
    PSEdition=[string]$PSVersionTable.PSEdition
    Pwsh7Detected=[bool]$pwsh
    Pwsh7Path=$pwshPath
    Pwsh7Version=$pwshVersion
    WinGetDetected=[bool]$winget
    WinGetPath=$wingetPath
    GitDetected=[bool]$git
    Native=[pscustomobject]$native
    Modules=[pscustomobject]$mods
    InstallPerformed=$false
    ResidentDependencyAdded=$false
    Policy='native-first / on-demand / no runtime auto-install'
  }
  $script:PcPowerShellCapsCache=$result
  $script:PcPowerShellCapsCacheAt=$now
  return $result
}

function Get-PcPowerShellSourceCatalog {
  param([int]$TtlSeconds=300)
  $now=Get-Date
  if($script:PcPowerShellCatalogCache -and $TtlSeconds -gt 0 -and
     (($now-$script:PcPowerShellCatalogCacheAt).TotalSeconds -lt $TtlSeconds)){
    return $script:PcPowerShellCatalogCache
  }

  $path=Join-Path (Split-Path $script:PcIoScriptRoot -Parent) 'powershell-sources.json'
  if(-not(Test-Path $path)){
    return [pscustomobject]@{Total=0;Counts=[pscustomobject]@{};Entries=@();Error='Catalogue absent'}
  }
  try{
    $raw=Get-Content $path -Raw -Encoding UTF8|ConvertFrom-Json
    $entries=@($raw.entries)
    $counts=[ordered]@{}
    foreach($class in @('CORE','ON-DEMAND','SOURCE-ONLY','EXTERNAL-TOOL','REJECT')){
      $counts[$class]=@($entries|Where-Object class -eq $class).Count
    }
    $result=[pscustomobject]@{
      Total=$entries.Count
      Counts=[pscustomobject]$counts
      Entries=$entries
      Policy=$raw.policy
      ObservedAt=$raw.observed_at
      Error=$null
    }
    $script:PcPowerShellCatalogCache=$result
    $script:PcPowerShellCatalogCacheAt=$now
    return $result
  }catch{
    return [pscustomobject]@{Total=0;Counts=[pscustomobject]@{};Entries=@();Error=$_.Exception.Message}
  }
}

function Get-PcReadOnlyDiagnostics {
  param(
    [int]$TtlSeconds=30,
    [int]$RecentErrorHours=6,
    [int]$MaxRecentErrors=5
  )
  $now=Get-Date
  if($script:PcReadOnlyDiagCache -and $TtlSeconds -gt 0 -and
     (($now-$script:PcReadOnlyDiagCacheAt).TotalSeconds -lt $TtlSeconds)){
    return $script:PcReadOnlyDiagCache
  }

  $errors=New-Object System.Collections.Generic.List[string]
  $drives=@()
  try{
    foreach($d in @([IO.DriveInfo]::GetDrives())){
      if(-not$d.IsReady -or $d.DriveType -ne [IO.DriveType]::Fixed){continue}
      $total=[double]$d.TotalSize
      $free=[double]$d.AvailableFreeSpace
      $pctFree=if($total-gt0){[math]::Round(($free/$total)*100,1)}else{0}
      $drives += [pscustomobject]@{
        Name=[string]$d.Name
        TotalGB=[math]::Round($total/1GB,1)
        FreeGB=[math]::Round($free/1GB,1)
        FreePercent=$pctFree
      }
    }
  }catch{$errors.Add('drive: '+$_.Exception.Message)}

  $networkAvailable=$false
  try{$networkAvailable=[Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()}
  catch{$errors.Add('network: '+$_.Exception.Message)}

  $freeRamMb=$null
  $totalRamMb=$null
  $uptimeHours=$null
  try{
    $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $freeRamMb=[math]::Round(([double]$os.FreePhysicalMemory/1024),0)
    $totalRamMb=[math]::Round(([double]$os.TotalVisibleMemorySize/1024),0)
    $boot=[Management.ManagementDateTimeConverter]::ToDateTime([string]$os.LastBootUpTime)
    $uptimeHours=[math]::Round(((Get-Date)-$boot).TotalHours,1)
  }catch{
    try{
      $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
      $freeRamMb=[math]::Round(([double]$os.FreePhysicalMemory/1024),0)
      $totalRamMb=[math]::Round(([double]$os.TotalVisibleMemorySize/1024),0)
      $uptimeHours=[math]::Round(((Get-Date)-[datetime]$os.LastBootUpTime).TotalHours,1)
    }catch{$errors.Add('os: '+$_.Exception.Message)}
  }

  $recent=@()
  try{
    if($MaxRecentErrors-gt0){
      $since=(Get-Date).AddHours(-[math]::Abs($RecentErrorHours))
      $recent=@(Get-WinEvent -FilterHashtable @{LogName='System';Level=2;StartTime=$since} -MaxEvents $MaxRecentErrors -ErrorAction SilentlyContinue |
        Select-Object TimeCreated,Id,ProviderName,LevelDisplayName)
    }
  }catch{$errors.Add('events: '+$_.Exception.Message)}

  $result=[pscustomobject]@{
    ObservedAt=$now
    NetworkAvailable=[bool]$networkAvailable
    FreeRamMb=$freeRamMb
    TotalRamMb=$totalRamMb
    UptimeHours=$uptimeHours
    FixedDrives=$drives
    RecentSystemErrors=$recent
    RecentErrorHours=$RecentErrorHours
    MaxRecentErrors=$MaxRecentErrors
    Error=if($errors.Count){$errors -join ' | '}else{$null}
    ReadOnly=$true
    NetworkTrafficGenerated=$false
    DnsCacheModified=$false
    ExternalModuleRequired=$false
    SourcePolicy='native bounded read-only'
  }

  $script:PcReadOnlyDiagCache=$result
  $script:PcReadOnlyDiagCacheAt=$now
  return $result
}

function Get-PcLocalNetworkSnapshot {
  param([int]$TtlSeconds=30)
  $now=Get-Date
  if($script:PcNetworkSnapshotCache -and $TtlSeconds -gt 0 -and
     (($now-$script:PcNetworkSnapshotCacheAt).TotalSeconds -lt $TtlSeconds)){
    return $script:PcNetworkSnapshotCache
  }

  $rows=@()
  $errors=New-Object System.Collections.Generic.List[string]
  try{
    foreach($nic in @([Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces())){
      if($nic.NetworkInterfaceType -eq [Net.NetworkInformation.NetworkInterfaceType]::Loopback){continue}
      $props=$nic.GetIPProperties()
      $v4=@($props.UnicastAddresses |
        Where-Object {$_.Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork} |
        ForEach-Object {$_.Address.IPAddressToString} |
        Where-Object {$_ -and $_ -notmatch '^169\.254\.' -and $_ -notmatch '^127\.'} |
        Select-Object -Unique)
      $gw=@($props.GatewayAddresses |
        Where-Object {$_.Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork} |
        ForEach-Object {$_.Address.IPAddressToString} |
        Where-Object {$_} |
        Select-Object -Unique)
      $dns=@($props.DnsAddresses |
        Where-Object {$_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork} |
        ForEach-Object {$_.IPAddressToString} |
        Where-Object {$_} |
        Select-Object -Unique)
      $rows += [pscustomobject]@{
        Name=[string]$nic.Name
        Description=[string]$nic.Description
        Type=[string]$nic.NetworkInterfaceType
        Status=[string]$nic.OperationalStatus
        IPv4=$v4
        Gateway=$gw
        DNS=$dns
        LinkMbps=if([double]$nic.Speed-gt0){[math]::Round(([double]$nic.Speed/1MB)*8,0)}else{0}
      }
    }
  }catch{$errors.Add('network-snapshot: '+$_.Exception.Message)}

  $primary=$null
  $primary=@($rows | Where-Object {
    $_.Status -eq 'Up' -and @($_.IPv4).Count-gt0 -and @($_.Gateway).Count-gt0
  } | Select-Object -First 1)
  if($primary.Count-eq0){
    $primary=@($rows | Where-Object {
      $_.Status -eq 'Up' -and @($_.IPv4).Count-gt0
    } | Select-Object -First 1)
  }

  $result=[pscustomobject]@{
    ObservedAt=$now
    Primary=if($primary.Count){$primary[0]}else{$null}
    Interfaces=$rows
    ReadOnly=$true
    NetworkTrafficGenerated=$false
    ExternalLookup=$false
    DnsCacheModified=$false
    ActiveProbeUsed=$false
    ExternalModuleRequired=$false
    Error=if($errors.Count){$errors -join ' | '}else{$null}
    SourcePolicy='local .NET network introspection only'
  }
  $script:PcNetworkSnapshotCache=$result
  $script:PcNetworkSnapshotCacheAt=$now
  return $result
}

