# Skins 2D Roblox — 5 designs originaux

Cinq tenues complètes (chemise + pantalon) au format **vêtements classiques** Roblox,
générées par le script `generate_skins.py`. Chaque PNG fait 585 × 559 px et respecte
le gabarit officiel (torse, bras, jambes).

| Design | Idée | Dossier |
|---|---|---|
| Cyber Néon | circuits lumineux cyan/magenta sur fond nuit, cœur hexagonal sur la poitrine | `output/cyber-neon/` |
| Nébuleuse | nuage cosmique, poussière d'étoiles, planète annelée en relief | `output/nebuleuse/` |
| Glitch Pixel | blocs rétro 8 px, bandes décalées façon écran cassé, cœur pixel | `output/glitch-pixel/` |
| Magma | obsidienne fissurée (Voronoi), lave incandescente dans les fentes, noyau brûlant | `output/magma/` |
| Holo Iridescent | reflets arc-en-ciel chromés, lignes de balayage, losange emblème | `output/holo/` |

Dans chaque dossier : `chemise.png`, `pantalon.png` et `apercu.png` (gabarits + avatar).
`output/planche-contact.png` montre les 5 tenues côte à côte.

## Publier sur Roblox

1. Va sur <https://create.roblox.com> → **Avatar** → **Vêtements classiques** (ou roblox.com → Créer → Chemises / Pantalons).
2. Téléverse `chemise.png` comme **Chemise** et `pantalon.png` comme **Pantalon** (ne pas redimensionner).
3. Donne un nom, valide. Roblox demande des frais de publication en Robux (10 R$ par article à la date d'écriture)
   et passe l'article en modération avant qu'il n'apparaisse.
4. Pour tester sans payer : ouvre Roblox Studio, insère un objet `Shirt` / `Pants` dans un personnage et
   mets le PNG comme texture via l'importation d'image (Asset Manager).

## Modifier ou créer d'autres designs

```bash
pip install pillow numpy
python3 generate_skins.py            # écrit dans ./output
python3 generate_skins.py /chemin    # ou ailleurs
```

Chaque design est une classe avec trois méthodes :

- `torso(w, h, kind)` : bande continue de 384 × 128 px (droite → devant → gauche → dos). Le devant commence à x = 64.
- `limb(w, h, kind, idx)` : bande continue de 256 × 64 px qui fait le tour du bras ou de la jambe.
- `cap(w, h, kind)` : faces du dessus et du dessous.

`kind` vaut `"shirt"` ou `"pants"`. Peindre en bandes continues garantit que les motifs
se raccordent sans couture autour du corps. Change la graine (`seed`) pour obtenir une variante.
