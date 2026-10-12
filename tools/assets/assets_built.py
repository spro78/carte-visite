"""
assets_built.py : constructions et objets de la vallée (clôtures, murets,
foin, caisses, grange, moulin, puits, poteaux, pont, étal).
Bois aux arêtes arrondies, proportions trapues, lisibles à hauteur de joueur
(un avatar mesure environ 5 studs).
"""

import math
import random

from mathutils import Vector

import kitlib as K
from kitdef import asset


def plank(length, width, thick, loc, rot=(0, 0, 0), r=0.12, seed=0, sag=0.0):
    """Planche/poutre : boîte arrondie, légèrement irrégulière."""
    o = K.rbox((length, width, thick), (0, 0, 0), r=r, segments=1)
    if sag:
        for v in o.data.vertices:
            v.co.z -= sag * (1 - (2 * v.co.x / length) ** 2)
    o = K.jitter(o, 0.025, seed=seed, scale=2.0)
    o.location = loc
    o.rotation_euler = rot
    return K.bake(o)


def post(height, radius, loc, segments=8, cap=True, seed=0):
    o = K.cylinder(radius, radius * 0.92, height, (0, 0, 0), segments=segments)
    if cap:
        top = K.lathe([(radius * 0.92, 0), (radius * 0.75, radius * 0.35), (0.0, radius * 0.55)], segments=segments, loc=(0, 0, height))
        o = K.join([o, top], "post")
    o = K.jitter(o, 0.02, seed=seed)
    o.location = loc
    return K.bake(o)


# ---------------------------------------------------------------------------
# Clôtures et murets (segments de 8 studs, à aligner bout à bout)
# ---------------------------------------------------------------------------
@asset("Fence", "Fence", footprint=4)
def fence(a):
    posts = [post(3.6, 0.32, (x, 0, 0), seed=i) for i, x in enumerate((-4.0, 0.0, 4.0))]
    rails = [plank(8.6, 0.28, 0.5, (0, 0, z), seed=10 + i, sag=0.06) for i, z in enumerate((1.5, 2.7))]
    p = K.join(posts, "posts")
    r = K.join(rails, "rails")
    K.shade(p, 40)
    K.shade(r, 40)
    a.piece("Posts", p, "WoodDark")
    a.piece("Rails", r, "Wood")
    a.box((0, 0, 1.8), (8.6, 0.7, 3.6))


@asset("StoneWall", "Fence", footprint=4)
def stone_wall(a):
    rnd = random.Random(3)
    stones = []
    x = -4.0
    row = 0
    for z, h in ((0.55, 1.1), (1.55, 1.0), (2.4, 0.8)):
        x = -4.0 + (0.6 if row % 2 else 0.0)
        while x < 4.0:
            w = rnd.uniform(1.3, 2.1)
            w = min(w, 4.0 - x)
            if w < 0.6:
                break
            s = K.rbox((w - 0.12, 1.5 - row * 0.15, h - 0.1), (x + w / 2, rnd.uniform(-0.06, 0.06), z), r=0.32, segments=2)
            stones.append(K.jitter(s, 0.07, seed=int(x * 10) + row * 31))
            x += w
        row += 1
    o = K.join(stones, "stones")
    o = K.target_tris(o, 900)
    light, dark = K.two_tone(o, -0.3)
    K.shade(light, 35)
    K.shade(dark, 35)
    a.piece("Stones", light, "Stone")
    a.piece("StonesShade", dark, "RockDark")
    a.box((0, 0, 1.4), (8.2, 1.6, 2.8))


# ---------------------------------------------------------------------------
# Foin, caisses, tonneaux (couvertures de poursuite)
# ---------------------------------------------------------------------------
@asset("HayBale", "Cover", footprint=2)
def hay_bale(a):
    r, length = 1.7, 2.6
    body = K.lathe([(0.0, 0.0), (r * 0.9, 0.0), (r, 0.18), (r, length - 0.18), (r * 0.9, length), (0.0, length)], segments=16)
    body = K.transform(body, loc=(-length / 2, 0, r), rot=(0, math.radians(90), 0))
    body = K.jitter(body, 0.09, seed=5, scale=0.6)
    K.shade(body, 50)
    spirals = []
    for side in (-1, 1):
        ring = K.cylinder(r * 0.62, r * 0.62, 0.06, (0, 0, 0), segments=14)
        spirals.append(K.transform(ring, loc=(side * (length / 2 + 0.01) - (0.06 if side > 0 else 0), 0, r), rot=(0, math.radians(90), 0)))
    s = K.join(spirals, "ends")
    bands = []
    for x in (-0.55, 0.55):
        band = K.lathe([(r + 0.02, -0.12), (r + 0.09, 0.0), (r + 0.02, 0.12)], segments=16, closed=True)
        bands.append(K.transform(band, loc=(x, 0, r), rot=(0, math.radians(90), 0)))
    a.piece("Hay", body, "Hay")
    a.piece("Ends", K.join([s] + bands, "ends"), "Straw")
    a.logc((0, 0, r), r, length)


