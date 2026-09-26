# PC COMMAND Lab

Objectif: construire un centre de controle local, lisible et tres leger pour observer le lien ChatGPT <-> Desktop Commander sans dependre d'un navigateur.

## Contraintes
- PC cible: Lenovo IdeaPad 3 15IGL05, Celeron N4020, 4 Go RAM, HDD.
- Google Drive Desktop reste actif.
- Le tableau de bord ne doit pas lancer de navigateur.
- Un seul processus GUI leger.
- Les tests et la mise au point se font ici dans BuildHub autant que possible afin d'economiser les appels Remote Desktop Commander.
- Les tests locaux servent uniquement aux mesures materielles finales.

## UX cible
Le bureau Windows contient un raccourci **PC COMMAND - LIVE**.
La fenetre montre:
1. Connexion: CONNECTE / DECONNECTE
2. Action actuelle
3. Derniere action
4. RAM libre / RAM Desktop Commander
5. Journal recent
6. Boutons: Actualiser, Ouvrir le journal, Masquer

Le programme est en lecture seule: fermer le tableau de bord ne coupe jamais Desktop Commander.
