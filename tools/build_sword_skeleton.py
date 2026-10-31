"""Builds the sword skeleton's body (note 135) in Blender, from nothing.

    blender -b --factory-startup -P tools/build_sword_skeleton.py                 (all of it)
    blender -b --factory-startup -P tools/build_sword_skeleton.py -- --no-bake    (old maps)
    blender -b --factory-startup -P tools/build_sword_skeleton.py -- --preview <dir> [--no-bake]

Writes models/source/sword_skeleton/sword_skeleton.blend (mesh, rig, materials)
and its maps. tools/anim_sword_skeleton.py then opens that .blend, writes every
animation and exports models/sword_skeleton.glb.

A very tall, gaunt thing, after the user's concept: a patchwork of rusted scale
plate eaten through with holes, over maroon sinew and tan bone. The right arm
and leg are armoured over black struts; the left arm is bare bone and sinew,
ending in a claw; ribs show through the left of the chest. A small bald skull
in a mask of vertical slits, amber eyes, and a long serrated blade.

    CORE    opaque: bone, sinew, struts, the armour that stays whole, the blade
    SHELL   the sheets of scale plate with holes in them (alpha scissor, drawn
            on both sides, no thickness: a hole must go right through)
    GLOW    the eyes and the amber lines in the right arm

Everything is baked from one procedural material on the low mesh itself: the
scales, their rivets and the scale-shaped holes are a Voronoi field in rest
space, so they run across every UV seam.

Blender's frame here: X the skeleton's LEFT, -Y its front, Z up. The exporter
makes that glTF's +X left, +Z front, +Y up: the same as
ossuary_skeleton_rigged.glb, so everything written for that rig holds (bone
names, the front, `Model`'s half turn in enemy.tscn).
"""

import bpy
import bmesh
import math
import os
import random
import sys
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_scout as kit
from build_scout import V, lerp, clamp, smooth, curve

ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "models", "source", "sword_skeleton")
ATLAS = kit.ATLAS

# Joints. Everything else hangs off these.
ANKLE_Z = 0.10
KNEE_Z = 0.63
HIP_Z = 1.16
HIP_X = 0.105
PELVIS_Z = 1.20
SHOULDER_Z = 1.76
SHOULDER_X = 0.235
ELBOW_Z = 1.32
WRIST_Z = 0.88
NECK_Z = 1.78
HEAD_Z = 1.93
# The grip's centre in the right fist, and how far the blade reaches from it.
GRIP = V(-SHOULDER_X, -0.005, 0.795)
BLADE_LEN = 1.16

# Name, parent, head, tail.
BONES = [
    ("root", None, V(0, 0, 0), V(0, 0, 0.12)),
    ("pelvis", "root", V(0, 0, PELVIS_Z), V(0, 0, 1.26)),
    ("spine.01", "pelvis", V(0, 0.01, 1.26), V(0, 0.018, 1.40)),
    ("spine.02", "spine.01", V(0, 0.018, 1.40), V(0, 0.018, 1.54)),
    ("chest", "spine.02", V(0, 0.018, 1.54), V(0, 0.0, NECK_Z)),
    ("neck", "chest", V(0, 0.0, NECK_Z), V(0, -0.015, HEAD_Z)),
    ("head", "neck", V(0, -0.015, HEAD_Z), V(0, -0.015, 2.19)),
    ("clavicle.L", "chest", V(0.04, 0.0, 1.745), V(SHOULDER_X, 0, SHOULDER_Z)),
    ("upper_arm.L", "clavicle.L", V(SHOULDER_X, 0, SHOULDER_Z), V(SHOULDER_X, 0, ELBOW_Z)),
    ("forearm.L", "upper_arm.L", V(SHOULDER_X, 0, ELBOW_Z), V(SHOULDER_X, 0, WRIST_Z)),
    ("hand.L", "forearm.L", V(SHOULDER_X, 0, WRIST_Z), V(SHOULDER_X, 0, 0.80)),
    ("clavicle.R", "chest", V(-0.04, 0.0, 1.745), V(-SHOULDER_X, 0, SHOULDER_Z)),
    ("upper_arm.R", "clavicle.R", V(-SHOULDER_X, 0, SHOULDER_Z), V(-SHOULDER_X, 0, ELBOW_Z)),
    ("forearm.R", "upper_arm.R", V(-SHOULDER_X, 0, ELBOW_Z), V(-SHOULDER_X, 0, WRIST_Z)),
    ("hand.R", "forearm.R", V(-SHOULDER_X, 0, WRIST_Z), V(-SHOULDER_X, 0, 0.80)),
    ("blade", "hand.R", GRIP.copy(), GRIP + V(0, -BLADE_LEN, 0)),
    ("thigh.L", "pelvis", V(HIP_X, 0, HIP_Z), V(HIP_X, 0, KNEE_Z)),
    ("shin.L", "thigh.L", V(HIP_X, 0, KNEE_Z), V(HIP_X, 0, ANKLE_Z)),
    ("foot.L", "shin.L", V(HIP_X, 0, ANKLE_Z), V(HIP_X, -0.17, 0.03)),
    ("toe.L", "foot.L", V(HIP_X, -0.17, 0.03), V(HIP_X, -0.27, 0.03)),
    ("thigh.R", "pelvis", V(-HIP_X, 0, HIP_Z), V(-HIP_X, 0, KNEE_Z)),
    ("shin.R", "thigh.R", V(-HIP_X, 0, KNEE_Z), V(-HIP_X, 0, ANKLE_Z)),
    ("foot.R", "shin.R", V(-HIP_X, 0, ANKLE_Z), V(-HIP_X, -0.17, 0.03)),
    ("toe.R", "foot.R", V(-HIP_X, -0.17, 0.03), V(-HIP_X, -0.27, 0.03)),
]
# The claw's fingers: name, y across the knuckles, length of the near and far
# joints, how far they fan out of line.
FINGERS = [
    ("f1", -0.034, 0.075, 0.105, -0.16),
    ("f2", -0.011, 0.082, 0.118, -0.04),
    ("f3", 0.012, 0.078, 0.112, 0.06),
    ("f4", 0.033, 0.066, 0.094, 0.19),
]
KNUCKLE_Z = 0.795
THUMB = V(SHOULDER_X - 0.018, -0.042, 0.862)


def finger_rest():
    """Each finger's joints, curled a little at rest, as [(bone, head, tail)...]."""
    out = []
    for name, y, l0, l1, fan in FINGERS:
        k = V(SHOULDER_X - 0.004, y, KNUCKLE_Z)
        d0 = V(-0.16, fan * 0.8, -1.0).normalized()
        d1 = V(-0.36, fan * 1.1, -1.0).normalized()
        a = k + d0 * l0
        b = a + d1 * l1
        out.append(("%s.L" % name, k, a))
        out.append(("%sb.L" % name, a, b))
    d0 = V(-0.3, -0.42, -1.0).normalized()
    d1 = V(-0.42, -0.2, -1.0).normalized()
    a = THUMB + d0 * 0.06
    out.append(("f0.L", THUMB, a))
    out.append(("f0b.L", a, a + d1 * 0.085))
    return out


ALL_BONES = list(BONES)
for bn, bh, bt in finger_rest():
    ALL_BONES.append((bn, "hand.L" if not bn[2] == "b" else bn[:2] + ".L", bh, bt))
SEG = {b[0]: (b[2], b[3]) for b in ALL_BONES}
PARENT = {b[0]: b[1] for b in ALL_BONES}


class M:
    """A surface: colour, rust share, metal, roughness; `scale` how much of the
    scale pattern it wears, `flesh` / `bone` how far it is that instead, `hole`
    how eaten through (0 solid, 0.5 half gone, or a function of the point)."""

    def __init__(self, col, rust=0.5, metal=0.5, rough=0.5, scale=1.0, flesh=0.0, bone=0.0, hole=0.0):
        self.col, self.rust, self.metal, self.rough = col, rust, metal, rough
        self.scale, self.flesh, self.bone, self.hole = scale, flesh, bone, hole

    def but(self, **kw):
        out = M(self.col, self.rust, self.metal, self.rough, self.scale, self.flesh, self.bone, self.hole)
        for k, v in kw.items():
            setattr(out, k, v)
        return out


BRONZE = M((0.215, 0.135, 0.078), 0.6, 0.38, 0.52)
BRONZE2 = M((0.145, 0.086, 0.05), 0.7, 0.36, 0.56)
RUST = M((0.112, 0.058, 0.034), 0.82, 0.22, 0.68)
IRON = M((0.075, 0.062, 0.052), 0.35, 0.6, 0.48, scale=0.0)
STRUT = M((0.022, 0.019, 0.017), 0.14, 0.55, 0.42, scale=0.0)
FLESH = M((0.098, 0.018, 0.022), 0.0, 0.0, 0.42, scale=0.0, flesh=1.0)
FLESH2 = M((0.062, 0.012, 0.016), 0.0, 0.0, 0.5, scale=0.0, flesh=1.0)
BONE = M((0.46, 0.35, 0.235), 0.0, 0.0, 0.62, scale=0.0, bone=1.0)
BONE2 = M((0.36, 0.25, 0.155), 0.0, 0.0, 0.68, scale=0.0, bone=1.0)
VOID = M((0.012, 0.009, 0.008), 0.0, 0.1, 0.7, scale=0.0)
BLADE = M((0.32, 0.22, 0.155), 0.7, 0.42, 0.48, scale=0.0)
GLOWM = M((1, 1, 1), 0.0, 0.0, 0.3, scale=0.0)


class Acc(kit.Acc):
    def __init__(self):
        super().__init__()
        self.kind = []

    def push(self, verts, faces, mat, bones, uv=None, luv=None, inner=None, closed=False, holes=None):
        base = len(self.v)
        if closed and kit.signed_volume(verts, faces) < 0.0:
            faces = [list(reversed(f)) for f in faces]
            if luv:
                luv = [list(reversed(l)) if l else None for l in luv]
        pre = self.pre
        jit = RNG.uniform(0.86, 1.12) if mat.flesh == 0.0 and mat.bone == 0.0 else 1.0
        for i, p in enumerate(verts):
            q = pre @ p if pre is not None else p.copy()
            self.v.append(q)
            h = mat.hole(q) if callable(mat.hole) else mat.hole
            if holes is not None:
                h += holes[i]
            self.col.append((mat.col[0] * jit, mat.col[1] * jit, mat.col[2] * jit, mat.rust))
            self.pbr.append((mat.metal, mat.rough, mat.scale, clamp(h)))
            self.kind.append((mat.flesh, mat.bone, 0.0, 1.0))
            self.bones.append(bones(q) if callable(bones) else bones)
        for k, f in enumerate(faces):
            self.f.append([base + i for i in f])
            self.luv.append(luv[k] if luv else None)
            self.inner.append(bool(inner[k]) if inner else False)
            self.fd.append(self.dens)
        if uv is not None:
            self.uv.extend(uv)
        return base


RNG = random.Random(135)
C = Acc()    # core
S = Acc()    # shell
G = Acc()    # glow


def b1(name):
    return [(name, 1.0)]


def seg_dist(p, a, b):
    ab = b - a
    t = clamp((p - a).dot(ab) / max(ab.length_squared, 1e-9))
    return (a + ab * t - p).length


