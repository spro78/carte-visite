"""
assets_nature.py : arbres, buissons, rochers, fleurs, souches.
Silhouettes rondes et épaisses, lisibles de loin ; aucun détail de moins de
0,3 stud ; budget de triangles adapté au téléphone.
"""

import math
import random

from mathutils import Vector

import kitlib as K
from kitdef import asset


# ---------------------------------------------------------------------------
# Troncs et branches
# ---------------------------------------------------------------------------
def trunk(height, r0, r1, lean=(0.0, 0.0), seed=0, branches=(), roots=4, name="trunk"):
    rnd = random.Random(seed)
    pts, radii = [], []
    steps = 6
    for i in range(steps + 1):
        t = i / steps
        bend = math.sin(t * math.pi * 0.8) * 0.35
        pts.append(Vector((lean[0] * t + bend * rnd.uniform(-0.2, 0.2), lean[1] * t, height * t)))
        radii.append(r0 + (r1 - r0) * (t ** 0.8))
    parts = [K.tube(pts, r0, segments=9, radii=radii, name=name)]
    # Racines : petits bourrelets qui s'étalent au pied
    for k in range(roots):
        a = 2 * math.pi * (k + rnd.uniform(-0.15, 0.15)) / roots
        d = Vector((math.cos(a), math.sin(a), 0))
        root_pts = [Vector((0, 0, 0.9)) + d * r0 * 0.3, d * (r0 * 1.2) + Vector((0, 0, 0.35)), d * (r0 * 1.9) + Vector((0, 0, -0.1))]
        parts.append(K.tube(root_pts, r0 * 0.45, segments=7, radii=[r0 * 0.5, r0 * 0.38, r0 * 0.22]))
    # Branches vers la couronne
    for (z, a_deg, length, rise, rad) in branches:
        a = math.radians(a_deg)
        d = Vector((math.cos(a), math.sin(a), 0))
        start = Vector((lean[0] * z / height, lean[1] * z / height, z))
        mid = start + d * length * 0.55 + Vector((0, 0, rise * 0.45))
        end = start + d * length + Vector((0, 0, rise))
        parts.append(K.tube([start, mid, end], rad, segments=7, radii=[rad, rad * 0.8, rad * 0.55]))
    o = K.join(parts, name)
    K.remesh(o, 0.16)
    K.smooth(o, 2, 0.5)
    o = K.target_tris(o, 420)
    return K.shade(o, 50)


def crown(spheres, voxel, noise_strength, noise_scale, seed, tris, flat_bottom=None, name="crown"):
    o = K.blob(spheres, voxel=voxel, smooth_iter=5, noise_strength=noise_strength, noise_scale=noise_scale, seed=seed, name=name)
    if flat_bottom is not None:
        # Dessous légèrement aplati : silhouette de nuage posée sur le tronc
        for v in o.data.vertices:
            if v.co.z < flat_bottom:
                v.co.z = flat_bottom + (v.co.z - flat_bottom) * 0.35
    o = K.target_tris(o, tris)
    return K.shade(o, 70)


