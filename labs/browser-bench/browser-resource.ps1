param([Parameter(Mandatory=$true)][string]$Browser)
$ErrorActionPreference = 'Stop'

function Find-Exe([string[]]$patterns) {
  foreach ($p in $patterns) {
    $item = Get-Item $p -ErrorAction SilentlyContinue
    if ($item) { return $item.FullName }
  }
  return $null
}

function Install-Browser([string]$name) {
  switch ($name) {
    'edge' { return (Find-Exe @('C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe','C:\Program Files\Microsoft\Edge\Application\msedge.exe')) }
    'firefox' {
      choco install firefox -y --no-progress | Out-Null
      return (Find-Exe @('C:\Program Files\Mozilla Firefox\firefox.exe'))
    }
    'brave' {
      choco install brave -y --no-progress | Out-Null
      return (Find-Exe @('C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe',(Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe')))
    }
    'qutebrowser' {
      choco install qutebrowser -y --no-progress | Out-Null
      return (Get-ChildItem 'C:\Program Files' -Filter 'qutebrowser.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName)
    }
    'falkon' {
      choco install falkon -y --no-progress | Out-Null
      return (Get-ChildItem 'C:\Program Files' -Filter 'falkon.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName)
    }
    'helium' {
      $rel = Invoke-RestMethod 'https://api.github.com/repos/imputnet/helium-windows/releases/latest'
      $asset = $rel.assets | Where-Object { $_.name -match 'x64-windows\.zip$' } | Select-Object -First 1
      if (-not $asset) { throw 'No Helium x64 portable asset' }
      $zip = Join-Path $env:TEMP $asset.name
      $dir = Join-Path $env:TEMP 'helium-resource'
      Invoke-WebRequest $asset.browser_download_url -OutFile $zip
      Expand-Archive $zip -DestinationPath $dir -Force
      $exe = Get-ChildItem $dir -Filter 'chrome.exe' -Recurse | Select-Object -First 1 -ExpandProperty FullName
      if (-not $exe) { $exe = Get-ChildItem $dir -Filter '*.exe' -Recurse | Where-Object { $_.Name -match 'helium' } | Select-Object -First 1 -ExpandProperty FullName }
      return $exe
    }
  }
  throw "Unknown browser $name"
}

function Get-Descendants([int]$rootPid) {
  $all = Get-CimInstance Win32_Process
  $ids = New-Object System.Collections.Generic.List[int]
  $ids.Add($rootPid)
  $changed = $true
  while ($changed) {
    $changed = $false
    foreach ($p in $all) {
      if ($ids.Contains([int]$p.ParentProcessId) -and -not $ids.Contains([int]$p.ProcessId)) {
        $ids.Add([int]$p.ProcessId)
        $changed = $true
      }
    }
  }
  return @($ids)
}

$exe = Install-Browser $Browser
if (-not $exe -or -not (Test-Path $exe)) { throw "Executable not found: $Browser" }

$profile = Join-Path $env:TEMP ("browser4g-" + $Browser + "-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $profile -Force | Out-Null
$url = 'https://example.com/'
$sw = [Diagnostics.Stopwatch]::StartNew()

switch ($Browser) {
  'firefox' { $p = Start-Process $exe -ArgumentList @('-no-remote','-profile',$profile,'-new-window',$url) -PassThru }
  'falkon' { $p = Start-Process $exe -ArgumentList @('-p',$profile,$url) -PassThru }
  'qutebrowser' { $p = Start-Process $exe -ArgumentList @('--basedir',$profile,$url) -PassThru }
  default { $p = Start-Process $exe -ArgumentList @("--user-data-dir=$profile",'--no-first-run','--disable-extensions',$url) -PassThru }
}
Start-Sleep -Seconds 15
$sw.Stop()

$ids = @(Get-Descendants $p.Id)
$procs = Get-Process -Id $ids -ErrorAction SilentlyContinue
$ram = ($procs | Measure-Object WorkingSet64 -Sum).Sum
$private = ($procs | Measure-Object PrivateMemorySize64 -Sum).Sum
$cpu = ($procs | Measure-Object CPU -Sum).Sum

$result = [ordered]@{
  browser = $Browser
  launch_ms = [math]::Round($sw.Elapsed.TotalMilliseconds,0)
  process_count = @($procs).Count
  working_set_mb = [math]::Round($ram/1MB,1)
  private_mb = [math]::Round($private/1MB,1)
  cpu_seconds = [math]::Round($cpu,2)
  page = $url
  runner = 'windows-latest'
  note = 'Relative prefilter only; final RAM decision must be measured on target Lenovo.'
}
Write-Host ('BROWSER4G_RESULT=' + ($result | ConvertTo-Json -Compress))

foreach ($proc in $procs) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
