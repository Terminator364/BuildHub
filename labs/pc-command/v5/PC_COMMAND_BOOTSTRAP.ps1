$ErrorActionPreference='SilentlyContinue'
$Root=Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$AppDir=Join-Path $Root 'app';$Stage=Join-Path $Root 'staging';$Backup=Join-Path $Root 'backup'
New-Item -ItemType Directory -Force -Path $AppDir,$Stage,$Backup|Out-Null
$Base='https://raw.githubusercontent.com/Terminator364/BuildHub/lab/pc-command-browser-20260926/labs/pc-command/v5'
$manifest=$null
try{$manifest=(Invoke-WebRequest "$Base/manifest.json" -TimeoutSec 6 -UseBasicParsing).Content|ConvertFrom-Json}catch{}
if($manifest){
  $st=Join-Path $Stage ([string]$manifest.version)
  if(Test-Path $st){Remove-Item $st -Recurse -Force}
  New-Item -ItemType Directory -Force -Path $st|Out-Null
  $ok=$true
  foreach($f in @($manifest.files)){
    $dest=Join-Path $st ([string]$f.relative_path)
    New-Item -ItemType Directory -Force -Path (Split-Path $dest -Parent)|Out-Null
    try{
      Invoke-WebRequest ("$Base/"+$f.relative_path) -OutFile $dest -TimeoutSec 10 -UseBasicParsing
      $git=(Get-Command git.exe -ErrorAction SilentlyContinue).Source
      if($git -and $f.git_blob_sha){$actual=(& $git hash-object $dest).Trim();if($actual-ne[string]$f.git_blob_sha){$ok=$false;break}}
    }catch{$ok=$false;break}
  }
  if($ok){
    $old=Join-Path $Backup ('app-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
    if(Test-Path $AppDir -and (Get-ChildItem $AppDir -Force -ErrorAction SilentlyContinue)){Copy-Item $AppDir $old -Recurse -Force -ErrorAction SilentlyContinue}
    Remove-Item (Join-Path $AppDir '*') -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $st '*') $AppDir -Recurse -Force
    ($manifest|ConvertTo-Json -Depth 8)|Set-Content (Join-Path $AppDir 'manifest.json') -Encoding UTF8
  }
}
$main=Join-Path $AppDir 'PC_COMMAND_V5.ps1'
if(-not(Test-Path $main)){Write-Host 'PC COMMAND: aucune version locale valide.' -ForegroundColor Red;Read-Host 'Entree pour fermer'|Out-Null;exit 2}
$me=$PID
Get-CimInstance Win32_Process|Where-Object{$_.ProcessId-ne$me -and $_.Name-eq'powershell.exe' -and $_.CommandLine-match'PC_COMMAND_V[0-9]+\.ps1'}|ForEach-Object{Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $main -Root $Root
