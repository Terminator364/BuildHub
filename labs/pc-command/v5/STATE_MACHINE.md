# PC COMMAND — machine d'etats observable

PC COMMAND suit uniquement des etats **observables ou explicitement publies**. Il n'expose pas le raisonnement prive/chain-of-thought de ChatGPT.

## Etats de tour
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

## Regles
1. Une conversation PCCONNECT publie un evenement au debut d'un tour avant le travail lourd.
2. Pendant ASSISTANT_PROCESSING, le PC calcule localement la duree ecoulee; aucun heartbeat distant permanent n'est necessaire.
3. Les changements de phase publies sont de haut niveau: RESEARCH, BUILD, VERIFY, WAITING, DELIVERY.
4. Les appels outils peuvent etre groupes en lots pour eviter des centaines d'ecritures.
5. La fin de reponse publie ASSISTANT_RESPONDED avec duree et dernier resultat.
6. Si un nouveau message arrive alors que le tour precedent est toujours PROCESSING, le tour precedent devient INTERRUPTED_INFERRED sauf preuve plus precise.
7. USER_STOPPED_EXPLICIT n'est utilise que si un adaptateur ou un evenement explicite prouve l'arret.
8. SECURITY_CHECK_REPORTED n'est utilise que si la plateforme/conversation/utilisateur le rapporte.
9. En OFFLINE, le viewer conserve le dernier etat fiable et marque clairement son age.
10. Un etat PROCESSING ancien sans evenement recent devient STALE/UNKNOWN, jamais automatiquement DONE.

## Pourquoi
Le support utilisateur a montre trois classes de panne importantes a absorber:
- controles de securite pouvant interrompre un long travail;
- desynchronisation/rechargement de conversations et reprises;
- quotas/limites dont l'attribution historique peut manquer de granularite.

PC COMMAND doit donc privilegier checkpoints, preuves et reprise plutot qu'inventer un etat.
