"""
terrain_valley.py : relief et sols propres à la carte héroïque « Carousel
Valley » (Id TheCarousel). Ces meshes sont dessinés pour SA disposition :
camps à 110 studs du centre (90°, 210°, 330°), carrousel au centre, piste des
chevaux volants à 62 studs, zone de jeu carrée de 300 studs.

Coordonnées : on raisonne en (x, z) Roblox (plan horizontal), converties en
Blender par (x, z) -> (x, -z). Les mêmes constantes sont écrites dans
src/shared/Kit/Layouts.lua (vérifié par test_visual) : une seule source.
"""

import math
import random

import bmesh
from mathutils import Vector, noise

import kitlib as K
from kitdef import asset

# ---------------------------------------------------------------------------
# Disposition (source de vérité, recopiée dans Layouts.lua)
# ---------------------------------------------------------------------------
LAYOUT = {
    "GroundSize": 300,
    "BaseRadius": 110,
    "BasePadSize": 36,
    "BaseAngles": {"FOX": 90, "CHICKEN": 210, "SNAKE": 330},
    "PlazaRadius": 26,
    "TrackRadius": 62,
    "TrackWidth": 18,
    "LaneWidth": 12,
    "ValleyEdge": 182,  # superellipse (exposant 4) où commencent les collines
    "Knoll": {"Angle": 30, "Radius": 104, "Height": 6},
    "Barn": {"Angle": 150, "Radius": 100},
    "Creek": {"Angle": 270, "Radius": 98},
}


def polar(deg, r):
    a = math.radians(deg)
    return (math.cos(a) * r, math.sin(a) * r)  # (x, z) Roblox


def B(x, z, y=0.0):
    """(x, z) Roblox + hauteur -> Vector Blender."""
    return Vector((x, -z, y))


def edge_radius(theta, a=LAYOUT["ValleyEdge"], p=4.0):
    c, s = abs(math.cos(theta)), abs(math.sin(theta))
    return a / (c ** p + s ** p) ** (1 / p)


