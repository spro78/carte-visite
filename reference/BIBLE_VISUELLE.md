# Bible visuelle : Poule, poule, renard, vipère (Hunt or Hide)

Mini-bible réutilisable pour toute carte, le lobby et l'interface.
- Chaque choix est relié à un **principe observé** sur la référence (P1 à P4), ou à une **contrainte du projet** (C1 à C3).
- Les règles chiffrées sont vérifiées par la simulation :
  - `tools/sim/test_visual.luau` pour les cartes ;
  - `test.luau` et `test_mobile.luau` pour l'interface.
- **Carousel Valley** (carte héroïque, décor modélisé dans Blender) sert d'exemple complet (§11). Le Canyon (§12) montre l'ancienne direction en blocs, gardée pour les autres cartes tant qu'elles ne sont pas refaites.

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
- **C4 — Décor modélisé, pas de blocs** (demande de Malcom, après refus des captures en blocs, jugées « trop génériques et trop pauvres ») :
  - silhouettes reconnaissables, relief aux formes travaillées ;
  - composition, chemins et couvertures lisibles, repères mémorables ;
  - palette cohérente, lumière douce ;
  - stylisé, lumineux et soigné, dans l'esprit de la référence, sans en copier ni les assets ni le plan ;
  - assets originaux modélisés (Blender, éventuellement Meshy) puis optimisés pour Roblox et le téléphone, jamais une centaine de pièces primitives.

## 2. Couleurs et sol

| Choix | Pourquoi | Preuve |
|---|---|---|
| Plateau d'un seul ton dominant, bandes à peine visibles (≈ 5 %) | P1 ; bandes = repère de vitesse (P4) | rendus |
| Carte en kit 3D : sol lisse d'un ton dominant, avec des taches d'herbe en trois tons voisins (clair, sombre, frais). Taches larges et douces, jamais de bruit fin | P1, C4 | `test_visual` (ΔE des rôles de sol) |
| Au plus 4 couleurs au sol : plateau, chemins, une zone d'accent, abords des camps | P1 | revue |
| Plateau à ΔE ≥ 40 (Lab) des 3 couleurs d'équipe, d'un avatar blanc (245, 245, 245) et d'un avatar sombre (27, 42, 53) | P3 | `test_visual` |
| Couleurs d'équipe = couleurs des contours : renard orange (240, 128, 40), poule jaune (250, 222, 90), vipère verte (40, 255, 40), plus claire et plus saturée que les sols verts | P3, C1 | `test_visual` |
| Chaque couleur d'équipe à ΔE ≥ 45 du plateau et ≥ 30 des chemins, sur chaque carte (contour lisible en poursuite) | P3, P4 | `test_visual` |
| Aucune surface ≥ 64 studs² confondable avec une couleur d'équipe (teinte < 22°, saturation et luminosité à moins de 0,25) | P3, C1 | `test_visual` |
| Couleurs d'équipe réservées : joueurs, camps, interface d'équipe | C1 | `test_visual` |
| Accents saturés seulement sur les repères | P4 | revue |

## 3. Ciel et éclairage

| Choix | Pourquoi | Preuve |
|---|---|---|
| `ClockTime` 12 à 16,5, `Brightness` ≥ 2,2 : jamais de crépuscule ni de nuit | P2 | `test_visual` |
| Brume ≤ 0,3, bleutée, qui voile seulement le fond lointain | P2, P4 | `test_visual` |
| Correction de couleur neutre, saturation +0,10 à +0,20, contraste ≤ +0,08 | P2, P3 | revue |
| Carte en kit 3D : ombres adoucies (`ShadowSoftness` ≈ 0,5), reflets faibles (`EnvironmentSpecularScale` ≤ 0,4), halo léger (`Bloom` seuil ≥ 1,5) : les volumes arrondis se lisent sans reflets durs | C4 | revue |

## 4. Matières et formes

### 4.1 Direction actuelle : kit 3D modélisé (Carousel Valley)

