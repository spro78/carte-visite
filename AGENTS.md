# Consignes pour les agents (Codex, Claude et autres)

Jeu Roblox **« Poule, poule, renard, vipère »** (nom de travail : *Hunt or Hide*).
- Trois équipes : le renard attrape la poule, la poule attrape la vipère, la vipère attrape le renard.
- Un joueur attrapé est **à terre**. Un coéquipier peut le porter jusqu'à la zone sûre de leur camp, où il se relève.
- Sans secours en 15 s, ou si plus aucun coéquipier n'est debout, il rejoint l'équipe qui l'a attrapé. Pas de prison.
- Quatre cartes, trois camps par carte, chacun avec une zone sûre.
- Règle complète : `README.md`, section « Règles du jeu ».

Pour l'installation et la publication, voir `README.md`.

## Arborescence

- `src/server` : services de manche, cartes (`Maps/`), bots, données ; règles de capture dans `Services/` :
  - `CaptureService` : capture -> mise à terre ;
  - `RescueService` : portage, réanimation, conversion faute de secours ;
  - `SafeZoneService` : zones sûres des camps.

  Outils de construction dans `Util/` :
  - `Build` : pièces ;
  - `Props` : décors ;
  - `Ground` : sol et relief en pièces.
- `src/client` : contrôleurs (déplacement, contours, portage, effets) et interface (`UI/`, kit dans `Theme.lua`).
- `src/shared` : configuration (`Config.lua`), équipes, remotes, types.
- `tools/sim` : simulateur Lune qui exécute le vrai code serveur et client ; tests `test*.luau`.
- `tools/preview` : moteur de rendu three.js des scènes simulées.
- `reference/` :
  - `BIBLE_VISUELLE.md` : direction artistique, à lire avant toute modification visuelle ;
  - `HUSS_VALLEY_NOTES.md` : notes sur la référence ;
  - `preuves/` : images de preuve.

## Règles à respecter

- **Langue** : textes vus par le joueur en anglais, commentaires et documentation en français.
- **Règles de jeu** : on ne change sans une demande explicite de Malcom :
  - ni la capture en triangle ;
  - ni la boucle à terre / portage / réanimation / conversion ;
  - ni les zones sûres ;
  - ni les conditions de victoire ;
  - ni les modes des cartes.

  La logique de mode vit dans `src/server/Maps/The*.lua` (`StartMode`, `ResolveTimeUp`, etc.) et dans `RoundService`. Les modes ne voient que les joueurs debout (`context.GetActors`).
- **Avatars** : l'avatar Roblox de chaque joueur reste intact (corps, vêtements, accessoires, couleurs). L'équipe se lit au contour lumineux seul, sans remplissage, couleurs dans `Teams.lua` :
  - renards orange ;
  - poules jaunes ;
  - vipères vertes (`SNAKE`).
- **Direction artistique** : suivre `reference/BIBLE_VISUELLE.md`.
  - Plein jour.
  - Sol à tenons d'un ton dominant, sans Terrain.
  - Couleurs d'équipe réservées aux équipes.
  - Couloirs de course dégagés.
  - Interface au kit du jeu.
- **Aucune copie** de *Huss Valley* (place 107535308163741) ni d'une autre expérience : ni cartes, ni parcours, ni logo, ni textes, ni modèles, ni icônes, ni sons, ni vignettes, ni agencement d'interface.
- **Économie juste** : la boutique ne vend que des cosmétiques. Aucun achat ne donne d'avantage en jeu.
- **Honnêteté des preuves** : tout rendu de `tools/preview` est un **rendu simulé**, jamais une capture Roblox Studio. La mention est ajoutée automatiquement sous chaque image ; ne pas la retirer. Ce qui n'a pas été vérifié dans Studio doit être dit.

## Vérifier avant de pousser

```bash
tools/check.sh          # types (luau-lsp + API Roblox) + toutes les simulations
tools/check.sh types    # types seulement
tools/check.sh sim      # simulations seulement
```

Toutes les simulations doivent passer :
- `test` : boucle de manche, HUD sur 4 écrans de PC ;
- `test_rescue` : tranche verticale sur le Canyon. Contours, zones sûres, mise à terre, portage à la touche C, lâcher, réanimation, conversion (chrono, sans coéquipier, reset), HUD ;
- `test_bots`, `test_farm`, `test_carousel`, `test_canyon`, `test_swamp` ;
- `test_economy` ;
- `test_mobile` : appareil tactile simulé, paysage et portrait, bouton CARRY ;
- `test_visual` : règles chiffrées de la bible sur chaque carte (dont contraste des contours et zones sûres).

Le simulateur refuse toute propriété qui n'existe pas dans l'API Roblox réelle.

Rendus : `tools/check.sh preview <groupe> [carte]`.
- Groupes : `lobby`, `maps`, `round`, `results`, `mobile`, `players`, `rescue`, `rescue_mobile`.
- Exemple : `tools/check.sh preview players TheCanyon` donne une vue joueur pendant une vraie manche sur le Canyon.
- `rescue` et `rescue_mobile` montrent la tranche verticale : contours, zone sûre, coéquipier à terre, portage, joueur à terre. Les bots sont figés pour la mise en scène.

## Ajouter ou modifier une carte

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
  - rendu réel (tenons, ombres, police, contours Highlight) ;
  - physique réelle du portage (soudure, ancrage, propriété réseau) ;
  - performance ;
  - contrôles tactiles Roblox.
- Protocole à suivre dans Studio : `reference/TEST_STUDIO.md`. Les rendus et la simulation ne comptent pas comme test Studio.
- L'environnement de Claude n'a pas accès à roblox.com, aux vignettes ni à YouTube.
