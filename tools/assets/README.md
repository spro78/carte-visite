# Kit d'assets 3D (Blender)

Le décor de Carousel Valley est un kit d'assets **original**, modélisé dans Blender par des scripts Python.
- Aucun modèle n'est téléchargé.
- Aucun asset ni plan d'une autre expérience n'est repris.
- Aucun outil de génération (Meshy) n'a servi : voir « Meshy » plus bas.

## Ce que contient le kit

59 assets, environ 82 000 triangles au total (chaque asset une fois) :

| Famille | Assets |
|---|---|
| Nature | TreeOak, TreeWide, TreeTall, TreeBlossom, TreePine, TreePineTall, TreeFarRound, TreeFarPine, Bush, BushFlower, Shrub, RockSmall/Medium/Large/Tall, FlowerPatch, GrassTuft, Mushrooms, Stump, Log |
| Village | Fence, StoneWall, HayBale, HayStack, Crate, Barrel, Barn (traversable), Windmill + WindmillBlades, Well, Signpost, LampPost, Bench, MarketStall, HayCart, Bridge |
| Fête et objectifs | CarouselHub, CarouselArm (cheval volant), ZoneRing, Nest, Egg, Bunting, HotAirBalloon, BigWheel (grande roue, repère sur les collines) |
| Camps | CampPad, CampGate, CampFlag, FoxDen, ChickenCoop, SnakeHollow |
| Relief de Carousel Valley | ValleyGround (place, piste, allées, taches d'herbe, pierres), ValleyHills1 à 6, Knoll, Creek |

Planches de contrôle (rendus Blender, **pas** des captures du jeu) : `reference/preuves/kit/`.

## Principes de modélisation

- **Unités** : 1 unité Blender = 1 stud.
- **Origine et orientation** :
  - l'origine de chaque asset est au sol, au centre de son emprise ;
  - l'avant (+Y dans Blender) devient le -Z de Roblox (LookVector).
- **Style** :
  - formes rondes et épaisses ;
  - arêtes biseautées, légères irrégularités ;
  - aucun détail plus fin que 0,3 stud.
- **Couleur par rôle** : une pièce ne porte pas sa couleur, mais un rôle (Foliage, Rock, Wood, Team...).
  - La palette de la carte (`src/shared/Kit/Palettes.lua`) donne la teinte.
  - Les rendus Blender relisent cette palette : il n'y a qu'une seule source.
- **Ombre peinte** : les feuillages, buissons et pierres ont une pièce plus sombre pour les faces tournées vers le bas. Le volume se lit même sans ombres portées.
- **Pas de texture, pas d'UV** : matériau SmoothPlastic (Neon pour les ampoules). C'est net sur téléphone et sans chargement d'images.
- **Collisions** : quelques volumes simples par asset (boîtes, cylindres, boules, rampes), posés invisibles par le serveur. Les meshes eux-mêmes ne collisionnent pas.
  - Le serveur, les bots et tous les clients ont donc exactement la même physique.
- **Budget** :
  - triangles de la carte posée : environ 260 000, vérifié par `test_visual` (plafond fixé à 400 000) ;
  - arbres lointains en version légère (56 à 170 triangles).

## Reconstruire le kit

```bash
tools/assets/build.sh            # modèles + export (FBX, données du jeu, manifeste)
tools/assets/build.sh --sheets   # + planches de contrôle (Cycles, environ 2 min)
tools/assets/build.sh --only Barn,Windmill --sheet --no-export   # essai rapide
```

Au premier lancement, le script installe Blender 5.2.2 en module Python (`bpy`) dans `tools/bin/blender-env`. Fichiers produits :
- `assets/kit/HoH_Kit.fbx` : tous les meshes, un objet par pièce (`Asset__Pièce`), pour l'import dans Studio ;
- `src/shared/Kit/Manifest.lua` : pièces, rôles, boîtes, collisions, points d'ancrage ;
- `src/shared/Kit/Meshes/<Asset>.lua` : géométrie compacte (base64), lue par le jeu ;
- `src/shared/Kit/Layouts.lua` : disposition de Carousel Valley et arbres des collines. `test_visual` vérifie que ces valeurs restent égales à `Config.Maps.TheCarousel`.

## Dans le jeu : deux façons d'afficher les meshes

1. **Sans rien faire (Studio, Play)**. Chaque client construit les meshes à partir des données (`EditableMesh`, puis `AssetService:CreateMeshPartAsync`) : `src/client/Controllers/KitController.lua`.
   - Les meshes sont préparés dès le lobby (six à la fois). Quand la carte est posée, le client n'a plus qu'à copier les modèles (`Config.Kit.PiecesPerFrame` par image).
   - Dans une expérience **publiée**, Roblox refuse ces API par défaut.
   - Il faut alors activer *Game Settings > Security > Allow Mesh & Image APIs*. Seul un propriétaire de 13 ans ou plus, à l'identité vérifiée, peut le faire.
   - Si l'API est refusée, le jeu affiche des blocs de remplacement et l'écrit une fois dans la sortie.
2. **Import dans Studio (recommandé pour publier)**. Le serveur copie les MeshParts importés au lieu de laisser les clients construire.
   1. Dans Studio, ouvrir *Import 3D* et choisir `assets/kit/HoH_Kit.fbx`.
   2. Dans la fenêtre d'import :
      - unité du fichier : **studs** ;
      - ne pas fusionner les meshes (un MeshPart par objet) ;
      - pièces ancrées.
   3. Mettre le modèle importé dans **ReplicatedStorage** et le renommer **`HoH_KitMeshes`**. Les MeshParts gardent leur nom (`TreeOak__Trunk`, `Barn__Walls`...).
   4. Enregistrer la place.
      - Avec `rojo serve`, ce dossier n'est pas géré par Rojo et reste dans la place.
      - Avec `rojo build`, il faut le réimporter, ou l'enregistrer en `.rbxm` (clic droit, *Save to File*).
   5. Contrôle visuel : l'arbre est debout, la porte du moulin regarde le manège, les portes de la grange s'ouvrent sur les allées. Sinon, l'import a tourné les axes ; il faut réimporter en changeant l'axe avant ou haut.

   Taille et position viennent du manifeste : un écart d'échelle à l'import est corrigé par le jeu, pas une rotation.

## Points à vérifier dans Studio (non vérifiés ici)

- Sens des faces des meshes construits à la volée. Si des faces avant manquent, passer `Config.Kit.FlipWinding = true`.
- Normales lissées automatiquement (`AddNormal()` sans valeur).
- Clonage d'un MeshPart créé par `CreateMeshPartAsync` (le même mesh pour tous les placements).
- Mémoire et temps de chargement sur téléphone.

Procédure complète : `reference/TEST_STUDIO.md`.

## Meshy

Malcom a autorisé Meshy et dispose d'un compte. Il n'a pas pu servir ici :
- la politique réseau de l'environnement refuse `meshy.ai` et `api.meshy.ai` (403 sur CONNECT) ;
- aucune session de navigateur connectée n'est disponible ;
- aucune clé d'API n'est fournie.

Pour l'utiliser plus tard :
1. Ajouter `meshy.ai` et `api.meshy.ai` aux domaines autorisés de l'environnement.
2. Ajouter une clé d'API en secret (variable `MESHY_API_KEY`).
3. Les modèles générés devront passer par Blender pour suivre les conventions ci-dessus : échelle, origine, rôles de couleur, budget de triangles, volumes de collision.
