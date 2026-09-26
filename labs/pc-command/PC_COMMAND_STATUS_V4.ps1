$Host.UI.RawUI.WindowTitle = 'PC COMMAND - SUIVI'
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [Console]::OutputEncoding
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$FeedUrl = 'https://raw.githubusercontent.com/Terminator364/BuildHub/lab/pc-command-browser-20260926/labs/pc-command/feed-v3.json'
$StateDir = Join-Path $env:LOCALAPPDATA 'PC_COMMAND'
$CacheFile = Join-Path $StateDir 'feed-v3-cache.json'
$HistoryFile = Join-Path $StateDir 'progress-history.jsonl'
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

$InternetSyncSeconds = 5
$EngineRecalcSeconds = 5
$DisplayRefreshSeconds = 10
$MaxConversations = 10
$MaxMacroTasks = 10
$Feed = $null
$LastSync = [datetime]::MinValue
$LastCalc = [datetime]::MinValue
$LastDisplay = [datetime]::MinValue
$SyncOk = $false
$View = 'conversations'
$ConversationIndex = 0
$MacroIndex = 0
$Cycle = 0
$PreviousCounts = @{}
$PreviousPercents = @{}
$Notices = New-Object System.Collections.Generic.List[string]
$LocalEvents = New-Object System.Collections.Generic.List[object]

function Add-Notice([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return }
  $Notices.Insert(0, ((Get-Date -Format 'HH:mm:ss') + ' | ' + $Text))
  while ($Notices.Count -gt 10) { $Notices.RemoveAt($Notices.Count - 1) }
}

function Get-Feed {
  try {
    $f = Invoke-RestMethod -Uri $FeedUrl -TimeoutSec 4 -Headers @{'Cache-Control'='no-cache'}
    ($f | ConvertTo-Json -Depth 20) | Set-Content -Path $CacheFile -Encoding UTF8
    $script:SyncOk = $true
    return $f
  } catch {
    $script:SyncOk = $false
    if (Test-Path $CacheFile) {
      try { return (Get-Content $CacheFile -Raw | ConvertFrom-Json) } catch {}
    }
    return $null
  }
}

function Get-MicroCompletion($Task) {
  if ($Task.state -eq 'DONE') { return 1.0 }
  $c = if ($null -ne $Task.completion) { [double]$Task.completion } else { 0.0 }
  if ($c -lt 0) { $c = 0 }
  if ($c -gt 1) { $c = 1 }
  return $c
}

function Get-MacroProgress($Macro) {
  $total = 0.0
  $done = 0.0
  $evidence = 0
  $tasks = @($Macro.micro_tasks)
  foreach ($t in $tasks) {
    $w = if ($null -ne $t.weight) { [double]$t.weight } else { 1.0 }
    $c = Get-MicroCompletion $t
    $total += $w
    $done += ($w * $c)
    if ($t.evidence) { $evidence++ }
  }
  $pct = if ($total -gt 0) { [int][math]::Round(($done / $total) * 100, 0) } else { 0 }
  $confidence = if ($tasks.Count -gt 0) { [int][math]::Round(($evidence / $tasks.Count) * 100, 0) } else { 0 }
  return [pscustomobject]@{
    Percent = $pct
    Confidence = $confidence
    Count = $tasks.Count
    Done = @($tasks | Where-Object state -eq 'DONE').Count
    Active = @($tasks | Where-Object state -eq 'ACTIVE').Count
    Pending = @($tasks | Where-Object state -eq 'PENDING').Count
    Blocked = @($tasks | Where-Object state -eq 'BLOCKED').Count
  }
}

