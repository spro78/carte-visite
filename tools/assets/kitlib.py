"""
kitlib.py : outils de modélisation pour le kit d'assets (Blender en module Python, bpy).

Conventions (identiques pour tout le kit) :
  - 1 unité Blender = 1 stud Roblox ; Z vers le haut dans Blender.
  - Passage aux coordonnées Roblox : (x, y, z) Blender -> (x, z, -y) Roblox,
    comme l'export FBX (axe avant -Z, axe haut Y). L'avant d'un asset
    (LookVector Roblox, -Z) est donc +Y dans Blender.
  - L'origine d'un asset est au sol, au centre de son emprise.
  - Chaque asset est une liste de pièces ; une pièce = un mesh + un « rôle » de
    couleur (Foliage, Trunk, Rock...). La couleur réelle vient de la palette de
    la carte (src/shared/Kit/Palettes.lua), le matériau est SmoothPlastic
    (aucune texture : pas d'UV à gérer, rendu net sur téléphone).
  - Collisions : quelques volumes simples (Block, Cylinder, Ball, Wedge) par
    asset, invisibles côté jeu ; le mesh lui-même ne collisionne pas.
"""

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

# ---------------------------------------------------------------------------
# Scène
# ---------------------------------------------------------------------------


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for tex in list(bpy.data.textures):
        bpy.data.textures.remove(tex)


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def obj_from_bm(bm, name):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    return link(bpy.data.objects.new(name, mesh))


def delete(obj):
    mesh = obj.data if obj.type == "MESH" else None
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh and mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def bake(obj):
    """Applique les modificateurs et la transformation : retourne un objet neuf."""
    dg = bpy.context.evaluated_depsgraph_get()
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(dg))
    mesh.transform(obj.matrix_world)
    out = link(bpy.data.objects.new(obj.name, mesh))
    delete(obj)
    return out


def join(objs, name=None):
    """Réunit plusieurs objets en un seul mesh (sans fusion des volumes)."""
    objs = [bake(o) for o in objs]
    bm = bmesh.new()
    for o in objs:
        bm.from_mesh(o.data)
    for o in objs:
        delete(o)
    return obj_from_bm(bm, name or "joined")


def mod(obj, kind, **settings):
    m = obj.modifiers.new(kind.lower(), kind)
    for key, value in settings.items():
        setattr(m, key, value)
    return m


_tex_count = 0


def noise_tex(kind="CLOUDS", scale=1.0, depth=2, basis="BLENDER_ORIGINAL"):
    global _tex_count
    _tex_count += 1
    tex = bpy.data.textures.new(f"tex{_tex_count}", kind)
    if hasattr(tex, "noise_scale"):
        tex.noise_scale = scale
    if hasattr(tex, "noise_depth"):
        tex.noise_depth = depth
    if hasattr(tex, "noise_basis"):
        tex.noise_basis = basis
    return tex


def displace(obj, strength, scale, kind="CLOUDS", seed=0, direction="NORMAL", depth=2):
    tex = noise_tex(kind, scale, depth)
    m = mod(obj, "DISPLACE", texture=tex, strength=strength, direction=direction, mid_level=0.5)
    # Décalage de la texture = variation déterministe d'une graine à l'autre
    empty = bpy.data.objects.new(f"noiseoffset{_tex_count}", None)
    link(empty)
    rnd = random.Random(seed)
    empty.location = (rnd.uniform(-50, 50), rnd.uniform(-50, 50), rnd.uniform(-50, 50))
    m.texture_coords = "OBJECT"
    m.texture_coords_object = empty
    return m


def remesh(obj, voxel):
    mod(obj, "REMESH", mode="VOXEL", voxel_size=voxel, adaptivity=0.0)


def smooth(obj, iterations=4, factor=0.8):
    mod(obj, "SMOOTH", iterations=iterations, factor=factor)


def laplacian(obj, iterations=3, lam=0.5):
    mod(obj, "LAPLACIANSMOOTH", iterations=iterations, lambda_factor=lam, use_volume_preserve=True)


def decimate(obj, ratio):
    mod(obj, "DECIMATE", ratio=ratio, use_collapse_triangulate=True)


def planar(obj, angle_deg=6):
    m = obj.modifiers.new("planar", "DECIMATE")
    m.decimate_type = "DISSOLVE"
    m.angle_limit = math.radians(angle_deg)


def bevel(obj, width, segments=2, angle=35, profile=0.5):
    m = mod(obj, "BEVEL", width=width, segments=segments, limit_method="ANGLE", profile=profile)
    m.angle_limit = math.radians(angle)
    m.harden_normals = False
    return m


def triangulate(obj):
    mod(obj, "TRIANGULATE")


