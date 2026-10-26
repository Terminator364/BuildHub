param([Parameter(Mandatory=$true)][string]$Browser)
$ErrorActionPreference='Stop'
$urls=@('https://chatgpt.com/','https://github.com/','https://www.youtube.com/')

function Find-Exe([string[]]$patterns){
  foreach($p in $patterns){$i=Get-Item $p -ErrorAction SilentlyContinue;if($i){return $i.FullName}}
  return $null
}
function Install-Browser([string]$name){
  switch($name){
    'edge'{return Find-Exe @('C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe','C:\Program Files\Microsoft\Edge\Application\msedge.exe')}
    'firefox'{choco install firefox -y --no-progress|Out-Null;return Find-Exe @('C:\Program Files\Mozilla Firefox\firefox.exe')}
    'brave'{choco install brave -y --no-progress|Out-Null;return Find-Exe @('C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe',(Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe'))}
    'qutebrowser'{choco install qutebrowser -y --no-progress|Out-Null;return(Get-ChildItem 'C:\Program Files' -Filter qutebrowser.exe -Recurse -ErrorAction SilentlyContinue|Select-Object -First 1 -ExpandProperty FullName)}
    'falkon'{choco install falkon -y --no-progress|Out-Null;return(Get-ChildItem 'C:\Program Files' -Filter falkon.exe -Recurse -ErrorAction SilentlyContinue|Select-Object -First 1 -ExpandProperty FullName)}
    'helium'{
      $rel=Invoke-RestMethod 'https://api.github.com/repos/imputnet/helium-windows/releases/latest'
      $a=$rel.assets|Where-Object{$_.name-match'x64-windows\.zip$'}|Select-Object -First 1
      if(-not$a){throw'No Helium x64 zip'}
      $zip=Join-Path $env:TEMP $a.name;$dir=Join-Path $env:TEMP 'helium-real'
      Invoke-WebRequest $a.browser_download_url -OutFile $zip;Expand-Archive $zip $dir -Force
      $exe=Get-ChildItem $dir -Filter chrome.exe -Recurse|Select-Object -First 1 -ExpandProperty FullName
      if(-not$exe){$exe=Get-ChildItem $dir -Filter '*.exe' -Recurse|Where-Object{$_.Name-match'helium'}|Select-Object -First 1 -ExpandProperty FullName}
      return $exe
    }
  }
}
function Desc([int]$root){
  $all=Get-CimInstance Win32_Process;$ids=New-Object 'System.Collections.Generic.List[int]';$ids.Add($root)
  $changed=$true
  while($changed){$changed=$false;foreach($x in $all){if($ids.Contains([int]$x.ParentProcessId)-and-not$ids.Contains([int]$x.ProcessId)){$ids.Add([int]$x.ProcessId);$changed=$true}}}
  return @($ids)
}

$exe=Install-Browser $Browser
if(-not$exe){throw"Executable not found: $Browser"}
$profile=Join-Path $env:TEMP ('b4g-real-'+$Browser+'-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $profile -Force|Out-Null
switch($Browser){
  'firefox'{$p=Start-Process $exe -ArgumentList @('-no-remote','-profile',$profile,'-new-window',$urls[0],'-new-tab',$urls[1],'-new-tab',$urls[2]) -PassThru}
  'qutebrowser'{$p=Start-Process $exe -ArgumentList @('--basedir',$profile,$urls[0],$urls[1],$urls[2]) -PassThru}
  'falkon'{$p=Start-Process $exe -ArgumentList @($urls[0],$urls[1],$urls[2]) -PassThru}
  default{$p=Start-Process $exe -ArgumentList @("--user-data-dir=$profile",'--no-first-run','--disable-extensions',$urls[0],$urls[1],$urls[2]) -PassThru}
}
Start-Sleep 30
$ids=@(Desc $p.Id)
$procs=Get-Process -Id $ids -ErrorAction SilentlyContinue
$ram=($procs|Measure-Object WorkingSet64 -Sum).Sum
$private=($procs|Measure-Object PrivateMemorySize64 -Sum).Sum
$cpu=($procs|Measure-Object CPU -Sum).Sum
$result=[ordered]@{
 browser=$Browser;pages=3;process_count=@($procs).Count;
 working_set_mb=[math]::Round($ram/1MB,1);private_mb=[math]::Round($private/1MB,1);
 cpu_seconds=[math]::Round($cpu,2);runner='windows-latest';
 note='Relative compatibility/resource prefilter; final decision requires target Lenovo test.'
}
Write-Host ('BROWSER4G_REALISTIC='+($result|ConvertTo-Json -Compress))
foreach($x in $procs){Stop-Process -Id $x.Id -Force -ErrorAction SilentlyContinue}
