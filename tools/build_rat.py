"""Builds models/rat.glb, the live rat, from the user's Tripo model.

    blender -b --factory-startup -P tools/build_rat.py -- models/rat.glb
    blender -b --factory-startup -P tools/build_rat.py -- --preview <dir>
    godot --headless --import --path .

Source: models/source/rat/mouse_with_bones.blend (the user's "mouse with
bones.blend", 2026-10-18; under models/source/.gdignore). It holds three
copies of one Tripo rat -- a textured 566-vertex mesh, standing up on its
haunches, nose along +X, up +Z, about 1 m nose to tail tip -- each with a
32-bone Tripo auto-rig. That rig is not used: its head and forelegs hang off
the root rather than the spine, the tail hangs off a "limb", and the tail has
three bones. This script keeps the mesh and its texture, builds a clean rat
skeleton on it (hips, three spine bones, neck, head, a seven-bone tail ending
in a TailTip marker, three-segment legs), skins it with Blender's automatic
weights, and authors the clips with IK legs baked to plain FK keys:

    Run     the gallop (half-bound): hind legs push together, forelegs land one
            after the other, the back arches and stretches, the tail streams.
            RUN_STRIDE metres a cycle at 1x.
    Idle    down on all fours, sniffing: head bobs and turns, whiskers go.
    Rear    up on its haunches (the model's own pose), nose working, looking
            about.
    Dangle  caught: hung by the tip of its tail, head down, writhing -- the
            body curls up toward the hand, the legs paddle and grab at the air,
            the head lifts and swings.

The pose functions work in the rig's own terms (bend a bone about a WORLD
axis, relative to its parent: `turn`), so the numbers below read as anatomy.
Everything stays in Blender's frame here; the glTF exporter makes it +Y up, and
the game turns it to face -Z (rat.gd).
"""

import bpy
import bmesh
import math
import os
import sys
from mathutils import Euler, Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SOURCE = os.path.join(ROOT, "models", "source", "rat", "mouse_with_bones.blend")
MESH_NAME = "tripo_node_4bf8b87c.001"

FPS = 30

# --- The skeleton, in the source's frame (metres, +X nose, +Z up) -------------------
# Placed through the mesh's own parts (measured from the Tripo weights: thigh
# centre (0.06, 0.05, 0.10), heel (0.14, 0.06, 0.07), toes (0.23, 0.10, 0.03),
# upper arm (0.25, 0.06, 0.44), forearm (0.34, 0.06, 0.37), head (0.34, 0, 0.65),
# tail centreline z 0.04 -> 0.01 -> 0.045 from x -0.08 to -0.50).
# name: (head, tail, parent)
BONES = [
    ("Root", (0.0, 0.0, 0.0), (0.0, 0.0, 0.06), None),
    ("Hips", (0.02, 0.0, 0.11), (0.08, 0.0, 0.22), "Root"),
    ("Spine1", (0.08, 0.0, 0.22), (0.14, 0.0, 0.33), "Hips"),
    ("Spine2", (0.14, 0.0, 0.33), (0.20, 0.0, 0.44), "Spine1"),
    ("Chest", (0.20, 0.0, 0.44), (0.245, 0.0, 0.52), "Spine2"),
    ("Neck", (0.245, 0.0, 0.52), (0.29, 0.0, 0.60), "Chest"),
    ("Head", (0.29, 0.0, 0.60), (0.47, 0.0, 0.66), "Neck"),
    ("Tail0", (-0.03, 0.0, 0.06), (-0.10, 0.0, 0.037), "Hips"),
    ("Tail1", (-0.10, 0.0, 0.037), (-0.17, 0.0, 0.02), "Tail0"),
    ("Tail2", (-0.17, 0.0, 0.02), (-0.24, 0.0, 0.014), "Tail1"),
    ("Tail3", (-0.24, 0.0, 0.014), (-0.31, 0.0, 0.016), "Tail2"),
    ("Tail4", (-0.31, 0.0, 0.016), (-0.38, 0.0, 0.022), "Tail3"),
    ("Tail5", (-0.38, 0.0, 0.022), (-0.44, 0.0, 0.032), "Tail4"),
    ("Tail6", (-0.44, 0.0, 0.032), (-0.50, 0.0, 0.045), "Tail5"),
    ("TailTip", (-0.50, 0.0, 0.045), (-0.52, 0.0, 0.05), "Tail6"),
]
for side, s in (("L", 1.0), ("R", -1.0)):
    BONES += [
        ("Thigh." + side, (0.03, 0.045 * s, 0.14), (0.14, 0.06 * s, 0.11), "Hips"),
        ("Shin." + side, (0.14, 0.06 * s, 0.11), (0.115, 0.062 * s, 0.045), "Thigh." + side),
        ("Foot." + side, (0.115, 0.062 * s, 0.045), (0.19, 0.08 * s, 0.028), "Shin." + side),
        ("Toes." + side, (0.19, 0.08 * s, 0.028), (0.25, 0.1 * s, 0.022), "Foot." + side),
        ("UpperArm." + side, (0.215, 0.05 * s, 0.49), (0.285, 0.065 * s, 0.40), "Chest"),
        ("Forearm." + side, (0.285, 0.065 * s, 0.40), (0.35, 0.07 * s, 0.36), "UpperArm." + side),
        ("Hand." + side, (0.35, 0.07 * s, 0.36), (0.38, 0.075 * s, 0.345), "Forearm." + side),
    ]
