# PC COMMAND — Cahier des charges canonique A+B+C

Version cahier: ABC-2026-09-26.6  
Statut: LIVING / APPEND-AND-REFINE  
Regle: **A + B + C -> MERGE + REFINE + PRESERVE**.

Ce document est le socle durable. Chaque message utilisateur pertinent ajoute un delta; il ne remplace pas silencieusement les exigences precedentes. Une exigence n'est retiree que sur demande explicite ou si une nouvelle directive la remplace clairement.

## A — Besoin / promesse utilisateur

### A1. Produit
PC COMMAND est un **logiciel**, pas une simple console de debug. Il doit rester ultra-leger et utiliser PowerShell/console comme interface principale afin de convenir au PC 4 Go.

### A2. Experience d'usage
- Un raccourci unique sur le Bureau ouvre PC COMMAND.
- L'utilisateur doit comprendre immediatement: **est-ce que ca travaille, sur quoi, depuis combien de temps, avec quel niveau de preuve, quelle prochaine etape, quel blocage**.
- L'interface doit etre humaine, lisible, detaillee mais condensee.
- Les touches disponibles changent selon la vue.
- Accueil, conversation, macro-tache, micro-taches, chronologie, sources, local, parametres, cahier A+B+C, rapports.
- Une animation/indicateur de vie doit montrer que le moteur tourne sans forcer un redraw complet chaque seconde.
- Rafraichissement visuel cible: 10 s. Calcul interne et synchro: 5 s.
- Mode offline: afficher le dernier etat fiable et son age, sans inventer une activite.

### A3. Multi-conversations
- Jusqu'a 10 conversations connectees simultanement.
- Chaque conversation a un identifiant stable, un code court et son propre flux.
- Une conversation ne doit pas ecraser l'etat d'une autre.
- Une conversation peut contenir jusqu'a 10 macro-taches actives visibles/prioritaires.
- Les micro-taches **ne sont pas limitees a 10 ni a 1000** dans l'historique logique; l'ecran les condense en groupes/actions utiles.
- Les micro-taches detaillees sont affichees a la demande; l'accueil reste leger.

### A4. Moteur de suivi
- Chaque nouveau message utilisateur pertinent est un delta de portee.
- Nouvelle finalite -> macro-tache; nouvelle etape -> micro-tache; correction/feedback -> mise a jour de portee.
- La progression est recalculee quand le denominateur change; elle peut baisser si de nouvelles taches sont ajoutees.
- Le temps ecoule seul ne fait jamais progresser artificiellement une tache.
- DONE exige une preuve/resultat observable.
- Le moteur distingue progression, fiabilite/couverture de preuves, fraicheur, risque et ETA.
- ETA uniquement lorsque la portee et la pente sont suffisamment stables.

### A5. Statut de conversation / tour
Etats observables:
- USER_MESSAGE_RECEIVED
- ASSISTANT_PROCESSING
- TOOL_RUNNING
- WAITING_EXTERNAL
- ASSISTANT_RESPONDED
- PAUSED
- USER_STOPPED_EXPLICIT
- INTERRUPTED_INFERRED
- SECURITY_CHECK_REPORTED
- NETWORK_ERROR
- RATE_LIMIT_WAIT
- OFFLINE
- RECOVERING
- COMPLETED

Le moteur doit montrer **TRAVAIL EN COURS** tant qu'un lease de travail est valide. A l'expiration d'un lease, il doit afficher ETAT INDETERMINE / SIGNAL ANCIEN, jamais inventer TERMINE ou SILENCIEUX.

PC COMMAND ne montre jamais le raisonnement prive/chain-of-thought; il affiche uniquement phase, duree, outils, evenements, resultats et preuves observables.

### A6. Sources et synchronisation
Source principale: conversations ChatGPT instrumentees par PCCONNECT. Adaptateurs possibles:
- GitHub
- Google Drive
- Telegram/ChatGPT Delivery
- TLIB
- Web/YouTube
- WMI Windows
- Desktop Commander

Aucun mot de passe Telegram ou autre secret ne doit etre demande ni stocke. Utiliser les connecteurs/autorisations officielles deja disponibles quand ils existent.

Desktop Commander est un adaptateur opportuniste, jamais une dependance canonique du moteur.

### A7. RAM / performance
- Budget total cible PC COMMAND: <=150 MB avec jusqu'a 9 conversations alimentees.
- Une seule instance viewer.
- Pas un processus par conversation.
- Overview leger; detail charge uniquement dans la vue concernee.
- Historique borne/compresse.
- Pas de navigateur embarque.
- Pas de stack lourde (Kafka, Elastic, Grafana, AI local resident, etc.).
- Google Drive Desktop doit rester actif.
- Les mesures RAM reelles sur MBMPC priment sur les estimations CI.

