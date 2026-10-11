# Hunt or Hide (« Poule, poule, renard, vipère »)

Party game Roblox de poursuite à trois équipes, écrit en Luau et synchronisé
avec Roblox Studio grâce à [Rojo](https://rojo.space). Tout est généré par le
code : lobby, cartes (relief en Terrain), mécanismes, interface, effets.

> Règle affichée au joueur : **"Catch your prey. Run from your hunter."**
> Le RENARD attrape la POULE, la POULE attrape la VIPÈRE, la VIPÈRE attrape le RENARD.
> Un joueur attrapé rejoint l'équipe qui l'a attrapé et continue de jouer.

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
    CaptureService.lua     Captures et conversions (validées par le serveur)
    AbilityService.lua     Dash et capacités (mêmes statistiques pour tous)
    LobbyBuilder.lua       Lobby (place du village, vote, roue, boutique, classements)
    HideService, LaunchService, ActorService (joueurs + bots), ...
  Maps/                    Cartes
    MapBase.lua            Système commun : arène, camps, chemins, cachettes, mécanismes
    _Template.lua          Modèle commenté pour créer une carte
    TheFarm, TheCarousel, TheCanyon, TheSwamp
  Util/                    Build (Parts), Props (décors 3D), TerrainKit (relief)
  Bots/                    Bots (noms, apparence, cerveau)
  Data/                    Profil sauvegardé, économie, boutique, roue, classements, Robux
src/client/                -> StarterPlayer.StarterPlayerScripts.Client
  Controllers/             Mouvement, contours, effets et sons, état, données
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

- **Un joueur** : bouton *Play* dans Studio. Une manche se lance avec un seul
  joueur (`Config.Round.MinPlayersToStart = 1`).
- **Plusieurs joueurs** : onglet *Test* -> *Clients and Servers* -> choisir
  *3 Players* (ou plus) -> *Start*. Studio ouvre un serveur et trois clients.
- **Manches rapides** : dans `src/shared/Config.lua`, passe
  `Config.Debug.FastRounds = true` (intermission 8 s, manche 45 s).

Les logs serveur (`[RoundService] ...`, `[MapRegistry] ...`) s'affichent
dans la fenêtre *Output* de Studio.

## Direction artistique et avatars

- **Roblox stylisé et lumineux** : relief en Terrain (vallées, mesas en strates,
  collines fleuries, bayou), décors en Parts aux formes douces (toits en pente,
  arbres, manèges), éclairage Future avec ambiance propre à chaque carte
  (après-midi, heure dorée, coucher de soleil, crépuscule). Réglages dans
  `src/shared/Style.lua` et `Map.Lighting`.
- **Chacun garde son avatar Roblox.** L'équipe se lit en pleine course grâce aux
  attributs de l'animal ajoutés par-dessus (oreilles et queue de renard, crête de
  poule, capuche de vipère), au foulard d'équipe, au contour (vert = ta proie,
  rouge = ton chasseur) et à l'étiquette au-dessus de la tête.
  `Config.Appearance.Mode` : "Accessories" (défaut), "Avatar" ou "Animal".
- **Avatars R6** conseillés : *Home > Game Settings > Avatar > Avatar Type = R6*.
- **Herbe animée du Terrain** : dans Studio, *Workspace > Terrain > Decoration = true*
  (propriété non modifiable par script).

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
   API Services** (sauvegarde et classements) ; *Workspace.Terrain.Decoration = true*.
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
- [ ] Test en conditions réelles dans Studio (sensations, mobile, performance à 16+ joueurs)
- [ ] Sons d'ambiance par carte et musique (identifiants d'assets à choisir)
