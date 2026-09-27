# PC COMMAND — PowerShell Capability Map

**Version cible:** v0.9.8  
**Source obligatoire:** `PC_COMMAND_POWERSHELL_REPOSITORIES_AUDIT_2026-09-26.pdf`  
**Politique:** native-first, zero-resident, load-on-demand, reversible, Windows 11 / 4 Go RAM.

## Etat terrain de reference

- Stable actuelle: **v0.9.7 field-proven**
- Windows PowerShell: **5.1.22621.3958**
- PowerShell 7 (`pwsh`): **absent — migration differee**
- WinGet: **present**
- Git: **present**
- Cmdlets natifs verifies: `Get-WinEvent`, `Get-ScheduledTask`, `Get-NetTCPConnection`, `Get-ComputerInfo`, `Test-NetConnection`
- Modules locaux: Pester 3.4.0 present; PSResourceGet, PSScriptAnalyzer, EventViewerX, PSWindowsUpdate, PSWriteHTML, powershell-yaml et ScheduledTaskManagement absents.
- Qualite projet: PSScriptAnalyzer + Pester executes **dans GitHub CI a la demande**, pas comme services locaux.
- RAM stable post-deploiement v0.9.7 observee: ~101.6–107.4 MB; probe v0.9.8 observe avec le viewer stable unique ~97.6 MB.
- Aucun module/depot externe installe par v0.9.8.

## Cartographie capacites

| Capacite | Existant maintenant | Ecart utile | Depot/source potentiel | RAM | Risque | Redondance | Action |
|---|---|---|---|---|---|---|---|
| Runtime PowerShell | Windows PowerShell 5.1 | Evaluer PS7 seulement si gain mesure | PowerShell/PowerShell | runtime | faible | faible | **CORE**, conserver 5.1 tant que benchmark PS7 non concluant |
| Gestion modules | PowerShellGet legacy disponible via OS | Pinning moderne si module externe justifie | PowerShell/PSResourceGet | ephemere | faible | moyenne | **ON-DEMAND**, ne pas installer maintenant |
| Analyse statique | CI existante | Aucun gap runtime | PowerShell/PSScriptAnalyzer | CI only | faible | aucune | **CORE CI**, ne pas charger dans viewer |
| Tests | CI Pester moderne; local Pester 3.4 | Aucun gap runtime | pester/Pester | CI only | faible | aucune | **CORE CI**, CI fait autorite |
| Paquets Windows | WinGet present | Fallback portable exceptionnel | microsoft/winget-cli; Scoop; Chocolatey | ephemere | moyen | forte | WinGet **CORE**; Scoop/Choco fallback |
| Logs Windows | Get-WinEvent natif | Requetes typees/volume si besoin prouve | EvotecIT/EventViewerX | ephemere | faible | moyenne | natif d'abord; EventViewerX **ON-DEMAND** |
| Windows Update | primitives Windows/WinGet partielles | Workflow Windows Update specialise | mgajda83/PSWindowsUpdate | ephemere | moyen | moyenne | **ON-DEMAND L2/L3** |
| Reseau | Test-NetConnection/Get-NetTCPConnection | Diagnostic humain avance | NETworkManager; PsNetTools; pstop | ephemere | faible-moyen | forte | natif d'abord; outils externes ponctuels |
| Taches planifiees | Get-ScheduledTask + cmdlets ScheduledTasks | Patterns declaratifs/idempotents | ScheduledTaskManagement | zero hors action | moyen | forte | **SOURCE-ONLY** |
| Rapports HTML/PDF | moteur PC Command pur PowerShell field-proven | XLSX seulement si besoin futur | PSWriteHTML; ImportExcel | generation | faible | forte pour HTML | garder moteur actuel; ImportExcel ON-DEMAND |
| YAML | JSON natif deja canonique | Aucun besoin YAML courant | cloudbase/powershell-yaml | ephemere | faible | forte | **SOURCE-ONLY**, ne pas ajouter |
| API locale | aucune API persistante requise | aucun gap demontre | Badgerati/Pode | resident | moyen | — | **REJECT maintenant** |
| Monitoring resident | on-demand natif | aucun besoin agent permanent | Icinga; PSNetMon; PowershellMonitoring | resident potentiel | moyen | forte | **SOURCE-ONLY/REJECT** |
| Debloat/tweaks | non integre | aucune execution globale autorisee | WinUtil; Sophia; Win11Debloat; Windows-Optimize-Debloat | zero si non lance | eleve | tres forte | **SOURCE-ONLY**, fonctions atomiques seulement |
| Reparation systeme | primitives natives | orchestration L3 eventuelle | repairtools; PathForge | ephemere | eleve | moyenne | **SOURCE-ONLY**, rollback obligatoire |
| Build orchestration | GitHub Actions + scripts simples | seulement si graphe build devient complexe | Invoke-Build; psake | build only | faible | forte | Invoke-Build ON-DEMAND; psake REJECT redondant |
| Packaging EXE | script/TUI fonctionne | aucun gap RAM | PS2EXE | aucun gain garanti | moyen | — | **REJECT comme optimisation RAM** |
| Ergonomie shell | TUI PC Command propre | aucun besoin prompt/theme | PSReadLine; posh-git; oh-my-posh; ConsoleGuiTools | interactif | faible | forte | hors runtime; mostly SOURCE-ONLY/REJECT |

## Lot n°1 retenu — v0.9.8

1. Catalogue machine `powershell-sources.json` contenant **41 sources** et leur classification.
2. Probe local **lecture seule**, cache court, basé sur `Get-Command` / `Get-Module -ListAvailable`.
3. Vue Sources: moteur, WinGet/Git, cmdlets natives, compte des classifications.
4. Vue Sante: resume PowerShell compact.
5. Aucun `Install-Module`, `Install-PSResource`, clone massif, watcher ou service.
6. PSScriptAnalyzer/Pester restent des gates CI ephemeres.

## Classification v0.9.8

- **CORE (4):** PowerShell/PowerShell; PowerShell/PSScriptAnalyzer; pester/Pester; microsoft/winget-cli.
- **ON-DEMAND (6):** PowerShell/PSResourceGet; EvotecIT/EventViewerX; mgajda83/PSWindowsUpdate; dfinke/ImportExcel; nightroman/Invoke-Build; jdhitsolutions/PSScriptTools.
- **SOURCE-ONLY (20):** voir `v5/powershell-sources.json`.
- **EXTERNAL-TOOL (4):** ScoopInstaller/Scoop; chocolatey/choco; BornToBeRoot/NETworkManager; psmux/pstop.
- **REJECT (7):** Badgerati/Pode; dahlbyk/posh-git; psake/psake; MScholtes/PS2EXE; PowerShell/ConsoleGuiTools; JanDeDobbeleer/oh-my-posh; oazabir/PowershellMonitoring.

## Gates avant promotion

- 41/41 entrees valides.
- Aucun installateur runtime.
- Aucun nouveau processus resident.
- PSScriptAnalyzer vert.
- Pester vert.
- Tests regression v0.9.7 verts.
- Smoke MBMPC vert.
- Vue Sources lisible.
- RAM viewer <=150 MB; objectif: pas d'augmentation idle mesurable due au catalogue/probe.
- Stable v0.9.7 conservee comme rollback tant que v0.9.8 n'est pas field-proven.
