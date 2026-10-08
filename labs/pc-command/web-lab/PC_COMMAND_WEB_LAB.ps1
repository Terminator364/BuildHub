param(
  [ValidateRange(1024,65535)][int]$Port=8791,
  [string]$PcRoot=(Join-Path $env:LOCALAPPDATA 'PC_COMMAND'),
  [switch]$NoBrowser
)
$ErrorActionPreference='Stop'
$LabRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
$Server=Join-Path $LabRoot 'server.mjs'
$Url='http://127.0.0.1:'+$Port
$ExpectedVersion='0.2.8'
$ExpectedService='pc-command-web-lab'
if(-not(Test-Path -LiteralPath $Server)){throw "Web Lab server absent: $Server"}
$node=Get-Command node.exe -ErrorAction Stop
$lockName='Local\PC_COMMAND_WEB_LAB_'+$Port
$mutex=[System.Threading.Mutex]::new($false,$lockName)
$locked=$false
try{
  try{$locked=$mutex.WaitOne(15000)}catch [System.Threading.AbandonedMutexException]{$locked=$true}
  if(-not$locked){throw 'Web Lab launcher is busy; retry after 15 seconds'}

  function Get-LabPing {
    try{return Invoke-RestMethod -Uri ($Url+'/api/ping') -TimeoutSec 1 -ErrorAction Stop}
    catch{return $null}
  }
  function Assert-LabIdentity($ping) {
    if(-not$ping){return}
    if($ping.service -ne $ExpectedService -or -not[bool]$ping.ok){
      throw ('Port '+$Port+' is used by a different or unverifiable service; refusing to launch')
    }
  }
  $ping=Get-LabPing
  Assert-LabIdentity $ping
  if($ping -and $ping.version -ne $ExpectedVersion){
    $serverOwner=[int]$ping.serverPid
    if($serverOwner -le 0){throw 'Old Web Lab has no verifiable PID'}
    $proc=Get-CimInstance Win32_Process -Filter ('ProcessId='+$serverOwner) -ErrorAction Stop
    if(-not$proc -or $proc.Name -ne 'node.exe' -or
       ([string]$proc.CommandLine).IndexOf($Server,[StringComparison]::OrdinalIgnoreCase) -lt 0){
      throw 'Old Web Lab PID/path ownership unverified; refusing to stop a process'
    }
    Stop-Process -Id $serverOwner -ErrorAction Stop
    $ping=$null
    for($k=0;$k-lt20;$k++){
      Start-Sleep -Milliseconds 150
      $attempt=Get-LabPing
      if(-not$attempt){break}
      Assert-LabIdentity $attempt
    }
  }
  if(-not$ping){
    $env:PC_COMMAND_ROOT=$PcRoot
    $env:PC_COMMAND_WEB_PORT=[string]$Port
    $env:PC_COMMAND_WEB_IDLE_MS='300000'
    $log=Join-Path $LabRoot 'web-lab.log'
    $err=Join-Path $LabRoot 'web-lab-error.log'
    Start-Process -FilePath $node.Source -ArgumentList @($Server) -WorkingDirectory $LabRoot -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError $err | Out-Null
    for($i=0;$i-lt60;$i++){
      Start-Sleep -Milliseconds 250
      $ping=Get-LabPing
      if($ping){Assert-LabIdentity $ping;if($ping.version -eq $ExpectedVersion){break}}
    }
  }
  Assert-LabIdentity $ping
  if(-not$ping -or $ping.version -ne $ExpectedVersion){
    throw ('Web Lab '+$ExpectedVersion+' failed readiness on '+$Url)
  }
  if($NoBrowser){Write-Output ('WEB_LAB_READY pid='+$ping.serverPid+' version='+$ping.version);return}

  # An existing Edge application window must be reused, not duplicated.
  $existing=@(Get-Process msedge -ErrorAction SilentlyContinue | Where-Object {
    $_.MainWindowTitle -match '(?i)PC COMMAND.*Web Lab'
  })
  if($existing.Count -gt 0){
    try{
      $shell=New-Object -ComObject WScript.Shell
      [void]$shell.AppActivate([int]$existing[0].Id)
    }catch{}
    return
  }
  $edgeCandidates=@(
    "$env:SystemDrive\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "$env:SystemDrive\Program Files\Microsoft\Edge\Application\msedge.exe",
    "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe"
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
  $edge=$edgeCandidates|Select-Object -First 1
  if($edge){
    $edgeProfile=Join-Path $LabRoot 'edge-profile'
    New-Item -ItemType Directory -Force -Path $edgeProfile | Out-Null
    $edgeArgs=@(
      ('--user-data-dir=' + $edgeProfile),
      ('--app=' + $Url),
      '--start-maximized',
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-background-mode'
    )
    Start-Process -FilePath $edge -ArgumentList $edgeArgs
  }else{Start-Process $Url}
  # Retain mutex briefly while the application window materializes.
  for($i=0;$i-lt16;$i++){
    Start-Sleep -Milliseconds 250
    $windows=@(Get-Process msedge -ErrorAction SilentlyContinue | Where-Object {
      $_.MainWindowTitle -match '(?i)PC COMMAND.*Web Lab'
    })
    if($windows.Count -gt 0){break}
  }
}finally{
  if($locked){$mutex.ReleaseMutex()}
  $mutex.Dispose()
}
