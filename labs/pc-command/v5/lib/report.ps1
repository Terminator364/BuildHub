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
  $htmlPath=Join-Path $Paths.Reports ("PC_COMMAND_REPORT_$stamp.html")
  $pdfPath=Join-Path $Paths.Reports ("PC_COMMAND_REPORT_$stamp.pdf")
  $convTitle=if($Channel){[string]$Channel.label}else{'PC COMMAND'}
  $progress=if($Channel){(Get-PcConversationProgress $Channel).Percent}elseif($Overview -and @($Overview.conversations).Count){[int]$Overview.conversations[0].progress_estimate}else{0}
  $life=if($Channel){Get-PcLifecycleView $Channel}else{$null}
  $rows=''
  if($Channel){
    foreach($m in @($Channel.macro_tasks)){
      $mp=Get-PcMacroProgress $m
      $rows += "<tr><td>$(ConvertTo-PcHtmlEncoded $m.title)</td><td>$($m.state)</td><td>$($mp.Percent)%</td><td>$(ConvertTo-PcHtmlEncoded $m.current_action)</td><td>$(ConvertTo-PcHtmlEncoded $m.next_step)</td></tr>"
    }
  }
  $html="<html><head><meta charset='utf-8'><style>body{font-family:Segoe UI,Arial;margin:28px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #bbb;padding:7px;vertical-align:top}th{background:#eee}.bar{height:16px;background:#ddd}.fill{height:100%;width:$progress%;background:#333}</style></head><body><h1>PC COMMAND</h1><p>Version $($Config.version) | $(Get-Date)</p><h2>$(ConvertTo-PcHtmlEncoded $convTitle)</h2><p>Progression estimee: <b>$progress%</b></p><div class='bar'><div class='fill'></div></div><p>Etat: <b>$(if($life){ConvertTo-PcHtmlEncoded $life.Label}else{'N/A'})</b></p><p>Etats observables uniquement; aucun raisonnement prive du modele n est expose.</p><table><tr><th>Macro-tache</th><th>Etat</th><th>Avancement</th><th>En cours</th><th>Prochaine etape</th></tr>$rows</table><p>Octets observes cette session: $script:PcSessionRxBytes</p></body></html>"
  [IO.File]::WriteAllText($htmlPath,$html,[Text.UTF8Encoding]::new($false))
  $edge=@('C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe','C:\Program Files\Microsoft\Edge\Application\msedge.exe')|Where-Object{Test-Path $_}|Select-Object -First 1
  $madePdf=$false
  if($edge){
    try{
      $p=Start-Process $edge -ArgumentList @('--headless','--disable-gpu',("--print-to-pdf=$pdfPath"),("file:///"+($htmlPath -replace '\','/'))) -PassThru -WindowStyle Hidden
      if($p.WaitForExit(30000) -and (Test-Path $pdfPath)){$madePdf=$true}
    }catch{}
  }
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