def skin(*names, sharp=0.035):
    """Weights by distance to the named bones: smooth where a strand crosses a
    joint, one bone along its length."""

    def fn(p):
        ds = [seg_dist(p, SEG[n][0], SEG[n][1]) for n in names]
        lo = min(ds)
        ws = [math.exp(-(d - lo) / sharp) for d in ds]
        tot = sum(ws)
        out = [(n, w / tot) for n, w in zip(names, ws) if w / tot > 0.04]
        tot = sum(w for _n, w in out)
        return [(n, w / tot) for n, w in out]

    return fn


# --- Shapes ------------------------------------------------------------------------

def tube(acc, pts, radii, mat, bones, n=7, flat=1.0, side=None, wob=0.0):
    """A closed tube along `pts`; radii per point (0 ends in a point)."""
    t0 = (pts[1] - pts[0]).normalized()
    ref = side if side is not None else (V(1, 0, 0) if abs(t0.x) < 0.9 else V(0, 1, 0))
    s = (ref - t0 * ref.dot(t0)).normalized()
    rings = []
    last = len(pts) - 1
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, last)] - pts[max(i - 1, 0)]).normalized()
        s = (s - t * s.dot(t)).normalized()
        b = t.cross(s)
        r = max(radii[i], 0.0006)
        ring = []
        for k in range(n):
            a = 2.0 * math.pi * k / n
            w = 1.0 + (RNG.uniform(-wob, wob) if wob > 0.0 else 0.0)
            ring.append(p + s * (r * w * math.cos(a)) + b * (r * flat * w * math.sin(a)))
        rings.append(ring)
    kit.loft(acc, rings, mat, bones)


def bez(a, b, c, k):
    return [a.lerp(b, i / k).lerp(b.lerp(c, i / k), i / k) for i in range(k + 1)]


def line(a, b, k):
    return [a.lerp(b, i / k) for i in range(k + 1)]


def long_bone(acc, a, b, mid, end0, end1, mat, bones, n=8, bow=None, k=10, knob=5.0):
    """A long bone: a thin shaft, swelling at each end, a little bowed."""
    bow = bow if bow is not None else V(0, 0, 0)
    pts, rad = [], []
    for i in range(k + 1):
        t = i / k
        pts.append(a.lerp(b, t) + bow * math.sin(t * math.pi))
        e = end0 if t < 0.5 else end1
        r = mid + (e - mid) * abs(2.0 * t - 1.0) ** knob
        if i == 0 or i == k:
            r *= 0.55
        rad.append(r)
    tube(acc, pts, rad, mat, bones, n=n, wob=0.05)


def fibers(acc, a, b, count, spread, r, mat, bones, bulge=0.012, k=5, n=5, side=None, spread_b=None):
    """Sinew: strands from about `a` to about `b`, thick in the middle."""
    d = (b - a).normalized()
    s0 = (side if side is not None else V(0.37, 0.61, 0.13))
    s0 = (s0 - d * s0.dot(d)).normalized()
    s1 = d.cross(s0)
    sb = spread_b if spread_b is not None else spread
    for i in range(count):
        ang = RNG.uniform(0, math.tau)
        rad = math.sqrt(RNG.random())
        ang2 = ang + RNG.uniform(-0.5, 0.5)
        p0 = a + (s0 * math.cos(ang) + s1 * math.sin(ang)) * rad * spread
        p1 = b + (s0 * math.cos(ang2) + s1 * math.sin(ang2)) * rad * sb
        mid = (p0 + p1) * 0.5 + (s0 * math.cos(ang) + s1 * math.sin(ang)) * bulge * RNG.uniform(0.3, 1.3)
        pts = bez(p0, mid, p1, k)
        th = r * RNG.uniform(0.6, 1.25)
        rad_ = [th * (0.3 + 0.7 * math.sin(math.pi * (j / k) ** 0.9)) for j in range(k + 1)]
        tube(acc, pts, rad_, mat, bones, n=n, flat=RNG.uniform(0.6, 1.0))


def sheet(acc, fn, nu, nv, mat, bones, hint, edge=0.0, edges=(1, 1, 1, 1)):
    """A plate with no thickness: fn(u, v) its surface. `edge` eats its rim
    away: the last share of the sheet toward each edge in `edges` (u0, u1, v0,
    v1) has its holes pushed up, so it ends in torn scales, not a line."""
    verts, faces, luv, holes = [], [], [], []
    U = [0.0]
    for i in range(nu):
        U.append(U[-1] + (fn((i + 1) / nu, 0.5) - fn(i / nu, 0.5)).length)
    W = [0.0]
    for j in range(nv):
        W.append(W[-1] + (fn(0.5, (j + 1) / nv) - fn(0.5, j / nv)).length)
    for i in range(nu + 1):
        for j in range(nv + 1):
            u, v = i / nu, j / nv
            verts.append(fn(u, v))
            h = 0.0
            if edge > 0.0:
                for on, x in zip(edges, (u, 1.0 - u, v, 1.0 - v)):
                    if on:
                        h = max(h, 0.62 * (1.0 - clamp(x / edge)) ** 1.4)
            holes.append(h)
    idx = lambda i, j: i * (nv + 1) + j
    for i in range(nu):
        for j in range(nv):
            faces.append([idx(i, j), idx(i + 1, j), idx(i + 1, j + 1), idx(i, j + 1)])
            luv.append([(U[i], W[j]), (U[i + 1], W[j]), (U[i + 1], W[j + 1]), (U[i], W[j + 1])])
    # Facing away from `hint`.
    c = fn(0.5, 0.5)
    du = fn(0.55, 0.5) - fn(0.45, 0.5)
    dv = fn(0.5, 0.55) - fn(0.5, 0.45)
    if du.cross(dv).dot(c - hint) < 0.0:
        faces = [list(reversed(f)) for f in faces]
        luv = [list(reversed(l)) for l in luv]
    acc.push(verts, faces, mat, bones, luv=luv, holes=holes)


def lace(acc, a, b, ra, rb, mat, bones, hole=0.47, nu=10, nv=5, bow=None, a0=0.0, a1=360.0, flat=1.0, side=None):
    """A sleeve of sinew between two points, eaten to a web: on the shell, so
    its holes go through."""
    d = (b - a).normalized()
    s0 = side if side is not None else (V(1, 0, 0) if abs(d.x) < 0.8 else V(0, 1, 0))
    s0 = (s0 - d * s0.dot(d)).normalized()
    s1 = d.cross(s0)
    bow = bow if bow is not None else V(0, 0, 0)

    def fn(u, v):
        ang = math.radians(lerp(a0, a1, u))
        r = lerp(ra, rb, v) * (1.0 + 0.22 * math.sin(v * math.pi))
        return a.lerp(b, v) + bow * math.sin(v * math.pi) + s0 * (r * math.cos(ang)) + s1 * (r * flat * math.sin(ang))

    sheet(acc, fn, nu, nv, mat.but(hole=hole), bones, a.lerp(b, 0.5), edge=0.16, edges=(0, 0, 1, 1))


def box(acc, size, mat, bones, xf, bevel=0.002):
    kit.rbox(acc, size, mat, bones, xf, bevel)


def arc_seg(acc, s, c, a0, a1, r, w, t, mat, bones):
    """A finger joint bent round the grip (which runs along Y): angle 0 at the
    back of the hand, going under the grip (+) to the palm side."""
    rings = []
    for i in range(4):
        a = math.radians(lerp(a0, a1, i / 3))
        d = V(s * math.cos(a), 0.0, -math.sin(a))
        ring = []
        for dy, dr in ((w * 0.5, -t * 0.5), (w * 0.5, t * 0.32), (w * 0.32, t * 0.5), (-w * 0.32, t * 0.5),
                       (-w * 0.5, t * 0.32), (-w * 0.5, -t * 0.5)):
            ring.append(c + d * (r + dr) + V(0, dy, 0))
        rings.append(ring)
    kit.loft(acc, rings, mat, bones)


# --- The head ------------------------------------------------------------------------

HEAD_RX = [(1.952, 0.022), (1.97, 0.034), (2.0, 0.046), (2.04, 0.060), (2.08, 0.070), (2.115, 0.077), (2.15, 0.079),
           (2.178, 0.069), (2.196, 0.046), (2.205, 0.018)]
HEAD_RY = [(1.952, 0.024), (1.97, 0.038), (2.0, 0.054), (2.04, 0.071), (2.08, 0.083), (2.115, 0.092), (2.15, 0.094),
           (2.178, 0.083), (2.196, 0.056), (2.205, 0.021)]
HEAD_CY = [(1.952, -0.045), (2.0, -0.036), (2.05, -0.022), (2.1, -0.012), (2.15, -0.006), (2.205, -0.004)]


def head_pt(a, z, off=0.0):
    """On the skull: `a` degrees round from the front (+ to its left)."""
    r = math.radians(a)
    rx = curve(z, HEAD_RX) + off
    ry = curve(z, HEAD_RY) + off
    return V(rx * math.sin(r), curve(z, HEAD_CY) - ry * math.cos(r), z)