function Get-ConversationProgress($Conversation) {
  $total = 0.0
  $done = 0.0
  $macros = @($Conversation.macro_tasks)
  foreach ($m in $macros) {
    $w = if ($null -ne $m.weight) { [double]$m.weight } else { 1.0 }
    $p = Get-MacroProgress $m
    $total += $w
    $done += ($w * ($p.Percent / 100.0))
  }
  return [pscustomobject]@{
    Percent = if ($total -gt 0) { [int][math]::Round(($done / $total) * 100, 0) } else { 0 }
    MacroCount = $macros.Count
    Active = @($macros | Where-Object state -eq 'ACTIVE').Count
    Waiting = @($macros | Where-Object state -eq 'WAITING').Count
    Blocked = @($macros | Where-Object state -eq 'BLOCKED').Count
  }
}

function Get-Bar([int]$Pct, [int]$Width = 30) {
  $filled = [math]::Floor(($Pct / 100.0) * $Width)
  if ($filled -lt 0) { $filled = 0 }
  if ($filled -gt $Width) { $filled = $Width }
  return ('[' + ('#' * $filled) + ('-' * ($Width - $filled)) + ']')
}

function Get-Connection {
  $dc = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -eq 'node.exe' -and $_.CommandLine -match 'desktop-commander.*remote'
  } | Select-Object -First 1
  if ($dc) {
    $p = Get-Process -Id $dc.ProcessId -ErrorAction SilentlyContinue
    return [pscustomobject]@{
      Connected = $true
      Pid = $dc.ProcessId
      RamMB = if ($p) { [math]::Round($p.WorkingSet64 / 1MB, 1) } else { 0 }
    }
  }
  return [pscustomobject]@{ Connected=$false; Pid=0; RamMB=0 }
}

function Get-DriveState {
  if (Get-Process GoogleDriveFS -ErrorAction SilentlyContinue) { return 'ACTIF' }
  return 'ARRETE'
}

function Get-EventAgeMinutes([string]$Iso) {
  if (-not $Iso) { return 999999 }
  try {
    $d = [datetimeoffset]::Parse($Iso)
    return [math]::Max(0, ([datetimeoffset]::Now - $d).TotalMinutes)
  } catch { return 999999 }
}

function Get-Health($Macro) {
  if ($Macro.blocker -or $Macro.state -eq 'BLOCKED') { return 'BLOQUE' }
  $age = Get-EventAgeMinutes $Macro.last_event
  if ($Macro.state -eq 'ACTIVE' -and $age -gt 15) { return 'SILENCIEUX' }
  $p = Get-MacroProgress $Macro
  if ($p.Percent -ge 95) { return 'CLOTURE' }
  if ($Macro.state -eq 'WAITING') { return 'ATTENTE' }
  return 'ACTIF'
}

function Get-Forecast($Macro) {
  $p = Get-MacroProgress $Macro
  $health = Get-Health $Macro
  if ($health -eq 'BLOQUE') { return 'Projection suspendue: un blocage est present.' }
  if ($health -eq 'SILENCIEUX') { return 'Attention: flux actif sans evenement recent; progression non extrapolee.' }
  if ($p.Percent -ge 90 -and $p.Confidence -ge 70) { return 'Phase de cloture probable, sous reserve de nouvelle portee.' }
  if ($p.Percent -ge 70) { return 'Phase avancee; la portee peut encore changer.' }
  if ($p.Percent -ge 40) { return 'Milieu de parcours; plusieurs micro-taches restent ouvertes.' }
  return 'Phase initiale ou plan encore evolutif.'
}

function Save-History($FeedObj) {
  if (-not $FeedObj) { return }
  $row = [ordered]@{
    at = (Get-Date).ToString('o')
    conversations = @()
  }
  foreach ($c in @($FeedObj.conversations)) {
    $cp = Get-ConversationProgress $c
    $row.conversations += [ordered]@{
      id = $c.id
      percent = $cp.Percent
      macro_count = $cp.MacroCount
    }
  }
  ($row | ConvertTo-Json -Compress -Depth 8) | Add-Content -Path $HistoryFile -Encoding UTF8
}

