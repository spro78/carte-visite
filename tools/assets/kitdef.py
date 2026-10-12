"""
kitdef.py : registre des assets du kit, pièces, collisions et rôles de couleur.

Un asset est déclaré par une fonction décorée par @asset(nom, catégorie). Elle
reçoit un objet Asset et y ajoute :
  - des pièces : a.piece(nom, objet_blender, rôle, matériau="SmoothPlastic")
  - des volumes de collision (coordonnées Blender, convertis à l'export) :
      a.box(centre, taille, lacet_degrés)  a.cyl(centre_base, rayon, hauteur)
      a.ball(centre, rayon)                 a.ramp(centre, taille, montée_vers_degrés)
Les rôles de couleur sont résolus par la palette de chaque carte
(src/shared/Kit/Palettes.lua). PREVIEW_ROLES sert seulement aux rendus Blender.
"""

import math

ASSETS = {}
ORDER = []


def asset(name, category, footprint=None, notes=""):
    def register(fn):
        ASSETS[name] = {"name": name, "category": category, "build": fn, "footprint": footprint, "notes": notes}
        ORDER.append(name)
        return fn

    return register


def to_roblox(v):
    x, y, z = v
    return (x, z, -y)


class Asset:
    def __init__(self, name):
        self.name = name
        self.pieces = []  # (nom, objet, rôle, matériau, ombre)
        self.colliders = []  # dicts en coordonnées Roblox
        self.anchors = {}  # points nommés (coordonnées Roblox)

    def piece(self, name, obj, role, material="SmoothPlastic", shadow=True):
        obj.name = f"{self.name}__{name}"
        obj.data.name = obj.name
        self.pieces.append({"name": name, "obj": obj, "role": role, "material": material, "shadow": shadow})
        return obj

    def box(self, center, size, yaw=0.0):
        cx, cy, cz = to_roblox(center)
        sx, sy, sz = size
        self.colliders.append({"shape": "Block", "pos": (cx, cy, cz), "size": (sx, sz, sy), "yaw": yaw})

    def cyl(self, base, radius, height):
        x, y, z = base
        cx, cy, cz = to_roblox((x, y, z + height / 2))
        self.colliders.append({"shape": "Cylinder", "pos": (cx, cy, cz), "size": (height, radius * 2, radius * 2), "yaw": 0.0})

    def logc(self, center, radius, length, yaw=0.0):
        """Cylindre couché (axe horizontal, le long de X Blender tourné de yaw)."""
        cx, cy, cz = to_roblox(center)
        self.colliders.append({"shape": "Cylinder", "pos": (cx, cy, cz), "size": (length, radius * 2, radius * 2), "yaw": yaw, "lying": True})

    def ball(self, center, radius):
        cx, cy, cz = to_roblox(center)
        self.colliders.append({"shape": "Ball", "pos": (cx, cy, cz), "size": (radius * 2, radius * 2, radius * 2), "yaw": 0.0})

    def ramp(self, center, size, rise_towards=0.0):
        """Rampe (WedgePart) : size = (largeur, longueur, hauteur) en Blender ;
        rise_towards = direction (degrés, dans le plan Blender, 0 = +X, 90 = +Y)
        vers laquelle la rampe monte."""
        cx, cy, cz = to_roblox(center)
        w, length, h = size
        # Un WedgePart monte vers son +Z local (face verticale à l'arrière).
        # +Z Roblox = -Y Blender, soit la direction -90° : lacet pour viser rise_towards
        yaw = rise_towards + 90.0
        self.colliders.append({"shape": "Wedge", "pos": (cx, cy, cz), "size": (w, h, length), "yaw": yaw})

    def anchor(self, name, point):
        self.anchors[name] = to_roblox(point)


# Couleurs de prévisualisation (rendus Blender) : la palette « Valley »
PREVIEW_ROLES = {
    "Foliage": (108, 186, 84),
    "FoliageDark": (66, 150, 82),
    "FoliageLight": (150, 208, 96),
    "FoliageShade": (78, 150, 74),
    "FoliageDarkShade": (48, 118, 68),
    "Blossom": (244, 170, 196),
    "BlossomShade": (212, 128, 164),
    "PineShade": (36, 98, 76),
    "Pine": (52, 128, 92),
    "Trunk": (124, 86, 62),
    "Rock": (170, 176, 196),
    "RockDark": (128, 132, 156),
    "Moss": (120, 182, 86),
    "Grass": (126, 196, 92),
    "GrassDark": (100, 172, 80),
    "GrassLight": (152, 210, 110),
    "Dirt": (214, 182, 136),
    "Path": (232, 214, 172),
    "PathEdge": (196, 170, 128),
    "Cobble": (214, 210, 204),
    "CobbleDark": (180, 176, 172),
    "Wood": (156, 108, 70),
    "WoodLight": (204, 160, 110),
    "WoodDark": (104, 70, 48),
    "Plank": (186, 140, 96),
    "Roof": (204, 76, 76),
    "RoofDark": (160, 56, 62),
    "Wall": (246, 236, 214),
    "WallAccent": (222, 112, 104),
    "Stone": (200, 198, 206),
    "Hay": (214, 184, 120),
    "Water": (92, 176, 222),
    "Flower1": (248, 248, 255),
    "Flower2": (236, 128, 172),
    "Flower3": (150, 132, 236),
    "Flower4": (110, 170, 240),
    "Metal": (178, 186, 200),
    "Cream": (252, 244, 228),
    "FairRed": (232, 80, 92),
    "FairBlue": (84, 156, 232),
    "FairLilac": (168, 136, 232),
    "FairTeal": (70, 184, 190),
    "Gold": (226, 186, 96),
    "Bulb": (255, 246, 214),
    "Egg": (250, 214, 92),
    "Straw": (200, 166, 104),
    "Team": (240, 128, 40),
    "TeamDark": (150, 70, 20),
    "Cloth": (236, 228, 214),
    "Mushroom": (226, 84, 84),
    "MushroomSpot": (252, 248, 240),
    "Stem": (240, 232, 214),
    "Reed": (120, 160, 76),
    "BarnWall": (186, 74, 78),
    "BarnDoor": (160, 60, 66),
    "LampMetal": (70, 78, 104),
    "Fruit": (226, 92, 92),
    "Saddle": (84, 156, 232),
    "Zone": (252, 248, 236),
    "EggBand": (150, 120, 230),
    "Rope": (120, 96, 80),
    "Flag1": (232, 80, 92),
    "Flag2": (252, 244, 228),
    "Flag3": (84, 156, 232),
    "Burrow": (60, 40, 32),
    "HillGrass": (118, 190, 90),
    "HillSlope": (150, 160, 186),
    "Lily": (98, 170, 86),
}


def rgb01(c):
    return tuple(x / 255 for x in c)