def target_tris(obj, tris):
    """Décime jusqu'à environ `tris` triangles (après les autres modificateurs)."""
    o = bake(obj)
    current = count_tris(o)
    if current > tris:
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = max(0.01, tris / current)
        m.use_collapse_triangulate = True
        o = bake(o)
    return o


def count_tris(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def cut_below(obj, z=0.0):
    """Coupe tout ce qui est sous z et bouche le trou (dessous plat)."""
    o = bake(obj)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z), plane_no=(0, 0, 1), clear_inner=True)
    cut_edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if cut_edges:
        bmesh.ops.holes_fill(bm, edges=cut_edges, sides=0)
    bm.to_mesh(o.data)
    bm.free()
    return o


def shade(obj, angle_deg=40):
    """Lissé, avec arêtes vives au-delà de l'angle donné."""
    mesh = obj.data
    for p in mesh.polygons:
        p.use_smooth = True
    if hasattr(mesh, "set_sharp_from_angle"):
        mesh.set_sharp_from_angle(angle=math.radians(angle_deg))
    return obj


def flat(obj):
    for p in obj.data.polygons:
        p.use_smooth = False
    return obj


# ---------------------------------------------------------------------------
# Primitives (toutes en coordonnées du monde, Z vers le haut)
# ---------------------------------------------------------------------------


def sphere(r, loc=(0, 0, 0), scale=(1, 1, 1), segments=24, rings=12, name="sphere"):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=r)
    o = obj_from_bm(bm, name)
    o.location = loc
    o.scale = scale
    return bake(o)


def ico(r, loc=(0, 0, 0), scale=(1, 1, 1), subdiv=2, name="ico"):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
    o = obj_from_bm(bm, name)
    o.location = loc
    o.scale = scale
    return bake(o)


def box(size, loc=(0, 0, 0), rot=(0, 0, 0), name="box"):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    o = obj_from_bm(bm, name)
    o.scale = size
    o.location = loc
    o.rotation_euler = rot
    return bake(o)


def rbox(size, loc=(0, 0, 0), rot=(0, 0, 0), r=0.15, segments=2, name="rbox"):
    """Boîte aux arêtes arrondies (biseau appliqué)."""
    o = box(size, (0, 0, 0), name=name)
    m = o.modifiers.new("bevel", "BEVEL")
    m.width = min(r, min(size) * 0.45)
    m.segments = segments
    m.limit_method = "NONE"
    o = bake(o)
    o.location = loc
    o.rotation_euler = rot
    return bake(o)


def cylinder(r1, r2, h, loc=(0, 0, 0), rot=(0, 0, 0), segments=12, name="cyl", caps=True):
    """Cylindre/cône vertical : base à loc (pas centré), hauteur h."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segments, radius1=r1, radius2=r2, depth=h)
    bmesh.ops.translate(bm, vec=(0, 0, h / 2), verts=bm.verts)
    o = obj_from_bm(bm, name)
    o.location = loc
    o.rotation_euler = rot
    return bake(o)


def lathe(profile, segments=16, name="lathe", loc=(0, 0, 0), closed=False):
    """Révolution d'un profil [(rayon, z), ...] autour de Z (du bas vers le haut).
    closed=True : le profil est une boucle (anneau, tore), sans couvercles."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = []
        for i in range(segments):
            a = 2 * math.pi * i / segments
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        rings.append(ring)
    pairs = list(range(len(rings) - 1))
    if closed:
        pairs.append(len(rings) - 1)
    for k in pairs:
        a, b = rings[k], rings[(k + 1) % len(rings)]
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if not closed and profile[0][0] > 1e-4:
        bm.faces.new(list(reversed(rings[0])))
    if not closed and profile[-1][0] > 1e-4:
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(bm, name)
    o.location = loc
    return bake(o)


def tube(points, radius, segments=8, name="tube", radii=None, caps=True):
    """Tube le long d'une polyligne (liste de Vector), rayon constant ou par point."""
    bm = bmesh.new()
    rings = []
    n = len(points)
    prev_side = None
    for i, p in enumerate(points):
        p = Vector(p)
        if i == 0:
            d = Vector(points[1]) - p
        elif i == n - 1:
            d = p - Vector(points[i - 1])
        else:
            d = Vector(points[i + 1]) - Vector(points[i - 1])
        d.normalize()
        up = Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((1, 0, 0))
        side = d.cross(up).normalized()
        if prev_side is not None and side.dot(prev_side) < 0:
            side = -side
        prev_side = side
        up2 = side.cross(d).normalized()
        r = radii[i] if radii else radius
        ring = []
        for k in range(segments):
            a = 2 * math.pi * k / segments
            ring.append(bm.verts.new(p + (side * math.cos(a) + up2 * math.sin(a)) * r))
        rings.append(ring)
    for k in range(n - 1):
        a, b = rings[k], rings[k + 1]
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if caps:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(bm, name)


