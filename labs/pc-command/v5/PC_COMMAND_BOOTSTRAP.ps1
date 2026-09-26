$ErrorActionPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$AppDir=Join-Path $Root 'app'
$Stage=Join-Path $Root 'staging'
$Backup=Join-Path $Root 'backup'
New-Item -ItemType Directory -Force -Path $AppDir,$Stage,$Backup|Out-Null

$Repo='Terminator364/BuildHub'
$Branch='lab/pc-command-v070'
$ManifestPath='labs/pc-command/v5/manifest.json'
$gh=(Get-Command gh.exe -ErrorAction SilentlyContinue).Source

function Get-GhJson([string]$Endpoint){
  if(-not$gh){return $null}
  $raw=& $gh api $Endpoint 2>$null
  if($LASTEXITCODE-ne0){return $null}
  try{return ($raw -join "`n")|ConvertFrom-Json}catch{return $null}
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

$localVersion=[version]'0.0.0'
$localManifest=Join-Path $AppDir 'manifest.json'
if(Test-Path $localManifest){
  try{$lm=Get-Content $localManifest -Raw|ConvertFrom-Json;$localVersion=[version]$lm.version}catch{}
}

$remote=$null
$manifestBytes=Get-GhContentBytes $ManifestPath $Branch
if($manifestBytes){
  try{$remote=[Text.Encoding]::UTF8.GetString($manifestBytes)|ConvertFrom-Json}catch{}
}

$install=$false
if($remote){try{if([version]$remote.version -gt $localVersion){$install=$true}}catch{}}
if(-not(Test-Path (Join-Path $AppDir 'PC_COMMAND_V5.ps1'))){$install=$true}

if($install -and $remote){
  $st=Join-Path $Stage ([string]$remote.version)
  if(Test-Path $st){Remove-Item $st -Recurse -Force}
  New-Item -ItemType Directory -Force -Path $st|Out-Null
  $ok=$true
  foreach($f in @($remote.files)){
    $dest=Join-Path $st ([string]$f.relative_path)
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent)|Out-Null
    $bytes=Get-GhBlobBytes ([string]$f.git_blob_sha)
    if(-not$bytes){$ok=$false;break}
    [IO.File]::WriteAllBytes($dest,$bytes)
    $actual=(& git hash-object $dest 2>$null).Trim()
    if($actual-ne[string]$f.git_blob_sha){$ok=$false;break}
  }
  if($ok){
    $old=Join-Path $Backup ('app-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
    if(Get-ChildItem $AppDir -Force -ErrorAction SilentlyContinue){Copy-Item $AppDir $old -Recurse -Force -ErrorAction SilentlyContinue}
    Remove-Item (Join-Path $AppDir '*') -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $st '*') $AppDir -Recurse -Force
    [IO.File]::WriteAllBytes($localManifest,$manifestBytes)
    Get-ChildItem $Backup -Directory -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -Skip 3|Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  }
}

$main=Join-Path $AppDir 'PC_COMMAND_V5.ps1'
if(-not(Test-Path $main)){
  Write-Host 'PC COMMAND: aucune version locale valide.' -ForegroundColor Red
  Read-Host 'Entree pour fermer'|Out-Null
  exit 2
}
Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$main,'-Root',$Root
exit 0
