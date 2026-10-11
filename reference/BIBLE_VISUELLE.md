# Bible visuelle : Poule, poule, renard, vipère (Hunt or Hide)

Mini-bible réutilisable pour toute carte, le lobby et l'interface.
- Chaque choix est relié à un **principe observé** sur la référence (P1 à P4), ou à une **contrainte du projet** (C1 à C3).
- Les règles chiffrées sont vérifiées par la simulation :
  - `tools/sim/test_visual.luau` pour les cartes ;
  - `test.luau` et `test_mobile.luau` pour l'interface.
- Le **Canyon** sert d'exemple complet (§11).

---

## 0. Référence et statut de vérification (à lire d'abord)

**Référence** : *Huss Valley*, de **Huss Valley Official**, place `107535308163741`
(https://www.roblox.com/fr/games/107535308163741/Huss-Valley).
Les jeux au nom proche sont écartés dans `HUSS_VALLEY_NOTES.md` (§0).

| Source | Ce qu'elle montre | Vu par Claude ? |
|---|---|---|
| Vignette publique de la place | Terrain vert très simple, ciel bleu, avatars blocky très contrastés, poursuite au premier plan | **Non** : la description vient de Malcom (observation de vignette, pas validation du jeu) |
| 3 captures fournies par Malcom (badge « TEAM FÚTBOL » de l'événement de cette place) | Lobby et écran de fin | Oui |
| Arène de jeu, effets, sons | — | **Non** |

Les domaines Roblox (pages, vignettes, CDN) et YouTube sont bloqués par la politique réseau de l'environnement.

**La référence n'est donc pas vérifiée en jeu.** Cette bible traduit quatre principes lus sur la vignette et les captures. Elle ne prétend pas reproduire l'arène.

## 1. Principes (référence) et contraintes (projet)

**Principes observés** :
- **P1 — Terrain très simple** : un sol plat, d'une couleur dominante, sans texture bruitée.
- **P2 — Ciel bleu** : plein jour, lumière franche.
- **P3 — Avatars blocky à fort contraste** : les joueurs se détachent nettement du décor.
- **P4 — Poursuite au premier plan** : les joueurs qui courent sont le sujet ; le décor et l'interface s'effacent.

**Contraintes du projet** :
- **C1 — Notre identité** :
  - les trois équipes (renard, poule, vipère) et leurs couleurs ;
  - trois camps par carte ;
  - nos règles et nos mécanismes.
- **C2 — Aucune copie** :
  - ni cartes, ni parcours ;
  - ni logo, ni textes ;
  - ni modèles, ni icônes, ni sons, ni vignettes ;
  - ni agencement ou style d'interface.
- **C3 — Lisible sur téléphone** : paysage par défaut, portrait si l'orientation libre est activée.

## 2. Couleurs et sol

| Choix | Pourquoi | Preuve |
|---|---|---|
| Plateau d'un seul ton dominant, bandes à peine visibles (≈ 5 %) | P1 ; bandes = repère de vitesse (P4) | rendus |
| Au plus 4 couleurs au sol : plateau, chemins, une zone d'accent, abords des camps | P1 | revue |
| Plateau à ΔE ≥ 40 (Lab) des 3 couleurs d'équipe, d'un avatar blanc (245, 245, 245) et d'un avatar sombre (27, 42, 53) | P3 | `test_visual` |
| Aucune surface ≥ 64 studs² confondable avec une couleur d'équipe (teinte < 22°, saturation et luminosité à moins de 0,25) | P3, C1 | `test_visual` |
| Couleurs d'équipe réservées : joueurs, camps, interface d'équipe | C1 | `test_visual` |
| Accents saturés seulement sur les repères | P4 | revue |

## 3. Ciel et éclairage

| Choix | Pourquoi | Preuve |
|---|---|---|
| `ClockTime` 12 à 16,5, `Brightness` ≥ 2,2 : jamais de crépuscule ni de nuit | P2 | `test_visual` |
| Brume ≤ 0,3, bleutée, qui voile seulement le fond lointain | P2, P4 | `test_visual` |
| Correction de couleur neutre, saturation +0,10 à +0,20, contraste ≤ +0,08 | P2, P3 | revue |

## 4. Matières et formes

| Choix | Pourquoi | Preuve |
|---|---|---|
| Sol en plaques à tenons, sans Terrain | P1, P3 (avatars blocky dans un monde blocky) | `test_visual` |
| Primitives trapues, végétation en cubes | P3 | rendus |
| Fond en gradins de blocs, dessus du même ton que le plateau | P1 | rendus |
| 4 à 6 silhouettes signature dans le fond (aiguilles, buttes, tours) | P4 : s'orienter sans regarder la carte | rendus |
| Petits décors en bordure ou contre un repère, jamais sur les lignes de course | P4 | `test_visual` (couloirs) |
| **Camps dégagés** : dalle, arche, murets, balise, emblème. Ni tente ni caisses : la caméra du joueur qui apparaît voit la carte | P4 | rendu « spawn » |

Tailles utiles (un joueur mesure 5 studs) :
- obstacles d'esquive : 4 à 8 studs ;
- cachettes : 6 à 10 studs ;
- repères de zone : 20 à 40 studs ;
- balises : 32 studs.

## 5. Repères de poursuite

| Choix | Pourquoi | Preuve |
|---|---|---|
| Couloirs de 10 studs dégagés de chaque camp au centre (pas d'obstacle de plus de 3 studs) | P4 | `test_visual` |
| Obstacles et cachettes entre les couloirs | P4, C1 | `test_visual` |
| Balises de camp de 32 studs, visibles depuis l'entrée des deux autres camps | P4, C1 | `test_visual` |
| Un repère central (le mécanisme) et 3 lieux de zone avec panneau | P4, C1 | rendus |

## 6. Joueurs à l'écran

- Caméra Roblox par défaut pour tous les contrôles : 12,5 studs derrière le joueur, 15° vers le bas, champ de 70° (P4).
- Contours au premier plan : proie en vert, chasseur en rouge, porteur en or (P3, C1).
- **Étiquette d'une ligne** : une puce aux couleurs de l'équipe (animal, ou PREY / HUNTER), puis le pseudo, sans ligne d'infos (P3, P4, C2).

## 7. Effets

- Dash : traînée blanche courte et poussière (P4).
- Capture : gerbe aux couleurs du chasseur, onde au sol, texte bref, secousse de la victime (P4).
- Moins de 0,6 s, 24 effets au plus. Rien ne reste au centre de l'écran (P4).

## 8. Interface : notre kit (C2)

| Choix | Pourquoi | Preuve |
|---|---|---|
| Police Fredoka One, droite ; panneaux vert-de-gris (18, 44, 48) à bord crème ; accent menthe | C2 (ni la police ni les couleurs de la référence) | rendus |
| Haut centre : **capsule chrono** puis **ruban de rôle** bordé à la couleur de l'équipe, puis ligne d'objectif | C2, P4 | `test.luau`, `test_mobile` |
| Menus en haut à droite, à gauche du tableau des équipes ; masqués en manche sur tactile | C2, C3 | `test_mobile` |
| **Médaillons d'action** ronds (dock clavier en bas, autour du saut Roblox en tactile) | C2, C3 | `test_mobile` |
| Fin de manche : bandeau du vainqueur, colonnes d'équipe, 3 cartes de distinction, puce de niveau. Ni onglets, ni podium | C2 | rendus |
| **Annonces** : pastille d'une ligne sous le ruban, ≤ 30 px (PC) ou ≤ 22 px (téléphone), 1,8 s, objectifs seulement | P4 | `test_mobile` |
| Zone de poursuite libre : rien de fixe dans le centre de l'écran pendant la manche | P4 | `test.luau`, `test_mobile` |
| Aucun chevauchement sur 4 PC, 3 téléphones, une tablette et 2 portraits | C3 | `test.luau`, `test_mobile` |

## 9. Appliquer la bible à une carte

1. Thème `MapBase.ArenaTheme` :
   - `Board` / `BoardAlt` : un ton dominant (P1), ΔE ≥ 40 (P3) ;
   - `Path`, `GroundColors` ;
   - `Backdrop` : gradins dont le dessus est du même ton que le plateau.
2. `Map.Lighting` dans les bornes du §3.
3. Repères : mécanisme central, 3 lieux avec panneau, 4 à 6 silhouettes dans le fond.
4. Obstacles et cachettes entre les couloirs ; petits décors en bordure.
5. `tools/check.sh` : `test_visual` doit passer.
6. Rendus `tools/check.sh preview` (vue d'ensemble, vue au sol, vue joueur) :
   - les comparer à ce document, pas à la référence ;
   - garder la mention « RENDU SIMULÉ ».

## 10. Non vérifié dans Roblox Studio

- Rendu réel :
  - tenons, matières, ombres « Future », brume ;
  - Fredoka One telle qu'affichée par Roblox.
- Sensation de vitesse et lisibilité en vraie partie.
- Encoches, zones sûres, joystick et saut réels sur appareil.
- Performance (nombre de pièces, appareils modestes).
- Ressemblance réelle avec la référence : l'arène n'a jamais été vue.

## 11. Exemple complet : The Canyon

Ce qui change, et le principe dont chaque changement découle :

| Élément | Avant | Après | Principe |
|---|---|---|---|
| Sol | Terrain sable clair (226, 186, 128) : ΔE 35 face aux poules, sous le seuil de 40 | Plaques à tenons « sauge » (138, 150, 100) / (131, 143, 95) : ΔE ≥ 46 | P1, P3 |
| Lumière | Crépuscule chaud (16 h 18), brume 0,3 | Plein jour (14 h), ciel bleu, brume 0,18 bleutée | P2 |
| Relief | Mesas lisses en Terrain | Gradins de blocs rouille : (138, 70, 54), (168, 92, 66), (204, 140, 108) ; dessus sauge | P1 |
| Horizon | Uniforme | 3 aiguilles et 3 buttes, une par secteur | P4 |
| Encombrement | 12 petits obstacles, 4 amas rocheux, 18 cactus épars | 6 gros obstacles entre les couloirs, 8 cactus en bordure | P4 |
| Camps | Tente, caisses, tonneau | Camps dégagés (vue de spawn libre) | P4 |
| Végétation | Cactus ronds | Cactus en cubes | P3 |
| Couleurs | Roche orange proche du renard | Aucune surface confondable | P3, C1 |

**Inchangé (C1)** :
- trois équipes, trois camps ;
- mode « Raid » (5 œufs par camp, vol chez la proie) et catapulte ;
- ville, mine traversable, arche.

Preuves (simulation) :
- `test_visual` : 14 contrôles sur le Canyon ;
- `reference/preuves/` :
  - planche avant/après à caméra identique ;
  - vue joueur au spawn et en poursuite ;
  - téléphone en paysage et en portrait.
- Chaque image porte « RENDU SIMULÉ ».
