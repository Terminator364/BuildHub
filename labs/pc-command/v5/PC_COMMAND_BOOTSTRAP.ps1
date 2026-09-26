$ErrorActionPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$AppDir=Join-Path $Root 'app'
$Stage=Join-Path $Root 'staging'
$Backup=Join-Path $Root 'backup'
$Base='https://raw.githubusercontent.com/Terminator364/BuildHub/lab/pc-command-browser-20260926/labs/pc-command/v5'
New-Item -ItemType Directory -Force -Path $AppDir,$Stage,$Backup|Out-Null

function Get-LocalVersion {
  $m=Join-Path $AppDir 'manifest.json'
  if(Test-Path $m){try{return [version]((Get-Content $m -Raw|ConvertFrom-Json).version)}catch{}}
  return [version]'0.0.0'
}

$remote=$null
try{
  $nonce=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $remote=(Invoke-WebRequest ($Base+"/manifest.json?n=$nonce") -TimeoutSec 4 -UseBasicParsing -Headers @{'Cache-Control'='no-cache'}).Content|ConvertFrom-Json
}catch{}

$localVersion=Get-LocalVersion
$mustInstall= -not(Test-Path (Join-Path $AppDir 'PC_COMMAND_V5.ps1'))
$upgrade=$false
if($remote){try{$upgrade=([version]$remote.version -gt $localVersion)}catch{}}

if(($mustInstall -or $upgrade) -and $remote){
  $st=Join-Path $Stage ([string]$remote.version)
  if(Test-Path $st){Remove-Item $st -Recurse -Force}
  New-Item -ItemType Directory -Force -Path $st|Out-Null
  $ok=$true
  $git=(Get-Command git.exe -ErrorAction SilentlyContinue).Source
  foreach($f in @($remote.files)){
    $dest=Join-Path $st ([string]$f.relative_path)
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent)|Out-Null
    try{
      Invoke-WebRequest ($Base+'/'+$f.relative_path+'?v='+$remote.version+'&n='+[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -OutFile $dest -TimeoutSec 8 -UseBasicParsing -Headers @{'Cache-Control'='no-cache'}
      if($git -and $f.git_blob_sha){
        $actual=(& $git hash-object $dest).Trim()
        if($actual-ne[string]$f.git_blob_sha){$ok=$false;break}
      }
      if($dest -like '*.ps1'){
        $tok=$null;$err=$null
        [void][Management.Automation.Language.Parser]::ParseFile($dest,[ref]$tok,[ref]$err)
        if($err.Count){$ok=$false;break}
      }
    }catch{$ok=$false;break}
  }

  if($ok -and (Test-Path (Join-Path $st 'PC_COMMAND_V5.ps1'))){
    $backupDir=Join-Path $Backup ('app-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
    if(Get-ChildItem $AppDir -Force -ErrorAction SilentlyContinue){Copy-Item $AppDir $backupDir -Recurse -Force -ErrorAction SilentlyContinue}
    Remove-Item (Join-Path $AppDir '*') -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $st '*') $AppDir -Recurse -Force
    ($remote|ConvertTo-Json -Depth 12)|Set-Content (Join-Path $AppDir 'manifest.json') -Encoding UTF8
  }
}

$main=Join-Path $AppDir 'PC_COMMAND_V5.ps1'
if(-not(Test-Path $main)){
  Write-Host 'PC COMMAND : aucune version locale valide.' -ForegroundColor Red
  Write-Host 'Connecte Internet puis relance le raccourci.' -ForegroundColor Yellow
  Read-Host 'Entree pour fermer'|Out-Null
  exit 2
}

Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',$main,'-Root',$Root
exit 0
