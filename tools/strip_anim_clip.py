"""Strip a Higgsfield / Meshy animated rig down to its skeleton and its clip.

    blender -b --factory-startup -P tools/strip_anim_clip.py -- in.glb out.glb clip_name

Higgsfield's 3D Rigging (Meshy) with an animation returns the whole knight --
mesh, 4096 textures, 8 MB -- for one clip. The game needs only the bones' motion:
the player's body is models/player_knight.glb on the same 24-bone Meshy skeleton
(note 155), and player_motion.gd retargets each clip onto it rest-relative.

What is kept: the armature, its one action (renamed `clip_name`), and ONE
triangle of the mesh, still skinned, with no material. Without a skinned mesh
Godot's glTF importer makes the bones plain Node3Ds instead of a Skeleton3D, and
the clip's tracks then target nodes, not bones. Meshy's stray icosphere goes.
See docs/notes/167.
"""

import bpy
import bmesh
import sys

ARGS = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, NAME = ARGS[0], ARGS[1], ARGS[2]

bpy.ops.wm.read_factory_settings(use_empty=True)
# Meshy samples at 30 fps; the importer keys at time * the scene rate, and the
# exporter resamples at it, so the scene runs at 30 for both.
bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=SRC)

arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
# The body: the mesh skinned to the armature. Anything else (the icosphere) goes.
body = None
for o in meshes:
    if any(m.type == "ARMATURE" for m in o.modifiers) or o.parent == arm:
        if body is None or len(o.data.polygons) > len(body.data.polygons):
            body = o
for o in meshes:
    if o is not body:
        bpy.data.objects.remove(o, do_unlink=True)

# One triangle left, its material slots cleared.
bm = bmesh.new()
bm.from_mesh(body.data)
bm.faces.ensure_lookup_table()
keep = bm.faces[0]
bmesh.ops.delete(bm, geom=[f for f in bm.faces if f is not keep], context="FACES")
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
bm.to_mesh(body.data)
bm.free()
body.data.materials.clear()

# The clip, under its game name. Meshy names it "Armature|<Name>|baselayer".
actions = list(bpy.data.actions)
if not actions:
    raise SystemExit("no action in " + SRC)
act = max(actions, key=lambda a: a.frame_range[1] - a.frame_range[0])
act.name = NAME
if arm.animation_data is None:
    arm.animation_data_create()
arm.animation_data.action = act
for a in actions:
    if a is not act:
        bpy.data.actions.remove(a)
frames = act.frame_range
print("CLIP", NAME, "frames", frames[0], frames[1], "fps", bpy.context.scene.render.fps)

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_force_sampling=True,
    export_materials="NONE",
)
print("WROTE", OUT)
