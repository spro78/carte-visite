# Consignes pour les agents (Codex, Claude et autres)

Jeu Roblox **« Poule, poule, renard, vipère »** (nom de travail : *Hunt or Hide*).
- Trois équipes : le renard attrape la poule, la poule attrape la vipère, la vipère attrape le renard.
- Un joueur attrapé est **à terre**. Un coéquipier peut le porter jusqu'à la zone sûre de leur camp, où il se relève.
- Sans secours en 15 s, ou si plus aucun coéquipier n'est debout, il rejoint l'équipe qui l'a attrapé. Pas de prison.
- Quatre cartes, trois camps par carte, chacun avec une zone sûre. La carte héroïque **Carousel Valley** (`TheCarousel`) est la seule de la rotation pour l'instant (`Config.Round.MapPool`).
- Trois modes votés avant chaque manche : CHASE, EGG RUN, CAROUSEL.
- Règle complète : `README.md`, section « Règles du jeu ».

Pour l'installation et la publication, voir `README.md`.

## Arborescence

- `src/server` : services de manche, cartes (`Maps/`), modes (`Modes/` : Chase, EggRun, Carousel), bots, données ; règles de capture dans `Services/` :
  - `CaptureService` : capture -> mise à terre ;
  - `RescueService` : portage, réanimation, conversion faute de secours ;
  - `SafeZoneService` : zones sûres des camps.

  Outils de construction dans `Util/` :
  - `Kit` : pose des assets du kit 3D (collisions simples côté serveur, meshes importés ou construits par les clients) ;
  - `Build` : pièces ;
  - `Props` : décors en pièces (cartes historiques) ;
  - `Ground` : sol et relief en pièces (cartes historiques).
- `src/client` : contrôleurs (déplacement, contours, portage, meshes du kit `KitController`, effets) et interface (`UI/`, kit dans `Theme.lua`).
- `src/shared` : configuration (`Config.lua`), équipes, modes (`ModeInfo`), remotes, types ; `Kit/` : manifeste, meshes, dispositions (générés) et palettes (à la main).
- `tools/assets` : modélisation Blender en Python (bpy) du kit 3D ; `tools/assets/build.sh` régénère `assets/kit/HoH_Kit.fbx` et `src/shared/Kit`. Ne jamais modifier les fichiers générés à la main.
- `tools/sim` : simulateur Lune qui exécute le vrai code serveur et client ; tests `test*.luau`.
- `tools/preview` : moteur de rendu three.js des scènes simulées.
- `reference/` :
  - `BIBLE_VISUELLE.md` : direction artistique, à lire avant toute modification visuelle ;
  - `HUSS_VALLEY_NOTES.md` : notes sur la référence ;
  - `preuves/` : images de preuve.

## Règles à respecter

- **Langue** : le jeu est en français par défaut (`Config.Language`, `"en"` possible), à la demande de Malcom.
  - Les textes vus par le joueur s'écrivent en anglais dans le code et passent par `Shared/Lang` (`Lang.T`, `Lang.F`, `Lang.Plural`) ; leur traduction française va dans le dictionnaire de `Lang.lua`.
  - Commentaires et documentation en français.
- **Règles de jeu** : on ne change sans une demande explicite de Malcom :
  - ni la capture en triangle ;
  - ni la boucle à terre / portage / réanimation / conversion ;
  - ni les zones sûres ;
  - ni les conditions de victoire ;
  - ni les modes, le vote ou la rotation des équipes.

  Les modes de Carousel Valley vivent dans `src/server/Modes/*.lua` ; ceux des cartes historiques dans `src/server/Maps/The*.lua`. `RoundService` appelle `map.StartMode(context, modeId)`. Les modes ne voient que les joueurs debout (`context.GetActors`).
- **Avatars** : l'avatar Roblox de chaque joueur reste intact (corps, vêtements, accessoires, couleurs). L'équipe se lit au contour lumineux seul, sans remplissage, couleurs dans `Teams.lua` :
  - renards orange ;
  - poules jaunes ;
  - vipères vertes (`SNAKE`).
- **Direction artistique** : suivre `reference/BIBLE_VISUELLE.md`.
  - Plein jour, lumière douce.
  - Décor en assets du kit 3D (Blender) : formes rondes et épaisses, couleurs par rôle (`Kit/Palettes.lua`), pas de Terrain, pas de « carte en blocs ».
  - Couleurs d'équipe réservées aux équipes.
  - Couloirs de course dégagés, repères visibles de loin.
  - Interface au kit du jeu.
- **Aucune copie** de *Huss Valley* (place 107535308163741) ni d'une autre expérience : ni cartes, ni parcours, ni logo, ni textes, ni modèles, ni icônes, ni sons, ni vignettes, ni agencement d'interface.
- **Économie juste** : la boutique ne vend que des cosmétiques. Aucun achat ne donne d'avantage en jeu.
- **Honnêteté des preuves** : tout rendu de `tools/preview` est un **rendu simulé**, jamais une capture Roblox Studio. La mention est ajoutée automatiquement sous chaque image ; ne pas la retirer. Ce qui n'a pas été vérifié dans Studio doit être dit.