function Get-EtaText($Conversation) {
  if (-not (Test-Path $HistoryFile)) { return 'ETA: donnees insuffisantes' }
  $rows = @(Get-Content $HistoryFile -Tail 30 | ForEach-Object {
    try { $_ | ConvertFrom-Json } catch {}
  })
  $samples = @()
  foreach ($r in $rows) {
    $c = @($r.conversations | Where-Object id -eq $Conversation.id | Select-Object -First 1)
    if ($c.Count -gt 0) {
      try { $samples += [pscustomobject]@{At=[datetimeoffset]::Parse($r.at);Pct=[double]$c[0].percent;Count=[int]$c[0].macro_count} } catch {}
    }
  }
  if ($samples.Count -lt 4) { return 'ETA: donnees insuffisantes' }
  $recent = @($samples | Select-Object -Last 8)
  $first = $recent[0]
  $last = $recent[-1]
  if ($recent | Where-Object { $_.Count -ne $last.Count }) { return 'ETA: plan en evolution, estimation suspendue' }
  $minutes = ($last.At - $first.At).TotalMinutes
  $delta = $last.Pct - $first.Pct
  if ($minutes -le 0 -or $delta -le 0) { return 'ETA: tendance insuffisante' }
  $rate = $delta / $minutes
  if ($rate -le 0.05) { return 'ETA: tendance trop lente ou instable' }
  $remaining = (100 - $last.Pct) / $rate
  if ($remaining -gt 1440) { return 'ETA: > 24 h, confiance faible' }
  return ('ETA indicative: ~' + [math]::Round($remaining,0) + ' min (si le plan ne change pas)')
}

function Humanize-Process([string]$Name, [string]$Cmd) {
  if ($Cmd -match 'PC_COMMAND_STATUS_V4') { return $null }
  if ($Cmd -match 'firefox|msedge|brave|falkon|qutebrowser|helium') { return 'Test navigateur ou navigation locale' }
  if ($Cmd -match 'Invoke-WebRequest|Invoke-RestMethod|curl|wget') { return 'Acces Internet / telechargement' }
  if ($Cmd -match 'Get-Process|Get-CimInstance|tasklist') { return 'Inspection ressources/processus' }
  if ($Cmd -match 'Remove-Item|del |erase ') { return 'Nettoyage local' }
  if ($Cmd -match 'Set-Content|Add-Content|Out-File') { return 'Mise a jour fichier local' }
  if ($Cmd -match 'Start-Process') { return 'Ouverture application/page' }
  if ($Cmd -match 'node|npm|npx') { return 'Execution Node / Desktop Commander' }
  if ($Name -match 'powershell|pwsh|cmd') { return 'Commande Windows' }
  return $null
}

try {
  Unregister-Event -SourceIdentifier PCCommandV4Start -ErrorAction SilentlyContinue
  Register-WmiEvent -Class Win32_ProcessStartTrace -SourceIdentifier PCCommandV4Start | Out-Null
} catch {}

function Drain-LocalEvents {
  foreach ($ev in @(Get-Event -SourceIdentifier PCCommandV4Start -ErrorAction SilentlyContinue)) {
    $pid2 = [int]$ev.SourceEventArgs.NewEvent.ProcessID
    $name = [string]$ev.SourceEventArgs.NewEvent.ProcessName
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$pid2"
    $cmd = if ($proc) { [string]$proc.CommandLine } else { '' }
    $human = Humanize-Process $name $cmd
    if ($human) {
      $LocalEvents.Insert(0, [pscustomobject]@{At=Get-Date;Text=$human})
      while ($LocalEvents.Count -gt 12) { $LocalEvents.RemoveAt($LocalEvents.Count - 1) }
    }
    Remove-Event -EventIdentifier $ev.EventIdentifier
  }
}

