"""Builds models/decrepit.glb from the user's rigged, animated decrepit enforcer.

    blender -b models/source/enforcer/PUTRID_ENFORCER_BAKED.blend -P tools/build_decrepit.py
    godot --headless --import --path .

The source (from the user; second delivery 2026-10-17) is a hunched, one-armed
Tripo mech on a 13-bone rig -- TORSO (root), HEAD, SHOULDER_L > ARM_L (the arm IS
a great pointed shield), THIGH/CALF L and R, and IK roots FOOT_L.001 / FOOT_R.001
and ARM_L.001 -- with five BAKED actions on NLA tracks at 60 fps:
  CRAWL_BAKED (49 frames, a loping in-place crawl, the shield swinging) -- the
      wander and the chase;
  SWIPE_BAKED (45, the shield drawn back and swung across the front as it
      lunges ~3 m) -- the close attack;
  JUMP_BAKED (75, a leap that brings the shield's point down into the floor
      2.2 m on) -- the jump slash;
  DROPKICK_BAKED (103, a dive, a flip and a kick with both feet ~3 m on) -- the
      long-range leap;
  DASH_BAKED (21, from a crouch into a wide lunge, the shield thrust out; in
      place) -- the dash stab.
CRAWL_BAKED and DASH_BAKED arrive as "CRAWL_BAKED.001" / "DASH_BAKED.001"
(Blender's duplicate suffix); the suffix is dropped here. The file also carries
the unbaked actions they were made from (some on UNMUTED tracks) and an empty
STABS: every track and action not ending in _BAKED is removed. Only the baked
ones go out. (The first delivery's STABS_BAKED shield slam is gone.)

ROOT MOTION is taken out of the clips here: SWIPE, JUMP and DROPKICK carry the
body forward (TORSO and the foot roots together), which in the game would leave the
model metres ahead of its collision body and snap it back on the next clip. Per
frame the TORSO's horizontal offset from frame 1 is subtracted from the three
parentless bones (TORSO, FOOT_L.001, FOOT_R.001; everything else hangs off
them), so every clip plays in place, and the offsets are printed as a table
("root ...") that decrepit.gd moves the body along.

Also measured and printed for decrepit.gd: the crawl's ground speed (its planted
feet), and per attack clip the shield's point and the feet, frame by frame (in
place: forward / up), for the contact frames -- the swipe's and the dash's
furthest reach, the jump's point at its lowest, the dropkick's feet furthest
forward. Added: empties parented to bones
(Godot imports them as BoneAttachment3Ds): "ShieldTip" (ARM_L) at the shield's
point, "EyeL" / "EyeR" (HEAD) at the mask's two pale eyes. The ten parts are
joined into one mesh with one baked colour atlas (as the enforcer's: one draw,
one skin).
"""
import os
import bpy
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "models", "decrepit.glb")
ATLAS_PX = 2048
ROOTS = ("TORSO", "FOOT_L.001", "FOOT_R.001")
MOVING = ("SWIPE_BAKED", "JUMP_BAKED", "DROPKICK_BAKED")
CLIPS = (("CRAWL_BAKED", True), ("SWIPE_BAKED", False), ("JUMP_BAKED", False),
         ("DROPKICK_BAKED", False), ("DASH_BAKED", False))
## Clips whose knees are NOT eased: the dropkick somersaults (frames 21-30 the
## whole body spins, the shield and calves moving 2-3 units a frame), and the
## flip detector -- a bend angle measured against a fixed forward -- reads the
## spin itself as a dozen knee flips. Its legs are left exactly as authored.
NO_KNEE_EASE = ("DROPKICK_BAKED",)


def log(*a):
    print("[decrepit]", *a)


def world_points(ob):
    m = ob.matrix_world
    return np.array([tuple(m @ v.co) for v in ob.data.vertices])


def bone_empty(name, arm, bone, at_world, size=0.1):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = size
    bpy.context.scene.collection.objects.link(e)
    e.parent = arm
    e.parent_type = "BONE"
    e.parent_bone = bone
    bpy.context.view_layer.update()
    e.matrix_world = Matrix.Translation(Vector(at_world))
    return e


def fcurves(action):
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.extend(cb.fcurves)
    return out


def use_action(arm, action):
    ad = arm.animation_data
    ad.action = action
    try:
        ad.action_slot = action.slots[0]
    except Exception:
        pass


