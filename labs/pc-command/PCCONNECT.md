# PCCONNECT v1 — protocole multi-conversations PC COMMAND

But: permettre a une conversation ChatGPT de publier son etat dans PC COMMAND avec zero dollar d'infrastructure.

## Commande utilisateur
`PCCONNECT`

## Regle de connexion
La conversation lit le fichier canonique `labs/pc-command/feed-v3.json` dans `Terminator364/BuildHub`, branche `lab/pc-command-browser-20260926`.

Elle cree ou reutilise une entree `conversation`, puis ne modifie que cette entree apres avoir relu le SHA courant. En cas de conflit GitHub: relire, fusionner, reessayer.

## Detection de taches
A chaque nouveau message utilisateur:
- nouvelle finalite autonome => nouvelle macro-tache;
- etape necessaire a une macro existante => nouvelle micro-tache;
- correction/feedback => evenement + ajustement de la micro-tache concernee;
- resultat prouve => progression + evidence;
- blocage => state BLOCKED;
- nouvelle portee => le denominateur augmente et le pourcentage peut baisser.

Maximum: 10 macro-taches actives par conversation. Au-dela, placer les nouvelles en QUEUED ou demander de prioriser.

## Evenements minimaux
Types recommandes, inspires de CloudEvents:
- conversation.connected
- task.added
- task.started
- task.progress
- task.completed
- task.blocked
- scope.expanded
- evidence.added
- tool.started
- tool.completed
- tool.failed
- conversation.paused
- conversation.resumed

Chaque evenement a au minimum: `at`, `type`, `summary`.

## Calcul
Micro-tache: completion 0.0..1.0.
Macro-tache: somme(weight * completion) / somme(weight).
Conversation: somme(macro_weight * macro_progress) / somme(macro_weight).
Le pourcentage est une estimation d'avancement, jamais une probabilite de reussite.

## Fiabilite
La confiance du suivi depend des taches avec evidence recente. Une tache ACTIVE sans nouvel evenement devient STALE dans l'interface; son pourcentage n'est pas invente.

## Limite structurelle importante
PC COMMAND ne peut pas espionner automatiquement toutes les conversations ChatGPT. Une conversation doit etre reliee par `PCCONNECT` (ou par un futur bootstrap/QR). Une fois reliee, elle publie les changements du flux dans le fichier partage.

## Local
Le PowerShell local:
- recalcule chaque seconde sans reseau;
- synchronise GitHub toutes les 10 secondes;
- observe les processus Windows localement sans consommer d'appel Remote Desktop Commander;
- fonctionne sur cache si Internet tombe.
