# Hunt or Hide

Jeu Roblox de chat à trois équipes (FOX > CHICKEN > SNAKE > FOX), écrit en Luau
et synchronisé avec Roblox Studio grâce à [Rojo](https://rojo.space).
Tout le jeu est généré par le code : lobby, maps, mécanismes et interface.
Rien n'est construit à la main dans Studio.

> Règle affichée au joueur : **"Catch your prey. Run from your hunter."**

## Structure

```
default.project.json     Projet Rojo
rokit.toml               Version de Rojo (Rokit)
src/shared/              -> ReplicatedStorage.Shared (serveur + client)
  Config.lua             Toutes les valeurs d'équilibrage
  Teams.lua              Équipes, couleurs, chaîne de prédation
  MapInfo.lua            Métadonnées d'affichage des maps
  Remotes.lua            Liste des RemoteEvents
  Types.lua              Types Luau partagés
src/server/              -> ServerScriptService.Server
  Main.server.lua        Point d'entrée serveur
  Services/
    RoundService.lua     Boucle de manche (machine à états)
    TeamService.lua      Attribution des équipes
    VoteService.lua      Vote de map
    LobbyBuilder.lua     Construction du lobby
    MapRegistry.lua      Chargement automatique des maps
    AnimalAppearance.lua Apparence d'animal (remplaçable)
  Maps/
    MapBase.lua          Briques communes (sol, bases, limites)
    _Template.lua        Modèle à copier pour une nouvelle map
    TheFarm.lua, TheCarousel.lua, TheCanyon.lua, TheSwamp.lua
  Util/Build.lua         Utilitaires de construction (Parts, SurfaceGui)
src/client/              -> StarterPlayer.StarterPlayerScripts.Client
  Main.client.lua        Point d'entrée client
  UI/HUD.lua             Interface (construite par le code)
  Controllers/           Logique client (état, puis déplacement en phase 2)
reference/               Captures d'écran de référence pour le lobby
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

- **Chacun garde son avatar Roblox.** Rien n'est ajouté ni teinté sur le personnage.
  L'animal se lit par le contour (vert = ta proie, rouge = ton prédateur),
  par un petit badge au-dessus de la tête et par le bandeau en haut de l'écran.
  Pour revenir aux oreilles/crêtes/capuches : `Config.Appearance.Mode = "Animal"`.
- **Ambiance inspirée de Huss Valley** : géométrie simple « gray-box », palette
  industrielle froide et désaturée, brume bleu-gris, lampes chaudes, accents jaunes
  « sécurité » ; les couleurs vives sont réservées au gameplay (équipes, objectifs,
  dangers). Tout est réglable dans `src/shared/Style.lua`.
- **Avatars R6** (comme Huss Valley) : dans Studio, *Home > Game Settings > Avatar >
  Avatar Type = R6*, puis *Save*. Ce réglage ne peut pas être fait par script.
  Les bots sont déjà en R6 (`Config.Bots.RigType`).
- **Éclairage Future** : réglé dans `default.project.json` (Lighting.Technology).

## Ajouter une map

1. Copier `src/server/Maps/_Template.lua` vers `src/server/Maps/<MonId>.lua`
   et remplir `Build`, `GetSpawns`, `StartMode`, `StopMode`, `Cleanup`.
2. Ajouter `<MonId>` dans `src/shared/MapInfo.lua` (nom, mode, phrase, couleur).
3. Ajouter `Config.Maps.<MonId>` dans `src/shared/Config.lua`.

La map entre automatiquement dans le tirage du vote.

## Avancement

- [x] Phase 1 : structure Rojo, Config, équipes, boucle de manche, lobby, vote
- [ ] Phase 2 : capture, conversion, contours vert/rouge, inertie, dash
- [ ] Phase 3 : THE FARM complète (Golden Egg, bras tournant)
- [ ] Phase 4 : bots
- [ ] Phase 5 : les trois autres maps
- [ ] Phase 6 : pièces, boutique, sauvegarde, classements
- [ ] Phase 7 : interface finale, mobile, sons, effets
- [ ] Phase 8 : relecture, exploits, performance à 30 joueurs
