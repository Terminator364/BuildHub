function Get-PcMicroCompletion {
  param($Task)
  if ($null -eq $Task) { return 0.0 }
  if ([string]$Task.state -eq 'DONE') { return 1.0 }
  $c = 0.0
  if ($null -ne $Task.completion) { $c = [double]$Task.completion }
  if ($c -lt 0) { $c = 0 }
  if ($c -gt 1) { $c = 1 }
  return $c
}

function Get-PcMacroProgress {
  param($Macro)
  $micro = @($Macro.micro_tasks)
  if ($micro.Count -eq 0) {
    $c = 0.0
    if ($null -ne $Macro.completion) { $c = [double]$Macro.completion }
    if ([string]$Macro.state -eq 'DONE') { $c = 1.0 }
    if ($c -lt 0) { $c = 0 }
    if ($c -gt 1) { $c = 1 }
    return [pscustomobject]@{
      Percent = [int][math]::Round($c * 100,0)
      Confidence = if ($null -ne $Macro.confidence) {[int][math]::Round(([double]$Macro.confidence)*100,0)} else {0}
      Count = 0; Done = 0; Active = 0; Pending = 0; Blocked = 0
    }
  }
  $total = 0.0; $done = 0.0; $evidence = 0
  foreach ($t in $micro) {
    $w = if ($null -ne $t.weight) {[double]$t.weight} else {1.0}
    $total += $w
    $done += $w * (Get-PcMicroCompletion $t)
    if ($t.evidence -or $t.evidence_ref) { $evidence++ }
  }
  return [pscustomobject]@{
    Percent = if ($total -gt 0) {[int][math]::Round(($done/$total)*100,0)} else {0}
    Confidence = if ($micro.Count -gt 0) {[int][math]::Round(($evidence/$micro.Count)*100,0)} else {0}
    Count = $micro.Count
    Done = @($micro|Where-Object state -eq 'DONE').Count
    Active = @($micro|Where-Object state -eq 'ACTIVE').Count
    Pending = @($micro|Where-Object state -eq 'PENDING').Count
    Blocked = @($micro|Where-Object state -eq 'BLOCKED').Count
  }
}

function Get-PcConversationProgress {
  param($Conversation)
  $macros = @($Conversation.macro_tasks)
  $total = 0.0; $done = 0.0
  foreach ($m in $macros) {
    $w = if ($null -ne $m.weight) {[double]$m.weight} else {1.0}
    $p = Get-PcMacroProgress $m
    $total += $w
    $done += $w * ($p.Percent/100.0)
  }
  return [pscustomobject]@{
    Percent = if ($total -gt 0) {[int][math]::Round(($done/$total)*100,0)} else {0}
    MacroCount = $macros.Count
    Active = @($macros|Where-Object state -eq 'ACTIVE').Count
    Waiting = @($macros|Where-Object state -eq 'WAITING').Count
    Blocked = @($macros|Where-Object state -eq 'BLOCKED').Count
    Done = @($macros|Where-Object state -eq 'DONE').Count
  }
}

function Get-PcAgeSeconds {
  param([string]$Iso)
  if ([string]::IsNullOrWhiteSpace($Iso)) { return [double]::PositiveInfinity }
  try { return [math]::Max(0,([datetimeoffset]::Now-[datetimeoffset]::Parse($Iso)).TotalSeconds) }
  catch { return [double]::PositiveInfinity }
}

function Format-PcAge {
  param([double]$Seconds)
  if ([double]::IsInfinity($Seconds)) { return 'inconnu' }
  if ($Seconds -lt 60) { return ([int]$Seconds).ToString()+' s' }
  if ($Seconds -lt 3600) { return ([int]($Seconds/60)).ToString()+' min '+([int]($Seconds%60)).ToString()+' s' }
  return ([int]($Seconds/3600)).ToString()+' h '+([int](($Seconds%3600)/60)).ToString()+' min'
}