def build_head():
    C.dens = S.dens = 2.2
    B = b1("head")
    rings = []
    zs = [1.952, 1.965, 1.985, 2.01, 2.04, 2.07, 2.095, 2.12, 2.145, 2.165, 2.183, 2.197, 2.205]
    for z in zs:
        rings.append([head_pt(360.0 * k / 24, z) for k in range(24)])
    kit.loft(C, rings, BRONZE.but(rust=0.5), B)
    # The mask's deep recess: a dark plate over the face.
    def recess(u, v):
        return head_pt(lerp(-64.0, 64.0, u), lerp(1.958, 2.098, v), 0.0012)

    sheet(C, recess, 14, 7, VOID, B, V(0, 0, 2.05))
    # The mask's slits: bars running down the face, the middle one heaviest, a
    # nasal running up into the brow.
    bars = [(a, 0.0031) for a in (-56, -47, -38, -30, -22, -15, -8, 8, 15, 22, 30, 38, 47, 56)] + [(0, 0.0068)]
    for a, w in bars:
        pts, rad = [], []
        z1 = 2.112 if a == 0 else 2.074 - 0.0007 * abs(a)
        z0 = 1.958 + 0.0007 * abs(a)
        for k in range(7):
            z = lerp(z0, z1, k / 6)
            # Bow the bars outward at the cheek, to the jaw.
            pts.append(head_pt(a * lerp(0.74, 1.0, smooth((z - 1.96) / 0.09)), z, 0.0052))
            rad.append(w * (0.72 if k in (0, 6) else 1.0))
        tube(C, pts, rad, BRONZE2.but(rust=0.4, scale=0.0), B, n=4, flat=0.9, side=V(1, 0, 0))

    # The rim round the mask: brow, cheeks, jaw.
    def rim(path, w):
        tube(C, path, [w] * len(path), BRONZE2.but(scale=0.0), B, n=6, flat=0.7)

    rim([head_pt(a, 2.098 + 0.012 * abs(a / 66.0) ** 1.6, 0.0035) for a in range(-66, 67, 8)], 0.0058)
    rim([head_pt(a, 1.962 + 0.1 * (abs(a) / 66.0) ** 3.4, 0.0035) for a in range(-66, 67, 8)], 0.0052)
    for s in (1, -1):
        rim([head_pt(s * 66.0, lerp(1.986, 2.102, k / 7), 0.0035) for k in range(8)], 0.0052)
    # The eyes: slanted slots of amber behind the bars.
    for s in (1.0, -1.0):
        pts = [head_pt(s * lerp(13.0, 41.0, k / 4), 2.0885 + 0.0085 * (k / 4), 0.0018) for k in range(5)]
        tube(G, pts, [0.0035, 0.0062, 0.0066, 0.0056, 0.0026], GLOWM, B, n=6, flat=0.75, side=V(0, 0, 1))
    # Seams over the dome.
    for a in (-122, -86, 86, 122, 180):
        tube(C, [head_pt(a, z, 0.0018) for z in (2.0, 2.05, 2.1, 2.14, 2.17, 2.192)], [0.0022, 0.0034, 0.0038, 0.0038, 0.0032, 0.0018],
             RUST.but(scale=0.0), B, n=5)
    C.dens = S.dens = 1.0
    # The neck: bare bones of it, thin as a wrist, with cords.
    N = b1("neck")
    for k in range(6):
        z = lerp(1.80, 1.925, k / 5)
        y = lerp(0.008, -0.012, k / 5)
        kit.lathe(C, [(0.0, z - 0.012), (0.022, z - 0.009), (0.026, z), (0.022, z + 0.009), (0.0, z + 0.012)], BONE2, N, n=8, c=(0.0, y))
        box(C, (0.012, 0.038, 0.012), BONE2, N, Matrix.Translation(V(0, y + 0.034, z - 0.004)) @ Matrix.Rotation(-0.5, 4, 'X'), 0.003)
    w = skin("chest", "neck", "head", sharp=0.03)
    fibers(C, V(0, -0.01, 1.755), V(0, -0.03, 1.955), 8, 0.04, 0.0046, FLESH, w, bulge=0.008, spread_b=0.03)
    lace(S, V(0, 0.002, 1.76), V(0, -0.014, 1.955), 0.05, 0.034, FLESH, w, hole=0.42, nu=12, nv=6)
    for s in (1.0, -1.0):
        tube(C, bez(V(s * 0.062, -0.012, 1.76), V(s * 0.04, -0.02, 1.85), V(s * 0.03, -0.03, 1.968), 6),
             [0.006, 0.0095, 0.009, 0.008, 0.0072, 0.0064, 0.005], FLESH, w, n=6)
        tube(C, bez(V(s * 0.05, 0.03, 1.77), V(s * 0.04, 0.03, 1.86), V(s * 0.03, 0.03, 1.97), 5), [0.006, 0.01, 0.01, 0.009, 0.008, 0.006],
             FLESH2, w, n=5)


# --- The torso -----------------------------------------------------------------------

CAGE_RX = [(1.44, 0.072), (1.5, 0.10), (1.56, 0.125), (1.62, 0.143), (1.68, 0.155), (1.73, 0.15), (1.78, 0.105)]
CAGE_RY = [(1.44, 0.056), (1.5, 0.072), (1.56, 0.085), (1.62, 0.092), (1.68, 0.092), (1.73, 0.08), (1.78, 0.055)]


def cage_pt(a, z, off=0.0):
    """On the ribcage: `a` degrees round from the front (+ to its left)."""
    r = math.radians(a)
    return V((curve(z, CAGE_RX) + off) * math.sin(r), -(curve(z, CAGE_RY) + off) * math.cos(r) + 0.006, z)


def build_torso():
    Ch = b1("chest")
    Sp2 = b1("spine.02")
    Sp1 = b1("spine.01")
    Pv = b1("pelvis")
    # The spine, whole, from the sacrum to the neck.
    w_sp = skin("pelvis", "spine.01", "spine.02", "chest", sharp=0.016)
    for k in range(15):
        z = lerp(1.255, 1.77, k / 14)
        y = 0.03 + 0.016 * math.sin((z - 1.25) * 5.0)
        r = lerp(0.031, 0.022, k / 14)
        kit.lathe(C, [(0.0, z - 0.0145), (r * 0.82, z - 0.012), (r, z - 0.004), (r, z + 0.004), (r * 0.82, z + 0.012), (0.0, z + 0.0145)],
                  BONE, w_sp, n=9, c=(0.0, y), sy=0.86)
        box(C, (0.11 * lerp(1.0, 0.74, k / 14), 0.018, 0.009), BONE2, w_sp, Matrix.Translation(V(0, y + 0.012, z)), 0.003)
        box(C, (0.012, 0.05, 0.016), BONE2, w_sp, Matrix.Translation(V(0, y + 0.04, z - 0.004)) @ Matrix.Rotation(-0.45, 4, 'X'), 0.003)
    # The ribs: all of them; the armour hides the right side.
    for k in range(7):
        z0 = 1.742 - 0.046 * k
        top = 158.0 - 9.0 * k
        for s in (1.0, -1.0):
            pts, rad = [], []
            for i in range(9):
                t = i / 8
                a = lerp(166.0, 180.0 - top, t) if False else lerp(176.0, 180.0 - top, t)
                # `a` runs from the back forward (180 at the spine).
                z = z0 - 0.078 * t - 0.03 * math.sin(t * math.pi)
                p = cage_pt(s * a, max(z, 1.45))
                p.y = lerp(p.y, 0.03, (1.0 - t) ** 6)
                pts.append(p)
                rad.append(0.0078 * (0.74 + 0.26 * math.sin(math.pi * clamp(t * 1.1))))
            pts[0].x *= 0.45
            tube(C, pts, rad, BONE, Ch, n=6, flat=0.62, side=V(0, 0, 1))
    # The sternum.
    tube(C, line(V(0, -0.074, 1.735), V(0, -0.07, 1.545), 5), [0.01, 0.017, 0.018, 0.016, 0.014, 0.005], BONE2, Ch, n=7, flat=0.3,
         side=V(1, 0, 0))
    # What is left of the organs, and the sinew in the cage.
    tube(C, line(V(0.0, 0.01, 1.74), V(0.0, 0.02, 1.47), 6), [0.022, 0.05, 0.062, 0.062, 0.05, 0.036, 0.02], FLESH2, Ch, n=9, flat=0.7,
         side=V(1, 0, 0), wob=0.1)
    for s in (1.0, 1.0, -1.0):
        fibers(C, cage_pt(s * 62.0, 1.71, -0.012), cage_pt(s * 56.0, 1.5, -0.016), 4, 0.05, 0.0055, FLESH, Ch, bulge=0.016)

    # Sinew webbed across the ribs on the bare side.
    def web(u, v):
        return cage_pt(lerp(8.0, 112.0, u), lerp(1.46, 1.74, v), -0.002)

    sheet(S, web, 10, 7, FLESH.but(hole=0.46), Ch, V(0, 0, 1.6), edge=0.12)
    # The waist: nothing but the spine, cords and a few rags of muscle.
    w_w = skin("spine.01", "spine.02", "chest", sharp=0.03)
    tube(C, line(V(0, 0.016, 1.47), V(0, 0.02, 1.26), 6), [0.03, 0.04, 0.04, 0.034, 0.034, 0.04, 0.03], FLESH2, w_w, n=9, flat=0.82, wob=0.12)
    for s in (1.0, -1.0):
        tube(C, bez(cage_pt(s * 38, 1.5), V(s * 0.052, -0.04, 1.37), V(s * 0.078, -0.052, 1.24), 7),
             [0.008, 0.012, 0.014, 0.014, 0.012, 0.012, 0.011, 0.007], FLESH, skin("pelvis", "spine.01", "spine.02", sharp=0.04), n=6, flat=0.7)
        fibers(C, cage_pt(s * 96, 1.5, -0.01), V(s * 0.1, 0.0, 1.28), 4, 0.03, 0.0048, FLESH2, skin("pelvis", "spine.01", "spine.02", sharp=0.04),
               bulge=0.018)
    lace(S, V(0, 0.012, 1.47), V(0, 0.012, 1.27), 0.07, 0.085, FLESH, w_w, hole=0.45, nu=12, nv=5, flat=0.78)
    # A few bands of armour still about the waist, on the right.
    def wrap(z0, z1, a0, a1, rx, ry):
        def fn(u, v):
            a = math.radians(lerp(a0, a1, u))
            return V(rx * math.sin(a), 0.012 - ry * math.cos(a), lerp(z0, z1, v))

        return fn

    sheet(S, wrap(1.385, 1.43, -150.0, 10.0, 0.082, 0.07), 10, 2, RUST.but(hole=0.3), w_w, V(0, 0, 1.4), edge=0.3)
    sheet(S, wrap(1.335, 1.375, -120.0, -8.0, 0.074, 0.066), 8, 2, BRONZE2.but(hole=0.34), w_w, V(0, 0, 1.35), edge=0.3)

    # The breastplate: whole on its right, eaten away across the left of the
    # chest to show the ribs.
    def eaten(p):
        return 0.1 + 0.62 * smooth((p.x + 0.015) / 0.1) + 0.1 * smooth((1.56 - p.z) / 0.1)

    def breast(u, v):
        a = lerp(-124.0, 52.0, u)
        z = lerp(1.455 + 0.05 * smooth(abs(a + 30.0) / 95.0), 1.775 - 0.05 * smooth(abs(a) / 120.0), v)
        return cage_pt(a, z, 0.008 + 0.004 * math.cos(math.radians(a * 1.2)))

    sheet(S, breast, 20, 12, BRONZE.but(hole=eaten), Ch, V(0, 0, 1.6), edge=0.11, edges=(1, 1, 1, 1))
    # A second, darker skin of plate behind the first, from the right side
    # round the back.
    def backp(u, v):
        a = lerp(-178.0, -62.0, u)
        return cage_pt(a, lerp(1.48, 1.765, v), 0.008)

    sheet(S, backp, 12, 9, RUST.but(hole=0.14), Ch, V(0, 0, 1.6), edge=0.1)

    def backl(u, v):
        a = lerp(176.0, 76.0, u)
        return cage_pt(a, lerp(1.53, 1.765, v), 0.008)

    sheet(S, backl, 10, 7, RUST.but(hole=0.3), Ch, V(0, 0, 1.6), edge=0.16)
    # A cape of plate over the left shoulder, ending at the arm.
    def yoke(u, v):
        a = lerp(-10.0, 95.0, u)
        return cage_pt(a, lerp(1.70 - 0.02 * math.sin(u * 3.0), 1.782, v), 0.014)

    sheet(S, yoke, 10, 4, BRONZE2.but(hole=0.2), Ch, V(0, 0, 1.6), edge=0.2, edges=(0, 1, 1, 0))
    # The slope from the neck out over each shoulder: a yoke of plate.
    for s, hole in ((-1.0, 0.06), (1.0, 0.22)):
        def slope(u, v, s=s):
            x = lerp(0.05, 0.262, u)
            w = lerp(0.056, 0.07, u) * (1.0 - 0.3 * u * u)
            y = lerp(-w, w, v) + 0.004
            z = lerp(1.836, 1.752, u ** 1.15) + 0.012 * math.sin(v * math.pi) - 0.04 * abs(2.0 * v - 1.0) ** 2.5
            return V(s * x, y, z)

        sheet(S, slope, 9, 7, BRONZE.but(hole=hole), [("chest", 0.6), ("clavicle.L" if s > 0 else "clavicle.R", 0.4)], V(s * 0.16, 0, 1.7), edge=0.16, edges=(0, 1, 1, 1))
    # The collar of flesh and plate round the neck.
    def collar(u, v):
        a = lerp(-180.0, 180.0, u)
        r = math.radians(a)
        rr = lerp(0.098, 0.045, v)
        return V(rr * math.sin(r), rr * 0.9 * -math.cos(r), lerp(1.742, 1.815, v) + 0.012 * math.sin(a * 0.05))

    sheet(S, collar, 18, 4, FLESH.but(hole=0.24), skin("chest", "neck", sharp=0.04), V(0, 0, 1.78), edge=0.28, edges=(0, 0, 1, 1))
    # The pelvis: wings of bone, a basin of sinew.
    for s in (1.0, -1.0):
        def wing(u, v, s=s):
            a = math.radians(lerp(55.0, 148.0, u))
            r = lerp(0.08, 0.142, v)
            z = lerp(1.13, 1.285 - 0.03 * abs(2 * u - 1) ** 2, v)
            return V(s * r * math.sin(a), 0.008 - r * 0.74 * math.cos(a), z)

        sheet(C, wing, 8, 4, BONE, Pv, V(0, 0, 1.2))
        tube(C, [wing(k / 6, 1.0) for k in range(7)], [0.006, 0.01, 0.012, 0.013, 0.012, 0.01, 0.006], BONE2, Pv, n=6)
    tube(C, line(V(0, 0.015, 1.30), V(0, 0.01, 1.10), 5), [0.024, 0.062, 0.076, 0.07, 0.046, 0.016], FLESH2, Pv, n=9, flat=0.72, side=V(1, 0, 0), wob=0.08)
    # The hip plate: a curved plate over the belly and groin, its top a waist.
    def hip_pt(a, z, off=0.0):
        rx = curve(z, [(1.015, 0.028), (1.06, 0.05), (1.11, 0.086), (1.17, 0.118), (1.23, 0.132), (1.29, 0.112), (1.335, 0.082)])
        ry = curve(z, [(1.015, 0.016), (1.06, 0.028), (1.11, 0.046), (1.17, 0.062), (1.23, 0.07), (1.29, 0.066), (1.335, 0.056)])
        r = math.radians(a)
        return V((rx + off) * math.sin(r), 0.008 - (ry + off) * math.cos(r), z)

    def front(u, v):
        z = lerp(1.015, 1.33 - 0.03 * (2 * u - 1) ** 2, v)
        a = lerp(-76.0, 76.0, u) * lerp(0.8, 1.0, smooth((z - 1.02) / 0.25))
        return hip_pt(a, z, 0.006)

    sheet(S, front, 14, 11, BRONZE.but(hole=lambda p: 0.08 + 0.14 * smooth((p.x + 0.03) / 0.12)), Pv, V(0, 0, 1.2), edge=0.1, edges=(1, 1, 0, 1))
    sheet(C, lambda u, v: front(u, v) + V(0, 0.004, 0), 10, 8, FLESH2, Pv, V(0, 0, 1.2))
    # The tassets: great plates over each hip.
    for s, hole in ((-1.0, 0.1), (1.0, 0.34)):
        def tasset(u, v, s=s):
            a = s * lerp(38.0, 142.0, u)
            z = lerp(1.09, 1.30 - 0.03 * (2 * u - 1) ** 2, v)
            return hip_pt(a, max(z, 1.11), 0.01 + 0.016 * (1.0 - v)) - V(0, 0, 0.03 * (1.0 - v))

        sheet(S, tasset, 10, 6, RUST.but(hole=hole), skin("pelvis", "thigh.L" if s > 0 else "thigh.R", sharp=0.12), V(s * 0.05, 0, 1.2),
              edge=0.18, edges=(1, 1, 1, 0))
    # And across the small of the back.
    def seat(u, v):
        a = lerp(142.0, 218.0, u)
        return hip_pt(a, lerp(1.135, 1.3, v), 0.012)

    sheet(S, seat, 8, 5, BRONZE2.but(hole=0.2), Pv, V(0, 0, 1.2), edge=0.18)


