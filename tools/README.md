# Outils de développement (hors Studio)

Ces outils permettent de vérifier le jeu sans ouvrir Roblox Studio.
Ils tournent sous Linux, macOS ou Windows (WSL) et n'ont aucun effet sur le jeu publié.

| Commande | Ce qu'elle fait |
|---|---|
| `tools/check.sh types` | Construit la place avec Rojo et vérifie les types de tout `src/` contre l'API Roblox réelle (luau-lsp). |
| `tools/check.sh sim` | Lance `tools/sim/test.luau` : le serveur et des clients factices tournent dans un faux Roblox, en temps virtuel. Des manches entières sont simulées. |
| `tools/check.sh preview` | Exporte la géométrie construite par le code (lobby, maps, manche en cours) et la rend en 3D avec three.js dans Chromium. Les images arrivent dans `tools/preview/out/`. |
| `tools/check.sh` | Types puis simulation. |

Les binaires (Rojo, Lune, luau-lsp) sont téléchargés automatiquement dans `tools/bin/`.
Le rendu nécessite Node.js et Playwright avec Chromium.

## Limites du faux Roblox (`tools/sim`)

- La physique est très simplifiée : sol plat, déplacement en ligne droite des Humanoid, balistique simple.
- Le serveur et les clients partagent les mêmes objets : la réplication est instantanée et sans latence.
- Les animations, les sons et le rendu ne sont pas simulés.

La simulation attrape les erreurs d'exécution et les erreurs de logique de jeu (manches, captures,
scores, sauvegardes). Elle ne remplace pas un vrai test dans Studio pour les sensations de jeu.
