$ErrorActionPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$AppDir=Join-Path $Root 'app'
$Stage=Join-Path $Root 'staging'
$Backup=Join-Path $Root 'backup'
New-Item -ItemType Directory -Force -Path $AppDir,$Stage,$Backup|Out-Null

$Base='https://raw.githubusercontent.com/Terminator364/BuildHub/lab/pc-command-browser-20260926/labs/pc-command/v5'
$localVersion=[version]'0.0.0'
$localManifest=Join-Path $AppDir 'manifest.json'
if(Test-Path $localManifest){
  try{$lm=Get-Content $localManifest -Raw|ConvertFrom-Json;$localVersion=[version]$lm.version}catch{}
}

$nonce=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$remote=$null
try{
  $remote=(Invoke-WebRequest ("$Base/manifest.json?pc=$nonce") -TimeoutSec 6 -UseBasicParsing -Headers @{'Cache-Control'='no-cache'}).Content|ConvertFrom-Json
}catch{}

$install=$false
if($remote){
  try{if([version]$remote.version -gt $localVersion){$install=$true}}catch{}
}
if(-not(Test-Path (Join-Path $AppDir 'PC_COMMAND_V5.ps1'))){$install=$true}

if($install -and $remote){
  $st=Join-Path $Stage ([string]$remote.version)
  if(Test-Path $st){Remove-Item $st -Recurse -Force}
  New-Item -ItemType Directory -Force -Path $st|Out-Null
  $ok=$true
  foreach($f in @($remote.files)){
    $dest=Join-Path $st ([string]$f.relative_path)
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent)|Out-Null
    try{
      Invoke-WebRequest ("$Base/"+$f.relative_path+"?pcv="+$remote.version+"&n="+$nonce) -OutFile $dest -TimeoutSec 10 -UseBasicParsing -Headers @{'Cache-Control'='no-cache'}
      $git=(Get-Command git.exe -ErrorAction SilentlyContinue).Source
      if($git -and $f.git_blob_sha){
        $actual=(& $git hash-object $dest).Trim()
        if($actual-ne[string]$f.git_blob_sha){$ok=$false;break}
      }
    }catch{$ok=$false;break}
  }
  if($ok){
    $old=Join-Path $Backup ('app-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
    if(Get-ChildItem $AppDir -Force -ErrorAction SilentlyContinue){
      Copy-Item $AppDir $old -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item (Join-Path $AppDir '*') -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $st '*') $AppDir -Recurse -Force
    ($remote|ConvertTo-Json -Depth 8)|Set-Content $localManifest -Encoding UTF8
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
