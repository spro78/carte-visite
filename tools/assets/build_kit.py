"""
build_kit.py : construit le kit d'assets dans Blender (module bpy), puis
  - exporte assets/kit/HoH_Kit.fbx (import dans Studio, 1 unité = 1 stud) ;
  - écrit les données des meshes pour le jeu (src/shared/Kit/Meshes/*.lua) et
    le manifeste (src/shared/Kit/Manifest.lua) ;
  - rend des planches de contrôle dans Blender (reference/preuves/kit/).

Usage (depuis la racine du dépôt) : tools/assets/build.sh [options]
  --only A,B     ne construit que ces assets
  --sheet        rend les planches (Cycles, CPU)
  --no-export    pas d'export (essais de modélisation)
"""

import argparse
import base64
import json
import math
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import kitlib as K  # noqa: E402
from kitdef import ASSETS, ORDER, PREVIEW_ROLES, Asset, rgb01  # noqa: E402
import assets_nature  # noqa: E402,F401

for optional in ("assets_built", "assets_fair", "terrain_valley"):
    try:
        __import__(optional)
    except ModuleNotFoundError as err:
        if err.name != optional:
            raise

KIT_DIR = os.path.join(ROOT, "assets", "kit")


def sync_preview_palette():
    """Les rendus Blender prennent les couleurs de la palette du jeu
    (src/shared/Kit/Palettes.lua, palette Valley) : une seule source."""
    import re
    path = os.path.join(ROOT, "src", "shared", "Kit", "Palettes.lua")
    if not os.path.exists(path):
        return
    src = open(path).read()
    block = src.split("Palettes.Valley = {", 1)[-1].split("\n}", 1)[0]
    for name, r, g, b in re.findall(r"\t(\w+) = rgb\((\d+), (\d+), (\d+)\)", block):
        PREVIEW_ROLES[name] = (int(r), int(g), int(b))


sync_preview_palette()
LUA_DIR = os.path.join(ROOT, "src", "shared", "Kit")
SHEET_DIR = os.path.join(ROOT, "reference", "preuves", "kit")


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------
def build(names):
    built = []
    for name in names:
        t0 = time.time()
        a = Asset(name)
        ASSETS[name]["build"](a)
        for p in a.pieces:
            K.bake(p["obj"]) if p["obj"].modifiers else None
        tris = 0
        kept = []
        for p in a.pieces:
            o = bpy.data.objects[p["obj"].name]
            p["obj"] = o
            n = K.count_tris(o)
            if n == 0:
                # Pièce vide (ex. aucune pente raide dans un morceau de colline)
                K.delete(o)
                continue
            kept.append(p)
            tris += n
        a.pieces = kept
        a.tris = tris
        built.append(a)
        print(f"  {name:<22} {len(a.pieces)} pièces {tris:>6} triangles  {time.time() - t0:5.1f} s")
    return built


# ---------------------------------------------------------------------------
# Données des meshes (coordonnées Roblox, centrées sur la boîte englobante)
# ---------------------------------------------------------------------------
def piece_data(obj):
    """Sommets (dupliqués le long des arêtes vives) et triangles, en Roblox."""
    mesh = obj.data
    mesh.calc_loop_triangles()
    normals = mesh.corner_normals if hasattr(mesh, "corner_normals") else None
    index = {}
    verts = []
    tris = []
    for lt in mesh.loop_triangles:
        tri = []
        for loop_index in lt.loops:
            vi = mesh.loops[loop_index].vertex_index
            if normals is not None:
                n = normals[loop_index].vector
            else:
                n = mesh.loops[loop_index].normal
            key = (vi, round(n.x, 2), round(n.y, 2), round(n.z, 2))
            k = index.get(key)
            if k is None:
                co = mesh.vertices[vi].co
                k = len(verts)
                index[key] = k
                verts.append((co.x, co.z, -co.y))  # Blender -> Roblox
            tri.append(k)
        # (x, y, z) -> (x, z, -y) conserve l'orientation : l'ordre reste valable
        tris.append(tri)
    lo = [min(v[i] for v in verts) for i in range(3)]
    hi = [max(v[i] for v in verts) for i in range(3)]
    center = [(lo[i] + hi[i]) / 2 for i in range(3)]
    size = [max(hi[i] - lo[i], 0.05) for i in range(3)]
    q = bytearray()
    for v in verts:
        for i in range(3):
            n = (v[i] - center[i]) / (size[i] / 2)
            q += struct.pack("<h", max(-32767, min(32767, round(n * 32767))))
    t = bytearray()
    for tri in tris:
        for k in tri:
            t += struct.pack("<H", k)
    return {
        "center": center,
        "size": size,
        "verts": len(verts),
        "tris": len(tris),
        "V": base64.b64encode(bytes(q)).decode("ascii"),
        "T": base64.b64encode(bytes(t)).decode("ascii"),
    }