## Vérifier avant de pousser

```bash
tools/check.sh          # place + types (luau-lsp + API Roblox) + toutes les simulations
tools/check.sh place    # place seulement : dist/HuntOrHide.rbxl construite et contrôlée
tools/check.sh types    # types seulement
tools/check.sh sim      # simulations seulement
```

`dist/HuntOrHide.rbxl` est la place prête à ouvrir dans Studio. `tools/check.sh` la reconstruit : la pousser avec le code qui l'a produite (la construction est déterministe).

Toutes les simulations doivent passer :
- `test` : boucle de manche, HUD sur 4 écrans de PC ;
- `test_rescue` : tranche verticale sur le Canyon. Contours, zones sûres, mise à terre, portage à la touche C, lâcher, réanimation, conversion (chrono, sans coéquipier, reset), HUD ;
- `test_carousel` : Carousel Valley sur trois vraies manches. Vote (trois modes, votants, tous les joueurs, départage), composition des équipes, EGG RUN, CAROUSEL, CHASE, rotation des animaux ;
- `test_bots`, `test_farm`, `test_canyon`, `test_swamp` ;
- `test_economy` ;
- `test_mobile` : appareil tactile simulé, paysage et portrait, bouton CARRY ;
- `test_visual` : règles chiffrées de la bible sur chaque carte (dont contraste des contours et zones sûres). Sur Carousel Valley, il relit aussi les pièces du kit : couleurs, couloirs et piste dégagés, apparitions et nids hors collisions, budget de triangles ;
- `test_kit` : mémoire des meshes épuisée (comme dans Studio) : aucune erreur, une seule alerte, l'essentiel d'abord, jamais de bloc géant ;
- `test_kit_import` : kit importé dans Studio trouvé, rangé, copié à la bonne taille, contrôle physique écrit dans la sortie ;
- `test_langue` : une manche en français (lobby, vote, aide, équipes, zone sûre, secours, résultats), aucun texte anglais à l'écran, aucune traduction manquante, HUD lisible sur PC et téléphone.

Les scénarios tournent en anglais (`shared.HoH_Language`, posé par `tools/sim/world.luau`) ; `test_langue` et les rendus gardent la langue du jeu.

Le simulateur refuse toute propriété qui n'existe pas dans l'API Roblox réelle.

Rendus : `tools/check.sh preview <groupe> [carte]`.
- Groupes : `lobby`, `maps`, `round`, `results`, `mobile`, `players`, `rescue`, `rescue_mobile`, `hero` (cadrages fixes pour les avant/après), `modes` (vote et mode en jeu : `tools/check.sh preview modes EggRun`).
- Exemple : `tools/check.sh preview players TheCanyon` donne une vue joueur pendant une vraie manche sur le Canyon.
- `rescue` et `rescue_mobile` montrent la tranche verticale : contours, zone sûre, coéquipier à terre, portage, joueur à terre. Les bots sont figés pour la mise en scène.

## Ajouter ou modifier une carte

Nouvelle direction (comme Carousel Valley) :
1. Modéliser les assets manquants dans `tools/assets` (conventions dans `tools/assets/README.md`), puis `tools/assets/build.sh --sheets`.
2. Poser les assets avec `Kit.Place` ; camps avec `MapBase.BuildBases(..., { Kit = true })`.
3. Déclarer les modes de la carte dans `Shared/MapInfo` (`Modes`) et fournir leurs repères (nids, manège...).

Cartes historiques :
1. Partir de `src/server/Maps/_Template.lua`.
2. Thème `MapBase.ArenaTheme` (sol, chemins, gradins).
3. `Map.Lighting` dans les bornes de la bible.
4. Déclarer la carte dans `Config.Maps` et `Shared/MapInfo`.
5. `test_visual` doit passer : couleurs, contraste des avatars, couloirs, balises.

## Travail à plusieurs agents

- **Une branche par agent.** Claude travaille sur `claude/nice-albattani-2x8yqo` (PR #1). Un autre agent ouvre ses propres branches et PR. On ne pousse jamais sur la branche d'un autre agent.
- La revue passe par les commentaires de PR : `@codex review` déclenche Codex. Chaque remarque reçoit une correction poussée ou une réponse qui explique pourquoi pas.
- Les gros changements (règles, structure, économie) se décident avec Malcom.

## Limites connues

- Rien n'a été vérifié dans Roblox Studio ni sur un vrai appareil :
  - meshes du kit construits à la volée (EditableMesh : autorisation, sens des faces, mémoire) ou importés (axes) ;
  - collisions réelles des volumes du kit (butte, rampes, pont, grange) ;
  - rendu réel (ombres, police, contours Highlight) ;
  - physique réelle du portage (soudure, ancrage, propriété réseau) ;
  - performance ;
  - contrôles tactiles Roblox.
- Protocole à suivre dans Studio : `reference/TEST_STUDIO.md`. Les rendus et la simulation ne comptent pas comme test Studio.
- L'environnement de Claude n'a pas accès à roblox.com, aux vignettes, à YouTube ni à Meshy ; Blender y tourne sans fenêtre (module `bpy`).