# ---------------------------------------------------------------------------
# Outils de surfaces plates (sols peints)
# ---------------------------------------------------------------------------
def fan(points, y, name):
    """Polygone étoilé (rempli depuis son centre), points (x, z) Roblox."""
    bm = bmesh.new()
    cx = sum(p[0] for p in points) / len(points)
    cz = sum(p[1] for p in points) / len(points)
    c = bm.verts.new(B(cx, cz, y))
    ring = [bm.verts.new(B(x, z, y)) for x, z in points]
    n = len(ring)
    for i in range(n):
        bm.faces.new((c, ring[(i + 1) % n], ring[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    return K.obj_from_bm(bm, name)


def annulus(r0, r1, y, name, segments=96, wobble=0.0, seed=0, center=(0.0, 0.0)):
    bm = bmesh.new()
    inner, outer = [], []
    for i in range(segments):
        t = 2 * math.pi * i / segments
        w0 = 1 + wobble * noise.noise(Vector((math.cos(t) * 2 + seed, math.sin(t) * 2, 0.3)))
        w1 = 1 + wobble * noise.noise(Vector((math.cos(t) * 2 + seed, math.sin(t) * 2, 7.1)))
        inner.append(bm.verts.new(B(center[0] + math.cos(t) * r0 * w0, center[1] + math.sin(t) * r0 * w0, y)))
        outer.append(bm.verts.new(B(center[0] + math.cos(t) * r1 * w1, center[1] + math.sin(t) * r1 * w1, y)))
    for i in range(segments):
        j = (i + 1) % segments
        f = bm.faces.new((inner[i], inner[j], outer[j], outer[i]))
    for f in bm.faces:
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
    return K.obj_from_bm(bm, name)


def ribbon(points, width, y, name, wobble=0.0, seed=0, caps=True):
    """Bande de largeur donnée le long d'une polyligne (x, z) Roblox."""
    bm = bmesh.new()
    left, right = [], []
    n = len(points)
    for i, (x, z) in enumerate(points):
        if i == 0:
            dx, dz = points[1][0] - x, points[1][1] - z
        elif i == n - 1:
            dx, dz = x - points[i - 1][0], z - points[i - 1][1]
        else:
            dx, dz = points[i + 1][0] - points[i - 1][0], points[i + 1][1] - points[i - 1][1]
        l = math.hypot(dx, dz) or 1
        nx, nz = -dz / l, dx / l
        wl = width / 2 * (1 + wobble * noise.noise(Vector((x * 0.05 + seed, z * 0.05, 1.7))))
        wr = width / 2 * (1 + wobble * noise.noise(Vector((x * 0.05 + seed, z * 0.05, 9.3))))
        left.append(bm.verts.new(B(x + nx * wl, z + nz * wl, y)))
        right.append(bm.verts.new(B(x - nx * wr, z - nz * wr, y)))
    for i in range(n - 1):
        bm.faces.new((left[i], left[i + 1], right[i + 1], right[i]))
    if caps:
        for end, sign in ((0, -1), (n - 1, 1)):
            x, z = points[end]
            px, pz = points[end - sign] if end == n - 1 else points[1]
            dx, dz = (x - px), (z - pz)
            l = math.hypot(dx, dz) or 1
            dx, dz = dx / l, dz / l
            nx, nz = -dz, dx
            cverts = [left[end]]
            for k in range(1, 6):
                ang = math.pi * k / 6
                cverts.append(bm.verts.new(B(x + (nx * math.cos(ang) + dx * math.sin(ang)) * width / 2, z + (nz * math.cos(ang) + dz * math.sin(ang)) * width / 2, y)))
            cverts.append(right[end])
            c = bm.verts.new(B(x, z, y))
            for k in range(len(cverts) - 1):
                bm.faces.new((c, cverts[k], cverts[k + 1]))
    for f in bm.faces:
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
    return K.obj_from_bm(bm, name)


def thicken(obj, t=0.14):
    """Épaisseur vers le bas (les bords restent visibles en rasant)."""
    return K.solidify(obj, t)


def blob_points(cx, cz, r, seed, count=18, wobble=0.25, sx=1.0, sz=1.0, rot=0.0):
    pts = []
    for x, y in K.blob_outline(r, count, wobble, seed, sx, sz):
        c, s = math.cos(rot), math.sin(rot)
        pts.append((cx + x * c - y * s, cz + x * s + y * c))
    return pts


# ---------------------------------------------------------------------------
# Sols peints de la vallée : place, piste, allées, taches d'herbe, rives
# ---------------------------------------------------------------------------
def lane_points(deg):
    r0 = LAYOUT["PlazaRadius"] - 2
    r1 = LAYOUT["BaseRadius"] - LAYOUT["BasePadSize"] / 2 + 2
    pts = []
    for i in range(14):
        t = i / 13
        r = r0 + (r1 - r0) * t
        # léger S : l'allée n'est pas une règle
        offset = 2.2 * math.sin(t * math.pi * 2) * (1 - t)
        a = math.radians(deg)
        x, z = math.cos(a) * r, math.sin(a) * r
        pts.append((x - math.sin(a) * offset, z + math.cos(a) * offset))
    return pts


def path_clear(x, z, margin=0.0):
    r = math.hypot(x, z)
    if r < LAYOUT["PlazaRadius"] + 4 + margin:
        return False
    tr, tw = LAYOUT["TrackRadius"], LAYOUT["TrackWidth"]
    if abs(r - tr) < tw / 2 + 3 + margin:
        return False
    ang = math.degrees(math.atan2(z, x)) % 360
    for team, deg in LAYOUT["BaseAngles"].items():
        d = abs((ang - deg + 180) % 360 - 180)
        if r * math.sin(math.radians(min(d, 90))) < LAYOUT["LaneWidth"] / 2 + 4 + margin and d < 90:
            return False
        bx, bz = polar(deg, LAYOUT["BaseRadius"])
        if math.hypot(x - bx, z - bz) < 34 + margin:
            return False
    for key in ("Knoll", "Barn", "Creek"):
        f = LAYOUT[key]
        fx, fz = polar(f["Angle"], f["Radius"])
        if math.hypot(x - fx, z - fz) < 24 + margin:
            return False
    return True


@asset("ValleyGround", "Terrain", footprint=150)
def valley_ground(a):
    pr = LAYOUT["PlazaRadius"]
    # Place pavée du carrousel : disque, anneaux et rayons
    plaza = thicken(fan([(math.cos(t) * pr, math.sin(t) * pr) for t in [2 * math.pi * i / 72 for i in range(72)]], 0.16, "plaza"), 0.16)
    rings = [annulus(16.6, 17.6, 0.2, "r1", 72), annulus(21.6, 22.4, 0.2, "r2", 72), annulus(pr - 1.1, pr, 0.2, "r3", 72)]
    spokes = []
    for i in range(16):
        t = 2 * math.pi * (i + 0.5) / 16
        spokes.append(ribbon([(math.cos(t) * 17.6, math.sin(t) * 17.6), (math.cos(t) * 21.6, math.sin(t) * 21.6)], 0.8, 0.2, "spoke", caps=False))
    a.piece("Plaza", K.shade(plaza, 20), "Cobble", shadow=False)
    a.piece("PlazaLines", K.shade(K.join(rings + spokes, "plazalines"), 20), "CobbleDark", shadow=False)
    # Piste des chevaux volants (anneau) et allées vers les camps
    tr, tw = LAYOUT["TrackRadius"], LAYOUT["TrackWidth"]
    track = annulus(tr - tw / 2, tr + tw / 2, 0.12, "track", 120, wobble=0.012, seed=3)
    lanes = [ribbon(lane_points(deg), LAYOUT["LaneWidth"], 0.12, f"lane{deg}", wobble=0.12, seed=deg) for deg in LAYOUT["BaseAngles"].values()]
    paths = thicken(K.join([track] + lanes, "paths"), 0.12)
    a.piece("Paths", K.shade(paths, 20), "Path", shadow=False)
    edges = [annulus(tr - tw / 2 - 0.9, tr - tw / 2 + 0.1, 0.15, "e1", 120, wobble=0.012, seed=3), annulus(tr + tw / 2 - 0.1, tr + tw / 2 + 0.9, 0.15, "e2", 120, wobble=0.012, seed=3)]
    a.piece("PathEdges", K.shade(K.join(edges, "edges"), 20), "PathEdge", shadow=False)
    # Taches d'herbe claire et foncée (le sol n'est jamais d'un seul aplat)
    rnd = random.Random(17)
    light, dark = [], []
    tries = 0
    placed = []
    while len(placed) < 46 and tries < 2000:
        tries += 1
        x, z = rnd.uniform(-150, 150), rnd.uniform(-150, 150)
        r = rnd.uniform(5, 12)
        if not path_clear(x, z, r * 0.6) or any(math.hypot(x - px, z - pz) < r + pr2 for px, pz, pr2 in placed):
            continue
        placed.append((x, z, r))
        pts = blob_points(x, z, r, seed=tries, wobble=0.3, sx=rnd.uniform(0.8, 1.3), sz=rnd.uniform(0.7, 1.1), rot=rnd.uniform(0, 6.28))
        (light if len(placed) % 2 else dark).append(fan(pts, 0.06, "patch"))
    a.piece("PatchesLight", K.shade(K.join(light, "pl"), 20), "GrassLight", shadow=False)
    a.piece("PatchesDark", K.shade(K.join(dark, "pd"), 20), "GrassDark", shadow=False)
    a.anchor("Center", (0, 0, 0))


# ---------------------------------------------------------------------------
# Collines autour de la vallée (plusieurs morceaux, deux tons selon la pente)
# ---------------------------------------------------------------------------
RINGS = [-3, 0, 5, 11, 18, 26, 36, 48, 62, 78, 96, 118, 145, 180, 225, 280]
HILL_SECTORS = 6
TREE_SPOTS = []


def hill_height(theta, d):
    if d <= 0:
        return -0.6
    base = 30 + 16 * noise.noise(Vector((math.cos(theta) * 1.6, math.sin(theta) * 1.6, 0.5)))
    # Pied de colline en douceur (pas de marche au bord de la vallée)
    t = min(d / 64.0, 1.0)
    rise = t * t * (3 - 2 * t)
    bumps = 10 * noise.noise(Vector((math.cos(theta) * 4.0, math.sin(theta) * 4.0, d / 40))) * min(1, d / 45) ** 2
    far = max(0, d - 110) * 0.32 * (0.7 + 0.5 * noise.noise(Vector((math.cos(theta) * 2.2, math.sin(theta) * 2.2, 3.3))))
    return base * rise + bumps + far


def hill_chunk(k):
    seg = 30
    t0 = 2 * math.pi * k / HILL_SECTORS
    bm = bmesh.new()
    grid = []
    for i in range(seg + 1):
        theta = t0 + 2 * math.pi / HILL_SECTORS * i / seg
        re = edge_radius(theta)
        row = []
        for d in RINGS:
            r = re + d
            y = hill_height(theta, d)
            row.append(bm.verts.new(B(math.cos(theta) * r, math.sin(theta) * r, y)))
        grid.append(row)
    for i in range(seg):
        for j in range(len(RINGS) - 1):
            bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
    for f in bm.faces:
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
    o = K.obj_from_bm(bm, f"hills{k}")
    K.triangulate(o)
    return K.bake(o)


for _k in range(HILL_SECTORS):
    def _make(k):
        @asset(f"ValleyHills{k + 1}", "Terrain", footprint=200)
        def hills(a):
            o = hill_chunk(k)
            top, side = K.split_by_normal(o, 0.72, "grass", "slope")
            a.piece("Grass", K.shade(top, 35), "HillGrass")
            a.piece("Slope", K.shade(side, 35), "HillSlope")

    _make(_k)


def tree_spots():
    """Emplacements d'arbres sur les collines (pente douce), déterministes."""
    rnd = random.Random(29)
    spots = []
    for i in range(900):
        theta = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(6, 120)
        h0 = hill_height(theta, d)
        h1 = hill_height(theta, d + 2)
        if abs(h1 - h0) / 2 > 0.55:
            continue
        r = edge_radius(theta) + d
        x, z = math.cos(theta) * r, math.sin(theta) * r
        if any(math.hypot(x - sx, z - sz) < (11 if d < 40 else 16) for sx, _, sz, _ in spots):
            continue
        spots.append((x, h0 - 0.3, z, d))
    return spots


# ---------------------------------------------------------------------------
# Butte du moulin : plateau à flancs rocheux et deux rampes
# (repère : +Y Blender = avant, tourné vers le centre une fois posé)
# ---------------------------------------------------------------------------
KNOLL_R = 19.0
KNOLL_H = LAYOUT["Knoll"]["Height"]
RAMPS = [(90.0, 12.0, 15.0), (-20.0, 10.0, 14.0)]  # (direction en degrés Blender, largeur, longueur)


@asset("Knoll", "Terrain", footprint=KNOLL_R)
def knoll(a):
    outline = K.blob_outline(KNOLL_R, 28, 0.08, seed=5)
    top = K.prism(outline, KNOLL_H - 1.0, KNOLL_H, name="top")
    tm = top.modifiers.new("bevel", "BEVEL")
    tm.width = 0.6
    tm.segments = 2
    tm.limit_method = "ANGLE"
    top = K.bake(top)
    # Flancs : deux strates rocheuses de tons différents, irrégulières, et des
    # blocs éboulés au pied (la butte se lit de loin)
    low = K.prism([(x * 1.02, y * 1.02) for x, y in K.blob_outline(KNOLL_R, 30, 0.1, seed=6)], 0.0, 3.0, name="low")
    low = K.jitter(low, 0.6, seed=2, scale=2.5)
    high = K.prism([(x * 0.985, y * 0.985) for x, y in K.blob_outline(KNOLL_R, 30, 0.09, seed=8)], 2.8, KNOLL_H - 0.5, name="high")
    high = K.jitter(high, 0.45, seed=3, scale=2.5)
    rubble = []
    rnd = random.Random(31)
    for i in range(14):
        ang = 2 * math.pi * i / 14 + rnd.uniform(-0.1, 0.1)
        if any(abs(((math.degrees(ang) - r[0] + 180) % 360) - 180) < 22 for r in RAMPS):
            continue
        rr = KNOLL_R + rnd.uniform(0.6, 1.8)
        b = K.ico(1.0, (0, 0, 0), (rnd.uniform(1.0, 1.8), rnd.uniform(0.9, 1.4), rnd.uniform(0.8, 1.5)), subdiv=1)
        rubble.append(K.transform(b, loc=(math.cos(ang) * rr, math.sin(ang) * rr, 0.5), rot=(0, 0, ang)))
    low = K.target_tris(K.join([low] + rubble, "low"), 700)
    high = K.target_tris(high, 500)
    K.flat(low)
    K.flat(high)
    # Rampes de terre herbeuse
    ramps, ramp_sides = [], []
    for ang, w, length in RAMPS:
        rad = math.radians(ang)
        d = Vector((math.cos(rad), math.sin(rad), 0))
        side = Vector((-d.y, d.x, 0))
        start = d * (KNOLL_R - 1.0)
        end = d * (KNOLL_R - 1.0 + length)
        bm = bmesh.new()
        hw = w / 2
        v = [
            bm.verts.new(start + side * hw + Vector((0, 0, KNOLL_H))),
            bm.verts.new(start - side * hw + Vector((0, 0, KNOLL_H))),
            bm.verts.new(end - side * hw + Vector((0, 0, 0.05))),
            bm.verts.new(end + side * hw + Vector((0, 0, 0.05))),
        ]
        bm.faces.new(v)
        o = K.obj_from_bm(bm, "ramp")
        o = K.solidify(o, 0.8)
        ramps.append(o)
        # Joues rocheuses de part et d'autre de la rampe
        for s in (-1, 1):
            cheek = K.prism([(0, -0.6), (length + 0.5, -0.6), (length + 0.5, 0.6), (0, 0.6)], 0.0, 1.0, name="cheek")
            for vv in cheek.data.vertices:
                t = vv.co.x / (length + 0.5)
                if vv.co.z > 0.5:
                    vv.co.z = KNOLL_H * (1 - t) + 0.4
            cheek = K.transform(cheek, rot=(0, 0, rad))
            cheek = K.transform(cheek, loc=tuple(start + side * s * (hw + 0.5)))
            ramp_sides.append(K.jitter(cheek, 0.15, seed=int(ang) + s))
        a.ramp(tuple(start + d * (length / 2) + Vector((0, 0, KNOLL_H / 2))), (w, length, KNOLL_H), rise_towards=(ang + 180) % 360)
    a.piece("Top", K.shade(K.join([top] + ramps, "top"), 35), "Grass")
    a.piece("RockLow", low, "RockDark")
    a.piece("RockHigh", high, "Rock")
    a.piece("RampSides", K.flat(K.join(ramp_sides, "sides")), "RockDark")
    # Collisions du plateau : trois boîtes croisées (dodécagone)
    for yaw in (0, 60, 120):
        a.box((0, 0, KNOLL_H / 2), (KNOLL_R * 1.72, KNOLL_R * 1.0, KNOLL_H), yaw=yaw)
    a.anchor("Top", (0, 0, KNOLL_H))


# ---------------------------------------------------------------------------
# Ruisseau et ses rives (obstacle franchi par le pont)
# ---------------------------------------------------------------------------
CREEK_L, CREEK_W = 44.0, 11.0


@asset("Creek", "Terrain", footprint=CREEK_L / 2)
def creek(a):
    # Le ruisseau suit X (Blender) ; le pont le franchit selon Y
    pts = []
    for i in range(48):
        t = 2 * math.pi * i / 48
        x = math.cos(t) * CREEK_L / 2
        y = math.sin(t) * CREEK_W / 2 * (1 + 0.18 * math.sin(3 * t + 1.0))
        pts.append((x, y))
    bm = bmesh.new()
    c = bm.verts.new((0, 0, 0.22))
    ring = [bm.verts.new((x, y, 0.22)) for x, y in pts]
    for i in range(len(ring)):
        bm.faces.new((c, ring[i], ring[(i + 1) % len(ring)]))
    water = K.obj_from_bm(bm, "water")
    shore_out = [(x * (1 + 3.2 / CREEK_L * 2), y * (1 + 3.2 / CREEK_W * 2)) for x, y in pts]
    bm = bmesh.new()
    inner = [bm.verts.new((x, y, 0.16)) for x, y in pts]
    outer = [bm.verts.new((x, y, 0.1)) for x, y in shore_out]
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new((inner[i], inner[j], outer[j], outer[i]))
    shore = K.obj_from_bm(bm, "shore")
    for f in shore.data.polygons:
        pass
    a.piece("Water", K.shade(water, 10), "Water", shadow=False)
    a.piece("Shore", K.shade(K.solidify(shore, 0.1), 20), "Dirt", shadow=False)
    # Collisions : le ruisseau est un obstacle, sauf le couloir du pont (|x| < 3)
    for sx in (-1, 1):
        a.box((sx * (CREEK_L / 4 + 1.6), 0, 0.9), (CREEK_L / 2 - 3.2, CREEK_W * 0.95, 1.8))
    a.anchor("Bridge", (0, 0, 0))
