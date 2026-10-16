"""The sewer's generated props, fitted for scripts/sewer.gd.

    blender -b --factory-startup -P tools/build_sewer_kit.py

Source (models/source/sewer_hf/, a .gdignore folder): raw_bones.glb -- a heap of
bones, skulls and broken brick in muck, from a Higgsfield gpt_image_2_5 image
turned into a model by Tripo H3.1 through Higgsfield (2026-10-15).

Writes models/sewer/sewer_kit.glb with the object "bones" (base z = 0, centred,
PROP_SIZE across).

The first pass also made the tunnels, a gate and fungus from generated models.
They were replaced (2026-10-15, second pass): a generated section is baked per
piece, so its brick could never match the domes' and its channel ended in a lip
at every join. The sewer is now one CSG in one brick (sewer.gd), with the
Higgsfield textures doing the work (tools/build_sewer_texture.py).
"""
import os

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(HERE, "models", "source", "sewer_hf")
OUT_DIR = os.path.join(HERE, "models", "sewer")
OUT = os.path.join(OUT_DIR, "sewer_kit.glb")

BUDGET = {"bones": 6000}
PROP_SIZE = {"bones": 1.5}


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
    built = [build_prop("bones")]
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
