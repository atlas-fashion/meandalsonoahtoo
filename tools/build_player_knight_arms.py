"""Build models/player_knight_arms.glb, the knight's arms for the first-person view.

Source: models/player_knight.glb (tools/build_player_knight.py -- run that first;
this reads its output, so the emission map and the metal come with it).

What this does to it:
  - keeps only the arms: every vertex whose strongest bone is an Arm, ForeArm or
    Hand (the pauldrons ride the Shoulder bones and would sit on the camera);
    faces that touch anything else are cut away;
  - closes both hands into fists: the rig has no finger bones, so the fingers
    are bent in the mesh, round the knuckle line, about a handle the size of
    the sword's grip (`CURL_R`), the thumb left lying over it;
  - writes no materials or textures: first_person_arms.gd dresses the arms in
    the body's own material, so the 2048 maps are in video memory once;
  - keeps the whole 24-bone skeleton, so the bones and their names are the
    knight's (scripts/first_person_arms.gd poses Arm, ForeArm and Hand).

Prints each fist's grip point (the handle's centre) in glTF space, which
first_person_arms.gd `GRIP` holds.

Run (Blender 5.2):
  blender -b --factory-startup -P tools/build_player_knight_arms.py
then `godot --headless --import --path .`. Never hand-edit the output.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "models", "player_knight.glb")
OUT = os.path.join(ROOT, "models", "player_knight_arms.glb")
KEEP = {"LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand"}
# The knuckle line, as distance from the body's centre along the arm (Blender X,
# the T-pose arm). The hand runs 0.77 -> 1.00; the fingers start at 0.925,
# where the hand narrows to them, and the thumb lies inside that.
KNUCKLE = 0.918
# Finger centre height (Blender Z) and the radius they wrap round.
FINGER_Z = 1.355
CURL_R = 0.026
CURL_MAX = 2.75

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
groups = {g.index: g.name for g in mesh.vertex_groups}
mw = mesh.matrix_world
inv = mw.inverted()

bm = bmesh.new()
bm.from_mesh(mesh.data)
deform = bm.verts.layers.deform.active
keep = set()
for v in bm.verts:
    w = v[deform]
    if w:
        g = max(w.items(), key=lambda e: e[1])[0]
        if groups[g] in KEEP:
            keep.add(v.index)
drop = [f for f in bm.faces if any(v.index not in keep for v in f.verts)]
bmesh.ops.delete(bm, geom=drop, context="FACES_ONLY")
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")


def curl(p: Vector) -> Vector:
    """A finger point bent down (toward the palm, -Z) round the knuckle line."""
    side = 1.0 if p.x > 0.0 else -1.0
    u = abs(p.x) - KNUCKLE
    if u <= 0.0:
        return p
    d = p.z - FINGER_Z
    th = min(u / CURL_R, CURL_MAX)
    extra = u - CURL_R * th
    r = CURL_R + d
    x = KNUCKLE + r * math.sin(th) + extra * math.cos(th)
    z = FINGER_Z - CURL_R + r * math.cos(th) - extra * math.sin(th)
    return Vector((side * x, p.y, z))


for v in bm.verts:
    v.co = inv @ curl(mw @ v.co)
bm.to_mesh(mesh.data)
bm.free()
mesh.data.update()
print("arms: %d vertices, %d faces" % (len(mesh.data.vertices), len(mesh.data.polygons)))

# The handle runs through the curl's centre, front to back (Blender Y): its
# middle across the hand's depth.
ys = [(mw @ v.co).y for v in mesh.data.vertices if abs((mw @ v.co).x) > KNUCKLE - 0.06]
ymid = 0.5 * (min(ys) + max(ys))
for side in (1.0, -1.0):
    b = Vector((side * KNUCKLE, ymid, FINGER_Z - CURL_R))
    print("GRIP %s glTF (%.4f, %.4f, %.4f)" % ("left" if side > 0 else "right", b.x, b.z, -b.y))

if "--preview" in sys.argv:
    out = sys.argv[-1]
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    scn = bpy.context.scene
    scn.render.resolution_x = 700
    scn.render.resolution_y = 500
    world = bpy.data.worlds.new("w")
    scn.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.5
    hand = Vector((-0.86, 0.05, 1.34))
    for name, off, up in [("fist_front", Vector((0, -0.45, 0.05)), "Y"),
            ("fist_end", Vector((-0.45, -0.05, 0.05)), "Y"),
            ("fist_below", Vector((-0.05, -0.1, -0.45)), "Y"),
            ("arms_whole", Vector((0.86, -2.4, 0.0)), "Y")]:
        cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
        scn.collection.objects.link(cam)
        cam.location = hand + off
        cam.rotation_euler = (hand + (Vector((0.86, 0, 0)) if name == "arms_whole" else Vector()) -
            cam.location).to_track_quat("-Z", up).to_euler()
        scn.camera = cam
        scn.render.filepath = os.path.join(out, name + ".png")
        bpy.ops.render.render(write_still=True)
else:
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        export_animations=False,
        # No materials: the game dresses the arms in the knight's own (its
        # textures loaded once, not twice).
        export_materials="NONE",
        export_yup=True,
    )
    print("wrote", OUT, os.path.getsize(OUT))
