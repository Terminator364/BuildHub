function ConvertTo-PcPdfSafeText {
  param([string]$Text)
  if($null-eq$Text){return ''}
  return ($Text -replace '\\','\\' -replace '\(','\(' -replace '\)','\)')
}

function Split-PcPdfLine {
  param([string]$Text,[int]$Width=92)
  $out=New-Object System.Collections.Generic.List[string]
  $rest=if($null-eq$Text){''}else{[string]$Text}
  while($rest.Length-gt$Width){
    $cut=$Width
    $space=$rest.LastIndexOf(' ',[math]::Min($Width,$rest.Length-1))
    if($space-gt25){$cut=$space}
    $out.Add($rest.Substring(0,$cut).TrimEnd())
    $rest=$rest.Substring($cut).TrimStart()
  }
  $out.Add($rest)
  return @($out)
}

function New-PcTextPdf {
  param([string]$Path,[string[]]$Lines)
  $enc=[Text.Encoding]::GetEncoding(1252)
  $nl=[char]10
  $wrapped=New-Object System.Collections.Generic.List[string]
  foreach($line in @($Lines)){
    foreach($part in @(Split-PcPdfLine ([string]$line) 92)){$wrapped.Add($part)}
  }
  $perPage=48
  $pageCount=[math]::Max(1,[math]::Ceiling($wrapped.Count/[double]$perPage))
  $fontObj=3+(2*$pageCount)
  $objects=@{}
  $objects[1]='<< /Type /Catalog /Pages 2 0 R >>'
  $kids=New-Object System.Collections.Generic.List[string]
  for($i=0;$i-lt$pageCount;$i++){
    $pageObj=3+(2*$i)
    $contentObj=4+(2*$i)
    $kids.Add(($pageObj.ToString()+' 0 R'))
    $objects[$pageObj]='<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 '+$fontObj+' 0 R >> >> /Contents '+$contentObj+' 0 R >>'
    $chunk=@($wrapped|Select-Object -Skip ($i*$perPage) -First $perPage)
    $stream='BT'+$nl+'/F1 9 Tf'+$nl+'40 800 Td'+$nl
    foreach($line in $chunk){
      $stream+='('+(ConvertTo-PcPdfSafeText $line)+') Tj'+$nl+'0 -15 Td'+$nl
    }
    $stream+='ET'+$nl
    $len=$enc.GetByteCount($stream)
    $objects[$contentObj]='<< /Length '+$len+' >>'+$nl+'stream'+$nl+$stream+'endstream'
  }
  $objects[2]='<< /Type /Pages /Count '+$pageCount+' /Kids [ '+($kids -join ' ')+' ] >>'
  $objects[$fontObj]='<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'
  $maxObj=$fontObj
  $sb=New-Object Text.StringBuilder
  [void]$sb.Append('%PDF-1.4'+$nl)
  $offsets=@{0=0}
  for($n=1;$n-le$maxObj;$n++){
    $offsets[$n]=$enc.GetByteCount($sb.ToString())
    [void]$sb.Append(($n.ToString()+' 0 obj'+$nl+$objects[$n]+$nl+'endobj'+$nl))
  }
  $xref=$enc.GetByteCount($sb.ToString())
  [void]$sb.Append(('xref'+$nl+'0 '+($maxObj+1)+$nl))
  [void]$sb.Append(('0000000000 65535 f '+$nl))
  for($n=1;$n-le$maxObj;$n++){[void]$sb.Append((('{0:D10} 00000 n ' -f [int]$offsets[$n])+$nl))}
  [void]$sb.Append(('trailer'+$nl+'<< /Size '+($maxObj+1)+' /Root 1 0 R >>'+$nl+'startxref'+$nl+$xref+$nl+'%%EOF'+$nl))
  [IO.File]::WriteAllBytes($Path,$enc.GetBytes($sb.ToString()))
  return $Path
}