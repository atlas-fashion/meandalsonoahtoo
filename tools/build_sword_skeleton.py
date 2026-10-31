"""The sword skeleton's body (note 136), from the user's rusty metal golem.

    blender -b --factory-startup -P tools/build_sword_skeleton.py                 (all of it)
    blender -b --factory-startup -P tools/build_sword_skeleton.py -- --no-bake    (old normal map)

Writes models/source/sword_skeleton/sword_skeleton.blend (mesh, rig, materials)
and its maps. tools/anim_sword_skeleton.py then opens that .blend, writes every
animation and exports models/sword_skeleton.glb.

The source is the Tripo model models/source/sword_skeleton/rusty metal golem 3d
model.glb: 1.94 million triangles, 0.98 m tall, no rig, one surface cut into 375
UV charts. Here it is:

    SQUARED UP   scaled to 2.2 m, the hips over the origin, and turned 28 degrees:
                 the model stands turned to its right, and in this frame the hips
                 and shoulders lie across X.
    WELDED       along every chart's border, or decimating leaves slits between
                 charts. The UVs are per corner, so the charts stay charts.
    CUT DOWN     to TRIS, the left hand and the mask spared. The model's own UVs
                 and its 4096 colour and metal maps carry straight over.
    BAKED        only the normal map changes: the 1.94 million triangles and their
                 own normal map, onto the low mesh's tangent space, ATLAS square.
    RIGGED       watershed from each bone along the surface (`labels`), so a rib
                 stays with the chest however near the upper arm comes, then a few
                 steps of smoothing across each joint: this is plate and pin, and
                 it should not bend like skin.

The blade grows out of the right forearm: there is no right hand. `hand.R` is the
wrist inside its iron ring and `blade` runs on down it.

Blender's frame here: X the skeleton's LEFT, -Y its front, Z up. The exporter
makes that glTF's +X left, +Z front, +Y up: the same as
ossuary_skeleton_rigged.glb, so everything written for that rig holds (bone
names, the front, `Model`'s half turn in enemy.tscn).
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
SRC = os.path.join(ROOT, "models", "source", "sword_skeleton")
SOURCE = os.path.join(SRC, "rusty metal golem 3d model.glb")
ATLAS = 2048
TRIS = 42000
# The model's 0.98 m to the old body's 2.2, and where it is put.
SCALE = 2.2 / 0.98
SHIFT = (-0.145, -0.21, 0.0)
YAW = 28.0


def V(x, y, z):
    return Vector((x, y, z))


def log(*a):
    print("[golem]", *a, flush=True)


# The joints, in the squared-up frame: measured by slicing the mesh and off grids
# laid over it. The model stands wide, the sword arm back and the blade forward.
SHOULDER_L, ELBOW_L, WRIST_L = V(0.175, -0.02, 1.81), V(0.34, 0.06, 1.48), V(0.476, -0.02, 1.205)
SHOULDER_R, ELBOW_R, WRIST_R = V(-0.265, -0.015, 1.80), V(-0.35, -0.035, 1.49), V(-0.425, -0.20, 1.15)
HIP_L, KNEE_L, ANKLE_L = V(0.09, -0.009, 1.27), V(0.295, 0.026, 0.78), V(0.452, 0.129, 0.19)
HIP_R, KNEE_R, ANKLE_R = V(-0.09, 0.009, 1.27), V(-0.206, -0.165, 0.795), V(-0.319, -0.028, 0.19)
BALL_L, TOE_L = V(0.59, 0.03, 0.04), V(0.66, -0.03, 0.02)
BALL_R, TOE_R = V(-0.41, -0.18, 0.04), V(-0.463, -0.266, 0.02)
TIP = V(-0.465, -0.97, 0.37)
BLADE_DIR = (TIP - WRIST_R).normalized()
BLADE_LEN = (TIP - WRIST_R).length
PELVIS = V(0, 0, 1.27)
SPINE_1 = V(0.0, 0.0, 1.38)
SPINE_2 = V(-0.01, -0.02, 1.52)
CHEST = V(-0.02, -0.03, 1.66)
NECK = V(-0.01, -0.05, 1.87)
HEAD = V(-0.02, -0.16, 2.0)
# The amber eyes: where they sit in their sockets. The skull is turned 28 degrees
# to its left of the body (the source's front), and it stoops.
EYES = (V(-0.037, -0.305, 2.035), V(0.031, -0.277, 2.047))

# Name, parent, head, tail, (the radius of its seed along the bone, the seed's
# reach along the bone 0..1).
BONES = [
    ("root", None, V(0, 0, 0), V(0, 0, 0.12)),
    ("pelvis", "root", PELVIS, SPINE_1),
    ("spine.01", "pelvis", SPINE_1, SPINE_2),
    ("spine.02", "spine.01", SPINE_2, CHEST),
    ("chest", "spine.02", CHEST, NECK),
    ("neck", "chest", NECK, HEAD),
    ("head", "neck", HEAD, V(-0.03, -0.17, 2.19)),
    ("clavicle.L", "chest", V(0.03, -0.03, 1.82), SHOULDER_L),
    ("upper_arm.L", "clavicle.L", SHOULDER_L, ELBOW_L),
    ("forearm.L", "upper_arm.L", ELBOW_L, WRIST_L),
    ("hand.L", "forearm.L", WRIST_L, V(0.51, -0.055, 1.112)),
    ("clavicle.R", "chest", V(-0.07, -0.03, 1.82), SHOULDER_R),
    ("upper_arm.R", "clavicle.R", SHOULDER_R, ELBOW_R),
    ("forearm.R", "upper_arm.R", ELBOW_R, WRIST_R),
    ("hand.R", "forearm.R", WRIST_R, WRIST_R + BLADE_DIR * 0.05),
    ("blade", "hand.R", WRIST_R + BLADE_DIR * 0.05, TIP),
    ("thigh.L", "pelvis", HIP_L, KNEE_L),
    ("shin.L", "thigh.L", KNEE_L, ANKLE_L),
    ("foot.L", "shin.L", ANKLE_L, BALL_L),
    ("toe.L", "foot.L", BALL_L, TOE_L),
    ("thigh.R", "pelvis", HIP_R, KNEE_R),
    ("shin.R", "thigh.R", KNEE_R, ANKLE_R),
    ("foot.R", "shin.R", ANKLE_R, BALL_R),
    ("toe.R", "foot.R", BALL_R, TOE_R),
    # The claw: knuckle, joint, tip. It hangs half shut, palm in.
    ("f0.L", "hand.L", V(0.47, -0.09, 1.155), V(0.458, -0.12, 1.09)),
    ("f0b.L", "f0.L", V(0.458, -0.12, 1.09), V(0.456, -0.125, 1.03)),
    ("f1.L", "hand.L", V(0.518, -0.095, 1.105), V(0.525, -0.10, 1.035)),
    ("f1b.L", "f1.L", V(0.525, -0.10, 1.035), V(0.47, -0.115, 0.985)),
    ("f2.L", "hand.L", V(0.522, -0.068, 1.105), V(0.53, -0.068, 1.02)),
    ("f2b.L", "f2.L", V(0.53, -0.068, 1.02), V(0.46, -0.075, 0.962)),
    ("f3.L", "hand.L", V(0.52, -0.04, 1.105), V(0.528, -0.04, 1.03)),
    ("f3b.L", "f3.L", V(0.528, -0.04, 1.03), V(0.475, -0.05, 0.975)),
    ("f4.L", "hand.L", V(0.515, -0.012, 1.105), V(0.52, -0.015, 1.04)),
    ("f4b.L", "f4.L", V(0.52, -0.015, 1.04), V(0.47, -0.03, 0.99)),
]
PARENT = {b[0]: b[1] for b in BONES}
SEG = {b[0]: (b[2], b[3]) for b in BONES}
FINGERS = ("f1", "f2", "f3", "f4")
# Each hinge's axis at rest: the pins on the knees, and the plane the arm is bent in
# at the elbow. The animation reads these to know which way a joint folds.
PIN_KNEE_L = V(0.88, 0.47, 0.0)
PIN_KNEE_R = V(1.0, 0.0, 0.0)
# How far a seed reaches out from its bone, and the share of the bone's length it
# leaves bare at the far end, so the joint is where two watersheds meet.
SEED = {"pelvis": 0.11, "spine.01": 0.09, "spine.02": 0.09, "chest": 0.13, "neck": 0.06, "head": 0.12, "clavicle.L": 0.06, "clavicle.R": 0.06,
        "upper_arm.L": 0.06, "forearm.L": 0.05, "hand.L": 0.035, "upper_arm.R": 0.08, "forearm.R": 0.08, "hand.R": 0.035, "blade": 0.05,
        "thigh.L": 0.1, "thigh.R": 0.1, "shin.L": 0.09, "shin.R": 0.09, "foot.L": 0.09, "foot.R": 0.09, "toe.L": 0.05, "toe.R": 0.05}
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
    me.transform(Matrix.Rotation(math.radians(YAW), 4, 'Z') @ Matrix.Translation(SHIFT) @ Matrix.Scale(SCALE, 4))
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


def decimate(hi):
    low = hi.copy()
    low.data = hi.data.copy()
    low.name = "Low"
    bpy.context.scene.collection.objects.link(low)
    activate(low)
    # Evenly to twice the budget; then the fingers and the mask are held where they
    # are while the rest comes down. The group has to be weak on the first pass or
    # it is no pass at all: a held edge costs its length, and every other edge
    # costs next to nothing, so held edges are simply never taken.
    m = low.modifiers.new("Cut", 'DECIMATE')
    m.decimate_type = 'COLLAPSE'
    m.ratio = 2.0 * TRIS / len(low.data.polygons)
    bpy.ops.object.modifier_apply(modifier="Cut")
    g = low.vertex_groups.new(name="keep")
    fingers = [i for i, v in enumerate(low.data.vertices) if v.co.x > 0.42 and v.co.z < 1.2 and v.co.z > 0.93 and -0.16 < v.co.y < 0.03]
    mask = [i for i, v in enumerate(low.data.vertices) if v.co.z > 1.9 and v.co.y < -0.2]
    g.add(fingers + mask, 1.0, 'REPLACE')
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


def add_eyes(low):
    """Two lenses in the sockets, the one thing the texture cannot do: glow."""
    bm = bmesh.new()
    for e in EYES:
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.0105, matrix=Matrix.Translation(e) @ Matrix.Scale(1.0, 4), calc_uvs=False)
    me = bpy.data.meshes.new("Eyes")
    bm.to_mesh(me)
    bm.free()
    me.uv_layers.new(name=low.data.uv_layers[0].name)
    me.shade_smooth()
    ob = bpy.data.objects.new("Eyes", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def images():
    """The source's colour and metal maps, byte for byte: the charts are the same,
    so they carry straight over. The metal map's red is all ones already, so it
    serves as ORM."""
    for img in bpy.data.images:
        name = None
        if img.name.endswith("basecolor.jpg"):
            name = "sword_skeleton_col.jpg"
        elif img.name.endswith("_rm.jpg"):
            name = "sword_skeleton_orm.jpg"
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
    out = bpy.data.images.new("sword_skeleton_nor_s", ATLAS, ATLAS, alpha=False)
    out.colorspace_settings.name = 'Non-Color'
    import numpy as np
    px = np.empty(ATLAS * ATLAS * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    out.pixels.foreach_set(px)
    out.filepath_raw = os.path.join(SRC, "sword_skeleton_nor.png")
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
    t.image = image("sword_skeleton_col")
    L(t.outputs["Color"], p.inputs["Base Color"])
    tn = N("ShaderNodeTexImage")
    tn.image = image("sword_skeleton_nor")
    tn.image.colorspace_settings.name = 'Non-Color'
    nm = N("ShaderNodeNormalMap")
    L(tn.outputs["Color"], nm.inputs["Color"])
    L(nm.outputs[0], p.inputs["Normal"])
    to = N("ShaderNodeTexImage")
    to.image = image("sword_skeleton_orm")
    to.image.colorspace_settings.name = 'Non-Color'
    sp = N("ShaderNodeSeparateColor")
    L(to.outputs["Color"], sp.inputs[0])
    L(sp.outputs[1], p.inputs["Roughness"])
    L(sp.outputs[2], p.inputs["Metallic"])
    mat.use_backface_culling = True
    glow = bpy.data.materials.new("SkelGlow")
    glow.use_nodes = True
    q = next(n for n in glow.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    q.inputs["Base Color"].default_value = (0.4, 0.2, 0.02, 1.0)
    q.inputs["Emission Color"].default_value = (1.0, 0.54, 0.09, 1.0)
    q.inputs["Emission Strength"].default_value = 1.7
    q.inputs["Roughness"].default_value = 0.3
    return mat, glow


def build_armature():
    data = bpy.data.armatures.new("SwordSkeletonRig")
    arm = bpy.data.objects.new("SwordSkeletonRig", data)
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
    """Each vertex's bone: a watershed along the surface from the vertices lying
    close round each bone, so only the joint can pass a bone's territory on."""
    names = [b[0] for b in BONES if b[0] != "root"]
    idx = {n: i for i, n in enumerate(names)}
    n = len(me.vertices)
    best = [1e9] * n
    lab = [-1] * n
    heap = []
    for v in me.vertices:
        nearest, who = 1e9, None
        for name in names:
            a, b = SEG[name]
            d, t = seg_dist(v.co, a, b)
            if name[0] == "f" or name.startswith("hand"):
                r = d
            else:
                # Fingers and hand aside, a bone seeds up to its joint, no further.
                r = d
            if r < nearest:
                nearest, who = r, name
        if who is not None and nearest < SEED.get(who, 0.014):
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
    # The blade and the wrist are one piece of iron; so is each foot's boot.
    return W


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
    # The eyes, on the head alone.
    eyes = add_eyes(low)
    eyes.data.materials.append(glow)
    g = eyes.vertex_groups.new(name="head")
    g.add(list(range(len(eyes.data.vertices))), 1.0, 'REPLACE')
    activate(low)
    eyes.select_set(True)
    bpy.ops.object.join()
    body = low
    body.name = body.data.name = "SwordSkeletonBody"
    # The source's meshes, materials and 4096 maps stay out of the .blend.
    for m in list(bpy.data.materials):
        if m not in (core, glow):
            bpy.data.materials.remove(m)
    bpy.data.orphans_purge(do_recursive=True)
    for img in list(bpy.data.images):
        if img.name.startswith("rusty") or img.name.startswith("bake_") or img.name.endswith("_s"):
            bpy.data.images.remove(img)
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    log("body %d tris, %d verts" % (tris, len(body.data.vertices)))
    bpy.context.view_layer.update()
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "sword_skeleton.blend"), compress=True)
    log("wrote the .blend")


if __name__ == "__main__":
    main()