@asset("HayStack", "Cover", footprint=3.5)
def hay_stack(a):
    bales = []
    for (x, y, z, yaw) in ((-1.6, 0, 0.9, 0.04), (1.6, 0.1, 0.9, -0.03), (0.0, 0.0, 2.65, 0.08)):
        b = K.rbox((3.0, 2.0, 1.75), (0, 0, 0), r=0.35, segments=2)
        b = K.jitter(b, 0.08, seed=int(x * 7 + z * 3), scale=0.7)
        bales.append(K.transform(b, loc=(x, y, z), rot=(0, 0, yaw)))
    o = K.join(bales, "bales")
    light, dark = K.two_tone(o, -0.3)
    a.piece("Hay", K.shade(light, 45), "Hay")
    a.piece("HayShade", K.shade(dark, 45), "Straw")
    a.box((0, 0, 0.9), (6.3, 2.1, 1.8))
    a.box((0, 0, 2.6), (3.1, 2.1, 1.8))


@asset("Crate", "Cover", footprint=1.6)
def crate(a):
    S = 2.8
    body = K.rbox((S - 0.2, S - 0.2, S - 0.2), (0, 0, S / 2), r=0.1, segments=1)
    frame = []
    b = 0.42
    for sx in (-1, 1):
        for sy in (-1, 1):
            frame.append(K.rbox((b, b, S), (sx * (S - b) / 2, sy * (S - b) / 2, S / 2), r=0.1, segments=1))
    inner = S - 2 * b
    for z in (b / 2, S - b / 2):
        for sy in (-1, 1):
            frame.append(K.rbox((inner, b, b), (0, sy * (S - b) / 2, z), r=0.08, segments=1))
        for sx in (-1, 1):
            frame.append(K.rbox((b, inner, b), (sx * (S - b) / 2, 0, z), r=0.08, segments=1))
    # Planche en diagonale sur deux faces
    for sy in (-1, 1):
        d = K.rbox((inner * 1.38, 0.2, b * 0.8), (0, 0, 0), r=0.06, segments=1)
        frame.append(K.transform(d, loc=(0, sy * (S / 2 - 0.08), S / 2), rot=(0, math.radians(45 * sy), 0)))
    f = K.join(frame, "frame")
    a.piece("Box", K.shade(body, 30), "WoodLight")
    a.piece("Frame", K.shade(f, 30), "Wood")
    a.box((0, 0, S / 2), (S, S, S))


@asset("Barrel", "Cover", footprint=1.3)
def barrel(a):
    prof = [(0.0, 0.0), (1.0, 0.0), (1.12, 0.6), (1.22, 1.5), (1.12, 2.4), (1.0, 3.0), (0.0, 3.0)]
    body = K.lathe(prof, segments=14)
    hoops = []
    for z in (0.5, 2.5):
        rr = 1.13 + (0.06 if z == 0.5 else 0.04)
        hoops.append(K.lathe([(rr, -0.12), (rr + 0.06, 0.0), (rr, 0.12)], segments=14, loc=(0, 0, z), closed=True))
    h = K.join(hoops, "hoops")
    lid = K.cylinder(0.9, 0.9, 0.05, (0, 0, 3.0), segments=14)
    a.piece("Staves", K.shade(body, 40), "Wood")
    a.piece("Hoops", K.shade(h, 40), "Metal")
    a.piece("Lid", K.shade(lid, 30), "WoodLight")
    a.cyl((0, 0, 0), 1.2, 3.0)


