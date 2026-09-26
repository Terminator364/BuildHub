function ConvertTo-PcPdfEscaped {
  param([string]$Text)
  if($null-eq$Text){return ''}
  return (($Text -replace '\\','\\') -replace '\(','\(') -replace '\)','\)')
}

function Split-PcReportText {
  param([string]$Text,[int]$Width=96)
  $list=New-Object System.Collections.Generic.List[string]
  $rest=if($null-eq$Text){''}else{[string]$Text}
  if($rest.Length-eq0){$list.Add('');return @($list)}
  while($rest.Length-gt$Width){
    $cut=$Width
    $space=$rest.LastIndexOf(' ',[math]::Min($Width,$rest.Length-1))
    if($space-gt28){$cut=$space}
    $list.Add($rest.Substring(0,$cut).TrimEnd())
    $rest=$rest.Substring($cut).TrimStart()
  }
  $list.Add($rest)
  return @($list)
}

function New-PcSimplePdf {
  param([string]$Path,[string[]]$Lines)
  $enc=[Text.Encoding]::GetEncoding(1252)
  $nl=[Environment]::NewLine
  $all=New-Object System.Collections.Generic.List[string]
  foreach($line in @($Lines)){foreach($part in @(Split-PcReportText ([string]$line) 96)){$all.Add($part)}}
  $perPage=48
  $pageCount=[math]::Max(1,[math]::Ceiling($all.Count/[double]$perPage))
  $fontObj=3+(2*$pageCount)
  $objects=@{}
  $objects[1]='<< /Type /Catalog /Pages 2 0 R >>'
  $kids=New-Object System.Collections.Generic.List[string]
  for($i=0;$i-lt$pageCount;$i++){
    $pageObj=3+(2*$i);$contentObj=4+(2*$i);$kids.Add("$pageObj 0 R")
    $objects[$pageObj]="<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 $fontObj 0 R >> >> /Contents $contentObj 0 R >>"
    $stream='BT'+$nl+'/F1 9 Tf'+$nl+'40 800 Td'+$nl
    foreach($line in @($all|Select-Object -Skip ($i*$perPage) -First $perPage)){
      $stream+='('+(ConvertTo-PcPdfEscaped $line)+') Tj'+$nl+'0 -15 Td'+$nl
    }
    $stream+='ET'+$nl
    $objects[$contentObj]="<< /Length $($enc.GetByteCount($stream)) >>"+$nl+'stream'+$nl+$stream+'endstream'
  }
  $objects[2]="<< /Type /Pages /Count $pageCount /Kids [ "+($kids -join ' ')+" ] >>"
  $objects[$fontObj]='<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'
  $sb=New-Object Text.StringBuilder
  [void]$sb.Append('%PDF-1.4'+$nl)
  $offsets=@{0=0}
  for($n=1;$n-le$fontObj;$n++){
    $offsets[$n]=$enc.GetByteCount($sb.ToString())
    [void]$sb.Append("$n 0 obj"+$nl+$objects[$n]+$nl+'endobj'+$nl)
  }
  $xref=$enc.GetByteCount($sb.ToString())
  [void]$sb.Append('xref'+$nl+'0 '+($fontObj+1)+$nl)
  [void]$sb.Append('0000000000 65535 f '+$nl)
  for($n=1;$n-le$fontObj;$n++){[void]$sb.Append(("{0:D10} 00000 n " -f [int]$offsets[$n])+$nl)}
  [void]$sb.Append('trailer'+$nl+'<< /Size '+($fontObj+1)+' /Root 1 0 R >>'+$nl+'startxref'+$nl+$xref+$nl+'%%EOF'+$nl)
  [IO.File]::WriteAllBytes($Path,$enc.GetBytes($sb.ToString()))
  return $Path
}
function ConvertTo-PcHtmlEncoded {
  param([string]$Text)
  return [System.Net.WebUtility]::HtmlEncode($Text)
}

function Find-PcDriveRoot {
  $candidates=@('G:\My Drive','G:\Mon Drive','H:\My Drive','H:\Mon Drive',(Join-Path $env:USERPROFILE 'My Drive'),(Join-Path $env:USERPROFILE 'Google Drive'))
  foreach($c in $candidates){if(Test-Path $c){return $c}}
  foreach($d in Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue){
    try{
      $roots=Get-ChildItem $d.Root -Directory -ErrorAction SilentlyContinue|Where-Object Name -in @('My Drive','Mon Drive')
      if($roots){return $roots[0].FullName}
    }catch{}
  }
  return $null
}