# ---------------------------------------------------------------------------
# Arbres feuillus (trois silhouettes) et variante en fleurs
# ---------------------------------------------------------------------------
def round_tree(a, seed, kind, foliage_role="Foliage"):
    rnd = random.Random(seed)
    if kind == "oak":
        h = 8.0
        t = trunk(h, 1.05, 0.62, lean=(0.35, 0.2), seed=seed, branches=[(5.6, 30, 3.2, 3.0, 0.42), (6.2, 200, 3.0, 2.6, 0.38), (6.6, 115, 2.4, 3.2, 0.34)])
        spheres = [(0.3, 0.2, 11.6, 5.0), (3.3, 1.0, 10.6, 3.7), (-3.0, -0.6, 10.8, 3.9), (0.6, -3.0, 10.4, 3.5), (-0.8, 2.8, 12.3, 3.6), (0.5, 0.2, 14.4, 3.3), (2.4, -1.6, 13.2, 3.0)]
        c = crown(spheres, 0.42, 0.9, 3.2, seed, 760, flat_bottom=8.4)
        a.cyl((0, 0, 0), 1.15, 9.5)
    elif kind == "wide":
        h = 6.2
        t = trunk(h, 1.0, 0.6, lean=(-0.3, 0.25), seed=seed, branches=[(4.4, 20, 3.6, 2.2, 0.4), (4.8, 150, 3.8, 2.0, 0.4), (5.2, 260, 3.4, 2.4, 0.36)])
        ring = []
        for k in range(6):
            ang = 2 * math.pi * k / 6 + rnd.uniform(-0.2, 0.2)
            ring.append((math.cos(ang) * 4.6, math.sin(ang) * 4.6, 9.0 + rnd.uniform(-0.4, 0.5), 3.4 + rnd.uniform(-0.3, 0.4), (1, 1, 0.78)))
        spheres = ring + [(0, 0, 10.0, 4.4, (1, 1, 0.8)), (0.6, -0.4, 11.6, 3.2, (1, 1, 0.8))]
        c = crown(spheres, 0.45, 0.8, 3.6, seed, 820, flat_bottom=7.0)
        a.cyl((0, 0, 0), 1.1, 7.5)
    else:  # "tall"
        h = 7.0
        t = trunk(h, 0.95, 0.55, lean=(0.15, -0.2), seed=seed, branches=[(5.4, 70, 1.8, 3.2, 0.32), (6.0, 250, 1.6, 3.4, 0.3)])
        spheres = [(0, 0, 10.2, 3.6), (0.4, 0.2, 13.2, 3.9), (-0.3, -0.2, 16.4, 3.4), (0.2, 0.3, 19.0, 2.6), (1.6, 0.8, 12.0, 2.6), (-1.6, -0.6, 14.6, 2.6)]
        c = crown(spheres, 0.38, 0.7, 2.8, seed, 700, flat_bottom=7.4)
        a.cyl((0, 0, 0), 1.0, 8.5)
    a.piece("Trunk", t, "Trunk")
    light, dark = K.two_tone(c, -0.18)
    K.shade(light, 70)
    K.shade(dark, 70)
    a.piece("Foliage", light, foliage_role)
    a.piece("FoliageShade", dark, foliage_role + "Shade")
    return a


@asset("TreeOak", "Tree", footprint=6)
def tree_oak(a):
    round_tree(a, 11, "oak")


@asset("TreeWide", "Tree", footprint=8)
def tree_wide(a):
    round_tree(a, 23, "wide")


@asset("TreeTall", "Tree", footprint=4.5)
def tree_tall(a):
    round_tree(a, 37, "tall")


@asset("TreeBlossom", "Tree", footprint=6)
def tree_blossom(a):
    round_tree(a, 41, "oak", foliage_role="Blossom")


# ---------------------------------------------------------------------------
# Sapins : étages de cônes à bord ondulé
# ---------------------------------------------------------------------------
def pine(a, seed, tiers, height):
    rnd = random.Random(seed)
    t = trunk(4.2, 0.85, 0.5, seed=seed, roots=3, name="trunk")
    parts = []
    z = 3.0
    for i, (radius, tier_h) in enumerate(tiers):
        prof = [(0.0, 0.0), (radius * 0.78, 0.15), (radius, 0.55), (radius * 0.96, 0.95), (radius * 0.55, tier_h * 0.45), (radius * 0.14, tier_h * 0.9), (0.0, tier_h)]
        cone = K.lathe(prof, segments=14, name=f"tier{i}")
        # Bord ondulé et légère torsion : pas un cône de géométrie
        for v in cone.data.vertices:
            ang = math.atan2(v.co.y, v.co.x)
            rr = math.hypot(v.co.x, v.co.y)
            if rr > radius * 0.6 and v.co.z < 1.2:
                v.co.z -= 0.45 * (0.5 + 0.5 * math.sin(7 * ang + seed + i))
        cone.location = (rnd.uniform(-0.15, 0.15), rnd.uniform(-0.15, 0.15), z)
        cone.rotation_euler = (rnd.uniform(-0.04, 0.04), rnd.uniform(-0.04, 0.04), rnd.uniform(0, 6.28))
        parts.append(K.bake(cone))
        z += tier_h * 0.55
    f = K.join(parts, "pine")
    K.remesh(f, 0.28)
    K.smooth(f, 2, 0.5)
    f = K.target_tris(f, 640)
    light, dark = K.two_tone(f, -0.25)
    K.shade(light, 38)
    K.shade(dark, 38)
    a.piece("Trunk", t, "Trunk")
    a.piece("Foliage", light, "Pine")
    a.piece("FoliageShade", dark, "PineShade")
    a.cyl((0, 0, 0), 1.0, height * 0.6)