# ---------------------------------------------------------------------------
# Grange : traversable par ses grandes portes (couloir de poursuite)
# ---------------------------------------------------------------------------
@asset("Barn", "Landmark", footprint=16)
def barn(a):
    W, D, H = 22.0, 28.0, 10.0  # largeur (X), profondeur (Y), hauteur des murs
    door_w, door_h = 9.0, 8.5
    t = 0.8  # épaisseur des murs
    walls = []
    # Murs latéraux pleins
    for sx in (-1, 1):
        walls.append(K.rbox((t, D, H), (sx * (W / 2 - t / 2), 0, H / 2), r=0.2))
    # Pignons avant/arrière : deux montants autour de la porte + linteau + triangle
    for sy in (-1, 1):
        y = sy * (D / 2 - t / 2)
        side_w = (W - door_w) / 2
        for sx in (-1, 1):
            walls.append(K.rbox((side_w, t, H), (sx * (door_w / 2 + side_w / 2), y, H / 2), r=0.2))
        walls.append(K.rbox((door_w + 0.2, t, H - door_h), (0, y, door_h + (H - door_h) / 2), r=0.2))
    # Pignon (profil de toit à la Mansart) : prisme dans le plan XZ
    prof = [(-W / 2, H), (-W / 2 + 2.6, H + 5.0), (0, H + 7.6), (W / 2 - 2.6, H + 5.0), (W / 2, H)]
    for sy in (-1, 1):
        g = K.prism([(x, z) for x, z in prof], -t / 2, t / 2, name="gable")
        g = K.transform(g, loc=(0, sy * (D / 2 - t / 2), 0), rot=(math.radians(90), 0, 0))
        walls.append(g)
    w = K.join(walls, "walls")
    # Toit : profil épaissi, avec débord
    roof_prof = [(-W / 2 - 1.2, H - 0.6), (-W / 2 + 2.3, H + 5.2), (0, H + 8.2), (W / 2 - 2.3, H + 5.2), (W / 2 + 1.2, H - 0.6)]
    roof_parts = []
    for i in range(len(roof_prof) - 1):
        (x0, z0), (x1, z1) = roof_prof[i], roof_prof[i + 1]
        length = math.hypot(x1 - x0, z1 - z0)
        ang = math.atan2(z1 - z0, x1 - x0)
        slab = K.rbox((length + 0.5, D + 2.4, 0.7), (0, 0, 0), r=0.25, segments=2)
        slab = K.transform(slab, loc=((x0 + x1) / 2, 0, (z0 + z1) / 2 + 0.35), rot=(0, -ang, 0))
        roof_parts.append(slab)
    roof = K.join(roof_parts, "roof")
    # Garnitures blanches : chaînes d'angle, encadrements des portes, croix sur les battants
    trims = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            trims.append(K.rbox((1.0, 1.0, H), (sx * (W / 2 - 0.3), sy * (D / 2 - 0.3), H / 2), r=0.2))
    for sy in (-1, 1):
        y = sy * (D / 2 + 0.05)
        for sx in (-1, 1):
            trims.append(K.rbox((0.7, 0.5, door_h), (sx * (door_w / 2 + 0.2), y, door_h / 2), r=0.15))
        trims.append(K.rbox((door_w + 1.1, 0.5, 0.7), (0, y, door_h + 0.2), r=0.15))
        # Lucarne du fenil
        trims.append(K.rbox((4.0, 0.5, 0.5), (0, y, H + 4.6), r=0.12))
        trims.append(K.rbox((4.0, 0.5, 0.5), (0, y, H + 1.4), r=0.12))
        for sx in (-1, 1):
            trims.append(K.rbox((0.5, 0.5, 3.7), (sx * 1.8, y, H + 3.0), r=0.12))
    tr = K.join(trims, "trims")
    # Battants ouverts (rabattus contre la façade) avec croix
    doors, crosses = [], []
    for sy in (-1, 1):
        y = sy * (D / 2 + 0.6)
        for sx in (-1, 1):
            cx = sx * (door_w / 2 + door_w / 4 + 0.5)
            doors.append(K.rbox((door_w / 2, 0.45, door_h - 0.4), (cx, y + sy * 0.25, door_h / 2), r=0.12))
            for k in (-1, 1):
                ang = math.atan2(door_h - 1.2, door_w / 2 - 0.6) * k
                bar = K.rbox((math.hypot(door_w / 2 - 0.6, door_h - 1.2), 0.3, 0.45), (0, 0, 0), r=0.1)
                crosses.append(K.transform(bar, loc=(cx, y + sy * 0.55, door_h / 2), rot=(0, ang, 0)))
            crosses.append(K.rbox((door_w / 2, 0.3, 0.45), (cx, y + sy * 0.55, door_h - 0.6), r=0.1))
            crosses.append(K.rbox((door_w / 2, 0.3, 0.45), (cx, y + sy * 0.55, 0.6), r=0.1))
    d = K.join(doors, "doors")
    c = K.join(crosses + [tr], "trims")
    # Girouette (coq stylisé) au faîte
    vane = K.join([
        K.cylinder(0.12, 0.12, 2.4, (0, 0, H + 8.4), segments=6),
        K.ico(0.7, (0, 0, H + 11.2), (1.2, 0.35, 0.9), subdiv=1),
        K.cylinder(0.08, 0.08, 1.6, (0, 0, H + 9.8), (0, math.radians(90), 0), segments=6),
    ], "vane")
    a.piece("Walls", K.shade(w, 30), "BarnWall")
    a.piece("Roof", K.shade(roof, 30), "RoofDark")
    a.piece("Trims", K.shade(c, 30), "Cream")
    a.piece("Doors", K.shade(d, 30), "BarnDoor")
    a.piece("Vane", K.shade(vane, 40), "Metal")
    # Collisions : murs seulement (on traverse par les portes)
    a.box((-(W / 2 - t / 2), 0, H / 2), (t, D, H))
    a.box(((W / 2 - t / 2), 0, H / 2), (t, D, H))
    side_w = (W - door_w) / 2
    for sy in (-1, 1):
        for sx in (-1, 1):
            a.box((sx * (door_w / 2 + side_w / 2), sy * (D / 2 - t / 2), H / 2), (side_w, t + 1.2, H))
    a.anchor("DoorFront", (0, D / 2 + 2, 0))
    a.anchor("DoorBack", (0, -D / 2 - 2, 0))


