param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='SilentlyContinue'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new()
$OutputEncoding=[Console]::OutputEncoding

$Lib=Join-Path $PSScriptRoot 'lib'
. (Join-Path $Lib 'engine.ps1')
. (Join-Path $Lib 'io.ps1')
. (Join-Path $Lib 'report.ps1')
. (Join-Path $Lib 'ui.ps1')

$Defaults=Get-Content (Join-Path $PSScriptRoot 'config.default.json') -Raw|ConvertFrom-Json
$Paths=Initialize-PcPaths $Root
$App=[pscustomobject]@{
  SyncSeconds=[int]$Defaults.cadence.internet_sync_seconds
  EngineSeconds=[int]$Defaults.cadence.engine_recalc_seconds
  DisplaySeconds=[int]$Defaults.cadence.display_refresh_seconds
  Mode='AUTO'
}
if(Test-Path $Paths.LocalConfig){
  try{
    $lc=Get-Content $Paths.LocalConfig -Raw|ConvertFrom-Json
    if($lc.internet_sync_seconds){$App.SyncSeconds=[int]$lc.internet_sync_seconds}
    if($lc.engine_recalc_seconds){$App.EngineSeconds=[int]$lc.engine_recalc_seconds}
    if($lc.display_refresh_seconds){$App.DisplaySeconds=[int]$lc.display_refresh_seconds}
    if($lc.mode){$App.Mode=[string]$lc.mode}
  }catch{}
}

$View='general';$ConversationIndex=0;$MacroIndex=0
$Sync=[pscustomobject]@{Online=$false;Overview=$null;Registry=$null;Channel=$null;Error='Not synced'}
$LastSync=[datetime]::MinValue;$LastCalc=[datetime]::MinValue;$LastDisplay=[datetime]::MinValue;$LastSpinner=[datetime]::MinValue;$LastUpdateCheck=[datetime]::MinValue
$UpdateInfo=$null;$SpinnerIndex=0;$Cycle=0;$ForceDetail=$false
$LocalEvents=New-Object System.Collections.Generic.List[object]
$ManifestUrl='https://raw.githubusercontent.com/Terminator364/BuildHub/lab/pc-command-browser-20260926/labs/pc-command/v5/manifest.json'

try{
  Unregister-Event -SourceIdentifier PcCommandV5Proc -ErrorAction SilentlyContinue
  Register-WmiEvent -Class Win32_ProcessStartTrace -SourceIdentifier PcCommandV5Proc|Out-Null
}catch{}

function Add-LocalPcEvent([string]$Text){
  if(-not$Text){return}
  $LocalEvents.Insert(0,[pscustomobject]@{At=Get-Date;Text=$Text})
  while($LocalEvents.Count-gt15){$LocalEvents.RemoveAt($LocalEvents.Count-1)}
}

function Drain-LocalPcEvents{
  foreach($ev in @(Get-Event -SourceIdentifier PcCommandV5Proc -ErrorAction SilentlyContinue)){
    $pid2=[int]$ev.SourceEventArgs.NewEvent.ProcessID
    $name=[string]$ev.SourceEventArgs.NewEvent.ProcessName
    $p=Get-CimInstance Win32_Process -Filter "ProcessId=$pid2" -ErrorAction SilentlyContinue
    $cmd=if($p){[string]$p.CommandLine}else{''}
    $h=$null
    if($cmd-match'PC_COMMAND'){ } elseif($cmd-match'firefox|msedge|brave|falkon|qutebrowser|helium'){$h='Navigateur/test web lance'}
    elseif($cmd-match'Invoke-WebRequest|Invoke-RestMethod|curl|wget'){$h='Acces Internet/telechargement local'}
    elseif($cmd-match'node|npm|npx'){$h='Processus Node/Desktop Commander'}
    elseif($name-match'powershell|pwsh|cmd'){$h='Commande Windows locale'}
    if($h){Add-LocalPcEvent $h}
    Remove-Event -EventIdentifier $ev.EventIdentifier -ErrorAction SilentlyContinue
  }
}

