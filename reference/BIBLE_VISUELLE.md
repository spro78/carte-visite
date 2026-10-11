# Bible visuelle : Poule, poule, renard, vipère (Hunt or Hide)

Référence de direction artistique : **Huss Valley, de Huss Valley Official** (place
`107535308163741`, https://www.roblox.com/games/107535308163741/Huss-Valley).
D'autres jeux portent un nom proche et ne servent pas de référence (voir
`HUSS_VALLEY_NOTES.md`, section 0).

Ce qu'on reprend, ce sont des **principes** : lisibilité immédiate, simplicité
assumée, énergie de poursuite.

On ne reprend **aucun** élément concret de la référence :
- ni cartes, ni parcours ;
- ni logo, ni textes ;
- ni modèles, ni icônes, ni sons, ni vignettes ;
- ni interface.

Notre identité reste la nôtre :
- trois équipes (renard, poule, vipère) ;
- trois camps par carte ;
- nos règles et nos mécanismes.

Chaque règle chiffrée ci-dessous est vérifiée par la simulation quand c'est
possible (`tools/sim/test_visual.luau`, tests de disposition du HUD).

---

## 1. Palette

Valeurs mesurées sur les captures de la référence : elles fixent des niveaux à
viser, pas des couleurs à recopier.
- Sol principal : saturation 0,55 à 0,75, luminosité 0,55 à 0,75.
- Dalles claires : saturation ≤ 0,30, luminosité ≥ 0,85.
- Accents : saturation ≥ 0,85, luminosité ≥ 0,9.

Règles pour chaque carte :
- **Au plus 4 couleurs de sol** : sol principal, chemins, une zone d'accent, abords des camps.
- **Valeurs moyennes au sol** (luminosité de 0,5 à 0,8). Un avatar sombre comme un avatar clair s'y détache.
- **Accents saturés réservés aux repères** : manège, grange, balises, mécanismes. Jamais en grandes surfaces au sol.
- **Couleurs d'équipe exclusives**, et elles n'apparaissent que sur trois choses : les joueurs (animal, foulard), les camps et l'interface d'équipe.
  - Couleurs : renard orange (240, 128, 40), poule jaune (250, 222, 90), vipère violet (145, 90, 220).
  - Aucune grande surface de décor (64 studs² ou plus) de la zone de jeu ne s'en approche : teinte à moins de 22°, avec saturation > 0,45 et luminosité > 0,5.
  - Le foin devient ocre, la roche du canyon passe au brun-rouge, le marais n'a plus de violet.

| Biome | Sol | Chemins | Accent | Fond (terrasses) |
|---|---|---|---|---|
| Ferme | vert prairie | terre claire | rouge grange, blanc | gris-bleu + dessus herbe |
| Fête foraine | vert tendre | dalles crème | rayures rouge/bleu/blanc | gris-bleu + dessus herbe, cerisiers |
| Canyon | sable clair | terre battue | bois, cactus vert | brun-rouge en strates, dessus sable |
| Marais | vert mousse | planches | eau turquoise, lanternes | vert sapin + dessus mousse |

## 2. Ciel et éclairage

- **Toujours de jour.** `ClockTime` de 12 à 16,5 ; `Brightness` ≥ 2,2 ; ombres douces (`ShadowSoftness` ≥ 0,2).
- Ciel bleu clair à gros nuages blancs (`Clouds` couverture ≈ 0,55).
- Brume légère : `Atmosphere.Density` ≤ 0,3. Les reliefs lointains pâlissent, mais rien de proche n'est voilé.
- Correction de couleur : saturation +0,1 à +0,2 et contraste ≤ +0,08. Aucune carte sombre ni nocturne.
- Teintes par biome, sans perdre la lumière de jour :
  - fête : après-midi doré ;
  - canyon : chaud et clair ;
  - marais : vert frais.

## 3. Matières

- **Sol de jeu en plaques à tenons** (Plastic + tenons), en grands aplats. Pas de Terrain au sol : son grain brouille la lecture et il se nettoie mal.
- Murs, terrasses et rochers : plastique lisse ou ardoise (Slate), toujours à couleur franche.
- Bois (`WoodPlanks`) pour les constructions. Néon seulement pour de petits points lumineux (balises, ampoules).
- Eau : plaque bleu turquoise semi-transparente (verre), à plat.
- Interdit en grandes surfaces : textures réalistes bruitées (herbe, sable, gravier du Terrain) et matières brillantes.