@asset("TreePine", "Tree", footprint=5)
def tree_pine(a):
    pine(a, 51, [(5.2, 5.2), (4.3, 4.8), (3.3, 4.4), (2.2, 4.0)], 18)


@asset("TreePineTall", "Tree", footprint=4.5)
def tree_pine_tall(a):
    pine(a, 57, [(4.6, 5.0), (4.0, 4.8), (3.4, 4.6), (2.6, 4.2), (1.7, 3.8)], 22)


# ---------------------------------------------------------------------------
# Buissons : un gros (obstacle de poursuite) et deux petits (décor)
# ---------------------------------------------------------------------------
def bush_shape(seed, count, spread, size, height, tris):
    rnd = random.Random(seed)
    spheres = []
    for k in range(count):
        ang = 2 * math.pi * k / count + rnd.uniform(-0.3, 0.3)
        d = spread * rnd.uniform(0.4, 1.0)
        r = size * rnd.uniform(0.75, 1.05)
        spheres.append((math.cos(ang) * d, math.sin(ang) * d, height * rnd.uniform(0.55, 0.8), r, (1, 1, 0.85)))
    spheres.append((0, 0, height, size * 1.15, (1, 1, 0.9)))
    o = K.blob(spheres, voxel=0.22, smooth_iter=5, noise_strength=0.45, noise_scale=1.4, seed=seed, name="bush")
    o = K.cut_below(o, 0.05)
    o = K.ground(o)
    o = K.target_tris(o, tris)
    return K.shade(o, 70)


@asset("Bush", "Bush", footprint=3.5)
def bush(a):
    o = bush_shape(61, 5, 2.4, 1.8, 1.9, 420)
    light, dark = K.two_tone(o, -0.2)
    a.piece("Leaves", K.shade(light, 70), "FoliageDark")
    a.piece("LeavesShade", K.shade(dark, 70), "FoliageDarkShade")
    a.cyl((0, 0, 0), 2.9, 3.4)


@asset("BushFlower", "Bush", footprint=3)
def bush_flower(a):
    o = bush_shape(67, 4, 1.9, 1.6, 1.6, 380)
    verts = [v.co.copy() for v in o.data.vertices if v.co.z > 1.0]
    light, dark = K.two_tone(o, -0.2)
    a.piece("Leaves", K.shade(light, 70), "Foliage")
    a.piece("LeavesShade", K.shade(dark, 70), "FoliageShade")
    # Fleurs : petites boules blanches à la surface
    rnd = random.Random(5)
    dots = []
    rnd.shuffle(verts)
    for p in verts[:14]:
        dots.append(K.ico(0.32, (p.x, p.y, p.z + 0.12), subdiv=1))
    fl = K.join(dots, "flowers")
    K.shade(fl, 80)
    a.piece("Flowers", fl, "Flower1")
    a.cyl((0, 0, 0), 2.4, 3.0)


@asset("Shrub", "Bush", footprint=1.6)
def shrub(a):
    o = bush_shape(71, 3, 1.0, 1.0, 0.9, 220)
    a.piece("Leaves", o, "FoliageLight")


# ---------------------------------------------------------------------------
# Rochers facettés à chapeau d'herbe (pierre gris-bleu de la palette)
# ---------------------------------------------------------------------------
def rock_shape(seed, size, squash=0.75, tris=260, moss=True):
    rnd = random.Random(seed)
    o = K.ico(1.0, (0, 0, 0), (size[0], size[1], size[2]), subdiv=3)
    K.displace(o, 0.3 * min(size), 0.9, kind="VORONOI", seed=seed)
    o = K.bake(o)
    K.planar(o, 4)
    o = K.bake(o)
    o = K.jitter(o, 0.06 * min(size), seed=seed)
    o.location.z = size[2] * (1 - squash) * 0.5
    o = K.cut_below(o, 0.0)
    o = K.ground(o)
    o = K.target_tris(o, tris)
    K.flat(o)
    if moss:
        top, side = K.split_by_normal(o, 0.82, "moss", "rock")
        return top, side
    return None, o


