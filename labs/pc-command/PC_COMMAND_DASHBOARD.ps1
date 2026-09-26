Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

$ErrorActionPreference = 'SilentlyContinue'
$stateDir = Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$rawLog = Join-Path $stateDir 'remote.stdout.log'
$cacheFile = Join-Path $stateDir 'status-cache.json'
$statusUrl = 'https://raw.githubusercontent.com/Terminator364/BuildHub/lab/pc-command-browser-20260926/labs/pc-command/status.json'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(3)

function Get-RemoteStatus {
  try {
    $json = $client.GetStringAsync($statusUrl).GetAwaiter().GetResult()
    $json | Set-Content -Path $cacheFile -Encoding UTF8
    return ($json | ConvertFrom-Json)
  } catch {
    if (Test-Path $cacheFile) {
      return (Get-Content $cacheFile -Raw | ConvertFrom-Json)
    }
    return $null
  }
}

$form = New-Object Windows.Forms.Form
$form.Text = 'PC COMMAND'
$form.Width = 720
$form.Height = 540
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$title = New-Object Windows.Forms.Label
$title.Text = 'PC COMMAND — Centre de controle'
$title.Font = New-Object Drawing.Font('Segoe UI',16,[Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object Drawing.Point(18,16)
$form.Controls.Add($title)

$conn = New-Object Windows.Forms.Label
$conn.Font = New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
$conn.AutoSize = $true
$conn.Location = New-Object Drawing.Point(20,58)
$form.Controls.Add($conn)

$resource = New-Object Windows.Forms.Label
$resource.Font = New-Object Drawing.Font('Segoe UI',9)
$resource.AutoSize = $true
$resource.Location = New-Object Drawing.Point(20,84)
$form.Controls.Add($resource)

$stage = New-Object Windows.Forms.Label
$stage.Font = New-Object Drawing.Font('Segoe UI',9,[Drawing.FontStyle]::Bold)
$stage.AutoSize = $true
$stage.Location = New-Object Drawing.Point(20,112)
$form.Controls.Add($stage)

$current = New-Object Windows.Forms.Label
$current.Font = New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
$current.MaximumSize = New-Object Drawing.Size(665,45)
$current.AutoSize = $true
$current.Location = New-Object Drawing.Point(20,140)
$form.Controls.Add($current)

$last = New-Object Windows.Forms.Label
$last.Font = New-Object Drawing.Font('Segoe UI',9)
$last.MaximumSize = New-Object Drawing.Size(665,40)
$last.AutoSize = $true
$last.Location = New-Object Drawing.Point(20,193)
$form.Controls.Add($last)

$next = New-Object Windows.Forms.Label
$next.Font = New-Object Drawing.Font('Segoe UI',9)
$next.MaximumSize = New-Object Drawing.Size(665,40)
$next.AutoSize = $true
$next.Location = New-Object Drawing.Point(20,235)
$form.Controls.Add($next)

$blocker = New-Object Windows.Forms.Label
$blocker.Font = New-Object Drawing.Font('Segoe UI',9)
$blocker.MaximumSize = New-Object Drawing.Size(665,35)
$blocker.AutoSize = $true
$blocker.Location = New-Object Drawing.Point(20,277)
$form.Controls.Add($blocker)

$box = New-Object Windows.Forms.TextBox
$box.Multiline = $true
$box.ReadOnly = $true
$box.ScrollBars = 'Vertical'
$box.Font = New-Object Drawing.Font('Segoe UI',9)
$box.Location = New-Object Drawing.Point(20,318)
$box.Size = New-Object Drawing.Size(665,120)
$form.Controls.Add($box)

$refresh = New-Object Windows.Forms.Button
$refresh.Text = 'Actualiser'
$refresh.Location = New-Object Drawing.Point(20,455)
$refresh.Size = New-Object Drawing.Size(100,32)
$form.Controls.Add($refresh)

$openLog = New-Object Windows.Forms.Button
$openLog.Text = 'Journal brut'
$openLog.Location = New-Object Drawing.Point(132,455)
$openLog.Size = New-Object Drawing.Size(110,32)
$form.Controls.Add($openLog)

$hide = New-Object Windows.Forms.Button
$hide.Text = 'Fermer affichage'
$hide.Location = New-Object Drawing.Point(545,455)
$hide.Size = New-Object Drawing.Size(140,32)
$form.Controls.Add($hide)

function Update-Dashboard {
  $dc = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander.*remote'
  } | Select-Object -First 1
  if ($dc) {
    $p = Get-Process -Id $dc.ProcessId
    $dcRam = [math]::Round($p.WorkingSet64 / 1MB, 1)
    $conn.Text = "Connexion ChatGPT-PC : CONNECTEE  |  PID $($dc.ProcessId)"
    $conn.ForeColor = [Drawing.Color]::ForestGreen
  } else {
    $dcRam = 0
    $conn.Text = 'Connexion ChatGPT-PC : DECONNECTEE'
    $conn.ForeColor = [Drawing.Color]::Firebrick
  }

  $os = Get-CimInstance Win32_OperatingSystem
  $freeMb = [math]::Round($os.FreePhysicalMemory / 1024, 0)
  $resource.Text = "RAM libre : $freeMb MB    |    Desktop Commander : $dcRam MB"

  $s = Get-RemoteStatus
  if ($s) {
    $stage.Text = 'Etape : ' + $s.stage
    $current.Text = 'EN COURS : ' + $s.current_action
    $last.Text = 'Dernier succes : ' + $s.last_success
    $next.Text = 'Prochaine etape : ' + $s.next_step
    if ($s.blocker) {
      $blocker.Text = 'Blocage : ' + $s.blocker
      $blocker.ForeColor = [Drawing.Color]::Firebrick
    } else {
      $blocker.Text = 'Blocage : aucun'
      $blocker.ForeColor = [Drawing.Color]::ForestGreen
    }
    $box.Text = (($s.recent | ForEach-Object { '• ' + $_ }) -join [Environment]::NewLine)
  } else {
    $stage.Text = 'Etape : hors ligne'
    $current.Text = 'EN COURS : impossible de recuperer le statut GitHub'
    $last.Text = 'Dernier succes : statut local indisponible'
    $next.Text = 'Prochaine etape : reconnexion automatique'
    $blocker.Text = 'Blocage : reseau'
    $box.Text = ''
  }
}

$refresh.Add_Click({ Update-Dashboard })
$openLog.Add_Click({ if (Test-Path $rawLog) { Start-Process notepad.exe -ArgumentList $rawLog } })
$hide.Add_Click({ $form.Close() })

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 15000
$timer.Add_Tick({ Update-Dashboard })
$timer.Start()
Update-Dashboard
[void]$form.ShowDialog()
