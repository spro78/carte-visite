# Hunt or Hide (« Poule, poule, renard, vipère »)

Party game Roblox de poursuite à trois équipes, écrit en Luau et synchronisé
avec Roblox Studio grâce à [Rojo](https://rojo.space).
- Le décor de la carte héroïque (Carousel Valley) vient d'un **kit d'assets 3D
  original modélisé dans Blender** (`tools/assets`, `assets/kit/HoH_Kit.fbx`).
- Le reste est généré par le code : lobby, autres cartes, mécanismes, interface, effets.

> Règle affichée au joueur : **"Catch your prey. Run from your hunter."**
> Le RENARD attrape la POULE, la POULE attrape la VIPÈRE, la VIPÈRE attrape le RENARD.
> Un joueur attrapé est **à terre** : un coéquipier peut le porter jusqu'à son camp pour
> le relever. Sinon, il rejoint l'équipe qui l'a attrapé. Il n'y a pas de prison.

## Règles du jeu (règle retenue)

1. **Capture** : en touchant sa proie, on la met **à terre**. Elle reste couchée là où elle a été attrapée.
   - Elle ne bouge plus, ne peut plus être attrapée et ne compte plus pour les objectifs.
   - Elle reste dans son équipe.
   - La capture compte pour le chasseur : pièces, statistiques, fil des captures.
   - Si elle portait un œuf, l'œuf tombe (Golden Egg) ou retourne à son camp (Raid).
2. **Portage** : un coéquipier debout, à moins de 7 studs, peut la porter.
   - Commandes : touche **C**, bouton **Y** à la manette, bouton **CARRY** en tactile.
   - Le porteur est ralenti (x0,8), ne peut attraper personne et peut la lâcher (même commande).
   - Le chrono de la personne portée est suspendu.
3. **Réanimation** : dès que le porteur entre dans la **zone sûre de leur camp**, la personne portée se relève sur la plateforme.
   - Elle reste dans son équipe, avec 2 s de protection.
   - Le porteur gagne un objectif (pièces).
4. **Pas de secours** : au bout de **15 s** à terre sans être portée, la personne rejoint l'équipe qui l'a attrapée et se relève sur place, protégée 2 s.
   - C'est la conversion d'origine, appliquée une seule fois, à la fin.
   - Si plus aucun coéquipier n'est debout, la conversion est immédiate.
   - Personne ne reste bloqué.
5. **Cas particuliers** :
   - Un porteur attrapé lâche son coéquipier, qui garde au moins 5 s de chrono.
   - Réapparaître (reset) pendant qu'on est à terre vaut abandon : conversion immédiate.
   - En fin de manche, tout le monde se relève sans changer d'équipe. Les joueurs à terre comptaient déjà dans leur équipe.
6. **Zones sûres** : chaque camp a une zone autour et derrière sa plateforme, marquée au sol par un liseré pointillé et « SAFE ZONE ».
   - Un défenseur dans la zone de **son** camp ne peut être ni attrapé ni mordu (vérifié par le serveur).
   - La protection dure encore une demi-seconde après la sortie de la zone : tant que la pastille « SAFE ZONE » est affichée chez le joueur, malgré le décalage du réseau, il ne peut pas être attrapé.
   - Les adversaires peuvent y entrer (vol d'œufs du Raid), mais n'y sont pas protégés.
   - Même règle pour les trois camps et les quatre cartes.
7. **Victoire** : inchangée.
   - Objectif de la carte.
   - Ou dernière équipe debout.
   - Ou, au chrono, l'équipe la plus nombreuse (ou la règle de la carte).

8. **Modes et vote** : avant chaque manche, le lobby propose trois options « mode + carte ».
   - **CHASE** : poursuite pure. Dernière équipe debout, sinon la plus nombreuse au chrono.
   - **EGG RUN** : des œufs peints apparaissent dans trois nids, un entre chaque paire de camps.
     - On ramasse un œuf en le touchant et on le rapporte dans la zone sûre de son camp : +1.
     - Le porteur est ralenti (x0,85), visible de tous, ne peut ni attraper ni porter un coéquipier.
     - Porteur attrapé : l'œuf tombe. Un œuf laissé seul 20 s retourne dans un nid.
     - Première équipe à 5 œufs ; au chrono, le plus d'œufs.
   - **CAROUSEL** : le manège du centre a trois bras ; au bout de chacun, un cheval volant fait le tour de la vallée.
     - Sous chaque cheval, un anneau au sol suit sa course.
     - Chaque seconde, chaque anneau donne 1 point à l'équipe qui y a le plus de joueurs debout ; égalité : personne.
     - L'anneau prend la couleur de l'équipe qui le tient. Le manège change de sens toutes les 60 s.
     - La piste ne traverse aucune zone sûre. Première équipe à 120 points ; au chrono, le plus de points.
   - **Vote** : une voix par joueur, on peut changer d'avis. Chaque carte de vote montre la règle, le
     nombre de voix et le nom des votants ; une ligne liste tous les joueurs et ceux qui n'ont pas voté.
     L'option la plus votée gagne ; égalité ou aucun vote : le mode joué il y a le plus longtemps.
   - **Équipes** : tailles égales à un près ; chacun change d'animal d'une manche à l'autre et passe par
     les trois au fil des manches. Le décompte affiche la composition des trois équipes.

Réglages : `Config.Rescue`, `Config.SafeZone`, `Config.Modes` et `Config.Round.MapPool`
dans `src/shared/Config.lua`.

## Structure

```
default.project.json       Projet Rojo
src/shared/                -> ReplicatedStorage.Shared (serveur + client)
  Config.lua               Toutes les valeurs d'équilibrage (manche, cartes, économie, boutique)
  Teams.lua                Équipes, couleurs, chaîne de prédation
  MapInfo.lua              Nom de chaque carte et modes qu'on peut y jouer
  ModeInfo.lua             Modes (CHASE, EGG RUN, CAROUSEL...) : nom, règle en trois lignes
  Kit/                     Kit 3D généré par tools/assets : Manifest, Meshes/, Layouts, Palettes
  Style.lua                Direction artistique (palette, Terrain, éclairage)
  Remotes.lua, Types.lua   RemoteEvents et types partagés
src/server/                -> ServerScriptService.Server
  Main.server.lua          Point d'entrée : initialise les services dans l'ordre
  Services/                Déroulement de la partie
    RoundService.lua       Boucle : lobby/vote -> équipes -> décompte -> manche -> résultats
    VoteService.lua        Vote des options « mode + carte », départage par rotation
    MapRegistry.lua        Chargement automatique des cartes de Maps/
    TeamService.lua        Équipes équilibrées, animaux qui tournent d'une manche à l'autre
    CaptureService.lua     Captures (validées par le serveur) -> mise à terre
    RescueService.lua      À terre, portage, réanimation, conversion faute de secours
    SafeZoneService.lua    Zones sûres des camps (protection vérifiée par le serveur)
    AbilityService.lua     Dash et capacités (mêmes statistiques pour tous)
    LobbyBuilder.lua       Lobby (place du village, vote, roue, boutique, classements)
    HideService, LaunchService, ActorService (joueurs + bots), ...
  Maps/                    Cartes
    MapBase.lua            Système commun : arène, camps, chemins, cachettes, mécanismes
    _Template.lua          Modèle commenté pour créer une carte
    TheCarousel            Carte héroïque « Carousel Valley » (kit 3D, trois modes)
    TheFarm, TheCanyon, TheSwamp   Cartes historiques (un mode chacune, hors rotation)
  Modes/                   Règles des modes, indépendantes des cartes : Chase, EggRun, Carousel
  Util/                    Kit (pose des assets 3D), Build (Parts), Props, Ground
  Bots/                    Bots (noms, apparence, cerveau)
  Data/                    Profil sauvegardé, économie, boutique, roue, classements, Robux
src/client/                -> StarterPlayer.StarterPlayerScripts.Client
  Controllers/             Mouvement, contours, portage (RescueController), meshes du kit
                           (KitController), effets et sons, état, données
  UI/                      HUD, barre d'action tactile, boutique, fil des captures
tools/                     Vérification hors Studio (types, simulation, rendus 3D)
  assets/                  Kit 3D : modélisation Blender en Python, export FBX et données du jeu
assets/kit/HoH_Kit.fbx     Le kit exporté, à importer dans Studio (tools/assets/README.md)
```

## Installation

### 1. Installer Rojo

Option A, avec Rokit (recommandé, la version est épinglée dans `rokit.toml`) :

```bash
# Installer Rokit : https://github.com/rojo-rbx/rokit#installation
rokit install
rojo --version   # doit afficher 7.4.x
```

Option B, binaire direct : télécharger Rojo 7.4 depuis
<https://github.com/rojo-rbx/rojo/releases> et le mettre dans le PATH.

Option C, extension VS Code "Rojo" (evaera.vscode-rojo) : elle installe
Rojo et le plugin Studio pour toi.

### 2. Installer le plugin Rojo dans Studio

```bash
rojo plugin install
```

Puis redémarre Roblox Studio. Un bouton **Rojo** apparaît dans l'onglet *Plugins*.

### 3. Préparer la place dans Studio

1. Ouvre Roblox Studio, crée une place vide (template *Baseplate*).
2. **Supprime** `Workspace.Baseplate` et `Workspace.SpawnLocation` : le lobby
   construit son propre sol et son propre spawn.
3. Enregistre la place (`HuntOrHide.rbxl`, ignoré par git).

### 4. Synchroniser

Dans le dossier du projet :

```bash
rojo serve
```

Dans Studio : onglet *Plugins* -> **Rojo** -> **Connect** (localhost:34872).
Les scripts apparaissent dans `ReplicatedStorage.Shared`,
`ServerScriptService.Server` et `StarterPlayer.StarterPlayerScripts.Client`.
Chaque modification d'un fichier `.lua` est poussée en direct dans Studio.

Alternative sans serveur : `rojo build -o HuntOrHide.rbxl` puis ouvrir le fichier.

## Tester

- **Protocole de vérification dans Studio** (Carousel Valley, kit 3D, trois modes,
  vote, contours, zones sûres, mise à terre, portage, HUD, mobile) : `reference/TEST_STUDIO.md`.
- **Kit 3D** : au *Play*, chaque client construit les meshes à la volée (EditableMesh).
  Pour une expérience publiée, importer `assets/kit/HoH_Kit.fbx` (procédure dans
  `tools/assets/README.md`) ou activer l'option « Allow Mesh & Image APIs ».
- **Un joueur** : bouton *Play* dans Studio. Une manche se lance avec un seul
  joueur (`Config.Round.MinPlayersToStart = 1`).
- **Plusieurs joueurs** : onglet *Test* -> *Clients and Servers* -> choisir
  *3 Players* (ou plus) -> *Start*. Studio ouvre un serveur et trois clients.
- **Manches rapides** : dans `src/shared/Config.lua`, passe
  `Config.Debug.FastRounds = true` (intermission 8 s, manche 45 s).

Les logs serveur (`[RoundService] ...`, `[MapRegistry] ...`) s'affichent
dans la fenêtre *Output* de Studio.

## Direction artistique et avatars

- **Bible visuelle** : `reference/BIBLE_VISUELLE.md` (principes tirés de la
  référence, règles chiffrées vérifiées par `tools/sim/test_visual.luau`, kit
  d'interface propre au jeu, preuves dans `reference/preuves/`). En bref :
  - toujours de jour, lumière douce ;
  - décor en meshes stylisés du kit 3D : formes rondes et épaisses, arêtes adoucies,
    couleurs par rôle (palette `src/shared/Kit/Palettes.lua`), aucune texture ;
  - vallée fermée par des collines, sol d'herbe en plusieurs tons, allées bordées de pierres ;
  - couleurs d'équipe réservées aux équipes ;
  - couloirs de course dégagés, repères visibles de loin (manège, grande roue, moulin, grange, drapeaux) ;
  - interface en police Fredoka One, panneaux vert-de-gris à bord crème.

  Réglages dans `Map.Lighting`, les palettes du kit et, pour les cartes historiques,
  `src/shared/Style.lua`.
- **Chacun garde son avatar Roblox, entièrement** : corps, vêtements, accessoires et
  couleurs. L'équipe se lit à un **contour lumineux seul**, sans remplissage, aux
  couleurs de l'équipe :
  - renards orange ;
  - poules jaunes ;
  - vipères vertes (l'équipe garde son nom `SNAKE` dans le code).

  L'étiquette au-dessus de la tête complète : équipe, PREY / HUNTER, SAFE, DOWN.
  `Config.Appearance.Mode` : "Avatar" (défaut). "Accessories" et "Animal" restent
  disponibles mais ne sont pas utilisés.
- **Avatars R6** conseillés : *Home > Game Settings > Avatar > Avatar Type = R6*.

## Ajouter une carte

Tout est expliqué dans `src/server/Maps/_Template.lua`. En résumé :

1. Copier `_Template.lua` vers `src/server/Maps/<MonId>.lua` et changer `Map.Id`.
2. Ajouter `<MonId>` dans `src/shared/MapInfo.lua` (nom, mode, phrase « comment gagner », couleur).
3. Ajouter `Config.Maps.<MonId>` : taille de la zone (limites), distance et taille
   des camps, angles des camps (optionnel), valeurs du mode.
4. Remplir `THEME` (sol, chemins, relief, clôture, arbres, style des camps) et
   `Map.Lighting`, puis construire les lieux propres à la carte dans `Map.Build`.

`MapBase.BuildArena` construit la partie commune (relief, limites, trois camps
avec balise visible de loin, points d'apparition, chemins). Le terrain est effacé
automatiquement en fin de manche. La carte entre dans le vote et la rotation.

## Économie : récompenses gratuites, boutique de cosmétiques

- **Aucun achat ne donne d'avantage en poursuite** : vitesse, dash, portée de
  capture et survie sont identiques pour tous. Seule l'adresse compte.
- **Gratuit** : pièces et XP à chaque manche (participation, captures,
  objectifs, survie, victoire), pièces à chaque niveau, cosmétiques offerts aux
  niveaux 3, 5, 8, 12 et 20, roue gratuite toutes les 4 h.
- **Boutique** (comptoir du cadeau géant ou bouton SHOP) : chapeaux, traînées et
  effets de capture, chaque prix affiché en pièces.
- **Robux (désactivé tant que les identifiants valent 0)** : pass VIP (pièces x2)
  et packs de pièces, dans `Config.Monetization`. Les pièces n'achètent que des
  cosmétiques.

## Publier une version jouable

1. Ouvrir `dist/HuntOrHide.rbxl` dans Studio : la place est déjà construite et
   contrôlée par `tools/check.sh`. Ou `rojo build -o HuntOrHide.rbxl`, ou `rojo serve`.
   Démarrage rapide et protocole : `reference/TEST_STUDIO.md`.
2. Avec `rojo serve` dans une place existante : supprimer la Baseplate et la SpawnLocation d'origine.
3. *Game Settings* : Avatar Type = R6 ; *Security* : activer **Studio Access to
   API Services** (sauvegarde et classements) et **Allow Mesh & Image APIs**
   (meshes du kit 3D construits par chaque client). Sans cette option, importer
   le kit dans la place : `tools/assets/README.md`.
4. Tester dans Studio : *Play* (1 joueur + bots), puis *Test > Clients and Servers*
   avec 3 joueurs (captures, vote, résultats, boutique, roue) et l'émulateur de
   téléphone (*Test > Device*) pour les boutons tactiles.
5. *File > Publish to Roblox*, régler le nombre de joueurs par serveur (12-16),
   l'icône et les miniatures, puis rendre l'expérience publique.
6. Plus tard : créer le pass VIP et les packs de pièces, reporter leurs
   identifiants dans `Config.Monetization`.

## Avancement

- [x] Boucle de manche, équipes, vote et rotation, lobby
- [x] Captures, conversion, contours, inertie, dash, capacités
- [x] 4 cartes : The Farm, The Carousel, The Canyon, The Swamp
- [x] Kit 3D original modélisé dans Blender (59 assets) et carte héroïque Carousel Valley (simulation)
- [x] Trois modes jouables par tout le serveur (CHASE, EGG RUN, CAROUSEL), vote lisible, équipes tournantes (simulation)
- [ ] Carousel Valley vérifiée dans Studio (meshes, collisions, sensations) : `reference/TEST_STUDIO.md`
- [ ] Même traitement (kit 3D) pour The Farm, The Canyon et The Swamp, puis retour dans la rotation
- [x] Bots
- [x] Pièces, niveaux, boutique de cosmétiques, sauvegarde, classements
- [x] Effets, sons, fil des captures, résultats expliqués, arrivée en cours de manche
- [x] Avatars intacts + contour d'équipe, zones sûres, mise à terre / portage / réanimation (simulation)
- [ ] Test en conditions réelles dans Studio (sensations, mobile, performance à 16+ joueurs) :
      protocole dans `reference/TEST_STUDIO.md`
- [ ] Sons d'ambiance par carte et musique (identifiants d'assets à choisir)
