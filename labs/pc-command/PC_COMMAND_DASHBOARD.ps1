Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'SilentlyContinue'
$stateDir = Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$rawLog = Join-Path $stateDir 'remote.stdout.log'
$activityLog = Join-Path $stateDir 'activity.log'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

function Convert-ToHumanActivity([string]$line) {
  if ($line -match 'Received tool call.*?:\s*start_process') { return 'Commande locale lancee' }
  if ($line -match 'Received tool call.*?:\s*write_file') { return 'Fichier cree ou modifie' }
  if ($line -match 'Received tool call.*?:\s*read_file') { return 'Lecture d un fichier local' }
  if ($line -match 'Received tool call.*?:\s*list_processes') { return 'Inspection des processus' }
  if ($line -match 'Received tool call.*?:\s*kill_process') { return 'Arret d un processus' }
  if ($line -match 'Received tool call.*?:\s*list_directory') { return 'Inspection d un dossier' }
  if ($line -match 'Received tool call.*?:\s*start_search') { return 'Recherche locale' }
  if ($line -match 'Tool call .* completed') { return 'Action terminee avec succes' }
  if ($line -match 'Tool call .* failed|error|ERROR') { return 'Erreur detectee' }
  return $null
}

function Get-HumanActivities {
  $items = New-Object System.Collections.Generic.List[string]
  if (Test-Path $rawLog) {
    foreach ($line in (Get-Content $rawLog -Tail 120)) {
      $h = Convert-ToHumanActivity $line
      if ($h) { $items.Add($h) }
    }
  }
  if (Test-Path $activityLog) {
    foreach ($line in (Get-Content $activityLog -Tail 12)) { $items.Add($line) }
  }
  return @($items | Select-Object -Last 12)
}

$form = New-Object Windows.Forms.Form
$form.Text = 'PC COMMAND'
$form.Width = 650
$form.Height = 470
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$title = New-Object Windows.Forms.Label
$title.Text = 'PC COMMAND — Centre de controle'
$title.Font = New-Object Drawing.Font('Segoe UI',16,[Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object Drawing.Point(18,16)
$form.Controls.Add($title)

$status = New-Object Windows.Forms.Label
$status.Font = New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold)
$status.AutoSize = $true
$status.Location = New-Object Drawing.Point(20,58)
$form.Controls.Add($status)

$resource = New-Object Windows.Forms.Label
$resource.Font = New-Object Drawing.Font('Segoe UI',9)
$resource.AutoSize = $true
$resource.Location = New-Object Drawing.Point(20,88)
$form.Controls.Add($resource)

$current = New-Object Windows.Forms.Label
$current.Font = New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
$current.AutoSize = $true
$current.Location = New-Object Drawing.Point(20,118)
$form.Controls.Add($current)

$box = New-Object Windows.Forms.TextBox
$box.Multiline = $true
$box.ReadOnly = $true
$box.ScrollBars = 'Vertical'
$box.Font = New-Object Drawing.Font('Segoe UI',9)
$box.Location = New-Object Drawing.Point(20,150)
$box.Size = New-Object Drawing.Size(595,210)
$form.Controls.Add($box)

$refresh = New-Object Windows.Forms.Button
$refresh.Text = 'Actualiser'
$refresh.Location = New-Object Drawing.Point(20,378)
$refresh.Size = New-Object Drawing.Size(100,32)
$form.Controls.Add($refresh)

$openLog = New-Object Windows.Forms.Button
$openLog.Text = 'Journal brut'
$openLog.Location = New-Object Drawing.Point(132,378)
$openLog.Size = New-Object Drawing.Size(110,32)
$form.Controls.Add($openLog)

$hide = New-Object Windows.Forms.Button
$hide.Text = 'Fermer affichage'
$hide.Location = New-Object Drawing.Point(475,378)
$hide.Size = New-Object Drawing.Size(140,32)
$form.Controls.Add($hide)

function Update-Dashboard {
  $dc = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander.*remote'
  } | Select-Object -First 1

  if ($dc) {
    $p = Get-Process -Id $dc.ProcessId
    $status.Text = "● CONNECTE — PID $($dc.ProcessId)"
    $status.ForeColor = [Drawing.Color]::ForestGreen
    $dcRam = [math]::Round($p.WorkingSet64 / 1MB, 1)
  } else {
    $status.Text = '● DECONNECTE'
    $status.ForeColor = [Drawing.Color]::Firebrick
    $dcRam = 0
  }

  $os = Get-CimInstance Win32_OperatingSystem
  $freeMb = [math]::Round($os.FreePhysicalMemory / 1024, 0)
  $resource.Text = "RAM libre: $freeMb MB    |    PC Command: $dcRam MB"

  $activities = @(Get-HumanActivities)
  if ($activities.Count -gt 0) {
    $current.Text = 'Action recente : ' + $activities[-1]
    $box.Text = (($activities | ForEach-Object { '• ' + $_ }) -join [Environment]::NewLine)
  } else {
    $current.Text = 'Action recente : en attente'
    $box.Text = 'Aucune activite recente.'
  }
}

$refresh.Add_Click({ Update-Dashboard })
$openLog.Add_Click({
  if (Test-Path $rawLog) { Start-Process notepad.exe -ArgumentList $rawLog }
})
$hide.Add_Click({ $form.Close() })

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Update-Dashboard })
$timer.Start()
Update-Dashboard
[void]$form.ShowDialog()