# --- The arms ------------------------------------------------------------------------

def build_right_arm():
    x = -SHOULDER_X
    U = b1("upper_arm.R")
    F = b1("forearm.R")
    H_ = b1("hand.R")
    Cl = b1("clavicle.R")
    # The clavicle: a strut, and the plate over it.
    tube(C, line(V(-0.04, 0.0, 1.745), V(x + 0.03, 0, SHOULDER_Z), 3), [0.02, 0.022, 0.024, 0.03], STRUT, Cl, n=7)

    def sh(u, v):
        a = math.radians(lerp(-180.0, 180.0, u))
        el = math.radians(lerp(8.0, 118.0, v))
        p = V(0.086 * math.sin(el) * math.cos(a), 0.09 * math.sin(el) * math.sin(a), 0.086 * math.cos(el))
        return V(x - 0.008, 0.0, SHOULDER_Z + 0.02) + p

    # The shoulder: a cap, segmented like the arm below it.
    pw = [("upper_arm.R", 0.6), ("clavicle.R", 0.4)]
    rings = []
    for el in (2, 20, 40, 60, 82, 104, 122):
        e = math.radians(el)
        rings.append([V(x - 0.006 + 0.056 * math.sin(e) * math.cos(a), 0.062 * math.sin(e) * math.sin(a), SHOULDER_Z - 0.006 + 0.05 * math.cos(e))
                      for a in (math.tau * k / 14 for k in range(14))])
    kit.loft(C, rings, BRONZE, pw)
    su = kit.band(C, RUST, pw, (x - 0.006, 0.0), 0.058, 0.065, SHOULDER_Z - 0.066, SHOULDER_Z - 0.026, 0.0, 360.0, nu=14, nv=1, t=0.008, wrap=True)
    # The long banded slats over a black strut, an amber line in the gaps.
    tube(C, line(V(x, 0, SHOULDER_Z - 0.05), V(x, 0, ELBOW_Z + 0.03), 3), [0.026, 0.022, 0.021, 0.024], STRUT, U, n=8)
    for z0, z1, Bn in ((ELBOW_Z + 0.04, SHOULDER_Z - 0.065, U), (WRIST_Z + 0.03, ELBOW_Z - 0.05, F)):
        slats = 6
        for k in range(slats):
            a0 = 360.0 * k / slats + 8.0
            a1 = a0 + 360.0 / slats - 15.0
            r = 0.036 if Bn is U else 0.034
            kit.band(C, BRONZE if k % 2 == 0 else RUST, Bn, (x, 0.0), r, r, z0, z1, a0, a1, nu=3, nv=5, t=0.007,
                     rb=0.88 if Bn is U else 1.0, rad=lambda u, v, l=(Bn is F): (0.008 * math.sin(v * math.pi) if l else 0.004 * math.sin(v * math.pi)))
            a = a0 + 360.0 / slats - 7.5
            ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
            box(G, (0.0024, 0.0024, (z1 - z0) * 0.7), GLOWM, Bn, Matrix.Translation(V(x + r * 0.78 * sa, r * 0.78 * ca, (z0 + z1) * 0.5)), 0.0005)
        # Bands round the slats.
        for t in (0.04, 0.5, 0.96):
            z = lerp(z0, z1, t)
            kit.band(C, IRON if t != 0.5 else BRONZE2, Bn, (x, 0.0), 0.0435, 0.0435, z - 0.009, z + 0.009, 0.0, 360.0, nu=12, nv=1, t=0.008, wrap=True)
    # The elbow: a hinge and a cop.
    tube(C, line(V(x, 0, ELBOW_Z + 0.03), V(x, 0, ELBOW_Z - 0.03), 2), [0.027, 0.03, 0.027], IRON, F, n=9)
    ax = V(-1, 0, 0)
    kit.gear(C, BRONZE2, F, V(x - 0.034, 0, ELBOW_Z), ax, 0.032, 9, 0.012, 0.006)
    kit.gear(C, BRONZE2, F, V(x + 0.034, 0, ELBOW_Z), ax, 0.03, 9, 0.01, 0.006)
    kit.lathe(C, [(0.0, 0.03), (0.014, 0.028), (0.023, 0.022), (0.027, 0.01)], BRONZE, F, n=10, xf=kit.frame(V(x, 0.022, ELBOW_Z), V(0, 1, 0)), cap1=True)
    # The forearm's great cuff, as wide as a greave.
    cz = 1.13
    kit.band(C, BRONZE, F, (x, 0.0), 0.056, 0.056, cz - 0.07, cz + 0.07, 0.0, 360.0, nu=16, nv=4, t=0.01, rb=0.82, wrap=True,
             rad=lambda u, v: 0.006 * math.sin(v * math.pi))
    for z, r in ((cz - 0.072, 0.047), (cz + 0.072, 0.058)):
        kit.band(C, IRON, F, (x, 0.0), r, r, z - 0.008, z + 0.008, 0.0, 360.0, nu=14, nv=1, t=0.01, wrap=True)
    box(G, (0.0045, 0.003, 0.07), GLOWM, F, Matrix.Translation(V(x, -0.0615, cz)), 0.0008)
    # The gauntlet: a flared cuff, plated knuckles, fingers shut on the grip.
    C.dens = 1.5
    kit.band(C, RUST, H_, (x, 0.0), 0.05, 0.053, 0.836, 0.915, 0.0, 360.0, nu=14, nv=2, t=0.008, rb=1.16, wrap=True)
    box(C, (0.052, 0.084, 0.062), IRON, H_, Matrix.Translation(V(x - 0.006, 0, 0.838)), 0.012)
    for k, (dz, mat) in enumerate(((0.05, BRONZE), (0.03, RUST), (0.01, BRONZE2))):
        xf = Matrix.Translation(V(x - (0.04 + 0.003 * k), 0.0, 0.795 + dz)) @ Matrix.Rotation(0.1 + 0.38 * k, 4, 'Y')
        box(C, (0.011, 0.092, 0.028), mat, H_, xf, 0.003)
    c = V(x, 0.0, GRIP.z)
    for y in (-0.0345, -0.0115, 0.0115, 0.0345):
        cc = c + V(0, y, 0)
        arc_seg(C, -1.0, cc, -38.0, 22.0, 0.031, 0.0205, 0.023, IRON, H_)
        arc_seg(C, -1.0, cc, 26.0, 86.0, 0.030, 0.0195, 0.022, BRONZE2, H_)
        arc_seg(C, -1.0, cc, 90.0, 146.0, 0.029, 0.0185, 0.0205, IRON, H_)
    th = V(x, -0.043, GRIP.z)
    arc_seg(C, -1.0, th, 168.0, 118.0, 0.033, 0.023, 0.023, IRON, H_)
    arc_seg(C, -1.0, th, 112.0, 68.0, 0.031, 0.022, 0.021, BRONZE2, H_)
    C.dens = 1.0


