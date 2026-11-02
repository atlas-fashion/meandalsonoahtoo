"""The Proel builder's body (note 149), from the user's rusted metal golem.

    blender -b --factory-startup -P tools/build_proel_builder.py                 (all of it)
    blender -b --factory-startup -P tools/build_proel_builder.py -- --no-bake    (old normal map)

Writes models/source/proel_builder/proel_builder.blend (mesh, rig, materials) and
its maps. tools/anim_proel_builder.py then opens that .blend, writes every animation
and exports models/proel_builder.glb.

The source is the Tripo model models/source/proel_builder/rusted metal golem 3d
model.glb: 1.92 million triangles, 0.98 m tall, no rig, one surface. It is the same
kind of thing as the Proel swordsman's golem and goes through the same steps
(tools/build_sword_skeleton.py, note 136): scaled, welded, cut down, its normal map
baked, rigged by a watershed along the surface. What differs:

    NOT TURNED   it stands square, a little behind and to the right of the origin.
    TWO HAMMERS  each arm ends in a yoke and a head 0.56 x 0.44 x 0.29 m, with no
                 hand at all. `hammer.*` runs from the axle in the yoke through the
                 head, a hinge across X like the elbow. Its vertices are settled before
                 any others (`hammer_of`): a head hangs a few centimetres off its leg,
                 and a vertex on the wrong side of that drags a sliver the length of
                 the leg through every swing.

Blender's frame here: X the builder's LEFT, -Y its front, Z up, as for the swordsman.
The bones keep that rig's names, so sword_skeleton_react.gd and the eyes read this one.
"""

import bpy
import bmesh
import heapq
import math
import os
import sys
import time
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "models", "source", "proel_builder")
SOURCE = os.path.join(SRC, "rusted metal golem 3d model.glb")
ATLAS = 2048
TRIS = 42000
# The model's 0.98 m to 2.2, as the swordsman.
SCALE = 2.2 / 0.97900391
SHIFT = (0.03, -0.12, 0.0)


def V(x, y, z):
    return Vector((x, y, z))


def R(x, y, z):
    """A point read off the scaled source, in the frame the model is put in."""
    return V(x + SHIFT[0], y + SHIFT[1], z)


def log(*a):
    print("[golem]", *a, flush=True)


# The joints: measured by slicing the mesh and off close renders of it. The axles at the
# elbows and in the yokes are the model's own.
SHOULDER_L, ELBOW_L, WRIST_L = R(0.27, 0.07, 1.85), R(0.39, 0.06, 1.565), R(0.585, -0.01, 0.99)
SHOULDER_R, ELBOW_R, WRIST_R = R(-0.33, 0.13, 1.85), R(-0.43, 0.12, 1.565), R(-0.655, 0.055, 0.985)
HEAD_L, HEAD_R = R(0.692, -0.02, 0.74), R(-0.724, -0.02, 0.733)
HIP_L, KNEE_L, ANKLE_L = R(0.10, 0.10, 1.2), R(0.285, 0.03, 0.74), R(0.47, 0.07, 0.19)
HIP_R, KNEE_R, ANKLE_R = R(-0.145, 0.10, 1.2), R(-0.25, 0.03, 0.81), R(-0.345, 0.205, 0.19)
BALL_L, TOE_L = R(0.55, -0.06, 0.04), R(0.60, -0.15, 0.02)
BALL_R, TOE_R = R(-0.445, 0.075, 0.04), R(-0.50, 0.0, 0.02)
PELVIS = R(-0.02, 0.11, 1.22)
SPINE_1 = R(-0.015, 0.125, 1.36)
SPINE_2 = R(-0.02, 0.12, 1.54)
CHEST = R(-0.03, 0.10, 1.68)
NECK = R(-0.04, 0.05, 1.90)
HEAD = R(-0.06, -0.04, 1.98)
# The eyes, in their sockets. The texture has only one of them lit.
EYES = (R(-0.02, -0.215, 2.03), R(-0.09, -0.215, 2.025))
EYE_R = 0.016

