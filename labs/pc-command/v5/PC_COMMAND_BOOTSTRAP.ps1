$ErrorActionPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$AppDir=Join-Path $Root 'app'
$StageRoot=Join-Path $Root 'staging'
$BackupRoot=Join-Path $Root 'backup'
$ConfigDir=Join-Path $Root 'config'
$UpdateStatus=Join-Path $ConfigDir 'update-status.json'
$RootBootstrap=Join-Path $Root 'PC_COMMAND_BOOTSTRAP.ps1'
New-Item -ItemType Directory -Force -Path $Root,$StageRoot,$BackupRoot,$ConfigDir|Out-Null

$Repo='Terminator364/BuildHub'
$Branch='pc-command/stable'
$RequiredChannel='stable'
$ManifestPath='labs/pc-command/v5/manifest.json'
$gh=(Get-Command gh.exe -ErrorAction SilentlyContinue).Source

function Write-UpdateStatus {
  param([string]$State,[string]$Version,[string]$Message,[string]$BackupPath=$null)
  $o=[ordered]@{
    schema='pc.command.update.status.v1'
    at=(Get-Date).ToString('o')
    state=$State
    version=$Version
    message=$Message
    backup=$BackupPath
  }
  try{$o|ConvertTo-Json -Depth 5|Set-Content $UpdateStatus -Encoding UTF8}catch{}
}

function Get-GhJson([string]$Endpoint){
  if(-not$gh){return $null}
  $raw=& $gh api $Endpoint 2>$null
  if($LASTEXITCODE-ne0){return $null}
  try{return ($raw -join [Environment]::NewLine)|ConvertFrom-Json}catch{return $null}
}
function Get-GhContentBytes([string]$Path,[string]$Ref){
  $ep='repos/'+$Repo+'/contents/'+$Path+'?ref='+[uri]::EscapeDataString($Ref)
  $j=Get-GhJson $ep
  if(-not$j -or -not$j.content){return $null}
  try{return [Convert]::FromBase64String(([string]$j.content -replace '\s',''))}catch{return $null}
}
function Get-GhBlobBytes([string]$Sha){
  $j=Get-GhJson ('repos/'+$Repo+'/git/blobs/'+$Sha)
  if(-not$j -or -not$j.content){return $null}
  try{return [Convert]::FromBase64String(([string]$j.content -replace '\s',''))}catch{return $null}
}
function Sync-PcRootBootstrap {
  $appBootstrap=Join-Path $AppDir 'PC_COMMAND_BOOTSTRAP.ps1'
  if(Test-Path $appBootstrap){
    try{Copy-Item $appBootstrap $RootBootstrap -Force;return $true}catch{return $false}
  }
  return $false
}
function Test-PcInstalledTree {
  param([string]$Path)
  if([string]::IsNullOrWhiteSpace($Path)){return $false}
  $main=Join-Path $Path 'PC_COMMAND_V5.ps1'
  $manifest=Join-Path $Path 'manifest.json'
  if(-not(Test-Path $main) -or -not(Test-Path $manifest)){return $false}
  try{
    $m=Get-Content $manifest -Raw -Encoding UTF8|ConvertFrom-Json
    [void][version]$m.version
    return $true
  }catch{return $false}
}
function Recover-PcInterruptedSwap {
  if(Test-PcInstalledTree $AppDir){return $false}

  $candidates=New-Object System.Collections.Generic.List[string]
  if(Test-Path $UpdateStatus){
    try{
      $st=Get-Content $UpdateStatus -Raw -Encoding UTF8|ConvertFrom-Json
      if($st.backup -and (Test-Path ([string]$st.backup))){$candidates.Add([string]$st.backup)}
    }catch{}
  }
  foreach($b in @(Get-ChildItem $BackupRoot -Directory -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending)){
    if(-not$candidates.Contains($b.FullName)){$candidates.Add($b.FullName)}
  }

  foreach($candidate in $candidates){
    if(-not(Test-PcInstalledTree $candidate)){continue}
    try{
      if(Test-Path $AppDir){Remove-Item $AppDir -Recurse -Force}
      Move-Item $candidate $AppDir -Force
      [void](Sync-PcRootBootstrap)
      $rv=''
      try{$rv=[string]((Get-Content (Join-Path $AppDir 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json).version)}catch{}
      Write-UpdateStatus 'RECOVERED_PREVIOUS' $rv 'Application precedente restauree avant acces reseau.' $candidate
      return $true
    }catch{
      Write-UpdateStatus 'RECOVERY_REQUIRED' '' ('Restauration locale impossible: '+$_.Exception.Message) $candidate
    }
  }
  return $false
}

[void](Recover-PcInterruptedSwap)
if(-not(Test-Path $AppDir)){New-Item -ItemType Directory -Force -Path $AppDir|Out-Null}

function Start-PcInstalledApp {
  $main=Join-Path $AppDir 'PC_COMMAND_V5.ps1'
  if(Test-Path $main){
    Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$main,'-Root',$Root
    return $true
  }
  return $false
}
function Wait-PcViewerExit {
  param([int]$Seconds=10)
  $deadline=(Get-Date).AddSeconds($Seconds)
  $rootRx=[regex]::Escape($Root)
  do{
    $running=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{
      $_.Name-eq'powershell.exe' -and $_.CommandLine -match'PC_COMMAND_V5\.ps1' -and $_.CommandLine -match $rootRx
    })
    if($running.Count-eq0){return $true}
    Start-Sleep -Milliseconds 250
  }while((Get-Date)-lt$deadline)
  return $false
}

