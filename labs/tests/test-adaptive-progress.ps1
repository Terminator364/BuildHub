$ErrorActionPreference='Stop'

function MacroProgress($m) {
  $total=0.0;$done=0.0
  foreach($t in @($m.micro_tasks)){
    $w=[double]$t.weight
    $c=if($t.state -eq 'DONE'){1.0}else{[double]$t.completion}
    $total+=$w;$done+=($w*$c)
  }
  if($total -eq 0){return 0}
  [math]::Round(($done/$total)*100,0)
}

function ConversationProgress($c) {
  $total=0.0;$done=0.0
  foreach($m in @($c.macro_tasks)){
    $w=[double]$m.weight
    $p=(MacroProgress $m)/100.0
    $total+=$w;$done+=($w*$p)
  }
  if($total -eq 0){return 0}
  [math]::Round(($done/$total)*100,0)
}

$c=[pscustomobject]@{
  macro_tasks=@(
    [pscustomobject]@{
      id='A';weight=1;micro_tasks=@(
        [pscustomobject]@{id='a1';weight=1;state='DONE';completion=1.0},
        [pscustomobject]@{id='a2';weight=1;state='ACTIVE';completion=0.5}
      )
    }
  )
}
$p1=ConversationProgress $c
if($p1 -ne 75){throw "Expected 75 before scope expansion, got $p1"}

$c.macro_tasks[0].micro_tasks += [pscustomobject]@{id='a3';weight=1;state='PENDING';completion=0.0}
$p2=ConversationProgress $c
if($p2 -ne 50){throw "Expected 50 after new micro-task, got $p2"}
if($p2 -ge $p1){throw 'Scope expansion must recalculate denominator'}

$c.macro_tasks += [pscustomobject]@{
  id='B';weight=1;micro_tasks=@(
    [pscustomobject]@{id='b1';weight=1;state='PENDING';completion=0.0}
  )
}
$p3=ConversationProgress $c
if($p3 -ne 25){throw "Expected 25 after new macro-task, got $p3"}

$c.macro_tasks[0].micro_tasks[2].state='DONE'
$c.macro_tasks[0].micro_tasks[2].completion=1.0
$p4=ConversationProgress $c
if($p4 -le $p3){throw 'Completed evidence must increase progress'}

Write-Host "ADAPTIVE_PROGRESS_OK p1=$p1 p2=$p2 p3=$p3 p4=$p4"