NON_DEFORM = {"Root", "TailTip"}


def _clear_others(keep):
    for ob in list(bpy.data.objects):
        if ob != keep:
            bpy.data.objects.remove(ob, do_unlink=True)


def load_mesh():
    bpy.ops.wm.open_mainfile(filepath=SOURCE)
    src = bpy.data.objects[MESH_NAME]
    # Its rest shape, free of the Tripo rig.
    src.parent = None
    for m in list(src.modifiers):
        src.modifiers.remove(m)
    src.vertex_groups.clear()
    src.matrix_world = Matrix.Identity(4)
    _clear_others(src)
    src.name = "Rat"
    src.data.name = "Rat"
    for mat in src.data.materials:
        mat.name = "RatFur"
    return src


def build_armature():
    arm_data = bpy.data.armatures.new("RatRig")
    arm = bpy.data.objects.new("RatRig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones
    for name, head, tail, parent in BONES:
        b = eb.new(name)
        b.head = Vector(head)
        b.tail = Vector(tail)
        # Every bone rolled so its X axis lies along world +Y (sideways): a
        # bend about X is then a pitch, the same way for every bone.
        b.align_roll(Vector((0.0, 1.0, 0.0)) if abs((b.tail - b.head).normalized().y) < 0.9
                     else Vector((0.0, 0.0, 1.0)))
        b.use_deform = name not in NON_DEFORM
        if parent:
            b.parent = eb[parent]
            b.use_connect = (eb[parent].tail - b.head).length < 1e-4
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm


def skin(mesh, arm):
    bpy.ops.object.select_all(action='DESELECT')
    mesh.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    # The small islands (ears, eyes, whiskers) belong to the head, whatever
    # the heat solve made of them; any vertex left with no weight takes its
    # nearest weighted neighbour's.
    me = mesh.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    seen = set()
    islands = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        seen.add(v.index)
        isl = []
        while stack:
            a = stack.pop()
            isl.append(a.index)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in seen:
                    seen.add(b.index)
                    stack.append(b)
        islands.append(isl)
    bm.free()
    islands.sort(key=len, reverse=True)
    head = mesh.vertex_groups.get("Head")
    for isl in islands[1:]:
        for g in mesh.vertex_groups:
            g.remove(isl)
        head.add(isl, 1.0, 'REPLACE')
    from mathutils import kdtree
    weighted = [v for v in me.vertices if sum(g.weight for g in v.groups) > 0.01]
    kd = kdtree.KDTree(len(weighted))
    for i, v in enumerate(weighted):
        kd.insert(v.co, i)
    kd.balance()
    fixed = 0
    for v in me.vertices:
        if sum(g.weight for g in v.groups) > 0.01:
            continue
        _co, i, _d = kd.find(v.co)
        for g in weighted[i].groups:
            mesh.vertex_groups[g.group].add([v.index], g.weight, 'REPLACE')
        fixed += 1
    # Smoothed, at most four bones a vertex (glTF's), normalised: the raw heat
    # weights pulled rump skin up with a swinging thigh.
    bpy.ops.object.select_all(action='DESELECT')
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.mode_set(mode='WEIGHT_PAINT')
    bpy.ops.object.vertex_group_smooth(group_select_mode='ALL', factor=0.5, repeat=3)
    bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    print("[rat] skinned; %d islands to the head, %d unweighted vertices filled" % (len(islands) - 1, fixed))


# --- Posing ----------------------------------------------------------------------

def turn(pb, axis, angle, also=None):
    """Bends pose bone `pb` by `angle` (radians) about the WORLD-frame axis
    `axis`, as seen in its rest frame -- i.e. relative to its parent. Composes
    with what it already has."""
    rest = pb.bone.matrix_local.to_3x3()
    local_axis = (rest.inverted() @ Vector(axis)).normalized()
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = Quaternion(local_axis, angle) @ pb.rotation_quaternion


PITCH = (0.0, 1.0, 0.0)   # + tips the front end down (nose toward +X, -Z)
YAW = (0.0, 0.0, 1.0)     # + turns the nose toward +Y (its left)
ROLL = (1.0, 0.0, 0.0)    # + rolls its left side up


def reset(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
        pb.scale = Vector((1.0, 1.0, 1.0))


def preview(arm, mesh, out_dir, tag):
    """Renders the posed rat from the side, three-quarter and top."""
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'TEXTURE'
    sc.render.resolution_x = 560
    sc.render.resolution_y = 420
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cd = bpy.data.cameras.new("PreviewCam")
        cd.type = 'ORTHO'
        cd.ortho_scale = 1.4
        cam = bpy.data.objects.new("PreviewCam", cd)
        sc.collection.objects.link(cam)
    sc.camera = cam
    bpy.context.view_layer.update()
    bb = [mesh.matrix_world @ Vector(c) for c in mesh.bound_box]
    deps = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(deps)
    pts = [ev.matrix_world @ v.co for v in ev.data.vertices]
    centre = sum(pts, Vector()) / len(pts)
    for name, d in (("side", (0, -3, 0)), ("q", (2.2, -2.2, 1.4)), ("top", (0, 0, 3)), ("front", (3, 0, 0.3))):
        cam.location = centre + Vector(d)
        cam.rotation_euler = (centre - cam.location).to_track_quat('-Z', 'Y').to_euler()
        if name == "top":
            cam.rotation_euler = Euler((0.0, 0.0, 0.0))
        sc.render.filepath = os.path.join(out_dir, "%s_%s.png" % (tag, name))
        bpy.ops.render.render(write_still=True)


def update():
    bpy.context.view_layer.update()


def place(pb, head, ydir, lateral=Vector((0.0, 1.0, 0.0))):
    """Points pose bone `pb` along `ydir` from `head` (armature space, which is
    world here), its Z axis kept on `lateral` as the rig's rolls have it."""
    y = ydir.normalized()
    z = (lateral - y * y.dot(lateral)).normalized()
    x = y.cross(z)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = head
    pb.matrix = m
    pb.scale = Vector((1.0, 1.0, 1.0))
    update()


def two_bone(pb_a, pb_b, target, bend):
    """Analytical two-bone IK in the plane of `bend`: the joint between the
    bones goes toward `bend` (knees forward, elbows back). Out of reach, the
    limb points straight at the target."""
    h = pb_a.head.copy()
    a = pb_a.bone.length
    b = pb_b.bone.length
    span = target - h
    d = max(min(span.length, a + b - 1e-4), abs(a - b) + 1e-4)
    u = span.normalized()
    w = bend - u * u.dot(bend)
    w = w.normalized() if w.length > 1e-6 else Vector((1.0, 0.0, 0.0))
    cos_a = max(-1.0, min(1.0, (a * a + d * d - b * b) / (2.0 * a * d)))
    sin_a = math.sqrt(max(0.0, 1.0 - cos_a * cos_a))
    joint = h + a * (cos_a * u + sin_a * w)
    end = h + u * d
    place(pb_a, h, joint - h)
    place(pb_b, joint, end - joint)
    return end


def dir_down(angle_deg):
    """A forward direction tipped `angle_deg` below the horizontal."""
    a = math.radians(angle_deg)
    return Vector((math.cos(a), 0.0, -math.sin(a)))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def bump(p, centre, width):
    """A periodic bell on the cycle (phase `p` in 0..1)."""
    d = (p - centre + 0.5) % 1.0 - 0.5
    return math.exp(-(d / width) ** 2)


def in_window(p, start, length):
    """0..1 through a window of the cycle starting at `start`, or -1 outside."""
    t = (p - start) % 1.0
    return t / length if t < length else -1.0


def set_hips(arm, pos, pitch_deg, yaw_deg=0.0, roll_deg=0.0):
    pb = arm.pose.bones["Hips"]
    rot = (Matrix.Rotation(math.radians(yaw_deg), 4, 'Z') @ Matrix.Rotation(math.radians(pitch_deg), 4, 'Y')
           @ Matrix.Rotation(math.radians(roll_deg), 4, 'X'))
    m = rot @ pb.bone.matrix_local.to_3x3().to_4x4()
    m.translation = pos
    pb.matrix = m
    pb.scale = Vector((1.0, 1.0, 1.0))
    update()


# Hind and fore lengths, from the rig.
def _len(arm, *names):
    return sum(arm.data.bones[n].length for n in names)


# --- The clips ---------------------------------------------------------------------
#
# Each `pose_*` sets the whole rig for cycle phase `p` (0..1) and leaves it
# evaluated. Units are the source's (the game scales the rat by rat.gd SCALE).

RUN_FRAMES = 10          # a cycle, at FPS
RUN_STRIDE = 0.8        # source metres the ground moves under it a cycle
HIND_STANCE = 0.30
FORE_STANCE = 0.215
HIND_TOUCH = (0.0, 0.03)  # L, R: phase each hind foot lands
FORE_TOUCH = (0.45, 0.52)


def _spine_bend(pb, flex):
    """`flex` degrees of arch (+) / stretch (-) spread down the back."""
    turn(pb["Spine1"], PITCH, math.radians(flex * 0.45))
    turn(pb["Spine2"], PITCH, math.radians(flex * 0.55))
    turn(pb["Chest"], PITCH, math.radians(flex * 0.35))


def _tail(pb, p, lift_deg, wave_deg, lateral_deg, speed=1.0, base=-55.0):
    turn(pb["Tail0"], PITCH, math.radians(base + lift_deg))
    for i in range(7):
        b = pb["Tail%d" % i]
        turn(b, YAW, math.radians(lateral_deg * math.sin(2 * math.pi * p * speed - i * 0.7)))
        if i > 0:
            turn(b, PITCH, math.radians(wave_deg * math.sin(2 * math.pi * p * speed - i * 0.9 + 1.3) - 1.5))


def _ankle_of(arm, side, toe, foot_deg, toes_deg):
    pb = arm.pose.bones
    return toe - dir_down(toes_deg) * pb["Toes." + side].bone.length \
        - dir_down(foot_deg) * pb["Foot." + side].bone.length


def _hind_ankle(arm, side, ankle, foot_deg, toes_deg):
    pb = arm.pose.bones
    s = 1.0 if side == "L" else -1.0
    two_bone(pb["Thigh." + side], pb["Shin." + side], ankle, Vector((1.0, 0.25 * s, 0.0)))
    place(pb["Foot." + side], pb["Shin." + side].tail.copy(), dir_down(foot_deg))
    place(pb["Toes." + side], pb["Foot." + side].tail.copy(), dir_down(toes_deg))


def _hind(arm, side, toe, foot_deg, toes_deg):
    _hind_ankle(arm, side, _ankle_of(arm, side, toe, foot_deg, toes_deg), foot_deg, toes_deg)


def _fore(arm, side, paw, hand_deg):
    pb = arm.pose.bones
    s = 1.0 if side == "L" else -1.0
    hl = pb["Hand." + side].bone.length
    hdir = dir_down(hand_deg)
    wrist = paw - hdir * hl
    two_bone(pb["UpperArm." + side], pb["Forearm." + side], wrist, Vector((-1.0, 0.1 * s, 0.0)))
    place(pb["Hand." + side], pb["Forearm." + side].tail.copy(), hdir)


def pose_run(arm, p):
    reset(arm)
    update()
    pb = arm.pose.bones
    # The body: hips height and pitch rock with the gait -- up off the hind
    # push (p ~0.4) and again off the fore push (~0.85), down as each pair
    # loads; the back arches as the hind feet come up under it (~0.9) and
    # stretches out in the long flight (~0.4).
    height = 0.18 + 0.026 * bump(p, 0.40, 0.12) + 0.014 * bump(p, 0.86, 0.10) \
        - 0.010 * bump(p, 0.12, 0.08) - 0.008 * bump(p, 0.60, 0.08)
    pitch = 56.0 - 5.0 * bump(p, 0.36, 0.12) + 5.0 * bump(p, 0.62, 0.12)
    c = math.cos(2 * math.pi * (p - 0.92))
    flex = 16.0 * c if c > 0.0 else 6.0 * c
    set_hips(arm, Vector((0.0, 0.0, height)), pitch, roll_deg=2.0 * math.sin(2 * math.pi * p))
    _spine_bend(pb, flex)
    # The head held steady against all that (most of it), nose a touch down.
    turn(pb["Neck"], PITCH, math.radians(-(pitch - 56.0) * 0.7 - flex * 0.9 - 26.0))
    turn(pb["Head"], PITCH, math.radians(-8.0 + 3.0 * math.sin(2 * math.pi * (p - 0.2))))
    # The tail streams out behind, a little up, a wave running down it.
    _tail(pb, p, lift_deg=6.0 - flex * 0.25, wave_deg=4.0, lateral_deg=5.0)
    update()
    hip_x = {s: pb["Thigh." + s].head.x for s in "LR"}
    sh_x = {s: pb["UpperArm." + s].head.x for s in "LR"}
    for i, side in enumerate("LR"):
        s = 1.0 if side == "L" else -1.0
        # Hind: the toes on the ground through the stance, sliding back the
        # stride's share; then a fast, high swing forward, foot folded.
        touch_x = hip_x[side] + 0.12
        lift_x = touch_x - RUN_STRIDE * HIND_STANCE

        def stance(t, s=s, touch_x=touch_x, lift_x=lift_x):
            toe = Vector((touch_x + (lift_x - touch_x) * t, 0.085 * s, 0.004))
            return toe, 18.0 + 45.0 * smooth(t), -2.0 + 30.0 * smooth((t - 0.6) / 0.4)

        t = in_window(p, HIND_TOUCH[i], HIND_STANCE)
        if t >= 0.0:
            toe, foot_deg, toes_deg = stance(t)
            _hind(arm, side, toe, foot_deg, toes_deg)
        else:
            # The swing: the ANKLE carried forward on a low arc under the hip
            # from where the push left it to where the next landing wants it,
            # the foot folding up behind and opening out to land. (Swinging
            # the toes instead put the ankle above the hip and the thigh up
            # through the rump.)
            u = ((p - HIND_TOUCH[i] - HIND_STANCE) % 1.0) / (1.0 - HIND_STANCE)
            k = smooth(u)
            a0 = _ankle_of(arm, side, *stance(1.0))
            a1 = _ankle_of(arm, side, *stance(0.0))
            ankle = a0.lerp(a1, k) + Vector((0.0, 0.0, 0.03 * math.sin(math.pi * u)))
            foot_deg = 63.0 + (18.0 - 63.0) * k + 28.0 * math.sin(math.pi * u)
            toes_deg = 28.0 + (-2.0 - 28.0) * smooth((u - 0.6) / 0.4) + 35.0 * math.sin(math.pi * u)
            _hind_ankle(arm, side, ankle, foot_deg, toes_deg)
        # Fore: reach well out in front, land, the body runs over the paw.
        reach_x = sh_x[side] + 0.11
        back_x = reach_x - RUN_STRIDE * FORE_STANCE
        t = in_window(p, FORE_TOUCH[i], FORE_STANCE)
        if t >= 0.0:
            paw = Vector((reach_x + (back_x - reach_x) * t, 0.06 * s, 0.003))
            hand_deg = 8.0 + 50.0 * smooth(t)
        else:
            u = ((p - FORE_TOUCH[i] - FORE_STANCE) % 1.0) / (1.0 - FORE_STANCE)
            k = smooth(u)
            paw = Vector((back_x + (reach_x - back_x) * k, 0.06 * s, 0.003 + 0.06 * math.sin(math.pi * u)))
            hand_deg = 58.0 + 30.0 * math.sin(math.pi * u) - 80.0 * smooth((u - 0.65) / 0.35)
        _fore(arm, side, paw, hand_deg)


IDLE_FRAMES = 150


def _sniff(p, rate=9.0):
    """The nose working: quick small bobs in bursts."""
    burst = max(0.0, math.sin(2 * math.pi * p * 2.0 + 0.6))
    return math.sin(2 * math.pi * p * rate * 5.0) * burst


def pose_idle(arm, p):
    """Down on all fours, sniffing about: the head bobs in bursts and turns
    to look, the body breathes, the tail lies out behind with a slow sway."""
    reset(arm)
    update()
    pb = arm.pose.bones
    look = math.sin(2 * math.pi * p) * 0.6 + math.sin(2 * math.pi * p * 3.0 + 1.0) * 0.4
    breathe = math.sin(2 * math.pi * p * 5.0)
    set_hips(arm, Vector((0.0, 0.0, 0.105 + 0.002 * breathe)), 58.0)
    _spine_bend(pb, 12.0 + 1.5 * breathe)
    turn(pb["Neck"], PITCH, math.radians(-34.0 + 6.0 * math.sin(2 * math.pi * p * 2.0)))
    turn(pb["Neck"], YAW, math.radians(18.0 * look))
    turn(pb["Head"], PITCH, math.radians(-6.0 + 4.0 * _sniff(p)))
    turn(pb["Head"], YAW, math.radians(8.0 * look))
    _tail(pb, p, lift_deg=-15.0, wave_deg=1.5, lateral_deg=6.0, speed=1.0)
    update()
    for i, side in enumerate("LR"):
        s = 1.0 if side == "L" else -1.0
        hip = pb["Thigh." + side].head
        _hind(arm, side, Vector((hip.x + 0.12, 0.085 * s, 0.004)), 22.0, -2.0)
        sh = pb["UpperArm." + side].head
        # One forepaw lifts and sets down now and then.
        lift = bump(p, 0.3 if side == "L" else 0.72, 0.05)
        _fore(arm, side, Vector((sh.x + 0.05 + 0.02 * lift, 0.06 * s, 0.003 + 0.03 * lift)), 10.0 + 30.0 * lift)


REAR_FRAMES = 150


def pose_rear(arm, p):
    """Up on its haunches, as the model stands: nose working, looking about,
    forepaws held up and twitching."""
    reset(arm)
    update()
    pb = arm.pose.bones
    look = math.sin(2 * math.pi * p) * 0.7 + math.sin(2 * math.pi * p * 2.0 + 2.0) * 0.3
    breathe = math.sin(2 * math.pi * p * 5.0)
    turn(pb["Spine2"], PITCH, math.radians(1.5 * breathe))
    turn(pb["Neck"], YAW, math.radians(24.0 * look))
    turn(pb["Neck"], PITCH, math.radians(-6.0 * math.sin(2 * math.pi * p * 2.0 + 0.4)))
    turn(pb["Head"], PITCH, math.radians(4.0 * _sniff(p) - 4.0))
    turn(pb["Head"], ROLL, math.radians(6.0 * look))
    for side in "LR":
        s = 1.0 if side == "L" else -1.0
        twitch = math.sin(2 * math.pi * p * 4.0 + (0.0 if side == "L" else 1.7))
        turn(pb["Forearm." + side], PITCH, math.radians(6.0 * twitch))
        turn(pb["Hand." + side], PITCH, math.radians(10.0 * twitch))
    for i in range(1, 7):
        turn(pb["Tail%d" % i], YAW, math.radians(5.0 * math.sin(2 * math.pi * p - i * 0.6)))
    update()


DANGLE_FRAMES = 120


def pose_dangle(arm, p):
    """Caught, hung by the tip of its tail, head down. It writhes: curls up
    toward the hand (trying to climb its own tail), throws itself side to
    side, twists, the forelegs reach and grab at the air, the hind legs kick
    and splay, the head lifts and swings. Loops (p 0..1)."""
    reset(arm)
    update()
    pb = arm.pose.bones
    w = 2 * math.pi
    # The body hangs nose down off the rump; the tail runs straight up from
    # the rump to the hand.
    curl = 0.5 + 0.5 * math.sin(w * p * 2.0 - 1.2)                 # 0 hanging .. 1 curled up
    curl = curl ** 1.5
    thrash = math.sin(w * p * 3.0) * 0.7 + math.sin(w * p * 7.0 + 0.5) * 0.3
    twist = math.sin(w * p * 2.0 + 0.4) * 22.0 + math.sin(w * p * 5.0) * 8.0
    set_hips(arm, Vector((0.0, 0.0, 0.0)), 151.0 - 25.0 * curl, yaw_deg=0.0, roll_deg=twist)
    turn(pb["Tail0"], PITCH, math.radians(-42.0 + 25.0 * curl))
    for i in range(1, 7):
        turn(pb["Tail%d" % i], PITCH, math.radians(-1.0 + 3.0 * math.sin(w * p * 3.0 - i)))
        turn(pb["Tail%d" % i], YAW, math.radians(2.5 * math.sin(w * p * 2.0 - i * 0.8)))
    # The trunk curls belly-in and throws itself side to side.
    for name, share in (("Spine1", 0.3), ("Spine2", 0.4), ("Chest", 0.3)):
        turn(pb[name], PITCH, math.radians(55.0 * curl * share))
        turn(pb[name], YAW, math.radians(34.0 * thrash * share))
    turn(pb["Neck"], PITCH, math.radians(25.0 * curl - 10.0 + 8.0 * math.sin(w * p * 5.0)))
    turn(pb["Neck"], YAW, math.radians(25.0 * math.sin(w * p * 3.0 + 1.0)))
    turn(pb["Head"], PITCH, math.radians(18.0 * curl + 6.0 * math.sin(w * p * 9.0)))
    # Forelegs: reaching out, grabbing at nothing, fast and out of step.
    for side, ph in (("L", 0.0), ("R", 2.1)):
        s = 1.0 if side == "L" else -1.0
        paddle = math.sin(w * p * 6.0 + ph)
        reach = math.sin(w * p * 2.0 + ph * 0.5)
        turn(pb["UpperArm." + side], PITCH, math.radians(-40.0 * reach - 20.0 * paddle - 10.0))
        turn(pb["UpperArm." + side], ROLL, math.radians(s * (25.0 + 15.0 * paddle)))
        turn(pb["Forearm." + side], PITCH, math.radians(-25.0 + 30.0 * paddle))
        turn(pb["Hand." + side], PITCH, math.radians(-30.0 + 40.0 * math.sin(w * p * 6.0 + ph + 1.0)))
    # Hind legs: kicking and splaying.
    for side, ph in (("L", 0.9), ("R", 3.0)):
        s = 1.0 if side == "L" else -1.0
        kick = math.sin(w * p * 5.0 + ph)
        splay = 0.5 + 0.5 * math.sin(w * p * 2.0 + ph)
        turn(pb["Thigh." + side], PITCH, math.radians(-25.0 + 35.0 * kick))
        turn(pb["Thigh." + side], ROLL, math.radians(s * (15.0 + 30.0 * splay)))
        turn(pb["Shin." + side], PITCH, math.radians(-20.0 - 25.0 * kick))
        turn(pb["Foot." + side], PITCH, math.radians(30.0 + 25.0 * math.sin(w * p * 5.0 + ph + 0.8)))
        turn(pb["Toes." + side], PITCH, math.radians(20.0 * math.sin(w * p * 10.0 + ph)))
    update()


CLIPS = [
    ("Run", pose_run, RUN_FRAMES),
    ("Idle", pose_idle, IDLE_FRAMES),
    ("Rear", pose_rear, REAR_FRAMES),
    ("Dangle", pose_dangle, DANGLE_FRAMES),
]


def bake(arm, name, fn, frames):
    """One action, a key on every bone every frame for `frames` + 1 frames (the
    last equal to the first, so it loops seamlessly)."""
    act = bpy.data.actions.new(name)
    arm.animation_data_create()
    arm.animation_data.action = act
    last = {}
    for f in range(frames + 1):
        fn(arm, (f % frames) / frames)
        for pb in arm.pose.bones:
            q = pb.rotation_quaternion.copy()
            q.normalize()
            if pb.name in last and last[pb.name].dot(q) < 0.0:
                q.negate()
            last[pb.name] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if pb.name in ("Hips", "Root"):
                pb.keyframe_insert("location", frame=f)
    track = arm.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 0, act)
    arm.animation_data.action = None
    print("[rat] %s: %d frames" % (name, frames))
    return act


def clean_material(mesh):
    """Base colour from the Tripo texture, nothing else: the source wires a
    Normal Map node that has no normal image of its own."""
    mat = mesh.data.materials[0]
    img = None
    for n in mat.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image is not None:
            img = n.image
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    if img is not None:
        img.name = "rat_fur"
        # The exporter names the texture after the path (Tripo's, packed).
        img.filepath = "//rat_fur.jpg"
    tex.image = img
    bsdf.inputs["Roughness"].default_value = 0.85
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return img


def contact_sheet(arm, mesh, fn, frames, out_png, view="side", cols=5, count=10):
    """Renders `count` phases of a clip side by side into one PNG."""
    import numpy as np
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'TEXTURE'
    sc.render.resolution_x = 400
    sc.render.resolution_y = 220
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cd = bpy.data.cameras.new("PreviewCam")
        cd.type = 'ORTHO'
        cam = bpy.data.objects.new("PreviewCam", cd)
        sc.collection.objects.link(cam)
    cam.data.ortho_scale = 1.0
    ground = bpy.data.objects.get("PreviewGround")
    if ground is None:
        gm = bpy.data.meshes.new("PreviewGround")
        gm.from_pydata([(-2, -2, 0), (2, -2, 0), (2, 2, 0), (-2, 2, 0)], [], [(0, 1, 2, 3)])
        ground = bpy.data.objects.new("PreviewGround", gm)
        sc.collection.objects.link(ground)
    ground.hide_render = view == "dangle"
    sc.camera = cam
    tiles = []
    tmp = out_png + ".tile.png"
    # Framed on the clip's own extent (its first pose, padded).
    fn(arm, 0.0)
    deps = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(deps)
    pts = [ev.matrix_world @ v.co for v in ev.data.vertices]
    lo = Vector([min(q[i] for q in pts) for i in range(3)])
    hi = Vector([max(q[i] for q in pts) for i in range(3)])
    centre = (lo + hi) * 0.5
    cam.data.ortho_scale = max((hi - lo).x, (hi - lo).z) * 1.35
    for k in range(count):
        fn(arm, k / count)
        d = {"side": (0, -3, 0.0), "q": (2.0, -2.0, 1.2), "front": (3, 0, 0.2), "dangle": (0.3, -3, 0)}[view]
        cam.location = centre + Vector(d)
        cam.rotation_euler = (centre - cam.location).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        im = bpy.data.images.load(tmp)
        px = np.array(im.pixels[:]).reshape(im.size[1], im.size[0], 4)
        tiles.append(px)
        bpy.data.images.remove(im)
    rows = (count + cols - 1) // cols
    h, w = tiles[0].shape[:2]
    sheet = np.zeros((rows * h, cols * w, 4))
    for k, t in enumerate(tiles):
        r, c = divmod(k, cols)
        # Blender's pixel rows run bottom up.
        sheet[(rows - 1 - r) * h:(rows - r) * h, c * w:(c + 1) * w] = t
    out = bpy.data.images.new("sheet", cols * w, rows * h, alpha=True)
    out.pixels = sheet.ravel()
    out.filepath_raw = out_png
    out.file_format = 'PNG'
    out.save()
    os.remove(tmp)


def export(arm, mesh, path):
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    mesh.select_set(True)
    bpy.context.view_layer.objects.active = arm
    reset(arm)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        use_selection=True,
        export_animations=True,
        export_animation_mode='NLA_TRACKS',
        export_force_sampling=True,
        export_frame_step=1,
        export_def_bones=False,
        export_skins=True,
        export_yup=True,
        export_apply=False,
    )
    print("[rat] wrote", path)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    mesh = load_mesh()
    # After the load: opening the source resets the scene (it came out 24 fps).
    bpy.context.scene.render.fps = FPS
    arm = build_armature()
    skin(mesh, arm)
    clean_material(mesh)
    if argv and argv[0] == "--preview":
        out_dir = argv[1]
        os.makedirs(out_dir, exist_ok=True)
        which = argv[2:] or ["Run", "Idle", "Rear", "Dangle"]
        for name, fn, frames in CLIPS:
            if name not in which:
                continue
            view = "dangle" if name == "Dangle" else "side"
            contact_sheet(arm, mesh, fn, frames, os.path.join(out_dir, name + "_side.png"), view=view)
            contact_sheet(arm, mesh, fn, frames, os.path.join(out_dir, name + "_q.png"), view="q" if name != "Dangle" else "front")
        return
    for name, fn, frames in CLIPS:
        bake(arm, name, fn, frames)
    export(arm, mesh, os.path.abspath(argv[0]) if argv else os.path.join(ROOT, "models", "rat.glb"))


main()