# ---------------------------------------------------------------------------
# Moulin : tour, chapeau et ailes (pièce séparée, que le client fait tourner)
# ---------------------------------------------------------------------------
@asset("Windmill", "Landmark", footprint=6)
def windmill(a):
    H = 15.0
    tower = K.lathe([(0.0, 0.0), (5.4, 0.0), (5.4, 1.4), (4.9, 1.6), (4.6, 7.0), (4.0, H), (0.0, H)], segments=8)
    K.shade(tower, 30)
    base = K.lathe([(5.9, 0.0), (6.0, 0.6), (5.7, 1.5), (0.0, 1.5)], segments=16)
    base = K.jitter(base, 0.08, seed=4)
    cap = K.lathe([(4.6, 0.0), (4.7, 0.5), (4.2, 2.2), (2.6, 4.2), (0.8, 5.2), (0.0, 5.4)], segments=12, loc=(0, 0, H - 0.3))
    ball = K.ico(0.6, (0, 0, H + 5.3), subdiv=2)
    cap = K.join([cap, ball], "cap")
    # Porte et fenêtres (encadrements bois), tournées vers l'avant (+Y Blender)
    trims = []
    trims.append(K.rbox((2.8, 0.6, 4.0), (0, 5.05, 3.3), r=0.2))
    for z in (7.5, 11.3):
        trims.append(K.rbox((1.6, 0.5, 1.8), (0, 4.6 - (z - 7.5) * 0.08, z), r=0.15))
    for k in range(8):
        ang = 2 * math.pi * k / 8 + math.pi / 8
        trims.append(K.rbox((0.35, 0.35, H - 1.6), (math.cos(ang) * 4.85, math.sin(ang) * 4.85, (H + 1.6) / 2), (0, 0, ang), r=0.1))
    tr = K.join(trims, "trims")
    tr = K.bake(tr)
    a.piece("Tower", tower, "Wall")
    a.piece("Base", K.shade(base, 35), "Stone")
    a.piece("Cap", K.shade(cap, 35), "RoofDark")
    a.piece("Trims", K.shade(tr, 30), "Wood")
    a.cyl((0, 0, 0), 5.7, H)
    # Moyeu des ailes (asset WindmillBlades, que le client fait tourner)
    a.anchor("Hub", (0, 5.6, H + 2.2))


