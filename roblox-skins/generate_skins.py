#!/usr/bin/env python3
"""Générateur de skins 2D Roblox (vêtements classiques : chemise + pantalon).

Chaque design produit deux fichiers PNG 585x559 conformes au gabarit officiel
Roblox, prêts à être téléversés dans Créer > Vêtements.

Usage :  python3 generate_skins.py [dossier_sortie]
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 585, 559          # taille du gabarit Roblox
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "output")

# ---------------------------------------------------------------------------
# Gabarit : coordonnées (x, y, largeur, hauteur) de chaque face
# ---------------------------------------------------------------------------
TORSO = {
    "up":    (231, 8, 128, 64),
    "down":  (231, 204, 128, 64),
    # bande latérale continue : droite(64) + devant(128) + gauche(64) + dos(128)
    "strip": [(165, 74, 64, 128), (231, 74, 128, 128), (361, 74, 64, 128), (427, 74, 128, 128)],
}
def limb(x0):
    return {
        "up":   (x0, 289, 64, 64),
        "down": (x0, 421, 64, 64),
        "strip": [(x0 + i * 66, 355, 64, 64) for i in range(4)],
    }
LEFT_LIMB, RIGHT_LIMB = limb(19), limb(308)
FRONT_X0 = 64            # début de la face "devant" dans la bande torse (après la face droite)

# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------
def hexc(s, a=255):
    s = s.lstrip("#")
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), a)

def vgrad(w, h, top, bottom):
    """Dégradé vertical RGBA (numpy float)."""
    t = np.linspace(0, 1, h)[:, None, None]
    a = np.array(top, dtype=float)[None, None, :]
    b = np.array(bottom, dtype=float)[None, None, :]
    return np.repeat(a + (b - a) * t, w, axis=1)

def fractal_noise(w, h, rng, octaves=4, base=8, wrap_x=True):
    """Bruit fractal [0,1] ; périodique horizontalement pour les bandes."""
    acc = np.zeros((h, w), dtype=float)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        gw, gh = base * 2 ** o, max(2, base * 2 ** o * h // w)
        g = rng.random((gh, gw)).astype(np.float32)
        if wrap_x:
            g[:, -1] = g[:, 0]
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        acc += amp * np.asarray(im, dtype=float) / 255.0
        total += amp
        amp *= 0.5
    return acc / total

def to_img(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")

def glow_layer(size, draw_fn, blur, strength=1.0):
    """Dessine draw_fn sur un calque, le floute, pour un effet néon."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer))
    g = layer.filter(ImageFilter.GaussianBlur(blur))
    if strength != 1.0:
        a = g.split()[3].point(lambda v: min(255, int(v * strength)))
        g.putalpha(a)
    return Image.alpha_composite(g, layer)

