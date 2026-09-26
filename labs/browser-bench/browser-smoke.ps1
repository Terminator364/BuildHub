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
    $exe = Find-Exe @('C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe')
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
    $exe = Get-ChildItem $dir -Filter '*.exe' -Recurse | Where-Object { $_.Name -match 'helium|chrome' } | Select-Object -First 1 -ExpandProperty FullName
  }
  default { throw "Unknown browser: $Browser" }
}

if (-not $exe -or -not (Test-Path $exe)) { throw "Executable not found for $Browser" }
Write-Host "BROWSER=$Browser"
Write-Host "EXE=$exe"
try {
  $v = & $exe --version 2>&1 | Select-Object -First 4
  Write-Host "VERSION=$($v -join ' ')"
} catch {
  Write-Host "VERSION_COMMAND_FAILED=$($_.Exception.Message)"
}
Write-Host "SMOKE_OK=$Browser"