while($true){
  $now=Get-Date
  Drain-LocalPcEvents

  if(($now-$LastSpinner).TotalSeconds-ge1){
    $sp=@('|','/','-','\')[$SpinnerIndex%4];$SpinnerIndex++;$LastSpinner=$now
    $pct=0;$st='CACHE'
    if($Sync.Overview -and @($Sync.Overview.conversations).Count-gt0){
      $c=$Sync.Overview.conversations[[math]::Min($ConversationIndex,@($Sync.Overview.conversations).Count-1)]
      if($null-ne$c.progress_estimate){$pct=[int]$c.progress_estimate}
      if($c.lifecycle.state){$st=[string]$c.lifecycle.state}
    }
    $Host.UI.RawUI.WindowTitle="PC COMMAND v$($Defaults.version) $sp $st $pct%"
  }

  $needDetail=($View -in @('conversation','macro','timeline')) -or $ForceDetail
  if(($now-$LastSync).TotalSeconds-ge$App.SyncSeconds -or $LastSync-eq[datetime]::MinValue){
    $Sync=Sync-PcState $Defaults $Paths $ConversationIndex -NeedDetail:$needDetail
    $LastSync=$now;$ForceDetail=$false
  }

  if(($now-$LastCalc).TotalSeconds-ge$App.EngineSeconds){
    $Cycle++
    if($Sync.Overview){Save-PcHistory $Sync.Overview $Paths.HistoryFile ([int]$Defaults.limits.history_max_bytes)}
    $LastCalc=$now
  }

  if(($now-$LastUpdateCheck).TotalSeconds-ge300 -or $LastUpdateCheck-eq[datetime]::MinValue){
    $UpdateInfo=Get-PcUpdateInfo $ManifestUrl ([string]$Defaults.version)
    $LastUpdateCheck=$now
  }

  if(($now-$LastDisplay).TotalSeconds-ge$App.DisplaySeconds -or $LastDisplay-eq[datetime]::MinValue){
    Clear-Host
    $conv=$Sync.Channel
    Write-PcHeader $App $Defaults $Sync $conv $UpdateInfo @('|','/','-','\')[$SpinnerIndex%4]
    switch($View){
      'general'{Write-PcGeneral $Sync.Overview}
      'conversation'{if($conv){Write-PcConversation $conv $Paths.HistoryFile}else{Write-Host 'Detail indisponible; synchronisation...' -ForegroundColor Yellow}}
      'macro'{if($conv -and @($conv.macro_tasks).Count-gt$MacroIndex){Write-PcMacro $conv.macro_tasks[$MacroIndex] ([int]$Defaults.limits.max_visible_microtasks)}}
      'timeline'{if($conv){Write-PcTimeline $conv}}
      'sources'{Write-PcSources $Defaults $Sync}
      'local'{Write-PcLocal $LocalEvents}
      'settings'{Write-PcSettings $App $Defaults}
    }
    Write-PcFooter $View
    Write-Host ("Cycle moteur: $Cycle | dernier sync: "+$LastSync.ToString('HH:mm:ss')+" | prochain ecran dans $($App.DisplaySeconds)s") -ForegroundColor DarkGray
    $LastDisplay=$now
  }

  if([Console]::KeyAvailable){
    $k=[Console]::ReadKey($true).KeyChar.ToString().ToUpperInvariant()
    if($k-eq'Q'){Unregister-Event -SourceIdentifier PcCommandV5Proc -ErrorAction SilentlyContinue;break}
    if($k-eq'R'){$LastSync=[datetime]::MinValue;$ForceDetail=$true;$LastDisplay=[datetime]::MinValue}
    elseif($k-eq'A'){$View='general';$LastDisplay=[datetime]::MinValue}
    elseif($k-eq'B'){if($View-eq'macro' -or $View-eq'timeline'){$View='conversation'}elseif($View-eq'conversation'){$View='general'}else{$View='general'};$LastDisplay=[datetime]::MinValue}
    elseif($k-eq'S'){$View='sources';$LastDisplay=[datetime]::MinValue}
    elseif($k-eq'L'){$View='local';$LastDisplay=[datetime]::MinValue}
    elseif($k-eq'P'){$View='settings';$LastDisplay=[datetime]::MinValue}
    elseif($k-eq'T' -and $Sync.Channel){$View='timeline';$LastDisplay=[datetime]::MinValue}
    elseif($k-eq'X'){
      $rep=New-PcReport $Defaults $Sync.Overview $Sync.Channel $Paths
      Add-LocalPcEvent ("Rapport cree: "+$(if($rep.Pdf){$rep.Pdf}else{$rep.Html}))
      if($rep.Pdf){Start-Process explorer.exe -ArgumentList $rep.Pdf}else{Start-Process $rep.Html}
      $LastDisplay=[datetime]::MinValue
    }
    elseif($k-eq'D' -and $View-eq'settings'){
      $last=Get-ChildItem $Paths.Reports -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
      if($last){$ex=Export-PcReportToDrive $last.FullName;Add-LocalPcEvent $ex.Message};$LastDisplay=[datetime]::MinValue
    }
    elseif($k-eq'C' -and $View-eq'settings'){
      Set-Clipboard 'PCCONNECT|v3|state=Terminator364/PC-COMMAND-STATE|code=Terminator364/BuildHub|slot=AUTO|max=10'
      Add-LocalPcEvent 'Code PCCONNECT copie.';$LastDisplay=[datetime]::MinValue
    }
    elseif($k-eq'U'){$LastUpdateCheck=[datetime]::MinValue;Add-LocalPcEvent 'Verification mise a jour demandee.';$LastDisplay=[datetime]::MinValue}
    elseif($View-eq'settings' -and $k-match'^[1-4]$'){
      if($k-eq'1'){$vals=@(5,10,30);$App.SyncSeconds=$vals[($vals.IndexOf($App.SyncSeconds)+1)%3]}
      elseif($k-eq'2'){$vals=@(5,10,30);$App.EngineSeconds=$vals[($vals.IndexOf($App.EngineSeconds)+1)%3]}
      elseif($k-eq'3'){$vals=@(10,20,30);$App.DisplaySeconds=$vals[($vals.IndexOf($App.DisplaySeconds)+1)%3]}
      elseif($k-eq'4'){$App.Mode=if($App.Mode-eq'AUTO'){'ECO'}else{'AUTO'}}
      Save-PcLocalSettings $Paths $App.SyncSeconds $App.EngineSeconds $App.DisplaySeconds $App.Mode
      $LastDisplay=[datetime]::MinValue
    }
    elseif($k-match'^[1-9]$' -and $Sync.Overview){
      $idx=[int]$k-1
      if($View-eq'general' -and $idx-lt@($Sync.Overview.conversations).Count){$ConversationIndex=$idx;$View='conversation';$ForceDetail=$true;$LastSync=[datetime]::MinValue;$LastDisplay=[datetime]::MinValue}
      elseif($View-eq'conversation' -and $Sync.Channel -and $idx-lt@($Sync.Channel.macro_tasks).Count){$MacroIndex=$idx;$View='macro';$LastDisplay=[datetime]::MinValue}
    }
  }
  Start-Sleep -Milliseconds 250
}
