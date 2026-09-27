param([int]$Port = 8791)

$ErrorActionPreference='Stop'
$LabRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
$Server=Join-Path $LabRoot 'server.mjs'
$PcRoot=Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$Url='http://127.0.0.1:'+$Port

if(-not(Test-Path -LiteralPath $Server)){throw "WEB LAB server absent: $Server"}
$node=(Get-Command node.exe -ErrorAction SilentlyContinue)
if(-not$node){throw 'Node.js est requis pour PC COMMAND WEB LAB.'}

function Test-WebLabReady {
  try{
    $ping=Invoke-RestMethod -Uri ($Url+'/api/ping') -TimeoutSec 1
    return [bool]$ping.ok
  }catch{return $false}
}

$ready=Test-WebLabReady
if(-not$ready){
  $env:PC_COMMAND_ROOT=$PcRoot
  $env:PC_COMMAND_WEB_PORT=[string]$Port
  $env:PC_COMMAND_WEB_IDLE_MS='300000'
  $log=Join-Path $LabRoot 'web-lab.log'
  $err=Join-Path $LabRoot 'web-lab-error.log'
  Start-Process -FilePath $node.Source -ArgumentList @($Server) -WorkingDirectory $LabRoot -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError $err
  for($i=0;$i-lt60;$i++){
    Start-Sleep -Milliseconds 250
    if(Test-WebLabReady){$ready=$true;break}
  }
}

if(-not$ready){
  $detail=''
  $errFile=Join-Path $LabRoot 'web-lab-error.log'
  if(Test-Path $errFile){$detail=(Get-Content $errFile -Raw -ErrorAction SilentlyContinue)}
  throw ('Le serveur WEB LAB n’a pas répondu sur '+$Url+'. '+$detail)
}

$edgeCandidates=@(
  (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
  (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
$edge=$edgeCandidates|Select-Object -First 1
if($edge){
  Start-Process -FilePath $edge -ArgumentList @('--app='+$Url,'--start-maximized')
}else{
  Start-Process $Url
}