def lua_vec(v):
    return "Vector3.new(%s, %s, %s)" % tuple(fmt(x) for x in v)


def fmt(x):
    s = "%.3f" % x
    s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def write_lua(built):
    os.makedirs(os.path.join(LUA_DIR, "Meshes"), exist_ok=True)
    manifest_lines = [
        "--[[",
        "\tManifest.lua : GÉNÉRÉ par tools/assets/build_kit.py (ne pas modifier à la main).",
        "\tKit d'assets modélisés dans Blender : pièces (mesh + rôle de couleur),",
        "\tvolumes de collision et points d'ancrage, en coordonnées Roblox (studs),",
        "\tl'origine de chaque asset étant au sol, au centre de son emprise.",
        "]]",
        "",
        "export type Piece = { Mesh: string, Role: string, Material: string, Center: Vector3, Size: Vector3, Tris: number, Shadow: boolean }",
        "export type Collider = { Shape: string, CFrame: CFrame, Size: Vector3 }",
        "export type AssetDef = { Category: string, Footprint: number, Height: number, Tris: number, Pieces: { Piece }, Colliders: { Collider }, Anchors: { [string]: Vector3 } }",
        "",
        "local Manifest: { [string]: AssetDef } = {",
    ]
    total = 0
    for a in built:
        data = {}
        pieces_lua = []
        height = 0
        for p in a.pieces:
            d = piece_data(p["obj"])
            mesh_name = f"{a.name}__{p['name']}"
            data[mesh_name] = d
            height = max(height, d["center"][1] + d["size"][1] / 2)
            pieces_lua.append(
                "\t\t\t{ Mesh = %q, Role = %q, Material = %q, Center = %s, Size = %s, Tris = %d, Shadow = %s },"
                .replace("%q", '"%s"')
                % (mesh_name, p["role"], p["material"], lua_vec(d["center"]), lua_vec(d["size"]), d["tris"], "true" if p["shadow"] else "false")
            )
        colliders_lua = []
        for c in a.colliders:
            # Cylinder : axe vertical ; CylinderX : couché (axe X local, comme Roblox)
            shape = "CylinderX" if c.get("lying") else c["shape"]
            colliders_lua.append(
                "\t\t\t{ Shape = \"%s\", CFrame = CFrame.new(%s, %s, %s) * CFrame.Angles(0, math.rad(%s), 0), Size = %s },"
                % (shape, fmt(c["pos"][0]), fmt(c["pos"][1]), fmt(c["pos"][2]), fmt(c["yaw"]), lua_vec(c["size"]))
            )
        anchors_lua = ["\t\t\t%s = %s," % (k, lua_vec(v)) for k, v in a.anchors.items()]
        footprint = ASSETS[a.name]["footprint"] or 2
        manifest_lines += [
            f"\t{a.name} = {{",
            f"\t\tCategory = \"{ASSETS[a.name]['category']}\",",
            f"\t\tFootprint = {fmt(footprint)},",
            f"\t\tHeight = {fmt(height)},",
            f"\t\tTris = {a.tris},",
            "\t\tPieces = {",
            *pieces_lua,
            "\t\t},",
            "\t\tColliders = {" + ("" if colliders_lua else "},"),
            *([*colliders_lua, "\t\t},"] if colliders_lua else []),
            "\t\tAnchors = {" + ("" if anchors_lua else "},"),
            *([*anchors_lua, "\t\t},"] if anchors_lua else []),
            "\t},",
        ]
        total += a.tris
        # Module de données de l'asset
        lines = [
            "-- GÉNÉRÉ par tools/assets/build_kit.py : géométrie de l'asset %s (Blender)." % a.name,
            "-- V : sommets int16 normalisés sur la boîte (centre, taille du manifeste), base64.",
            "-- T : triangles (indices uint16 à partir de 0), base64.",
            "return {",
        ]
        for mesh_name, d in data.items():
            lines.append('\t["%s"] = { N = %d, V = "%s", T = "%s" },' % (mesh_name, d["verts"], d["V"], d["T"]))
        lines.append("}")
        with open(os.path.join(LUA_DIR, "Meshes", a.name + ".lua"), "w") as f:
            f.write("\n".join(lines) + "\n")
    manifest_lines += ["}", "", "return Manifest", ""]
    with open(os.path.join(LUA_DIR, "Manifest.lua"), "w") as f:
        f.write("\n".join(manifest_lines))
    write_layouts()
    print(f"-> {len(built)} assets, {total} triangles au total (avant instanciation)")


