"""The scout's ForgeGUI look (note 188): the body ForgeGUI generated and rigged
(Meshy), and its spear, fitted onto the scout's OWN procedural rig
(scout_body.gd BONES), so every scout animation drives it unchanged.

    blender -b --factory-startup -P tools/build_scout_forge.py
    blender -b --factory-startup -P tools/build_scout_forge.py -- --preview <dir>
    godot --headless --import --path .

Reads models/source/scout_forge/body_v1_rigged.glb (the body, rigged by
ForgeGUI) and spear_v1.glb. Writes models/scout_forge.glb (the skinned body on
the scout's 31 bones, its eye lenses as the surface `ScoutGlow`, and the spear)
and scripts/scout_forge_binds.gd. Never hand-edit either; rebuild.

How it fits. The generation stands in an A-pose with its own joints. Its skin
weights are kept (Meshy's bones summed onto the scout's), and each scout bone
gets an affine map from the generation's pose to the scout's rest (identity
orientations at BONES): the whole body is scaled once (SCALE) so the shoulders
and hip sockets land on the rig's; each limb bone is turned from its A-pose
direction to the rig's straight-down one, about its own joint, and stretched
along its length to the rig's bone length; the fist is placed so the shaft runs
through it where the rig holds the spear. scout_body.gd `_binds` multiplies
those maps into the skin's binds, so the mesh is drawn exactly as generated
whenever the rig is posed as the generation stands, with no second skinning
pass. Everything is worked in GODOT axes (x right, y up, z back); Blender is
(x, -z, y).
"""
import bpy, bmesh, os, sys, math
import numpy as np
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "models", "source", "scout_forge")
BODY = os.path.join(SRC, "body_v1_rigged.glb")
SPEAR = os.path.join(SRC, "spear_v1.glb")
OUT = os.path.join(ROOT, "models", "scout_forge.glb")
BINDS = os.path.join(ROOT, "scripts", "scout_forge_binds.gd")

# As scout_body.gd.
SPEAR_TIP = 1.80
SPEAR_BUTT = 0.60
STRANDS = 7
STRAND_SPAN = 120.0
GRIP_OFF = 0.07
BONES = [
    ("Hips", None, (0.0, 0.98, 0.0)),
    ("Spine", "Hips", (0.0, 1.08, 0.0)),
    ("Chest", "Spine", (0.0, 1.28, 0.0)),
    ("Neck", "Chest", (0.0, 1.49, 0.0)),
    ("Head", "Neck", (0.0, 1.58, 0.0)),
    ("UpperArmR", "Chest", (0.21, 1.45, 0.0)),
    ("ForearmR", "UpperArmR", (0.21, 1.14, 0.0)),
    ("HandR", "ForearmR", (0.21, 0.85, 0.0)),
    ("UpperArmL", "Chest", (-0.21, 1.45, 0.0)),
    ("ForearmL", "UpperArmL", (-0.21, 1.14, 0.0)),
    ("HandL", "ForearmL", (-0.21, 0.85, 0.0)),
    ("ThighR", "Hips", (0.11, 0.93, 0.0)),
    ("ShinR", "ThighR", (0.11, 0.50, 0.0)),
    ("FootR", "ShinR", (0.11, 0.08, 0.0)),
    ("ThighL", "Hips", (-0.11, 0.93, 0.0)),
    ("ShinL", "ThighL", (-0.11, 0.50, 0.0)),
    ("FootL", "ShinL", (-0.11, 0.08, 0.0)),
]
REST = {n: np.array(p) for n, _, p in BONES}

# The generation's bones onto the scout's. Meshy's "Left" is the figure's own
# left, which (turned to face -Z) is the scout's L, at -x.
MAP = {
    "Hips": "Hips", "Spine02": "Spine", "Spine01": "Chest", "Spine": "Chest",
    "LeftShoulder": "Chest", "RightShoulder": "Chest",
    "neck": "Neck", "Head": "Head", "head_end": "Head", "headfront": "Head",
    "LeftArm": "UpperArmL", "LeftForeArm": "ForearmL", "LeftHand": "HandL",
    "RightArm": "UpperArmR", "RightForeArm": "ForearmR", "RightHand": "HandR",
    "LeftUpLeg": "ThighL", "LeftLeg": "ShinL", "LeftFoot": "FootL", "LeftToeBase": "FootL",
    "RightUpLeg": "ThighR", "RightLeg": "ShinR", "RightFoot": "FootR", "RightToeBase": "FootR",
}
SIDE = {"L": "Left", "R": "Right"}

