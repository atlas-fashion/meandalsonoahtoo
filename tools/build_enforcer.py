"""Builds models/enforcer.glb from the user's rigged, animated enforcer.

    blender -b models/source/enforcer/ENFORCER_BAKED.blend -P tools/build_enforcer.py
    godot --headless --import --path .

The source (models/source/enforcer/ENFORCER_BAKED.blend, from the user) is a
rusty Tripo mech on a 16-bone rig with four BAKED actions on NLA tracks --
WALK_BAKED (120 frames), BEAM_BAKED (47, the gun arm raised onto the shield
arm), BEAM_RECOIL_BAKED (20, the cannon kicking as it fires) and SWIPE_1_BAKED
(70, the shield arm swung) -- at 60 fps (second delivery, 2026-10-15). The
file also carries the unbaked actions they were made from (WALK, BEAM,
BEAM_RECOIL, SWIPE_1; BEAM_RECOIL on an UNMUTED NLA track): every track and
action not ending in _BAKED is removed before export -- only the baked ones
are used (user).

Added here, so the game does not have to guess where things are on the mesh:
  * empties parented to bones, which Godot imports as BoneAttachment3Ds:
    "EyeL" / "EyeR" (HEAD) in the middle of each eye, "Muzzle" (ARM_R) at the
    mouth of the cannon, pointing out of it, "Shield" (ARM_L) on the shield's
    face;
  * the chest crystal's material (cyan emission) renamed "EnforcerCrystal".
Measurements are printed: the eyes' radius, the muzzle, and the swipe's
fastest frame (where the shield strikes), which enforcer.gd uses.
"""
import os
import bpy
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "models", "enforcer.glb")


def log(*a):
    print("[enforcer]", *a)


def world_points(ob):
    m = ob.matrix_world
    return np.array([tuple(m @ v.co) for v in ob.data.vertices])


def bone_empty(name, arm, bone, at_world, look_world=None, size=0.1):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = size
    bpy.context.scene.collection.objects.link(e)
    e.parent = arm
    e.parent_type = "BONE"
    e.parent_bone = bone
    # Place in world space, then keep that under the bone.
    xf = Matrix.Translation(Vector(at_world))
    if look_world is not None:
        # Empty's -Z along the look direction (Godot's forward once converted:
        # Blender -Z stays -Z for an object's local axes? Godot gets Y-up; the
        # exporter converts, so "forward" is checked in the game instead).
        q = Vector(look_world).to_track_quat("-Z", "Z")
        xf = xf @ q.to_matrix().to_4x4()
    bpy.context.view_layer.update()
    e.matrix_world = xf
    return e


## One mesh, one texture. As delivered the model is 12 skinned meshes with 37
## materials (each Tripo part has its own texture per piece): ~37 draw calls an
## enforcer, every one again in each torch's shadow pass, and 12 skins to update
## -- with 57 of them in a level the bench fell 70 -> 64 fps, worst p99 28 -> 41
## ms. Here every part is joined into one mesh and its colour baked (Cycles,
## DIFFUSE colour only) into one ATLAS_PX atlas on a fresh UV map; the crystal's
## faces keep their own emissive material. Two surfaces, one skin.
ATLAS_PX = 2048


def atlas(arm):
    parts = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
        # Every part's own UVs under one name, so they survive the join.
        if o.data.uv_layers:
            o.data.uv_layers[0].name = "Source"
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "EnforcerBody"
    # Textures read the source UVs explicitly, whatever the active map is.
    for m in ob.data.materials:
        if m is None or not m.use_nodes:
            continue
        nt = m.node_tree
        uv = nt.nodes.new("ShaderNodeUVMap")
        uv.uv_map = "Source"
        for n in nt.nodes:
            if n.type == "TEX_IMAGE":
                nt.links.new(uv.outputs["UV"], n.inputs["Vector"])
    # The atlas UVs.
    target = ob.data.uv_layers.new(name="Atlas")
    ob.data.uv_layers.active = target
    target.active_render = True
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new("enforcer_atlas", ATLAS_PX, ATLAS_PX)
    for m in ob.data.materials:
        if m is None or not m.use_nodes:
            continue
        node = m.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = img
        m.node_tree.nodes.active = node
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 4
    sc.cycles.device = "CPU"
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.render.bake.use_pass_color = True
    sc.render.bake.margin = 6
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_clear=True)
    img.filepath_raw = os.path.join(HERE, "models", "source", "enforcer", "enforcer_atlas.png")
    img.file_format = "PNG"
    img.save()
    img.pack()
    # One material for everything but the crystal.
    body = bpy.data.materials.new("EnforcerBody")
    body.use_nodes = True
    nt = body.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "Atlas"
    nt.links.new(uv.outputs["UV"], tex.inputs["Vector"])
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.75
    bsdf.inputs["Metallic"].default_value = 0.3
    crystal = bpy.data.materials["EnforcerCrystal"]
    crystal_slot = [i for i, m in enumerate(ob.data.materials) if m == crystal][0]
    is_crystal = [p.material_index == crystal_slot for p in ob.data.polygons]
    ob.data.materials.clear()
    ob.data.materials.append(body)
    ob.data.materials.append(crystal)
    for p, c in zip(ob.data.polygons, is_crystal):
        p.material_index = 1 if c else 0
    ob.data.uv_layers.remove(ob.data.uv_layers["Source"])
    log("joined into one mesh: %d faces, 2 materials, atlas %d px" % (len(ob.data.polygons), ATLAS_PX))