def write_layouts():
    """Constantes de disposition des cartes dessinées dans Blender (une seule
    source : terrain_valley.LAYOUT) et emplacements d'arbres sur les collines."""
    try:
        import terrain_valley as TV
    except ModuleNotFoundError:
        return
    L = TV.LAYOUT
    lines = [
        "--[[",
        "\tLayouts.lua : GÉNÉRÉ par tools/assets/build_kit.py (ne pas modifier à la main).",
        "\tDisposition des cartes dont le relief est modélisé dans Blender. Les",
        "\tvaleurs doivent rester égales à Config.Maps (vérifié par test_visual).",
        "\tCoordonnées relatives au centre de la carte, en studs.",
        "]]",
        "",
        "local Layouts = {}",
        "",
        "Layouts.CarouselValley = {",
        f"\tGroundSize = {L['GroundSize']},",
        f"\tBaseRadius = {L['BaseRadius']},",
        f"\tBasePadSize = {L['BasePadSize']},",
        "\tBaseAngles = { FOX = %d, CHICKEN = %d, SNAKE = %d }," % (L["BaseAngles"]["FOX"], L["BaseAngles"]["CHICKEN"], L["BaseAngles"]["SNAKE"]),
        f"\tPlazaRadius = {L['PlazaRadius']},",
        f"\tTrackRadius = {L['TrackRadius']},",
        f"\tTrackWidth = {L['TrackWidth']},",
        f"\tLaneWidth = {L['LaneWidth']},",
        f"\tValleyEdge = {L['ValleyEdge']},",
    ]
    for key in ("Knoll", "Barn", "Creek"):
        f = L[key]
        extra = f", Height = {f['Height']}" if "Height" in f else ""
        lines.append(f"\t{key} = {{ Angle = {f['Angle']}, Radius = {f['Radius']}{extra} }},")
    (wx, wy, wz), _ = TV.wheel_spot()
    lines.append("\t-- Grande roue : pied (hauteur la plus basse de son emprise), tournée vers le centre")
    lines.append("\tBigWheel = Vector3.new(%s, %s, %s)," % (fmt(wx), fmt(wy), fmt(wz)))
    lines.append("\t-- Arbres des collines : { x, y, z, distance au bord de la vallée }")
    lines.append("\tHillTrees = {")
    for x, y, z, d in TV.tree_spots():
        lines.append("\t\t{ %s, %s, %s, %s }," % (fmt(x), fmt(y), fmt(z), fmt(d)))
    lines.append("\t},")
    lines.append("}")
    lines.append("")
    lines.append("return Layouts")
    lines.append("")
    with open(os.path.join(LUA_DIR, "Layouts.lua"), "w") as fh:
        fh.write("\n".join(lines))