### A8. Auto-update / recovery
- Version visible.
- Mise a jour continue via code GitHub, avec manifest versionne.
- Telechargement en staging, verification hash/readback, backup, bascule atomique.
- Conserver seulement quelques backups.
- Si l'update echoue, lancer la derniere version locale valide.
- Single-instance pour eviter les doublons.
- Redemarrage/reouverture reprend le cache et le dernier etat fiable.

### A9. Rapports / Drive / mobile
- Bouton rapport detaille.
- Export HTML/PDF local.
- Copie optionnelle vers le dossier Drive PC_COMMAND_STATE/REPORTS.
- Drive PC_COMMAND_STATE contient au minimum REPORTS, CHECKPOINTS, EXPORTS et le cahier durable.
- Le dossier Drive rend les sorties accessibles depuis le telephone sans creer un second runtime mobile lourd.

## B — Architecture / recherche / reemploi

### B1. Event-driven
Schema evenementiel inspire de CloudEvents: id, source, type, time, subject, payload. ID + source doivent permettre la deduplication.

### B2. Correlation
trace_id = conversation; span_id = operation; parent_span_id = parent. Inspiration W3C Trace Context / OpenTelemetry.

### B3. Reconstruction
Modele event-sourcing/process-mining:
- log append-only;
- projection d'etat;
- detection des changements de portee;
- reprise depuis checkpoints;
- conformance entre plan annonce et evenements observes.

### B4. Local-first
- Cache local canonique pour l'affichage.
- Transport reseau pour synchroniser, mais le viewer doit rester utilisable sans reseau.
- Repo GitHub prive PC-COMMAND-STATE pour les etats runtime.
- Repo BuildHub public pour le code/tests.
- Drive pour rapports/checkpoints utilisateur, pas pour chaque heartbeat.

### B5. Cadence
- calcul moteur: 5 s;
- synchro Internet: 5 s;
- rendu ecran: 10 s;
- titre/indicateur vivant: ~1 s local uniquement;
- pas de commit/heartbeat GitHub toutes les 5 s si rien n'a change;
- publier sur **changement semantique**, pas sur simple passage du temps.

### B6. Cahier vivant
Chaque conversation PCCONNECT doit publier en debut de tour:
- delta A: besoin/contrainte;
- delta B: consequences techniques/recherche/tests;
- delta C: feedback terrain/preuves.
Puis publier resultats/evidences avant la reponse finale.

## C — Terrain / preuves / retours integres

- Le premier tableau GUI etait trop lourd/peu lisible -> PowerShell retenu.
- Console brute Desktop Commander trop technique -> TUI humaine requise.
- Rafraichissement 5 s trop rapide a lire -> affichage 10 s, calcul/sync 5 s.
- Faux statut SILENCIEUX observe -> remplace par lease + fraicheur + etat indetermine.
- Ecran quasi vide/noir observe sur v0.5.1 -> rendu responsive et fail-safe integres en v0.6.x.
- V0.6.0 affiche correctement accueil, Drive actif, transport prive et statut TRAVAIL EN COURS.
- Viewer observe autour de 89 MB sur MBMPC, sous le plafond 150 MB.
- Google Drive doit rester actif.
- Le PC souffre d'un contexte RAM faible; toute nouvelle fonction doit justifier son cout memoire.
- Les incidents historiques rapportes au support OpenAI (securite, desynchronisation, interruption, quotas) deviennent des exigences de checkpoint/reprise et de statut honnete.

## Gates de qualite obligatoires

1. STATIC — parse PowerShell.
2. SCHEMA — config/event/state valides.
3. UNIT — progression, scope expansion, lease, ABC coverage.
4. CI — GitHub Actions vertes.
5. RUNTIME — lancement sur MBMPC.
6. VISUAL — capture lisible.
7. RESOURCE — RAM mesuree.
8. MULTI — simulation/terrain plusieurs conversations sans collision.
9. OFFLINE — cache fonctionne sans Internet.
10. UPDATE — staging/hash/backup/rollback.
11. REPORT — PDF/HTML genere.
12. DRIVE — rapport/copied checkpoint accessible.
13. RECOVERY — reouverture reprend l'etat.
14. FIELD — feedback utilisateur integre au cahier, pas perdu.

## Definition de fini

PC COMMAND n'est pas considere fini tant que les gates P0 (statut fiable, cahier vivant, progression adaptative, multi-conversations, RAM, offline, single-instance, update/recovery) ne sont pas prouvees sur le PC cible.
