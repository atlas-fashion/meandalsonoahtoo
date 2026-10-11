"""Build the player's arming sword as a single low-poly GLB.

Modelled from the reference photo: straight double-edged blade with a central
fuller, a brass crossguard whose quillons droop toward the tip and flare at the
ends, a corded leather grip, and a flattened fan-shaped brass pommel.

Built along Blender **+Z**, because the glTF exporter maps Blender +Z to glTF
(and Godot) +Y -- which is the axis `Head/SwordPivot` points the sword down.
Blender X stays Godot X (blade width); Blender Y becomes Godot Z (blade
thickness).

Footprint matches the box-mesh sword it replaces so the first-person framing
does not shift: butt at 0.0, tip at 2.65, blade 0.26 wide by 0.08 thick, guard
0.62 across.
"""

import bpy
import bmesh
import math
import sys

OUT = sys.argv[sys.argv.index("--") + 1]

TIP = 2.65
BLADE_BASE = 0.45
GUARD_Y = 0.40
GRIP_TOP = 0.355


def log(*a):
    print("[sword]", *a)


def srgb(r, g, b):
    """glTF stores base colour LINEAR; Godot shows it as sRGB. Authoring in the
    sRGB numbers directly imports about 30% too bright."""
    def to_linear(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (to_linear(r), to_linear(g), to_linear(b), 1.0)


def material(name, colour, metallic, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs["Base Color"].default_value = colour
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def ring(bm, pts, along, axis="z"):
    out = []
    for p in pts:
        if axis == "z":
            out.append(bm.verts.new((p[0], p[1], along)))
        else:  # guard lofts along X instead
            out.append(bm.verts.new((along, p[0], p[1])))
    return out


def bridge(bm, a, b):
    n = len(a)
    for i in range(n):
        j = (i + 1) % n
        try:
            bm.faces.new((a[i], a[j], b[j], b[i]))
        except ValueError:
            pass


def cap(bm, r, flip=False):
    try:
        bm.faces.new(list(reversed(r)) if flip else list(r))
    except ValueError:
        pass


def finish(bm, name, mat):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(obj)
    return obj


# ---------------------------------------------------------------------------
# blade: lens cross-section with a fuller ground into both faces
# ---------------------------------------------------------------------------
def blade_profile(w, t, fuller):
    """16 points around the section. `fuller` is how deep the groove is cut."""
    f = t - fuller
    half = [
        (w, 0.0),
        (w * 0.78, t * 0.52),
        (w * 0.50, t),
        (w * 0.32, f),
        (0.0, f),
        (-w * 0.32, f),
        (-w * 0.50, t),
        (-w * 0.78, t * 0.52),
    ]
    back = [(x, -y) for (x, y) in reversed(half[1:])]
    return half + [(-w, 0.0)] + back


def build_blade():
    bm = bmesh.new()
    #        along   half-width  half-thick  fuller depth
    # Edges stay near-parallel like the reference and only taper over the last
    # 0.33, which keeps the blade from reading as a leaf shape.
    spine = [
        (BLADE_BASE, 0.130, 0.040, 0.000),
        (0.520,      0.130, 0.040, 0.021),
        (1.000,      0.130, 0.039, 0.022),
        (1.600,      0.129, 0.038, 0.022),
        (2.050,      0.127, 0.036, 0.021),
        (2.200,      0.126, 0.035, 0.010),
        (2.320,      0.124, 0.034, 0.000),
        (2.460,      0.107, 0.030, 0.000),
        (2.570,      0.070, 0.023, 0.000),
        (TIP,        0.018, 0.010, 0.000),
    ]
    rings = [ring(bm, blade_profile(w, t, f), u) for (u, w, t, f) in spine]
    for a, b in zip(rings, rings[1:]):
        bridge(bm, a, b)
    cap(bm, rings[0], flip=True)
    cap(bm, rings[-1])
    return finish(bm, "Blade", MAT_STEEL)


# ---------------------------------------------------------------------------
# grip: tapered oval with corded wrap ridges
# ---------------------------------------------------------------------------
def oval(rx, ry, n=10):
    return [(rx * math.cos(2 * math.pi * i / n), ry * math.sin(2 * math.pi * i / n))
            for i in range(n)]


def build_grip():
    bm = bmesh.new()
    rings = []
    steps = 22
    for i in range(steps + 1):
        s = i / steps
        u = 0.030 + s * (GRIP_TOP - 0.030)
        # Slightly fatter at the pommel end, as in the photo.
        base = 0.043 - 0.007 * s
        # Seven shallow ridges read as a cord wrap without costing a texture.
        ridge = 0.0035 * (0.5 + 0.5 * math.cos(s * 7.0 * 2.0 * math.pi))
        r = base + ridge
        rings.append(ring(bm, oval(r, r * 0.80), u))
    for a, b in zip(rings, rings[1:]):
        bridge(bm, a, b)
    cap(bm, rings[0], flip=True)
    cap(bm, rings[-1])
    return finish(bm, "Grip", MAT_LEATHER)


# ---------------------------------------------------------------------------
# fittings: pommel + crossguard + the collar where the guard meets the blade
# ---------------------------------------------------------------------------
def build_pommel():
    bm = bmesh.new()
    # A wide, flat fan rather than a ball -- the reference pommel is much broader
    # than it is thick, so x and y radii are given independently.
    #       along    x radius  y radius
    stack = [
        (-0.088, 0.030, 0.015),
        (-0.072, 0.074, 0.026),
        (-0.046, 0.100, 0.031),
        (-0.014, 0.106, 0.032),
        (0.014,  0.088, 0.030),
        (0.038,  0.059, 0.026),
        (0.058,  0.044, 0.022),
    ]
    rings = [ring(bm, oval(rx, ry, 12), u) for (u, rx, ry) in stack]
    for a, b in zip(rings, rings[1:]):
        bridge(bm, a, b)
    cap(bm, rings[0], flip=True)
    cap(bm, rings[-1])
    return finish(bm, "Pommel", MAT_BRASS)


def guard_section(h, d):
    """Rounded rectangle in the (along-blade, thickness) plane."""
    return [
        (h, d * 0.55), (h * 0.55, d), (-h * 0.55, d), (-h, d * 0.55),
        (-h, -d * 0.55), (-h * 0.55, -d), (h * 0.55, -d), (h, -d * 0.55),
    ]


def build_guard():
    bm = bmesh.new()
    rings = []
    steps = 16
    for i in range(steps + 1):
        s = -1.0 + 2.0 * i / steps
        x = 0.31 * s
        a = abs(s)
        # Quillons droop toward the tip, and flare at the ends.
        droop = 0.058 * (a ** 1.7)
        # Chunky flared quillon tips, as in the reference.
        flare = 1.0 + 1.10 * (a ** 3.0)
        h = 0.030 * flare
        d = 0.038 * (1.0 + 0.90 * (a ** 3.0))
        pts = [(p[0] + GUARD_Y + droop, p[1]) for p in guard_section(h, d)]
        # Lofted along X, so the section lives in (Z, Y) -- swap into place.
        rings.append([bm.verts.new((x, p[1], p[0])) for p in pts])
    for a, b in zip(rings, rings[1:]):
        bridge(bm, a, b)
    cap(bm, rings[0], flip=True)
    cap(bm, rings[-1])

    # Central collar: the raised block the blade passes through.
    collar = []
    for u, r in ((0.352, 0.052), (0.395, 0.060), (0.452, 0.055), (0.478, 0.040)):
        collar.append(ring(bm, guard_section(r, r * 0.80), u))
    for a, b in zip(collar, collar[1:]):
        bridge(bm, a, b)
    cap(bm, collar[0], flip=True)
    cap(bm, collar[-1])
    return finish(bm, "Fittings", MAT_BRASS)


# ---------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
# Materials are created *after* the reset -- making them first would have them
# wiped out from under the builders.
MAT_STEEL = material("SwordSteel", srgb(0.60, 0.62, 0.66), 0.85, 0.30)
MAT_BRASS = material("SwordBrass", srgb(0.62, 0.50, 0.24), 0.80, 0.38)
MAT_LEATHER = material("SwordLeather", srgb(0.42, 0.24, 0.19), 0.0, 0.92)

blade = build_blade()
grip = build_grip()
pommel = build_pommel()
guard = build_guard()

# Pommel and guard share the brass material, so they merge into one surface.
parts = [blade, grip, pommel, guard]
bpy.context.view_layer.objects.active = blade
for o in parts:
    o.select_set(True)
with bpy.context.temp_override(active_object=blade, object=blade,
                               selected_objects=parts,
                               selected_editable_objects=parts):
    bpy.ops.object.join()
blade.name = "Sword"
blade.data.name = "Sword"

# Shade smooth, but keep the edges and the fuller crisp.
try:
    with bpy.context.temp_override(active_object=blade, object=blade,
                                   selected_objects=[blade],
                                   selected_editable_objects=[blade]):
        bpy.ops.object.shade_auto_smooth(angle=math.radians(38.0))
except Exception as exc:
    log("auto smooth unavailable, leaving flat:", exc)

blade.data.calc_loop_triangles()
log("triangles:", len(blade.data.loop_triangles))
log("materials:", [m.name for m in blade.data.materials])
log("bounds z:", round(min(v.co.z for v in blade.data.vertices), 4),
    "->", round(max(v.co.z for v in blade.data.vertices), 4))
log("bounds x:", round(min(v.co.x for v in blade.data.vertices), 4),
    "->", round(max(v.co.x for v in blade.data.vertices), 4))
log("bounds y:", round(min(v.co.y for v in blade.data.vertices), 4),
    "->", round(max(v.co.y for v in blade.data.vertices), 4))

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    export_animations=False,
    export_skins=False,
    export_apply=False,
    export_yup=True,
    export_materials='EXPORT',
    use_selection=False,
)
log("wrote", OUT)
