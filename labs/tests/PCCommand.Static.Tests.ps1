$root=Resolve-Path (Join-Path $PSScriptRoot '..')
$main=Get-Content (Join-Path $root 'pc-command\v5\PC_COMMAND_V5.ps1') -Raw
$ui=Get-Content (Join-Path $root 'pc-command\v5\lib\ui.ps1') -Raw
$cfg=Get-Content (Join-Path $root 'pc-command\v5\config.default.json') -Raw | ConvertFrom-Json

Describe 'PC Command controls' {
  It 'has a global Home action' { $main | Should -Match "\$k-eq'A'"; $ui | Should -Match '\[A\] Accueil' }
  It 'acknowledges every key path' { $main | Should -Match 'Set-PcInputAck'; $main | Should -Match 'Action: ' }
  It 'uses per-view action matrix' { $main | Should -Match 'Get-PcAllowedKeysForView' }
  It 'shows user preemption' { ($main+$ui) | Should -Match 'USER_PREEMPTED_BY_NEW_MESSAGE' }
  It 'keeps permanent process watcher disabled by default' { [bool]$cfg.local_observability.process_watcher | Should -BeFalse }
}
Describe 'PC Command RAM-first PowerShell policy' {
  It 'uses load-on-demand modules' { $cfg.powershell_runtime.modules | Should -Be 'load_on_demand' }
  It 'keeps CMD as bootstrap fallback only' { $cfg.powershell_runtime.cmd_role | Should -Be 'bootstrap_fallback_only' }
  It 'uses PSScriptAnalyzer and Pester gates' { [bool]$cfg.quality_gates.psscriptanalyzer_ci | Should -BeTrue; [bool]$cfg.quality_gates.pester_ci | Should -BeTrue }
}