def prism(outline, z0, z1, name="prism"):
    """Extrusion verticale d'un contour [(x, y), ...] entre z0 et z1."""
    bm = bmesh.new()
    bottom = [bm.verts.new((x, y, z0)) for x, y in outline]
    top = [bm.verts.new((x, y, z1)) for x, y in outline]
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bm.faces.new(list(reversed(bottom)))
    bm.faces.new(top)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from_bm(bm, name)


def blob_outline(radius, count=24, wobble=0.15, seed=0, sx=1.0, sy=1.0):
    """Contour organique fermé (pour plateaux, taches d'herbe, mares)."""
    rnd = random.Random(seed)
    phase = [rnd.uniform(0, 6.28) for _ in range(4)]
    pts = []
    for i in range(count):
        a = 2 * math.pi * i / count
        k = 1 + wobble * (0.6 * math.sin(2 * a + phase[0]) + 0.3 * math.sin(3 * a + phase[1]) + 0.2 * math.sin(5 * a + phase[2]))
        pts.append((math.cos(a) * radius * k * sx, math.sin(a) * radius * k * sy))
    return pts


def blob(spheres, voxel=0.3, smooth_iter=6, noise_strength=0.0, noise_scale=1.0, seed=0, name="blob"):
    """Union organique de sphères [(x, y, z, r, (sx, sy, sz)?), ...]."""
    parts = []
    for s in spheres:
        x, y, z, r = s[:4]
        sc = s[4] if len(s) > 4 else (1, 1, 1)
        parts.append(sphere(r, (x, y, z), sc, segments=20, rings=10))
    o = join(parts, name)
    remesh(o, voxel)
    if noise_strength > 0:
        displace(o, noise_strength, noise_scale, seed=seed)
    smooth(o, smooth_iter, 0.7)
    return bake(o)


def jitter(obj, amount, seed=0, scale=1.0):
    """Petites irrégularités (bruit 3D cohérent) sur chaque sommet."""
    o = bake(obj)
    off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    for v in o.data.vertices:
        p = v.co * (1.0 / scale) + off
        v.co += Vector(noise.noise_vector(p)) * amount
    return o


def bend_down(obj, amount, radius):
    """Affaisse les sommets en fonction de la distance horizontale au centre."""
    o = bake(obj)
    for v in o.data.vertices:
        d = math.hypot(v.co.x, v.co.y) / radius
        v.co.z -= amount * d * d
    return o


def transform(obj, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    obj.location = loc
    obj.rotation_euler = rot
    obj.scale = scale
    return bake(obj)


def mirror_x(obj):
    o = bake(obj)
    m = o.modifiers.new("mirror", "MIRROR")
    m.use_axis[0] = True
    m.use_bisect_axis[0] = False
    return bake(o)


def bounds(obj):
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def ground(obj):
    """Pose l'objet au sol (z min = 0)."""
    (_, _, z0), _ = bounds(obj)
    obj.location.z -= z0
    return bake(obj)


def split_by_normal(obj, min_up=0.55, name_top="top", name_side="side"):
    """Sépare les faces tournées vers le haut (herbe, mousse) du reste (roche)."""
    o = bake(obj)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    top = bm.copy()
    side = bm.copy()
    bm.free()
    up = Vector((0, 0, 1))
    bmesh.ops.delete(top, geom=[f for f in top.faces if f.normal.dot(up) < min_up], context="FACES")
    bmesh.ops.delete(side, geom=[f for f in side.faces if f.normal.dot(up) >= min_up], context="FACES")
    delete(o)
    a = obj_from_bm(top, name_top) if True else None
    b = obj_from_bm(side, name_side)
    return a, b


def two_tone(obj, threshold=-0.05, name_light="light", name_dark="dark"):
    """Ombre peinte : les faces tournées vers le bas forment une pièce plus
    sombre (fausse occlusion, lisible même sans ombres portées)."""
    o = bake(obj)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    light = bm.copy()
    dark = bm.copy()
    bm.free()
    up = Vector((0, 0, 1))
    bmesh.ops.delete(light, geom=[f for f in light.faces if f.normal.dot(up) < threshold], context="FACES")
    bmesh.ops.delete(dark, geom=[f for f in dark.faces if f.normal.dot(up) >= threshold], context="FACES")
    delete(o)
    return obj_from_bm(light, name_light), obj_from_bm(dark, name_dark)


def solidify(obj, thickness):
    mod(obj, "SOLIDIFY", thickness=thickness, offset=-1)
    return bake(obj)
