"""
assets_fair.py : carrousel (moyeu fixe et bras tournants à chevaux volants),
anneau de zone, nid et œuf, guirlande, montgolfière, et éléments des camps
(portail, drapeau, tanière du renard, poulailler, creux des vipères).
Les couleurs d'équipe ne servent qu'aux éléments des camps (rôle « Team »).
"""

import math
import random

from mathutils import Vector

import kitlib as K
from kitdef import asset
from assets_built import plank, post

RING_RADIUS = 62.0  # rayon de la piste du carrousel (même valeur que la carte)
ARM_HEIGHT = 19.0  # hauteur des bras au-dessus du sol
RIDE_HEIGHT = 8.4  # centre du cheval volant (on passe dessous)


# ---------------------------------------------------------------------------
# Cheval de manège stylisé (corps, crinière, selle, sabots)
# ---------------------------------------------------------------------------
def horse(scale=1.0, seed=0, tris=1300):
    s = scale
    body = [
        (0, 0, 0, 1.0, (1.05, 2.4, 1.1)),
        (0, 1.55, 0.2, 1.05),
        (0, -1.45, 0.08, 1.1),
    ]
    parts = [K.sphere(r, (x, y, z), sc if len(t) > 4 else (1, 1, 1), segments=18, rings=10) for t in body for (x, y, z, r, *rest) in [t] for sc in [rest[0] if rest else (1, 1, 1)]]
    parts.append(K.tube([Vector((0, 1.7, 0.55)), Vector((0, 2.35, 1.5)), Vector((0, 2.75, 2.35))], 0.7, segments=10, radii=[0.78, 0.62, 0.5]))
    head = K.sphere(1.0, (0, 0, 0), (0.55, 1.15, 0.62), segments=16, rings=10)
    parts.append(K.transform(head, loc=(0, 3.3, 2.45), rot=(math.radians(32), 0, 0)))
    for sx in (-1, 1):
        parts.append(K.transform(K.cylinder(0.22, 0.02, 0.8, (0, 0, 0), segments=6), loc=(sx * 0.28, 2.85, 2.95), rot=(math.radians(-15), sx * math.radians(10), 0)))
    legs = []
    for sx in (-1, 1):
        legs.append([Vector((sx * 0.5, 1.6, -0.5)), Vector((sx * 0.5, 2.45, -1.15)), Vector((sx * 0.5, 2.15, -2.05))])
        legs.append([Vector((sx * 0.5, -1.6, -0.5)), Vector((sx * 0.5, -2.4, -1.4)), Vector((sx * 0.5, -3.2, -1.85))])
    for lp in legs:
        parts.append(K.tube(lp, 0.32, segments=8, radii=[0.4, 0.3, 0.26]))
    b = K.join(parts, "horse")
    K.remesh(b, 0.13)
    K.smooth(b, 3, 0.6)
    b = K.target_tris(b, tris)
    K.shade(b, 60)
    # Crinière et queue
    mane = []
    for i in range(6):
        t = i / 5
        p = Vector((0, 1.75 + t * 1.15, 0.95 + t * 1.75)) + Vector((0, -0.25, 0.32))
        mane.append(K.sphere(0.42 - t * 0.08, p, (0.7, 1.0, 1.0), segments=10, rings=6))
    mane.append(K.tube([Vector((0, -2.45, 0.35)), Vector((0, -3.3, 0.1)), Vector((0, -3.75, -0.9)), Vector((0, -3.6, -1.7))], 0.35, segments=8, radii=[0.45, 0.42, 0.32, 0.12]))
    m = K.join(mane, "mane")
    K.remesh(m, 0.12)
    K.smooth(m, 2, 0.5)
    m = K.target_tris(m, max(120, tris // 4))
    K.shade(m, 60)
    # Selle et tapis
    saddle = K.rbox((1.9, 1.7, 0.45), (0, 0.1, 1.15), r=0.2)
    blanket = K.rbox((2.5, 1.5, 1.2), (0, 0.15, 0.55), r=0.25)
    sd = K.join([saddle, blanket], "saddle")
    K.shade(sd, 40)
    hooves = []
    for lp in legs:
        hooves.append(K.sphere(0.32, tuple(lp[-1]), (1, 1, 0.7), segments=8, rings=5))
    hv = K.join(hooves, "hooves")
    out = []
    for o in (b, m, sd, hv):
        o.scale = (s, s, s)
        out.append(K.bake(o))
    return out


def twisted_pole(z0, z1, radius, loc=(0, 0, 0), turns=6, n=12, segments=6):
    pts, radii = [], []
    for i in range(n + 1):
        t = i / n
        pts.append(Vector((loc[0], loc[1], z0 + (z1 - z0) * t)))
        radii.append(radius * (1 + 0.18 * math.sin(t * turns * 2 * math.pi)))
    return K.tube(pts, radius, segments=segments, radii=radii)


def scallops(radius, z, count, flap_r, colors=2, tilt=0.0):
    """Festons demi-disques le long d'un cercle ; retourne une liste par couleur."""
    groups = [[] for _ in range(colors)]
    for i in range(count):
        ang = 2 * math.pi * (i + 0.5) / count
        half = [(math.cos(math.pi + math.pi * j / 8) * flap_r, math.sin(math.pi + math.pi * j / 8) * flap_r) for j in range(9)]
        flap = K.prism(half, -0.06, 0.06, name="flap")
        flap = K.transform(flap, rot=(math.radians(90) + tilt, 0, 0))
        flap = K.transform(flap, loc=(math.cos(ang) * radius, math.sin(ang) * radius, z), rot=(0, 0, ang + math.pi / 2))
        groups[i % colors].append(flap)
    return groups


# ---------------------------------------------------------------------------
# Carrousel : moyeu fixe (plateforme, colonne, auvent rayé, chevaux)
# ---------------------------------------------------------------------------
@asset("CarouselHub", "Landmark", footprint=15)
def carousel_hub(a):
    R = 15.2
    base = K.lathe([(0.0, 0.0), (R, 0.0), (R, 0.7), (R - 0.8, 0.75), (R - 0.8, 1.4), (0.0, 1.4)], segments=40)
    floor = K.cylinder(R - 1.0, R - 1.0, 0.06, (0, 0, 1.4), segments=40)
    trim = K.join([
        K.lathe([(R + 0.05, 0.55), (R + 0.2, 0.7), (R + 0.05, 0.85)], segments=40, closed=True),
        K.lathe([(R - 0.75, 1.3), (R - 0.6, 1.45), (R - 0.75, 1.6)], segments=40, closed=True),
    ], "trim")
    column = K.lathe([(3.4, 1.4), (3.4, 2.4), (2.9, 2.8), (2.9, 10.8), (3.5, 11.4), (3.5, 12.6), (2.2, 13.0), (0.0, 13.0)], segments=16)
    rings = K.join([K.lathe([(3.05, z - 0.25), (3.25, z), (3.05, z + 0.25)], segments=16, closed=True) for z in (4.0, 7.0, 10.0)], "rings")
    poles, horses_b, manes, saddles, hooves = [], [], [], [], []
    for i in range(12):
        ang = 2 * math.pi * i / 12
        x, y = math.cos(ang) * 10.6, math.sin(ang) * 10.6
        poles.append(twisted_pole(1.4, 12.4, 0.2, (x, y, 0), turns=4))
        if i % 2 == 0:
            z = 5.0 if i % 4 == 0 else 6.0
            parts = horse(0.72, seed=i, tris=520)
            for o, lst in zip(parts, (horses_b, manes, saddles, hooves)):
                lst.append(K.transform(o, loc=(x, y, z), rot=(0, 0, ang)))
            a.box((x, y, z - 0.1), (1.7, 4.6, 3.0), yaw=math.degrees(ang) - 90)
    # Auvent : bandes rayées, bord festonné, ampoules
    canopy = {0: [], 1: []}
    n = 16
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = 2 * math.pi * (i + 1) / n
        pts = []
        prof = [(16.2, 12.4), (13.0, 14.1), (8.0, 16.3), (3.0, 18.0), (0.6, 18.6)]
        bm_parts = []
        verts = []
        for r, z in prof:
            verts.append([(math.cos(a0) * r, math.sin(a0) * r, z), (math.cos(a1) * r, math.sin(a1) * r, z)])
        import bmesh
        bm = bmesh.new()
        vv = [[bm.verts.new(p) for p in row] for row in verts]
        for k in range(len(vv) - 1):
            bm.faces.new((vv[k][0], vv[k][1], vv[k + 1][1], vv[k + 1][0]))
        o = K.obj_from_bm(bm, "stripe")
        o = K.solidify(o, 0.35)
        canopy[i % 2].append(o)
    val = scallops(16.25, 12.3, 24, 1.2)
    bulbs = [K.ico(0.36, (math.cos(2 * math.pi * (i + 0.5) / 24) * 16.4, math.sin(2 * math.pi * (i + 0.5) / 24) * 16.4, 12.55), subdiv=0) for i in range(24)]
    finial = K.join([
        K.ico(0.9, (0, 0, 19.3), subdiv=2),
        K.cylinder(0.35, 0.05, 2.2, (0, 0, 19.9), segments=8),
    ], "finial")
    flag = K.prism([(0, 0), (2.4, 0.7), (0, 1.4)], -0.05, 0.05, name="flag")
    flag = K.transform(flag, loc=(0.1, 0, 20.6), rot=(math.radians(90), 0, 0))
    a.piece("Base", K.shade(base, 30), "FairBlue")
    a.piece("Floor", K.shade(floor, 20), "WoodLight")
    a.piece("Trim", K.shade(K.join([trim, rings, finial], "trim"), 40), "Gold")
    a.piece("Column", K.shade(column, 30), "FairLilac")
    a.piece("Poles", K.shade(K.join(poles, "poles"), 40), "Gold")
    a.piece("Horses", K.join(horses_b, "horses"), "Cream")
    a.piece("Manes", K.join(manes, "manes"), "Gold")
    a.piece("Saddles", K.join(saddles, "saddles"), "FairRed")
    a.piece("Hooves", K.join(hooves, "hooves"), "WoodDark")
    a.piece("CanopyA", K.shade(K.join(canopy[0] + val[0], "ca"), 30), "FairRed")
    a.piece("CanopyB", K.shade(K.join(canopy[1] + val[1], "cb"), 30), "Cream")
    a.piece("Bulbs", K.shade(K.join(bulbs, "bulbs"), 80), "Bulb", material="Neon", shadow=False)
    a.piece("Flag", K.shade(flag, 30), "FairBlue")
    a.cyl((0, 0, 0), R, 0.7)
    a.cyl((0, 0, 0), R - 0.8, 1.4)
    a.cyl((0, 0, 0), 3.5, 18.0)


# ---------------------------------------------------------------------------
# Bras tournant du carrousel : poutre ornée et cheval volant au bout
# (tourne autour de l'origine ; le client l'anime, aucune collision)
# ---------------------------------------------------------------------------
@asset("CarouselArm", "Ride", footprint=RING_RADIUS)
def carousel_arm(a):
    R = RING_RADIUS
    beam = K.tube([Vector((4.0, 0, ARM_HEIGHT + 0.6)), Vector((R * 0.5, 0, ARM_HEIGHT + 0.3)), Vector((R, 0, ARM_HEIGHT))], 0.55, segments=8)
    truss = [K.tube([Vector((8.0, 0, ARM_HEIGHT - 1.6)), Vector((R * 0.55, 0, ARM_HEIGHT - 2.4)), Vector((R - 3, 0, ARM_HEIGHT - 1.4))], 0.28, segments=6)]
    for i in range(1, 10):
        x = 8 + (R - 11) * i / 10
        zt = ARM_HEIGHT + 0.6 - 0.6 * (x / R)
        zb = ARM_HEIGHT - 1.6 - 0.8 * math.sin(math.pi * (x - 8) / (R - 11))
        truss.append(K.tube([Vector((x, 0, zb)), Vector((x + (2.5 if i % 2 else -2.5), 0, zt - 0.2))], 0.16, segments=5))
    rings = [K.lathe([(0.62, -0.2), (0.75, 0.0), (0.62, 0.2)], segments=10, closed=True) for _ in range(6)]
    rings = [K.transform(r, loc=(10 + i * (R - 14) / 5, 0, ARM_HEIGHT + 0.6 - 0.6 * ((10 + i * (R - 14) / 5) / R)), rot=(0, math.radians(90), 0)) for i, r in enumerate(rings)]
    cap = K.ico(1.0, (R, 0, ARM_HEIGHT), subdiv=2)
    bulbs = [K.ico(0.34, (x, 0, ARM_HEIGHT - 0.75 + 0.6 * (1 - x / R)), subdiv=0) for x in range(10, int(R) - 2, 5)]
    pole = twisted_pole(RIDE_HEIGHT - 0.6, ARM_HEIGHT, 0.26, (R, 0, 0), turns=5, n=16, segments=8)
    parts = horse(1.0, seed=3)
    named = []
    for o in parts:
        named.append(K.transform(o, loc=(R, 0, RIDE_HEIGHT)))
    a.piece("Beam", K.shade(K.join([beam] + truss, "beam"), 40), "FairBlue")
    a.piece("Trim", K.shade(K.join(rings + [cap, pole], "trim"), 40), "Gold")
    a.piece("Bulbs", K.shade(K.join(bulbs, "bulbs"), 80), "Bulb", material="Neon", shadow=False)
    a.piece("Horse", named[0], "Cream")
    a.piece("Mane", named[1], "Gold")
    a.piece("Saddle", named[2], "Saddle")
    a.piece("Hooves", named[3], "WoodDark")
    a.anchor("Ride", (R, 0, 0))


@asset("ZoneRing", "Ride", footprint=10)
def zone_ring(a):
    ring = K.lathe([(9.2, 0.0), (10.0, 0.0), (10.0, 0.14), (9.2, 0.14)], segments=48, closed=True)
    # Chevrons au sol qui indiquent le sens de rotation
    marks = []
    for i in range(8):
        ang = 2 * math.pi * i / 8
        chev = K.prism([(-0.5, -0.9), (0.5, 0.0), (-0.5, 0.9), (-0.1, 0.0)], 0.0, 0.14, name="chev")
        chev = K.transform(chev, loc=(math.cos(ang) * 8.0, math.sin(ang) * 8.0, 0), rot=(0, 0, ang + math.pi / 2))
        marks.append(chev)
    a.piece("Ring", K.shade(K.join([ring] + marks, "ring"), 30), "Zone", shadow=False)


# ---------------------------------------------------------------------------
# Nid et œuf (mode Egg Run)
# ---------------------------------------------------------------------------
@asset("Nest", "Objective", footprint=2.5)
def nest(a):
    torus = K.lathe([(1.2 + 0.75 * math.cos(t), 0.75 + 0.75 * math.sin(t)) for t in [math.pi * (1.5 - k / 10) for k in range(21)]], segments=20)
    torus = K.jitter(torus, 0.12, seed=2, scale=0.5)
    inner = K.cylinder(1.4, 1.4, 0.3, (0, 0, 0.05), segments=16)
    sticks = []
    rnd = random.Random(6)
    for k in range(10):
        ang = rnd.uniform(0, 6.28)
        p0 = Vector((math.cos(ang) * 1.9, math.sin(ang) * 1.9, rnd.uniform(0.6, 1.2)))
        d = Vector((math.cos(ang + 1.4), math.sin(ang + 1.4), rnd.uniform(-0.2, 0.2))) * 1.3
        sticks.append(K.tube([p0 - d, p0 + d], 0.1, segments=5))
    a.piece("Straw", K.shade(K.join([torus, inner], "straw"), 60), "Straw")
    a.piece("Sticks", K.shade(K.join(sticks, "sticks"), 50), "WoodDark")


@asset("Egg", "Objective", footprint=0.9)
def egg(a):
    prof = []
    n = 16
    for i in range(n + 1):
        th = math.pi * i / n
        z = (1 - math.cos(th)) * 1.15
        r = math.sin(th) * (0.82 + 0.1 * math.cos(th))
        prof.append((max(r, 0.0), z))
    shell = K.lathe(prof, segments=20)
    # Bande en zigzag, posée sur la coquille
    band_prof = []
    for z in (1.0, 1.06, 1.12, 1.18):
        th = math.acos(1 - z / 1.15)
        band_prof.append((math.sin(th) * (0.82 + 0.1 * math.cos(th)) + 0.03, z))
    band = K.lathe(band_prof, segments=24)
    for v in band.data.vertices:
        ang = math.atan2(v.co.y, v.co.x)
        v.co.z += 0.09 * math.sin(8 * ang)
    a.piece("Shell", K.shade(shell, 80), "Egg")
    a.piece("Band", K.shade(band, 60), "EggBand")


# ---------------------------------------------------------------------------
# Guirlande de fanions (16 studs, étirée par la carte), montgolfière
# ---------------------------------------------------------------------------
@asset("Bunting", "Decor", footprint=8)
def bunting(a):
    L, sag = 16.0, 1.3
    pts = [Vector((-L / 2 + L * i / 16, 0, -sag * (1 - (2 * i / 16 - 1) ** 2))) for i in range(17)]
    rope = K.tube(pts, 0.06, segments=4)
    flags = [[], [], []]
    for i in range(9):
        x = -L / 2 + (i + 0.5) * L / 9
        z = -sag * (1 - (2 * (x + L / 2) / L - 1) ** 2)
        tri = K.prism([(-0.6, 0.0), (0.6, 0.0), (0.0, -1.3)], -0.04, 0.04, name="flag")
        flags[i % 3].append(K.transform(tri, loc=(x, 0, z), rot=(math.radians(90), 0, 0)))
    a.piece("Rope", K.shade(rope, 60), "Rope", shadow=False)
    for k in range(3):
        a.piece(f"Flags{k + 1}", K.shade(K.join(flags[k], f"f{k}"), 30), f"Flag{k + 1}", shadow=False)
    a.anchor("Left", (-L / 2, 0, 0))
    a.anchor("Right", (L / 2, 0, 0))


@asset("HotAirBalloon", "Landmark", footprint=7)
def balloon(a):
    prof = [(0.0, 5.0), (1.4, 5.0), (2.4, 6.4), (5.2, 9.6), (7.0, 13.0), (7.4, 15.8), (6.6, 18.6), (4.6, 20.6), (2.0, 21.6), (0.0, 21.8)]
    env = K.lathe(prof, segments=24)
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(env.data)
    a_bm = bm.copy()
    b_bm = bm.copy()
    bm.free()

    def gore(f):
        c = f.calc_center_median()
        return int(((math.atan2(c.y, c.x) + math.pi) / (2 * math.pi)) * 12) % 2

    bmesh.ops.delete(a_bm, geom=[f for f in a_bm.faces if gore(f) != 0], context="FACES")
    bmesh.ops.delete(b_bm, geom=[f for f in b_bm.faces if gore(f) != 1], context="FACES")
    K.delete(env)
    ea = K.obj_from_bm(a_bm, "ea")
    eb = K.obj_from_bm(b_bm, "eb")
    basket = K.rbox((2.6, 2.6, 1.8), (0, 0, 0.9), r=0.3)
    rim = K.lathe([(1.9, 1.7), (2.0, 1.85), (1.9, 2.0)], segments=4, closed=True)
    ropes = [K.tube([Vector((sx * 1.1, sy * 1.1, 1.8)), Vector((sx * 1.3, sy * 1.3, 5.1))], 0.08, segments=4) for sx in (-1, 1) for sy in (-1, 1)]
    a.piece("GoreA", K.shade(ea, 50), "FairRed", shadow=False)
    a.piece("GoreB", K.shade(eb, 50), "Cream", shadow=False)
    a.piece("Basket", K.shade(K.join([basket, rim] + ropes, "basket"), 40), "Wood", shadow=False)


# ---------------------------------------------------------------------------
# Camps des équipes : portail, drapeau, et un décor par animal
# ---------------------------------------------------------------------------
@asset("CampGate", "Camp", footprint=12)
def camp_gate(a):
    posts, stones = [], []
    for sx in (-1, 1):
        p = K.rbox((1.8, 1.8, 12.0), (sx * 10.5, 0, 6.0), r=0.45)
        posts.append(K.jitter(p, 0.04, seed=sx + 5))
        stones.append(K.jitter(K.rbox((3.0, 3.0, 1.6), (sx * 10.5, 0, 0.8), r=0.5), 0.08, seed=sx + 9))
        posts.append(K.rbox((2.4, 2.4, 0.6), (sx * 10.5, 0, 12.2), r=0.2))
    beam = K.rbox((24.5, 1.4, 1.5), (0, 0, 11.4), r=0.4)
    beam2 = K.rbox((22.0, 1.0, 0.9), (0, 0, 9.6), r=0.3)
    sign = K.rbox((14.0, 0.6, 3.4), (0, 0.15, 7.4), r=0.35)
    hangers = [K.rbox((0.25, 0.25, 1.6), (sx * 5.5, 0, 9.0), r=0.08) for sx in (-1, 1)]
    pennants = []
    for i in range(9):
        x = -9.6 + i * 2.4
        tri = K.prism([(-0.75, 0.0), (0.75, 0.0), (0.0, -1.6)], -0.05, 0.05, name="pennant")
        pennants.append(K.transform(tri, loc=(x, 0.75, 10.65), rot=(math.radians(90), 0, 0)))
    lanterns = [K.ico(0.55, (sx * 10.5, 1.2, 10.0), subdiv=2) for sx in (-1, 1)]
    a.piece("Posts", K.shade(K.join(posts + [beam, beam2] + hangers, "posts"), 35), "Wood")
    a.piece("Stones", K.shade(K.join(stones, "stones"), 35), "Stone")
    a.piece("Sign", K.shade(sign, 30), "Plank")
    a.piece("Pennants", K.shade(K.join(pennants, "pennants"), 30), "Team")
    a.piece("Lanterns", K.shade(K.join(lanterns, "lanterns"), 80), "Bulb", material="Neon", shadow=False)
    for sx in (-1, 1):
        a.box((sx * 10.5, 0, 6.0), (2.4, 2.4, 12.0))
    a.anchor("Sign", (0, 0.5, 7.4))


@asset("CampFlag", "Camp", footprint=1.5)
def camp_flag(a):
    pole = K.lathe([(0.9, 0.0), (0.8, 0.6), (0.32, 1.0), (0.28, 22.0), (0.0, 22.1)], segments=10)
    ball = K.ico(0.8, (0, 0, 22.6), subdiv=2)
    import bmesh
    bm = bmesh.new()
    nx, nz = 10, 6
    W, Hh = 9.0, 5.6
    grid = []
    for j in range(nz + 1):
        row = []
        for i in range(nx + 1):
            x = 0.4 + W * i / nx
            z = 21.6 - Hh * j / nz
            y = 0.45 * math.sin(i / nx * math.pi * 1.6) * (i / nx)
            row.append(bm.verts.new((x, y, z)))
        grid.append(row)
    for j in range(nz):
        for i in range(nx):
            bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    flag = K.obj_from_bm(bm, "flag")
    flag = K.solidify(flag, 0.12)
    stripe = K.rbox((W * 0.98, 0.3, 0.7), (0.4 + W / 2, 0.2, 21.6 - Hh * 0.72), r=0.1)
    a.piece("Pole", K.shade(pole, 40), "Cream")
    a.piece("Finial", K.shade(ball, 80), "Gold")
    a.piece("Flag", K.shade(flag, 60), "Team", shadow=False)
    a.piece("Stripe", K.shade(stripe, 30), "TeamDark", shadow=False)
    a.cyl((0, 0, 0), 0.9, 22.0)


@asset("FoxDen", "Camp", footprint=7)
def fox_den(a):
    mound = K.blob([(0, 0, 1.4, 4.4, (1.35, 1.0, 0.75)), (-3.2, 0.6, 1.2, 3.0), (3.0, -0.4, 1.0, 3.1), (0.6, 1.6, 2.8, 2.8)], voxel=0.3, smooth_iter=3, noise_strength=0.9, noise_scale=1.6, seed=12)
    mound = K.bake(mound)
    K.planar(mound, 6)
    mound = K.cut_below(K.bake(mound), 0.0)
    mound = K.target_tris(mound, 700)
    K.flat(mound)
    top, side = K.split_by_normal(mound, 0.7, "moss", "rock")
    hole = K.sphere(1.0, (0, 4.2, 1.5), (1.6, 0.6, 1.4), segments=16, rings=8)
    rim = []
    for i in range(7):
        ang = math.pi * (0.1 + 0.8 * i / 6)
        rim.append(K.ico(0.6, (math.cos(ang) * 2.0, 4.4, 0.4 + math.sin(ang) * 1.9), subdiv=1))
    a.piece("Rock", side, "Rock")
    a.piece("Moss", K.flat(top), "Moss")
    a.piece("Burrow", K.shade(hole, 60), "Burrow")
    a.piece("Rim", K.flat(K.join(rim, "rim")), "RockDark")
    a.box((0, 0, 2.2), (11.0, 7.5, 4.4))


@asset("ChickenCoop", "Camp", footprint=5)
def chicken_coop(a):
    body = K.rbox((6.4, 5.0, 4.2), (0, 0, 4.3), r=0.3)
    roof = [K.transform(K.rbox((7.6, 3.4, 0.4), (0, 0, 0), r=0.15), loc=(0, sy * 1.45, 7.2), rot=(-sy * math.radians(30), 0, 0)) for sy in (-1, 1)]
    gables = [K.transform(K.prism([(-2.5, 0), (2.5, 0), (0, 1.5)], -0.2, 0.2, name="g"), loc=(sx * 3.0, 0, 6.4), rot=(math.radians(90), 0, math.radians(90))) for sx in (-1, 1)]
    stilts = [K.rbox((0.5, 0.5, 2.4), (sx * 2.8, sy * 2.1, 1.2), r=0.12) for sx in (-1, 1) for sy in (-1, 1)]
    door = K.rbox((1.8, 0.3, 2.2), (0, 2.6, 3.6), r=0.12)
    ramp = K.transform(K.rbox((1.8, 4.6, 0.3), (0, 0, 0), r=0.1), loc=(0, 4.3, 1.25), rot=(math.radians(-27), 0, 0))
    slats = [K.transform(K.rbox((1.8, 0.2, 0.18), (0, 0, 0), r=0.05), loc=(0, 3.0 + k * 0.85, 2.2 - k * 0.43 + 0.2), rot=(math.radians(-27), 0, 0)) for k in range(4)]
    window = K.rbox((1.4, 0.3, 1.2), (1.9, 2.6, 4.9), r=0.12)
    a.piece("Body", K.shade(body, 30), "WoodLight")
    a.piece("Roof", K.shade(K.join(roof + gables, "roof"), 30), "Roof")
    a.piece("Frame", K.shade(K.join(stilts + [ramp] + slats, "frame"), 30), "Wood")
    a.piece("Door", K.shade(K.join([door, window], "door"), 30), "Team")
    a.box((0, 0, 4.3), (6.6, 5.2, 4.4))
    for sx in (-1, 1):
        for sy in (-1, 1):
            a.box((sx * 2.8, sy * 2.1, 1.1), (0.6, 0.6, 2.2))


@asset("SnakeHollow", "Camp", footprint=6)
def snake_hollow(a):
    rocks = []
    rnd = random.Random(14)
    for i in range(9):
        ang = 2 * math.pi * i / 9 + rnd.uniform(-0.15, 0.15)
        r = K.ico(1.0, (0, 0, 0), (rnd.uniform(1.0, 1.5), rnd.uniform(0.9, 1.2), rnd.uniform(0.8, 1.4)), subdiv=2)
        K.displace(r, 0.3, 0.8, kind="VORONOI", seed=i)
        r = K.bake(r)
        K.planar(r, 6)
        r = K.bake(r)
        rocks.append(K.transform(r, loc=(math.cos(ang) * 4.6, math.sin(ang) * 4.6, 0.5), rot=(0, 0, ang)))
    rk = K.cut_below(K.join(rocks, "rocks"), 0.0)
    K.flat(rk)
    top, side = K.split_by_normal(rk, 0.75, "moss", "rock")
    water = K.cylinder(4.0, 4.0, 0.12, (0, 0, 0.18), segments=24)
    reeds, heads = [], []
    for i in range(12):
        ang = rnd.uniform(0, 6.28)
        d = rnd.uniform(2.6, 3.8)
        h = rnd.uniform(2.4, 3.6)
        x, y = math.cos(ang) * d, math.sin(ang) * d
        reeds.append(K.tube([Vector((x, y, 0)), Vector((x + 0.15, y, h * 0.6)), Vector((x + 0.3, y, h))], 0.08, segments=4))
        if i % 2 == 0:
            heads.append(K.cylinder(0.18, 0.16, 0.7, (x + 0.28, y, h * 0.8), segments=6))
    pads = [K.cylinder(0.7, 0.7, 0.06, (math.cos(t) * 1.8, math.sin(t) * 1.6, 0.3), segments=10) for t in (0.4, 2.2, 4.1)]
    banner_pole = post(5.0, 0.22, (0, 5.6, 0), seed=3)
    banner = K.rbox((2.4, 0.15, 3.0), (1.3, 5.6, 3.6), r=0.1)
    a.piece("Rock", side, "Rock")
    a.piece("Moss", K.flat(top), "Moss")
    a.piece("Water", K.shade(water, 10), "Water", shadow=False)
    a.piece("Reeds", K.shade(K.join(reeds, "reeds"), 60), "Reed")
    a.piece("ReedHeads", K.shade(K.join(heads, "heads"), 60), "WoodDark")
    a.piece("Lily", K.shade(K.join(pads, "lily"), 30), "Lily", shadow=False)
    a.piece("BannerPole", K.shade(banner_pole, 40), "WoodDark")
    a.piece("Banner", K.shade(banner, 30), "Team")
    a.cyl((0, 0, 0), 5.6, 0.35)
    a.cyl((0, 5.6, 0), 0.3, 5.0)


def rounded_rect(w, h, r, seg=4):
    pts = []
    for cx, cy, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


@asset("CampPad", "Camp", footprint=20)
def camp_pad(a):
    """Plateforme d'un camp (36 x 36) : dessus aux couleurs de l'équipe, biseauté,
    bordure de pierres. La collision reste la Part du camp (MapBase)."""
    top = K.prism(rounded_rect(35.4, 35.4, 3.0), 0.3, 1.0, name="top")
    m = top.modifiers.new("bevel", "BEVEL")
    m.width = 0.35
    m.segments = 2
    m.limit_method = "ANGLE"
    top = K.bake(top)
    # Bordure : anneau de pierres arrondies tout autour
    stones = []
    rnd = random.Random(21)
    outline = rounded_rect(38.4, 38.4, 4.0, seg=3)
    n = len(outline)
    for i in range(n):
        x0, y0 = outline[i]
        x1, y1 = outline[(i + 1) % n]
        length = math.hypot(x1 - x0, y1 - y0)
        count = max(1, int(length / 2.6))
        for k in range(count):
            t = (k + 0.5) / count
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            ang = math.atan2(y1 - y0, x1 - x0)
            s = K.rbox((length / count - 0.15, 1.6, 0.9 + rnd.uniform(-0.1, 0.15)), (0, 0, 0), r=0.35)
            stones.append(K.transform(s, loc=(x, y, 0.42), rot=(0, 0, ang)))
    st = K.join(stones, "stones")
    st = K.target_tris(st, 1400)
    light, dark = K.two_tone(st, -0.3)
    a.piece("Top", K.shade(top, 35), "Team")
    a.piece("Stones", K.shade(light, 35), "Stone")
    a.piece("StonesShade", K.shade(dark, 35), "RockDark")
