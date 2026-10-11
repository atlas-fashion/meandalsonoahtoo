"""Render key frames of every clip so the poses can actually be looked at."""

import bpy
import sys
import os
import math
from mathutils import Vector

GLB = sys.argv[sys.argv.index("--") + 1]
OUTDIR = sys.argv[sys.argv.index("--") + 2]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')

scene = bpy.context.scene
scene.render.engine = 'BLENDER_WORKBENCH'
scene.render.resolution_x = 340
scene.render.resolution_y = 430
scene.render.resolution_percentage = 100
scene.render.film_transparent = False
scene.display.shading.light = 'STUDIO'
scene.display.shading.color_type = 'MATERIAL'
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
# Workbench takes its backdrop from the shading settings, not the world.
scene.display.shading.background_type = 'VIEWPORT'
scene.display.shading.background_color = (0.07, 0.07, 0.09)
if scene.world is None:
    scene.world = bpy.data.worlds.new("World")
scene.world.color = (0.05, 0.05, 0.06)

cam_data = bpy.data.cameras.new("Cam")
cam_data.lens = 52
cam = bpy.data.objects.new("Cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

# Three-quarter view from the character's front-left: -Y is forward, so the
# camera has to sit on the -Y side to see the face and the punches.
target = Vector((0.0, 0.0, 1.05))
cam.location = Vector((2.9, -3.9, 1.85))
# to_track_quat is the dependable look-at; hand-rolled euler aiming put the
# camera somewhere the skeleton wasn't.
cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()

SHOTS = [
    ("idle", 0), ("idle", 24), ("idle", 48),
    ("walk", 0), ("walk", 6), ("walk", 12), ("walk", 18),
    ("run", 0), ("run", 4), ("run", 8), ("run", 12),
    ("windup", 12),
    ("attack_1", 0), ("attack_1", 3),
    ("attack_2", 4), ("attack_3", 3), ("attack_3", 7),
    ("lunge", 4), ("lunge", 8), ("lunge", 14), ("lunge", 19),
]

ad = arm.animation_data or arm.animation_data_create()
for clip, frame in SHOTS:
    act = bpy.data.actions.get(clip)
    if act is None:
        print("MISSING", clip)
        continue
    ad.action = act
    if hasattr(ad, "action_slot") and act.slots:
        try:
            ad.action_slot = act.slots[0]
        except Exception:
            pass
    scene.frame_set(frame)
    path = os.path.join(OUTDIR, "%s_%02d.png" % (clip, frame))
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("SHOT %s %d -> %s" % (clip, frame, path))
print("DONE")