def build_left_arm():
    x = SHOULDER_X
    U = b1("upper_arm.L")
    F = b1("forearm.L")
    Hd = b1("hand.L")
    Cl = b1("clavicle.L")
    tube(C, bez(V(0.05, -0.03, 1.745), V(0.14, -0.055, 1.775), V(x - 0.03, 0.0, 1.78), 6), [0.012, 0.014, 0.012, 0.012, 0.012, 0.014, 0.017], BONE, Cl, n=7)
    # The shoulder blade, behind.
    def blade_(u, v):
        return V(lerp(0.07, 0.19, u), 0.098 + 0.016 * math.sin(u * math.pi) - 0.03 * (1.0 - v), lerp(1.6 + 0.09 * (1.0 - u) ** 2, 1.75, v))

    sheet(C, blade_, 6, 5, BONE2, Cl, V(0.13, 0.0, 1.65))
    # The ball of the shoulder, wrapped in a rag of plate.
    long_bone(C, V(x, 0, SHOULDER_Z + 0.012), V(x, 0, ELBOW_Z + 0.005), 0.0205, 0.037, 0.034, BONE, U, bow=V(0.012, -0.008, 0), n=9, k=12)

    def cap(u, v):
        a = math.radians(lerp(-115.0, 165.0, u))
        el = math.radians(lerp(10.0, 105.0, v))
        return V(x + 0.066 * math.sin(el) * math.cos(a), 0.072 * math.sin(el) * math.sin(a), SHOULDER_Z + 0.004 + 0.074 * math.cos(el))

    sheet(S, cap, 10, 6, BRONZE2.but(hole=0.3), [("upper_arm.L", 0.75), ("clavicle.L", 0.25)], V(x, 0, SHOULDER_Z - 0.01), edge=0.26, edges=(1, 1, 0, 1))
    # Sinew on the upper arm, more behind than before.
    w_u = skin("upper_arm.L", "forearm.L", "clavicle.L", sharp=0.02)
    fibers(C, V(x + 0.01, 0.015, 1.71), V(x, 0.01, ELBOW_Z + 0.02), 8, 0.03, 0.0056, FLESH, w_u, bulge=0.018)
    fibers(C, V(x - 0.015, -0.01, 1.70), V(x - 0.008, -0.02, 1.42), 4, 0.02, 0.0048, FLESH2, U, bulge=0.012)
    lace(S, V(x, 0, 1.70), V(x, 0, ELBOW_Z + 0.02), 0.043, 0.03, FLESH, w_u, hole=0.5, nu=10, nv=8, bow=V(0.012, -0.008, 0))
    # The elbow.
    kit.lathe(C, [(0.0, ELBOW_Z + 0.03), (0.027, ELBOW_Z + 0.018), (0.033, ELBOW_Z), (0.029, ELBOW_Z - 0.02), (0.0, ELBOW_Z - 0.035)], BONE2, F, n=9, c=(x, 0.008))
    # Radius and ulna, a gap between them; cords up the forearm.
    long_bone(C, V(x - 0.004, -0.018, ELBOW_Z - 0.005), V(x - 0.014, -0.016, WRIST_Z + 0.008), 0.0118, 0.021, 0.021, BONE, F, bow=V(-0.006, -0.01, 0), n=7)
    long_bone(C, V(x + 0.008, 0.019, ELBOW_Z - 0.005), V(x + 0.012, 0.015, WRIST_Z + 0.008), 0.0105, 0.023, 0.017, BONE2, F, bow=V(0.009, 0.006, 0), n=7)
    w_f = skin("forearm.L", "hand.L", sharp=0.02)
    fibers(C, V(x, 0.0, ELBOW_Z - 0.04), V(x, 0.0, WRIST_Z + 0.02), 7, 0.031, 0.0046, FLESH, w_f, bulge=0.014)
    lace(S, V(x, 0, ELBOW_Z - 0.04), V(x, 0, WRIST_Z + 0.03), 0.04, 0.032, FLESH, w_f, hole=0.47, nu=10, nv=8, flat=1.2)
    # A rag of plate on the forearm.
    def rag(u, v):
        a = math.radians(lerp(-40.0, 150.0, u))
        return V(x + 0.042 * math.cos(a), 0.046 * math.sin(a), lerp(0.97, 0.915, v))

    sheet(S, rag, 8, 3, RUST.but(hole=0.28), F, V(x, 0, 0.94), edge=0.3)
    # The wrist and the back of the hand: small bones.
    C.dens = 1.5
    for i in range(6):
        p = V(x + 0.012 * ((i % 3) - 1) - 0.003, -0.03 + 0.012 * i, 0.862 + 0.012 * (i % 2))
        kit.lathe(C, [(0.0, -0.011), (0.0095, -0.007), (0.0105, 0.0), (0.0095, 0.007), (0.0, 0.011)], BONE2, Hd, n=7, xf=Matrix.Translation(p))
    for name, y, l0, l1, fan in FINGERS:
        k = V(x - 0.004, y, KNUCKLE_Z)
        long_bone(C, V(x + 0.002, y * 0.55, 0.862), k, 0.0052, 0.0088, 0.0098, BONE, Hd, n=6, k=6)
    for bn, a, b in finger_rest():
        tip = bn[2] == "b"
        thumb = bn.startswith("f0")
        w = b1(bn)
        if tip:
            # The last joint, then the claw: long, hooked, black at the point.
            mid = a.lerp(b, 0.42)
            long_bone(C, a, mid, 0.0044, 0.0078, 0.0068, BONE, w, n=6, k=4)
            hook = (b - a).normalized().cross(V(0, 1, 0)).normalized() * -0.008
            pts = bez(mid, mid.lerp(b, 0.6) + hook * 0.2, b + hook, 6)
            r = [0.0068, 0.0062, 0.0054, 0.0045, 0.0034, 0.002, 0.0005]
            tube(C, pts, r, BONE2.but(col=(0.17, 0.11, 0.07)), w, n=6, flat=0.78)
        else:
            long_bone(C, a, b, 0.0052, 0.0088, 0.0082, BONE, w, n=6, k=5)
        # Sinew on the finger.
        if not tip:
            tube(C, line(a + V(-0.006, 0, 0), b + V(-0.006, 0, 0), 3), [0.0022, 0.0038, 0.0038, 0.0022], FLESH, w, n=5)
    fibers(C, V(x - 0.006, 0, 0.87), V(x - 0.006, 0, 0.805), 5, 0.028, 0.0036, FLESH, Hd, bulge=0.006, k=4)
    C.dens = 1.0


# --- The legs ------------------------------------------------------------------------

def sabaton_ring(y, z_top, z_bot, w, peak=0.0):
    """A cross-section of the foot at `y` along it: a flattened arch."""
    ring = []
    for k in range(10):
        a = math.tau * k / 10
        sx, sz = math.cos(a), math.sin(a)
        z = lerp(z_bot, z_top, 0.5 + 0.5 * sz)
        if sz > 0:
            z += peak * sz
        ring.append((w * sx, y, z))
    return ring


def foot(s, x, mat, toe_mat, bone_toes):
    side = "L" if s > 0 else "R"
    Fb = b1("foot." + side)
    To = b1("toe." + side)
    sec = [(0.075, 0.05, 0.002, 0.048), (0.04, 0.095, 0.002, 0.056), (-0.02, 0.125, 0.002, 0.058), (-0.08, 0.1, 0.002, 0.056), (-0.135, 0.07, 0.002, 0.052),
           (-0.172, 0.052, 0.002, 0.047)]
    rings = []
    for y, zt, zb, w in sec:
        rings.append([V(x + px, py, pz) for px, py, pz in sabaton_ring(y, zt, zb, w)])
    kit.loft(C, rings, mat, Fb)
    if not bone_toes:
        # A pointed toe, plated.
        sec2 = [(-0.168, 0.05, 0.002, 0.048), (-0.215, 0.038, 0.002, 0.04), (-0.25, 0.028, 0.002, 0.028), (-0.285, 0.018, 0.002, 0.013), (-0.305, 0.01, 0.003, 0.003)]
        rings = [[V(x + px, py, pz) for px, py, pz in sabaton_ring(y, zt, zb, w)] for y, zt, zb, w in sec2]
        kit.loft(C, rings, toe_mat, To)
        for y in (-0.095, -0.13):
            box(C, (0.1, 0.012, 0.03), BRONZE2, Fb, Matrix.Translation(V(x, y, 0.066 + (y + 0.16) * 0.3)) @ Matrix.Rotation(0.5, 4, 'X'), 0.003)
    else:
        # Bare metatarsals and long toes, splayed.
        for k, (off, length) in enumerate(((-0.044, 0.1), (-0.021, 0.125), (0.002, 0.13), (0.024, 0.115), (0.044, 0.09))):
            a = V(x + off * 0.72, -0.14, 0.03)
            b = V(x + off * 1.25, -0.172, 0.017)
            long_bone(C, a, b, 0.0078, 0.0112, 0.0108, BONE, Fb, n=6, k=4)
            c = b + V(off * 0.26, -length * 0.52, -0.006)
            d = c + V(off * 0.2, -length * 0.48, -0.006)
            long_bone(C, b, c, 0.0064, 0.0098, 0.0088, BONE, To, n=6, k=4)
            tube(C, bez(c, c.lerp(d, 0.6) + V(0, 0, 0.003), d, 4), [0.0078, 0.0068, 0.0052, 0.0034, 0.0008], BONE2, To, n=5)