# ---------------------------------------------------------------------------
# Export FBX pour l'import dans Roblox Studio
# ---------------------------------------------------------------------------
def export_fbx(built, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    # Les pièces sont rangées sur une grille (l'import n'a pas à les superposer)
    col = 0
    for a in built:
        for p in a.pieces:
            o = p["obj"]
            o.location.x += col * 30
            o.select_set(True)
        col += 1
    bpy.context.view_layer.objects.active = built[0].pieces[0]["obj"]
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        object_types={"MESH"},
        apply_unit_scale=True,
        global_scale=1.0,
        axis_forward="-Z",
        axis_up="Y",
        mesh_smooth_type="FACE",
        use_mesh_modifiers=True,
        add_leaf_bones=False,
        bake_anim=False,
    )
    col = 0
    for a in built:
        for p in a.pieces:
            p["obj"].location.x -= col * 30
        col += 1
    print("-> FBX :", os.path.relpath(path, ROOT))


# ---------------------------------------------------------------------------
# Planches de contrôle (rendus Blender, pas des captures du jeu)
# ---------------------------------------------------------------------------
def material_for(role):
    name = "mat_" + role
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    c = rgb01(PREVIEW_ROLES.get(role, (200, 200, 200)))
    # Couleurs sRGB -> linéaire
    lin = tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)
    bsdf.inputs["Base Color"].default_value = (*lin, 1)
    bsdf.inputs["Roughness"].default_value = 0.6
    if role == "Bulb":
        bsdf.inputs["Emission Color"].default_value = (*lin, 1)
        bsdf.inputs["Emission Strength"].default_value = 2.0
    return mat


def label(text, loc, size):
    curve = bpy.data.curves.new("label", "FONT")
    curve.body = text
    curve.size = size
    curve.align_x = "CENTER"
    obj = bpy.data.objects.new("label", curve)
    obj.location = loc
    obj.rotation_euler = (math.radians(90), 0, math.pi)
    K.link(obj)
    mat = bpy.data.materials.get("mat_label") or bpy.data.materials.new("mat_label")
    mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.02, 0.03, 0.06, 1)
    curve.materials.append(mat)
    return obj


