param(
  [Parameter(Mandatory=$true)][string]$Browser
)
$ErrorActionPreference = 'Stop'

function Find-Exe([string[]]$patterns) {
  foreach ($p in $patterns) {
    $item = Get-Item $p -ErrorAction SilentlyContinue
    if ($item) { return $item.FullName }
  }
  return $null
}

function Get-VersionSafe([string]$exe) {
  $out = Join-Path $env:TEMP ('browser-out-' + [guid]::NewGuid().ToString('N') + '.txt')
  $err = Join-Path $env:TEMP ('browser-err-' + [guid]::NewGuid().ToString('N') + '.txt')
  $p = Start-Process -FilePath $exe -ArgumentList '--version' -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
  if (-not $p.WaitForExit(7000)) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    return 'VERSION_TIMEOUT_BUT_EXECUTABLE_LAUNCHED'
  }
  $text = @()
  if (Test-Path $out) { $text += Get-Content $out -ErrorAction SilentlyContinue }
  if (Test-Path $err) { $text += Get-Content $err -ErrorAction SilentlyContinue }
  if (-not $text) { return ('EXIT_' + $p.ExitCode) }
  return (($text | Select-Object -First 4) -join ' ')
}

switch ($Browser) {
  'edge' {
    $exe = Find-Exe @(
      'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
      'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
    )
  }
  'firefox' {
    choco install firefox -y --no-progress
    if ($LASTEXITCODE -ne 0) { throw "Firefox install failed: $LASTEXITCODE" }
    $exe = Find-Exe @('C:\Program Files\Mozilla Firefox\firefox.exe')
  }
  'brave' {
    choco install brave -y --no-progress
    if ($LASTEXITCODE -ne 0) { throw "Brave install failed: $LASTEXITCODE" }
    $exe = Find-Exe @(
      'C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe',
      (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\Application\brave.exe')
    )
  }
  'qutebrowser' {
    choco install qutebrowser -y --no-progress
    if ($LASTEXITCODE -ne 0) { throw "qutebrowser install failed: $LASTEXITCODE" }
    $exe = Get-ChildItem 'C:\Program Files' -Filter 'qutebrowser.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
  }
  'falkon' {
    choco install falkon -y --no-progress
    if ($LASTEXITCODE -ne 0) { throw "Falkon install failed: $LASTEXITCODE" }
    $exe = Get-ChildItem 'C:\Program Files' -Filter 'falkon.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
  }
  'helium' {
    $rel = Invoke-RestMethod 'https://api.github.com/repos/imputnet/helium-windows/releases/latest'
    $asset = $rel.assets | Where-Object { $_.name -match 'x64-windows\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw 'No Helium x64 zip asset found' }
    $zip = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip
    $dir = Join-Path $env:TEMP 'helium-smoke'
    Expand-Archive $zip -DestinationPath $dir -Force
    $exe = Get-ChildItem $dir -Filter 'chrome.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if (-not $exe) {
      $exe = Get-ChildItem $dir -Filter '*.exe' -Recurse | Where-Object { $_.Name -match 'helium' } | Select-Object -First 1 -ExpandProperty FullName
    }
  }
  default { throw "Unknown browser: $Browser" }
}

if (-not $exe -or -not (Test-Path $exe)) { throw "Executable not found for $Browser" }
Write-Host "BROWSER=$Browser"
Write-Host "EXE=$exe"
Write-Host ("VERSION=" + (Get-VersionSafe $exe))
Write-Host "SMOKE_OK=$Browser"
