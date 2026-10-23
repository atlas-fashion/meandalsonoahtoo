"""Builds models/surgery/surgeon.glb, the surgery's surgeon (note 99).

    blender -b --factory-startup -P tools/build_surgeon.py
    godot --headless --import --path .

Sources (models/source/surgery_hf/): raw_surgeon.glb -- a gpt_image_2_5 picture
(ref_surgeon.png) made into a textured, auto-rigged character by Meshy on
Higgsfield (24-bone humanoid, 1.85 m) with the "Checkout_Gesture" clip (his work
at the console); raw_surgeon_alert.glb and raw_surgeon_die.glb -- the same
model rigged again by Meshy with "Alert_Quick_Turn_Right" and
"Fall_Dead_from_Abdominal_Injury". Same mesh, same rig, same bone names: their
clips are taken onto the first one's armature as NLA tracks named "work",
"alert" and "die" (surgery_control.gd plays them by name). The stray icosphere
Meshy ships is dropped; the maps are shrunk to TEX px and the metallic factor
set (Meshy's 1.0 renders leather as chrome in this dungeon).
"""

import bpy
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "models", "source", "surgery_hf")
OUT = os.path.join(ROOT, "models", "surgery", "surgeon.glb")
TEX = 1024
METAL = 0.1
CLIPS = (("raw_surgeon.glb", "work"), ("raw_surgeon_alert.glb", "alert"), ("raw_surgeon_die.glb", "die"))


def log(*a):
    print("[surgeon]", *a)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 24
    main_arm = None
    actions = {}
    for path, clip in CLIPS:
        before = set(bpy.data.objects)
        acts_before = set(bpy.data.actions)
        bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, path))
        new = [o for o in bpy.data.objects if o not in before]
        arm = next(o for o in new if o.type == 'ARMATURE')
        act = next(a for a in bpy.data.actions if a not in acts_before)
        act.name = clip
        act.use_fake_user = True
        actions[clip] = act
        if main_arm is None:
            main_arm = arm
            for o in new:
                if o.type == 'MESH' and o.name.startswith("Icosphere"):
                    bpy.data.objects.remove(o)
        else:
            for o in new:
                bpy.data.objects.remove(o)
        log("%s: %s, frames %s" % (path, clip, tuple(act.frame_range)))
    ad = main_arm.animation_data or main_arm.animation_data_create()
    ad.action = None
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    for clip in ("work", "alert", "die"):
        act = actions[clip]
        track = ad.nla_tracks.new()
        track.name = clip
        strip = track.strips.new(clip, int(act.frame_range[0]), act)
        try:
            strip.action_slot = act.slots[0]
        except Exception:
            pass
        track.mute = True
    for m in bpy.data.materials:
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == 'BSDF_PRINCIPLED':
                    n.inputs["Metallic"].default_value = METAL
    for img in bpy.data.images:
        if img.size[0] > TEX:
            img.scale(TEX, TEX)
    for o in bpy.data.objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True,
                              export_animation_mode='NLA_TRACKS', export_image_format='JPEG',
                              export_jpeg_quality=90, export_apply=False)
    log("wrote", OUT, "%.1f MB" % (os.path.getsize(OUT) / 1e6))


main()