@asset("WindmillBlades", "Landmark", footprint=7)
def windmill_blades(a):
    """Ailes du moulin, centrées sur le moyeu, dans le plan XZ (Blender) :
    elles tournent autour de l'axe avant (+Y Blender)."""
    sails, cloth = [], []
    sails.append(K.transform(K.cylinder(0.9, 0.7, 1.4, (0, 0, 0), segments=10), loc=(0, -0.4, 0), rot=(math.radians(-90), 0, 0)))
    for k in range(4):
        ang = math.pi / 4 + k * math.pi / 2
        arm = K.rbox((0.5, 0.4, 12.5), (0, 0, 6.6), r=0.12)
        frame = [arm]
        for i in range(5):
            frame.append(K.rbox((3.2, 0.25, 0.25), (1.6, 0, 2.6 + i * 2.3), r=0.08))
        frame.append(K.rbox((0.25, 0.25, 10.2), (3.1, 0, 7.4), r=0.08))
        f = K.join(frame, "sail")
        panel = K.rbox((2.8, 0.12, 9.6), (1.6, -0.15, 7.4), r=0.04, segments=1)
        for obj, lst in ((f, sails), (panel, cloth)):
            lst.append(K.transform(obj, rot=(0, ang, 0)))
    s = K.join(sails, "sails")
    cl = K.join(cloth, "cloth")
    a.piece("Blades", K.shade(s, 30), "WoodDark")
    a.piece("Sails", K.shade(cl, 30), "Cloth")


# ---------------------------------------------------------------------------
# Puits, panneau indicateur, réverbère de fête, banc, étal, charrette, pont
# ---------------------------------------------------------------------------
@asset("Well", "Decor", footprint=3)
def well(a):
    rnd = random.Random(9)
    stones = []
    for ring in range(3):
        n = 10
        for k in range(n):
            ang = 2 * math.pi * (k + (0.5 if ring % 2 else 0)) / n
            s = K.rbox((1.5, 0.9, 0.85), (0, 0, 0), r=0.28)
            s = K.jitter(s, 0.06, seed=ring * 20 + k)
            stones.append(K.transform(s, loc=(math.cos(ang) * 2.3, math.sin(ang) * 2.3, 0.45 + ring * 0.82), rot=(0, 0, ang + math.pi / 2 + rnd.uniform(-0.05, 0.05))))
    st = K.join(stones, "stones")
    st = K.target_tris(st, 900)
    water = K.cylinder(1.9, 1.9, 0.1, (0, 0, 1.6), segments=14)
    wood = [post(5.4, 0.3, (sx * 2.3, 0, 0), seed=sx + 3) for sx in (-1, 1)]
    wood.append(K.rbox((5.4, 0.35, 0.35), (0, 0, 5.1), r=0.1))
    roof = []
    for sy in (-1, 1):
        roof.append(K.transform(K.rbox((6.4, 2.6, 0.3), (0, 0, 0), r=0.12), loc=(0, sy * 1.1, 6.15), rot=(-sy * math.radians(32), 0, 0)))
    bucket = K.lathe([(0.0, 0.0), (0.45, 0.0), (0.55, 0.7), (0.0, 0.7)], segments=10, loc=(0.4, 0, 3.4))
    a.piece("Stones", K.shade(st, 35), "Stone")
    a.piece("Water", K.shade(water, 10), "Water")
    a.piece("Posts", K.shade(K.join(wood + [bucket], "wood"), 40), "Wood")
    a.piece("Roof", K.shade(K.join(roof, "roof"), 30), "RoofDark")
    a.cyl((0, 0, 0), 2.8, 2.6)


@asset("Signpost", "Decor", footprint=1)
def signpost(a):
    p = post(6.5, 0.3, (0, 0, 0), seed=2)
    boards = []
    for i, (z, ang) in enumerate(((5.4, 20), (4.5, 150), (3.6, 270))):
        r = math.radians(ang)
        b = K.prism([(0, -0.55), (2.6, -0.55), (3.3, 0), (2.6, 0.55), (0, 0.55)], -0.12, 0.12, name="arrow")
        b = K.transform(b, loc=(0, 0, 0), rot=(math.radians(90), 0, 0))
        boards.append(K.transform(b, loc=(math.cos(r) * 0.3, math.sin(r) * 0.3, z), rot=(0, 0, r)))
    a.piece("Post", K.shade(p, 40), "WoodDark")
    a.piece("Boards", K.shade(K.join(boards, "boards"), 30), "Plank")
    a.cyl((0, 0, 0), 0.45, 6.5)