def build_right_leg():
    x = -HIP_X
    T = b1("thigh.R")
    Sh = b1("shin.R")
    # Struts down the thigh, under the plate.
    tube(C, line(V(x, 0, HIP_Z), V(x, 0, KNEE_Z + 0.05), 3), [0.04, 0.034, 0.03, 0.032], STRUT, T, n=8)
    for s, y in ((1, 0.03), (-1, -0.03)):
        tube(C, line(V(x + s * 0.03, y, 0.98), V(x + s * 0.024, y, KNEE_Z + 0.06), 2), [0.012, 0.012, 0.012], IRON, T, n=7)
    tube(C, line(V(x - 0.043, -0.02, 0.86), V(x - 0.043, -0.02, 0.70), 2), [0.0034, 0.0034, 0.0034], GLOWM.but(col=(0.02, 0.01, 0.0)), T, n=5)

    # The cuisse: a long plate wrapped round the thigh, square at the bottom.
    def cuisse(u, v):
        a = math.radians(lerp(-200.0, 158.0, u))
        z = lerp(0.725, 1.125, v)
        r = lerp(0.058, 0.08, smooth(v)) + 0.005 * math.sin(v * math.pi)
        return V(x + r * math.sin(a), -r * 1.04 * math.cos(a), z)

    sheet(S, cuisse, 16, 9, BRONZE.but(hole=lambda p: 0.13 + 0.2 * smooth((p.z - 1.0) / 0.1)), T, V(x, 0, 0.97), edge=0.1, edges=(0, 0, 0, 1))
    kit.band(C, RUST, T, (x, 0.0), 0.062, 0.065, 0.712, 0.746, 0.0, 360.0, nu=14, nv=1, t=0.008, wrap=True)
    # The knee: a great cog on its outer side, a lesser within, and the plate.
    ax = V(-1, 0, 0)
    tube(C, line(V(x, 0, KNEE_Z + 0.05), V(x, 0, KNEE_Z - 0.05), 2), [0.034, 0.042, 0.032], STRUT, Sh, n=9)
    w_k = skin("thigh.R", "shin.R", sharp=0.03)
    kit.gear(C, BRONZE, Sh, V(x - 0.046, 0, KNEE_Z), ax, 0.058, 11, 0.018, 0.01)
    kit.gear(C, IRON, Sh, V(x - 0.06, 0, KNEE_Z), ax, 0.034, 8, 0.012, 0.007)
    kit.lathe(C, [(0.0, 0.03), (0.012, 0.028), (0.02, 0.018), (0.02, 0.0)], BRONZE2, Sh, n=10, xf=kit.frame(V(x - 0.066, 0, KNEE_Z), ax), cap1=True)
    tube(G, line(V(x - 0.0885, 0.0, KNEE_Z - 0.006), V(x - 0.0885, 0.0, KNEE_Z + 0.006), 1), [0.005, 0.005], GLOWM, Sh, n=6)
    kit.gear(C, BRONZE2, Sh, V(x + 0.044, 0, KNEE_Z), ax, 0.042, 9, 0.014, 0.008)
    kit.lathe(C, [(0.0, 0.04), (0.02, 0.038), (0.04, 0.024), (0.048, 0.0)], BRONZE, Sh, n=12, sx=0.92, sy=1.1, xf=kit.frame(V(x, -0.022, KNEE_Z + 0.006), V(0, -1, 0)), cap1=True)

    # The greave: a calf-shaped plate front and back, strapped.
    def calf(z):
        return curve(z, [(0.11, 0.043), (0.17, 0.045), (0.3, 0.056), (0.42, 0.069), (0.5, 0.068), (0.57, 0.056)])

    def greave(u, v):
        a = math.radians(lerp(-180.0, 180.0, u))
        z = lerp(0.135, 0.575 + 0.03 * math.cos(a), v)
        r = calf(z) + 0.0065 * math.cos(a * 2.0) * math.sin(v * math.pi)
        return V(x + r * math.sin(a), -r * 1.1 * math.cos(a), z)

    tube(C, line(V(x, 0, KNEE_Z - 0.05), V(x, 0, ANKLE_Z + 0.03), 3), [0.03, 0.028, 0.024, 0.026], STRUT, Sh, n=7)
    sheet(S, greave, 20, 12, BRONZE.but(hole=lambda p: 0.09 + 0.26 * smooth((p.z - 0.38) / 0.16) * smooth((-p.x - 0.09) / 0.04)), Sh, V(x, 0, 0.34), edge=0.08, edges=(0, 0, 0, 1))
    for z, t in ((0.5, 0.012), (0.42, 0.01), (0.18, 0.014)):
        kit.band(C, RUST, Sh, (x, 0.0), calf(z) + 0.005, (calf(z) + 0.005) * 1.1, z - t, z + t, 0.0, 360.0, nu=16, nv=1, t=0.009, wrap=True)
    tube(C, bez(V(x - 0.046, -0.04, 0.36), V(x - 0.08, 0.016, 0.33), V(x - 0.03, 0.07, 0.3), 4), [0.006, 0.008, 0.008, 0.008, 0.006], RUST, Sh, n=5)
    # Ankle.
    kit.lathe(C, [(0.0, ANKLE_Z + 0.06), (0.044, ANKLE_Z + 0.05), (0.052, ANKLE_Z + 0.015), (0.052, ANKLE_Z - 0.02), (0.05, ANKLE_Z - 0.03)], RUST, b1("foot.R"), n=12, c=(x, 0.0), sy=1.15)
    foot(-1.0, x, BRONZE, BRONZE2, False)


def build_left_leg():
    x = HIP_X
    T = b1("thigh.L")
    Sh = b1("shin.L")
    # The femur, its head and its great knob, pitted.
    long_bone(C, V(x + 0.012, -0.002, HIP_Z + 0.005), V(x + 0.002, 0.0, KNEE_Z + 0.02), 0.0262, 0.046, 0.05, BONE, T, bow=V(0.016, -0.018, 0), n=9, k=12)
    kit.lathe(C, [(0.0, -0.03), (0.024, -0.02), (0.03, 0.0), (0.024, 0.02), (0.0, 0.03)], BONE2, T, n=8, xf=Matrix.Translation(V(x + 0.05, 0.012, HIP_Z - 0.03)))
    # What flesh is left: long maroon rags on the front and behind.
    w = skin("thigh.L", "pelvis", "shin.L", sharp=0.04)
    fibers(C, V(x + 0.018, -0.03, 1.13), V(x - 0.006, -0.044, 0.67), 6, 0.04, 0.0072, FLESH, w, bulge=0.03)
    fibers(C, V(x - 0.02, 0.03, 1.14), V(x + 0.0, 0.03, 0.68), 6, 0.04, 0.0072, FLESH2, w, bulge=0.03)
    lace(S, V(x + 0.006, 0, 1.12), V(x, 0, KNEE_Z + 0.04), 0.066, 0.04, FLESH, w, hole=0.47, nu=12, nv=9, bow=V(0.012, -0.014, 0))
    tube(C, bez(V(x - 0.04, -0.01, 1.14), V(x - 0.058, -0.015, 0.93), V(x - 0.03, 0.0, 0.76), 7), [0.008, 0.02, 0.025, 0.024, 0.02, 0.015, 0.011, 0.006], FLESH, w, n=7, wob=0.1)
    tube(C, bez(V(x + 0.05, 0.02, 1.08), V(x + 0.062, 0.03, 0.93), V(x + 0.03, 0.03, 0.78), 6), [0.007, 0.016, 0.02, 0.018, 0.014, 0.011, 0.006], FLESH2, w, n=7, wob=0.1)

    def rag(u, v):
        a = math.radians(lerp(-150.0, 40.0, u))
        return V(x + 0.066 * math.sin(a), -0.072 * math.cos(a), lerp(0.99, 0.84, v))

    sheet(S, rag, 8, 4, FLESH.but(hole=0.4), T, V(x, 0, 0.92), edge=0.3)
    # The knee, bare.
    kit.lathe(C, [(0.0, 0.05), (0.04, 0.038), (0.05, 0.0), (0.043, -0.035), (0.0, -0.05)], BONE, b1("shin.L"), n=10, xf=Matrix.Translation(V(x, 0.005, KNEE_Z - 0.01)), sy=0.9)
    kit.lathe(C, [(0.0, -0.028), (0.019, -0.022), (0.025, 0.0), (0.021, 0.022), (0.0, 0.03)], BONE2, skin("thigh.L", "shin.L", sharp=0.05), n=8,
              xf=Matrix.Translation(V(x, -0.046, KNEE_Z + 0.008)), sy=0.6)
    # The tibia, then the greave closing round it at mid-shin.
    long_bone(C, V(x, 0.0, KNEE_Z - 0.03), V(x + 0.002, 0.0, ANKLE_Z + 0.04), 0.023, 0.043, 0.03, BONE, Sh, bow=V(-0.006, -0.012, 0), n=9, k=10)
    long_bone(C, V(x + 0.03, 0.014, KNEE_Z - 0.05), V(x + 0.028, 0.014, 0.2), 0.0098, 0.015, 0.016, BONE2, Sh, n=6)
    fibers(C, V(x, 0.03, KNEE_Z - 0.03), V(x + 0.006, 0.02, 0.34), 5, 0.04, 0.007, FLESH, skin("shin.L", "thigh.L", sharp=0.03), bulge=0.024)
    lace(S, V(x, 0, KNEE_Z - 0.05), V(x, 0, 0.42), 0.05, 0.062, FLESH, skin("shin.L", "thigh.L", sharp=0.03), hole=0.46, nu=10, nv=4)

    def calf(z):
        return curve(z, [(0.11, 0.043), (0.17, 0.045), (0.3, 0.056), (0.42, 0.066), (0.5, 0.066)])

    def greave(u, v):
        a = math.radians(lerp(-180.0, 180.0, u))
        top = lerp(0.42, 0.53, 0.5 + 0.5 * math.sin(a * 1.0 + 0.8))
        z = lerp(0.135, top, v)
        r = calf(z) + 0.0065 * math.cos(a * 2.0) * math.sin(v * math.pi)
        return V(x + r * math.sin(a), -r * 1.08 * math.cos(a), z)

    sheet(S, greave, 18, 10, BRONZE.but(hole=lambda p: 0.08 + 0.3 * smooth((p.z - 0.32) / 0.14)), Sh, V(x, 0, 0.34), edge=0.14, edges=(0, 0, 0, 1))
    tube(C, line(V(x, 0, 0.4), V(x, 0, ANKLE_Z + 0.03), 2), [0.03, 0.026, 0.026], FLESH2, Sh, n=7)
    for z, t in ((0.27, 0.011), (0.18, 0.013)):
        kit.band(C, RUST, Sh, (x, 0.0), calf(z) + 0.005, (calf(z) + 0.005) * 1.08, z - t, z + t, 0.0, 360.0, nu=16, nv=1, t=0.009, wrap=True)
    kit.lathe(C, [(0.0, ANKLE_Z + 0.06), (0.044, ANKLE_Z + 0.05), (0.052, ANKLE_Z + 0.015), (0.052, ANKLE_Z - 0.02), (0.05, ANKLE_Z - 0.03)], RUST, b1("foot.L"), n=12, c=(x, 0.0), sy=1.15)
    foot(1.0, x, BRONZE2, BONE, True)


# --- The blade -----------------------------------------------------------------------

def build_blade():
    """In the fist, running forward along -Y in the rest pose. Slightly curved,
    the back straight, a saw of uneven teeth up the cutting edge (down, -Z, at
    rest); forged thin, a raised spine along the back."""
    B = b1("blade")
    g = GRIP
    # The grip, the guard, the pommel.
    tube(C, line(g + V(0, 0.058, 0), g + V(0, -0.062, 0), 3), [0.0145, 0.0165, 0.0165, 0.0145], STRUT.but(rough=0.7), B, n=7, flat=0.86, side=V(1, 0, 0))
    kit.lathe(C, [(0.0, 0.0), (0.016, 0.003), (0.021, 0.014), (0.016, 0.026), (0.0, 0.032)], IRON, B, n=8, xf=kit.frame(g + V(0, 0.058, 0), V(0, 1, 0)))
    box(C, (0.038, 0.016, 0.086), RUST.but(scale=0.0), B, Matrix.Translation(g + V(0, -0.07, 0.002)), 0.004)
    L = BLADE_LEN
    n = 64
    top, bot = [], []
    rng = random.Random(7)

    def path(t):
        # Bows away from the edge along its length, an even, slight curve.
        y = -0.078 - (L - 0.078) * t
        z = 0.0 + 0.046 * math.sin(t * math.pi * 0.8) + 0.03 * t * t * t
        return y, z

    def width(t):
        return lerp(0.031, 0.024, t) * (1.0 - smooth((t - 0.8) / 0.2) * 0.9) + 0.007 * math.sin(t * math.pi * 0.9)

    verts, faces = [], []
    for i in range(n + 1):
        t = i / n
        y, z = path(t)
        w = width(t) if i < n else 0.0
        # Each pair of stations a tooth: a long raked flank, a short steep one.
        tooth = (0.0058 + 0.0052 * rng.random()) * (1.0 if i % 2 == 0 else 0.0) * (1.0 - smooth((t - 0.9) / 0.1))
        cut = z - w - tooth
        back = z + w * 0.9
        rib = lerp(z, back, 0.68)
        th = lerp(0.0078, 0.0034, t) * (1.0 if i < n else 0.15)
        o = g + V(0, 0, 0)
        # The section: edge, flat, spine, back, and round the other side.
        sec = [(0.0, cut), (th * 0.82, lerp(cut, rib, 0.42)), (th, rib), (th * 0.72, back), (-th * 0.72, back), (-th, rib), (-th * 0.82, lerp(cut, rib, 0.42))]
        yy = y + (0.0035 if i % 2 == 0 else 0.0)
        for sx, sz in sec:
            verts.append(g + V(sx, yy, sz))
    m = 7
    for i in range(n):
        for k in range(m):
            a = i * m + k
            b = i * m + (k + 1) % m
            faces.append([a, b, b + m, a + m])
    faces.append(list(range(m)))
    faces.append([n * m + k for k in range(m)])
    verts2, faces2 = verts, faces
    C.push(verts2, faces2, BLADE, B, closed=True)