function Detect-ScopeChanges($NewFeed) {
  if (-not $NewFeed) { return }
  foreach ($conv in @($NewFeed.conversations)) {
    $cp = Get-ConversationProgress $conv
    $key = 'conv:' + [string]$conv.id
    if ($PreviousCounts.ContainsKey($key)) {
      $dc = $cp.MacroCount - [int]$PreviousCounts[$key]
      $dp = $cp.Percent - [int]$PreviousPercents[$key]
      if ($dc -gt 0) { Add-Notice "Nouvelle macro-tache dans $($conv.label): +$dc. Pourcentage recalcule." }
      elseif ($dp -ne 0) { Add-Notice "Progression $($conv.label): $dp point(s)." }
    }
    $PreviousCounts[$key] = $cp.MacroCount
    $PreviousPercents[$key] = $cp.Percent

    foreach ($m in @($conv.macro_tasks)) {
      $mp = Get-MacroProgress $m
      $mk = 'macro:' + [string]$conv.id + ':' + [string]$m.id
      if ($PreviousCounts.ContainsKey($mk)) {
        $dt = $mp.Count - [int]$PreviousCounts[$mk]
        $dp = $mp.Percent - [int]$PreviousPercents[$mk]
        if ($dt -gt 0) { Add-Notice "Nouvelle micro-tache dans $($m.title): +$dt. Progression recalculee." }
        elseif ($dp -ne 0) { Add-Notice "$($m.title): $dp point(s)." }
      }
      $PreviousCounts[$mk] = $mp.Count
      $PreviousPercents[$mk] = $mp.Percent
    }
  }
}

function Show-Header {
  $conn = Get-Connection
  $os = Get-CimInstance Win32_OperatingSystem
  $free = [math]::Round($os.FreePhysicalMemory / 1024, 0)
  $drive = Get-DriveState
  Write-Host '=============================================================================' -ForegroundColor Cyan
  Write-Host ' PC COMMAND - MOTEUR DE FLUX' -ForegroundColor Cyan
  Write-Host '=============================================================================' -ForegroundColor Cyan
  if ($conn.Connected) {
    Write-Host ("ChatGPT-PC : CONNECTE | PID $($conn.Pid) | Desktop Commander $($conn.RamMB) MB") -ForegroundColor Green
  } else {
    Write-Host 'ChatGPT-PC : DECONNECTE | Le suivi Internet reste disponible' -ForegroundColor Yellow
  }
  Write-Host ("RAM libre : $free MB | Google Drive : $drive")
  Write-Host ("Moteur : calcul 5 s | Internet 5 s | affichage 10 s | cycle $Cycle")
  Write-Host ("Derniere synchro : " + $(if ($LastSync -eq [datetime]::MinValue) {'jamais'} else {$LastSync.ToString('HH:mm:ss')}))
  if (-not $SyncOk -and $LastSync -ne [datetime]::MinValue) { Write-Host 'Reseau: cache local utilise au dernier cycle.' -ForegroundColor Yellow }
  Write-Host ''
}

function Show-ConversationTabs {
  if (-not $Feed) { return }
  $parts = @()
  $i = 1
  foreach ($c in @($Feed.conversations | Select-Object -First $MaxConversations)) {
    $p = Get-ConversationProgress $c
    $name = [string]$c.label
    if ($name.Length -gt 18) { $name = $name.Substring(0,18) }
    $parts += "[$i $name $($p.Percent)%]"
    $i++
  }
  Write-Host ('CONVERSATIONS CONNECTEES : ' + ($parts -join '  ')) -ForegroundColor DarkCyan
  Write-Host ''
}

function Show-Conversations {
  Write-Host 'VUE GENERALE' -ForegroundColor Cyan
  Write-Host ''
  $i = 1
  foreach ($c in @($Feed.conversations | Select-Object -First $MaxConversations)) {
    $p = Get-ConversationProgress $c
    Write-Host ("[$i] " + $c.label + " | code " + $c.short_code) -ForegroundColor Green
    Write-Host ('    ' + (Get-Bar $p.Percent 34) + ' ' + $p.Percent + '%')
    Write-Host ("    $($p.MacroCount) macro-tache(s) | $($p.Active) active(s) | $($p.Blocked) bloquee(s)")
    Write-Host ('    ' + $c.objective)
    Write-Host ('    ' + (Get-EtaText $c)) -ForegroundColor DarkGray
    Write-Host ''
    $i++
  }
  if ($Notices.Count -gt 0) {
    Write-Host 'CHANGEMENTS DETECTES' -ForegroundColor Yellow
    foreach ($n in @($Notices | Select-Object -First 5)) { Write-Host ('  ' + $n) }
    Write-Host ''
  }
}