def render_sheet(built, path, cols=6, title=None):
    """(title : sous-titre ; la mention « rendu Blender » est toujours ajoutée)"""
    """Planche : chaque asset ramené à la taille d'une case (échelle indiquée)."""
    sc = bpy.context.scene
    keep = set()
    for a in built:
        for p in a.pieces:
            o = p["obj"]
            keep.add(o.name)
            o.data.materials.clear()
            o.data.materials.append(material_for(p["role"]))
    # Seuls les assets de la planche sont rendus
    hidden = []
    for o in sc.objects:
        if o.type == "MESH" and o.name not in keep and not o.hide_render:
            o.hide_render = True
            hidden.append(o)
    cell = 10.0
    rows = math.ceil(len(built) / cols)
    extras = []
    saved = []
    for i, a in enumerate(built):
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        for p in a.pieces:
            (x0, y0, z0), (x1, y1, z1) = K.bounds(p["obj"])
            lo = Vector((min(lo.x, x0), min(lo.y, y0), min(lo.z, z0)))
            hi = Vector((max(hi.x, x1), max(hi.y, y1), max(hi.z, z1)))
        dims = hi - lo
        k = cell * 0.62 / max(dims.x, dims.y * 0.6, dims.z, 1e-3)
        cx = (i % cols - (cols - 1) / 2) * cell
        cz = -(i // cols) * cell * 1.05
        for p in a.pieces:
            o = p["obj"]
            saved.append((o, o.location.copy(), o.scale.copy()))
            o.scale = (k, k, k)
            o.location = (-cx - (lo.x + hi.x) / 2 * k, -(lo.y + hi.y) / 2 * k, cz - lo.z * k)
        extras.append(label(f"{a.name}", (-cx, cell * 0.45, cz - 1.1), 0.62))
        extras.append(label(f"{dims.x:.0f} x {dims.y:.0f} x {dims.z:.0f} studs  -  {a.tris} tris", (-cx, cell * 0.45, cz - 1.85), 0.42))
        # socle
        bpy.ops.mesh.primitive_cylinder_add(radius=cell * 0.42, depth=0.2, location=(-cx, 0, cz - 0.1), vertices=48)
        disc = bpy.context.active_object
        dm = bpy.data.materials.get("mat_disc") or bpy.data.materials.new("mat_disc")
        dm.use_nodes = True
        dm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.23, 0.45, 0.16, 1)
        disc.data.materials.append(dm)
        extras.append(disc)
    # Mention obligatoire : rendu Blender, pas une capture du jeu
    footer = "RENDU BLENDER (Cycles) - kit d'assets original Hunt or Hide - pas une capture Roblox Studio"
    if title:
        footer = title + "   |   " + footer
    extras.append(label(footer, (0, cell * 0.45, -(rows - 1) * cell * 1.05 - cell * 0.42), 0.5))
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.4
    sun.data.angle = math.radians(10)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
    K.link(sun)
    world = bpy.data.worlds.new("sky")
    sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.7, 0.95, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    K.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    width = cell * cols
    height = cell * 1.05 * rows
    cam.data.ortho_scale = max(width * 1.02, height * 1.95)
    # Vue de face : l'avant des assets (+Y Blender, -Z Roblox) regarde la caméra
    pitch = math.radians(78)
    cam.rotation_euler = (pitch, 0, math.pi)
    mid_z = -(rows - 1) * cell * 1.05 / 2 - cell * 0.05
    cam.location = (0, 60 * math.sin(pitch), mid_z + 60 * math.cos(pitch))
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.cycles.device = "CPU"
    sc.view_settings.view_transform = "Standard"
    sc.render.film_transparent = False
    sc.render.resolution_x = 1800
    sc.render.resolution_y = int(1800 * min(1.0, (height * 1.22) / (width * 1.02)))
    if path.endswith(".jpg"):
        sc.render.image_settings.file_format = "JPEG"
        sc.render.image_settings.quality = 88
    sc.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    t0 = time.time()
    bpy.ops.render.render(write_still=True)
    print(f"-> planche {os.path.relpath(path, ROOT)} ({time.time() - t0:.0f} s)")
    for o, loc, scale in saved:
        o.location = loc
        o.scale = scale
    for o in hidden:
        o.hide_render = False
    for o in extras + [sun, cam]:
        bpy.data.objects.remove(o, do_unlink=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    parser.add_argument("--sheet", action="store_true")
    parser.add_argument("--sheet-out", default="")
    parser.add_argument("--no-export", action="store_true")
    parser.add_argument("--sheets", action="store_true", help="planches par famille dans reference/preuves/kit")
    args = parser.parse_args()
    names = [n for n in args.only.split(",") if n] or ORDER
    K.reset()
    print(f"Construction de {len(names)} assets")
    built = build(names)
    if args.sheet:
        out = args.sheet_out or os.path.join(SHEET_DIR, "kit_sheet.jpg")
        render_sheet(built, out)
    if args.sheets:
        nature_decor = {"FlowerPatch", "GrassTuft", "Mushrooms", "Stump", "Log"}
        groups = [
            ("kit_nature.jpg", "Nature : arbres, buissons, rochers, fleurs", lambda n, c: c in ("Tree", "Bush", "Rock") or n in nature_decor),
            ("kit_village.jpg", "Village : clôtures, couvertures, grange, moulin, décor", lambda n, c: c in ("Fence", "Cover") or (c == "Landmark" and n not in ("CarouselHub", "HotAirBalloon", "BigWheel")) or (c == "Decor" and n not in nature_decor)),
            ("kit_fete_camps.jpg", "Fête, objectifs et camps des équipes", lambda n, c: c in ("Ride", "Objective", "Camp") or n in ("CarouselHub", "HotAirBalloon", "BigWheel")),
        ]
        by_name = {a.name: a for a in built}
        for filename, title, accept in groups:
            subset = [by_name[n] for n in ORDER if n in by_name and accept(n, ASSETS[n]["category"])]
            if subset:
                render_sheet(subset, os.path.join(SHEET_DIR, filename), title=title)
    if not args.no_export:
        write_lua(built)
        export_fbx(built, os.path.join(KIT_DIR, "HoH_Kit.fbx"))


if __name__ == "__main__":
    main()