# --- Meshes, the material ------------------------------------------------------------

def make_mesh(name, acc, attrs=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in acc.v], [], acc.f)
    me.update()
    if attrs:
        for an, data in (("sk_col", acc.col), ("sk_pbr", acc.pbr), ("sk_kind", acc.kind)):
            at = me.attributes.new(an, 'FLOAT_COLOR', 'POINT')
            at.data.foreach_set("color", [x for c in data for x in c])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def skin_shader():
    """Three materials in one, by the vertex attributes: scale plate, sinew,
    bone. Outputs one at a time: `surface`, `albedo`, `orm`, `alpha`."""
    mat = bpy.data.materials.new("SwordSkeletonBake")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    N = nt.nodes.new
    L = nt.links.new

    def op(kind, a, b=None, clamp_=False):
        n = N("ShaderNodeMath")
        n.operation = kind
        n.use_clamp = clamp_
        for i, x in enumerate((a, b)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                n.inputs[i].default_value = x
            else:
                L(x, n.inputs[i])
        return n.outputs[0]

    add = lambda a, b: op('ADD', a, b)
    sub = lambda a, b: op('SUBTRACT', a, b)
    mul = lambda a, b: op('MULTIPLY', a, b)

    def noise(scale, detail, rough, vec=None, stretch=None):
        n = N("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        v = vec if vec is not None else pos
        if stretch is not None:
            vm = N("ShaderNodeVectorMath")
            vm.operation = 'MULTIPLY'
            L(v, vm.inputs[0])
            vm.inputs[1].default_value = stretch
            v = vm.outputs[0]
        L(v, n.inputs["Vector"])
        return n.outputs[0]

    def ramp(x, a, b, c=0.0, d=1.0):
        n = N("ShaderNodeMapRange")
        n.interpolation_type = 'SMOOTHSTEP'
        L(x, n.inputs[0])
        n.inputs[1].default_value = a
        n.inputs[2].default_value = b
        n.inputs[3].default_value = c
        n.inputs[4].default_value = d
        return n.outputs[0]

    def mix(f, a, b):
        n = N("ShaderNodeMix")
        n.data_type = 'RGBA'
        if isinstance(f, (int, float)):
            n.inputs[0].default_value = f
        else:
            L(f, n.inputs[0])
        for i, x in ((6, a), (7, b)):
            if isinstance(x, tuple):
                n.inputs[i].default_value = x
            else:
                L(x, n.inputs[i])
        return n.outputs[2]

    def scale3(c, f):
        n = N("ShaderNodeVectorMath")
        n.operation = 'SCALE'
        if isinstance(c, tuple):
            n.inputs[0].default_value = c[:3]
        else:
            L(c, n.inputs[0])
        if isinstance(f, (int, float)):
            n.inputs["Scale"].default_value = f
        else:
            L(f, n.inputs["Scale"])
        return n.outputs[0]

    def attr(name):
        a = N("ShaderNodeAttribute")
        a.attribute_name = name
        return a

    def split(c):
        s = N("ShaderNodeSeparateColor")
        L(c, s.inputs[0])
        return s.outputs

    geo = N("ShaderNodeNewGeometry")
    pos = geo.outputs["Position"]
    a_col = attr("sk_col")
    a_pbr = attr("sk_pbr")
    a_kind = attr("sk_kind")
    pb = split(a_pbr.outputs["Color"])
    metal_a, rough_a, scale_a = pb[0], pb[1], pb[2]
    hole_a = a_pbr.outputs["Alpha"]
    kd = split(a_kind.outputs["Color"])
    flesh_a, bone_a = kd[0], kd[1]
    # The scales.
    CELL = 58.0
    vf = N("ShaderNodeTexVoronoi")
    vf.feature = 'F1'
    vf.distance = 'EUCLIDEAN'
    vf.inputs["Scale"].default_value = CELL
    vf.inputs["Randomness"].default_value = 0.62
    L(pos, vf.inputs["Vector"])
    ve = N("ShaderNodeTexVoronoi")
    ve.feature = 'DISTANCE_TO_EDGE'
    ve.inputs["Scale"].default_value = CELL
    ve.inputs["Randomness"].default_value = 0.62
    L(pos, ve.inputs["Vector"])
    edge_d = ve.outputs["Distance"]
    cell_p = vf.outputs["Position"]
    cc = split(vf.outputs["Color"])
    cr, cg, cb = cc[0], cc[1], cc[2]
    plate = ramp(edge_d, 0.01, 0.1)
    # Each scale tipped its own way, its corner rising off the next.
    d = N("ShaderNodeVectorMath")
    d.operation = 'SUBTRACT'
    L(pos, d.inputs[0])
    L(cell_p, d.inputs[1])
    rdir = N("ShaderNodeVectorMath")
    rdir.operation = 'SUBTRACT'
    L(vf.outputs["Color"], rdir.inputs[0])
    rdir.inputs[1].default_value = (0.5, 0.5, 0.5)
    tip = N("ShaderNodeVectorMath")
    tip.operation = 'DOT_PRODUCT'
    L(d.outputs[0], tip.inputs[0])
    L(rdir.outputs[0], tip.inputs[1])
    tilt = mul(tip.outputs["Value"], CELL * 1.5)
    rivet = mul(ramp(vf.outputs["Distance"], 0.2, 0.12), ramp(cb, 0.25, 0.35))
    h_arm = add(add(mul(plate, 0.55), mul(mul(tilt, plate), 0.22)), mul(rivet, 0.32))
    h_arm = mul(h_arm, scale_a)
    # Where it is eaten: a big slow field read at each scale's own centre, so a
    # scale goes whole.
    n_cell = noise(11.0, 4.0, 0.62, vec=cell_p)
    big_k = add(1.25, mul(flesh_a, -0.8))
    fine_k = add(0.42, mul(flesh_a, 0.62))
    hval = add(add(hole_a, mul(sub(n_cell, 0.5), big_k)), mul(sub(cr, 0.5), fine_k))
    gone = ramp(hval, 0.495, 0.505)
    near = ramp(hval, 0.12, 0.5)
    # Noise.
    n_big = noise(6.5, 6.0, 0.62)
    n_mid = noise(26.0, 8.0, 0.66)
    n_fine = noise(160.0, 6.0, 0.6)
    n_streak = noise(34.0, 5.0, 0.55, stretch=(1.0, 1.0, 0.12))
    ao = N("ShaderNodeAmbientOcclusion")
    ao.samples = 12
    ao.inputs["Distance"].default_value = 0.05
    open_ = ao.outputs["AO"]
    bev = N("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = 0.003
    dot = N("ShaderNodeVectorMath")
    dot.operation = 'DOT_PRODUCT'
    L(geo.outputs["Normal"], dot.inputs[0])
    L(bev.outputs[0], dot.inputs[1])
    edge = ramp(sub(1.0, dot.outputs["Value"]), 0.012, 0.11)
    worn = mul(edge, ramp(open_, 0.55, 0.92))
    worn = op('MAXIMUM', worn, mul(mul(ramp(edge_d, 0.13, 0.05), plate), mul(scale_a, ramp(n_mid, 0.35, 0.62))))
    # Rust, as the scout's, plus each scale its own shade.
    cav = sub(1.0, open_)
    t = add(add(mul(n_big, 0.6), mul(n_mid, 0.4)), mul(a_col.outputs["Alpha"], 0.4))
    t = add(add(t, mul(cav, 0.3)), mul(n_streak, 0.1))
    rust = mul(ramp(t, 0.73, 0.87), ramp(a_col.outputs["Alpha"], 0.02, 0.12))
    rc = N("ShaderNodeValToRGB")
    L(add(mul(n_fine, 0.5), mul(n_mid, 0.5)), rc.inputs[0])
    els = rc.color_ramp.elements
    els[0].position = 0.34
    els[0].color = (0.05, 0.02, 0.012, 1.0)
    els[1].position = 0.66
    els[1].color = (0.32, 0.115, 0.04, 1.0)
    m_ = rc.color_ramp.elements.new(0.5)
    m_.color = (0.17, 0.064, 0.024, 1.0)
    shade = add(ramp(cg, 0.0, 1.0, 0.5, 1.16), mul(sub(n_big, 0.5), 0.6))
    shade = add(1.0, mul(sub(shade, 1.0), scale_a))
    base = scale3(a_col.outputs["Color"], shade)
    bright = scale3(a_col.outputs["Color"], 1.75)
    c1 = mix(worn, base, bright)
    c2 = mix(rust, c1, rc.outputs[0])
    # Stained maroon round the holes.
    c3 = mix(mul(near, 0.72), c2, (0.085, 0.014, 0.018, 1.0))
    # Black in the gaps between the scales.
    gap = add(0.14, mul(0.86, plate))
    gap = add(1.0, mul(sub(gap, 1.0), scale_a))
    arm_col = scale3(c3, gap)
    # Sinew: long fibres, wet pits.
    fib = noise(52.0, 5.0, 0.6, stretch=(1.0, 1.0, 0.1))
    fib2 = noise(120.0, 4.0, 0.55, stretch=(1.0, 1.0, 0.16))
    pv = N("ShaderNodeTexVoronoi")
    pv.feature = 'SMOOTH_F1'
    pv.inputs["Scale"].default_value = 44.0
    L(pos, pv.inputs["Vector"])
    pit = ramp(pv.outputs["Distance"], 0.28, 0.1)
    pit = mul(pit, ramp(n_big, 0.42, 0.56))
    h_fl = sub(add(mul(fib, 0.7), mul(fib2, 0.3)), mul(pit, 0.8))
    fl = mix(ramp(fib, 0.32, 0.68), (0.03, 0.006, 0.009, 1.0), a_col.outputs["Color"])
    fl = mix(ramp(fib2, 0.5, 0.75), fl, scale3(a_col.outputs["Color"], 1.9))
    fl = mix(mul(ramp(n_mid, 0.5, 0.72), 0.55), fl, (0.24, 0.1, 0.075, 1.0))
    fl = scale3(fl, sub(1.0, mul(pit, 0.86)))
    # Bone: dirty tan, darker in the hollows, pitted and eaten at the ends.
    bv = N("ShaderNodeTexVoronoi")
    bv.feature = 'SMOOTH_F1'
    bv.inputs["Scale"].default_value = 62.0
    L(pos, bv.inputs["Vector"])
    bpit = mul(ramp(bv.outputs["Distance"], 0.2, 0.08), ramp(n_big, 0.44, 0.6))
    h_bn = sub(mul(n_mid, 0.35), mul(bpit, 0.75))
    bn = mix(ramp(n_big, 0.32, 0.7), scale3(a_col.outputs["Color"], 0.58), a_col.outputs["Color"])
    bn = mix(mul(ramp(n_streak, 0.45, 0.62), 0.5), bn, (0.11, 0.05, 0.035, 1.0))
    bn = mix(ramp(n_mid, 0.56, 0.7), bn, scale3(a_col.outputs["Color"], 1.25))
    bn = scale3(bn, sub(1.0, mul(bpit, 0.9)))
    albedo = mix(flesh_a, arm_col, fl)
    albedo = mix(bone_a, albedo, bn)
    grime = ramp(open_, 0.2, 0.95, 0.28, 1.0)
    albedo = scale3(albedo, grime)
    # Roughness, metal, height.
    rough = add(rough_a, mul(rust, 0.42))
    rough = add(rough, mul(sub(n_fine, 0.5), 0.3))
    rough = op('SUBTRACT', rough, mul(worn, 0.2), True)
    metal = op('MULTIPLY', metal_a, sub(1.0, rust), True)
    metal = op('ADD', metal, mul(mul(worn, 0.2), sub(1.0, add(flesh_a, bone_a))), True)
    height = add(h_arm, mul(mul(rust, 0.3), add(n_fine, 0.2)))
    height = mul(height, sub(1.0, add(flesh_a, bone_a)))
    height = add(height, add(mul(h_fl, mul(flesh_a, 1.0)), mul(h_bn, bone_a)))
    orm = N("ShaderNodeCombineColor")
    orm.inputs[0].default_value = 1.0
    L(rough, orm.inputs[1])
    L(metal, orm.inputs[2])
    bump = N("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.85
    bump.inputs["Distance"].default_value = 0.0036
    L(height, bump.inputs["Height"])
    L(bev.outputs[0], bump.inputs["Normal"])
    p = N("ShaderNodeBsdfPrincipled")
    L(albedo, p.inputs["Base Color"])
    L(rough, p.inputs["Roughness"])
    L(metal, p.inputs["Metallic"])
    L(bump.outputs[0], p.inputs["Normal"])
    e_a = N("ShaderNodeEmission")
    L(albedo, e_a.inputs[0])
    e_o = N("ShaderNodeEmission")
    L(orm.outputs[0], e_o.inputs[0])
    e_h = N("ShaderNodeEmission")
    L(sub(1.0, gone), e_h.inputs[0])
    out = N("ShaderNodeOutputMaterial")
    outs = {"surface": p.outputs[0], "albedo": e_a.outputs[0], "orm": e_o.outputs[0], "alpha": e_h.outputs[0]}

    def show(which):
        L(outs[which], out.inputs["Surface"])

    show("surface")
    return mat, show


def bake(low, show, shader):
    """The maps, off the low mesh itself."""
    import numpy as np
    sc = bpy.context.scene
    kit.setup_cycles(40)
    nt = shader.node_tree
    tex = nt.nodes.new("ShaderNodeTexImage")
    nt.nodes.active = tex
    b = sc.render.bake
    b.use_selected_to_active = False
    b.margin = 12
    b.margin_type = 'EXTEND'
    b.use_clear = True
    b.target = 'IMAGE_TEXTURES'
    kit.activate(low)
    imgs = {}
    for name, kind, non_color, which in (("col", 'EMIT', False, "albedo"), ("alpha", 'EMIT', True, "alpha"), ("orm", 'EMIT', True, "orm"),
                                         ("nor", 'NORMAL', True, "surface")):
        img = kit.blank_image("sword_skeleton_" + name, ATLAS, non_color)
        tex.image = img
        show(which)
        kit.log("baking", name)
        bpy.ops.object.bake(type=kind, normal_space='TANGENT', normal_r='POS_X', normal_g='POS_Y', normal_b='POS_Z')
        kit.fill_corner(img, {"albedo": (0.05, 0.04, 0.035), "alpha": (1.0, 1.0, 1.0), "orm": (1.0, 0.8, 0.1), "surface": (0.5, 0.5, 1.0)}[which])
        imgs[name] = img
    # Colour and the holes in one map.
    w, h = ATLAS, ATLAS
    px = np.empty(w * h * 4, dtype=np.float32)
    imgs["col"].pixels.foreach_get(px)
    al = np.empty(w * h * 4, dtype=np.float32)
    imgs["alpha"].pixels.foreach_get(al)
    px[3::4] = al[0::4]
    out = bpy.data.images.new("sword_skeleton_col_a", w, h, alpha=True)
    out.pixels.foreach_set(px)
    out.filepath_raw = os.path.join(SRC, "sword_skeleton_col.png")
    out.file_format = 'PNG'
    out.save()
    imgs["orm"].filepath_raw = os.path.join(SRC, "sword_skeleton_orm.jpg")
    imgs["orm"].file_format = 'JPEG'
    imgs["orm"].save(quality=93)
    imgs["nor"].filepath_raw = os.path.join(SRC, "sword_skeleton_nor.png")
    imgs["nor"].file_format = 'PNG'
    imgs["nor"].save()
    nt.nodes.remove(tex)


def final_materials():
    def image(name):
        for ext in (".jpg", ".png"):
            p = os.path.join(SRC, name + ext)
            if os.path.exists(p):
                img = bpy.data.images.load(p, check_existing=True)
                img.name = name
                return img
        raise RuntimeError("no map " + name)

    def pbr(name, scissor):
        mat = bpy.data.materials.new(name)
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
        if scissor:
            g = N("ShaderNodeMath")
            g.operation = 'GREATER_THAN'
            L(t.outputs["Alpha"], g.inputs[0])
            g.inputs[1].default_value = 0.5
            L(g.outputs[0], p.inputs["Alpha"])
            mat.use_backface_culling = False
            try:
                mat.surface_render_method = 'DITHERED'
            except AttributeError:
                pass
        else:
            mat.use_backface_culling = True
        return mat

    core = pbr("SkelCore", False)
    shell_ = pbr("SkelShell", True)
    glow = bpy.data.materials.new("SkelGlow")
    glow.use_nodes = True
    p = next(n for n in glow.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs["Base Color"].default_value = (0.4, 0.2, 0.02, 1.0)
    p.inputs["Emission Color"].default_value = (1.0, 0.54, 0.09, 1.0)
    p.inputs["Emission Strength"].default_value = 1.7
    p.inputs["Roughness"].default_value = 0.3
    return core, shell_, glow


def build_armature():
    data = bpy.data.armatures.new("SwordSkeletonRig")
    arm = bpy.data.objects.new("SwordSkeletonRig", data)
    bpy.context.scene.collection.objects.link(arm)
    kit.activate(arm)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = data.edit_bones
    for name, parent, head, tail in ALL_BONES:
        b = eb.new(name)
        b.head = head
        b.tail = tail
        b.use_connect = False
        if parent:
            b.parent = eb[parent]
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm


def assign_weights(ob, arm, per_vert):
    groups = {b.name: ob.vertex_groups.new(name=b.name) for b in arm.data.bones}
    for i, bones in enumerate(per_vert):
        for n, w in bones:
            groups[n].add([i], w, 'REPLACE')
    m = ob.modifiers.new("Rig", 'ARMATURE')
    m.object = arm
    ob.parent = arm


def preview(body, out_dir):
    sc = bpy.context.scene
    kit.setup_cycles(64)
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = 760, 1000
    sc.render.image_settings.file_format = 'PNG'
    sc.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new("Prev")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.03, 0.03, 0.035, 1.0)
    sc.world = world
    cd = bpy.data.cameras.new("PrevCam")
    cam = bpy.data.objects.new("PrevCam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for name, loc, power, col in (("Key", (-2.2, -3.0, 2.8), 200.0, (1.0, 0.8, 0.6)), ("Fill", (2.8, -2.0, 1.6), 70.0, (0.75, 0.8, 1.0)),
                                  ("Rim", (0.6, 3.2, 2.4), 160.0, (1.0, 0.85, 0.7))):
        ld = bpy.data.lights.new(name, 'POINT')
        ld.energy = power
        ld.color = col
        ld.shadow_soft_size = 0.25
        l = bpy.data.objects.new(name, ld)
        l.location = loc
        sc.collection.objects.link(l)
    gm = bpy.data.meshes.new("PrevFloor")
    gm.from_pydata([(-6, -6, 0), (6, -6, 0), (6, 6, 0), (-6, 6, 0)], [], [(0, 1, 2, 3)])
    sc.collection.objects.link(bpy.data.objects.new("PrevFloor", gm))
    os.makedirs(out_dir, exist_ok=True)
    views = (("front", V(0.5, -5.2, 1.1), V(0, 0, 1.08), 50.0), ("q", V(-2.8, -4.2, 1.5), V(0, 0, 1.08), 50.0), ("back", V(2.4, 4.4, 1.6), V(0, 0, 1.08), 50.0),
             ("head", V(0.42, -1.25, 2.12), V(0, -0.03, 2.03), 85.0), ("chest", V(0.5, -1.7, 1.7), V(0.02, 0, 1.52), 70.0),
             ("hand", V(1.0, -0.8, 0.95), V(0.235, 0, 0.8), 85.0), ("legs", V(-0.6, -2.4, 0.5), V(0, 0, 0.5), 55.0))
    for name, loc, at, lens in views:
        cam.location = loc
        cam.data.lens = lens
        cam.rotation_euler = (at - loc).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(out_dir, "model_%s.png" % name)
        bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    prev_dir = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    no_bake = "--no-bake" in argv
    os.makedirs(SRC, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    kit.RNG.seed(135)
    build_head()
    build_torso()
    build_right_arm()
    build_left_arm()
    build_right_leg()
    build_left_leg()
    build_blade()
    kit.log("core %d faces, shell %d, glow %d" % (len(C.f), len(S.f), len(G.f)))
    # Core and shell unwrapped and baked as one.
    both = Acc()
    n_c = len(C.v)
    n_cf = len(C.f)
    both.v = C.v + S.v
    both.f = C.f + [[i + n_c for i in f] for f in S.f]
    for k in ("col", "pbr", "kind", "bones", "luv", "inner", "fd"):
        setattr(both, k, getattr(C, k) + getattr(S, k))
    low = make_mesh("SkelBake", both)
    kit.fix_normals(low)
    shader, show = skin_shader()
    low.data.materials.append(shader)
    kit.unwrap(low, both)
    if not no_bake:
        bake(low, show, shader)
    core, shell_, glow = final_materials()
    low.data.materials.clear()
    low.data.materials.append(core)
    low.data.materials.append(shell_)
    for i, poly in enumerate(low.data.polygons):
        poly.material_index = 0 if i < n_cf else 1
    gl = make_mesh("SkelGlowMesh", G, attrs=False)
    kit.fix_normals(gl, 60.0)
    gl.data.uv_layers.new(name="UV")
    gl.data.materials.append(glow)
    for attr in ("sk_col", "sk_pbr", "sk_kind"):
        a = low.data.attributes.get(attr)
        if a:
            low.data.attributes.remove(a)
    arm = build_armature()
    per_vert = list(both.bones) + list(G.bones)
    kit.activate(low)
    gl.select_set(True)
    bpy.ops.object.join()
    body = low
    body.name = body.data.name = "SwordSkeletonBody"
    if len(body.data.vertices) != len(per_vert):
        raise RuntimeError("vertex count %d, weights for %d" % (len(body.data.vertices), len(per_vert)))
    assign_weights(body, arm, per_vert)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method='FIXED', ngon_method='BEAUTY')
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    kit.log("body %d tris, %d verts" % (tris, len(body.data.vertices)))
    if prev_dir:
        preview(body, prev_dir)
        return
    bpy.context.view_layer.update()
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "sword_skeleton.blend"), compress=True)
    kit.log("wrote the .blend")


if __name__ == "__main__":
    main()