$localVersion=[version]'0.0.0'
$localManifest=Join-Path $AppDir 'manifest.json'
if(Test-Path $localManifest){
  try{$lm=Get-Content $localManifest -Raw -Encoding UTF8|ConvertFrom-Json;$localVersion=[version]$lm.version}catch{}
}

$remote=$null
$manifestBytes=Get-GhContentBytes $ManifestPath $Branch
if($manifestBytes){
  try{$remote=[Text.Encoding]::UTF8.GetString($manifestBytes)|ConvertFrom-Json}catch{}
}
if($remote -and [string]$remote.channel -ne $RequiredChannel){
  Write-UpdateStatus 'REJECTED' ([string]$remote.version) ('Canal manifest refuse: '+[string]$remote.channel+'; attendu: '+$RequiredChannel)
  $remote=$null
}

$install=$false
if($remote){try{if([version]$remote.version -gt $localVersion){$install=$true}}catch{}}
if(-not(Test-Path (Join-Path $AppDir 'PC_COMMAND_V5.ps1'))){$install=$true}

if($install -and $remote){
  $version=[string]$remote.version
  $st=Join-Path $StageRoot $version
  if(Test-Path $st){Remove-Item $st -Recurse -Force}
  New-Item -ItemType Directory -Force -Path $st|Out-Null
  Write-UpdateStatus 'STAGING' $version 'Telechargement et verification des blobs.'
  $ok=$true
  foreach($f in @($remote.files)){
    $dest=Join-Path $st ([string]$f.relative_path)
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent)|Out-Null
    $bytes=Get-GhBlobBytes ([string]$f.git_blob_sha)
    if(-not$bytes){$ok=$false;Write-UpdateStatus 'REJECTED' $version ('Blob absent: '+$f.relative_path);break}
    [IO.File]::WriteAllBytes($dest,$bytes)
    $actual=(& git hash-object $dest 2>$null).Trim()
    if($actual-ne[string]$f.git_blob_sha){
      $ok=$false
      Write-UpdateStatus 'REJECTED' $version ('Hash invalide: '+$f.relative_path)
      break
    }
  }
  if($ok){
    [IO.File]::WriteAllBytes((Join-Path $st 'manifest.json'),$manifestBytes)

    $stageMain=Join-Path $st 'PC_COMMAND_V5.ps1'
    $smoke=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $stageMain -Root $Root -SmokeTest 2>&1
    $smokeText=($smoke -join [Environment]::NewLine)
    if($LASTEXITCODE-ne0 -or $smokeText -notmatch'PC_COMMAND_SMOKE_OK'){
      $ok=$false
      Write-UpdateStatus 'REJECTED' $version 'Pre-swap runtime smoke failed.'
    }
  }

  if($ok){
    Write-UpdateStatus 'READY_TO_SWAP' $version 'Candidate verifie; attente extinction viewer.'
    if(-not(Wait-PcViewerExit 10)){
      Write-UpdateStatus 'DEFERRED' $version 'Viewer encore actif; mise a jour reportee.'
      exit 0
    }

    $rollbackDir=Join-Path $BackupRoot ('app-'+$localVersion.ToString()+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
    $hadCurrent=(Test-Path (Join-Path $AppDir 'PC_COMMAND_V5.ps1'))
    try{
      if($hadCurrent){
        if(Test-Path $rollbackDir){Remove-Item $rollbackDir -Recurse -Force}
        Move-Item $AppDir $rollbackDir -Force
      }
      Move-Item $st $AppDir -Force
      # The Desktop shortcut launches the bootstrap stored at PC_COMMAND root,
      # not the copy inside app. Keep that launcher synchronized with the
      # newly installed release so future updates use the newest safety logic.
      [void](Sync-PcRootBootstrap)
      Write-UpdateStatus 'SWAPPED' $version 'Nouvelle version installee; bootstrap racine synchronise; verification post-launch.' $rollbackDir
    }catch{
      if(-not(Test-Path $AppDir) -and $hadCurrent -and (Test-Path $rollbackDir)){Move-Item $rollbackDir $AppDir -Force}
      [void](Sync-PcRootBootstrap)
      Write-UpdateStatus 'ROLLED_BACK' $version ('Echec swap: '+$_.Exception.Message) $rollbackDir
      [void](Start-PcInstalledApp)
      exit 3
    }

    [void](Start-PcInstalledApp)
    Start-Sleep -Seconds 4
    $rootRx=[regex]::Escape($Root)
    $newAlive=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object{
      $_.Name-eq'powershell.exe' -and $_.CommandLine -match'PC_COMMAND_V5\.ps1' -and $_.CommandLine -match $rootRx
    }).Count -gt 0
    $postVersion=''
    try{$postVersion=[string]((Get-Content (Join-Path $AppDir 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json).version)}catch{}
    $postOk=($newAlive -and $postVersion-eq$version)

    if($postOk){
      Write-UpdateStatus 'SUCCESS' $version 'Pre-smoke, swap et post-launch valides.' $rollbackDir
      Get-ChildItem $BackupRoot -Directory -ErrorAction SilentlyContinue|
        Sort-Object LastWriteTime -Descending|Select-Object -Skip 3|
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
      exit 0
    }

    try{
      if(Test-Path $AppDir){Remove-Item $AppDir -Recurse -Force}
      if($hadCurrent -and (Test-Path $rollbackDir)){Move-Item $rollbackDir $AppDir -Force}
      [void](Sync-PcRootBootstrap)
      Write-UpdateStatus 'ROLLED_BACK' $version ('Post-launch invalide; viewer='+$newAlive+'; version='+$postVersion+'; rollback automatique.') $rollbackDir
      [void](Start-PcInstalledApp)
      exit 4
    }catch{
      Write-UpdateStatus 'RECOVERY_REQUIRED' $version ('Rollback impossible: '+$_.Exception.Message) $rollbackDir
      exit 5
    }
  }
}

# Self-heal launcher drift even when there is no application update.
$appBootstrap=Join-Path $AppDir 'PC_COMMAND_BOOTSTRAP.ps1'
if(Test-Path $appBootstrap){
  try{
    $appHash=(& git hash-object $appBootstrap 2>$null).Trim()
    $rootHash=if(Test-Path $RootBootstrap){(& git hash-object $RootBootstrap 2>$null).Trim()}else{''}
    if($appHash -and $appHash-ne$rootHash){[void](Sync-PcRootBootstrap)}
  }catch{}
}

if(-not(Test-Path (Join-Path $AppDir 'PC_COMMAND_V5.ps1'))){
  Write-Host 'PC COMMAND: aucune version locale valide.' -ForegroundColor Red
  Read-Host 'Entree pour fermer'|Out-Null
  exit 2
}
[void](Start-PcInstalledApp)
exit 0