def torso_world(arm):
    return arm.matrix_world @ arm.pose.bones["TORSO"].head


## The root motion out of `action`: its TORSO's horizontal offset from the first
## frame, per frame, removed from the parentless bones' location keys.
def strip_root(arm, action):
    sc = bpy.context.scene
    use_action(arm, action)
    f0, f1 = int(action.frame_range[0]), int(action.frame_range[1])
    sc.frame_set(f0)
    start = torso_world(arm).copy()
    offs = {}
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        d = torso_world(arm) - start
        offs[f] = Vector((d.x, d.y, 0.0))
    # World offset -> each root bone's own location axes.
    to_local = {}
    for name in ROOTS:
        b = arm.data.bones[name]
        to_local[name] = (arm.matrix_world.to_3x3() @ b.matrix_local.to_3x3()).inverted()
    curves = fcurves(action)
    touched = 0
    for fc in curves:
        for name in ROOTS:
            if fc.data_path != 'pose.bones["%s"].location' % name:
                continue
            for kp in fc.keyframe_points:
                f = kp.co[0]
                lo = max(f0, min(f1, int(np.floor(f))))
                hi = max(f0, min(f1, lo + 1))
                t = f - lo
                d = offs[lo].lerp(offs[hi], t)
                local = to_local[name] @ d
                dv = local[fc.array_index]
                kp.co[1] -= dv
                kp.handle_left[1] -= dv
                kp.handle_right[1] -= dv
                touched += 1
            fc.update()
    # Check: the torso should now stay over its start.
    worst = 0.0
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        d = torso_world(arm) - start
        worst = max(worst, Vector((d.x, d.y)).length)
    log("%s: root stripped (%d keys), torso now within %.4f of its start" % (action.name, touched, worst))
    # The table: (seconds, forward = -y, left = +x) every 2 frames, last frame too.
    fps = sc.render.fps
    rows = []
    for f in list(range(f0, f1 + 1, 2)) + ([f1] if (f1 - f0) % 2 else []):
        o = offs[f]
        rows.append("[%.4f, %.3f, %.3f]" % ((f - f0) / fps, -o.y, o.x))
    log("root %s %d frames: [%s]" % (action.name, f1 - f0 + 1, ", ".join(rows)))


def apply_smoothing(parts):
    for o in parts:
        bpy.context.view_layer.objects.active = o
        for m in list(o.modifiers):
            if m.type == "NODES":
                bpy.ops.object.modifier_move_to_index(modifier=m.name, index=0)
                bpy.ops.object.modifier_apply(modifier=m.name)


## The mask's eyes: its pale spheres, picked out by sampling the mask's own
## colour texture at every vertex's UV.
def find_eyes(head):
    me = head.data
    mat = me.materials[0]
    img = None
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image is not None:
            img = n.image
    if img is None or not me.uv_layers:
        log("eyes: no texture on the mask")
        return []
    w, h = img.size
    px = np.array(img.pixels[:]).reshape(h, w, 4)
    uv = me.uv_layers[0].data
    lum = np.zeros(len(me.vertices))
    for loop in me.loops:
        u, v = uv[loop.index].uv
        x = int((u % 1.0) * (w - 1))
        y = int((v % 1.0) * (h - 1))
        c = px[y, x, :3]
        lum[loop.vertex_index] = max(lum[loop.vertex_index], float(c @ np.array([0.2126, 0.7152, 0.0722])))
    pts = world_points(head)
    centre = pts.mean(axis=0)
    eyes = []
    for thresh in (0.75, 0.65, 0.55):
        pick = (lum > thresh) & (pts[:, 1] < centre[1])
        if pick.sum() < 8:
            continue
        p = pts[pick]
        eyes = []
        for side in (1.0, -1.0):
            s = p[np.sign(p[:, 0] - centre[0]) == side]
            if len(s) < 4:
                continue
            c = s.mean(axis=0)
            r = float(np.percentile(np.linalg.norm(s - c, axis=1), 85))
            eyes.append((side, c, r, len(s)))
        if len(eyes) == 2:
            log("eyes at threshold %.2f: %s" % (thresh, [(e[0], tuple(round(x, 3) for x in e[1]), round(e[2], 3), e[3]) for e in eyes]))
            return eyes
    log("eyes: not found")
    return []