## 4. Formes et échelle

- Référence : un joueur mesure 5 studs et saute à environ 7 studs.
- Primitives franches : blocs, coins, cylindres, boules. Proportions trapues, aucun détail de moins de 1 stud dans la zone de jeu.
- Arbres **en cubes** (tronc + 3 à 5 gros cubes). Bâtiments en boîtes simples à toit en pente.
- **Fond en terrasses de blocs** : 3 gradins autour de la zone de jeu (environ 12, 26 et 48 studs de haut), dessus plats colorés, arbres en cubes posés dessus.
- Éléments de jeu à leur taille utile :
  - obstacles d'esquive : 4 à 8 studs ;
  - cachettes : 6 à 10 studs ;
  - repères : 25 à 60 studs.
- **Encombrement** : les petits décors (fleurs, caisses, panneaux) restent en bordure ou autour des repères, jamais sur les lignes de course.

## 5. Contraste des équipes et visibilité des joueurs

- Caméra de jeu : caméra Roblox par défaut, à 12,5 studs derrière le joueur, inclinée de 15°, champ de 70°. Toutes les vues de contrôle sont faites avec elle.
- **Couloirs de course** : de chaque camp vers le centre, une bande de 10 studs sans obstacle de plus de 3 studs. Seules exceptions : les mécanismes de jeu et les cachettes voulues.
- Contours : proie en vert, chasseur en rouge, porteur d'objectif en or (toujours au premier plan). Étiquettes à moins de 90 studs.
- Aucune zone sombre ; l'éclairage de jour suffit partout.

## 6. Repères

- Chaque carte a :
  - **un repère central** (le mécanisme), visible de partout ;
  - **trois balises de camp** de 32 studs, aux couleurs de l'équipe ;
  - **2 ou 3 repères de bord**, à silhouette unique.
- Depuis chaque camp, à hauteur d'yeux, on voit les deux autres balises.

## 7. Effets de vitesse et de capture

- Dash : traînée blanche courte, bouffée de poussière, léger élargissement du champ (+5° pendant 0,2 s, joueur local seulement).
- Capture :
  - gerbe aux couleurs du chasseur et onde de choc au sol ;
  - texte flottant court ;
  - petite secousse pour la victime.
- Durée : moins de 0,6 s, 24 effets vivants au plus, et rien ne reste au centre de l'écran.

## 8. Règles du HUD

- **Zone de poursuite libre** : pendant la manche, rien de fixe dans le centre de l'écran (de 20 à 80 % en largeur, de 22 à 78 % en hauteur). Seuls les contours et les étiquettes du monde y apparaissent.
- Haut centre : libellé de phase, rôle, sous-ligne, chrono. 4 lignes au plus ; jusqu'à 168 px de haut sur PC, 112 px sur téléphone.
- **Annonces** : pastille d'une ligne sous le bloc du haut.
  - Taille : ≤ 30 px de haut sur PC, ≤ 22 px sur téléphone ; ≤ 42 % de la largeur.
  - Durée : 1,8 s, une seule à la fois.
  - Contenu : seulement les événements d'objectif. Jamais les points qui défilent : le panneau des équipes les affiche déjà.
- Emplacements :
  - équipes en haut à droite, fil des captures dessous ;
  - pièces en bas à gauche, masquées en manche sur tactile ;
  - capacité et dash en bas au centre (clavier) ;
  - en tactile, boutons ronds autour du bouton de saut de Roblox.
- Fenêtres (aide, boutique, résultats) : uniquement hors manche.
- Typographie : une seule famille, grasse, titres en italique. Texte blanc à contour sombre ; la couleur d'équipe seulement pour les noms d'équipe.
- Aucun chevauchement entre blocs : vérifié pour 4 tailles de PC, 3 téléphones, une tablette et le portrait.

## 9. Ce que chaque carte garde en propre

- **Ferme** : grange rouge traversable, moulin, verger, bras tournant au centre, œuf d'or.
- **Fête foraine** : manège-plateau central, grande roue, chapiteau, montagnes russes en fond, allée de stands.
- **Canyon** : ville western dans la gorge, tunnel de mine, arche de roche, catapulte, nids d'œufs.
- **Marais** : pontons, cabane sur pilotis, saules, tourniquet et geysers.