def rock_asset(a, seed, size, tris, colliders):
    top, side = rock_shape(seed, size, tris=tris)
    a.piece("Rock", side, "Rock")
    if top and len(top.data.polygons) > 0:
        K.flat(top)
        a.piece("Moss", top, "Moss")
    for c in colliders:
        a.box(*c)


@asset("RockSmall", "Rock", footprint=1.6)
def rock_small(a):
    rock_asset(a, 81, (1.6, 1.3, 1.1), 140, [])


@asset("RockMedium", "Rock", footprint=3)
def rock_medium(a):
    rock_asset(a, 83, (3.2, 2.6, 2.4), 260, [((0, 0, 1.4), (5.0, 4.0, 2.8))])


@asset("RockLarge", "Rock", footprint=6)
def rock_large(a):
    rock_asset(a, 87, (6.2, 4.6, 4.8), 420, [((0, 0, 2.6), (10.0, 7.2, 5.2)), ((0, 0, 6.0), (6.0, 4.2, 2.4))])


@asset("RockTall", "Rock", footprint=3.5)
def rock_tall(a):
    rock_asset(a, 89, (2.8, 2.4, 6.5), 320, [((0, 0, 4.0), (4.4, 3.8, 8.0))])


# ---------------------------------------------------------------------------
# Petits décors : fleurs, touffes, champignons, souche, tronc couché
# ---------------------------------------------------------------------------
@asset("FlowerPatch", "Decor", footprint=2.5)
def flower_patch(a):
    rnd = random.Random(91)
    stems, heads = [], {1: [], 2: [], 3: []}
    for k in range(9):
        ang = rnd.uniform(0, 6.28)
        d = rnd.uniform(0.2, 2.2)
        x, y = math.cos(ang) * d, math.sin(ang) * d
        h = rnd.uniform(0.7, 1.3)
        stems.append(K.cylinder(0.08, 0.06, h, (x, y, 0), segments=5))
        col = 1 + k % 3
        petals = []
        for p in range(5):
            pa = 2 * math.pi * p / 5
            petals.append(K.ico(0.2, (x + math.cos(pa) * 0.22, y + math.sin(pa) * 0.22, h), (1, 1, 0.55), subdiv=1))
        heads[col].extend(petals)
    leaves = []
    for k in range(6):
        ang = rnd.uniform(0, 6.28)
        d = rnd.uniform(0.0, 1.8)
        leaves.append(K.ico(0.55, (math.cos(ang) * d, math.sin(ang) * d, 0.15), (1.4, 0.8, 0.35), subdiv=1))
    st = K.join(stems + leaves, "stems")
    K.shade(st, 60)
    a.piece("Stems", st, "Foliage")
    for col, plist in heads.items():
        if plist:
            o = K.join(plist, f"petals{col}")
            K.shade(o, 80)
            a.piece(f"Petals{col}", o, f"Flower{col + 1}")


@asset("GrassTuft", "Decor", footprint=1.2)
def grass_tuft(a):
    rnd = random.Random(95)
    blades = []
    for k in range(9):
        ang = 2 * math.pi * k / 9 + rnd.uniform(-0.2, 0.2)
        lean = rnd.uniform(0.25, 0.6)
        h = rnd.uniform(0.9, 1.6)
        base = Vector((math.cos(ang) * 0.25, math.sin(ang) * 0.25, 0))
        tip = base + Vector((math.cos(ang) * lean, math.sin(ang) * lean, h))
        blades.append(K.tube([base, (base + tip) / 2 + Vector((0, 0, 0.1)), tip], 0.14, segments=4, radii=[0.16, 0.11, 0.02]))
    o = K.join(blades, "tuft")
    K.shade(o, 60)
    a.piece("Blades", o, "GrassDark")


