param(
  [int]$Port = 8791
)

$ErrorActionPreference='Stop'
$LabRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
$Server=Join-Path $LabRoot 'server.mjs'
$PcRoot=Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$Url='http://127.0.0.1:'+$Port

if(-not(Test-Path -LiteralPath $Server)){throw "WEB LAB server absent: $Server"}
$node=(Get-Command node.exe -ErrorAction SilentlyContinue)
if(-not$node){throw 'Node.js est requis pour PC COMMAND WEB LAB.'}

$listener=Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue|Select-Object -First 1
if($listener){
  $owner=[int]$listener.OwningProcess
  $proc=Get-CimInstance Win32_Process -Filter ('ProcessId='+$owner) -ErrorAction SilentlyContinue
  if(-not$proc -or [string]$proc.CommandLine -notmatch 'PC_COMMAND-WEB-LAB|pc-command\\web-lab|web-lab\\server\.mjs'){
    throw "Le port $Port est déjà utilisé par un autre processus (PID $owner)."
  }
}else{
  $env:PC_COMMAND_ROOT=$PcRoot
  $env:PC_COMMAND_WEB_PORT=[string]$Port
  $env:PC_COMMAND_WEB_IDLE_MS='120000'
  $log=Join-Path $LabRoot 'web-lab.log'
  Start-Process -FilePath $node.Source -ArgumentList @($Server) -WorkingDirectory $LabRoot -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError (Join-Path $LabRoot 'web-lab-error.log')
  $ready=$false
  for($i=0;$i-lt25;$i++){
    Start-Sleep -Milliseconds 200
    try{
      $ping=Invoke-RestMethod -Uri ($Url+'/api/ping') -TimeoutSec 1
      if($ping.ok){$ready=$true;break}
    }catch{}
  }
  if(-not$ready){throw 'Le serveur WEB LAB n’a pas répondu dans le délai prévu.'}
}

Start-Process $Url