def over(img, draw_fn):
    """Dessine draw_fn sur un calque transparent puis le compose (préserve l'opacité)."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer))
    return Image.alpha_composite(img, layer)

def scanlines(img, step=3, dark=28):
    arr = np.asarray(img).astype(int)
    arr[::step, :, :3] = np.clip(arr[::step, :, :3] - dark, 0, 255)
    return to_img(arr)

def paste(canvas, img, box):
    x, y, w, h = box
    canvas.alpha_composite(img.resize((w, h)) if img.size != (w, h) else img, (x, y))

def build_garment(design, kind):
    """Assemble un PNG 585x559 à partir des fonctions de peinture d'un design.
    kind = 'shirt' ou 'pants'."""
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    # torse
    strip = design.torso(384, 128, kind)
    x = 0
    for box in TORSO["strip"]:
        paste(canvas, strip.crop((x, 0, x + box[2], 128)), box)
        x += box[2]
    paste(canvas, design.cap(128, 64, kind), TORSO["up"])
    paste(canvas, design.cap(128, 64, kind), TORSO["down"])
    # membres
    for i, lb in enumerate((LEFT_LIMB, RIGHT_LIMB)):
        strip = design.limb(256, 64, kind, i)
        x = 0
        for box in lb["strip"]:
            paste(canvas, strip.crop((x, 0, x + 64, 64)), box)
            x += 64
        paste(canvas, design.cap(64, 64, kind), lb["up"])
        paste(canvas, design.cap(64, 64, kind), lb["down"])
    return canvas

# ---------------------------------------------------------------------------
# Design 1 : CYBER NÉON — circuits lumineux sur fond nuit, cœur hexagonal
# ---------------------------------------------------------------------------
class CyberNeon:
    name = "cyber-neon"
    title = "Cyber Néon"
    CYAN, MAGENTA = "#19f0ff", "#ff2bd6"

    def __init__(self, seed=1):
        self.rng = random.Random(seed)

    def base(self, w, h, kind):
        top, bot = (hexc("#0e1538"), hexc("#060914")) if kind == "shirt" else (hexc("#090d22"), hexc("#04060f"))
        img = to_img(vgrad(w, h, top, bot))
        def grid(d):
            for x in range(0, w, 16):
                d.line([(x, 0), (x, h)], fill=(255, 255, 255, 12))
            for y in range(0, h, 16):
                d.line([(0, y), (w, y)], fill=(255, 255, 255, 12))
        return over(img, grid)

    def circuits(self, w, h, n, color, wrap=True):
        rng = self.rng
        paths = []
        for _ in range(n):
            x, y = rng.randrange(0, w, 8), rng.randrange(8, h - 8, 8)
            pts = [(x, y)]
            for _ in range(rng.randint(3, 7)):
                dx, dy = rng.choice([(8, 0), (-8, 0), (0, 8), (0, -8)])
                k = rng.randint(1, 5)
                x, y = x + dx * k, min(max(y + dy * k, 4), h - 4)
                pts.append((x, y))
            paths.append(pts)
        def draw(d):
            for pts in paths:
                for off in ((0, 0), (-w, 0), (w, 0)) if wrap else ((0, 0),):
                    p = [(px + off[0], py) for px, py in pts]
                    d.line(p, fill=hexc(color, 230), width=2)
                    for q in (p[0], p[-1]):
                        d.ellipse([q[0] - 3, q[1] - 3, q[0] + 3, q[1] + 3], fill=hexc(color))
        return glow_layer((w, h), draw, 3, 1.4)

    def torso(self, w, h, kind):
        img = self.base(w, h, kind)
        img = Image.alpha_composite(img, self.circuits(w, h, 14, self.CYAN))
        img = Image.alpha_composite(img, self.circuits(w, h, 4, self.MAGENTA))
        if kind == "shirt":
            cx, cy, r = FRONT_X0 + 64, 60, 34
            def emblem(d):
                hexa = [(cx + r * math.cos(math.radians(60 * i - 30)), cy + r * math.sin(math.radians(60 * i - 30))) for i in range(6)]
                d.polygon(hexa, outline=hexc(self.MAGENTA), width=3)
                hexa2 = [(cx + (r - 10) * math.cos(math.radians(60 * i - 30)), cy + (r - 10) * math.sin(math.radians(60 * i - 30))) for i in range(6)]
                d.polygon(hexa2, outline=hexc(self.CYAN, 200), width=2)
                d.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill=hexc("#ffffff"))
            img = Image.alpha_composite(img, glow_layer((w, h), emblem, 5, 1.6))
            # fond sombre derrière l'emblème pour la lisibilité
        else:
            def belt(d):
                d.rectangle([0, 2, w, 7], fill=hexc(self.MAGENTA, 220))
            img = Image.alpha_composite(img, glow_layer((w, h), belt, 3))
        return scanlines(img, 4, 14)

    def limb(self, w, h, kind, idx):
        img = self.base(w, h, kind)
        img = Image.alpha_composite(img, self.circuits(w, h, 5, self.CYAN))
        y = 44 if kind == "shirt" else 18
        def band(d):
            d.rectangle([0, y, w, y + 3], fill=hexc(self.MAGENTA, 230))
            d.rectangle([0, y + 8, w, y + 9], fill=hexc(self.CYAN, 200))
        img = Image.alpha_composite(img, glow_layer((w, h), band, 3))
        return scanlines(img, 4, 14)

    def cap(self, w, h, kind):
        return to_img(vgrad(w, h, hexc("#0a1030"), hexc("#060914")))

# ---------------------------------------------------------------------------
# Design 2 : NÉBULEUSE — nuage cosmique, étoiles et planète annelée
# ---------------------------------------------------------------------------
class Nebula:
    name = "nebuleuse"
    title = "Nébuleuse"

    def __init__(self, seed=7):
        self.rng = np.random.default_rng(seed)

    def sky(self, w, h, kind):
        n = fractal_noise(w, h, self.rng, octaves=5, base=6)
        n2 = fractal_noise(w, h, self.rng, octaves=3, base=4)
        deep = np.array(hexc("#0b0620"), float)
        purple = np.array(hexc("#5b1f8f"), float)
        pink = np.array(hexc("#ff5fa8"), float)
        teal = np.array(hexc("#19c8d8"), float)
        t = np.clip((n - 0.35) * 2.2, 0, 1)[..., None]
        col = deep + (purple - deep) * t
        t2 = np.clip((n2 - 0.5) * 3, 0, 1)[..., None] * t
        col = col + (pink - col) * t2 * 0.8
        t3 = np.clip((n - 0.62) * 5, 0, 1)[..., None]
        col = col + (teal - col) * t3 * 0.6
        if kind == "pants":
            col[..., :3] *= 0.7
        img = to_img(col)
        def dust(d):
            for _ in range(int(w * h / 180)):
                x, y = self.rng.integers(0, w), self.rng.integers(0, h)
                b = int(self.rng.integers(120, 256))
                d.point((x, y), fill=(255, 255, 255, b))
        img = over(img, dust)
        def stars(d):
            for _ in range(int(w * h / 2500)):
                x, y = self.rng.integers(0, w), self.rng.integers(0, h)
                r = int(self.rng.integers(1, 3))
                d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, 255))
                d.line([(x - 4, y), (x + 4, y)], fill=(255, 255, 255, 140))
                d.line([(x, y - 4), (x, y + 4)], fill=(255, 255, 255, 140))
        return Image.alpha_composite(img, glow_layer((w, h), stars, 2, 1.2))

    def torso(self, w, h, kind):
        img = self.sky(w, h, kind)
        if kind == "shirt":
            cx, cy, r = FRONT_X0 + 64, 66, 30
            pl = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            d = ImageDraw.Draw(pl)
            for i in range(r, 0, -1):
                t = i / r
                c = (int(255 - 150 * t), int(170 - 100 * t), int(90 + 120 * t), 255)
                d.ellipse([cx - i, cy - i, cx + i, cy + i], fill=c)
            shade = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            ds = ImageDraw.Draw(shade)
            ds.ellipse([cx - r + 10, cy - r + 10, cx + r + 10, cy + r + 10], fill=(0, 0, 0, 120))
            mask = Image.new("L", (w, h), 0)
            ImageDraw.Draw(mask).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
            pl.paste(Image.alpha_composite(pl, shade), (0, 0), mask)
            def rings(d):
                d.ellipse([cx - 52, cy - 14, cx + 52, cy + 14], outline=(255, 230, 200, 230), width=4)
                d.ellipse([cx - 44, cy - 11, cx + 44, cy + 11], outline=(255, 180, 220, 160), width=2)
            ring = glow_layer((w, h), rings, 2)
            # moitié arrière de l'anneau derrière la planète
            back = ring.crop((0, 0, w, cy)); front = ring.crop((0, cy, w, h))
            img.alpha_composite(back, (0, 0))
            img = Image.alpha_composite(img, pl)
            img.alpha_composite(front, (0, cy))
        else:
            img = over(img, lambda d: d.rectangle([0, 0, w, 6], fill=(255, 255, 255, 200)))
        return img

    def limb(self, w, h, kind, idx):
        return self.sky(w, h, kind)

    def cap(self, w, h, kind):
        return to_img(vgrad(w, h, hexc("#2a1255"), hexc("#0b0620")))

# ---------------------------------------------------------------------------
# Design 3 : GLITCH PIXEL — blocs rétro, bandes décalées, cœur pixel
# ---------------------------------------------------------------------------
class GlitchPixel:
    name = "glitch-pixel"
    title = "Glitch Pixel"
    PAL = ["#ff2a6d", "#05d9e8", "#d1f7ff", "#7a04eb", "#f9f871"]
    HEART = ["0110110", "1111111", "1111111", "0111110", "0011100", "0001000"]

    def __init__(self, seed=3):
        self.rng = random.Random(seed)

    def blocks(self, w, h, kind, density):
        base = hexc("#17171f") if kind == "shirt" else hexc("#101016")
        img = Image.new("RGBA", (w, h), base)
        s = 8
        def cells(d):
            for y in range(0, h, s):
                for x in range(0, w, s):
                    r = self.rng.random()
                    if r < density:
                        c = hexc(self.rng.choice(self.PAL), self.rng.randint(120, 255))
                        d.rectangle([x, y, x + s - 1, y + s - 1], fill=c)
                    elif r < density + 0.12:
                        d.rectangle([x, y, x + s - 1, y + s - 1], fill=(255, 255, 255, 14))
        return over(img, cells)

    def glitch(self, img):
        arr = np.asarray(img).copy()
        h, w = arr.shape[:2]
        for _ in range(max(2, h // 26)):
            y = self.rng.randrange(0, h - 4)
            hh = self.rng.randint(2, 6)
            shift = self.rng.randint(-24, 24)
            band = np.roll(arr[y:y + hh], shift, axis=1)
            ch = self.rng.randrange(3)
            band[..., ch] = np.clip(band[..., ch].astype(int) + 90, 0, 255)
            arr[y:y + hh] = band
        return Image.fromarray(arr, "RGBA")

    def torso(self, w, h, kind):
        img = self.blocks(w, h, kind, 0.10)
        if kind == "pants":
            d = ImageDraw.Draw(img)
            for x in range(0, w, 16):
                d.rectangle([x, 0, x + 7, 5], fill=hexc("#f9f871"))
        img = scanlines(self.glitch(img), 3, 22)
        if kind == "shirt":
            s = 10
            ox, oy = FRONT_X0 + 64 - len(self.HEART[0]) * s // 2, 36
            layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
            dl = ImageDraw.Draw(layer)
            dl.rectangle([ox - 8, oy - 8, ox + len(self.HEART[0]) * s + 7, oy + len(self.HEART) * s + 7], fill=(10, 10, 14, 200))
            for j, row in enumerate(self.HEART):
                for i, c in enumerate(row):
                    if c == "1":
                        dl.rectangle([ox + i * s - 4, oy + j * s + 3, ox + i * s + s - 5, oy + j * s + s + 2], fill=hexc("#05d9e8", 160))
            for j, row in enumerate(self.HEART):
                for i, c in enumerate(row):
                    if c == "1":
                        dl.rectangle([ox + i * s, oy + j * s, ox + i * s + s - 1, oy + j * s + s - 1], fill=hexc("#ff2a6d"))
            img = Image.alpha_composite(img, layer)
        return img

    def limb(self, w, h, kind, idx):
        img = self.blocks(w, h, kind, 0.14)
        d = ImageDraw.Draw(img)
        y = 40 if kind == "shirt" else 24
        d.rectangle([0, y, w, y + 5], fill=hexc("#05d9e8"))
        d.rectangle([0, y + 9, w, y + 11], fill=hexc("#ff2a6d"))
        return scanlines(self.glitch(img), 3, 22)

    def cap(self, w, h, kind):
        return Image.new("RGBA", (w, h), hexc("#17171f"))

# ---------------------------------------------------------------------------
# Design 4 : MAGMA — obsidienne fissurée, lave incandescente dans les fentes
# ---------------------------------------------------------------------------
class Magma:
    name = "magma"
    title = "Magma"

    def __init__(self, seed=11):
        self.rng = np.random.default_rng(seed)

    def rock(self, w, h, kind, n_cells, heat):
        pts = np.column_stack([self.rng.random(n_cells) * w, self.rng.random(n_cells) * h])
        pts = np.concatenate([pts, pts + [w, 0], pts - [w, 0]])          # périodique en x
        ys, xs = np.mgrid[0:h, 0:w]
        d = np.sqrt((xs[..., None] - pts[:, 0]) ** 2 + (ys[..., None] - pts[:, 1]) ** 2)
        d.sort(axis=2)
        crack = np.clip(1 - (d[..., 1] - d[..., 0]) / 3.0, 0, 1)         # 1 sur les frontières
        grain = fractal_noise(w, h, self.rng, octaves=4, base=10)
        hot = fractal_noise(w, h, self.rng, octaves=3, base=3)
        hot = np.clip((hot - 0.45) * heat, 0, 1)
        rockc = (np.array([34, 30, 36], float) + grain[..., None] * 28) * (0.8 if kind == "pants" else 1)
        lava_t = crack * (0.35 + 0.65 * hot)
        yellow = np.array([255, 230, 90], float); orange = np.array([255, 90, 20], float); red = np.array([120, 10, 0], float)
        lava = red + (orange - red) * np.clip(lava_t * 1.6, 0, 1)[..., None]
        lava = lava + (yellow - lava) * np.clip((lava_t - 0.6) * 2.5, 0, 1)[..., None]
        col = rockc + (lava - rockc) * np.clip(lava_t * 1.5, 0, 1)[..., None]
        img = to_img(np.concatenate([col, np.full((h, w, 1), 255.0)], axis=2))
        glow = to_img(np.concatenate([lava, (np.clip(lava_t, 0, 1) * 150)[..., None]], axis=2)).filter(ImageFilter.GaussianBlur(4))
        return Image.alpha_composite(img, glow)

    def torso(self, w, h, kind):
        img = self.rock(w, h, kind, 42, 3.0)
        if kind == "shirt":
            cx, cy = FRONT_X0 + 64, 62
            def core(d):
                for r, c in ((30, (255, 60, 10, 90)), (20, (255, 140, 30, 180)), (10, (255, 240, 160, 255))):
                    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=c)
            img = Image.alpha_composite(img, glow_layer((w, h), core, 8, 1.2))
        return img

    def limb(self, w, h, kind, idx):
        return self.rock(w, h, kind, 16, 2.6)

    def cap(self, w, h, kind):
        return Image.new("RGBA", (w, h), (30, 26, 32, 255))

# ---------------------------------------------------------------------------
# Design 5 : HOLO — iridescence chromée, lignes de balayage, losange emblème
# ---------------------------------------------------------------------------
class Holo:
    name = "holo"
    title = "Holo Iridescent"

    def __init__(self, seed=5):
        self.rng = np.random.default_rng(seed)

    def sheet(self, w, h, kind, period):
        ys, xs = np.mgrid[0:h, 0:w]
        n = fractal_noise(w, h, self.rng, octaves=3, base=3)
        hue = ((xs * 2.0 / w) + (ys / period) + n * 0.6) % 1.0            # 2 tours en x => périodique
        sat = 0.55 if kind == "shirt" else 0.45
        val = 0.95 - 0.35 * (ys / h) if kind == "shirt" else 0.75 - 0.3 * (ys / h)
        # HSV -> RGB vectorisé
        i = np.floor(hue * 6).astype(int) % 6
        f = hue * 6 - np.floor(hue * 6)
        p, q, t = val * (1 - sat), val * (1 - sat * f), val * (1 - sat * (1 - f))
        r = np.choose(i, [val, q, p, p, t, val]); g = np.choose(i, [t, val, val, q, p, p]); b = np.choose(i, [p, p, t, val, val, q])
        rgb = np.stack([r, g, b], axis=2) * 255
        # reflets chromés diagonaux
        band = (np.sin((xs + ys) / 9.0) * 0.5 + 0.5) ** 6
        rgb = rgb + (255 - rgb) * band[..., None] * 0.5
        img = to_img(np.concatenate([rgb, np.full((h, w, 1), 255.0)], axis=2))
        return scanlines(img, 2, 18)

    def torso(self, w, h, kind):
        img = self.sheet(w, h, kind, 110)
        if kind == "shirt":
            cx, cy, r = FRONT_X0 + 64, 62, 34
            def diamond(d):
                pts = [(cx, cy - r), (cx + r * 0.7, cy), (cx, cy + r), (cx - r * 0.7, cy)]
                d.polygon(pts, fill=(255, 255, 255, 60), outline=(255, 255, 255, 240), width=3)
                d.line([(cx - r * 0.7, cy), (cx + r * 0.7, cy)], fill=(255, 255, 255, 200), width=2)
                d.line([(cx, cy - r), (cx, cy + r)], fill=(255, 255, 255, 200), width=2)
                d.line([(cx - r * 0.35, cy - r * 0.5), (cx + r * 0.35, cy + r * 0.5)], fill=(255, 255, 255, 120))
            img = Image.alpha_composite(img, glow_layer((w, h), diamond, 4, 1.3))
            img = over(img, lambda d: d.rectangle([0, 0, w, 3], fill=(255, 255, 255, 230)))   # col
        else:
            def belt(d):
                d.rectangle([0, 0, w, 7], fill=(20, 20, 30, 255))                              # ceinture sombre
                d.rectangle([0, 8, w, 9], fill=(255, 255, 255, 200))
            img = over(img, belt)
        return img

    def limb(self, w, h, kind, idx):
        img = self.sheet(w, h, kind, 70)
        if kind == "shirt":
            return over(img, lambda d: d.rectangle([0, h - 6, w, h - 1], fill=(255, 255, 255, 230)))  # poignet
        return over(img, lambda d: d.rectangle([0, h - 8, w, h - 1], fill=(20, 20, 30, 255)))         # ourlet

    def cap(self, w, h, kind):
        return Image.new("RGBA", (w, h), (235, 225, 255, 255))

# ---------------------------------------------------------------------------
# Aperçus
# ---------------------------------------------------------------------------
def font(size):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()

def crop(img, box):
    x, y, w, h = box
    return img.crop((x, y, x + w, y + h))

def mannequin(shirt, pants):
    """Vue de face approximative d'un avatar R6 habillé (tête neutre)."""
    S = 64
    out = Image.new("RGBA", (4 * S, 5 * S + 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle([1.5 * S + 6, 2, 2.5 * S - 6, S - 2], 10, fill=(230, 190, 150, 255))   # tête
    out.alpha_composite(crop(shirt, TORSO["strip"][1]), (S, S))                                  # torse devant
    out.alpha_composite(crop(shirt, LEFT_LIMB["strip"][1]).resize((S, 2 * S)), (0, S))         # bras
    out.alpha_composite(crop(shirt, RIGHT_LIMB["strip"][1]).resize((S, 2 * S)), (3 * S, S))
    out.alpha_composite(crop(pants, LEFT_LIMB["strip"][1]).resize((S, 2 * S)), (S, 3 * S))     # jambes
    out.alpha_composite(crop(pants, RIGHT_LIMB["strip"][1]).resize((S, 2 * S)), (2 * S, 3 * S))
    return out

def checker(w, h):
    img = Image.new("RGBA", (w, h), (235, 235, 240, 255))
    d = ImageDraw.Draw(img)
    for y in range(0, h, 16):
        for x in range(0, w, 16):
            if (x // 16 + y // 16) % 2:
                d.rectangle([x, y, x + 15, y + 15], fill=(215, 215, 222, 255))
    return img

def preview(design, shirt, pants):
    pad = 20
    man = mannequin(shirt, pants).resize((256, 328), Image.NEAREST)
    w = pad * 4 + W * 2 + 256
    h = pad * 2 + H + 50
    img = checker(w, h)
    d = ImageDraw.Draw(img)
    d.text((pad, 14), f"{design.title}  —  chemise / pantalon / aperçu avatar", font=font(24), fill=(30, 30, 40, 255))
    img.alpha_composite(shirt, (pad, 50 + pad))
    img.alpha_composite(pants, (pad * 2 + W, 50 + pad))
    img.alpha_composite(man, (pad * 3 + W * 2, 50 + pad + (H - 328) // 2))
    return img

def main():
    designs = [CyberNeon(), Nebula(), GlitchPixel(), Magma(), Holo()]
    thumbs = []
    for dz in designs:
        folder = os.path.join(OUT, dz.name)
        os.makedirs(folder, exist_ok=True)
        shirt = build_garment(dz, "shirt")
        pants = build_garment(dz, "pants")
        shirt.save(os.path.join(folder, "chemise.png"))
        pants.save(os.path.join(folder, "pantalon.png"))
        preview(dz, shirt, pants).save(os.path.join(folder, "apercu.png"))
        thumbs.append((dz.title, mannequin(shirt, pants)))
        print(f"✔ {dz.title:16s} -> {folder}")
    # planche contact
    cw, ch = 256 + 40, 328 + 70
    sheet = checker(cw * len(thumbs), ch)
    d = ImageDraw.Draw(sheet)
    for i, (title, man) in enumerate(thumbs):
        sheet.alpha_composite(man.resize((256, 328), Image.NEAREST), (i * cw + 20, 50))
        d.text((i * cw + 20, 14), title, font=font(22), fill=(30, 30, 40, 255))
    sheet.save(os.path.join(OUT, "planche-contact.png"))
    print("✔ planche-contact.png")

if __name__ == "__main__":
    main()
