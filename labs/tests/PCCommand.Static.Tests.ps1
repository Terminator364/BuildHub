BeforeAll {
  $script:root=Resolve-Path (Join-Path $PSScriptRoot '..')
  $script:main=Get-Content (Join-Path $script:root 'pc-command\v5\PC_COMMAND_V5.ps1') -Raw
  $script:ui=Get-Content (Join-Path $script:root 'pc-command\v5\lib\ui.ps1') -Raw
  $script:cfg=Get-Content (Join-Path $script:root 'pc-command\v5\config.default.json') -Raw | ConvertFrom-Json
}

Describe 'PC Command controls' {
  It 'has a global Home action' { $script:main | Should -Match "\$k-eq'A'"; $script:ui | Should -Match '\[A\] Accueil' }
  It 'acknowledges every key path' { $script:main | Should -Match 'Set-PcInputAck'; $script:main | Should -Match 'Action: ' }
  It 'uses per-view action matrix' { $script:main | Should -Match 'Get-PcAllowedKeysForView' }
  It 'shows user preemption' { ($script:main+$script:ui) | Should -Match 'USER_PREEMPTED_BY_NEW_MESSAGE' }
  It 'keeps permanent process watcher disabled by default' { [bool]$script:cfg.local_observability.process_watcher | Should -BeFalse }
}
Describe 'PC Command RAM-first PowerShell policy' {
  It 'uses load-on-demand modules' { $script:cfg.powershell_runtime.modules | Should -Be 'load_on_demand' }
  It 'keeps CMD as bootstrap fallback only' { $script:cfg.powershell_runtime.cmd_role | Should -Be 'bootstrap_fallback_only' }
  It 'uses PSScriptAnalyzer and Pester gates' { [bool]$script:cfg.quality_gates.psscriptanalyzer_ci | Should -BeTrue; [bool]$script:cfg.quality_gates.pester_ci | Should -BeTrue }
}
