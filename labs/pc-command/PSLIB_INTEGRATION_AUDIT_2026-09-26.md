# PC COMMAND — PSLIB INTEGRATION AUDIT — 2026-09-26

## Source lue intégralement
`PC_COMMAND_POWERSHELL_REPOSITORIES_AUDIT_2026-09-26.pdf` (Drive id `1MrZfxDIzZowqICey1uS4S2hmq3aNFvnK`).

Architecture gelée reprise sans la réinterpréter:
- PowerShell = moteur principal.
- CMD = bootstrap/fallback uniquement.
- cmdlets Windows natives avant dépendances externes.
- modules chargés à la demande.
- pas de clone/import massif.
- pas de watcher/service/dashboard permanent sans nécessité démontrée.
- L0 READ et L1 SAFE automatisables; L2/L3 avec contrôle/rollback adapté.
- fonctions importées atomiques, réversibles/idempotentes si possible.
- PSScriptAnalyzer + Pester avant changements sensibles.

## Etat réel PC Command au moment de l'audit
- PC local: Windows PowerShell **5.1.22621.3958**.
- `pwsh.exe`: **absent**.
- Pester local détecté: **3.4.0**.
- PSScriptAnalyzer local: **absent**.
- Runtime local observé: PC COMMAND **v0.9.1**, viewer ~115 MB au contrôle.
- Branche stable BuildHub: **v0.9.2**.
- Politique retenue: ne pas installer PowerShell 7 ou des modules système sur le PC avant test réversible; déplacer les gates lourdes vers GitHub CI.

## Revalidation GitHub du lot prioritaire
Métadonnées relues via GitHub le 26/09/2026 avant intégration.

| Dépôt | Archivé | Licence API | Push observé | Décision actuelle |
|---|---|---|---|---|
| PowerShell/PowerShell | non | MIT | 2026-09-25 | référence runtime; migration pwsh différée |
| PowerShell/PSResourceGet | non | MIT | 2026-09-21 | différé runtime; pas requis pour v0.9.3 |
| PowerShell/PSScriptAnalyzer | non | MIT | 2026-09-22 | **intégration CI uniquement** |
| pester/Pester | non | NOASSERTION API | 2026-09-24 | **intégration CI uniquement**; licence à vérifier dans le dépôt avant vendoring |
| microsoft/winget-cli | non | MIT | 2026-09-26 | disponible comme L2 paquet; aucun changement système automatique |
| fleschutz/PowerShell | non | CC0-1.0 | 2026-09-08 | catalogue de primitives; aucune exécution en bloc |
| EvotecIT/EventViewerX | non | MIT | 2026-09-22 | différé; cmdlets natives logs d'abord |
| mgajda83/PSWindowsUpdate | non | MIT | 2025-06-16 | différé L2; Windows Update natif/lecture d'abord |
| EvotecIT/PSWriteHTML | non | MIT | 2026-09-07 | différé; rapports actuels restent sans dépendance |
| theohbrothers/ScheduledTaskManagement | non | Apache-2.0 | 2024-09-08 | différé; ScheduledTasks natif d'abord |
| cloudbase/powershell-yaml | non | Apache-2.0 | 2026-07-07 | différé; JSON natif reste préféré |
| Badgerati/Pode | non | MIT | 2026-09-21 | **non retenu** tant qu'aucune API locale persistante n'est indispensable |

## Lot 1 exact intégré
1. **PSScriptAnalyzer** dans GitHub Actions, scope CI seulement.
2. **Pester** dans GitHub Actions, scope CI seulement.
3. **Aucune installation locale** sur le PC.
4. Désactivation par défaut du watcher WMI de processus dans PC Command; observation locale passe en mode à la demande.
5. Maintien du runtime local actuel tant qu'une migration `pwsh` n'a pas de benchmark RAM/compatibilité/rollback.

## Tests / rollback
- Parse PowerShell.
- PSScriptAnalyzer Severity Error.
- Tests existants PC Command.
- Pester assertions statiques.
- Smoke runtime avant promotion.
- Branch candidate séparée de `pc-command/stable`.
- Aucune promotion automatique vers stable si P0 regression ouverte.
- Rollback: la branche stable et les backups locaux restent la référence.

## Décision
Le lot 1 n'augmente pas l'empreinte idle du PC: les nouveaux outils de qualité s'exécutent sur GitHub CI, pas dans le viewer local.