# Name, parent, head, tail.
BONES = [
    ("root", None, V(0, 0, 0), V(0, 0, 0.12)),
    ("pelvis", "root", PELVIS, SPINE_1),
    ("spine.01", "pelvis", SPINE_1, SPINE_2),
    ("spine.02", "spine.01", SPINE_2, CHEST),
    ("chest", "spine.02", CHEST, NECK),
    ("neck", "chest", NECK, HEAD),
    ("head", "neck", HEAD, R(-0.07, -0.14, 2.19)),
    ("clavicle.L", "chest", R(0.0, 0.09, 1.84), SHOULDER_L),
    ("upper_arm.L", "clavicle.L", SHOULDER_L, ELBOW_L),
    ("forearm.L", "upper_arm.L", ELBOW_L, WRIST_L),
    ("hammer.L", "forearm.L", WRIST_L, HEAD_L + (HEAD_L - WRIST_L).normalized() * 0.2),
    ("clavicle.R", "chest", R(-0.06, 0.09, 1.84), SHOULDER_R),
    ("upper_arm.R", "clavicle.R", SHOULDER_R, ELBOW_R),
    ("forearm.R", "upper_arm.R", ELBOW_R, WRIST_R),
    ("hammer.R", "forearm.R", WRIST_R, HEAD_R + (HEAD_R - WRIST_R).normalized() * 0.2),
    ("thigh.L", "pelvis", HIP_L, KNEE_L),
    ("shin.L", "thigh.L", KNEE_L, ANKLE_L),
    ("foot.L", "shin.L", ANKLE_L, BALL_L),
    ("toe.L", "foot.L", BALL_L, TOE_L),
    ("thigh.R", "pelvis", HIP_R, KNEE_R),
    ("shin.R", "thigh.R", KNEE_R, ANKLE_R),
    ("foot.R", "shin.R", ANKLE_R, BALL_R),
    ("toe.R", "foot.R", BALL_R, TOE_R),
]
PARENT = {b[0]: b[1] for b in BONES}
SEG = {b[0]: (b[2], b[3]) for b in BONES}
# The knees' hinges at rest. The animation reads these to know which way a joint folds.
PIN_KNEE_L = V(1.0, 0.0, 0.0)
PIN_KNEE_R = V(1.0, 0.0, 0.0)
# How far a seed reaches out from its bone.
SEED = {"pelvis": 0.13, "spine.01": 0.10, "spine.02": 0.10, "chest": 0.15, "neck": 0.07, "head": 0.14, "clavicle.L": 0.07, "clavicle.R": 0.07,
        "upper_arm.L": 0.12, "forearm.L": 0.10, "hammer.L": 0.05, "upper_arm.R": 0.12, "forearm.R": 0.10, "hammer.R": 0.05,
        "thigh.L": 0.1, "thigh.R": 0.1, "shin.L": 0.09, "shin.R": 0.09, "foot.L": 0.09, "foot.R": 0.09, "toe.L": 0.05, "toe.R": 0.05}
# The middle of each leg, (height, x), off the slices, and how far from that the leg ends
# and the head beside it may begin. Over HAMMER_TOP is the collar on the forearm.
LEG_LINE_L = ((1.0, 0.182), (0.84, 0.248), (0.76, 0.273), (0.52, 0.349), (0.44, 0.383))
LEG_LINE_R = ((1.0, -0.195), (0.84, -0.257), (0.76, -0.259), (0.6, -0.276), (0.44, -0.302))
LEG_CLEAR = 0.082
HAMMER_TOP = 0.97
# Steps of smoothing across a joint between these. A hinge is sharp; the spine bends.
SOFT_DEFAULT = 2
SOFT = {("pelvis", "spine.01"): 8, ("spine.01", "spine.02"): 10, ("spine.02", "chest"): 10, ("chest", "neck"): 6, ("neck", "head"): 3, ("chest", "clavicle.L"): 6,
        ("chest", "clavicle.R"): 6, ("clavicle.L", "upper_arm.L"): 4, ("clavicle.R", "upper_arm.R"): 4, ("pelvis", "thigh.L"): 5, ("pelvis", "thigh.R"): 5}


def activate(ob):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def load_source():
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    hi = next(o for o in bpy.data.objects if o.type == 'MESH')
    hi.name = "Hi"
    me = hi.data
    me.transform(Matrix.Translation(SHIFT) @ Matrix.Scale(SCALE, 4))
    me.update()
    activate(hi)
    m = hi.modifiers.new("Weld", 'WELD')
    m.merge_threshold = 0.0004
    bpy.ops.object.modifier_apply(modifier="Weld")
    log("source: %d tris, %d verts after welding" % (len(hi.data.polygons), len(hi.data.vertices)))
    return hi


def seg_dist(p, a, b):
    d = b - a
    t = max(0.0, min(1.0, (p - a).dot(d) / max(d.length_squared, 1e-9)))
    return (p - (a + d * t)).length, t


