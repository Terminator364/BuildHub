# PCCONNECT v2 — connecter une conversation ChatGPT a PC COMMAND

Commande utilisateur:

```
PCCONNECT|v2|pc=MBMPC|repo=Terminator364/BuildHub|branch=lab/pc-command-browser-20260926|protocol=labs/pc-command/PCCONNECT.md|slot=AUTO|max=10
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
