# Protocole de test dans Roblox Studio : tranche verticale (Canyon)

Ce protocole couvre ce que la simulation (`tools/check.sh`) ne peut pas prouver : le rendu et la physique réels de Roblox.
- **Seules des captures de la vraie fenêtre Studio comptent comme preuve.**
- Les rendus de `tools/preview` et la simulation ne valent pas un test Studio.
- Durée : 30 à 45 minutes.

## 1. Préparer la place

1. Récupérer la branche `claude/nice-albattani-2x8yqo` (PR #1).
2. Générer la place ou synchroniser :
   - `rojo build -o HuntOrHide.rbxl`, puis ouvrir le fichier dans Studio ;
   - ou `rojo serve` puis *Plugins > Rojo > Connect*.
3. Supprimer `Workspace.Baseplate` et `Workspace.SpawnLocation` s'ils existent.
4. Pour aller vite, dans `src/shared/Config.lua` (à remettre ensuite) :
   - `Config.Debug.ForceMap = "TheCanyon"` : toujours la carte de la tranche ;
   - option : `Config.Rescue.BleedOutSeconds = 30` pour avoir le temps de faire les captures d'écran à terre.
5. Ouvrir la fenêtre *Output* : aucune ligne rouge ne doit apparaître pendant les tests.

## 2. Test seul avec les bots (*Play*)

Une manche démarre avec toi et 11 bots (4 par équipe).

| # | Action | Résultat attendu | Capture |
|---|---|---|---|
| 1 | Pendant le décompte, regarder les autres joueurs | Avatars intacts, sans oreilles, queue ni foulard. Contour lumineux seul : renards orange, poules jaunes, vipères vertes. Ton propre contour aussi | ✔ vue au spawn |
| 2 | Rester dans son camp (plateforme ou derrière) | Liseré pointillé au sol, « SAFE ZONE » à l'entrée. Pastille du HUD : `SAFE ZONE · nobody can catch you here` | ✔ |
| 3 | Laisser un chasseur te toucher **dans** ta zone | Aucune capture ; sa morsure (vipère) ne te ralentit pas | |
| 4 | Sortir, te faire attraper | Tu tombes sur le dos, immobile ; pastille `YOU'RE DOWN · 15s · ...` avec une jauge ; plus de boutons d'action | ✔ |
| 5 | Attendre un bot coéquipier | Il vient, te charge sur l'épaule (`CARRIED HOME by ...`), te ramène au camp, tu te relèves sur la plateforme avec un champ de force | ✔ portage vu par la caméra |
| 6 | Sinon, attendre 15 s | Tu rejoins l'équipe qui t'a attrapé, debout sur place, protégé 2 s ; fil : `toi joined the ...` | |
| 7 | Trouver un coéquipier bot à terre | Marqueur `HELP 12s · 34m` au-dessus de lui, étiquette `DOWN`, pastille `... is down · 34m · carry them home` | ✔ |
| 8 | T'en approcher (moins de 7 studs) | Pastille `Press C to carry ...`, médaillon `CARRY` avec la puce `C` dans le dock | ✔ |
| 9 | Appuyer sur **C** | Le corps se pose sur ton épaule droite ; tu ralentis ; flèche vers ton camp ; médaillon `DROP` ; pastille `CARRYING ...` | ✔ caméra de dos |
| 10 | Appuyer encore sur **C**, puis le reprendre | Il retombe à côté, avec au moins 5 s de chrono, puis remonte sur l'épaule | |
| 11 | Entrer dans la zone sûre de ton camp | Il se relève sur la plateforme : « SAVED! », étincelles ; fil `toi saved ...` ; pièces | ✔ |
| 12 | Pendant le portage, toucher une proie | Aucune capture (mains prises) | |

## 3. Test à plusieurs joueurs (*Test > Clients and Servers*, 3 joueurs)

C'est le test le plus important pour la physique réelle : la soudure entre deux vrais joueurs et la propriété réseau.

| # | Action | Résultat attendu |
|---|---|---|
| 1 | Joueur 2 attrape joueur 1 | Joueur 1 couché, immobile côté client et côté serveur |
| 2 | Si joueur 3 est dans l'équipe de joueur 1 : il le porte avec C | Pas de saccades ni de téléportations ; le porteur avance normalement à 80 % de sa vitesse ; la caméra du joueur porté suit |
| 3 | Joueur 2 attrape le porteur | Le porteur tombe à son tour ; le joueur porté retombe à côté (chrono minimum 5 s) |
| 4 | Le joueur à terre fait *Reset Character* (menu Échap) | Il réapparaît dans l'équipe de celui qui l'a attrapé (pas de résurrection gratuite) |
| 5 | Plus aucun coéquipier debout | Conversion immédiate, personne ne reste couché |

## 4. Mobile (*Test > Device*, téléphone en paysage puis en portrait)

| # | Contrôle | Résultat attendu |
|---|---|---|
| 1 | Près d'un coéquipier à terre | Bouton rond `CARRY` au-dessus du dash gauche, sans couvrir le saut ni le joystick de Roblox ; pastille `Tap CARRY to save ...` |
| 2 | Toucher CARRY puis DROP | Même comportement qu'au clavier |
| 3 | Pastille d'état et annonces | En haut, sous le ruban ; jamais au centre de l'écran |

## 5. Captures à envoyer

Une capture de la vraie fenêtre Studio pour chaque ligne marquée ✔, plus :
- la fenêtre *Output* en fin de manche ;
- le panneau *Stats* (`Shift+F5`) pendant une poursuite, pour les performances.

## 6. Ce qui peut différer de la simulation (à regarder en priorité)

| Domaine | Risque |
|---|---|
| Contours (Highlight) | Épaisseur et lisibilité à distance ; vert vif sur sol vert ; limite de 31 Highlights |
| Corps à terre | Posé par une racine ancrée ; l'animation d'attente de l'avatar peut bouger les membres |
| Portage | Corps soudé sur l'épaule, sans animation dédiée ; possibles saccades selon la propriété réseau ; pose à vérifier en R6 et en R15 |
| Sol sous le joueur | Rayon vers le bas qui ignore les pièces non collidables ; vérifier la mine, l'arche et les buttes du Canyon |
| Sons | Sons intégrés à Roblox (`rbxasset://`) : volume et choix à juger à l'oreille |
