Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'SilentlyContinue'
$stateDir = Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$logPath = Join-Path $stateDir 'activity.log'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

$form = New-Object Windows.Forms.Form
$form.Text = 'PC COMMAND'
$form.Width = 640
$form.Height = 430
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

$actionLabel = New-Object Windows.Forms.Label
$actionLabel.Text = 'Activite recente'
$actionLabel.Font = New-Object Drawing.Font('Segoe UI',10,[Drawing.FontStyle]::Bold)
$actionLabel.AutoSize = $true
$actionLabel.Location = New-Object Drawing.Point(20,122)
$form.Controls.Add($actionLabel)

$box = New-Object Windows.Forms.TextBox
$box.Multiline = $true
$box.ReadOnly = $true
$box.ScrollBars = 'Vertical'
$box.Font = New-Object Drawing.Font('Consolas',9)
$box.Location = New-Object Drawing.Point(20,148)
$box.Size = New-Object Drawing.Size(590,180)
$form.Controls.Add($box)

$refresh = New-Object Windows.Forms.Button
$refresh.Text = 'Actualiser'
$refresh.Location = New-Object Drawing.Point(20,344)
$refresh.Size = New-Object Drawing.Size(100,32)
$form.Controls.Add($refresh)

$openLog = New-Object Windows.Forms.Button
$openLog.Text = 'Ouvrir journal'
$openLog.Location = New-Object Drawing.Point(132,344)
$openLog.Size = New-Object Drawing.Size(115,32)
$form.Controls.Add($openLog)

$hide = New-Object Windows.Forms.Button
$hide.Text = 'Fermer affichage'
$hide.Location = New-Object Drawing.Point(470,344)
$hide.Size = New-Object Drawing.Size(140,32)
$form.Controls.Add($hide)

function Update-Dashboard {
  $dc = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander.*remote'
  } | Select-Object -First 1

  if ($dc) {
    $p = Get-Process -Id $dc.ProcessId
    $status.Text = "● CONNECTE — Desktop Commander PID $($dc.ProcessId)"
    $status.ForeColor = [Drawing.Color]::ForestGreen
    $dcRam = [math]::Round($p.WorkingSet64 / 1MB, 1)
  } else {
    $status.Text = '● DECONNECTE'
    $status.ForeColor = [Drawing.Color]::Firebrick
    $dcRam = 0
  }

  $os = Get-CimInstance Win32_OperatingSystem
  $freeMb = [math]::Round($os.FreePhysicalMemory / 1024, 0)
  $resource.Text = "RAM libre: $freeMb MB    |    Desktop Commander: $dcRam MB"

  if (Test-Path $logPath) {
    $lines = Get-Content $logPath -Tail 12
    $box.Text = ($lines -join [Environment]::NewLine)
  } else {
    $box.Text = 'En attente des premieres activites...'
  }
}

$refresh.Add_Click({ Update-Dashboard })
$openLog.Add_Click({
  if (Test-Path $logPath) { Start-Process notepad.exe -ArgumentList $logPath }
})
$hide.Add_Click({ $form.Close() })

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Update-Dashboard })
$timer.Start()
Update-Dashboard
[void]$form.ShowDialog()
