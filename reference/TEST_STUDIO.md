# Protocole de test dans Roblox Studio : Carousel Valley

Ce protocole couvre ce que la simulation (`tools/check.sh`) ne peut pas prouver : le rendu et la physique réels de Roblox.
- **Seules des captures de la vraie fenêtre Studio comptent comme preuve.**
- Les rendus de `tools/preview` (mention « RENDU SIMULÉ »), les planches Blender (« RENDU BLENDER ») et la simulation ne valent pas un test Studio.
- Durée : 10 minutes pour le démarrage rapide (§0), 45 à 60 minutes pour tout le protocole.

## 0. Démarrage rapide (10 minutes)

1. Télécharger `dist/HuntOrHide.rbxl` depuis la branche `claude/nice-albattani-2x8yqo` (PR #1). Sur GitHub : ouvrir le fichier, puis *Download raw file*.
2. L'ouvrir dans Studio : double-clic, ou *File > Open from File*. La place est prête : rien à installer, rien à supprimer.
3. Ouvrir *View > Output*, puis *Test > Play*. On joue seul : les bots complètent les trois équipes.
4. Dans *Output*, deux lignes disent si la carte marche :
   - `[Kit] 189/189 meshes du kit prêts en … s (construits par ce client)` : les meshes 3D fonctionnent. La ligne apparaît pendant le lobby.
   - `[Carousel Valley] carte construite : … assets du kit, … volumes de collision` : la carte est posée. La ligne apparaît à la fin du vote.
   - Si `[Kit] Meshes non construits (…)` apparaît à la place : la raison est entre parenthèses. Il faut alors importer le kit (§1, étape 5B). En attendant, la carte s'affiche en blocs de remplacement, mais reste jouable.
5. Jouer une manche : vote, composition des équipes, puis la manche. Regarder la carte (§2), un objectif (§4 : ramener un œuf ou tenir un anneau) et une conversion (§5, ligne 4).
6. Renvoyer :
   - trois captures de la fenêtre Studio (vote, vue de la carte, une poursuite) ;
   - le texte de *Output*, copié-collé ;
   - ce qui ne va pas.

## 1. Préparer la place (protocole complet)

1. Récupérer la branche `claude/nice-albattani-2x8yqo` (PR #1).
2. Trois façons d'avoir la place, toutes vérifiées hors Studio (`tools/check.sh place`, `rojo serve` répond) :
   - ouvrir `dist/HuntOrHide.rbxl`, déjà construite (reconstruite par `tools/check.sh` à chaque poussée) ;
   - ou `rojo build default.project.json -o HuntOrHide.rbxl` (Rojo 7.4.4, version fixée dans `rokit.toml`), puis ouvrir le fichier ;
   - ou, pour modifier le code en direct : `rojo serve`, puis dans Studio *Plugins > Rojo > Connect* (plugin Rojo 7.4.x, port 34872).
3. Avec `rojo serve` dans une place existante : supprimer `Workspace.Baseplate` et `Workspace.SpawnLocation` s'ils existent.
4. Ouvrir la fenêtre *Output* : aucune ligne rouge ne doit apparaître pendant les tests.
5. Meshes du kit 3D, deux possibilités (détails dans `tools/assets/README.md`) :
   - **A. Rien à faire** : au *Play*, chaque client construit les meshes (EditableMesh). C'est le premier test à faire.
   - **B. Import** : *Import 3D* de `assets/kit/HoH_Kit.fbx` (unité : studs, sans fusion), modèle renommé `HoH_KitMeshes` dans ReplicatedStorage. À faire avant de publier.
6. Pour aller vite (à remettre ensuite), dans `src/shared/Config.lua` :
   - `Config.Debug.ForceMode = "Carousel"` (ou `"EggRun"`, `"Chase"`) pour imposer un mode ;
   - `Config.Rescue.BleedOutSeconds = 30` pour avoir le temps des captures d'écran à terre.

## 2. La carte (seul, *Play*)

| # | Contrôle | Résultat attendu | Capture |
|---|---|---|---|
| 1 | Entrer dans la manche, regarder autour | Vallée d'herbe fermée par des collines ; manège au centre ; moulin sur sa butte ; grange rouge ; ruisseau et pont ; grande roue sur les collines, posée sur la pente sans flotter ; trois camps (portail en bois avec le nom, drapeau d'équipe, tanière / poulailler / creux des vipères). Aucun bloc gris de remplacement | ✔ même cadrage que `reference/preuves/avant_apres/` |
| 2 | Sortie *Output* | Pas de message « [Kit] Meshes non construits ». Si le message apparaît : noter la raison, essayer l'import (B) | ✔ si message |
| 3 | Faces des meshes | Arbres, rochers, grange vus de partout, sans trou. Si des faces manquent : `Config.Kit.FlipWinding = true` et recommencer | |
| 4 | Collisions | On ne traverse ni les troncs, ni les rochers, ni les murs de la grange. On passe par les portes de la grange. On monte sur la butte du moulin par ses deux rampes. On franchit le ruisseau par le pont seulement | ✔ sur la butte |
| 5 | Repères | Depuis chaque camp, on voit le manège, la grande roue, le moulin et les drapeaux des deux autres camps | |
| 6 | Mouvement | Les chevaux volants tournent doucement au-dessus de la piste ; les ailes du moulin tournent | |
| 7 | Performance | *Shift+F5* : images par seconde stables ; noter la mémoire (*Shift+F6*, catégorie Graphics/Geometry) | ✔ Stats |

## 3. Le vote (*Test > Clients and Servers*, 3 joueurs)

| # | Action | Résultat attendu | Capture |
|---|---|---|---|
| 1 | Pendant l'intermission | Trois cartes : CHASE, EGG RUN, CAROUSEL « on Carousel Valley », chacune avec sa règle en trois lignes. Une ligne en dessous liste les joueurs et ceux qu'on attend. Écrans du lobby : nom du mode et de la carte | ✔ |
| 2 | Joueur 1 clique EGG RUN, joueur 2 marche sur la plaque EGG RUN, joueur 3 vote CAROUSEL | Carte EGG RUN : « 2 votes · noms ». Le panneau géant indique le mode en tête | |
| 3 | Fin du vote | Annonce « Next: EGG RUN on Carousel Valley » ; c'est bien ce mode qui est joué | |
| 4 | Décompte | Panneau des trois équipes avec tous les joueurs (bots compris) | ✔ |
| 5 | Manche suivante sans voter | Le mode joué il y a le plus longtemps est choisi | |
| 6 | Trois manches de suite | Personne ne garde le même animal deux fois de suite | |

## 4. Les modes

### EGG RUN
| # | Action | Résultat attendu |
|---|---|---|
| 1 | Début | Trois œufs peints (blanc, bande lilas) flottent dans trois nids, un entre chaque paire de camps ; la flèche montre l'œuf le plus proche |
| 2 | Toucher un œuf | L'œuf se pose au-dessus de la tête ; « You have an egg! » ; ralenti ; flèche vers son camp |
| 3 | Entrer dans la zone sûre de son camp | +1 œuf ; un nouvel œuf réapparaît dans un nid après 4 s |
| 4 | Se faire attraper en portant | L'œuf tombe au sol ; ramassable après 1 s ; retourne seul dans un nid après 20 s |
| 5 | 5 œufs | Victoire de l'équipe |

### CAROUSEL
| # | Action | Résultat attendu | Capture |
|---|---|---|---|
| 1 | Début | Les trois chevaux volants accélèrent (un tour en 48 s) ; un anneau au sol suit chacun | ✔ |
| 2 | Rester dans un anneau | 1 point par seconde pour son équipe ; l'anneau prend sa couleur | ✔ |
| 3 | Un adversaire entre à égalité | Plus de point ; anneau gris | |
| 4 | Après 60 s | Annonce « The carousel turns the other way! », sens inversé | |
| 5 | Fluidité | L'anneau et le cheval glissent sans saccade (animation côté client) ; l'anneau ne passe jamais dans une zone sûre | |

### CHASE
| # | Action | Résultat attendu |
|---|---|---|
| 1 | Toute la manche | Pas de score ; sous le ruban : « last team standing » ; pas d'anneau au sol |

## 5. Règles qui ne changent pas (à revérifier sur cette carte)

| # | Contrôle | Résultat attendu |
|---|---|---|
| 1 | Avatars | Intacts ; contour lumineux seul : renards orange, poules jaunes, vipères vertes |
| 2 | Zone sûre de son camp | Liseré pointillé, « SAFE ZONE » ; impossible d'y être attrapé ou mordu |
| 3 | Mise à terre et portage (C, bouton CARRY) | Comme dans la version précédente : porté jusqu'à la zone sûre, relevé sur la plateforme |
| 4 | Conversion : se faire attraper, puis rester à terre 15 s sans secours | On se relève dans l'équipe du chasseur : contour, ruban et tableau des équipes changent ; pas de prison |
| 5 | Téléphone (*Test > Device*, paysage et portrait) | Vote lisible (une règle par carte en petit écran), composition des équipes, pastille d'état, bouton CARRY |

## 6. Captures à envoyer

Une capture de la vraie fenêtre Studio pour chaque ligne marquée ✔, plus :
- la fenêtre *Output* en fin de manche ;
- le panneau *Stats* (`Shift+F5`) pendant une poursuite.

## 7. Publier dans « Mes expériences »

1. Dans Studio : *File > Publish to Roblox As…*, puis *Create new experience* (nom, description). L'expérience apparaît dans *Mes expériences* du Creator Hub.
2. *Game Settings* :
   - *Security* : **Allow Mesh & Image APIs**, pour que les meshes du kit se construisent dans l'expérience publiée (compte de 13 ans ou plus, à l'identité vérifiée) ;
   - *Security* : **Studio Access to API Services** (sauvegarde, classements) ;
   - *Avatar* : R6.
