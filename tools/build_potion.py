"""Build the health potion the player holds, as a small GLB.

    blender -b --factory-startup -P tools/build_potion.py -- models/potion_held.glb

A round-bottomed glass flask with a narrow neck and a lip, the liquid as its
own inner volume filled to about two thirds with a flat surface, a cork, and
a twine wrap round the neck. Every round part is a lathe: a profile in (radius,
height) spun about Blender +Z, which the glTF exporter maps to Godot +Y, so the
flask stands up with its base at the origin. Metres, 0.27 tall.

The materials here are placeholders with the right NAMES: `held_potion.gd`
replaces them in Godot by name -- the glass needs alpha blending and the
liquid an emission level that the glTF round trip does not carry reliably.
"""

import bpy
import bmesh
import math
import sys

OUT = sys.argv[sys.argv.index("--") + 1]
STEPS = 40


def log(*a):
    print("[potion]", *a)


def material(name, colour):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs["Base Color"].default_value = colour
    return mat


def lathe(name, profile, mat, smooth=True):
    """`profile` is [(radius, height)], bottom to top. A point at radius 0
    closes the end it is on."""
    bm = bmesh.new()
    verts = [bm.verts.new((r, 0.0, z)) for (r, z) in profile]
    edges = [bm.edges.new((a, b)) for a, b in zip(verts, verts[1:])]
    bmesh.ops.spin(bm, geom=verts + edges, cent=(0, 0, 0), axis=(0, 0, 1),
                   angle=math.tau, steps=STEPS, use_merge=True)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = smooth
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mat)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def ring(name, z, major, minor, mat):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=STEPS, minor_segments=8,
                                     location=(0.0, 0.0, z))
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.use_smooth = True
    return obj


bpy.ops.wm.read_factory_settings(use_empty=True)
GLASS = material("PotionGlass", (0.75, 0.9, 0.8, 1.0))
LIQUID = material("PotionLiquid", (0.1, 0.9, 0.25, 1.0))
CORK = material("PotionCork", (0.45, 0.3, 0.17, 1.0))
TWINE = material("PotionTwine", (0.55, 0.47, 0.32, 1.0))

# The glass: a round belly on a small flat foot, a shoulder, a long neck and a
# rolled lip. One shell -- the cork closes the top.
glass = lathe("Glass", [
    (0.000, 0.000), (0.040, 0.002), (0.068, 0.012), (0.087, 0.032),
    (0.097, 0.058), (0.099, 0.082), (0.093, 0.108), (0.078, 0.130),
    (0.056, 0.148), (0.034, 0.162), (0.025, 0.176), (0.024, 0.212),
    (0.030, 0.218), (0.032, 0.226), (0.028, 0.232), (0.022, 0.232),
], GLASS)

# The liquid, just inside the glass, up to a flat surface at about two thirds
# of the belly.
liquid = lathe("Liquid", [
    (0.000, 0.006), (0.036, 0.008), (0.062, 0.017), (0.080, 0.035),
    (0.089, 0.058), (0.091, 0.080), (0.087, 0.098), (0.000, 0.098),
], LIQUID)

cork = lathe("Cork", [
    (0.000, 0.200), (0.020, 0.200), (0.021, 0.232), (0.026, 0.252),
    (0.027, 0.262), (0.023, 0.270), (0.000, 0.271),
], CORK, smooth=False)

twine = [ring("Twine%d" % i, z, 0.0262, 0.0042, TWINE)
         for i, z in enumerate((0.184, 0.192, 0.200))]

parts = [glass, liquid, cork] + twine
for o in parts:
    o.data.calc_loop_triangles()
log("triangles:", sum(len(o.data.loop_triangles) for o in parts))
for o in parts:
    zs = [v.co.z + o.location.z for v in o.data.vertices]
    log("%-8s z %.3f -> %.3f" % (o.name, min(zs), max(zs)))

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    export_animations=False,
    export_skins=False,
    export_apply=True,
    export_yup=True,
    export_materials='EXPORT',
    use_selection=False,
)
log("wrote", OUT)