function Show-Macros($Conversation) {
  $cp = Get-ConversationProgress $Conversation
  Write-Host ('CONVERSATION : ' + $Conversation.label) -ForegroundColor Cyan
  Write-Host ('OBJECTIF     : ' + $Conversation.objective)
  Write-Host ('AVANCEMENT   : ' + (Get-Bar $cp.Percent 40) + ' ' + $cp.Percent + '%') -ForegroundColor Green
  Write-Host ('ETA          : ' + (Get-EtaText $Conversation))
  Write-Host ''
  Write-Host 'MACRO-TACHES' -ForegroundColor Cyan
  $i = 1
  foreach ($m in @($Conversation.macro_tasks | Select-Object -First $MaxMacroTasks)) {
    $p = Get-MacroProgress $m
    $health = Get-Health $m
    $color = if ($health -eq 'BLOQUE') {'Red'} elseif ($health -eq 'SILENCIEUX') {'Yellow'} elseif ($m.state -eq 'WAITING') {'DarkYellow'} else {'Green'}
    Write-Host ("[$i] " + $m.title + " | " + $health) -ForegroundColor $color
    Write-Host ('    ' + (Get-Bar $p.Percent 30) + ' ' + $p.Percent + '% | preuves ' + $p.Confidence + '%')
    Write-Host ('    En cours : ' + $m.current_action)
    Write-Host ''
    $i++
  }
}

function Show-Micro($Macro) {
  $p = Get-MacroProgress $Macro
  Write-Host ('MACRO-TACHE : ' + $Macro.title) -ForegroundColor Cyan
  Write-Host ('AVANCEMENT  : ' + (Get-Bar $p.Percent 42) + ' ' + $p.Percent + '%') -ForegroundColor Green
  Write-Host ('FIABILITE   : ' + $p.Confidence + '% des micro-taches ont une preuve')
  Write-Host ('SANTE       : ' + (Get-Health $Macro))
  Write-Host ('ANALYSE     : ' + (Get-Forecast $Macro)) -ForegroundColor Yellow
  Write-Host ''
  Write-Host ('EN COURS    : ' + $Macro.current_action)
  Write-Host ('DERNIER OK  : ' + $Macro.last_success) -ForegroundColor Green
  Write-Host ('PROCHAINE   : ' + $Macro.next_step)
  if ($Macro.blocker) { Write-Host ('BLOCAGE     : ' + $Macro.blocker) -ForegroundColor Red }
  else { Write-Host 'BLOCAGE     : aucun' -ForegroundColor Green }
  Write-Host ''
  Write-Host ("MICRO-TACHES : $($p.Done) terminee(s) | $($p.Active) active(s) | $($p.Pending) attente | $($p.Blocked) bloquee(s)")
  foreach ($t in @($Macro.micro_tasks)) {
    $mark = switch ($t.state) { 'DONE' {'OK'} 'ACTIVE' {'>>'} 'BLOCKED' {'!!'} default {'..'} }
    $pct = [math]::Round((Get-MicroCompletion $t) * 100, 0)
    Write-Host ("  $mark " + $t.title + " - " + $pct + "%")
    if ($t.evidence) { Write-Host ('       preuve: ' + $t.evidence) -ForegroundColor DarkGray }
  }
  if ($Macro.events) {
    Write-Host ''
    Write-Host 'EVENEMENTS RECENTS' -ForegroundColor Cyan
    foreach ($e in @($Macro.events | Select-Object -Last 8)) {
      Write-Host ('  ' + $e.at + ' | ' + $e.type + ' | ' + $e.summary)
    }
  }
}