def main():
    sc = bpy.context.scene
    arm = bpy.data.objects["Armature"]
    # The file may have been saved in pose or edit mode; the operators below
    # (join, smart project, bake) need object mode.
    if bpy.context.mode != "OBJECT":
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="OBJECT")
    # Rest pose for every measurement.
    arm.animation_data.action = None
    for t in arm.animation_data.nla_tracks:
        t.mute = True
    sc.frame_set(1)
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()

    # Only the baked actions go out.
    for ob in bpy.data.objects:
        if ob.type != "ARMATURE" and ob.animation_data is not None:
            ob.animation_data_clear()
    ad = arm.animation_data
    for t in list(ad.nla_tracks):
        if not all(s.action is not None and s.action.name.endswith("_BAKED") for s in t.strips):
            ad.nla_tracks.remove(t)
    for a in list(bpy.data.actions):
        if not a.name.endswith("_BAKED"):
            bpy.data.actions.remove(a)
    log("tracks kept:", [t.name for t in ad.nla_tracks])

    for m in bpy.data.materials:
        if m.name == "Material.001":
            m.name = "EnforcerCrystal"

    # Eyes: the two front-most bulges on the head ball (the face looks along -Y).
    head = bpy.data.objects["rusty spherical robot 3d model"]
    p = world_points(head)
    front = p[:, 1].min()
    lens = p[p[:, 1] < front + 0.06]
    eyes = []
    for side in (-1.0, 1.0):
        s = lens[np.sign(lens[:, 0] - p[:, 0].mean()) == side]
        c = s.mean(axis=0)
        r = float(np.percentile(np.linalg.norm(s[:, [0, 2]] - c[[0, 2]], axis=1), 90))
        eyes.append((side, c, r))
        log("eye %+.0f at (%.3f, %.3f, %.3f), radius %.3f, %d verts" % (side, c[0], c[1], c[2], r, len(s)))
    # The model's own left is +X (it faces -Y).
    for side, c, r in eyes:
        bone_empty("EyeL" if side > 0 else "EyeR", arm, "HEAD", c, size=r)

    # Muzzle: the end of the cannon (tripo_part_30, on ARM_R) furthest along
    # the arm bone, the middle of the vertices there.
    pb = arm.pose.bones["ARM_R"]
    b_head = arm.matrix_world @ pb.head
    b_tail = arm.matrix_world @ pb.tail
    axis = (b_tail - b_head).normalized()
    gun = world_points(bpy.data.objects["tripo_part_30"])
    proj = (gun - np.array(b_head)) @ np.array(axis)
    tip = proj.max()
    mouth = gun[proj > tip - 0.05].mean(axis=0)
    log("muzzle at (%.3f, %.3f, %.3f), %.3f along ARM_R" % (mouth[0], mouth[1], mouth[2], tip))
    bone_empty("Muzzle", arm, "ARM_R", mouth, look_world=axis, size=0.15)

    # Shield: tripo_part_10 on ARM_L, its centre.
    shield = world_points(bpy.data.objects["tripo_part_10"])
    sh = shield.mean(axis=0)
    log("shield at (%.3f, %.3f, %.3f)" % tuple(sh))
    bone_empty("Shield", arm, "ARM_L", sh, size=0.3)

    # Back to the posed rig, and the swipe sampled: the shield's speed per frame.
    arm.data.pose_position = "POSE"
    for t in arm.animation_data.nla_tracks:
        t.mute = True
    for name, track_action in (("SWIPE_1_BAKED", "SWIPE_1_BAKED"), ("BEAM_BAKED", "BEAM_BAKED"),
                              ("BEAM_RECOIL_BAKED", "BEAM_RECOIL_BAKED")):
        act = bpy.data.actions[track_action]
        arm.animation_data.action = act
        e = bpy.data.objects["Shield" if name.startswith("SWIPE") else "Muzzle"]
        last = None
        speeds = []
        rows = []
        for f in range(int(act.frame_range[0]), int(act.frame_range[1]) + 1):
            sc.frame_set(f)
            bpy.context.view_layer.update()
            w = e.matrix_world.translation.copy()
            if last is not None:
                speeds.append(((w - last).length * sc.render.fps, f))
            rows.append((f, w))
            last = w
        top = sorted(speeds, reverse=True)[:5]
        log("%s: fastest frames %s" % (name, [(f, round(v, 2)) for v, f in top]))
        for f, w in rows[:: max(1, len(rows) // 12)]:
            log("  %s f%3d at (%.2f, %.2f, %.2f)" % (name, f, w.x, w.y, w.z))
        log("  %s first (%.3f, %.3f, %.3f) last (%.3f, %.3f, %.3f)" % (name, *rows[0][1], *rows[-1][1]))
    arm.animation_data.action = None
    for t in arm.animation_data.nla_tracks:
        t.mute = False
    sc.frame_set(1)
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    atlas(arm)
    arm.data.pose_position = "POSE"

    bpy.ops.object.select_all(action="DESELECT")
    for ob in bpy.data.objects:
        ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format="GLB",
                              export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_image_format="JPEG", export_jpeg_quality=90,
                              export_def_bones=False)
    log("wrote", OUT, "%.1f MB" % (os.path.getsize(OUT) / 1e6))


main()