# The generation is 1.70 m; this brings its shoulders (1.449) and hip sockets
# (0.925) onto the rig's (1.45, 0.93). 1.86 m tall, as the old scout.
SCALE = 1.095
# The fist: where the shaft runs through it, from the fist's centre (metres,
# rig rest axes, mirrored in x for the left), and its turn about the forearm.
FIST_SHIFT = {"R": (0.0, 0.0, 0.0), "L": (0.0, 0.0, 0.0)}
FIST_TWIST = {"R": 0.0, "L": 0.0}
# The eye lenses (found on the goggles, find_lenses): how far in front of the
# glass, how much of the rim's opening they fill, how far they face outward.
LENS = dict(proud=0.008, fill=0.92, splay=0.0)
# Weight clean-up (clean_weights).
THIGH_TOP = 0.04
SMOOTH = 3
# The cowl on the mantle's strands (cowl_weights): cloth is what the ORM map
# calls non-metal (below `metal`) between `low` and `high` on the trunk; it
# hangs free from `top` (nothing) down to `hem` (all of `share`), all of it
# round to `side` degrees from straight behind and none past `front` (over the
# arms and the chest it stays put), and less where an arm holds it too.
COWL = dict(metal=0.25, low=1.10, high=1.62, top=1.46, hem=1.22, share=0.32, side=90.0, front=125.0, smooth=4)
# The dungeon's grade (grade): as generated the plate is dark iron (albedo 0.25)
# at metal 0.6, which is black in this dungeon -- at 3.4 m in a corridor only
# the eyes showed, where the old scout's plate read plainly. The albedo is
# lifted by a gamma and the metal map scaled down (note 134: metal stays low
# here, full metal goes black).
ALBEDO_GAMMA = 1.5
METAL_SCALE = 0.35
BODY_TEX = 2048
SPEAR_TEX = 1024
SPEAR_TRIS = 5000


def log(*a):
    print("[scout_forge]", *a, flush=True)


def to_g(v):
    return np.array((v[0], v[2], -v[1]))


def from_g(g):
    return Vector((g[0], -g[2], g[1]))


def src_to_g(v):
    """A point of the generation (Blender, facing -Y) into rig space: turned
    to face -Z and scaled."""
    return np.array((-v[0], v[2], v[1])) * SCALE


def rot_between(a, b):
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k * (1.0 / (1.0 + c))


def axis_rot(axis, ang):
    m = Matrix.Rotation(ang, 3, Vector(axis))
    return np.array(m)


def affine(lin, src_pt, dst_pt):
    """x -> lin @ (x - src_pt) + dst_pt, as a 3x4."""
    out = np.zeros((3, 4))
    out[:, :3] = lin
    out[:, 3] = dst_pt - lin @ src_pt
    return out


def stretch(d, s):
    """Scale by s along unit direction d."""
    d = d / np.linalg.norm(d)
    return np.eye(3) + (s - 1.0) * np.outer(d, d)


def grade(img, role):
    """The dungeon's grade on a map, in place (ALBEDO_GAMMA, METAL_SCALE)."""
    if role not in ("col", "orm"):
        return
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    if role == "col":
        px[:, :, :3] = np.power(np.clip(px[:, :, :3], 0.0, 1.0), 1.0 / ALBEDO_GAMMA)
    else:
        px[:, :, 2] *= METAL_SCALE
    img.pixels.foreach_set(px.ravel())
    img.update()


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def strand_rest():
    out = []
    for k in range(STRANDS):
        th = math.radians(-STRAND_SPAN + 2.0 * STRAND_SPAN * k / (STRANDS - 1))
        edge = lambda t: Vector((math.sin(t) * 0.41, 1.5 + 0.07 * abs(math.sin(t)), math.cos(t) * 0.29))
        a = abs(math.degrees(th))
        if a <= 90.0:
            ln = 0.72 + (0.42 - 0.72) * math.sin(math.radians(a))
        else:
            ln = 0.42 + (0.26 - 0.42) * min(max((a - 90.0) / 60.0, 0.0), 1.0)
        root = edge(th)
        bottom = root + Vector((math.sin(th) * 0.045, -ln, math.cos(th) * 0.06))
        mid = root.lerp(bottom, 0.5)
        out.append((root, mid))
    return out


def seg_dist(P, a, b):
    d = b - a
    t = np.clip(((P - a) @ d) / max(float(d @ d), 1e-9), 0.0, 1.0)
    return np.linalg.norm(P - (a + t[:, None] * d[None, :]), axis=1)


def weld_edges(P, me):
    """Positions welded across UV seams: each vertex's welded index, the count,
    and the edges between welded points."""
    key = {}
    weld = np.zeros(len(P), dtype=np.int64)
    for v, p in enumerate(np.round(P, 5)):
        weld[v] = key.setdefault(tuple(p), len(key))
    ed = np.array([tuple(e.vertices) for e in me.edges])
    return weld, len(key), weld[ed[:, 0]], weld[ed[:, 1]]