def hammer_of(p):
    """The hammer this point is part of, or None. A head hangs so close beside the leg
    that nothing but the leg's own line tells them apart: the leg's middle at this
    height, from the slices, and LEG_CLEAR past that is hammer."""
    if not 0.47 < p.z < HAMMER_TOP:
        return None
    for name, head, line, sgn in (("hammer.L", HEAD_L, LEG_LINE_L, 1.0), ("hammer.R", HEAD_R, LEG_LINE_R, -1.0)):
        if sgn * (p.x - SHIFT[0]) > sgn * leg_x(line, p.z) + LEG_CLEAR and (p - head).length < 0.56:
            return name
    return None


def leg_x(line, z):
    for (z1, x1), (z0, x0) in zip(line, line[1:]):
        if z >= z0:
            return x0 + (x1 - x0) * (z - z0) / (z1 - z0)
    return line[-1][1]


def decimate(hi):
    low = hi.copy()
    low.data = hi.data.copy()
    low.name = "Low"
    bpy.context.scene.collection.objects.link(low)
    activate(low)
    # Evenly to twice the budget; then the mask is held where it is while the rest
    # comes down (build_sword_skeleton.py: a held edge is never taken).
    m = low.modifiers.new("Cut", 'DECIMATE')
    m.decimate_type = 'COLLAPSE'
    m.ratio = 2.0 * TRIS / len(low.data.polygons)
    bpy.ops.object.modifier_apply(modifier="Cut")
    g = low.vertex_groups.new(name="keep")
    mask = [i for i, v in enumerate(low.data.vertices) if v.co.z > 1.9 and v.co.y < -0.26]
    g.add(mask, 1.0, 'REPLACE')
    m = low.modifiers.new("Cut", 'DECIMATE')
    m.decimate_type = 'COLLAPSE'
    m.ratio = TRIS / len(low.data.polygons)
    m.vertex_group = "keep"
    m.invert_vertex_group = True
    m.vertex_group_factor = 1.0
    bpy.ops.object.modifier_apply(modifier="Cut")
    low.vertex_groups.clear()
    me = low.data
    me.shade_smooth()
    log("low: %d tris, %d verts" % (len(me.polygons), len(me.vertices)))
    return low