3. Si l'option des meshes n'est pas disponible : importer le kit (§1, étape 5B) avant de publier.
4. Pour que Claude publie lui-même les mises à jour depuis le cloud (facultatif) :
   - créer une clé d'API sur create.roblox.com/credentials, limitée à cette expérience, avec le droit d'écrire les places ;
   - l'ajouter dans les réglages de l'environnement cloud, en secret `ROBLOX_API_KEY`, jamais dans la conversation ;
   - autoriser le domaine `apis.roblox.com` dans l'accès réseau de l'environnement ;
   - donner l'identifiant de l'univers et celui de la place (ce ne sont pas des secrets).

   Commande alors utilisée : `rojo upload --api_key "$ROBLOX_API_KEY" --universe_id <univers> --asset_id <place> default.project.json`.

## 8. Ce qui peut différer de la simulation (à regarder en priorité)

| Domaine | Risque |
|---|---|
| Meshes construits à la volée | API refusée dans une expérience publiée sans l'option ; ordre des sommets (faces) ; normales ; mémoire sur téléphone |
| Import du FBX | Axes (rotation des assets) ; un MeshPart par objet ; noms conservés |
| Collisions du kit | Volumes simples posés à la main : bords de la butte, rampes, pont, ruisseau, murs de la grange |
| Chevaux volants | Anneaux suivis par le serveur au calcul (pas de collision) ; vérifier que le point compte bien quand on est dedans |
| Contours (Highlight) | Lisibles sur le vert de la vallée ; limite de 31 Highlights (`Config.Appearance.MaxOutlines`) |
| Lumière | `Map.Lighting` de Carousel Valley (ombres douces, brume légère) : rendu réel à juger |