def smooth_over(W, P, me, passes):
    """`W` (a row per vertex) averaged with its neighbours over the surface."""
    weld, m, a, b = weld_edges(P, me)
    for _ in range(passes):
        Wm = np.zeros((m, W.shape[1]))
        np.add.at(Wm, weld, W)
        Wm /= np.bincount(weld, minlength=m)[:, None].astype(float)
        acc = Wm.copy()
        deg = np.ones(m)
        np.add.at(acc, a, Wm[b])
        np.add.at(acc, b, Wm[a])
        np.add.at(deg, a, 1.0)
        np.add.at(deg, b, 1.0)
        Wm = 0.5 * Wm + 0.5 * acc / deg[:, None]
        W = Wm[weld]
    return W


def cowl_weights(mesh, P, W, idx):
    """The cowl's hanging part onto the mantle's strands, so the rig's cloth
    (scout_body.gd `_cloak`) swings it as it swung the old mantle. The
    generation is ONE welded shell and its albedo does not tell hessian from
    iron (0.28 against 0.25), but its metal map does (0.0 against 0.6). A share
    of each cloth vertex, growing down to the hem, goes to the upper bone of
    the two strands either side of it; only a share, since the hem is joined to
    the plate under it. Returns a column per strand."""
    me = mesh.data
    mat = me.materials[0]
    orm = next(l.from_node.image for l in mat.node_tree.links
               if l.to_node.type == "SEPARATE_COLOR" and l.from_node.type == "TEX_IMAGE")
    w, h = orm.size
    px = np.array(orm.pixels[:]).reshape(h, w, 4)
    uv = np.zeros((len(P), 2))
    for l in me.loops:
        uv[l.vertex_index] = me.uv_layers.active.data[l.index].uv
    metal = px[(np.clip(uv[:, 1], 0, 0.9999) * h).astype(int), (np.clip(uv[:, 0], 0, 0.9999) * w).astype(int), 2]
    trunk = W[:, [idx[n] for n in ("Hips", "Spine", "Chest", "Neck")]].sum(axis=1)
    cloth = ((metal < COWL["metal"]) & (P[:, 1] > COWL["low"]) & (P[:, 1] < COWL["high"]) & (trunk > 0.5)).astype(float)
    cloth = smooth_over(cloth[:, None], P, me, COWL["smooth"])[:, 0]
    t = np.clip((COWL["top"] - P[:, 1]) / (COWL["top"] - COWL["hem"]), 0.0, 1.0)
    fall = t * t * (3.0 - 2.0 * t)
    th = np.degrees(np.arctan2(P[:, 0], P[:, 2]))
    round_ = np.clip((COWL["front"] - np.abs(th)) / (COWL["front"] - COWL["side"]), 0.0, 1.0)
    arms = W[:, [idx[n] for n in ("UpperArmR", "UpperArmL", "ForearmR", "ForearmL")]].sum(axis=1)
    share = COWL["share"] * cloth * fall * round_ * np.clip(1.0 - 2.5 * arms, 0.0, 1.0)
    share = smooth_over(share[:, None], P, me, 1)[:, 0]
    pos = (np.clip(th, -STRAND_SPAN, STRAND_SPAN) + STRAND_SPAN) / (2.0 * STRAND_SPAN) * (STRANDS - 1)
    k0 = np.clip(np.floor(pos).astype(int), 0, STRANDS - 2)
    f = pos - k0
    out = np.zeros((len(P), STRANDS))
    rows = np.arange(len(P))
    out[rows, k0] = share * (1.0 - f)
    out[rows, k0 + 1] += share * f
    log("cowl: %d cloth vertices, %d swing (share > 0.05), most %.2f" % (
        int((cloth > 0.5).sum()), int((share > 0.05).sum()), float(share.max())))
    return out


