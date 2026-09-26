# PCCONNECT v2 — connecter une conversation ChatGPT a PC COMMAND

Commande utilisateur:

```
PCCONNECT|v2|pc=MBMPC|repo=Terminator364/BuildHub|branch=lab/pc-command-v070|protocol=labs/pc-command/PCCONNECT.md|slot=AUTO|max=10
```

## Mission de la conversation qui recoit ce code
1. Utiliser le connecteur GitHub deja autorise sur le compte.
2. Lire ce protocole et `labs/pc-command/feed-v3.json`.
3. Ne jamais supprimer/modifier le flux d'une autre conversation.
4. Si la conversation n'a pas encore d'entree:
   - verifier que moins de 10 conversations sont actives;
   - creer un `conversation_id` stable et un `short_code`;
   - ajouter son objectif courant et ses macro-taches connues.
5. A chaque message utilisateur, traiter le message comme un **delta de portee**:
   - nouvelle finalite/delivrable -> nouvelle macro-tache;
   - nouvelle etape -> micro-tache;
   - correction/feedback -> evenement et modification de la tache concernee;
   - abandon explicite -> state CANCELLED;
   - resultat prouve -> evidence + progression;
   - echec/blocage -> BLOCKED.
6. Maximum 10 macro-taches actives dans ce flux. Au-dela: QUEUED/priorisation.
7. Avant chaque ecriture GitHub, relire le SHA courant; merger uniquement son delta.
8. En cas de conflit, relire/rejouer idempotemment.
9. Mettre a jour `last_update`, `last_event`, `current_action`, `last_success`, `next_step`, `blocker` et les evenements.
10. Ne pas faire de commit de heartbeat sans changement: publier seulement lors d'un changement de sens.

## Semantique
Conversation -> macro-taches -> micro-taches -> preuves/evenements.

Progression:
- micro: 0..1;
- macro: moyenne ponderee des micro-taches;
- conversation: moyenne ponderee des macro-taches;
- nouvelle tache = nouveau denominateur = recalcul pouvant faire baisser le %.

Ce pourcentage est une **estimation d'avancement**, pas une probabilite de succes.

## Sources
Quand cette conversation utilise GitHub, Drive, Telegram, YouTube/Web, TLIB ou Desktop Commander, elle doit reporter l'action dans son flux:
- `tool.started`
- `tool.completed`
- `tool.failed`
- `evidence.added`

Le moteur local peut aussi observer certains processus Windows. Il ne faut jamais declarer une source comme observee si aucun evenement/preuve n'est disponible.

## Regle A+B+C
- A = besoin/promesse utilisateur;
- B = recherche/architecture/reemploi;
- C = terrain/feedback/preuves.
Toujours MERGE + REFINE + PRESERVE.

## Fin / pause
Si l'utilisateur quitte ou change de sujet:
- conversation.paused si travail inacheve;
- conversation.completed seulement si toutes les macro-taches requises sont closes ou explicitement abandonnees.

## PCCONNECT v3 - instrumentation des tours
- Debut de chaque tour: publier turn.started et ASSISTANT_PROCESSING.
- Avant un lot d outils: TOOL_RUNNING + last_signal_at.
- Apres le lot: resultat, preuve, progression et blocage.
- Avant reponse: ASSISTANT_RESPONDED + turn.completed + overview.json.
- Une longue operation reste TRAVAIL EN COURS jusqu a 15 min sans signal; 15-30 min = signal ancien; au-dela = interruption possible.
- A+B+C a chaque delta: besoin/promesse + recherche/architecture + terrain/feedback; MERGE + REFINE + PRESERVE.


## Regle de cahier vivant A+B+C
Chaque message utilisateur pertinent pour le projet devient un delta de cahier des charges:
- A: besoin, contrainte, comportement souhaite, livrable;
- B: consequence d'architecture, recherche, reemploi ou test;
- C: retour terrain, capture, bug, mesure, preuve.

La conversation publie ce delta au debut du tour, puis publie les preuves et resultats avant la reponse finale. Les anciennes exigences sont preservees sauf retrait explicite de l'utilisateur.

## Statut de travail
Au debut d'un travail significatif, publier ASSISTANT_PROCESSING avec started_at, last_signal_at et lease_until.
Le PC local mesure le temps ecoule sans heartbeat distant permanent.
Un lease expire ne signifie jamais TERMINE: l'etat devient INDETERMINE jusqu'a une nouvelle preuve.
Ne jamais exposer le raisonnement prive; publier uniquement phase, outils, resultats et preuves observables.


## Feedback Ledger obligatoire

Avant BUILD sur chaque message utilisateur pertinent:

1. Lire:
   - `pc-command/feedback/feedback-index.json`
   - `pc-command/feedback/feedback-ledger.jsonl`
   dans le depot prive `Terminator364/PC-COMMAND-STATE`.
2. Produire le delta:
   - A = besoin/promesse/contrainte/livrable;
   - B = recherche, innovation, contre-audit, consequence architecture;
   - C = retour terrain, capture, bug, critique, mesure.
3. Creer exactement une nouvelle entree idempotente de schema `pc.command.feedback.v1`.
4. Generer le prochain `feedback_id` sans reutiliser un id existant.
5. Relire le SHA courant juste avant ecriture; en cas de conflit: refetch -> merge -> retry.
6. Mettre a jour:
   - `feedback-ledger.jsonl`
   - `FEEDBACK_LEDGER_MASTER.md`
   - `feedback-index.json`
   - les exigences/cahier de la conversation;
   - la `VERSION_TRACE` si une version est impactee.
7. Le feedback doit etre enregistre **avant** la phase de construction, sauf urgence de securite.
8. Aucun ancien feedback n'est supprime silencieusement.
9. Une nouvelle version doit declarer:
   - feedbacks traites;
   - feedbacks reportes;
   - regressions ouvertes;
   - preuves/gates executees.
10. Une version n'est pas consideree meilleure si elle casse une fonction precedemment validee.

### Donnees brutes et vie privee
Ne pas stocker de mot de passe, token, secret, chain-of-thought ou contenu prive non necessaire.
Le ledger contient des resumes techniques des feedbacks et preuves terrain, pas des secrets.