def light_eyes(glow):
    """The eyes' colour: the swordsman's dull red, under the bloom. The anim script sets
    it again, so changing it here needs no rebuild of the model."""
    q = next(n for n in glow.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    q.inputs["Base Color"].default_value = (0.22, 0.012, 0.008, 1.0)
    q.inputs["Emission Color"].default_value = (1.0, 0.035, 0.018, 1.0)
    q.inputs["Emission Strength"].default_value = 0.8


def add_eyes(low):
    """Two lenses in the sockets, the one thing the texture cannot do: glow."""
    bm = bmesh.new()
    for e in EYES:
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=EYE_R, matrix=Matrix.Translation(e) @ Matrix.Scale(1.0, 4), calc_uvs=False)
    me = bpy.data.meshes.new("Eyes")
    bm.to_mesh(me)
    bm.free()
    me.uv_layers.new(name=low.data.uv_layers[0].name)
    me.shade_smooth()
    ob = bpy.data.objects.new("Eyes", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def images():
    """The source's colour and metal maps, byte for byte: the charts are the same, so
    they carry straight over. The metal map's red is all ones, so it serves as ORM."""
    for img in bpy.data.images:
        name = None
        if img.name.endswith("basecolor.jpg"):
            name = "proel_builder_col.jpg"
        elif img.name.endswith("_rm.jpg"):
            name = "proel_builder_orm.jpg"
        if name:
            with open(os.path.join(SRC, name), "wb") as f:
                f.write(bytes(img.packed_file.data))


def bake_normal(hi, low):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = 'OPTIX'
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    sc.cycles.device = 'GPU'
    sc.cycles.samples = 8
    sc.cycles.use_denoising = False
    size = ATLAS * 2
    img = bpy.data.images.new("bake_nor", size, size, alpha=False, float_buffer=True)
    img.colorspace_settings.name = 'Non-Color'
    img.generated_color = (0.5, 0.5, 1.0, 1.0)
    mat = low.data.materials[0]
    if mat.users > 1 or mat == hi.data.materials[0]:
        mat = mat.copy()
        low.data.materials[0] = mat
    nt = mat.node_tree
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    nt.nodes.active = t
    b = sc.render.bake
    b.use_selected_to_active = True
    b.use_cage = False
    b.cage_extrusion = 0.02
    b.max_ray_distance = 0.06
    b.margin = 16
    b.margin_type = 'EXTEND'
    b.use_clear = True
    b.target = 'IMAGE_TEXTURES'
    bpy.ops.object.select_all(action='DESELECT')
    hi.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    t0 = time.time()
    bpy.ops.object.bake(type='NORMAL', normal_space='TANGENT', normal_r='POS_X', normal_g='POS_Y', normal_b='POS_Z')
    log("normal baked in %.0f s" % (time.time() - t0))
    img.scale(ATLAS, ATLAS)
    out = bpy.data.images.new("proel_builder_nor_s", ATLAS, ATLAS, alpha=False)
    out.colorspace_settings.name = 'Non-Color'
    import numpy as np
    px = np.empty(ATLAS * ATLAS * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    out.pixels.foreach_set(px)
    out.filepath_raw = os.path.join(SRC, "proel_builder_nor.png")
    out.file_format = 'PNG'
    out.save()
    nt.nodes.remove(t)


def final_materials():
    def image(name):
        for ext in (".jpg", ".png"):
            p = os.path.join(SRC, name + ext)
            if os.path.exists(p):
                img = bpy.data.images.load(p, check_existing=True)
                img.name = name
                return img
        raise RuntimeError("no map " + name)

    mat = bpy.data.materials.new("SkelCore")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    N = nt.nodes.new
    L = nt.links.new
    out = N("ShaderNodeOutputMaterial")
    p = N("ShaderNodeBsdfPrincipled")
    L(p.outputs[0], out.inputs["Surface"])
    t = N("ShaderNodeTexImage")
    t.image = image("proel_builder_col")
    L(t.outputs["Color"], p.inputs["Base Color"])
    tn = N("ShaderNodeTexImage")
    tn.image = image("proel_builder_nor")
    tn.image.colorspace_settings.name = 'Non-Color'
    nm = N("ShaderNodeNormalMap")
    L(tn.outputs["Color"], nm.inputs["Color"])
    L(nm.outputs[0], p.inputs["Normal"])
    to = N("ShaderNodeTexImage")
    to.image = image("proel_builder_orm")
    to.image.colorspace_settings.name = 'Non-Color'
    sp = N("ShaderNodeSeparateColor")
    L(to.outputs["Color"], sp.inputs[0])
    L(sp.outputs[1], p.inputs["Roughness"])
    L(sp.outputs[2], p.inputs["Metallic"])
    mat.use_backface_culling = True
    glow = bpy.data.materials.new("SkelGlow")
    glow.use_nodes = True
    q = next(n for n in glow.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    light_eyes(glow)
    q.inputs["Roughness"].default_value = 0.3
    return mat, glow


def build_armature():
    data = bpy.data.armatures.new("ProelBuilderRig")
    arm = bpy.data.objects.new("ProelBuilderRig", data)
    bpy.context.scene.collection.objects.link(arm)
    activate(arm)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = data.edit_bones
    for name, parent, head, tail in BONES:
        b = eb.new(name)
        b.head = head
        b.tail = tail
        b.use_connect = False
        if parent:
            b.parent = eb[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm


def graph(me):
    adj = [[] for _ in me.vertices]
    for e in me.edges:
        a, b = e.vertices
        d = (me.vertices[a].co - me.vertices[b].co).length
        adj[a].append((b, d))
        adj[b].append((a, d))
    return adj


def labels(me, adj):
    """Each vertex's bone: a watershed along the surface from the vertices lying close
    round each bone, so only the joint can pass a bone's territory on. Every vertex of a
    head is that hammer's from the start, and nothing else starts as one."""
    names = [b[0] for b in BONES if b[0] != "root"]
    idx = {n: i for i, n in enumerate(names)}
    n = len(me.vertices)
    best = [1e9] * n
    lab = [-1] * n
    heap = []
    for v in me.vertices:
        who = hammer_of(v.co)
        if who is None:
            nearest = 1e9
            for name in names:
                d, _t = seg_dist(v.co, *SEG[name])
                if d < nearest and not name.startswith("hammer"):
                    nearest, who = d, name
            if nearest >= SEED.get(who, 0.014):
                who = None
        if who is not None:
            best[v.index] = 0.0
            lab[v.index] = idx[who]
            heapq.heappush(heap, (0.0, v.index))
    seeded = sum(1 for l in lab if l >= 0)
    while heap:
        d, v = heapq.heappop(heap)
        if d > best[v]:
            continue
        for u, w in adj[v]:
            nd = d + w
            if nd < best[u]:
                best[u] = nd
                lab[u] = lab[v]
                heapq.heappush(heap, (nd, u))
    # A loose piece no seed reached: the bone nearest it.
    loose = 0
    for v in me.vertices:
        if lab[v.index] < 0:
            loose += 1
            lab[v.index] = min(range(len(names)), key=lambda i: seg_dist(v.co, *SEG[names[i]])[0])
    log("labels: %d seeded of %d, %d unreached" % (seeded, n, loose))
    return names, lab


def soft_weights(me, adj, names, lab):
    """One-hot labels, smoothed across each joint by that joint's own width."""
    import numpy as np
    n = len(me.vertices)
    k = len(names)
    W = np.zeros((n, k), dtype=np.float32)
    W[np.arange(n), np.array(lab)] = 1.0
    idx = {nm: i for i, nm in enumerate(names)}
    ea, eb = [], []
    for v, nb in enumerate(adj):
        for u, _d in nb:
            if not fused(names[lab[v]], names[lab[u]]):
                ea.append(v)
                eb.append(u)
    ea, eb = np.array(ea), np.array(eb)
    cnt = np.bincount(ea, minlength=n).astype(np.float32)
    cnt[cnt == 0] = 1.0
    lab = np.array(lab)

    def step(mask):
        s = np.zeros_like(W)
        np.add.at(s, ea, W[eb])
        s /= cnt[:, None]
        W[mask] = W[mask] * 0.5 + s[mask] * 0.5

    # Every joint a little; the wide ones more, only on their own bones' vertices.
    all_v = np.ones(n, dtype=bool)
    for _ in range(SOFT_DEFAULT):
        step(all_v)
    for (a, b), steps in SOFT.items():
        for _ in range(steps - SOFT_DEFAULT):
            pair = np.zeros(k, dtype=bool)
            pair[idx[a]] = True
            pair[idx[b]] = True
            mask = np.isin(lab, [idx[a], idx[b]])
            # Only what is already shared between these two moves.
            mask &= (W[:, ~pair].sum(1) < 1e-3)
            step(mask)
    return W


def fused(a, b):
    """A hammer and a leg with a surface between them? The left head's corner has grown
    into the shin: at the source they are one surface."""
    for x, y in ((a, b), (b, a)):
        if x.startswith("hammer") and y.split(".")[0] in ("thigh", "shin", "foot", "toe"):
            return True
    return False


def part_hammers(ob, names, lab):
    """Takes the faces of such a join away, so nothing stretches between them. What they
    leave is a hole a few centimetres across, on the inside of the shin."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    gone = [f for f in bm.faces if any(fused(names[lab[a.index]], names[lab[b.index]]) for a in f.verts for b in f.verts)]
    bmesh.ops.delete(bm, geom=gone, context='FACES')
    bm.to_mesh(ob.data)
    bm.free()
    log("parted %d faces" % len(gone))


def assign_weights(ob, arm, names, W):
    import numpy as np
    groups = {b.name: ob.vertex_groups.new(name=b.name) for b in arm.data.bones}
    n, k = W.shape
    for i in range(n):
        order = np.argsort(-W[i])[:4]
        tot = float(W[i][order].sum())
        for j in order:
            w = float(W[i][j])
            if w > 0.01:
                groups[names[j]].add([i], w / tot, 'REPLACE')
    m = ob.modifiers.new("Rig", 'ARMATURE')
    m.object = arm
    ob.parent = arm


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    no_bake = "--no-bake" in argv
    bpy.ops.wm.read_factory_settings(use_empty=True)
    hi = load_source()
    low = decimate(hi)
    if not no_bake:
        images()
        bake_normal(hi, low)
    bpy.data.objects.remove(hi)
    core, glow = final_materials()
    low.data.materials.clear()
    low.data.materials.append(core)
    arm = build_armature()
    me = low.data
    adj = graph(me)
    names, lab = labels(me, adj)
    W = soft_weights(me, adj, names, lab)
    assign_weights(low, arm, names, W)
    part_hammers(low, names, lab)
    # The eyes, on the head alone.
    eyes = add_eyes(low)
    eyes.data.materials.append(glow)
    g = eyes.vertex_groups.new(name="head")
    g.add(list(range(len(eyes.data.vertices))), 1.0, 'REPLACE')
    activate(low)
    eyes.select_set(True)
    bpy.ops.object.join()
    body = low
    body.name = body.data.name = "ProelBuilderBody"
    # The source's meshes, materials and 4096 maps stay out of the .blend.
    for m in list(bpy.data.materials):
        if m not in (core, glow):
            bpy.data.materials.remove(m)
    bpy.data.orphans_purge(do_recursive=True)
    for img in list(bpy.data.images):
        if img.name.startswith("rusted") or img.name.startswith("bake_") or img.name.endswith("_s"):
            bpy.data.images.remove(img)
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    log("body %d tris, %d verts" % (tris, len(body.data.vertices)))
    bpy.context.view_layer.update()
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "proel_builder.blend"), compress=True)
    log("wrote the .blend")


if __name__ == "__main__":
    main()
