$script:PcActionPolicyVersion='pc.command.action.policy.v1'

function Get-PcBoolProperty {
  param($Object,[string]$Name,[bool]$Default=$false)
  if($null-eq$Object){return $Default}
  $p=$Object.PSObject.Properties[$Name]
  if($p){return [bool]$p.Value}
  return $Default
}

function Get-PcStringProperty {
  param($Object,[string]$Name,[string]$Default='')
  if($null-eq$Object){return $Default}
  $p=$Object.PSObject.Properties[$Name]
  if($p -and $null-ne$p.Value){return [string]$p.Value}
  return $Default
}

function Test-PcActionPolicy {
  param($Action)
  $name=Get-PcStringProperty $Action 'Name' 'unnamed'
  $level=(Get-PcStringProperty $Action 'Level' '').ToUpperInvariant()
  $bounded=Get-PcBoolProperty $Action 'Bounded'
  $readOnly=Get-PcBoolProperty $Action 'ReadOnly'
  $modifiesSystem=Get-PcBoolProperty $Action 'ModifiesSystem'
  $preconditions=Get-PcBoolProperty $Action 'Preconditions'
  $rollback=Get-PcBoolProperty $Action 'Rollback'
  $backup=Get-PcBoolProperty $Action 'Backup'
  $postVerification=Get-PcBoolProperty $Action 'PostVerification'
  $expectedChanges=Get-PcBoolProperty $Action 'ExpectedChanges'
  $manualApproval=Get-PcBoolProperty $Action 'ManualApproval'
  $externalSource=Get-PcBoolProperty $Action 'ExternalSource'
  $externalSourcePinned=Get-PcBoolProperty $Action 'ExternalSourcePinned'
  $remotePipeExecute=Get-PcBoolProperty $Action 'RemotePipeExecute'
  $globalPreset=Get-PcBoolProperty $Action 'GlobalPreset'

  $missing=New-Object System.Collections.Generic.List[string]
  $reasons=New-Object System.Collections.Generic.List[string]
  $decision='DENY'
  $auto=$false

  if($remotePipeExecute){
    $reasons.Add('remote pipe-to-execute interdit')
    return [pscustomobject]@{Name=$name;Level=$level;Decision='DENY';Auto=$false;Missing=@();Reasons=@($reasons);Policy=$script:PcActionPolicyVersion}
  }
  if($globalPreset){
    $reasons.Add('preset global interdit')
    return [pscustomobject]@{Name=$name;Level=$level;Decision='DENY';Auto=$false;Missing=@();Reasons=@($reasons);Policy=$script:PcActionPolicyVersion}
  }
  if($externalSource -and -not$externalSourcePinned){
    $missing.Add('ExternalSourcePinned')
  }

  switch($level){
    'L0' {
      if(-not$readOnly){$missing.Add('ReadOnly')}
      if(-not$bounded){$missing.Add('Bounded')}
      if($modifiesSystem){$reasons.Add('L0 ne doit pas modifier le systeme')}
      if($missing.Count-eq0 -and $reasons.Count-eq0){
        $decision='ALLOW_AUTO';$auto=$true;$reasons.Add('lecture bornee')
      }
    }
    'L1' {
      if(-not$bounded){$missing.Add('Bounded')}
      if($modifiesSystem){$reasons.Add('L1 ne doit pas modifier le systeme de facon importante')}
      if($missing.Count-eq0 -and $reasons.Count-eq0){
        $decision='ALLOW_AUTO';$auto=$true;$reasons.Add('operation sure et bornee')
      }
    }
    'L2' {
      if(-not$preconditions){$missing.Add('Preconditions')}
      if(-not$rollback){$missing.Add('Rollback')}
      if(-not$postVerification){$missing.Add('PostVerification')}
      if(-not$expectedChanges){$missing.Add('ExpectedChanges')}
      if($missing.Count-eq0){
        $decision='ALLOW_GATED';$auto=$false;$reasons.Add('modification autorisee uniquement avec gates et rollback')
      }
    }
    'L3' {
      if(-not$preconditions){$missing.Add('Preconditions')}
      if(-not$rollback){$missing.Add('Rollback')}
      if(-not$backup){$missing.Add('Backup')}
      if(-not$postVerification){$missing.Add('PostVerification')}
      if(-not$expectedChanges){$missing.Add('ExpectedChanges')}
      if(-not$manualApproval){$missing.Add('ManualApproval')}
      if($missing.Count-eq0){
        $decision='REQUIRE_EXPLICIT_APPROVAL';$auto=$false;$reasons.Add('action systeme profonde jamais automatique')
      }
    }
    default {
      $missing.Add('ValidLevel')
      $reasons.Add('niveau inconnu')
    }
  }

  if($missing.Count-gt0 -and $decision-ne'DENY'){$decision='DENY';$auto=$false}
  if($missing.Count-gt0 -and $decision-eq'DENY'){$reasons.Add('gates manquants')}

  return [pscustomobject]@{
    Name=$name
    Level=$level
    Decision=$decision
    Auto=$auto
    Missing=@($missing)
    Reasons=@($reasons)
    Policy=$script:PcActionPolicyVersion
  }
}

function Get-PcActionPolicySummary {
  return [pscustomobject]@{
    Version=$script:PcActionPolicyVersion
    L0='READ: auto si lecture seule + borne'
    L1='SAFE: auto si borne et sans modification systeme importante'
    L2='MODIFY: preconditions + expected changes + rollback + verification'
    L3='SYSTEM: L2 + backup + approbation explicite; jamais automatique'
    DeniedPatterns=@('remote pipe-to-execute','global debloat/tweak presets')
  }
}