@asset("Mushrooms", "Decor", footprint=1.5)
def mushrooms(a):
    caps, stems, spots = [], [], []
    for (x, y, h, r) in [(0, 0, 1.1, 0.75), (0.9, 0.4, 0.7, 0.5), (-0.6, 0.7, 0.55, 0.4)]:
        stems.append(K.cylinder(r * 0.36, r * 0.3, h, (x, y, 0), segments=8))
        cap = K.lathe([(0.0, 0.0), (r, 0.0), (r * 1.02, r * 0.18), (r * 0.8, r * 0.55), (r * 0.4, r * 0.8), (0.0, r * 0.86)], segments=12, loc=(x, y, h - 0.08))
        caps.append(cap)
        for s in range(3):
            ang = s * 2.1 + x
            spots.append(K.ico(r * 0.16, (x + math.cos(ang) * r * 0.55, y + math.sin(ang) * r * 0.55, h - 0.08 + r * 0.6), (1, 1, 0.5), subdiv=1))
    for name, lst, role in (("Stems", stems, "Stem"), ("Caps", caps, "Mushroom"), ("Spots", spots, "MushroomSpot")):
        o = K.join(lst, name)
        K.shade(o, 60)
        a.piece(name, o, role)


@asset("Stump", "Decor", footprint=1.8)
def stump(a):
    t = K.lathe([(1.45, 0.0), (1.2, 0.35), (1.05, 0.8), (1.0, 1.4), (0.92, 1.45), (0.0, 1.45)], segments=14)
    t = K.jitter(t, 0.06, seed=3)
    K.shade(t, 45)
    ring = K.cylinder(0.8, 0.8, 0.06, (0, 0, 1.45), segments=14)
    K.shade(ring, 30)
    a.piece("Bark", t, "Trunk")
    a.piece("Rings", ring, "WoodLight")
    a.cyl((0, 0, 0), 1.3, 1.5)


@asset("Log", "Decor", footprint=4)
def fallen_log(a):
    body = K.cylinder(0.95, 0.85, 7.0, (0, 0, 0), segments=12)
    body = K.transform(body, loc=(-3.5, 0, 0.9), rot=(0, math.radians(90), 0))
    body = K.jitter(body, 0.08, seed=7)
    K.shade(body, 45)
    ends = []
    for x in (-3.5, 3.5):
        ends.append(K.transform(K.cylinder(0.72, 0.72, 0.08, (0, 0, 0), segments=12), loc=(x + (0.0 if x < 0 else -0.04), 0, 0.9), rot=(0, math.radians(90), 0)))
    e = K.join(ends, "ends")
    K.shade(e, 30)
    moss = K.blob([(-1.0, 0.0, 1.6, 0.9, (1.8, 0.9, 0.4)), (1.4, 0.2, 1.65, 0.7, (1.5, 0.9, 0.35))], voxel=0.18, smooth_iter=3)
    moss = K.target_tris(moss, 120)
    K.shade(moss, 70)
    a.piece("Bark", body, "Trunk")
    a.piece("Ends", e, "WoodLight")
    a.piece("Moss", moss, "Moss")
    a.box((0, 0, 0.9), (7.2, 1.9, 1.8))


# ---------------------------------------------------------------------------
# Arbres lointains (collines) : mêmes silhouettes, très peu de triangles
# ---------------------------------------------------------------------------
@asset("TreeFarRound", "Tree", footprint=5)
def tree_far_round(a):
    t = K.cylinder(0.9, 0.6, 8.5, (0, 0, 0), segments=6)
    c = K.blob([(0, 0, 11.5, 4.6), (2.6, 0.6, 10.6, 3.2), (-2.4, -0.4, 10.8, 3.3), (0.3, 0.2, 14.0, 3.0)], voxel=0.6, smooth_iter=4, noise_strength=0.6, noise_scale=3.0, seed=7)
    c = K.target_tris(c, 150)
    light, dark = K.two_tone(c, -0.2)
    a.piece("Trunk", K.shade(t, 40), "Trunk")
    a.piece("Foliage", K.shade(light, 70), "Foliage")
    a.piece("FoliageShade", K.shade(dark, 70), "FoliageShade")


@asset("TreeFarPine", "Tree", footprint=4)
def tree_far_pine(a):
    t = K.cylinder(0.7, 0.5, 4.0, (0, 0, 0), segments=6)
    tiers = []
    z = 2.6
    for r, h in ((4.8, 6.0), (3.8, 5.4), (2.6, 4.8)):
        tiers.append(K.cylinder(r, 0.0, h, (0, 0, z), segments=7))
        z += h * 0.55
    f = K.join(tiers, "pine")
    light, dark = K.two_tone(f, -0.3)
    a.piece("Trunk", K.shade(t, 40), "Trunk")
    a.piece("Foliage", K.shade(light, 30), "Pine")
    a.piece("FoliageShade", K.shade(dark, 30), "PineShade")
