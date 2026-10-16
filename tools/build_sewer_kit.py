"""The sewer kit: Higgsfield/Tripo pieces fitted for scripts/sewer.gd.

    blender -b --factory-startup -P tools/build_sewer_kit.py

Sources (models/source/sewer_hf/, a .gdignore folder): images made with
Higgsfield's gpt_image_2_5 from the user's wall and vault photos, turned into
models by Tripo H3.1 through Higgsfield (2026-10-15):
  raw_tunnel.glb  -- one straight section of round brick sewer tunnel with a
                     walkway each side of a sunken channel and a drain grate.
  raw_grate.glb   -- a rusted, padlocked, round-topped iron gate.
  raw_bones.glb   -- a heap of bones, skulls and broken brick in muck.
  raw_fungus.glb  -- pale drooping sewer fungus on broken bricks and sludge.
(raw_chamber.glb came back tilted ~15 deg with its near wall cut low -- the
cutaway the image asked for -- and is not used: the chambers are built in the
game from the measured tunnel profile.)

Writes models/sewer/sewer_kit.glb with objects "tunnel", "grate", "bones",
"fungus" and models/sewer/tunnel_profile.json.

Conventions (Blender, Z up; Godot gets Y up, -Y here becomes +Z there):
  tunnel  runs along Y, TUNNEL_LEN long, centred; the walkways' top is z = 0.
          The generated section TAPERED (the image's perspective: interior
          half-width 0.19 at one end, 0.24 at the other in its raw units), so
          every cross-section is scaled about the walkway line to the middle's
          size first -- sections must meet end to end.
  grate   stands in the XZ plane (thin along Y), base z = 0, 1 unit wide.
  props   base z = 0, centred, at their game size.
The profile JSON gives the tunnel's inside, in metres, as [height, half-width]
pairs from the channel's bottom to the crown, measured at mid-length with
rays: sewer.gd cuts the chamber mouths to it.
"""
import json
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(HERE, "models", "source", "sewer_hf")
OUT_DIR = os.path.join(HERE, "models", "sewer")
OUT = os.path.join(OUT_DIR, "sewer_kit.glb")

TUNNEL_LEN = 6.0
## Cross-section scale (raw units -> metres): the inside comes out ~3.8 m wide
## at the walkways and ~3.7 m from walkway to crown.
TUNNEL_XS = 9.0
## The walkways' top in the raw model (measured: -0.179 .. -0.192).
RAW_WALK_Z = -0.185
## Faces kept per piece (the raw tunnel is 38k triangles; ~120 of them make
## the sewer).
BUDGET = {"tunnel": 26000, "grate": 6000, "bones": 6000, "fungus": 6000}
PROP_SIZE = {"bones": 1.5, "fungus": 1.0}


def log(*a):
    print("[sewer kit]", *a)


def load(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in new:
        o.select_set(True)
    bpy.context.view_layer.objects.active = new[0]
    if len(new) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    # Free of any import parent, transforms applied.
    mw = ob.matrix_world.copy()
    ob.parent = None
    ob.matrix_world = mw
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.data.objects):
        if o.type == "EMPTY":
            bpy.data.objects.remove(o)
    return ob


def verts(ob):
    return np.array([tuple(v.co) for v in ob.data.vertices])


def set_verts(ob, a):
    for v, p in zip(ob.data.vertices, a):
        v.co = Vector(p)
    ob.data.update()


def decimate(ob, target):
    n = len(ob.data.polygons)
    if n <= target:
        return
    m = ob.modifiers.new("dec", "DECIMATE")
    m.ratio = target / n
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier=m.name)
    log("%s: %d -> %d faces" % (ob.name, n, len(ob.data.polygons)))


def stations(ob, ys, z_mid, x_probe=0.0):
    """Per station along Y: (centre x, half-width, crown z) of the inside."""
    bvh = BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get())
    rows = []
    for y in ys:
        o = Vector((x_probe, y, z_mid))
        a = bvh.ray_cast(o, Vector((1, 0, 0)))
        b = bvh.ray_cast(o, Vector((-1, 0, 0)))
        if a[0] is None or b[0] is None:
            continue
        cx = (a[0].x + b[0].x) * 0.5
        c = bvh.ray_cast(Vector((cx, y, z_mid)), Vector((0, 0, 1)))
        if c[0] is None:
            continue
        rows.append((y, cx, (a[0].x - b[0].x) * 0.5, c[0].z))
    return np.array(rows)