function Show-Sources {
  Write-Host 'SOURCES ET ADAPTATEURS' -ForegroundColor Cyan
  Write-Host ''
  Write-Host 'DEPENDANCES PHYSIQUES REQUISES : Internet + compte ChatGPT.' -ForegroundColor Green
  Write-Host 'Les autres sources sont des adaptateurs: elles enrichissent le moteur sans etre indispensables.'
  Write-Host ''
  Write-Host '  GitHub public     : bus/snapshot zero-dollar, lecture locale sans authentification.'
  Write-Host '  ChatGPT connecte  : publie les changements de taches via PCCONNECT.'
  Write-Host '  Desktop Commander : source locale optionnelle pour actions Windows observees.'
  Write-Host '  Google Drive      : source optionnelle quand une conversation y effectue une action.'
  Write-Host '  Telegram          : source optionnelle quand une conversation/bot publie un etat.'
  Write-Host '  YouTube/Web       : pas de surveillance magique; les actions/recherches doivent emettre des evenements.'
  Write-Host ''
  Write-Host 'Limite honnete: PC COMMAND ne peut pas lire toutes les conversations ChatGPT sans qu elles soient connectees.' -ForegroundColor Yellow
}

function Show-Local {
  Write-Host 'ACTIVITE LOCALE OBSERVEE' -ForegroundColor Cyan
  Write-Host ''
  if ($LocalEvents.Count -eq 0) { Write-Host 'Aucune nouvelle activite locale detectee depuis le lancement.' }
  else {
    foreach ($e in $LocalEvents) { Write-Host ('  ' + $e.At.ToString('HH:mm:ss') + ' | ' + $e.Text) }
  }
  Write-Host ''
  Write-Host 'Cette vue utilise WMI localement et ne consomme pas un appel Desktop Commander.' -ForegroundColor DarkGray
}

function Show-Settings {
  $code = 'PCCONNECT|v1|pc=MBMPC|hub=Terminator364/BuildHub|branch=lab/pc-command-browser-20260926|feed=feed-v3|slot=AUTO|max=10'
  Write-Host 'PARAMETRES' -ForegroundColor Cyan
  Write-Host ''
  Write-Host ("Synchro Internet : $InternetSyncSeconds s")
  Write-Host ("Recalcul moteur   : $EngineRecalcSeconds s")
  Write-Host ("Rafraichissement  : $DisplayRefreshSeconds s")
  Write-Host ("Conversations max : $MaxConversations")
  Write-Host ("Macro-taches max  : $MaxMacroTasks par conversation")
  Write-Host ''
  Write-Host 'CODE POUR RELIER UNE NOUVELLE CONVERSATION CHATGPT :' -ForegroundColor Green
  Write-Host $code -ForegroundColor White
  Write-Host ''
  Write-Host '[C] Copier ce code dans le presse-papiers'
  Write-Host 'La nouvelle conversation devra publier ses propres evenements et ne modifier que son flux.'
}

