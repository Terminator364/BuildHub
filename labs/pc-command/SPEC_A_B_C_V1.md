# PC COMMAND — Cahier des charges A+B+C — v1

## 0. Principe
PC COMMAND est un moteur local de suivi de flux de travail multi-conversations, leger, lisible et zero-dollar.
Il ne remplace pas ChatGPT. Il consolide les evenements publies par les conversations connectees et les preuves locales/externes disponibles.

Methode obligatoire: **A + B + C**, puis **MERGE + REFINE + PRESERVE**.

- **A — besoin/promesse**: objectif utilisateur, contraintes, UX, livrables, priorites.
- **B — recherche/architecture**: standards, documentation, projets existants, benchmarks, reemploi.
- **C — terrain/retours**: captures, erreurs reelles, comportement du PC, feedback utilisateur, nouveaux besoins.
- Chaque nouveau feedback est un **delta**: il complete ou corrige le cahier sans effacer les exigences anterieures sauf demande explicite.

## 1. Contraintes P0
- PC cible: Lenovo IdeaPad 3 15IGL05, Celeron N4020, 4 Go RAM, HDD.
- Budget: 0 USD.
- Dependances physiques obligatoires: connexion Internet + compte ChatGPT de l'utilisateur.
- Google Drive Desktop doit rester actif.
- Interface locale: PowerShell/console, pas d'UI lourde.
- Synchro Internet: 5 s.
- Recalcul du moteur: 5 s.
- Rafraichissement visuel: 10 s pour garder la lecture confortable.
- Maximum 10 conversations actives affichees.
- Maximum 10 macro-taches actives par conversation.
- Desktop Commander est une source/adaptateur optionnel, pas la source canonique du suivi.
- Le suivi doit continuer sur cache meme si Desktop Commander est deconnecte.
- Aucun pourcentage ne doit etre presente comme une probabilite de succes.

## 2. Modele de travail
Hierarchie:

```
Compte / PC COMMAND
  -> Conversation connectee (trace)
      -> Macro-tache (objectif/delivrable)
          -> Micro-tache (etape verifiable)
              -> Evenements / preuves
```

### Detection des changements
Une conversation connectee doit convertir les changements en evenements structures:
- nouvelle finalite autonome -> `task.added` macro;
- nouvelle etape necessaire -> `task.added` micro;
- correction/feedback -> `scope.expanded` ou `task.changed`;
- lancement outil -> `tool.started`;
- resultat -> `tool.completed` + preuve;
- echec -> `tool.failed` / `task.blocked`;
- reprise -> `conversation.resumed`;
- fin -> `task.completed` / `conversation.completed`.

Le moteur local ne doit pas inventer une tache a partir du temps ecoule. Il recalcule a partir des donnees publiees et des observations locales.

## 3. Progression adaptative
### Micro-tache
- `completion` entre 0.0 et 1.0.
- DONE force 1.0.
- ACTIVE conserve la valeur publiee.
- Une absence d'evenement ne fait pas progresser artificiellement.

### Macro-tache
`sum(weight * completion) / sum(weight)`

### Conversation
`sum(macro_weight * macro_progress) / sum(macro_weight)`

### Extension de portee
Quand une nouvelle tache est ajoutee, le denominateur augmente.
Le pourcentage peut donc baisser. Ce n'est pas une regression: c'est un recalcul du plan.

### Fiabilite
Afficher separement:
- progression estimee;
- couverture des preuves;
- fraicheur des evenements;
- etat ACTIF / ATTENTE / BLOQUE / SILENCIEUX / CLOTURE.

### Prediction / ETA
ETA autorisee uniquement si:
- plusieurs echantillons de progression existent;
- la portee est stable sur la fenetre;
- la pente est positive et suffisante.
Sinon afficher `ETA: donnees insuffisantes` ou `plan en evolution`.
Aucune fausse precision.

## 4. Architecture
```
Conversations ChatGPT connectees
       |  evenements structures
       v
Transport zero-dollar (GitHub public / snapshot consolide)
       |
       v
PC COMMAND local
  1. Event Ingestor
  2. Deduplicateur
  3. State Projector
  4. Scope Detector
  5. Progress Engine
  6. Confidence/Freshness Engine
  7. ETA/Risk Engine
  8. Source Health
  9. Cache/History local
 10. PowerShell TUI
```

## 5. Evenement canonique
Format inspire de CloudEvents + W3C Trace Context/OpenTelemetry:

```json
{
  "event_id": "unique",
  "trace_id": "conversation",
  "span_id": "operation",
  "parent_span_id": "optional",
  "sequence": 42,
  "time": "ISO-8601",
  "source": "chatgpt|github|desktop|drive|telegram|youtube|tlib|web",
  "type": "task.added",
  "subject": "macro-or-micro-task-id",
  "summary": "texte humain court",
  "status": "ACTIVE",
  "completion": 0.35,
  "evidence_ref": "optional",
  "payload_hash": "sha256"
}
```