def face_inside(ob, z_axis=1.5):
    """Wind every face the tunnel's axis can see TOWARD the axis.

    The section is a shell you stand inside. normals_make_consistent points a
    shell's normals away from its centre, which turned the whole vault away
    from the player: from inside every face above the walkway was a back
    face, and the tunnels rendered black beside a lit torch. A ray from the
    axis (at the face's own Y) to each face's centre: if it first meets that
    face and the face looks away, flip it."""
    bvh = BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get())
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    flip = []
    seen = 0
    for f in bm.faces:
        c = f.calc_center_median()
        o = Vector((0.0, c.y, z_axis))
        d = c - o
        if d.length < 1e-4:
            continue
        d.normalize()
        hit = bvh.ray_cast(o, d, 20.0)
        if hit[2] != f.index:
            continue
        seen += 1
        if f.normal.dot(d) > 0.0:
            flip.append(f)
    bmesh.ops.reverse_faces(bm, faces=flip)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    log("tunnel: %d faces seen from the axis, %d turned to face it" % (seen, len(flip)))


def build_tunnel():
    ob = load("raw_tunnel")
    p = verts(ob)
    # Raw: length along X (open ends at +-0.5), Y across, Z up. To game axes
    # first: length along Y, across X, walkway at z = 0, in metres.
    out = np.zeros_like(p)
    out[:, 0] = p[:, 1] * TUNNEL_XS
    out[:, 1] = p[:, 0] * (TUNNEL_LEN / (p[:, 0].max() - p[:, 0].min()))
    out[:, 2] = (p[:, 2] - RAW_WALK_Z) * TUNNEL_XS
    out[:, 1] -= (out[:, 1].max() + out[:, 1].min()) * 0.5
    set_verts(ob, out)
    # The generated section is not a true prism: the image's perspective made
    # it TAPER, and it also drifts sideways and its crown slopes along its
    # length. Measured at stations along it (centre line and half-width at
    # mid-height, crown above the centre), fitted with lines, and every
    # cross-section moved and scaled (about the walkway line) to the middle's.
    ys = np.linspace(-TUNNEL_LEN * 0.42, TUNNEL_LEN * 0.42, 9)
    st = stations(ob, ys, 1.6)
    kc, c0 = np.polyfit(st[:, 0], st[:, 1], 1)
    kw, w0 = np.polyfit(st[:, 0], st[:, 2], 1)
    kh, h0 = np.polyfit(st[:, 0], st[:, 3], 1)
    log("tunnel before: centre %.3f%+.3f y, half-width %.3f%+.3f y, crown %.3f%+.3f y" % (c0, kc, w0, kw, h0, kh))
    q = verts(ob)
    y = q[:, 1]
    q[:, 0] = (q[:, 0] - (c0 + kc * y)) * (w0 / (w0 + kw * y))
    q[:, 2] = q[:, 2] * (h0 / (h0 + kh * y))
    set_verts(ob, q)
    st2 = stations(ob, ys, 1.6)
    log("tunnel after: centre %.3f..%.3f, half-width %.3f..%.3f, crown %.3f..%.3f" % (
        st2[:, 1].min(), st2[:, 1].max(), st2[:, 2].min(), st2[:, 2].max(), st2[:, 3].min(), st2[:, 3].max()))
    ob.name = "tunnel"
    decimate(ob, BUDGET["tunnel"])
    face_inside(ob)
    # Re-flatten the open ends exactly on +-TUNNEL_LEN/2 so sections meet.
    q = verts(ob)
    end = TUNNEL_LEN * 0.5
    q[:, 1] = np.clip(q[:, 1], -end, end)
    set_verts(ob, q)
    profile(ob)
    return ob