def atlas(parts):
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
        if o.data.uv_layers:
            o.data.uv_layers[0].name = "Source"
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "DecrepitBody"
    for m in ob.data.materials:
        if m is None or not m.use_nodes:
            continue
        nt = m.node_tree
        uv = nt.nodes.new("ShaderNodeUVMap")
        uv.uv_map = "Source"
        for n in nt.nodes:
            if n.type == "TEX_IMAGE":
                nt.links.new(uv.outputs["UV"], n.inputs["Vector"])
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
    # Tripo marks every part fully METALLIC, and a metal has no diffuse colour:
    # the colour bake came out pure black until the metallic was taken off.
    for m in ob.data.materials:
        if m is None or not m.use_nodes:
            continue
        for bsdf in [n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"]:
            for l in list(m.node_tree.links):
                if l.to_node == bsdf and l.to_socket.name == "Metallic":
                    m.node_tree.links.remove(l)
            bsdf.inputs["Metallic"].default_value = 0.0
    img = bpy.data.images.new("decrepit_atlas", ATLAS_PX, ATLAS_PX)
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
    filled = (np.array(img.pixels[:]).reshape(-1, 4)[:, :3].sum(1) > 0.004).mean()
    log("atlas baked: %.0f%% of it filled" % (filled * 100.0))
    img.filepath_raw = os.path.join(HERE, "models", "source", "enforcer", "decrepit_atlas.png")
    img.file_format = "PNG"
    img.save()
    img.pack()
    body = bpy.data.materials.new("DecrepitBody")
    body.use_nodes = True
    nt = body.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "Atlas"
    nt.links.new(uv.outputs["UV"], tex.inputs["Vector"])
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.7
    bsdf.inputs["Metallic"].default_value = 0.35
    ob.data.materials.clear()
    ob.data.materials.append(body)
    for p in ob.data.polygons:
        p.material_index = 0
    ob.data.uv_layers.remove(ob.data.uv_layers["Source"])
    log("joined into one mesh: %d faces, 1 material, atlas %d px" % (len(ob.data.polygons), ATLAS_PX))
    return ob


def track(arm, action, empty, frames=None):
    sc = bpy.context.scene
    use_action(arm, action)
    rows = []
    f0, f1 = int(action.frame_range[0]), int(action.frame_range[1])
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        bpy.context.view_layer.update()
        rows.append((f, empty.matrix_world.translation.copy()))
    return rows




## --- Knee flips (found measuring the imported clips, 2026-10-15) --------------------
##
## The baked IK lets the knees FLIP: the bend swings to the other side of the
## leg in two or three frames (STABS f17-18, JUMP f38-40), and the crawl's last
## frame has both knees on the other side from its first, so it popped every
## loop. With the IK constraints dropped (the baked keys ARE the solved pose),
## each knee's bend direction is measured per frame as an angle about its
## hip-foot line; where it whips round faster than FLIP_DEG a frame, the angle is
## eased across the flip over FLIP_WINDOW frames either side, and the thigh and
## calf are re-solved so the foot stays exactly where the clip has it. The crawl
## is treated as a cycle (its seam is a flip like any other), then its last frame
## is set to its first.
FLIP_DEG = 18.0
FLIP_WINDOW = 7
LEGS = (("THIGH_L", "CALF_L"), ("THIGH_R", "CALF_R"))


def drop_constraints(arm):
    n = 0
    for pb in arm.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
            n += 1
    log("constraints removed: %d (the baked keys carry the solved pose)" % n)


def _leg_state(arm, thigh, calf):
    t = arm.pose.bones[thigh]
    c = arm.pose.bones[calf]
    return Vector(t.head), Vector(c.head), Vector(c.tail)


def _frame_axes(hip, foot):
    u = (foot - hip).normalized()
    ref = Vector((0.0, -1.0, 0.0))
    ref = ref - u * ref.dot(u)
    if ref.length < 1e-4:
        ref = Vector((0.0, 0.0, 1.0)) - u * u.z
    ref.normalize()
    return u, ref, u.cross(ref)


def _phi(hip, knee, foot):
    u, ref, side = _frame_axes(hip, foot)
    k = knee - hip
    n = k - u * k.dot(u)
    return float(np.arctan2(n.dot(side), n.dot(ref)))


def _swing(a, b):
    a = a.normalized()
    b = b.normalized()
    axis = a.cross(b)
    s = axis.length
    if s < 1e-7:
        return Matrix.Identity(3)
    return Matrix.Rotation(float(np.arctan2(s, a.dot(b))), 3, axis / s)


def _key(pb, f):
    if pb.rotation_mode == "QUATERNION":
        pb.keyframe_insert("rotation_quaternion", frame=f)
    else:
        pb.keyframe_insert("rotation_euler", frame=f)


def _eased(un, flips):
    target = un.copy()
    for i in flips:
        a = max(0, i - FLIP_WINDOW)
        b = min(len(un) - 1, i + 1 + FLIP_WINDOW)
        for j in range(a, b + 1):
            s = (j - a) / float(b - a)
            s = s * s * (3.0 - 2.0 * s)
            target[j] = un[a] + (un[b] - un[a]) * s
    return target


def smooth_knees(arm, action, cyclic):
    sc = bpy.context.scene
    use_action(arm, action)
    f0, f1 = int(action.frame_range[0]), int(action.frame_range[1])
    frames = list(range(f0, f1 + 1))
    # A cycle's last frame repeats its first: the cycle is the frames before it.
    n = len(frames) - 1 if cyclic else len(frames)
    for thigh, calf in LEGS:
        ph = []
        for f in frames[:n]:
            sc.frame_set(f)
            hip, knee, foot = _leg_state(arm, thigh, calf)
            ph.append(_phi(hip, knee, foot))
        ph = np.array(ph)
        if cyclic:
            # Three laps unwrapped together: the middle lap sees its seam as an
            # ordinary step from the lap before and into the lap after.
            un = np.unwrap(np.concatenate([ph, ph, ph]))
            d = np.abs(np.diff(un))
            flips = [i for i in range(len(d)) if np.degrees(d[i]) > FLIP_DEG]
            target = _eased(un, flips)[n:2 * n]
            base = un[n:2 * n]
            nflips = len([i for i in flips if n - 1 <= i < 2 * n])
        else:
            un = np.unwrap(ph)
            d = np.abs(np.diff(un))
            flips = [i for i in range(len(d)) if np.degrees(d[i]) > FLIP_DEG]
            target = _eased(un, flips)
            base = un
            nflips = len(flips)
        if nflips == 0:
            log("%s %s: no knee flips" % (action.name, thigh))
            continue
        changed = 0
        for idx in range(n):
            f = frames[idx]
            want = float(target[idx])
            if abs(want - float(base[idx])) < np.radians(0.5):
                continue
            sc.frame_set(f)
            bpy.context.view_layer.update()
            hip, knee, foot = _leg_state(arm, thigh, calf)
            u, ref, side = _frame_axes(hip, foot)
            la = (knee - hip).length
            lb = (foot - knee).length
            dd = (foot - hip).length
            ca = max(-1.0, min(1.0, (la * la + dd * dd - lb * lb) / (2.0 * la * dd)))
            wdir = ref * float(np.cos(want)) + side * float(np.sin(want))
            knee_new = hip + u * (la * ca) + wdir * (la * float(np.sqrt(1.0 - ca * ca)))
            tb = arm.pose.bones[thigh]
            cb = arm.pose.bones[calf]
            m = tb.matrix.copy()
            rot = (_swing(knee - hip, knee_new - hip) @ m.to_3x3()).to_4x4()
            rot.translation = m.translation
            tb.matrix = rot
            bpy.context.view_layer.update()
            k2 = Vector(cb.head)
            mc = cb.matrix.copy()
            rc = (_swing(Vector(cb.tail) - k2, foot - k2) @ mc.to_3x3()).to_4x4()
            rc.translation = mc.translation
            cb.matrix = rc
            bpy.context.view_layer.update()
            _key(tb, f)
            _key(cb, f)
            changed += 1
        log("%s %s: %d flip(s) eased, %d frames re-solved" % (action.name, thigh, nflips, changed))
    if cyclic:
        # The last frame IS the first, for every channel.
        for fc in fcurves(action):
            v = fc.evaluate(f0)
            fc.keyframe_points.insert(f1, v, options={"REPLACE"})
            fc.update()


## --- One-frame pops (found 2026-10-17) -------------------------------------------
##
## DROPKICK_BAKED's shield arm turns ~150 degrees between frames 4 and 5 (its tip
## 4.24 units in one frame, against ~0.25 either side) -- a snap baked into the
## clip that no blending can hide, three frames after the clip starts. A bone
## whose rotation steps more than POP_DEG in one frame AND more than POP_RATIO
## times both neighbouring steps is a pop (an isolated spike, not fast motion:
## the dropkick's somersault turns every frame for ten and is left alone). Each
## is spread over POP_WINDOW frames either side: the window re-keyed as an eased
## slerp between its ends.
POP_DEG = 35.0
POP_RATIO = 3.0
POP_WINDOW = 3


def _local_q(pb):
    if pb.rotation_mode == "QUATERNION":
        return pb.rotation_quaternion.copy()
    return pb.rotation_euler.to_quaternion()


def _set_local_q(pb, q):
    if pb.rotation_mode == "QUATERNION":
        pb.rotation_quaternion = q
    else:
        pb.rotation_euler = q.to_euler(pb.rotation_mode)


def depop(arm, action):
    sc = bpy.context.scene
    use_action(arm, action)
    f0, f1 = int(action.frame_range[0]), int(action.frame_range[1])
    frames = list(range(f0, f1 + 1))
    fixed = []
    for pb in arm.pose.bones:
        qs = []
        for f in frames:
            sc.frame_set(f)
            qs.append(_local_q(pb))
        steps = [0.0] + [float(np.degrees(qs[i - 1].rotation_difference(qs[i]).angle)) for i in range(1, len(qs))]
        for i in range(1, len(qs)):
            prev_s = steps[i - 1] if i - 1 >= 1 else 0.0
            next_s = steps[i + 1] if i + 1 < len(steps) else 0.0
            if steps[i] > POP_DEG and steps[i] > POP_RATIO * max(prev_s, next_s, 1.0):
                a = max(0, i - 1 - POP_WINDOW)
                b = min(len(qs) - 1, i + POP_WINDOW)
                qa, qb = qs[a], qs[b]
                for j in range(a + 1, b):
                    s = (j - a) / float(b - a)
                    s = s * s * (3.0 - 2.0 * s)
                    _set_local_q(pb, qa.slerp(qb, s))
                    _key(pb, frames[j])
                fixed.append("%s f%d (%.0f deg in a frame; frames %d-%d eased)" % (pb.name, frames[i], steps[i], frames[a], frames[b]))
    log("%s pops: %s" % (action.name, fixed if fixed else "none"))


def knee_report(arm, action, cyclic):
    sc = bpy.context.scene
    use_action(arm, action)
    f0, f1 = int(action.frame_range[0]), int(action.frame_range[1])
    worst = 0.0
    at = None
    prev = None
    seq = list(range(f0, f1 + 1)) + ([f0 + 1] if cyclic else [])
    scale = arm.matrix_world.to_scale().x
    for f in seq:
        sc.frame_set(f)
        bpy.context.view_layer.update()
        ks = [Vector(arm.pose.bones[c].head) for _, c in LEGS]
        if prev is not None:
            for a, b in zip(ks, prev):
                s = (a - b).length * scale
                if s > worst:
                    worst = s
                    at = f
        prev = ks
    log("%s: worst knee step %.3f a frame (at f%s)%s" % (action.name, worst, at, ", the loop included" if cyclic else ""))


def main():
    sc = bpy.context.scene
    arm = bpy.data.objects["Armature"]
    if bpy.context.mode != "OBJECT":
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="OBJECT")
    for o in list(bpy.data.objects):
        if o.type == "LIGHT" or o.type == "CAMERA":
            bpy.data.objects.remove(o)
    ad = arm.animation_data
    ad.action = None
    for t in ad.nla_tracks:
        t.mute = True

    # "X_BAKED.001" (a duplicate's suffix) is X_BAKED.
    import re
    for a in list(bpy.data.actions):
        m = re.match(r"^(.*_BAKED)\.\d+$", a.name)
        if m and m.group(1) not in bpy.data.actions:
            log("renamed", a.name, "->", m.group(1))
            a.name = m.group(1)
    for t in ad.nla_tracks:
        m = re.match(r"^(.*_BAKED)\.\d+$", t.name)
        if m:
            t.name = m.group(1)
        for s in t.strips:
            m = re.match(r"^(.*_BAKED)\.\d+$", s.name)
            if m:
                s.name = m.group(1)

    # Only the baked actions go out.
    for ob in bpy.data.objects:
        if ob.type != "ARMATURE" and ob.animation_data is not None:
            ob.animation_data_clear()
    for t in list(ad.nla_tracks):
        if not all(s.action is not None and s.action.name.endswith("_BAKED") for s in t.strips):
            ad.nla_tracks.remove(t)
    for a in list(bpy.data.actions):
        if not a.name.endswith("_BAKED"):
            bpy.data.actions.remove(a)
    log("tracks kept:", [t.name for t in ad.nla_tracks], "fps", sc.render.fps)
    missing = [n for n, _ in CLIPS if n not in bpy.data.actions]
    assert not missing, "missing baked clips: %s" % missing

    # Root motion out of the clips that travel.
    arm.data.pose_position = "POSE"
    for name in MOVING:
        strip_root(arm, bpy.data.actions[name])
    # The crawl should already be in place.
    a = bpy.data.actions["CRAWL_BAKED"]
    use_action(arm, a)
    sc.frame_set(int(a.frame_range[0]))
    s0 = torso_world(arm).copy()
    drift = 0.0
    for f in range(int(a.frame_range[0]), int(a.frame_range[1]) + 1):
        sc.frame_set(f)
        drift = max(drift, Vector(((torso_world(arm) - s0).x, (torso_world(arm) - s0).y)).length)
    log("CRAWL_BAKED torso drift %.4f" % drift)

    # Knee flips out of every clip (constraints first: the keys are the pose).
    drop_constraints(arm)
    for name, cyc in CLIPS:
        knee_report(arm, bpy.data.actions[name], cyc)
        if name in NO_KNEE_EASE:
            log("%s: knees left as authored" % name)
            continue
        smooth_knees(arm, bpy.data.actions[name], cyc)
        knee_report(arm, bpy.data.actions[name], cyc)
    for name, _ in CLIPS:
        depop(arm, bpy.data.actions[name])
    a = bpy.data.actions["CRAWL_BAKED"]
    use_action(arm, a)

    # Ground speed of the crawl: its feet while planted (lowest), sliding back.
    speeds = []
    lows = []
    for foot in ("FOOT_L.001", "FOOT_R.001"):
        rows = []
        for f in range(int(a.frame_range[0]), int(a.frame_range[1]) + 1):
            sc.frame_set(f)
            rows.append(arm.matrix_world @ arm.pose.bones[foot].head)
        z = np.array([r.z for r in rows])
        low = z.min()
        lows.append(low)
        for i in range(1, len(rows)):
            if rows[i].z < low + 0.04 and rows[i - 1].z < low + 0.04:
                speeds.append((rows[i] - rows[i - 1]).length * sc.render.fps)
    log("crawl ground speed (planted feet) %.3f m/s at the authored size, %d samples; feet low %s" % (
        float(np.median(speeds)) if speeds else -1.0, len(speeds), [round(l, 3) for l in lows]))

    # Rest pose for the markers and the atlas.
    ad.action = None
    sc.frame_set(1)
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    parts = [o for o in bpy.data.objects if o.type == "MESH"]
    allp = np.concatenate([world_points(o) for o in parts])
    log("rest bounds min %s max %s" % (tuple(np.round(allp.min(0), 3)), tuple(np.round(allp.max(0), 3))))
    head = bpy.data.objects["rusty steampunk spherical mask 3d model"]
    eyes = find_eyes(head)
    for side, c, r, n in eyes:
        # The model's own left is +X (it faces -Y).
        bone_empty("EyeL" if side > 0 else "EyeR", arm, "HEAD", c, size=r)
    apply_smoothing(parts)
    body = atlas(parts)

    # The shield's point: the vertices skinned mainly to ARM_L, furthest along it.
    vg = body.vertex_groups.get("ARM_L")
    pb = arm.data.bones["ARM_L"]
    b_head = arm.matrix_world @ pb.head_local
    b_tail = arm.matrix_world @ pb.tail_local
    axis = (b_tail - b_head).normalized()
    pts = world_points(body)
    own = []
    for v in body.data.vertices:
        for g in v.groups:
            if vg is not None and g.group == vg.index and g.weight > 0.5:
                own.append(v.index)
    sh = pts[own]
    proj = (sh - np.array(b_head)) @ np.array(axis)
    tip = sh[proj > proj.max() - 0.08].mean(axis=0)
    log("shield: %d verts on ARM_L, point %.3f along the arm at (%.3f, %.3f, %.3f)" % (len(own), proj.max(), *tip))
    bone_empty("ShieldTip", arm, "ARM_L", tip, size=0.15)
    # The chest, for the crystal (decrepit.gd): where a ray from in front meets
    # the TORSO's own plating -- only faces skinned to it, so the shield arm in
    # front cannot catch the ray -- just above the torso bone's root: in the rest
    # pose the mask covers it from z 3.28 up, the chest is the plating under that.
    tg = body.vertex_groups.get("TORSO")
    tv = set()
    for v in body.data.vertices:
        for g in v.groups:
            if tg is not None and g.group == tg.index and g.weight > 0.5:
                tv.add(v.index)
    mw = body.matrix_world
    verts = [mw @ v.co for v in body.data.vertices]
    polys = [list(p.vertices) for p in body.data.polygons if all(i in tv for i in p.vertices)]
    bvh = BVHTree.FromPolygons(verts, polys)
    tb = arm.data.bones["TORSO"]
    t_head = arm.matrix_world @ tb.head_local
    t_tail = arm.matrix_world @ tb.tail_local
    aim = t_head.lerp(t_tail, 0.05)
    hit = bvh.ray_cast(aim + Vector((0.0, -6.0, 0.0)), Vector((0.0, 1.0, 0.0)))
    if hit[0] is not None:
        at, normal = hit[0], hit[1]
        if normal.y > 0.0:
            normal = -normal
        log("chest at (%.3f, %.3f, %.3f), facing (%.2f, %.2f, %.2f), %d torso faces" % (*at, *normal, len(polys)))
        bone_empty("Chest", arm, "TORSO", at, size=0.1)
        bone_empty("ChestOut", arm, "TORSO", at + normal * 0.3, size=0.05)
    else:
        log("chest: the ray missed the torso")
    arm.data.pose_position = "POSE"

    # Contacts, in place (the root is out): per frame the shield's point and
    # the lower foot, forward (-y) and up (z) from the body's start, in authored
    # units. decrepit.gd's *_CONTACT / *_TIP / *_ROOT_AT_HIT come from these.
    e = bpy.data.objects["ShieldTip"]
    for name, _ in CLIPS[1:]:
        act = bpy.data.actions[name]
        use_action(arm, act)
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
        sc.frame_set(f0)
        base = torso_world(arm).copy()
        rows = []
        for f in range(f0, f1 + 1):
            sc.frame_set(f)
            bpy.context.view_layer.update()
            tip = e.matrix_world.translation
            feet = [arm.matrix_world @ arm.pose.bones[b].head for b in ("FOOT_L", "FOOT_R")]
            fw = max(feet, key=lambda v: -v.y)
            rows.append((f, -(tip.y - base.y), tip.z, -(fw.y - base.y), fw.z))
        tipf = max(rows, key=lambda r: r[1])
        low = min((r for r in rows if r[0] > f0 + 10), key=lambda r: r[2])
        footf = max(rows, key=lambda r: r[3])
        log("%s contacts: tip furthest fwd %.3f at f%d (t %.3f); tip lowest z %.3f at f%d (t %.3f, fwd %.3f); foot furthest fwd %.3f at f%d (t %.3f, up %.3f)" % (
            name, tipf[1], tipf[0], (tipf[0] - f0) / sc.render.fps, low[2], low[0], (low[0] - f0) / sc.render.fps, low[1],
            footf[3], footf[0], (footf[0] - f0) / sc.render.fps, footf[4]))
        for r in rows[::3]:
            log("  %s f%3d tip fwd %.2f up %.2f | foot fwd %.2f up %.2f" % (name, *r))
    ad.action = None
    for t in ad.nla_tracks:
        t.mute = False
    sc.frame_set(1)

    bpy.ops.object.select_all(action="DESELECT")
    for ob in bpy.data.objects:
        ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format="GLB",
                              export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                              export_image_format="JPEG", export_jpeg_quality=90,
                              export_def_bones=False)
    log("wrote", OUT, "%.1f MB" % (os.path.getsize(OUT) / 1e6))


main()