function Get-PcLifecycleView {
  param($Conversation)
  $lc = $Conversation.lifecycle
  if ($null -eq $lc) {
    return [pscustomobject]@{Label='ETAT INCONNU';Color='Yellow';Detail='Aucun etat publie.';AgeSeconds=[double]::PositiveInfinity}
  }
  $state = [string]$lc.state
  $stamp = if ($lc.last_transition_at) {[string]$lc.last_transition_at} elseif ($Conversation.updated_at) {[string]$Conversation.updated_at} else {''}
  $age = Get-PcAgeSeconds $stamp
  $phase = if ($lc.phase) {[string]$lc.phase} else {'-'}
  switch ($state) {
    'ASSISTANT_PROCESSING' {
      if ($age -gt 120) { return [pscustomobject]@{Label='SIGNAL DISTANT ANCIEN';Color='Yellow';Detail=("Dernier signal il y a "+(Format-PcAge $age)+". Traitement possiblement en cours ou interrompu.");AgeSeconds=$age} }
      return [pscustomobject]@{Label='TRAVAIL EN COURS';Color='Green';Detail=("Phase "+$phase+" | depuis "+(Format-PcAge $age));AgeSeconds=$age}
    }
    'TOOL_RUNNING' { return [pscustomobject]@{Label='OUTIL EN COURS';Color='Green';Detail=("Phase "+$phase+" | signal "+(Format-PcAge $age));AgeSeconds=$age} }
    'WAITING_EXTERNAL' { return [pscustomobject]@{Label='ATTENTE EXTERNE';Color='Yellow';Detail=("Dependance externe | "+(Format-PcAge $age));AgeSeconds=$age} }
    'ASSISTANT_RESPONDED' { return [pscustomobject]@{Label='REPONSE LIVREE';Color='Cyan';Detail='En attente du prochain message utilisateur.';AgeSeconds=$age} }
    'PAUSED' { return [pscustomobject]@{Label='EN PAUSE';Color='Yellow';Detail='Travail volontairement mis en pause.';AgeSeconds=$age} }
    'USER_STOPPED_EXPLICIT' { return [pscustomobject]@{Label='ARRET UTILISATEUR';Color='Yellow';Detail='Arret explicite rapporte.';AgeSeconds=$age} }
    'INTERRUPTED_INFERRED' { return [pscustomobject]@{Label='INTERRUPTION PROBABLE';Color='Yellow';Detail='Le flux precedent n a pas publie sa fermeture.';AgeSeconds=$age} }
    'SECURITY_CHECK_REPORTED' { return [pscustomobject]@{Label='CONTROLE SECURITE';Color='Yellow';Detail='Un controle de securite a ete rapporte.';AgeSeconds=$age} }
    'NETWORK_ERROR' { return [pscustomobject]@{Label='ERREUR RESEAU';Color='Red';Detail='Erreur reseau rapportee par le flux.';AgeSeconds=$age} }
    'RATE_LIMIT_WAIT' { return [pscustomobject]@{Label='ATTENTE QUOTA';Color='Yellow';Detail='Limite/quota rapporte.';AgeSeconds=$age} }
    'OFFLINE' { return [pscustomobject]@{Label='HORS LIGNE';Color='Yellow';Detail='Dernier etat local disponible.';AgeSeconds=$age} }
    'RECOVERING' { return [pscustomobject]@{Label='REPRISE';Color='Green';Detail='Reprise du dernier etat fiable.';AgeSeconds=$age} }
    'COMPLETED' { return [pscustomobject]@{Label='TERMINE';Color='Green';Detail='Flux declare termine.';AgeSeconds=$age} }
    default { return [pscustomobject]@{Label=$state;Color='Yellow';Detail=("Etat publie | "+(Format-PcAge $age));AgeSeconds=$age} }
  }
}

function Get-PcRisk {
  param($Conversation)
  $score = 0; $reasons = New-Object System.Collections.Generic.List[string]
  $life = Get-PcLifecycleView $Conversation
  if ($life.Label -match 'ANCIEN|INTERRUPTION|ERREUR') { $score += 35; $reasons.Add($life.Label) }
  foreach ($m in @($Conversation.macro_tasks)) {
    if ($m.blocker -or $m.state -eq 'BLOCKED') { $score += 15; $reasons.Add(('Blocage: '+$m.title)) }
  }
  if ($score -gt 100) { $score = 100 }
  $level = if ($score -ge 60) {'ELEVE'} elseif ($score -ge 30) {'MOYEN'} else {'FAIBLE'}
  return [pscustomobject]@{Score=$score;Level=$level;Reasons=@($reasons)}
}

function Get-PcEta {
  param([string]$HistoryFile,[string]$ConversationId,[int]$CurrentPercent,[int]$MacroCount)
  if (-not (Test-Path $HistoryFile)) { return 'donnees insuffisantes' }
  $samples = New-Object System.Collections.Generic.List[object]
  foreach ($line in @(Get-Content $HistoryFile -Tail 80 -ErrorAction SilentlyContinue)) {
    try {
      $r = $line | ConvertFrom-Json
      $c = @($r.conversations|Where-Object id -eq $ConversationId|Select-Object -First 1)
      if ($c.Count -gt 0) { $samples.Add([pscustomobject]@{At=[datetimeoffset]::Parse($r.at);Pct=[double]$c[0].percent;Count=[int]$c[0].macro_count}) }
    } catch {}
  }
  if ($samples.Count -lt 4) { return 'donnees insuffisantes' }
  $recent = @($samples|Select-Object -Last 10)
  if (@($recent|Where-Object Count -ne $MacroCount).Count -gt 0) { return 'plan en evolution: estimation suspendue' }
  $first=$recent[0]; $last=$recent[-1]
  $mins=($last.At-$first.At).TotalMinutes; $delta=$last.Pct-$first.Pct
  if ($mins -le 0 -or $delta -le 0) { return 'tendance insuffisante' }
  $rate=$delta/$mins
  if ($rate -lt 0.05) { return 'tendance trop lente/instable' }
  $remaining=(100-$CurrentPercent)/$rate
  if ($remaining -gt 1440) { return '>24 h (confiance faible)' }
  return ('~'+[math]::Round($remaining,0)+' min si la portee reste stable')
}

function Get-PcVisibleMicroTasks {
  param($Macro,[int]$MaxVisible=20)
  $all=@($Macro.micro_tasks)
  if ($all.Count -le $MaxVisible) { return [pscustomobject]@{Items=$all;Hidden=0;Total=$all.Count} }
  $active=@($all|Where-Object state -in @('ACTIVE','BLOCKED')|Select-Object -First ([math]::Min(10,$MaxVisible)))
  $remaining=@($all|Where-Object {$_ -notin $active}|Select-Object -Last ($MaxVisible-$active.Count))
  return [pscustomobject]@{Items=@($active+$remaining);Hidden=$all.Count-($active.Count+$remaining.Count);Total=$all.Count}
}