def profile(ob):
    """The inside's half-width at each height, at mid-length and at both ends."""
    bvh = BVHTree.FromObject(ob, bpy.context.evaluated_depsgraph_get())
    q = verts(ob)
    rows = []
    stations = {}
    for y in (-TUNNEL_LEN * 0.45, 0.0, TUNNEL_LEN * 0.45):
        floor = bvh.ray_cast(Vector((0, y, 1.0)), Vector((0, 0, -1)))
        crown = bvh.ray_cast(Vector((0, y, 0.5)), Vector((0, 0, 1)))
        stations[y] = (floor[0].z if floor[0] else None, crown[0].z if crown[0] else None)
    z_lo = stations[0.0][0]
    z_hi = stations[0.0][1]
    z = z_lo + 0.02
    while z < z_hi - 0.02:
        a = bvh.ray_cast(Vector((0, 0, z)), Vector((1, 0, 0)))
        b = bvh.ray_cast(Vector((0, 0, z)), Vector((-1, 0, 0)))
        if a[0] is not None and b[0] is not None:
            rows.append([round(z, 3), round(min(a[0].x, -b[0].x), 3)])
        z += 0.1
    rows.append([round(z_hi, 3), 0.0])
    walk = []
    for x in np.arange(-1.6, 1.61, 0.2):
        h = bvh.ray_cast(Vector((x, 0, 1.0)), Vector((0, 0, -1)))
        walk.append([round(float(x), 2), round(h[0].z, 3) if h[0] else None])
    data = {"length": TUNNEL_LEN, "floor": round(z_lo, 3), "crown": round(z_hi, 3),
            "half_width": rows, "floor_across": walk,
            "outer_half_width": round(float(np.abs(q[:, 0]).max()), 3),
            "bottom": round(float(q[:, 2].min()), 3), "top": round(float(q[:, 2].max()), 3),
            "ends": {str(k): v for k, v in stations.items()}}
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "tunnel_profile.json"), "w") as f:
        json.dump(data, f, indent=1)
    log("tunnel: floor %.2f crown %.2f, outer half-width %.2f, %.2f..%.2f" % (
        z_lo, z_hi, data["outer_half_width"], data["bottom"], data["top"]))
    log("tunnel ends (floor, crown): %s" % stations)
    log("tunnel floor across: %s" % walk)


def build_grate():
    ob = load("raw_grate")
    p = verts(ob)
    # Raw: thin along X, width along Y, height along Z. To: width X, thin Y.
    out = np.stack([p[:, 1], p[:, 0], p[:, 2]], 1)
    out[:, 2] -= out[:, 2].min()
    out[:, 0] -= (out[:, 0].max() + out[:, 0].min()) * 0.5
    out[:, 1] -= (out[:, 1].max() + out[:, 1].min()) * 0.5
    out /= (out[:, 0].max() - out[:, 0].min())
    set_verts(ob, out)
    ob.name = "grate"
    decimate(ob, BUDGET["grate"])
    q = verts(ob)
    log("grate: %.2f wide, %.2f tall, %.2f thick (units of its width)" % tuple(np.ptp(q, 0)[[0, 2, 1]]))
    return ob


def build_prop(name):
    ob = load("raw_" + name)
    p = verts(ob)
    p[:, 2] -= p[:, 2].min()
    p[:, 0] -= (p[:, 0].max() + p[:, 0].min()) * 0.5
    p[:, 1] -= (p[:, 1].max() + p[:, 1].min()) * 0.5
    span = max(np.ptp(p[:, 0]), np.ptp(p[:, 1]))
    p *= PROP_SIZE[name] / span
    set_verts(ob, p)
    ob.name = name
    decimate(ob, BUDGET[name])
    log("%s: %.2f x %.2f x %.2f m" % ((name,) + tuple(np.ptp(verts(ob), 0))))
    return ob


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    built = [build_tunnel(), build_grate(), build_prop("bones"), build_prop("fungus")]
    for o in built:
        for m in o.data.materials:
            m.name = "sewer_" + o.name
    bpy.ops.object.select_all(action="DESELECT")
    for o in built:
        o.select_set(True)
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format="GLB",
                              export_image_format="JPEG", export_jpeg_quality=90)
    log("wrote %s (%.1f MB)" % (OUT, os.path.getsize(OUT) / 1e6))


main()
