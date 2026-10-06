$Host.UI.RawUI.WindowTitle = 'PC COMMAND - SUIVI'
$ErrorActionPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$statusUrl = 'https://raw.githubusercontent.com/Terminator364/BuildHub/lab/pc-command-browser-20260926/labs/pc-command/status.json'
$cache = Join-Path $env:LOCALAPPDATA 'PC_COMMAND\status-cache.json'
New-Item -ItemType Directory -Force -Path (Split-Path $cache -Parent) | Out-Null

function Get-Status {
  try {
    $s = Invoke-RestMethod -Uri $statusUrl -TimeoutSec 5
    ($s | ConvertTo-Json -Depth 6) | Set-Content -Path $cache -Encoding UTF8
    return $s
  } catch {
    if (Test-Path $cache) { return (Get-Content $cache -Raw | ConvertFrom-Json) }
    return $null
  }
}

while ($true) {
  Clear-Host
  $dc = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander.*remote'
  } | Select-Object -First 1
  $os = Get-CimInstance Win32_OperatingSystem
  $free = [math]::Round($os.FreePhysicalMemory / 1024, 0)
  $s = Get-Status

  Write-Host '===============================================' -ForegroundColor Cyan
  Write-Host ' PC COMMAND - SUIVI DU TRAVAIL' -ForegroundColor Cyan
  Write-Host '===============================================' -ForegroundColor Cyan
  Write-Host ''

  if ($dc) {
    Write-Host 'Connexion PC : CONNECTEE' -ForegroundColor Green
  } else {
    Write-Host 'Connexion PC : DECONNECTEE' -ForegroundColor Red
  }
  Write-Host ('RAM libre     : ' + $free + ' MB') -ForegroundColor Yellow
  Write-Host ''

  if ($s) {
    Write-Host ('ETAPE          : ' + $s.stage)
    Write-Host ''
    Write-Host ('EN COURS       : ' + $s.current_action) -ForegroundColor White
    Write-Host ('DERNIER SUCCES : ' + $s.last_success) -ForegroundColor Green
    Write-Host ('PROCHAINE ETAPE: ' + $s.next_step)
    if ($s.blocker) {
      Write-Host ('BLOCAGE        : ' + $s.blocker) -ForegroundColor Red
    } else {
      Write-Host 'BLOCAGE        : aucun' -ForegroundColor Green
    }
  } else {
    Write-Host 'Statut GitHub indisponible. Nouvelle tentative dans 2 minutes.' -ForegroundColor Yellow
  }

  Write-Host ''
  Write-Host ('Derniere actualisation : ' + (Get-Date -Format 'HH:mm:ss'))
  Write-Host 'Actualisation automatique toutes les 2 minutes.'
  Write-Host 'Ferme simplement cette fenetre pour arreter le suivi.' -ForegroundColor DarkGray
  Start-Sleep -Seconds 120
}