function New-PcReport {
  param($Config,$Overview,$Channel,$Paths)
  $stamp=Get-Date -Format 'yyyyMMdd-HHmmss'
  $convTitle=if($Channel){[string]$Channel.label}else{'PC COMMAND'}
  $safe=($convTitle -replace '[^A-Za-z0-9_-]','_').Trim('_')
  if(-not$safe){$safe='PC_COMMAND'}
  $baseName='PC_COMMAND_'+$safe+'_v'+$Config.version+'_'+$stamp
  $htmlPath=Join-Path $Paths.Reports ($baseName+'.html')
  $pdfPath=Join-Path $Paths.Reports ($baseName+'.pdf')
  $progress=if($Channel){(Get-PcConversationProgress $Channel).Percent}elseif($Overview -and @($Overview.conversations).Count){[int]$Overview.conversations[0].progress_estimate}else{0}
  $life=if($Channel){Get-PcLifecycleView $Channel}else{$null}
  $rows=''
  $micro=''
  if($Channel){
    foreach($m in @($Channel.macro_tasks)){
      $mp=Get-PcMacroProgress $m
      $rows += "<tr><td>$(ConvertTo-PcHtmlEncoded $m.title)</td><td>$($m.state)</td><td>$($mp.Percent)%</td><td>$(ConvertTo-PcHtmlEncoded $m.current_action)</td><td>$(ConvertTo-PcHtmlEncoded $m.next_step)</td></tr>"
      if($m.micro_tasks){
        $micro += "<h3>$(ConvertTo-PcHtmlEncoded $m.title)</h3><ul>"
        foreach($t in @($m.micro_tasks)){
          $tp=[int][math]::Round((Get-PcMicroCompletion $t)*100,0)
          $micro += "<li><b>$($t.state) $tp%</b> — $(ConvertTo-PcHtmlEncoded $t.title)"
          if($t.evidence){$micro += "<br><span class='muted'>preuve: $(ConvertTo-PcHtmlEncoded $t.evidence)</span>"}
          $micro += "</li>"
        }
        $micro += "</ul>"
      }
    }
  }
  $abc=''
  if($Channel -and $Channel.cahier_des_charges){
    $q=Get-PcRequirementCoverage $Channel
    $abc="<h2>Cahier des charges A+B+C</h2><p>Version $(ConvertTo-PcHtmlEncoded $Channel.cahier_des_charges.version) — couverture $($q.Percent)% — P0 ouvertes $($q.P0Open)</p><p>Dernier delta: $(ConvertTo-PcHtmlEncoded $Channel.cahier_des_charges.last_delta)</p>"
  }
  $html="<html><head><meta charset='utf-8'><style>body{font-family:Segoe UI,Arial;margin:28px;color:#111}table{border-collapse:collapse;width:100%}th,td{border:1px solid #bbb;padding:7px;vertical-align:top}th{background:#eee}.bar{height:16px;background:#ddd;border-radius:8px;overflow:hidden}.fill{height:100%;width:$progress%;background:#333}.muted{color:#666;font-size:90%}li{margin:6px 0}</style></head><body><h1>PC COMMAND</h1><p>Version $($Config.version) | $(Get-Date)</p><h2>$(ConvertTo-PcHtmlEncoded $convTitle)</h2><p>Progression estimee: <b>$progress%</b></p><div class='bar'><div class='fill'></div></div><p>Etat: <b>$(if($life){ConvertTo-PcHtmlEncoded $life.Label}else{'N/A'})</b></p><p>Etats observables uniquement; aucun raisonnement prive du modele n est expose.</p>$abc<h2>Macro-taches</h2><table><tr><th>Macro-tache</th><th>Etat</th><th>Avancement</th><th>En cours</th><th>Prochaine etape</th></tr>$rows</table><h2>Micro-taches condensees</h2>$micro</body></html>"
  [IO.File]::WriteAllText($htmlPath,$html,[Text.UTF8Encoding]::new($false))
  $pdfLines=New-Object System.Collections.Generic.List[string]
  $pdfLines.Add('PC COMMAND - RAPPORT DETAILLE')
  $pdfLines.Add(('Version: '+$Config.version+' | '+(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
  $pdfLines.Add(('Conversation: '+$convTitle))
  $pdfLines.Add(('Progression estimee: '+$progress+'%'))
  if($life){$pdfLines.Add(('Etat: '+$life.Label+' | '+$life.Detail))}
  $pdfLines.Add('')
  if($Channel){
    foreach($m in @($Channel.macro_tasks)){
      $mp=Get-PcMacroProgress $m
      $pdfLines.Add(('MACRO: '+$m.title+' | '+$m.state+' | '+$mp.Percent+'%'))
      if($m.current_action){$pdfLines.Add(('  En cours: '+$m.current_action))}
      if($m.next_step){$pdfLines.Add(('  Ensuite: '+$m.next_step))}
      foreach($t in @($m.micro_tasks|Select-Object -First 30)){
        $tp=[int][math]::Round((Get-PcMicroCompletion $t)*100,0)
        $pdfLines.Add(('    - '+$t.state+' '+$tp+'% | '+$t.title))
        if($t.evidence){$pdfLines.Add(('      preuve: '+$t.evidence))}
      }
      $pdfLines.Add('')
    }
  }
  $madePdf=$false
  try{New-PcSimplePdf $pdfPath @($pdfLines)|Out-Null;if(Test-Path $pdfPath){$madePdf=$true}}catch{}
  return [pscustomobject]@{Html=$htmlPath;Pdf=if($madePdf){$pdfPath}else{$null}}
}

function Export-PcReportToDrive {
  param([string]$Path)
  if(-not $Path -or -not(Test-Path $Path)){return [pscustomobject]@{Success=$false;Message='Rapport absent'}}
  $root=Find-PcDriveRoot
  if(-not $root){return [pscustomobject]@{Success=$false;Message='Google Drive local non detecte'}}
  $dest=Join-Path $root 'PC_COMMAND_STATE\REPORTS'
  New-Item -ItemType Directory -Force -Path $dest|Out-Null
  Copy-Item $Path (Join-Path $dest ([IO.Path]::GetFileName($Path))) -Force
  return [pscustomobject]@{Success=$true;Message=('Copie Drive: '+$dest)}
}


function Export-PcReportToDownloads {
  param([string]$Path)
  if(-not$Path -or -not(Test-Path $Path)){return [pscustomobject]@{Success=$false;Message='Rapport absent'}}
  $dest=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\PC_COMMAND'
  New-Item -ItemType Directory -Force -Path $dest|Out-Null
  $target=Join-Path $dest ([IO.Path]::GetFileName($Path))
  Copy-Item $Path $target -Force
  return [pscustomobject]@{Success=$true;Message=('Copie telechargements: '+$target);Path=$target}
}