def clean_weights(W, P, J, idx, me):
    """Meshy's weights bleed: a thigh 0.2 at the waist, 22 cm above the hip,
    opened the side of the waist on a stride; the plate hanging between the
    legs was on both thighs and tore as they parted. So a thigh lets go of
    what is above its hip socket (THIGH_TOP) and of the other side of the
    body, both to the hips; then the weights are smoothed over the surface
    (SMOOTH passes, positions welded across UV seams) so no rule leaves a step
    for the skin to tear along. (Pruning by distance and sharpening were
    tried first: they made steps, and edges opened tenfold.)"""
    W = W.copy()
    hips = idx["Hips"]
    for s, side in SIDE.items():
        i = idx["Thigh" + s]
        top = J[side + "UpLeg"][1] + THIGH_TOP
        sx = J[side + "UpLeg"][0]
        wrong = (P[:, 1] > top) | (P[:, 0] * np.sign(sx) < -0.01)
        W[wrong, hips] += W[wrong, i]
        W[wrong, i] = 0.0
    W = smooth_over(W, P, me, SMOOTH)
    W[W < 0.01] = 0.0
    W /= W.sum(axis=1, keepdims=True)
    log("weights: thighs held below their sockets + %.2f m, smoothed %d passes" % (THIGH_TOP, SMOOTH))
    return W


def body():
    objs = import_glb(BODY)
    arm = next(o for o in objs if o.type == "ARMATURE")
    mesh = next(o for o in objs if o.type == "MESH" and len(o.vertex_groups) > 0)
    for o in objs:
        if o not in (arm, mesh):
            bpy.data.objects.remove(o)
    # Joints, rig space.
    J = {}
    for b in arm.data.bones:
        J[b.name] = src_to_g(arm.matrix_world @ b.head_local)
        J[b.name + ":tail"] = src_to_g(arm.matrix_world @ b.tail_local)
    mw = mesh.matrix_world.copy()
    me = mesh.data
    n = len(me.vertices)
    P = np.array([src_to_g(mw @ v.co) for v in me.vertices])

    # Weights onto the scout's bones.
    names = [n_ for n_, _, _ in BONES]
    idx = {n_: i for i, n_ in enumerate(names)}
    gname = {g.index: g.name for g in mesh.vertex_groups}
    W = np.zeros((n, len(names)))
    unmapped = set()
    for v in me.vertices:
        for g in v.groups:
            src = gname[g.group]
            if src not in MAP:
                unmapped.add(src)
                continue
            W[v.index, idx[MAP[src]]] += g.weight
    if unmapped:
        log("unmapped groups:", sorted(unmapped))
    W = clean_weights(W, P, J, idx, me)
    # The cowl's share on the mantle's strands, taken from what holds it now.
    Wc = cowl_weights(mesh, P, W, idx)
    W = np.hstack([W * (1.0 - Wc.sum(axis=1, keepdims=True)), Wc])
    for k in range(STRANDS):
        idx["Cloak%dA" % k] = len(names)
        names.append("Cloak%dA" % k)
    # Four strongest, normalised.
    for i in range(n):
        row = W[i]
        if np.count_nonzero(row) > 4:
            keep = np.argsort(row)[-4:]
            mask = np.zeros_like(row)
            mask[keep] = 1.0
            row *= mask
        s = row.sum()
        if s <= 0.0:
            row[idx["Chest"]] = 1.0
        else:
            row /= s
    log("verts %d; joints: shoulder R %s L %s, hip R %s L %s" % (
        n, np.round(J["RightArm"], 3), np.round(J["LeftArm"], 3), np.round(J["RightUpLeg"], 3), np.round(J["LeftUpLeg"], 3)))

    # The maps, one per bone.
    A = {}
    down = np.array((0.0, -1.0, 0.0))
    for nm in ("Hips", "Spine", "Chest", "Neck", "Head"):
        A[nm] = affine(np.eye(3), np.zeros(3), np.zeros(3))
    for s, side in SIDE.items():
        # Arms: shoulder -> elbow -> wrist straightened down, each stretched to
        # the rig's length.
        sh, el, wr = J[side + "Arm"], J[side + "ForeArm"], J[side + "Hand"]
        r_sh, r_el, r_wr = REST["UpperArm" + s], REST["Forearm" + s], REST["Hand" + s]
        for nm, a, b, ra, rb in (("UpperArm" + s, sh, el, r_sh, r_el), ("Forearm" + s, el, wr, r_el, r_wr)):
            d = b - a
            lin = rot_between(d, rb - ra) @ stretch(d, np.linalg.norm(rb - ra) / np.linalg.norm(d))
            A[nm] = affine(lin, a, ra)
            log("%s: mesh %.3f -> rig %.3f (x%.3f)" % (nm, np.linalg.norm(d), np.linalg.norm(rb - ra), np.linalg.norm(rb - ra) / np.linalg.norm(d)))
        # The fist: its centre onto the grip, GRIP_OFF below the wrist; turned
        # as the forearm, then so the wrist is straight above it.
        hand = W[:, idx["Hand" + s]] > 0.6
        c = P[hand].mean(axis=0)
        mx = np.array((1.0 if s == "R" else -1.0, 1.0, 1.0))
        lin_f = A["Forearm" + s][:, :3]
        lin = rot_between(lin_f @ (c - wr), down) @ lin_f
        lin = lin / np.cbrt(np.linalg.det(lin))
        lin = axis_rot((0.0, 1.0, 0.0), FIST_TWIST[s] * (1.0 if s == "R" else -1.0)) @ lin
        grip = r_wr + down * GRIP_OFF + np.array(FIST_SHIFT[s]) * mx
        A["Hand" + s] = affine(lin, c, grip)
        log("Hand%s: fist centre %.3f from the wrist (rig %.3f)" % (s, np.linalg.norm(c - wr), GRIP_OFF))
        # Legs: hip -> knee -> the ankle's pivot, ANKLE above the floor (the
        # generation's ankle joint is higher; what is below the pivot is foot).
        hp, kn, an = J[side + "UpLeg"], J[side + "Leg"], J[side + "Foot"]
        r_hp, r_kn, r_an = REST["Thigh" + s], REST["Shin" + s], REST["Foot" + s]
        d_sh = an - kn
        piv = kn + d_sh * ((kn[1] - r_an[1]) / (kn[1] - an[1]))
        for nm, a, b, ra, rb in (("Thigh" + s, hp, kn, r_hp, r_kn), ("Shin" + s, kn, piv, r_kn, r_an)):
            d = b - a
            lin = rot_between(d, rb - ra) @ stretch(d, np.linalg.norm(rb - ra) / np.linalg.norm(d))
            A[nm] = affine(lin, a, ra)
            log("%s: mesh %.3f -> rig %.3f (x%.3f)" % (nm, np.linalg.norm(d), np.linalg.norm(rb - ra), np.linalg.norm(rb - ra) / np.linalg.norm(d)))
        # The foot: rigid, its pivot onto the rig's ankle, the toes turned
        # straight forward (the stance turns them out itself).
        foot = (W[:, idx["Foot" + s]] > 0.6) & (P[:, 1] < piv[1] + 0.02)
        fp = P[foot]
        toe = fp[np.argmin(fp[:, 2])]
        heel = fp[np.argmax(fp[:, 2])]
        fwd = toe - heel
        fwd[1] = 0.0
        yaw = math.atan2(fwd[0], -fwd[2])
        lin = axis_rot((0.0, 1.0, 0.0), yaw)
        A["Foot" + s] = affine(lin, piv, r_an)
        log("Foot%s: toes out %.1f deg, pivot %s" % (s, math.degrees(yaw), np.round(piv, 3)))

    # The strands: the rig turns each from straight down to where it hangs
    # (scout_body.gd `_cloak`, `_swing`), at rest too; its map turns it back, so
    # the cowl hangs as generated.
    for k, (root, mid) in enumerate(strand_rest()):
        root, mid = np.array(root), np.array(mid)
        A["Cloak%dA" % k] = affine(rot_between(mid - root, down), root, root)

    # Where the mesh is when the rig stands at rest (for the preview and the
    # lenses).
    R = np.zeros_like(P)
    Ph = np.hstack([P, np.ones((n, 1))])
    for nm, i in idx.items():
        w = W[:, i]
        if not w.any():
            continue
        R += w[:, None] * (Ph @ A[nm].T)
    return mesh, arm, P, W, A, R, names


