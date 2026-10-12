# Hunt or Hide (« Poule, poule, renard, vipère »)

Party game Roblox de poursuite à trois équipes, écrit en Luau et synchronisé
avec Roblox Studio grâce à [Rojo](https://rojo.space). Tout est généré par le
code : lobby, cartes (sol et relief en pièces), mécanismes, interface, effets.

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
   - Les adversaires peuvent y entrer (vol d'œufs du Raid), mais n'y sont pas protégés.
   - Même règle pour les trois camps et les quatre cartes.
7. **Victoire** : inchangée.
   - Objectif de la carte.
   - Ou dernière équipe debout.
   - Ou, au chrono, l'équipe la plus nombreuse (ou la règle de la carte).

Réglages : `Config.Rescue` et `Config.SafeZone` dans `src/shared/Config.lua`.

## Structure

```
default.project.json       Projet Rojo
src/shared/                -> ReplicatedStorage.Shared (serveur + client)
  Config.lua               Toutes les valeurs d'équilibrage (manche, cartes, économie, boutique)
  Teams.lua                Équipes, couleurs, chaîne de prédation
  MapInfo.lua              Nom, mode et phrase "comment gagner" de chaque carte
  Style.lua                Direction artistique (palette, Terrain, éclairage)
  Remotes.lua, Types.lua   RemoteEvents et types partagés
src/server/                -> ServerScriptService.Server
  Main.server.lua          Point d'entrée : initialise les services dans l'ordre
  Services/                Déroulement de la partie
    RoundService.lua       Boucle : lobby/vote -> équipes -> décompte -> manche -> résultats
    VoteService.lua        Vote + rotation des cartes
    MapRegistry.lua        Chargement automatique des cartes de Maps/
    TeamService.lua        Équipes équilibrées
    CaptureService.lua     Captures (validées par le serveur) -> mise à terre
    RescueService.lua      À terre, portage, réanimation, conversion faute de secours
    SafeZoneService.lua    Zones sûres des camps (protection vérifiée par le serveur)
    AbilityService.lua     Dash et capacités (mêmes statistiques pour tous)
    LobbyBuilder.lua       Lobby (place du village, vote, roue, boutique, classements)
    HideService, LaunchService, ActorService (joueurs + bots), ...
  Maps/                    Cartes
    MapBase.lua            Système commun : arène, camps, chemins, cachettes, mécanismes
    _Template.lua          Modèle commenté pour créer une carte
    TheFarm, TheCarousel, TheCanyon, TheSwamp
  Util/                    Build (Parts), Props (décors 3D), Ground (sol et relief en pièces)
  Bots/                    Bots (noms, apparence, cerveau)
  Data/                    Profil sauvegardé, économie, boutique, roue, classements, Robux
src/client/                -> StarterPlayer.StarterPlayerScripts.Client
  Controllers/             Mouvement, contours, portage (RescueController), effets et sons, état, données
  UI/                      HUD, barre d'action tactile, boutique, fil des captures
tools/                     Vérification hors Studio (types, simulation, rendus 3D)
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

- **Protocole de vérification dans Studio** (contours, zones sûres, mise à terre,
  portage, réanimation, HUD, mobile) : `reference/TEST_STUDIO.md`.
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
  d'interface propre au jeu, exemple complet sur le Canyon, preuves dans
  `reference/preuves/`). En bref :
  - toujours de jour ;
  - sol en plaques à tenons d'un ton dominant, sans Terrain (`src/server/Util/Ground.lua`) ;
  - fond en gradins de blocs ;
  - couleurs d'équipe réservées aux équipes ;
  - couloirs de course dégagés ;
  - interface en police Fredoka One, panneaux vert-de-gris à bord crème.

  Réglages dans `src/shared/Style.lua`, `Map.Lighting` et les thèmes des cartes.
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

1. `rojo build -o HuntOrHide.rbxl`, ouvrir le fichier dans Studio (ou `rojo serve`).
2. Supprimer la Baseplate et la SpawnLocation d'origine si elles existent.
3. *Game Settings* : Avatar Type = R6 ; *Security* : activer **Studio Access to
   API Services** (sauvegarde et classements).
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
- [x] Bots
- [x] Pièces, niveaux, boutique de cosmétiques, sauvegarde, classements
- [x] Effets, sons, fil des captures, résultats expliqués, arrivée en cours de manche
- [x] Avatars intacts + contour d'équipe, zones sûres, mise à terre / portage / réanimation (simulation)
- [ ] Test en conditions réelles dans Studio (sensations, mobile, performance à 16+ joueurs) :
      protocole dans `reference/TEST_STUDIO.md`
- [ ] Sons d'ambiance par carte et musique (identifiants d'assets à choisir)