@asset("LampPost", "Decor", footprint=0.8)
def lamp_post(a):
    pole = K.lathe([(0.55, 0.0), (0.5, 0.5), (0.24, 0.9), (0.2, 7.2), (0.3, 7.4), (0.0, 7.5)], segments=10)
    arm = K.tube([(0, 0, 7.0), (0.6, 0, 7.8), (1.5, 0, 7.9), (2.0, 0, 7.5)], 0.12, segments=6)
    hood = K.lathe([(0.0, 0.0), (0.55, 0.0), (0.4, 0.45), (0.0, 0.6)], segments=10, loc=(2.0, 0, 7.0))
    bulb = K.ico(0.4, (2.0, 0, 6.9), subdiv=2)
    a.piece("Pole", K.shade(K.join([pole, arm, hood], "pole"), 40), "LampMetal")
    a.piece("Bulb", K.shade(bulb, 80), "Bulb", material="Neon", shadow=False)
    a.cyl((0, 0, 0), 0.5, 7.5)
    a.anchor("Light", (2.0, 0, 6.8))


@asset("Bench", "Decor", footprint=1.6)
def bench(a):
    wood = [plank(4.6, 0.55, 0.22, (0, y, 1.35), seed=i) for i, y in enumerate((-0.3, 0.3))]
    wood += [plank(4.6, 0.22, 0.5, (0, -0.75, 2.2 + i * 0.6), seed=5 + i) for i in range(2)]
    legs = []
    for sx in (-1, 1):
        legs.append(K.rbox((0.35, 1.3, 1.3), (sx * 1.9, 0.0, 0.65), r=0.1))
        legs.append(K.rbox((0.3, 0.3, 1.6), (sx * 1.9, -0.75, 1.95), r=0.08))
    a.piece("Seat", K.shade(K.join(wood, "seat"), 30), "WoodLight")
    a.piece("Legs", K.shade(K.join(legs, "legs"), 30), "WoodDark")
    a.box((0, -0.2, 1.2), (4.7, 1.6, 2.4))


@asset("MarketStall", "Cover", footprint=4)
def market_stall(a):
    counter = K.rbox((7.0, 2.6, 3.0), (0, 0, 1.5), r=0.2)
    top = K.rbox((7.4, 3.0, 0.3), (0, 0, 3.1), r=0.1)
    posts = [post(7.6, 0.25, (sx * 3.3, sy * 1.1, 0), seed=int(sx * 3 + sy)) for sx in (-1, 1) for sy in (-1, 1)]
    # Auvent rayé : bandes alternées (deux pièces) avec bord festonné
    stripes = {0: [], 1: []}
    n = 7
    for i in range(n):
        x0 = -3.9 + i * 7.8 / n
        s = K.rbox((7.8 / n + 0.02, 4.8, 0.2), (x0 + 3.9 / n, 0, 0), r=0.05, segments=1)
        s = K.transform(s, loc=(0, 0.4, 8.2), rot=(math.radians(14), 0, 0))
        half = [(math.cos(math.pi + math.pi * j / 8) * 0.56, math.sin(math.pi + math.pi * j / 8) * 0.56) for j in range(9)]
        flap = K.prism(half, -0.06, 0.06, name="flap")
        flap = K.transform(flap, loc=(x0 + 3.9 / n, 2.72, 7.66), rot=(math.radians(90) + math.radians(14), 0, 0))
        stripes[i % 2] += [s, flap]
    goods = []
    rnd = random.Random(4)
    for k in range(6):
        goods.append(K.ico(0.45, (-2.6 + k * 1.05, rnd.uniform(-0.6, 0.4), 3.6), subdiv=1))
    a.piece("Counter", K.shade(K.join([counter, top], "counter"), 30), "WoodLight")
    a.piece("Posts", K.shade(K.join(posts, "posts"), 40), "Wood")
    a.piece("StripeA", K.shade(K.join(stripes[0], "a"), 30), "FairRed")
    a.piece("StripeB", K.shade(K.join(stripes[1], "b"), 30), "Cream")
    a.piece("Goods", K.shade(K.join(goods, "goods"), 60), "Fruit")
    a.box((0, 0, 1.55), (7.4, 3.0, 3.1))