def find_lenses(mesh, P):
    """The goggles, found on the generation: rays from in front over the face,
    the brass rims picked out by the albedo under each hit. Returns, per side,
    the glass's centre and the rim's inner radius."""
    from mathutils.bvhtree import BVHTree
    from mathutils.geometry import barycentric_transform
    me = mesh.data
    verts = [Vector(p) for p in P]
    polys = [tuple(p.vertices) for p in me.polygons]
    bvh = BVHTree.FromPolygons(verts, polys)
    uv = me.uv_layers.active.data
    img = next(nd.image for nd in me.materials[0].node_tree.nodes
               if nd.type == "TEX_IMAGE" and nd.image and any(
                   l.from_node == nd and l.to_socket.name.lower() == "base color" for l in me.materials[0].node_tree.links))
    w, h = img.size
    px = np.array(img.pixels[:]).reshape(h, w, 4)
    head_top = P[:, 1].max()
    hits = []
    for y in np.arange(head_top - 0.30, head_top - 0.02, 0.003):
        for x in np.arange(-0.14, 0.14, 0.003):
            loc, nrm, fi, dist = bvh.ray_cast(Vector((x, y, -1.0)), Vector((0.0, 0.0, 1.0)))
            if loc is None:
                continue
            poly = me.polygons[fi]
            vi = list(poly.vertices)
            li = list(poly.loop_indices)
            tri = None
            for k in range(1, len(vi) - 1):
                a, b, c = (verts[vi[0]], verts[vi[k]], verts[vi[k + 1]])
                tri = (0, k, k + 1)
                bc = barycentric_transform(loc, a, b, c, Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
                if min(bc) >= -0.01:
                    break
            u = sum(bc[j] * uv[li[tri[j]]].uv[0] for j in range(3))
            v = sum(bc[j] * uv[li[tri[j]]].uv[1] for j in range(3))
            col = px[int(np.clip(v, 0, 0.9999) * h), int(np.clip(u, 0, 0.9999) * w)]
            hits.append((x, y, loc.z, col[0], col[1], col[2]))
    H = np.array(hits)
    brass = (H[:, 3] - H[:, 5] > 0.12) & (H[:, 3] > 0.22) & (H[:, 3] > H[:, 4])
    out = {}
    for side, sel in (("R", H[:, 0] > 0.012), ("L", H[:, 0] < -0.012)):
        b = H[brass & sel]
        # The rims are the brass highest on the face: the ear gears sit out at
        # the sides, behind.
        b = b[np.abs(b[:, 0]) < 0.08]
        cx, cy = np.median(b[:, 0]), np.median(b[:, 1])
        for _ in range(3):
            r = np.hypot(b[:, 0] - cx, b[:, 1] - cy)
            keep = r < 0.06
            cx, cy = b[keep, 0].mean(), b[keep, 1].mean()
        r = np.hypot(b[:, 0] - cx, b[:, 1] - cy)
        inner = float(np.percentile(r[r < 0.06], 20))
        # The glass at the centre.
        c = H[(np.hypot(H[:, 0] - cx, H[:, 1] - cy) < inner * 0.5)]
        z = float(np.median(c[:, 2])) if len(c) else float(b[:, 2].min())
        out[side] = (np.array((cx, cy, z)), inner)
        log("lens %s: centre %s, inner radius %.3f" % (side, np.round(out[side][0], 3), inner))
    return out


def lenses(A, found):
    """Two glowing discs set in the goggles, on the head (`ScoutGlow`)."""
    verts, faces = [], []
    seg = 20
    for side, s in (("R", 1.0), ("L", -1.0)):
        cen, rad = found[side]
        cen = cen + np.array((0.0, 0.0, -LENS["proud"]))
        nrm = np.array((s * math.sin(LENS["splay"]), 0.0, -math.cos(LENS["splay"])))
        u = np.cross(nrm, (0.0, 1.0, 0.0))
        u /= np.linalg.norm(u)
        v = np.cross(u, nrm)
        base = len(verts)
        verts.append(cen)
        for k in range(seg):
            a = math.tau * k / seg
            verts.append(cen + (u * math.cos(a) + v * math.sin(a)) * rad * LENS["fill"])
        for k in range(seg):
            # u, v, nrm is the same handed frame on both sides: one winding.
            # (Flipping the left one drew it facing into the head: no glow.)
            faces.append([base, base + 1 + (k + 1) % seg, base + 1 + k])
    # Rig rest -> generation space through the head's map (identity here).
    lin = A["Head"][:, :3]
    t = A["Head"][:, 3]
    inv = np.linalg.inv(lin)
    return [inv @ (p - t) for p in verts], faces


def build_body(preview):
    mesh, arm, P, W, A, R, names = body()
    me = mesh.data
    # The body in rig space (the generation's pose), as Blender coordinates.
    for i, v in enumerate(me.vertices):
        v.co = from_g(R[i] if preview else P[i])
    mesh.parent = None
    mesh.matrix_world = Matrix.Identity(4)
    me.update()
    if me.has_custom_normals and not preview:
        pass
    # The lenses.
    lv, lf = lenses(A, find_lenses(mesh, P))
    if preview:
        lv = [lenses_rest for lenses_rest in lenses_rest_points(lv, A)]
    glow = bpy.data.materials.new("ScoutGlow")
    glow.use_nodes = True
    bsdf = glow.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.02, 0.12, 0.14, 1.0)
    bsdf.inputs["Emission Color"].default_value = (0.0, 0.91, 1.0, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 3.0
    gm = bpy.data.meshes.new("Lenses")
    gm.from_pydata([from_g(p) for p in lv], [], lf)
    gm.materials.append(glow)
    gob = bpy.data.objects.new("Lenses", gm)
    bpy.context.scene.collection.objects.link(gob)
    # Names.
    mat = me.materials[0]
    mat.name = "ScoutForge"
    for nd in mat.node_tree.nodes:
        if nd.type == "TEX_IMAGE" and nd.image:
            img = nd.image
            role = "nor" if "normal" in img.name.lower() else None
            for link in mat.node_tree.links:
                if link.from_node == nd and role is None:
                    sock = link.to_socket.name.lower()
                    role = "col" if sock == "base color" else "orm"
            img.name = "scout_forge_" + (role or "tex")
            if img.size[0] > BODY_TEX:
                img.scale(BODY_TEX, BODY_TEX)
            grade(img, role)
    # Weights, replaced by the scout's bones.
    mesh.modifiers.clear()
    for g in list(mesh.vertex_groups):
        mesh.vertex_groups.remove(g)
    groups = {nm: mesh.vertex_groups.new(name=nm) for nm in names}
    for i in range(len(me.vertices)):
        for j in np.nonzero(W[i])[0]:
            groups[names[j]].add([i], float(W[i, j]), "REPLACE")
    # The lenses joined in, all on the head.
    hg = gob.vertex_groups.new(name="Head")
    hg.add(list(range(len(gm.vertices))), 1.0, "REPLACE")
    bpy.ops.object.select_all(action="DESELECT")
    mesh.select_set(True)
    gob.select_set(True)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.join()
    mesh.name = me.name = "ScoutForge"
    bpy.data.objects.remove(arm)
    return mesh, A, names


def lenses_rest_points(lv, A):
    lin = A["Head"][:, :3]
    t = A["Head"][:, 3]
    return [lin @ p + t for p in lv]


def build_rig(mesh):
    data = bpy.data.armatures.new("ScoutRig")
    arm = bpy.data.objects.new("ScoutRig", data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = data.edit_bones

    def add(name, parent, p):
        b = eb.new(name)
        b.head = p
        b.tail = p + Vector((0.0, 0.06, 0.0))
        b.roll = 0.0
        b.use_connect = False
        if parent:
            b.parent = eb[parent]

    for name, parent, g in BONES:
        add(name, parent, from_g(g))
    for k, (root, mid) in enumerate(strand_rest()):
        add("Cloak%dA" % k, "Chest", from_g(root))
        add("Cloak%dB" % k, "Cloak%dA" % k, from_g(mid))
    bpy.ops.object.mode_set(mode="OBJECT")
    mod = mesh.modifiers.new("Rig", "ARMATURE")
    mod.object = arm
    mesh.parent = arm
    return arm


def build_spear():
    objs = import_glb(SPEAR)
    meshes = [o for o in objs if o.type == "MESH"]
    for o in objs:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    sp = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = sp.data
    P = np.array([tuple(v.co) for v in me.vertices])
    # The long axis, and which end is the head (the wider end).
    ax = int(np.argmax(P.max(axis=0) - P.min(axis=0)))
    lo, hi = P[:, ax].min(), P[:, ax].max()
    length = hi - lo
    t = (P[:, ax] - lo) / length
    others = [a for a in range(3) if a != ax]
    def width(sel):
        q = P[sel][:, others]
        return float((q.max(axis=0) - q.min(axis=0)).max()) if len(q) else 0.0
    head_hi = width(t > 0.85) > width(t < 0.15)
    # The shaft's centre line, from its middle.
    mid = P[(t > 0.4) & (t < 0.6)][:, others]
    centre = (mid.max(axis=0) + mid.min(axis=0)) * 0.5
    s = (SPEAR_TIP + SPEAR_BUTT) / length
    for v in me.vertices:
        p = np.array(tuple(v.co))
        along = (p[ax] - lo) if head_hi else (hi - p[ax])
        off = (p[others] - centre) * s
        # Spear frame (Godot): point along -Z, rear grip at 0.
        gz = SPEAR_BUTT - along * s
        g = np.array((off[0], off[1], gz))
        v.co = from_g(g)
    me.update()
    # Shaft radius, for the record.
    q = np.array([tuple(v.co) for v in me.vertices])
    sel = np.abs(q[:, 1] - 0.0) < 0.05
    log("spear: %.3f m long -> %.2f (x%.3f), head at %s end, shaft radius %.3f m" % (
        length, SPEAR_TIP + SPEAR_BUTT, s, "high" if head_hi else "low", float(np.abs(q[sel][:, [0, 2]]).max())))
    if me.has_custom_normals:
        bpy.context.view_layer.objects.active = sp
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    if tris > SPEAR_TRIS:
        mod = sp.modifiers.new("dec", "DECIMATE")
        mod.ratio = SPEAR_TRIS / tris
        mod.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = sp
        bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.select_all(action="DESELECT")
    sp.select_set(True)
    bpy.context.view_layer.objects.active = sp
    bpy.ops.object.shade_auto_smooth(angle=math.radians(40.0))
    mat = me.materials[0]
    mat.name = "ScoutForgeSpear"
    for nd in mat.node_tree.nodes:
        if nd.type == "TEX_IMAGE" and nd.image:
            img = nd.image
            role = "nor" if "normal" in img.name.lower() else None
            for link in mat.node_tree.links:
                if link.from_node == nd and role is None:
                    role = "col" if link.to_socket.name.lower() == "base color" else "orm"
            img.name = "scout_forge_spear_" + (role or "tex")
            if img.size[0] > SPEAR_TEX:
                img.scale(SPEAR_TEX, SPEAR_TEX)
            grade(img, role)
    sp.name = me.name = "ScoutForgeSpear"
    log("spear: %d tris" % sum(len(p.vertices) - 2 for p in me.polygons))
    return sp


def write_binds(A, names):
    lines = [
        "## Generated by tools/build_scout_forge.py (note 188). Never hand-edit; rebuild.",
        "## Each scout bone's map from the ForgeGUI scout's own pose (its mesh, model",
        "## space) to the rig's rest; scout_body.gd `_binds` puts it in the skin.",
        "extends RefCounted",
        "",
        "const MAPS := {",
    ]
    for nm in names:
        m = A[nm]
        cols = [m[:, 0], m[:, 1], m[:, 2], m[:, 3]]
        lines.append('\t"%s": Transform3D(%s),' % (nm, ", ".join(
            "Vector3(%.6f, %.6f, %.6f)" % tuple(c) for c in cols)))
    lines.append("}")
    with open(BINDS, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    log("wrote", BINDS)


def preview_scene(out_dir, mesh, spear):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = "GPU"
    except Exception as e:
        log("cpu render", e)
    sc.render.resolution_x, sc.render.resolution_y = 800, 1000
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("Prev")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.06, 1.0)
    sc.world = world
    for name, loc, power in (("Key", (2.0, 2.4, 2.6), 160.0), ("Fill", (-2.6, 1.6, 1.4), 60.0), ("Rim", (0.4, -3.0, 2.2), 120.0)):
        ld = bpy.data.lights.new(name, "POINT")
        ld.energy = power
        l = bpy.data.objects.new(name, ld)
        l.location = loc
        sc.collection.objects.link(l)
    cd = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    os.makedirs(out_dir, exist_ok=True)
    # Blender: the scout faces +Y.
    views = (("front", Vector((0.0, 4.2, 1.0)), Vector((0, 0, 0.95)), 50.0),
             ("q", Vector((1.9, 3.3, 1.5)), Vector((0, 0, 0.95)), 50.0),
             ("side", Vector((4.2, 0.0, 1.0)), Vector((0, 0, 0.95)), 50.0),
             ("back", Vector((-1.8, -3.4, 1.5)), Vector((0, 0, 0.95)), 50.0),
             ("head", Vector((0.0, 1.0, 1.72)), Vector((0, 0, 1.68)), 85.0),
             ("handR", Vector((0.9, 0.7, 0.9)), Vector((0.21, 0.0, 0.79)), 85.0),
             ("handL", Vector((-0.9, 0.7, 0.9)), Vector((-0.21, 0.0, 0.79)), 85.0),
             ("feet", Vector((0.6, 1.1, 0.4)), Vector((0.0, 0.0, 0.08)), 60.0))
    for name, loc, at, lens in views:
        cam.location = loc
        cd.lens = lens
        cam.rotation_euler = (at - loc).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(out_dir, name + ".png")
        bpy.ops.render.render(write_still=True)
        log("rendered", name)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    mesh, A, names = build_body(preview is not None)
    spear = build_spear()
    if preview:
        # A spear through each fist where the rig holds it at rest: the shaft
        # along z through the grip.
        for s, x in (("R", 0.21), ("L", -0.21)):
            dup = spear.copy()
            dup.data = spear.data
            sc = bpy.context.scene.collection
            sc.objects.link(dup)
            dup.matrix_world = Matrix.Translation(from_g((x, 0.85 - GRIP_OFF, 0.0)))
        bpy.data.objects.remove(spear)
        preview_scene(preview, mesh, None)
        return
    build_rig(mesh)
    write_binds(A, names)
    bpy.ops.object.select_all(action="DESELECT")
    for o in bpy.data.objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects["ScoutRig"]
    bpy.ops.export_scene.gltf(
        filepath=OUT, export_format="GLB", use_selection=True, export_animations=False,
        export_skins=True, export_def_bones=False, export_yup=True, export_apply=False,
        export_image_format="JPEG", export_image_quality=90, export_tangents=True,
    )
    log("wrote", OUT, os.path.getsize(OUT))


if __name__ == "__main__":
    main()
