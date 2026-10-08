param()
$ErrorActionPreference='Stop'
$lab=Join-Path $PSScriptRoot '..\pc-command\web-lab'
$launcher=Join-Path $lab 'PC_COMMAND_WEB_LAB.ps1'
$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$listener.Start()
$port=($listener.LocalEndpoint).Port
$listener.Stop()
$tmp=Join-Path $env:TEMP ('pc-web-lab-ci-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tmp|Out-Null
$serverPid=0
try{
  & $launcher -Port $port -PcRoot $tmp -NoBrowser|Out-Null
  $first=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$port+'/api/ping') -TimeoutSec 2
  if($first.service -ne 'pc-command-web-lab' -or $first.version -ne '0.2.8'){throw 'Bad readiness identity/version'}
  $serverPid=[int]$first.serverPid
  & $launcher -Port $port -PcRoot $tmp -NoBrowser|Out-Null
  $second=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$port+'/api/ping') -TimeoutSec 2
  if([int]$second.serverPid -ne $serverPid){throw 'Second launch duplicated or replaced server'}
  $running=Get-Process -Id $serverPid -ErrorAction Stop
  if($running.ProcessName -ne 'node'){throw 'Incorrect server executable'}
  $invalidPath=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$port+'/api/status') -TimeoutSec 2
  if($invalidPath.lab.version -ne '0.2.8'){throw 'Status version drift'}
  Write-Host 'PC_COMMAND_WEB_LAB_028_LAUNCHER_SINGLE_INSTANCE_OK'
}finally{
  if($serverPid -gt 0){
    $owned=Get-CimInstance Win32_Process -Filter ('ProcessId='+$serverPid) -ErrorAction SilentlyContinue
    if($owned -and $owned.Name -eq 'node.exe' -and
       ([string]$owned.CommandLine).IndexOf('pc-command'+[IO.Path]::DirectorySeparatorChar+'web-lab'+[IO.Path]::DirectorySeparatorChar+'server.mjs',[StringComparison]::OrdinalIgnoreCase) -ge 0){
      Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
    }
  }
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