Tout le décor vient d'un kit d'assets originaux, modélisés dans Blender par des scripts (`tools/assets`, mode d'emploi dans `tools/assets/README.md`).

| Choix | Pourquoi | Preuve |
|---|---|---|
| **Formes rondes et épaisses** : arêtes biseautées, légères irrégularités, aucun détail plus fin que 0,3 stud | C4 ; lisible en mouvement et de loin (P4) | planches `reference/preuves/kit/` |
| **Pas de texture ni d'UV** : SmoothPlastic, Neon pour les ampoules | P1 ; net sur téléphone, aucune image à charger (C3) | `Manifest.lua` |
| **Couleur par rôle** : une pièce porte un rôle (Foliage, Rock, Wood, Team...), la palette de la carte (`src/shared/Kit/Palettes.lua`) donne la teinte. Les planches Blender relisent la même palette | C1 : une seule source, couleurs d'équipe réservées au rôle Team | `test_visual` |
| **Ombre peinte** : feuillages, buissons et pierres ont une pièce plus sombre pour les faces tournées vers le bas | Le volume se lit même sans ombre portée (téléphones modestes) | planches |
| **Relief en meshes** : collines lissées autour de la vallée (pentes plus claires et plus froides que le dessus), butte à strates de roche, ruisseau. Pas de Terrain | P1, C4 | `test_visual` |
| **Collisions simples** : quelques volumes invisibles par asset (boîtes, cylindres, boules, rampes). Les meshes ne collisionnent pas | Même physique pour le serveur, les bots et tous les clients ; pas de collision au triangle | `test_visual` (pistes, nids, spawns) |
| **Repères modélisés** : un repère central animé, un repère par secteur (moulin sur sa butte, grange traversable, ruisseau et pont), une grande silhouette sur l'horizon (grande roue sur les collines, hors de l'aire de jeu) | P4, C4 | rendus « hero » |
| **Camps du kit** : dalle à bord de pierre (couleur d'équipe), portail en bois au nom du camp, drapeau d'équipe de 22 studs, clôtures sur trois côtés, décor de l'animal derrière (tanière, poulailler, creux des vipères). L'entrée reste dégagée | C1, P4 | `test_visual` (balises, zones sûres) |
| **Budget** : moins de 400 000 triangles posés sur la carte ; arbres lointains en version légère (56 à 170 triangles) ; un asset = un mesh réutilisé partout | C3 | `test_visual` (budget) |

### 4.2 Ancienne direction : blocs à tenons (Farm, Canyon, Swamp, lobby)

Gardée tant que ces cartes ne sont pas refaites avec le kit (C4).

| Choix | Pourquoi | Preuve |
|---|---|---|
| Sol en plaques à tenons, sans Terrain | P1, P3 (avatars blocky dans un monde blocky) | `test_visual` |
| Primitives trapues, végétation en cubes | P3 | rendus |
| Fond en gradins de blocs, dessus du même ton que le plateau | P1 | rendus |
| **Camps dégagés** : dalle, arche, murets, balise, emblème. Ni tente ni caisses : la caméra du joueur qui apparaît voit la carte | P4 | rendu « spawn » |

### 4.3 Pour toutes les cartes

| Choix | Pourquoi | Preuve |
|---|---|---|
| 4 à 6 silhouettes signature (aiguilles, buttes, tours, moulin) | P4 : s'orienter sans regarder la carte | rendus |
| Petits décors en bordure ou contre un repère, jamais sur les lignes de course | P4 | `test_visual` (couloirs) |

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
| **Zone sûre** de chaque camp (plateforme + 8 studs sur les côtés, 4 devant, jusqu'à 24 derrière) marquée au sol : liseré pointillé à la couleur de l'équipe éclaircie, « SAFE ZONE » à l'entrée. Plat (0,12 stud), traversable : ne gêne ni la course ni la vue | P4, C1 | `test_visual`, `test_rescue` |
| Un repère central (le mécanisme) et 3 lieux de zone avec panneau | P4, C1 | rendus |
| Objectif mobile (anneaux des chevaux volants) : sur une piste dégagée qui passe devant chaque camp sans entrer dans aucune zone sûre | P4, C1 | `test_visual` (piste libre), `test_carousel` |

## 6. Joueurs à l'écran

- Caméra Roblox par défaut pour tous les contrôles : 12,5 studs derrière le joueur, 15° vers le bas, champ de 70° (P4).
- **Avatars intacts** : corps, vêtements, accessoires et couleurs de chaque joueur restent ceux de son avatar Roblox. Rien n'est ajouté ni recoloré (P3, C1).
- **Contour lumineux seul**, à la couleur de l'équipe, pour chaque joueur, le sien compris (P3, C1) :
  - Highlight sans remplissage, toujours au premier plan ;
  - il ne voile ni l'avatar ni les effets ;
  - au plus 28 contours : le sien, les coéquipiers à terre, puis les plus proches ;
  - un ennemi caché dans les herbes perd son contour, sauf de près.
- **Étiquette d'une ligne** : une puce aux couleurs de l'équipe, puis le pseudo, sans ligne d'infos (P3, P4, C2). La puce affiche :
  - PREY / HUNTER pour qui me concerne, sinon l'animal ;
  - SAFE dans la zone sûre de son camp, bord menthe ;
  - DOWN quand le joueur est à terre.
- **À terre** : couché sur le dos, contour qui pulse. Pour les coéquipiers, un marqueur « HELP » visible de loin indique les secondes restantes et la distance (P4).
- **Porté** : couché à plat ventre sur l'épaule droite du porteur, tête dans son dos (P4).

## 7. Effets

- Dash : traînée blanche courte et poussière (P4).
- Capture : gerbe aux couleurs du chasseur, onde au sol, « DOWN! », secousse de la victime (P4).
- Ramassage : petit nuage de poussière. Réanimation : étincelles de l'équipe, onde, « SAVED! ». Conversion : onde de la nouvelle équipe (P4).
- Moins de 0,6 s, 24 effets au plus. Rien ne reste au centre de l'écran (P4).

## 8. Interface : notre kit (C2)

| Choix | Pourquoi | Preuve |
|---|---|---|
| Police Fredoka One, droite ; panneaux vert-de-gris (18, 44, 48) à bord crème ; accent menthe | C2 (ni la police ni les couleurs de la référence) | rendus |
| Haut centre : **capsule chrono** puis **ruban de rôle** bordé à la couleur de l'équipe (proie et chasseur écrits à la couleur de leur contour), puis ligne d'objectif | C2, P4 | `test.luau`, `test_mobile` |
| **Pastille d'état** d'une ligne sous le bloc du haut, bord à la couleur de l'état ; l'annonce passe dessous. Par priorité : à terre (secondes + jauge), porté, en train de porter, consigne de portage (« Press C… » / « Tap CARRY… »), zone sûre, coéquipier à terre ailleurs | P4, C3 | `test_rescue`, `test_mobile` |
| Médaillon **CARRY** (puce C) dans le dock, ou au-dessus du dash gauche en tactile, seulement près d'un coéquipier à terre ; devient DROP pendant le portage | C2, C3 | `test_rescue`, `test_mobile` |
| Menus en haut à droite, à gauche du tableau des équipes ; masqués en manche sur tactile | C2, C3 | `test_mobile` |
| **Médaillons d'action** ronds (dock clavier en bas, autour du saut Roblox en tactile) | C2, C3 | `test_mobile` |
| Fin de manche : bandeau du vainqueur, colonnes d'équipe, 3 cartes de distinction, puce de niveau. Ni onglets, ni podium | C2 | rendus |
| **Annonces** : pastille d'une ligne sous le ruban, ≤ 30 px (PC) ou ≤ 22 px (téléphone), 1,8 s, objectifs seulement | P4 | `test_mobile` |
| Zone de poursuite libre : rien de fixe dans le centre de l'écran pendant la manche | P4 | `test.luau`, `test_mobile` |
| Aucun chevauchement sur 4 PC, 3 téléphones, une tablette et 2 portraits | C3 | `test.luau`, `test_mobile` |

## 9. Appliquer la bible à une carte

### 9.1 Avec le kit 3D (direction actuelle)

1. Assets : réutiliser le kit ; modéliser ce qui manque dans `tools/assets/assets_*.py` (conventions du §4.1). Un modèle venu de Meshy passe par Blender : échelle, origine au sol, rôles de couleur, budget, volumes de collision.
2. Relief et sols de la carte : un module comme `tools/assets/terrain_valley.py` (sol peint, collines, butte), avec la disposition (`LAYOUT`) recopiée dans `Config.Maps` ; `test_visual` vérifie l'égalité.
3. Palette : une entrée dans `src/shared/Kit/Palettes.lua`, mêmes contrôles de couleur qu'au §2.
4. `tools/assets/build.sh --sheets` : regarder les planches avant d'intégrer.
5. Carte : placer les assets avec `Kit.Place` ; camps avec `MapBase.BuildBases(..., { Kit = true })`.
6. `Map.Lighting` dans les bornes du §3 ; `tools/check.sh` doit passer.
7. Rendus `tools/check.sh preview hero <Carte>` : mêmes cadrages avant/après, mention « RENDU SIMULÉ ».
8. **Test dans Roblox Studio** (`reference/TEST_STUDIO.md`) avant de dire la carte prête : les rendus simulés ne suffisent pas.

### 9.2 En blocs (ancienne direction)

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

- Kit 3D :
  - meshes construits à la volée (`EditableMesh`) : autorisation dans une expérience publiée, sens des faces, normales lissées ;
  - import du FBX : axes, noms, un MeshPart par pièce ;
  - collisions réelles des volumes simples (butte, rampes, pont, grange) ;
  - mémoire et temps de chargement sur téléphone.
- Rendu réel :
  - tenons, matières, ombres « Future », brume ;
  - Fredoka One telle qu'affichée par Roblox.
- Sensation de vitesse et lisibilité en vraie partie.
- Encoches, zones sûres de l'écran, joystick et saut réels sur appareil.
- Contours Highlight réels : épaisseur, lisibilité en mouvement, limite de 31.
- Portage réel : pose du corps soudé, propriété réseau, absence de saccades. Aucune animation dédiée : le corps est posé, pas animé.
- Lisibilité du liseré « SAFE ZONE » au sol.
- Performance (nombre de pièces, appareils modestes).
- Ressemblance réelle avec la référence : l'arène n'a jamais été vue.

## 11. Exemple complet : Carousel Valley (kit 3D)

Ce qui change par rapport à « The Carousel » (fête foraine en blocs), et le principe dont chaque changement découle :

| Élément | Avant (blocs) | Après (kit 3D) | Principe |
|---|---|---|---|
| Sol | Plaques à tenons vertes | Sol lisse (116, 190, 86) avec taches d'herbe en trois tons voisins | P1, C4 |
| Relief | Gradins de blocs bleu-lilas | Six collines lissées qui ferment la vallée ; butte à strates de roche, deux rampes | P1, C4 |
| Repères | Grande roue, montagnes russes, chapiteau, tour, tasses (en blocs, dans l'aire de jeu) | Manège à chevaux volants au centre ; moulin à ailes tournantes sur la butte (30°) ; grange rouge traversable (150°) ; ruisseau et pont (270°) ; grande roue modélisée sur les collines, hors de l'aire de jeu (292°) ; montgolfières | P4, C2, C4 |
| Végétation | Arbres ronds roses et cubes | Six essences (feuillus, cerisiers, conifères), buissons, fleurs ; versions légères sur les collines | C4 |
| Camps | Dalle, arche, murets | Dalle à bord de pierre, portail au nom du camp, drapeau d'équipe, clôtures, tanière / poulailler / creux des vipères | C1, C4 |
| Lumière | Après-midi doré (16 h 06), brume chaude | Plein jour (14 h 18), ombres adoucies, brume bleutée au loin | P2, C4 |
| Mécanisme | Plateforme centrale tournante : tout le monde s'y entasse | Trois chevaux volants autour de la vallée, chacun avec un anneau au sol ; aucun objectif au centre | P4, C1 |
| Modes | Un seul (« King of the Wheel ») | Trois au vote : CHASE, EGG RUN, CAROUSEL | C1 |
| Pièces | 4 798 pièces primitives | 59 assets modélisés, environ 260 000 triangles posés, collisions simples | C3, C4 |

**Inchangé (C1)** :
- trois équipes, trois camps à 110 studs, zones sûres ;
- capture en triangle, mise à terre, portage, réanimation, conversion faute de secours.

Preuves :
- planches du kit (Blender) : `reference/preuves/kit/` ;
- planche avant/après à caméra identique : `reference/preuves/carousel_valley_avant_apres.jpg` ;
- vues joueur et modes : `reference/preuves/carousel_valley_*.jpg` ;
- `test_visual` (couleurs, contraste des contours, couloirs, piste libre, nids, budget) et `test_carousel` (vote, modes).
- Chaque image porte « RENDU SIMULÉ » ou « RENDU BLENDER ». **Aucune n'est une capture de Roblox Studio** ; la carte n'est pas déclarée prête avant le test du protocole `reference/TEST_STUDIO.md`.

## 12. Exemple en blocs : The Canyon

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
- `test_visual` : 20 contrôles sur le Canyon (dont contraste des contours et zones sûres) ;
- `test_rescue` : tranche verticale complète sur le Canyon ;
- `reference/preuves/` :
  - planche avant/après à caméra identique (passe du décor) ;
  - vue joueur au spawn (zone sûre) et pendant une manche simulée ;
  - téléphone en paysage et en portrait ;
  - tranche verticale : `canyon_contours_equipes`, `canyon_zone_sure`, `canyon_coequipier_a_terre`, `canyon_portage`, `canyon_portage_profil`, `canyon_joueur_a_terre`, `canyon_telephone_carry`, `canyon_telephone_carry_portrait`, `canyon_telephone_portage`.
- Chaque image porte « RENDU SIMULÉ ». Aucune n'est une capture de Roblox Studio (protocole : `reference/TEST_STUDIO.md`).