@asset("HayCart", "Cover", footprint=4)
def hay_cart(a):
    bed = K.rbox((6.4, 3.6, 0.5), (0, 0, 2.0), r=0.15)
    sides = [K.rbox((6.4, 0.3, 1.2), (0, sy * 1.7, 2.8), r=0.1) for sy in (-1, 1)]
    sides += [K.rbox((0.3, 3.6, 1.2), (sx * 3.1, 0, 2.8), r=0.1) for sx in (-1, 1)]
    shaft = [K.rbox((4.0, 0.3, 0.3), (5.0, sy * 0.9, 1.7), (0, math.radians(8), 0), r=0.08) for sy in (-1, 1)]
    wheels, hubs = [], []
    for sx in (-1.6, 1.6):
        for sy in (-1, 1):
            w = K.lathe([(1.2, -0.25), (1.35, 0.0), (1.2, 0.25)], segments=14, closed=True)
            w = K.join([w, K.cylinder(1.22, 1.22, 0.3, (0, 0, -0.15), segments=14)], "wheel")
            wheels.append(K.transform(w, loc=(sx, sy * 2.0, 1.35), rot=(math.radians(90), 0, 0)))
            hubs.append(K.transform(K.cylinder(0.35, 0.35, 0.7, (0, 0, -0.35), segments=8), loc=(sx, sy * 2.05, 1.35), rot=(math.radians(90), 0, 0)))
    hay = K.blob([(-1.4, 0, 3.6, 1.6, (1.3, 1.0, 0.7)), (1.2, 0.2, 3.7, 1.7, (1.3, 1.0, 0.7)), (0, -0.2, 4.4, 1.4, (1.4, 1.0, 0.6))], voxel=0.25, smooth_iter=3, noise_strength=0.25, noise_scale=0.8, seed=8)
    hay = K.target_tris(hay, 320)
    a.piece("Body", K.shade(K.join([bed] + sides + shaft, "body"), 30), "Wood")
    a.piece("Wheels", K.shade(K.join(wheels, "wheels"), 40), "WoodDark")
    a.piece("Hubs", K.shade(K.join(hubs, "hubs"), 40), "Metal")
    a.piece("Hay", K.shade(hay, 60), "Hay")
    a.box((0, 0, 2.2), (6.6, 4.2, 4.4))


@asset("Bridge", "Landmark", footprint=7)
def bridge(a):
    L, Wd = 16.0, 6.0
    arch = 1.6
    planks = []
    n = 16
    for i in range(n):
        x = -L / 2 + (i + 0.5) * L / n
        z = 0.5 + arch * math.cos(math.pi * x / L) ** 0.8 if abs(x) < L / 2 else 0.5
        slope = -arch * math.pi / L * math.sin(math.pi * x / L)
        planks.append(K.transform(plank(L / n - 0.08, Wd, 0.35, (0, 0, 0), seed=i), loc=(x, 0, z), rot=(0, -math.atan(slope), 0)))
    beams, rails = [], []
    for sy in (-1, 1):
        pts = []
        for i in range(13):
            x = -L / 2 + i * L / 12
            pts.append(Vector((x, sy * (Wd / 2 - 0.2), 0.15 + arch * math.cos(math.pi * x / L) ** 0.8)))
        beams.append(K.tube(pts, 0.35, segments=6))
        top = [p + Vector((0, 0, 2.6)) for p in pts]
        rails.append(K.tube(top, 0.2, segments=6))
        for i in range(0, 13, 3):
            p = pts[i]
            rails.append(post(2.8, 0.2, (p.x, p.y, p.z - 0.2), segments=6, seed=i))
    a.piece("Deck", K.shade(K.join(planks, "deck"), 30), "Plank")
    a.piece("Beams", K.shade(K.join(beams, "beams"), 40), "WoodDark")
    a.piece("Rails", K.shade(K.join(rails, "rails"), 40), "Wood")
    # Collisions : deux rampes et un palier, garde-corps
    a.ramp((-L / 2 + 2.6, 0, (arch + 0.6) / 2), (Wd, 5.2, arch + 0.6), rise_towards=0)
    a.ramp((L / 2 - 2.6, 0, (arch + 0.6) / 2), (Wd, 5.2, arch + 0.6), rise_towards=180)
    a.box((0, 0, (arch + 0.6) / 2), (L - 10.4, Wd, arch + 0.6))
    for sy in (-1, 1):
        a.box((0, sy * (Wd / 2 - 0.2), arch + 1.8), (L - 2, 0.4, 2.6))