Regles:
- `event_id` + `payload_hash` => deduplication.
- `sequence` monotone par conversation.
- `trace_id` relie toutes les operations d'une conversation.
- `span_id` et `parent_span_id` relient outil -> sous-operation -> preuve.

## 6. Sources / adaptateurs
Les sources ne sont pas toutes des dependances locales.

- **ChatGPT**: publie les changements de plan et l'etat des outils.
- **GitHub**: code, CI, commits, preuves de tests, bus/snapshot public.
- **TLIB**: faits/recherche et etat moteur quand interroge par une conversation.
- **Drive**: actions/fichiers observes via une conversation connectee.
- **Telegram/Delivery**: envoi, reception, receipts quand le projet l'utilise.
- **YouTube/Web**: recherche/navigation seulement quand un outil/conversation emet l'evenement correspondant.
- **Desktop Commander**: actions Windows observables localement.
- **WMI local**: observation des processus sans consommer d'appel Remote Desktop Commander.

Limite honnete: un PowerShell local ne peut pas lire magiquement toutes les conversations du compte ChatGPT. Chaque conversation doit etre instrumentee via PCCONNECT ou un futur connecteur officiel.

## 7. Multi-conversations
Commande utilisateur:

`PCCONNECT`

Code complet genere dans Parametres:

`PCCONNECT|v2|pc=MBMPC|repo=Terminator364/BuildHub|branch=lab/pc-command-browser-20260926|feed=feed-v3|slot=AUTO|max=10`

Une conversation connectee:
1. lit le protocole;
2. cree/reutilise son `conversation_id`;
3. preserve tous les autres flux;
4. publie uniquement ses deltas;
5. ajoute une preuve avant DONE;
6. ne declare jamais une source observee si elle ne l'est pas.

## 8. Interface PowerShell
### Vue generale
- sante connexion;
- RAM libre;
- Drive actif;
- cadence moteur/sync/ecran;
- onglets conversations;
- progression conversation;
- macro-taches;
- changements detectes.

### Detail conversation
- objectif;
- progression;
- ETA;
- macro-taches;
- sante/fraicheur.

### Detail macro
- micro-taches;
- etat/progression;
- preuves;
- dernier succes;
- action actuelle;
- prochaine etape;
- blocage;
- evenements recents.

### Parametres
- cadence 5/5/10;
- limites 10/10;
- code PCCONNECT;
- copie presse-papiers;
- sources disponibles;
- cache/historique;
- version moteur.

Raccourcis: General, Conversation, Macro, Sources, Local, Parametres, Sync, Retour, Fermer.

## 9. UX et performance
- aucun redraw toutes les secondes;
- calcul interne 5 s;
- ecran recompose toutes les 10 s;
- pas de navigateur integre au suivi;
- pas de polling lourd de dix endpoints: lire un snapshot consolide;
- historique JSONL borne/compacte;
- cache local;
- operations reseau avec timeout court;
- degradation gracieuse hors-ligne.

## 10. Securite et integrite
- lecture publique possible; ecriture via compte/connector ChatGPT autorise.
- aucune execution PowerShell arbitraire provenant directement du feed.
- le feed transporte de l'etat, jamais des commandes executable-as-data.
- idempotence, hash, sequence, readback.
- une conversation = un writer logique de son propre etat.
- conflits => relire / merger / reessayer.
- secrets interdits dans le depot public.

## 11. A+B+C — qualification
### A — Promesse
Suivi humain, automatique, adaptatif, multi-conversations, faible RAM, zero-dollar.

### B — Recherche / reemploi
- modele evenementiel inspire CloudEvents;
- correlation inspiree W3C Trace Context / OpenTelemetry;
- event logs et reconstruction de flux inspires du process mining;
- BuildHub/GitHub pour CI et snapshot public;
- PowerShell/WMI pour le local leger.

### C — Terrain
Feedbacks deja integres:
- tableau blanc trop lourd/rejete;
- console brute trop illisible/rejetee;
- PowerShell simple valide;
- besoin de plus de detail humain;
- lecture impossible a 5 s -> ecran 10 s;
- moteur/sync plus rapide en interne -> 5 s;
- nouvelle tache doit modifier immediatement la portee;
- multi-conversations + parametres + code de connexion;
- Google Drive ne doit pas etre coupe.

## 12. Gates de preuve
- STATIC: parse PowerShell.
- SCHEMA: feed valide, limites 10/10.
- CI: tests BuildHub verts.
- RUNTIME: lancement local.
- VISUAL: capture lisible.
- RESOURCE: RAM du viewer mesuree.
- FIELD: au moins deux conversations PCCONNECT modifient le meme cockpit sans collision.
- RECOVERY: reboot/fermeture/reouverture reprend le dernier cache.