while ($true) {
  $now = Get-Date
  Drain-LocalEvents

  if (($now - $LastSync).TotalSeconds -ge $InternetSyncSeconds -or -not $Feed) {
    $newFeed = Get-Feed
    if ($newFeed) {
      Detect-ScopeChanges $newFeed
      $Feed = $newFeed
      if ($Feed.engine.local_recalc_seconds) { $EngineRecalcSeconds = [int]$Feed.engine.local_recalc_seconds }
      if ($Feed.engine.remote_sync_seconds) { $InternetSyncSeconds = [int]$Feed.engine.remote_sync_seconds }
      if ($Feed.engine.max_connected_conversations) { $MaxConversations = [int]$Feed.engine.max_connected_conversations }
      if ($Feed.engine.max_active_macro_tasks_per_conversation) { $MaxMacroTasks = [int]$Feed.engine.max_active_macro_tasks_per_conversation }
    }
    $LastSync = $now
  }

  if (($now - $LastCalc).TotalSeconds -ge $EngineRecalcSeconds) {
    $Cycle++
    if ($Feed) { Save-History $Feed }
    $LastCalc = $now
  }

  if (($now - $LastDisplay).TotalSeconds -ge $DisplayRefreshSeconds -or $LastDisplay -eq [datetime]::MinValue) {
    Clear-Host
    Show-Header
    Show-ConversationTabs
    if (-not $Feed) {
      Write-Host 'Aucun flux disponible. Le moteur retentera automatiquement.' -ForegroundColor Red
    } elseif ($View -eq 'conversations') {
      Show-Conversations
    } elseif ($View -eq 'macros') {
      $conv = @($Feed.conversations)[$ConversationIndex]
      Show-Macros $conv
    } elseif ($View -eq 'micro') {
      $conv = @($Feed.conversations)[$ConversationIndex]
      $macro = @($conv.macro_tasks)[$MacroIndex]
      Show-Micro $macro
    } elseif ($View -eq 'sources') {
      Show-Sources
    } elseif ($View -eq 'local') {
      Show-Local
    } elseif ($View -eq 'settings') {
      Show-Settings
    }

    Write-Host ''
    Write-Host '-----------------------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '[A] General  [1-9] Selection  [B] Retour  [S] Sources  [L] Local  [P] Parametres  [R] Sync  [Q] Fermer'
    Write-Host ('Affichage: ' + $LastDisplay.ToString('HH:mm:ss') + ' -> ' + $now.ToString('HH:mm:ss') + ' | prochain ecran dans 10 s') -ForegroundColor DarkGray
    $LastDisplay = $now
  }

  if ([Console]::KeyAvailable) {
    $k = [Console]::ReadKey($true).KeyChar.ToString().ToUpperInvariant()
    if ($k -eq 'Q') { Unregister-Event -SourceIdentifier PCCommandV4Start -ErrorAction SilentlyContinue; exit }
    if ($k -eq 'R') { $LastSync = [datetime]::MinValue; $LastDisplay = [datetime]::MinValue }
    elseif ($k -eq 'A') { $View='conversations'; $LastDisplay=[datetime]::MinValue }
    elseif ($k -eq 'S') { $View='sources'; $LastDisplay=[datetime]::MinValue }
    elseif ($k -eq 'L') { $View='local'; $LastDisplay=[datetime]::MinValue }
    elseif ($k -eq 'P') { $View='settings'; $LastDisplay=[datetime]::MinValue }
    elseif ($k -eq 'B') {
      if ($View -eq 'micro') { $View='macros' }
      elseif ($View -eq 'macros') { $View='conversations' }
      else { $View='conversations' }
      $LastDisplay=[datetime]::MinValue
    }
    elseif ($k -eq 'C' -and $View -eq 'settings') {
      $code='PCCONNECT|v1|pc=MBMPC|hub=Terminator364/BuildHub|branch=lab/pc-command-browser-20260926|feed=feed-v3|slot=AUTO|max=10'
      Set-Clipboard -Value $code
      Add-Notice 'Code PCCONNECT copie dans le presse-papiers.'
      $LastDisplay=[datetime]::MinValue
    }
    elseif ($k -match '^[1-9]$' -and $Feed) {
      $idx=[int]$k-1
      if ($View -eq 'conversations' -and $idx -lt @($Feed.conversations).Count) {
        $ConversationIndex=$idx; $View='macros'; $LastDisplay=[datetime]::MinValue
      } elseif ($View -eq 'macros') {
        $conv=@($Feed.conversations)[$ConversationIndex]
        if ($idx -lt @($conv.macro_tasks).Count) { $MacroIndex=$idx; $View='micro'; $LastDisplay=[datetime]::MinValue }
      }
    }
  }

  Start-Sleep -Milliseconds 250
}
