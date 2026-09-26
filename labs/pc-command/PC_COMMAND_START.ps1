$ErrorActionPreference='SilentlyContinue'
$stateDir=Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$viewer=Join-Path $stateDir 'PC_COMMAND_STATUS_V2.ps1'
$stdout=Join-Path $stateDir 'remote.stdout.log'
$stderr=Join-Path $stateDir 'remote.stderr.log'
New-Item -ItemType Directory -Force -Path $stateDir|Out-Null

$dc=Get-CimInstance Win32_Process|Where-Object{$_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander.*remote'}|Select-Object -First 1
if(-not $dc){
  $npx=(Get-Command npx.cmd -ErrorAction SilentlyContinue).Source
  if($npx){
    Start-Process -FilePath $npx -ArgumentList @('--yes','@wonderwhy-er/desktop-commander@latest','remote') -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden
    $limit=(Get-Date).AddSeconds(20)
    do{
      Start-Sleep 1
      $dc=Get-CimInstance Win32_Process|Where-Object{$_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander.*remote'}|Select-Object -First 1
    }until($dc -or (Get-Date)-gt $limit)
  }
}
if(Test-Path $viewer){
  Start-Process powershell.exe -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$viewer+'"'))
}
