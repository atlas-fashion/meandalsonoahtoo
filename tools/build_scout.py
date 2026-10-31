"""Builds models/scout.glb, the scout (note 134), in Blender, from nothing.

    blender -b --factory-startup -P tools/build_scout.py                 (all of it)
    blender -b --factory-startup -P tools/build_scout.py -- --no-bake    (old maps)
    blender -b --factory-startup -P tools/build_scout.py -- --preview <dir> [--no-bake]
    godot --headless --import --path .

Writes models/source/scout/scout.blend (the source: low and high meshes, the
rig, the materials), its maps beside it, and models/scout.glb.

A hunched robot soldier in rusted, riveted brass and iron plate, a ragged
hooded mantle, a barbed spear (note 127). Every part is modelled here as real
geometry: lathed helmet, goggles and greaves, curved plates with thickness,
real gears, a gauntlet whose fingers close on the shaft, a forged spear head.

    the LOW mesh (A) is what the game draws;
    the HIGH mesh is the low one plus what H adds (rivets, straps, seams),
    which is only ever baked: its colour, roughness, metal and normal go into
    one 2048 atlas through a procedural material (rust in patches, grime in
    the crevices by ambient occlusion, bare metal on worn edges).
    The mantle has its own 1024 maps, drawn in numpy (weave, stains, tears).

THE RIG IS scout_body.gd's AND MUST MATCH IT: same bone names, same rest
positions, every rest orientation the identity. Blender's bone axis is its own
+Y, so every bone runs along +Y with no roll, which exports as no rotation at
all. All the animation stays procedural in scout_body.gd; this file only makes
what it moves. Plates are rigid on their bones; a plate spanning a joint is
half on each.

Blender's frame here: X the scout's right, Y forward, Z up (the exporter makes
that glTF's +X, -Z forward, +Y up: the game's model space).
"""

import bpy
import bmesh
import math
import os
import random
import sys
from bpy_extras import bmesh_utils
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "models", "source", "scout")
OUT = os.path.join(ROOT, "models", "scout.glb")

ATLAS = 2048
CLOTH_TEX = 1024
# The spear sits this far to the side while it is unwrapped and baked (in its
# own frame it runs straight through the body).
SPEAR_BAKE_X = 1.6
HEAD_SCALE = 1.16
HEAD_PIVOT = (0.0, 0.0, 1.58)
# The atlas's far corner holds the hidden inner faces: everything else is
# scaled into INNER_FIT of it.
INNER_FIT = 0.98
INNER_UV = 0.99

# As scout_body.gd.
SPEAR_TIP = 1.80
SPEAR_BUTT = 0.60
STRANDS = 7
STRAND_SPAN = 120.0

# Name, parent, rest (game model space: x, y up, z back).
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

# Colour (linear), rust share, metal, roughness.
BRASS = ((0.60, 0.43, 0.19), 0.50, 0.62, 0.42)
BRASS2 = ((0.47, 0.32, 0.13), 0.62, 0.55, 0.50)
IRON = ((0.25, 0.23, 0.21), 0.58, 0.55, 0.52)
IRON2 = ((0.17, 0.16, 0.15), 0.42, 0.5, 0.58)
DARK = ((0.075, 0.07, 0.065), 0.25, 0.35, 0.65)
LEATHER = ((0.17, 0.095, 0.05), 0.08, 0.0, 0.72)
STEEL = ((0.56, 0.54, 0.50), 0.30, 0.68, 0.34)
GLASS = ((0.012, 0.018, 0.022), 0.0, 0.0, 0.1)
RIVET = ((0.34, 0.30, 0.25), 0.30, 0.6, 0.45)


def log(*a):
    print("[scout]", *a, flush=True)


def V(x, y, z):
    return Vector((x, y, z))


def lerp(a, b, t):
    return a + (b - a) * t


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def smooth(t):
    t = clamp(t)
    return t * t * (3.0 - 2.0 * t)


def curve(x, pts):
    """Catmull-Rom through (x, y) keys."""
    if x <= pts[0][0]:
        return pts[0][1]
    if x >= pts[-1][0]:
        return pts[-1][1]
    for i in range(len(pts) - 1):
        if x <= pts[i + 1][0]:
            x0, y0 = pts[max(i - 1, 0)]
            x1, y1 = pts[i]
            x2, y2 = pts[i + 1]
            x3, y3 = pts[min(i + 2, len(pts) - 1)]
            t = (x - x1) / max(x2 - x1, 1e-6)
            m1 = (y2 - y0) / max(x2 - x0, 1e-6) * (x2 - x1)
            m2 = (y3 - y1) / max(x3 - x1, 1e-6) * (x2 - x1)
            t2 = t * t
            t3 = t2 * t
            return (2 * t3 - 3 * t2 + 1) * y1 + (t3 - 2 * t2 + t) * m1 + (-2 * t3 + 3 * t2) * y2 + (t3 - t2) * m2
    return pts[-1][1]


def frame(o, z, up=None):
    """Local Z along `z`, at `o`; local Y as near `up` (world Z) as it can be."""
    z = Vector(z).normalized()
    up = Vector(up) if up is not None else V(0, 0, 1)
    x = up.cross(z)
    if x.length < 1e-4:
        x = V(1, 0, 0)
    x.normalize()
    y = z.cross(x)
    return Matrix.Translation(Vector(o)) @ Matrix((x, y, z)).transposed().to_4x4()


def signed_volume(verts, faces):
    c = sum(verts, Vector()) / max(len(verts), 1)
    vol = 0.0
    for f in faces:
        a = verts[f[0]] - c
        for i in range(1, len(f) - 1):
            vol += a.dot((verts[f[i]] - c).cross(verts[f[i + 1]] - c))
    return vol


class Acc:
    """Vertices, faces and per-vertex data, gathered part by part."""

    def __init__(self):
        self.v = []
        self.f = []
        self.col = []
        self.pbr = []
        self.bones = []
        self.uv = []
        self.pre = None
        # Per face: its corners' UVs in metres (None: Smart UV Project), whether
        # it is a hidden inner face, and its texel density against the rest.
        self.luv = []
        self.inner = []
        self.fd = []
        self.dens = 1.0

    def push(self, verts, faces, mat, bones, uv=None, luv=None, inner=None, closed=False):
        base = len(self.v)
        pre = self.pre
        if closed and signed_volume(verts, faces) < 0.0:
            faces = [list(reversed(f)) for f in faces]
            if luv:
                luv = [list(reversed(l)) if l else None for l in luv]
        for p in verts:
            self.v.append(pre @ p if pre is not None else p.copy())
        for k, f in enumerate(faces):
            self.f.append([base + i for i in f])
            self.luv.append(luv[k] if luv else None)
            self.inner.append(bool(inner[k]) if inner else False)
            self.fd.append(self.dens)
        (c, rust, metal, rough) = mat
        # No two plates quite the same colour.
        jit = RNG.uniform(0.88, 1.1) if rust > 0.0 else 1.0
        col = (c[0] * jit, c[1] * jit, c[2] * jit, rust)
        for _i in verts:
            self.col.append(col)
            self.pbr.append((metal, rough, 0.0, 1.0))
            self.bones.append(bones)
        if uv is not None:
            self.uv.extend(uv)
        return base


RNG = random.Random(127)
A = Acc()      # the plate, low
H = Acc()      # high-only detail
G = Acc()      # the glow
C = Acc()      # the mantle
SP = Acc()     # the spear, low
SH = Acc()     # the spear, high-only detail


def lathe(acc, prof, mat, bones, n=24, c=(0.0, 0.0), sx=1.0, sy=1.0, xf=None, cap0=True, cap1=True):
    """A surface of revolution about local Z: `prof` is [(r, z)..]. r 0 at an
    end is a pole; otherwise the end is capped unless told not to. Angle 0 is
    local +Y, 90 is local +X."""
    verts, faces, luv = [], [], []
    rows = []
    length = [0.0]
    for (r0, z0), (r1, z1) in zip(prof, prof[1:]):
        length.append(length[-1] + math.hypot(r1 - r0, z1 - z0))
    pole0 = prof[0][0] < 1e-5
    pole1 = prof[-1][0] < 1e-5
    rbar = sum(p[0] for p in prof) / len(prof)

    def uvat(k, i):
        a = 2.0 * math.pi * i / n
        if pole0:
            return (length[k] * math.sin(a), length[k] * math.cos(a))
        if pole1:
            d = length[-1] - length[k]
            return (d * math.sin(a), d * math.cos(a))
        return (a * rbar, length[k])

    for r, z in prof:
        if r < 1e-5:
            rows.append([len(verts)])
            verts.append(V(c[0], c[1], z))
            continue
        row_ = []
        for i in range(n):
            a = 2.0 * math.pi * i / n
            row_.append(len(verts))
            verts.append(V(c[0] + r * sx * math.sin(a), c[1] + r * sy * math.cos(a), z))
        rows.append(row_)
    for k, (a, b) in enumerate(zip(rows, rows[1:])):
        if len(a) == 1 and len(b) == 1:
            continue
        for i in range(n):
            j = (i + 1) % n
            if len(a) == 1:
                faces.append([a[0], b[j], b[i]])
                luv.append([uvat(k, i + 0.5), uvat(k + 1, i + 1), uvat(k + 1, i)])
            elif len(b) == 1:
                faces.append([a[i], a[j], b[0]])
                luv.append([uvat(k, i), uvat(k, i + 1), uvat(k + 1, i + 0.5)])
            else:
                faces.append([a[i], a[j], b[j], b[i]])
                luv.append([uvat(k, i), uvat(k, i + 1), uvat(k + 1, i + 1), uvat(k + 1, i)])

    def cap_uv(r, order):
        return [(r * math.sin(2.0 * math.pi * i / n), r * math.cos(2.0 * math.pi * i / n)) for i in order]

    if cap0 and len(rows[0]) > 1:
        faces.append(list(reversed(rows[0])))
        luv.append(cap_uv(prof[0][0], reversed(range(n))))
    if cap1 and len(rows[-1]) > 1:
        faces.append(list(rows[-1]))
        luv.append(cap_uv(prof[-1][0], range(n)))
    # Faces outward: a profile running down the axis winds outward as it is.
    if sum((z0 - z1) * (r0 + r1) for (r0, z0), (r1, z1) in zip(prof, prof[1:])) < 0.0:
        faces = [list(reversed(f)) for f in faces]
        luv = [list(reversed(l)) for l in luv]
    if xf is not None:
        verts = [xf @ p for p in verts]
    acc.push(verts, faces, mat, bones, luv=luv)


class Surf:
    """A shell's outer surface, for what sits on it."""

    def __init__(self, fn, hint):
        self.fn = fn
        self.hint = hint

    def at(self, u, v):
        e = 0.01
        p = self.fn(u, v)
        du = self.fn(u + e, v) - self.fn(u - e, v)
        dv = self.fn(u, v + e) - self.fn(u, v - e)
        n = du.cross(dv)
        if n.length < 1e-9:
            n = p - self.hint
        n.normalize()
        if n.dot(p - self.hint) < 0.0:
            n = -n
        return p, n


def shell(acc, fn, nu, nv, t, mat, bones, hint, wrap=False, xf=None):
    """A curved plate of thickness `t`, its outer face fn(u, v), `hint` a point
    on the inside."""
    su = Surf(fn, hint)
    cols = nu if wrap else nu + 1
    outer, inner = [], []
    for i in range(cols):
        for j in range(nv + 1):
            p, n = su.at(i / nu, j / nv)
            outer.append(p)
            inner.append(p - n * t)
    verts = outer + inner
    m = len(outer)
    idx = lambda i, j: (i % cols) * (nv + 1) + j
    U = [0.0]
    for i in range(nu):
        U.append(U[-1] + (su.at((i + 1) / nu, 0.5)[0] - su.at(i / nu, 0.5)[0]).length)
    W = [0.0]
    for j in range(nv):
        W.append(W[-1] + (su.at(0.5, (j + 1) / nv)[0] - su.at(0.5, j / nv)[0]).length)
    faces, luv, hid = [], [], []

    def add(f, l=None, h=False):
        faces.append(f)
        luv.append(l)
        hid.append(h)

    for i in range(nu):
        for j in range(nv):
            q = [idx(i, j), idx(i + 1, j), idx(i + 1, j + 1), idx(i, j + 1)]
            add(q, [(U[i], W[j]), (U[i + 1], W[j]), (U[i + 1], W[j + 1]), (U[i], W[j + 1])])
            add([m + k for k in reversed(q)], None, True)
    # The rims stay joined to the plate's island.
    for i in range(nu):
        add([idx(i, 0), m + idx(i, 0), m + idx(i + 1, 0), idx(i + 1, 0)],
            [(U[i], 0.0), (U[i], -t), (U[i + 1], -t), (U[i + 1], 0.0)])
        add([idx(i + 1, nv), m + idx(i + 1, nv), m + idx(i, nv), idx(i, nv)],
            [(U[i + 1], W[nv]), (U[i + 1], W[nv] + t), (U[i], W[nv] + t), (U[i], W[nv])])
    if not wrap:
        for j in range(nv):
            add([idx(nu, j), m + idx(nu, j), m + idx(nu, j + 1), idx(nu, j + 1)],
                [(U[nu], W[j]), (U[nu] + t, W[j]), (U[nu] + t, W[j + 1]), (U[nu], W[j + 1])])
            add([idx(0, j + 1), m + idx(0, j + 1), m + idx(0, j), idx(0, j)],
                [(0.0, W[j + 1]), (-t, W[j + 1]), (-t, W[j]), (0.0, W[j])])
    if xf is not None:
        verts = [xf @ p for p in verts]
        fn0 = fn
        su = Surf(lambda u, v, f=fn0, x=xf: x @ f(u, v), xf @ hint)
    acc.push(verts, faces, mat, bones, luv=luv, inner=hid, closed=True)
    return su


def band(acc, mat, bones, c, rx, ry, z0, z1, a0, a1, nu=16, nv=3, t=0.005, rb=1.0, zb=None, zt=None,
         rad=None, xf=None, rc=0.0, wrap=False):
    """A plate round an upright axis at `c`, from angle a0 to a1 (degrees, 0 is
    +Y, 90 is +X), z0 to z1. rb: the bottom's radius against the top's. zb, zt:
    its bottom and top edges bent (of u). rad: extra radius (of u, v). rc: the
    corners rounded, as a share of the plate's length."""
    cx, cy = c
    span = z1 - z0

    def fn(u, v):
        a = math.radians(lerp(a0, a1, u))
        cut = 0.0
        d = abs(2.0 * u - 1.0)
        if rc > 0.0 and d > 1.0 - rc:
            k = (d - (1.0 - rc)) / rc
            cut = (1.0 - math.sqrt(max(0.0, 1.0 - k * k))) * span * 0.42
        lo = z0 + (zb(u) if zb else 0.0) + cut
        hi = z1 + (zt(u) if zt else 0.0) - cut
        s = lerp(rb, 1.0, v)
        e = rad(u, v) if rad else 0.0
        return V(cx + (rx * s + e) * math.sin(a), cy + (ry * s + e) * math.cos(a), lerp(lo, hi, v))

    return shell(acc, fn, nu, nv, t, mat, bones, V(cx, cy, (z0 + z1) * 0.5), wrap=wrap, xf=xf)


def hemi(acc, p, n, r, mat=RIVET, bones=None):
    """A rivet head."""
    xf = frame(p, n, V(0, 1, 0) if abs(n.z) > 0.9 else V(0, 0, 1))
    lathe(acc, [(r * 1.25, -0.002), (r * 1.25, 0.0008), (r, r * 0.42), (r * 0.62, r * 0.72), (0.0, r * 0.8)],
          mat, bones or [], n=12, xf=xf, cap0=False)


def rivets(su, uvs, r=0.0078, acc=None, mat=RIVET):
    acc = acc or H
    for u, v in uvs:
        p, n = su.at(u, v)
        hemi(acc, p, n, r, mat)


def row(su, v, k, u0=0.06, u1=0.94, r=0.0078, acc=None):
    rivets(su, [(lerp(u0, u1, i / max(k - 1, 1)), v) for i in range(k)], r, acc)


def rbox(acc, size, mat, bones, xf, bevel=0.004):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = V(v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])
    bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges), offset=bevel, segments=1, affect='EDGES',
                    profile=0.5)
    bm.verts.index_update()
    verts = [xf @ v.co for v in bm.verts]
    faces = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    acc.push(verts, faces, mat, bones)


def gear(acc, mat, bones, c, axis, r, teeth, thick, depth=0.011, n_hole=0):
    """A real gear: `teeth` trapezoid teeth round a rim, chamfered."""
    xf = frame(c, axis)
    outline = []
    for k in range(teeth):
        a = 2.0 * math.pi * k / teeth
        w = 2.0 * math.pi / teeth
        for da, rr in ((-0.5 * 0.92, r), (-0.25 * 0.92, r + depth), (0.25 * 0.92, r + depth), (0.5 * 0.92, r)):
            b = a + w * da * 0.92
            outline.append((rr * math.sin(b), rr * math.cos(b)))
    m = len(outline)
    verts, faces = [], []
    ch = min(0.003, thick * 0.25)
    rings = [(-thick * 0.5, 1.0 - ch / r), (-thick * 0.5 + ch, 1.0), (thick * 0.5 - ch, 1.0), (thick * 0.5, 1.0 - ch / r)]
    for z, s in rings:
        for x, y in outline:
            verts.append(V(x * s, y * s, z))
    for i in range(3):
        for j in range(m):
            a = i * m + j
            b = i * m + (j + 1) % m
            faces.append([a, b, b + m, a + m])
    c0 = len(verts)
    verts.append(V(0, 0, -thick * 0.5))
    verts.append(V(0, 0, thick * 0.5))
    for j in range(m):
        faces.append([(j + 1) % m, j, c0])
        faces.append([3 * m + j, 3 * m + (j + 1) % m, c0 + 1])
    acc.push([xf @ p for p in verts], faces, mat, bones, closed=True)


def loft(acc, rings, mat, bones, cap0=True, cap1=True, xf=None):
    """Closed rings of equal size, one after another."""
    n = len(rings[0])
    verts = [p for r in rings for p in r]
    per = sum((r[i] - r[(i + 1) % n]).length for r in rings for i in range(n)) / len(rings)
    cen = [sum(r, Vector()) / n for r in rings]
    W = [0.0]
    for a, b in zip(cen, cen[1:]):
        W.append(W[-1] + (a - b).length)
    faces, luv = [], []
    for k in range(len(rings) - 1):
        for i in range(n):
            a = k * n + i
            b = k * n + (i + 1) % n
            faces.append([a, b, b + n, a + n])
            u0 = per * i / n
            u1 = per * (i + 1) / n
            luv.append([(u0, W[k]), (u1, W[k]), (u1, W[k + 1]), (u0, W[k + 1])])
    if cap0:
        faces.append(list(reversed(range(n))))
        luv.append(None)
    if cap1:
        faces.append([(len(rings) - 1) * n + i for i in range(n)])
        luv.append(None)
    if xf is not None:
        verts = [xf @ p for p in verts]
    acc.push(verts, faces, mat, bones, luv=luv, closed=cap0 and cap1)


def blade(acc, mat, bones, path, widths, thick, side=None, up=None, xf=None):
    """Forged steel: a diamond section along `path`, `widths` across (0 at a
    tip), `thick` through. It lies in the plane normal to `up`."""
    up = up or V(0, 0, 1)
    rings = []
    tip = None
    for i, p in enumerate(path):
        d = path[min(i + 1, len(path) - 1)] - path[max(i - 1, 0)]
        s = d.cross(up).normalized()
        w = widths[i]
        t = thick[i] if isinstance(thick, (list, tuple)) else thick * (w / max(widths))
        if w < 1e-5:
            tip = p
            continue
        rings.append([p + s * w, p + up * t, p - s * w, p - up * t])
    verts = [q for r in rings for q in r]
    faces = []
    for k in range(len(rings) - 1):
        for i in range(4):
            a = k * 4 + i
            b = k * 4 + (i + 1) % 4
            faces.append([a, b, b + 4, a + 4])
    faces.append([3, 2, 1, 0])
    if tip is not None:
        c = len(verts)
        verts.append(tip)
        last = (len(rings) - 1) * 4
        for i in range(4):
            faces.append([last + i, last + (i + 1) % 4, c])
    else:
        last = (len(rings) - 1) * 4
        faces.append([last, last + 1, last + 2, last + 3])
    if xf is not None:
        verts = [xf @ p for p in verts]
    acc.push(verts, faces, mat, bones, closed=True)


def b1(name):
    return [(name, 1.0)]


# --- The head ------------------------------------------------------------------------

def skull_pt(a, phi, off=0.0):
    """On the dome: a round the head, phi down from the crown (degrees)."""
    a = math.radians(a)
    phi = math.radians(phi)
    return V((0.160 + off) * math.sin(phi) * math.sin(a), (0.170 + off) * math.sin(phi) * math.cos(a),
             1.705 + (0.150 + off) * math.cos(phi))


def build_head():
    pre = (Matrix.Translation(HEAD_PIVOT) @ Matrix.Scale(HEAD_SCALE, 4)
           @ Matrix.Translation(-Vector(HEAD_PIVOT)))
    A.pre = H.pre = G.pre = pre
    A.dens = 1.7
    B = b1("Head")
    # The dome, brass, down to the brow; iron below it to the jaw.
    prof = [(0.0, 1.855)]
    for phi in (9, 20, 32, 45, 58, 70, 80):
        prof.append((0.160 * math.sin(math.radians(phi)), 1.705 + 0.150 * math.cos(math.radians(phi))))
    lathe(A, prof, BRASS, B, n=28, sy=1.0625, cap1=False)
    lathe(A, [(0.158, 1.733), (0.1605, 1.70), (0.156, 1.66), (0.145, 1.62), (0.125, 1.585)], IRON, B, n=28,
          sy=1.0625, cap0=False)
    # The gores of the dome: iron straps with rivets down them (baked).
    for a in (45, 90, 135, 225, 270, 315):
        rows = []
        for phi in range(14, 84, 7):
            cc = skull_pt(a, phi, 0.0022)
            side = V(math.cos(math.radians(a)), -math.sin(math.radians(a)), 0.0)
            rows.append([cc + side * 0.0085, cc + side * 0.0045 + V(0, 0, 0.0016) * 0, cc - side * 0.0045,
                         cc - side * 0.0085])
        strip = []
        for r in rows:
            strip.append([r[0], r[1] + (r[1] - V(0, 0, 1.705)).normalized() * 0.002,
                          r[2] + (r[2] - V(0, 0, 1.705)).normalized() * 0.002, r[3],
                          r[3] - (r[3] - V(0, 0, 1.705)).normalized() * 0.004,
                          r[0] - (r[0] - V(0, 0, 1.705)).normalized() * 0.004])
        loft(H, strip, IRON, [])
        for phi in range(22, 80, 11):
            p = skull_pt(a, phi, 0.004)
            hemi(H, p, (p - V(0, 0, 1.705)).normalized(), 0.0058)
    # The crest: a comb from the brow over the crown to the nape.
    ribbon = []
    for k in range(25):
        t = k / 24
        phi = lerp(-74.0, 96.0, t)
        lift = 0.031 * math.sin(math.pi * clamp((t + 0.04) / 1.08)) ** 0.7
        p = skull_pt(0.0, abs(phi), -0.004)
        if phi < 0.0:
            p.y = -abs(p.y) * -1.0
        else:
            p.y = -abs(p.y)
        o = (p - V(0, 0, 1.705)).normalized()
        top = p + o * (lift + 0.009)
        ribbon.append([p + V(0.008, 0, 0), top + V(0.0065, 0, 0), top - V(0.0065, 0, 0), p - V(0.008, 0, 0)])
    loft(A, ribbon, IRON2, B)
    # The brow band.
    su = band(A, IRON, B, (0.0, 0.0), 0.1665, 0.1765, 1.722, 1.752, 0.0, 360.0, nu=32, nv=2, t=0.008, wrap=True,
              rad=lambda u, v: 0.0034 * math.sin(v * math.pi))
    row(su, 0.5, 26, 0.0, 0.962, 0.0062)
    # The nape: two lames flaring out over the neck.
    for k, (z0, z1, r) in enumerate(((1.615, 1.68, 0.168), (1.57, 1.635, 0.178))):
        su = band(A, BRASS if k == 0 else IRON, B, (0.0, -0.01), r, r * 1.03, z0, z1, 92.0, 268.0, nu=14, nv=2,
                  t=0.006, rb=1.13, rc=0.22)
        row(su, 0.8, 7, 0.1, 0.9, 0.0065)
    # The cheeks, brass, and the nasal between the goggles.
    for s in (1.0, -1.0):
        su = band(A, BRASS2, B, (0.0, 0.0), 0.1645, 0.1755, 1.602, 1.706, s * 42.0, s * 106.0, nu=10, nv=4,
                  t=0.006, rb=0.9, rc=0.4, zt=lambda u: 0.012 * (u - 0.5))
        rivets(su, [(0.2, 0.75), (0.5, 0.86), (0.8, 0.75), (0.86, 0.3), (0.5, 0.2)], 0.0068)
    su = band(A, BRASS, B, (0.0, 0.0), 0.169, 0.179, 1.655, 1.772, -10.0, 10.0, nu=4, nv=5, t=0.006,
              rad=lambda u, v: 0.0025 * math.cos((u - 0.5) * 3.0) + 0.012 * (1.0 - v) * (1.0 - v) - 0.016 * v * v,
              zb=lambda u: 0.006 * abs(2.0 * u - 1.0))
    rivets(su, [(0.5, 0.2), (0.5, 0.5), (0.5, 0.8)], 0.0062)
    # The mouth: a dark slot, its lip above and its jaw below, the teeth between.
    droop = lambda u: -0.016 * (2.0 * u - 1.0) ** 2
    band(A, DARK, B, (0.0, 0.0), 0.143, 0.152, 1.585, 1.655, -74.0, 74.0, nu=12, nv=1, t=0.01)
    su = band(A, IRON, B, (0.0, 0.0), 0.1565, 0.169, 1.634, 1.668, -60.0, 60.0, nu=14, nv=2, t=0.008,
              zb=droop, rad=lambda u, v: 0.004 * math.sin(v * math.pi))
    row(su, 0.72, 7, 0.1, 0.9, 0.0056)
    su = band(A, BRASS, B, (0.0, 0.0), 0.150, 0.164, 1.552, 1.603, -104.0, 104.0, nu=18, nv=4, t=0.008, rb=0.68,
              zt=lambda u: -0.016 * (2.0 * u - 1.0) ** 2,
              rad=lambda u, v: 0.008 * math.sin(v * math.pi))
    row(su, 0.82, 11, 0.08, 0.92, 0.0056)
    rivets(su, [(0.0, 0.7), (1.0, 0.7)], 0.0105)
    for k in range(-4, 5):
        a = k * 10.8
        t = a / 54.0
        z = 1.6185 - 0.016 * t * t * 0.9
        h = 0.036 - abs(k) * 0.0016
        rr = lerp(0.1565, 0.169, 0.5 * (1.0 + math.cos(math.radians(a * 2.0)))) * 0.0 + 0.0
        y = 0.163 * math.cos(math.radians(a))
        x = 0.152 * math.sin(math.radians(a))
        xf = Matrix.Translation(V(x, y, z)) @ Matrix.Rotation(-math.radians(a), 4, 'Z')
        rbox(A, (0.0135, 0.016, h), STEEL, B, xf, 0.0024)
    # The goggles.
    for s in (1.0, -1.0):
        goggle(s, B)
        # The ear gear and the drum it turns on.
        ear = V(s * 0.166, 0.004, 1.692)
        ax = V(s, 0, 0)
        lathe(A, [(0.044, -0.03), (0.046, 0.0), (0.046, 0.01), (0.04, 0.014)], IRON2, B, n=16, xf=frame(ear, ax))
        gear(A, BRASS, B, ear + ax * 0.018, ax, 0.05, 10, 0.021)
        lathe(A, [(0.0, 0.05), (0.012, 0.049), (0.023, 0.044), (0.025, 0.035), (0.025, 0.0)], IRON, B, n=12,
              xf=frame(ear, ax), cap1=False)
        xfg = frame(ear + ax * 0.03, ax)
        for k in range(5):
            a = 2.0 * math.pi * k / 5.0
            hemi(H, xfg @ V(math.sin(a) * 0.037, math.cos(a) * 0.037, 0.0), ax, 0.0052)
    # The antennae: a long one, a short bent one.
    for base, ax, length, r, tip in ((V(0.062, -0.05, 1.835), V(0.1, -0.17, 1.0), 0.33, 0.0062, 0.013),
                                     (V(-0.078, -0.055, 1.822), V(-0.58, -0.3, 0.76), 0.16, 0.0052, 0.0)):
        xf = frame(base, ax)
        lathe(A, [(0.024, -0.03), (0.024, 0.006), (0.019, 0.016), (0.012, 0.022), (0.012, 0.04), (0.009, 0.044)],
              IRON, B, n=12, xf=xf)
        lathe(A, [(r, 0.03), (r * 0.72, length)], STEEL, B, n=7, xf=xf)
        if tip > 0.0:
            lathe(A, [(0.0, length - tip), (tip * 0.75, length - tip * 0.65), (tip, length), (tip * 0.75, length + tip * 0.65),
                      (0.0, length + tip)], BRASS, B, n=10, xf=xf)
            lathe(A, [(r * 0.9, length * 0.5 - 0.006), (r * 1.7, length * 0.5 - 0.002), (r * 1.7, length * 0.5 + 0.002),
                      (r * 0.9, length * 0.5 + 0.006)], BRASS, B, n=8, xf=xf)
        else:
            lathe(A, [(0.0065, length), (0.0065, length + 0.012), (0.0, length + 0.016)], IRON, B, n=7, xf=xf)
    A.pre = H.pre = G.pre = None
    A.dens = 1.0
    # The neck: a ribbed iron column, a bellows.
    N = b1("Neck")
    prof = []
    z = 1.485
    while z < 1.60:
        prof += [(0.056, z), (0.066, z + 0.008), (0.066, z + 0.016), (0.056, z + 0.024)]
        z += 0.024
    lathe(A, prof, DARK, N, n=14, sy=1.04)


def goggle(s, B):
    """Brass housing, knurled iron bezel, dark glass, the cyan ring and pupil.
    Turned a little outward, an insect's eyes; a brass hood bent low over the
    inner side of each makes the stare a glare."""
    base = V(s * 0.0725, 0.128, 1.704)
    ax = V(s * 0.17, 1.0, 0.0).normalized()
    xf = frame(base, ax)
    lathe(A, [(0.057, -0.03), (0.058, 0.03), (0.0635, 0.033), (0.0635, 0.043)], BRASS, B, n=24, xf=xf, cap0=False)
    lathe(A, [(0.0635, 0.04), (0.0695, 0.043), (0.0695, 0.062), (0.066, 0.067), (0.056, 0.068), (0.0525, 0.058)],
          IRON, B, n=24, xf=xf, cap0=False)
    lathe(A, [(0.0535, 0.056), (0.04, 0.0595), (0.02, 0.062), (0.0, 0.0625)], GLASS, B, n=24, xf=xf, cap0=False)
    # The ring and the pupil.
    lathe(G, [(0.0255, 0.0615), (0.0275, 0.0635), (0.0365, 0.0620), (0.0385, 0.0595)], ((1, 1, 1), 0, 0, 0), B, n=28,
          xf=xf, cap0=False, cap1=False)
    lathe(G, [(0.0125, 0.0625), (0.009, 0.0645), (0.0, 0.0652)], ((1, 1, 1), 0, 0, 0), B, n=14, xf=xf, cap0=False)
    # Knurling on the bezel, and its screws.
    for k in range(36):
        a = 2.0 * math.pi * k / 36.0
        lf = Matrix.Rotation(a, 4, 'Z')
        rbox(H, (0.0018, 0.0038, 0.0165), IRON, [], xf @ lf @ Matrix.Translation(V(0.0, 0.0693, 0.0525)), 0.0006)
    for k in range(4):
        a = math.pi * 0.25 + k * math.pi * 0.5
        p = xf @ V(math.sin(a) * 0.0605, math.cos(a) * 0.0605, 0.0685)
        hemi(H, p, ax, 0.0052)

    def hood(u, v):
        a = math.radians(lerp(-96.0, 96.0, u) + s * 30.0)
        ends = abs(2.0 * u - 1.0) ** 3
        r = 0.0742 + 0.0048 * math.sin(math.pi * v) - 0.0095 * smooth((v - 0.62) / 0.38) * (1.0 - ends)
        far = lerp(-0.005, 0.0775 - 0.03 * ends, v)
        return V(r * math.sin(a), r * math.cos(a), far)

    su = shell(A, hood, 14, 4, 0.0045, BRASS2, B, V(0, 0, 0.035), xf=xf)
    rivets(su, [(0.14, 0.25), (0.5, 0.2), (0.86, 0.25)], 0.0056)


# --- The body ------------------------------------------------------------------------

RX_F = [(1.17, 0.168), (1.22, 0.19), (1.28, 0.212), (1.34, 0.226), (1.40, 0.222), (1.46, 0.195), (1.51, 0.14)]
RY_F = [(1.17, 0.120), (1.22, 0.142), (1.28, 0.165), (1.34, 0.182), (1.40, 0.178), (1.46, 0.145), (1.51, 0.10)]


def chest_pt(a_deg, z, ry_back=0.82, off=0.0):
    a = math.radians(a_deg)
    rx = curve(z, RX_F) + off
    ry = (curve(z, RY_F) if math.cos(a) > 0.0 else curve(z, RY_F) * ry_back) + off
    return V(rx * math.sin(a), ry * math.cos(a), z)


def build_torso():
    Cb = b1("Chest")
    Sb = b1("Spine")
    Pb = b1("Hips")
    half_cs = [("Chest", 0.5), ("Spine", 0.5)]
    half_sp = [("Spine", 0.5), ("Hips", 0.5)]
    # The core, seen through the gaps.
    lathe(A, [(0.135, 1.5), (0.195, 1.42), (0.205, 1.32), (0.17, 1.22), (0.145, 1.19)], DARK, Cb, n=20, sy=0.78)
    lathe(A, [(0.14, 1.235), (0.135, 1.1), (0.15, 1.02)], DARK, Sb, n=18, sy=0.76)

    # The breastplate: a pigeon-breast with a raised keel down the middle.
    def breast(u, v):
        a = lerp(-122.0, 122.0, u)
        ea = abs(a) / 122.0
        top = 1.485 - 0.075 * ea ** 1.5
        bot = 1.205 + 0.03 * ea ** 2
        z = lerp(bot, top, v)
        p = chest_pt(a, z)
        keel = 0.015 * math.exp(-((a / 13.0) ** 2)) * math.sin(math.pi * clamp(0.1 + 0.9 * v))
        d = V(math.sin(math.radians(a)), math.cos(math.radians(a)), 0.0)
        return p + d * keel

    su = shell(A, breast, 26, 8, 0.008, BRASS, Cb, V(0, 0, 1.33))
    row(su, 0.975, 15, 0.07, 0.93, 0.0072)
    row(su, 0.03, 15, 0.07, 0.93, 0.0072)
    rivets(su, [(0.03, v / 7.0) for v in range(1, 7)] + [(0.97, v / 7.0) for v in range(1, 7)], 0.0072)
    for k in range(6):
        rivets(su, [(0.5, 0.16 + 0.13 * k)], 0.0062)
    # An iron bar down each side of the keel, and across the top of the belly.
    for u0 in (0.41, 0.59):
        fn = lambda u, v, u0=u0: breast(u0 + (u - 0.5) * 0.012, lerp(0.12, 0.94, v)) + V(0, 0.003, 0)
        s2 = shell(H, fn, 2, 6, 0.004, IRON, [], V(0, 0, 1.33))
    # The back plate, iron, and the power box bolted to it.
    def back(u, v):
        a = lerp(118.0, 242.0, u)
        z = lerp(1.215, 1.47, v)
        return chest_pt(a, z, off=0.004)

    su = shell(A, back, 16, 5, 0.008, IRON, Cb, V(0, 0, 1.33))
    row(su, 0.95, 9, 0.08, 0.92, 0.007)
    row(su, 0.05, 9, 0.08, 0.92, 0.007)
    xf = Matrix.Translation(V(0, -0.175, 1.325))
    rbox(A, (0.21, 0.09, 0.2), IRON2, Cb, xf, 0.01)
    rbox(A, (0.16, 0.022, 0.13), BRASS2, Cb, Matrix.Translation(V(0, -0.228, 1.325)), 0.005)
    for s in (1.0, -1.0):
        xf2 = frame(V(s * 0.085, -0.222, 1.325), V(0, 0, 1))
        lathe(A, [(0.016, -0.115), (0.016, 0.115)], BRASS, Cb, n=8, xf=xf2)
        for z in (1.235, 1.415):
            hemi(H, V(s * 0.095, -0.222, z), V(0, -1, 0), 0.0082)
    # The gorget: a collar standing round the neck.
    lathe(A, [(0.198, 1.425), (0.165, 1.47), (0.135, 1.505), (0.118, 1.53), (0.116, 1.555), (0.126, 1.562), (0.133, 1.557)],
          BRASS, Cb, n=26, sy=0.92, cap0=False)
    lathe(A, [(0.133, 1.559), (0.126, 1.566), (0.112, 1.562), (0.104, 1.54), (0.1, 1.5)], IRON, Cb, n=26, sy=0.92, cap1=False)
    for k in range(16):
        a = 2.0 * math.pi * k / 16.0
        n = V(math.sin(a), math.cos(a), 0.45).normalized()
        hemi(H, V(0.161 * math.sin(a), 0.148 * math.cos(a), 1.477), n, 0.0066)
    # The belly: overlapping lames, each half on the bones either side.
    lames = (
        (1.215, 1.15, 0.180, 0.133, half_cs, BRASS),
        (1.168, 1.106, 0.172, 0.128, Sb, IRON),
        (1.122, 1.062, 0.170, 0.128, half_sp, BRASS2),
    )
    for z1, z0, rx, ry, w, mat in lames:
        su = band(A, mat, w, (0.0, 0.0), rx, ry, z0, z1, 0.0, 360.0, nu=26, nv=3, t=0.012, rb=1.09, wrap=True,
                  rad=lambda u, v: 0.0025 * math.sin(v * math.pi))
        rivets(su, [(i / 14.0, 0.28) for i in range(14)], 0.0066)
    # The pelvis, the belt and its buckle.
    lathe(A, [(0.15, 1.085), (0.172, 1.03), (0.185, 0.97), (0.17, 0.91), (0.12, 0.885)], IRON2, Pb, n=22, sy=0.8)
    su = band(A, LEATHER, Pb, (0.0, 0.0), 0.196, 0.161, 1.018, 1.07, 0.0, 360.0, nu=28, nv=2, t=0.012, wrap=True,
              rb=1.03, rad=lambda u, v: 0.002 * math.sin(v * math.pi))
    rivets(su, [(i / 18.0, 0.5) for i in range(18)], 0.0058)
    rbox(A, (0.085, 0.022, 0.07), BRASS, Pb, Matrix.Translation(V(0, 0.168, 1.044)), 0.006)
    rbox(A, (0.046, 0.026, 0.034), IRON2, Pb, Matrix.Translation(V(0, 0.17, 1.044)), 0.004)
    # Pouches on the belt, flaps buckled down.
    for x, y, rot, w in ((0.165, 0.09, -0.75, 0.095), (-0.185, -0.03, 1.45, 0.08)):
        xf = Matrix.Translation(V(x, y, 0.975)) @ Matrix.Rotation(rot, 4, 'Z')
        rbox(A, (w, 0.058, 0.105), LEATHER, Pb, xf, 0.012)
        rbox(A, (w + 0.008, 0.064, 0.034), LEATHER, Pb, xf @ Matrix.Translation(V(0, 0.002, 0.04)), 0.009)
        rbox(A, (0.016, 0.009, 0.016), BRASS, Pb, xf @ Matrix.Translation(V(0, 0.034, 0.03)), 0.003)
    # The placket over the groin; the skirt behind.
    su = band(A, BRASS, Pb, (0.0, 0.0), 0.175, 0.150, 0.862, 1.022, -30.0, 30.0, nu=8, nv=4, t=0.007, rb=1.05, rc=0.5,
              rad=lambda u, v: 0.008 * math.exp(-((u - 0.5) / 0.14) ** 2))
    rivets(su, [(0.2, 0.86), (0.8, 0.86), (0.08, 0.6), (0.92, 0.6)], 0.0066)
    for k, (z0, z1) in enumerate(((0.905, 1.02), (0.83, 0.925))):
        su = band(A, IRON if k == 0 else BRASS2, Pb, (0.0, 0.0), 0.19, 0.17, z0, z1, 142.0, 218.0, nu=8, nv=2, t=0.007,
                  rb=1.08, rc=0.4 if k == 1 else 0.0)
        row(su, 0.8, 5, 0.1, 0.9, 0.0066)
    # The tassets, half on the hip, half on the thigh beneath.
    for s in (1.0, -1.0):
        w = [("Hips", 0.5), ("ThighR" if s > 0.0 else "ThighL", 0.5)]
        cc = (s * 0.075, 0.0)
        su = band(A, BRASS, w, cc, 0.128, 0.158, 0.862, 1.022, s * 28.0, s * 130.0, nu=10, nv=3, t=0.007, rb=1.1)
        row(su, 0.84, 6, 0.08, 0.92, 0.0066)
        su = band(A, IRON, w, cc, 0.141, 0.172, 0.772, 0.884, s * 28.0, s * 130.0, nu=10, nv=3, t=0.007, rb=1.07, rc=0.28)
        row(su, 0.82, 6, 0.1, 0.9, 0.0066)
        # Its strap to the belt.
        p = su.at(0.5, 1.0)[0]
        rbox(H, (0.022, 0.006, 0.05), LEATHER, [], Matrix.Translation(p + V(0, 0, 0.012)) @ Matrix.Rotation(-s * 1.35, 4, 'Z'), 0.002)


def build_arm(s):
    r = s > 0.0
    side = "R" if r else "L"
    U = b1("UpperArm" + side)
    F = b1("Forearm" + side)
    Hd = b1("Hand" + side)
    pw = [("Chest", 0.5), ("UpperArm" + side, 0.5)]
    x = s * 0.21
    # The pauldron: a great dome, a rolled rim, three lames beneath.
    xf = Matrix.Translation(V(s * 0.262, 0.0, 1.462)) @ Matrix.Rotation(s * math.radians(13.0), 4, 'Y')
    lathe(A, [(0.0, 0.085), (0.05, 0.082), (0.096, 0.067), (0.127, 0.04), (0.143, 0.004), (0.145, -0.012)], BRASS, pw, n=24,
          sy=1.13, xf=xf, cap1=False)
    lathe(A, [(0.143, -0.008), (0.152, -0.008), (0.156, -0.016), (0.152, -0.024), (0.143, -0.024)], IRON, pw, n=24,
          sy=1.13, xf=xf, cap0=False, cap1=False)
    # A rib across the dome, front to back, and rivets round its skirt.
    for k in range(14):
        a = 2.0 * math.pi * k / 14.0
        p = V(0.128 * math.sin(a), 0.128 * 1.13 * math.cos(a), 0.022)
        n = V(math.sin(a), math.cos(a), 0.75).normalized()
        hemi(H, xf @ p, xf.to_3x3() @ n, 0.0074)
    rings = []
    for k in range(13):
        a = math.radians(lerp(-62.0, 62.0, k / 12.0))
        cz = 0.092 * math.cos(a * 0.98) - 0.012
        cy = 0.15 * math.sin(a)
        o = V(0, math.sin(a), math.cos(a))
        t = V(0, 0, 0)
        rings.append([V(0.012, cy, cz), V(0.0095, cy, cz) + o * 0.02, V(-0.0095, cy, cz) + o * 0.02, V(-0.012, cy, cz)])
    loft(A, rings, IRON, pw, xf=xf @ Matrix.Rotation(s * math.radians(14.0), 4, 'Y'))
    a0, a1 = (-20.0, 200.0) if r else (20.0, -200.0)
    for k, (z0, z1, rx, ry, mat) in enumerate(((-0.07, -0.02, 0.145, 0.164, IRON), (-0.108, -0.058, 0.135, 0.153, BRASS),
                                               (-0.145, -0.096, 0.122, 0.138, IRON))):
        su = band(A, mat, pw, (0.0, 0.0), rx, ry, z0, z1, a0, a1, nu=16, nv=2, t=0.006, rb=0.95, rc=0.2, xf=xf,
                  rad=lambda u, v: 0.0022 * math.sin(math.pi * v))
        row(su, 0.72, 9, 0.08, 0.92, 0.0062)
    # The upper arm: a dark core, a plate tube.
    lathe(A, [(0.05, 1.34), (0.05, 1.17)], DARK, U, n=12, c=(x, 0.0))
    su = band(A, IRON, U, (x, 0.0), 0.067, 0.067, 1.185, 1.325, 0.0, 360.0, nu=18, nv=3, t=0.01, rb=0.9, wrap=True)
    rivets(su, [(i / 8.0, 0.9) for i in range(8)], 0.006)
    band(A, BRASS2, U, (x, 0.0), 0.0625, 0.0625, 1.178, 1.2, 0.0, 360.0, nu=16, nv=1, t=0.008, wrap=True)
    # The elbow: a ball, a gear at the side, a winged cop behind.
    lathe(A, [(0.0, 1.195), (0.038, 1.18), (0.052, 1.14), (0.038, 1.1), (0.0, 1.085)], IRON2, F, n=14, c=(x, 0.0))
    ax = V(s, 0, 0)
    gear(A, BRASS, F, V(x + s * 0.052, 0.0, 1.14), ax, 0.05, 10, 0.016, 0.0095)
    lathe(A, [(0.0, 0.024), (0.018, 0.021), (0.02, 0.0)], IRON, F, n=10, xf=frame(V(x + s * 0.054, 0.0, 1.14), ax), cap1=False)
    xfc = frame(V(x, 0.008, 1.14), V(0, -1, 0))
    lathe(A, [(0.0, 0.074), (0.03, 0.071), (0.054, 0.056), (0.066, 0.034), (0.069, 0.012)], BRASS, F, n=14, sx=0.86, sy=1.18,
          xf=xfc, cap1=False)
    # The vambrace, tapering to the wrist, a raised rib along its back.
    prof = [(0.058, 1.102), (0.068, 1.078), (0.074, 1.03), (0.072, 0.98), (0.063, 0.925), (0.056, 0.888)]
    lathe(A, prof, BRASS, F, n=16, c=(x, 0.0), sy=1.05)
    for z0, z1 in ((1.074, 1.098), (0.893, 0.915)):
        su = band(A, IRON, F, (x, 0.0), 0.073, 0.077, z0, z1, 0.0, 360.0, nu=16, nv=1, t=0.01, wrap=True)
        rivets(su, [(i / 7.0, 0.5) for i in range(7)], 0.0052)
    band(A, IRON2, F, (x, 0.0), 0.0735, 0.0775, 0.925, 1.075, s * 160.0, s * 200.0, nu=4, nv=4, t=0.008,
         rad=lambda u, v: 0.005 * math.sin(math.pi * u) + 0.0115 * math.sin(math.pi * clamp(0.25 + 0.7 * v)) - 0.012 * (1.0 - v))
    for z in (0.95, 1.0, 1.05):
        hemi(H, V(x + s * 0.0745, 0.0, z), ax, 0.0062)
    # The gauntlet: a flared cuff, the hand's back in lames, a palm, and fingers
    # closed on the shaft (fore and aft through the fist, 0.07 under the wrist).
    su = band(A, IRON, Hd, (x, 0.0), 0.058, 0.061, 0.815, 0.884, 0.0, 360.0, nu=16, nv=2, t=0.008, rb=1.14, wrap=True)
    rivets(su, [(i / 8.0, 0.5) for i in range(8)], 0.0052)
    A.dens = 1.5
    cx = V(x, 0.0, 0.78)
    rbox(A, (0.058, 0.094, 0.062), IRON2, Hd, Matrix.Translation(V(x + s * 0.006, 0.0, 0.822)), 0.012)
    for k, (dz, mat) in enumerate(((0.052, BRASS), (0.033, IRON), (0.013, BRASS2))):
        xf2 = Matrix.Translation(V(x + s * (0.042 + 0.003 * k), 0.0, 0.78 + dz)) @ Matrix.Rotation(s * (-0.1 - 0.38 * k), 4, 'Y')
        rbox(A, (0.012, 0.098, 0.03), mat, Hd, xf2, 0.004)
    for f, y in enumerate((-0.0345, -0.0115, 0.0115, 0.0345)):
        finger(s, V(x, y, 0.78), Hd)
    # The thumb, over the shaft from the palm side.
    th_c = V(x, 0.043, 0.78)
    for k, (a0, a1) in enumerate(((168.0, 118.0), (112.0, 68.0))):
        arc_seg(s, th_c, a0, a1, 0.0355 - 0.002 * k, 0.0235 - 0.002 * k, 0.0235, IRON if k == 0 else BRASS2, Hd)
    A.dens = 1.0


def arc_seg(s, c, a0, a1, r, w, t, mat, bones):
    """A finger joint: a box bent round the shaft; angle 0 at the back of the
    hand, going under the shaft (+) to the palm side."""
    rings = []
    for i in range(4):
        a = math.radians(lerp(a0, a1, i / 3))
        d = V(s * math.cos(a), 0.0, -math.sin(a))
        ring = []
        for dy, dr in ((w * 0.5, -t * 0.5), (w * 0.5, t * 0.32), (w * 0.32, t * 0.5), (-w * 0.32, t * 0.5), (-w * 0.5, t * 0.32),
                       (-w * 0.5, -t * 0.5)):
            ring.append(c + d * (r + dr) + V(0, dy, 0))
        rings.append(ring)
    loft(A, rings, mat, bones)


def finger(s, c, bones):
    arc_seg(s, c, -38.0, 22.0, 0.0345, 0.0205, 0.024, IRON, bones)
    arc_seg(s, c, 26.0, 86.0, 0.0335, 0.0195, 0.023, BRASS2, bones)
    arc_seg(s, c, 90.0, 146.0, 0.0325, 0.0185, 0.0215, IRON, bones)


def build_leg(s):
    r = s > 0.0
    side = "R" if r else "L"
    T = b1("Thigh" + side)
    Sh = b1("Shin" + side)
    Ft = b1("Foot" + side)
    x = s * 0.11
    # The thigh: a core, a cuisse round the front and side, a strap behind.
    lathe(A, [(0.086, 0.93), (0.092, 0.82), (0.074, 0.63), (0.05, 0.585)], DARK, T, n=14, c=(x, 0.0), sy=1.05)
    ridge = lambda u, v: 0.009 * math.exp(-((u - 0.5) / 0.1) ** 2) * math.sin(math.pi * clamp(0.15 + 0.8 * v))
    su = band(A, BRASS, T, (x, 0.0), 0.1, 0.106, 0.70, 0.875, -128.0, 128.0, nu=18, nv=3, t=0.007, rb=0.9, rc=0.12,
              rad=ridge)
    row(su, 0.14, 9, 0.05, 0.95, 0.0066)
    su = band(A, BRASS2, T, (x, 0.0), 0.0925, 0.098, 0.57, 0.72, -122.0, 122.0, nu=18, nv=3, t=0.007, rb=0.89, rc=0.14,
              rad=ridge)
    row(su, 0.84, 9, 0.05, 0.95, 0.0066)
    band(H, LEATHER, [], (x, 0.0), 0.092, 0.096, 0.665, 0.69, 125.0, 235.0, nu=8, nv=1, t=0.004)
    su = band(A, IRON, T, (x, 0.0), 0.0805, 0.0875, 0.535, 0.60, -92.0, 92.0, nu=12, nv=2, t=0.006, rb=0.95, rc=0.2)
    row(su, 0.7, 5, 0.1, 0.9, 0.006)
    # The knee: a ball, a gear at the side, a domed cop in front.
    lathe(A, [(0.0, 0.565), (0.046, 0.545), (0.06, 0.5), (0.046, 0.455), (0.0, 0.438)], IRON2, Sh, n=14, c=(x, 0.0))
    ax = V(s, 0, 0)
    gear(A, BRASS, Sh, V(x + s * 0.06, 0.0, 0.5), ax, 0.054, 11, 0.016, 0.0095)
    lathe(A, [(0.0, 0.026), (0.02, 0.023), (0.022, 0.0)], IRON, Sh, n=10, xf=frame(V(x + s * 0.062, 0.0, 0.5), ax), cap1=False)
    xfk = frame(V(x, 0.012, 0.5), V(0, 1, 0))
    lathe(A, [(0.0, 0.087), (0.03, 0.084), (0.056, 0.069), (0.072, 0.045), (0.078, 0.018), (0.079, 0.0)], BRASS, Sh, n=16,
          sx=1.0, sy=1.12, xf=xfk, cap1=False)
    for k in range(8):
        a = 2.0 * math.pi * k / 8.0
        p = V(0.066 * math.sin(a), 0.066 * 1.12 * math.cos(a), 0.05)
        hemi(H, xfk @ p, xfk.to_3x3() @ V(math.sin(a), math.cos(a), 1.0).normalized(), 0.0062)
    # The greave, a calf's swell behind, a brass rib in front, a band at each end.
    GR = [(0.128, 0.058), (0.175, 0.058), (0.25, 0.069), (0.34, 0.081), (0.41, 0.077), (0.462, 0.066)]
    lathe(A, [(r_, z_) for z_, r_ in reversed(GR)], IRON, Sh, n=16, c=(x, -0.004), sy=1.14)

    def rib(u, v):
        z = lerp(0.165, 0.44, v)
        a = math.radians(lerp(-11.0, 11.0, u) * lerp(0.7, 1.0, smooth(v * 2.0)))
        r = curve(z, GR) + 0.0035 + 0.0032 * math.sin(math.pi * u)
        return V(x + r * math.sin(a), -0.004 + r * 1.14 * math.cos(a), z)

    su = shell(A, rib, 4, 7, 0.005, BRASS, Sh, V(x, 0.0, 0.3))
    rivets(su, [(0.5, 0.1 + 0.16 * k) for k in range(6)], 0.0058)
    for z0, z1 in ((0.425, 0.452), (0.135, 0.165)):
        rr = 0.076 if z0 > 0.3 else 0.0625
        su = band(A, BRASS2, Sh, (x, -0.004), rr, rr * 1.14, z0, z1, 0.0, 360.0, nu=16, nv=1, t=0.01, wrap=True)
        rivets(su, [(i / 7.0, 0.5) for i in range(7)], 0.0052)
    for k in range(4):
        hemi(H, V(x + s * 0.0835, -0.004, 0.40 - 0.06 * k), ax, 0.0058)
    # The sabaton.
    lathe(A, [(0.0, 0.135), (0.04, 0.125), (0.052, 0.09), (0.04, 0.055)], IRON2, Ft, n=12, c=(x, 0.0))
    lathe(A, [(0.0555, 0.13), (0.06, 0.1), (0.066, 0.075)], BRASS2, Ft, n=14, c=(x, 0.0), sy=1.1, cap1=False)
    W = [(-0.098, 0.05), (-0.07, 0.06), (0.0, 0.068), (0.06, 0.066), (0.11, 0.059), (0.16, 0.046), (0.195, 0.03), (0.218, 0.014), (0.232, 0.004)]
    Hh = [(-0.098, 0.05), (-0.07, 0.082), (0.0, 0.098), (0.06, 0.086), (0.11, 0.068), (0.16, 0.052), (0.195, 0.036), (0.218, 0.018), (0.232, 0.006)]

    def sect(y, off=0.0):
        w = curve(y, W) + off
        h = curve(y, Hh) + off
        out = []
        for k in range(9):
            t = math.pi * k / 8.0
            sq = abs(math.cos(t)) ** 0.75 * (1.0 if math.cos(t) >= 0.0 else -1.0)
            out.append(V(x + w * sq, y, 0.016 + h * math.sin(t) ** 0.8))
        return out

    loft(A, [sect(y) for y in (-0.098, -0.08, -0.05, 0.0, 0.05, 0.1, 0.14, 0.18, 0.205, 0.222)], IRON, Ft)
    # The lames over the instep, and the toe cap.
    for k, (y0, y1, mat) in enumerate(((0.035, 0.09, BRASS), (0.078, 0.13, IRON), (0.118, 0.17, BRASS))):
        def lame(u, v, y0=y0, y1=y1):
            y = lerp(y1, y0, v)
            q = sect(y, 0.0052)
            t = u * 8.0
            i = min(int(t), 7)
            return q[i].lerp(q[i + 1], t - i)

        su = shell(A, lame, 8, 2, 0.005, mat, Ft, V(x, 0.1, 0.03))
        row(su, 0.3, 4, 0.2, 0.8, 0.0052)

    def toe(u, v):
        y = lerp(0.232, 0.158, v)
        q = sect(y, 0.0052)
        t = u * 8.0
        i = min(int(t), 7)
        return q[i].lerp(q[i + 1], t - i)

    shell(A, toe, 8, 3, 0.005, BRASS2, Ft, V(x, 0.17, 0.03))
    # The sole and the heel, iron, a hobnailed block.
    prof = []
    ring_w = [(y, curve(y, W) + 0.0045) for y in (-0.1, -0.05, 0.05, 0.12, 0.18, 0.218, 0.238)]
    rings = []
    for z in (0.0, 0.018):
        rr = []
        for y, w in ring_w:
            rr.append(V(x + w, y, z))
        for y, w in reversed(ring_w):
            rr.append(V(x - w, y, z))
        rings.append(rr)
    loft(A, rings, IRON2, Ft)
    # Greaved at the back, a plate over the heel.
    def heel(u, v):
        y = lerp(-0.04, -0.102, v)
        q = sect(max(y, -0.098), 0.0052)
        t = u * 8.0
        i = min(int(t), 7)
        return q[i].lerp(q[i + 1], t - i) + V(0, min(0.0, y + 0.098), 0)

    su = shell(A, heel, 8, 2, 0.005, BRASS, Ft, V(x, -0.05, 0.03))
    row(su, 0.3, 4, 0.2, 0.8, 0.0052)


# --- The mantle ----------------------------------------------------------------------

def cloak_edge(th):
    """scout_body.gd `_cloak_edge`, in Blender's frame."""
    return V(math.sin(th) * 0.41, -math.cos(th) * 0.29, 1.5 + 0.07 * abs(math.sin(th)))


def cloak_len(th):
    a = abs(math.degrees(th))
    if a <= 90.0:
        return lerp(0.72, 0.42, math.sin(math.radians(a)))
    return lerp(0.42, 0.26, clamp((a - 90.0) / 60.0))


def cloak_hang(th, f, length):
    return cloak_edge(th) + V(math.sin(th) * 0.045 * f, -math.cos(th) * 0.06 * f, -length * f)


def strand_rest():
    out = []
    for k in range(STRANDS):
        th = math.radians(-STRAND_SPAN + 2.0 * STRAND_SPAN * k / (STRANDS - 1))
        root = cloak_edge(th)
        bottom = cloak_hang(th, 1.0, cloak_len(th))
        out.append((root, root.lerp(bottom, 0.5), bottom))
    return out


def fbm1(x, seed):
    s = 0.0
    a = 1.0
    for o in range(3):
        s += a * math.sin(x * (1.0 + o * 1.7) + seed * (o + 1) * 1.37)
        a *= 0.55
    return s / 1.8


CLOAK_COLS = 120
CLOAK_ROWS = 30
YOKE = 0.3


def cloak_fold(th, s):
    """The pleats, falling from the shoulders, deeper toward the hem."""
    x = th * 5.2 + 0.8 * fbm1(th * 1.7 + s * 2.0, 3.0) + 0.5 * s * math.sin(th * 2.0)
    f = math.sin(x) + 0.42 * math.sin(2.3 * x + 1.2 + s * 1.5) + 0.2 * math.sin(4.7 * x + 0.6 - s * 3.0)
    # Sharper ridges than valleys, as cloth hangs.
    f = (f + 0.7) ** 1.6 * 0.55 - 0.3 if f > -0.7 else -0.3
    h = clamp((s - YOKE * 0.75) / (1.0 - YOKE * 0.75))
    return f * (0.016 + 0.075 * smooth(h) ** 0.8)


def build_cloak():
    span = 103.0
    verts, uvs, bones = [], [], []
    rng = random.Random(6151)
    hems = []
    for c in range(CLOAK_COLS):
        k = c / 3.0
        hems.append(1.0 - 0.1 * abs(fbm1(k * 1.3, 7.0)) - 0.14 * abs(fbm1(k * 0.37, 2.0)) - rng.uniform(0.0, 0.03))
    for c in range(CLOAK_COLS):
        u = c / (CLOAK_COLS - 1)
        th = math.radians(lerp(-span, span, u))
        length = cloak_len(th)
        sf = clamp((math.degrees(th) + STRAND_SPAN) / (2.0 * STRAND_SPAN) * (STRANDS - 1), 0.0, STRANDS - 1.0)
        k0 = min(int(sf), STRANDS - 2)
        w1 = clamp(sf - k0)
        # The collar, the shoulder edge, the hem.
        p0 = V(math.sin(th) * 0.142, -(math.cos(th) * 0.13 + 0.012),
               lerp(1.6, 1.545, clamp((abs(math.degrees(th)) - 110.0) / 32.0)))
        p1 = cloak_edge(th)
        p2 = cloak_hang(th, hems[c], length)
        p1a = p1 + (p0 - p1) * 0.3
        p1b = p1 + (p2 - p1) * min(0.24, 0.1 / max(length * hems[c], 0.05))
        out = V(math.sin(th), -math.cos(th), 0.0)
        for r in range(CLOAK_ROWS):
            s = r / (CLOAK_ROWS - 1)
            if s < YOKE * 0.65:
                p = p0.lerp(p1a, s / (YOKE * 0.65))
                # Soft over the shoulders, sagging a little off the collar.
                f = -1.0
            elif s < YOKE * 1.3:
                t = (s - YOKE * 0.65) / (YOKE * 0.65)
                p = p1a * (1 - t) ** 2 + p1 * 2.0 * t * (1 - t) + p1b * t * t
                f = (s - YOKE) / (1.0 - YOKE) if s > YOKE else -1.0
            else:
                t = (s - YOKE * 1.3) / (1.0 - YOKE * 1.3)
                p = p1b.lerp(p2, t)
                f = (s - YOKE) / (1.0 - YOKE)
            p = p + out * cloak_fold(th, s)
            verts.append(p)
            uvs.append((u, s))
            if s < 0.05:
                bones.append([("Chest", 1.0)])
                continue
            ff = max(f, 0.0)
            chest_w = max(0.0, 1.0 - ff * 3.0)
            wa = clamp(1.0 - (ff - 0.3) / 0.4)
            a0 = "Cloak%d" % k0
            a1 = "Cloak%d" % (k0 + 1)
            rest = 1.0 - chest_w
            if chest_w > 0.0:
                bb = [("Chest", chest_w), (a0 + "A", rest * (1.0 - w1)), (a1 + "A", rest * w1)]
            else:
                bb = [(a0 + "A", wa * (1.0 - w1)), (a0 + "B", (1.0 - wa) * (1.0 - w1)), (a1 + "A", wa * w1), (a1 + "B", (1.0 - wa) * w1)]
            bones.append([b for b in bb if b[1] > 1e-4])
    faces = []
    for c in range(CLOAK_COLS - 1):
        for r in range(CLOAK_ROWS - 1):
            i0 = c * CLOAK_ROWS + r
            i1 = i0 + CLOAK_ROWS
            faces.append([i0, i1, i1 + 1, i0 + 1])
    base = len(C.v)
    C.v.extend(verts)
    C.f.extend([[base + i for i in f] for f in faces])
    C.uv.extend(uvs)
    C.bones.extend(bones)
    C.col.extend([(1, 1, 1, 0)] * len(verts))
    C.pbr.extend([(0, 1, 0, 1)] * len(verts))
    # The hood, fallen back and bunched round the neck: a soft roll, deep at
    # the nape. Its UVs sit in the mantle's untorn top.
    nu, nv = 46, 12
    hv, hu, hf = [], [], []
    for i in range(nu):
        a = 2.0 * math.pi * i / nu
        back = 0.5 - 0.5 * math.cos(a)       # 0 in front, 1 behind
        cy = 0.0 - 0.012
        major = lerp(0.138, 0.158, back)
        rr = lerp(0.03, 0.082, smooth(back) ** 1.3)
        for j in range(nv):
            b = 2.0 * math.pi * j / nv
            wob = 1.0 + 0.16 * math.sin(a * 5.0 + b * 2.0 + 1.0) + 0.1 * math.sin(a * 9.0 - b * 3.0)
            d = V(math.sin(a), math.cos(a), 0.0)
            cen = V(0, cy, 1.595 - 0.022 * back) + d * major
            q = cen + (d * math.cos(b) * 1.05 + V(0, 0, 1) * math.sin(b) * 0.78) * rr * wob
            q.z -= 0.02 * back * (0.5 - 0.5 * math.cos(b))
            hv.append(q)
            hu.append((i / nu * 0.5 + 0.25, 0.02 + 0.2 * j / nv))
    for i in range(nu):
        for j in range(nv):
            a = i * nv + j
            b = ((i + 1) % nu) * nv + j
            c = ((i + 1) % nu) * nv + (j + 1) % nv
            d = i * nv + (j + 1) % nv
            hf.append([a, b, c, d])
    base = len(C.v)
    C.v.extend(hv)
    C.f.extend([[base + i for i in f] for f in hf])
    C.uv.extend(hu)
    C.bones.extend([[("Chest", 1.0)]] * len(hv))
    C.col.extend([(1, 1, 1, 0)] * len(hv))
    C.pbr.extend([(0, 1, 0, 1)] * len(hv))


# --- The spear -----------------------------------------------------------------------

def build_spear():
    """Its own frame: the rear grip at the origin, the point along +Y here
    (the game's -Z), SPEAR_TIP ahead, SPEAR_BUTT behind."""
    none = []
    SP.dens = 0.8
    ax = frame(V(0, 0, 0), V(0, 1, 0))
    lathe(SP, [(0.021, -SPEAR_BUTT + 0.03), (0.02, 0.0), (0.019, 1.42)], DARK, none, n=10, xf=ax)
    # The rings up the shaft, every 0.14.
    y = -SPEAR_BUTT + 0.1
    k = 0
    while y < 1.36:
        lathe(SP, [(0.0195, y - 0.012), (0.0255, y - 0.008), (0.0265, y), (0.0255, y + 0.008), (0.0195, y + 0.012)], BRASS, none,
              n=10, xf=ax, cap0=False, cap1=False)
        y += 0.14
        k += 1
    # The ferrule and its spike.
    lathe(SP, [(0.0265, -SPEAR_BUTT + 0.075), (0.0285, -SPEAR_BUTT + 0.07), (0.0285, -SPEAR_BUTT + 0.01), (0.022, -SPEAR_BUTT),
               (0.012, -SPEAR_BUTT - 0.03), (0.0, -SPEAR_BUTT - 0.075)], IRON, none, n=10, xf=ax)
    # The socket, its collars, two long langets down the shaft.
    lathe(SP, [(0.0245, 1.30), (0.0275, 1.31), (0.0275, 1.32), (0.024, 1.33), (0.026, 1.40), (0.031, 1.452), (0.0345, 1.462), (0.0345, 1.476),
               (0.027, 1.486), (0.022, 1.50)], IRON, none, n=12, xf=ax)
    for s in (1.0, -1.0):
        def lang(u, v, s=s):
            y = lerp(1.1, 1.34, v)
            w = lerp(0.0065, 0.0135, v)
            a = lerp(-1.0, 1.0, u)
            r = 0.0212
            return V(s * w * a, y, s * r * math.cos(a * w / r))

        su = shell(SP, lang, 2, 3, 0.003, IRON2, none, V(0, 1.2, 0))
        rivets(su, [(0.5, 0.2), (0.5, 0.7)], 0.0058, SH)
    xf = None
    up = V(0, 0, 1)
    # The leaf: long and flat, a rib down it.
    blade(SP, STEEL, none, [V(0, 1.47, 0), V(0, 1.515, 0), V(0, 1.56, 0), V(0, 1.625, 0), V(0, 1.695, 0), V(0, 1.76, 0), V(0, SPEAR_TIP, 0)],
          [0.024, 0.056, 0.063, 0.05, 0.036, 0.018, 0.0], [0.02, 0.019, 0.017, 0.015, 0.012, 0.007, 0.0])
    for s in (1.0, -1.0):
        # The side prongs flaring forward, the barbs hooked back.
        blade(SP, STEEL, none, [V(s * 0.03, 1.492, 0), V(s * 0.07, 1.525, 0), V(s * 0.1, 1.575, 0), V(s * 0.114, 1.635, 0)],
              [0.026, 0.021, 0.013, 0.0], [0.011, 0.01, 0.007, 0.0])
        blade(SP, STEEL, none, [V(s * 0.03, 1.487, 0), V(s * 0.078, 1.482, 0), V(s * 0.112, 1.455, 0), V(s * 0.127, 1.405, 0)],
              [0.021, 0.016, 0.011, 0.0], [0.01, 0.0085, 0.0055, 0.0])
        # Teeth up the leaf's edge.
        for k in range(3):
            y = 1.595 + 0.048 * k
            w = curve(y, [(1.56, 0.063), (1.625, 0.05), (1.695, 0.036), (1.76, 0.018)])
            blade(SP, STEEL, none, [V(s * (w - 0.006), y - 0.012, 0), V(s * (w + 0.009), y + 0.006, 0), V(s * (w + 0.018), y + 0.02, 0)],
                  [0.0095, 0.005, 0.0], [0.0055, 0.003, 0.0])


# --- Meshes, materials ---------------------------------------------------------------

def make_mesh(name, acc, uv=False, attrs=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in acc.v], [], acc.f)
    me.update()
    if attrs:
        for an, data in (("scout_col", acc.col), ("scout_pbr", acc.pbr)):
            at = me.attributes.new(an, 'FLOAT_COLOR', 'POINT')
            at.data.foreach_set("color", [x for c in data for x in c])
    if uv:
        lay = me.uv_layers.new(name="UV")
        for poly in me.polygons:
            for li in poly.loop_indices:
                lay.data[li].uv = acc.uv[me.loops[li].vertex_index]
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def fix_normals(ob, angle=38.0, flip_check=True):
    ob.data.polygons.foreach_set("use_smooth", [True] * len(ob.data.polygons))
    ob.data.set_sharp_from_angle(angle=math.radians(angle))
    ob.data.update()


def activate(ob):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def unwrap(ob, acc):
    """The lathes, plates and lofts unroll as they were built, one island a
    plate; what is left goes through Smart UV Project. Every island to one
    density, times the part's own; the hidden inner faces all share a patch in
    the corner, so the atlas is spent on what can be seen."""
    me = ob.data
    lay = me.uv_layers.new(name="UV")
    for poly in me.polygons:
        l = acc.luv[poly.index]
        if l:
            for li, uv in zip(poly.loop_indices, l):
                lay.data[li].uv = uv
    activate(ob)
    bpy.context.scene.tool_settings.use_uv_select_sync = True
    bpy.ops.object.mode_set(mode='EDIT')
    bm = bmesh.from_edit_mesh(me)
    bm.faces.ensure_lookup_table()

    def pick(test):
        for f in bm.faces:
            f.select_set(test(f.index))
        bm.select_flush_mode()
        bmesh.update_edit_mesh(me)

    pick(lambda i: acc.luv[i] is None and not acc.inner[i])
    bpy.ops.uv.smart_project(angle_limit=math.radians(60.0), island_margin=0.0, area_weight=0.0, correct_aspect=True,
                             scale_to_bounds=False)
    pick(lambda i: not acc.inner[i])
    bpy.ops.uv.select_all(action='SELECT')
    bpy.ops.uv.average_islands_scale()
    bm = bmesh.from_edit_mesh(me)
    bm.faces.ensure_lookup_table()
    ul = bm.loops.layers.uv["UV"]
    for f in bm.faces:
        k = acc.fd[f.index]
        if k != 1.0 and not acc.inner[f.index]:
            for l in f.loops:
                l[ul].uv = l[ul].uv * k
    bmesh.update_edit_mesh(me)
    bm = bmesh.from_edit_mesh(me)
    bm.faces.ensure_lookup_table()
    ul = bm.loops.layers.uv["UV"]
    shelf_pack(bm, ul, acc)
    for f in bm.faces:
        n = len(f.loops)
        for k, l in enumerate(f.loops):
            if acc.inner[f.index]:
                a = 2.0 * math.pi * k / n
                l[ul].uv = (INNER_UV + 0.004 * math.cos(a), INNER_UV + 0.004 * math.sin(a))
            else:
                l[ul].uv = l[ul].uv * INNER_FIT
    bmesh.update_edit_mesh(me)
    bpy.ops.object.mode_set(mode='OBJECT')


def shelf_pack(bm, ul, acc):
    """Every island on its side, tallest first, in rows: as large as fits.
    (Blender's own packer left half the atlas empty round the small ones.)"""
    boxes = []
    for faces in bmesh_utils.bmesh_linked_uv_islands(bm, ul):
        if acc.inner[faces[0].index]:
            continue
        us = [l[ul].uv.x for f in faces for l in f.loops]
        vs = [l[ul].uv.y for f in faces for l in f.loops]
        u0, v0 = min(us), min(vs)
        w, h = max(us) - u0, max(vs) - v0
        turn = h > w
        boxes.append([h if turn else w, w if turn else h, turn, u0, v0, faces])
    boxes.sort(key=lambda b: -b[1])
    gap = 7.0 / ATLAS

    def lay(k):
        x = y = rowh = 0.0
        out = []
        for w, h, *_ in boxes:
            if x + w * k > 1.0:
                x = 0.0
                y += rowh + gap
                rowh = 0.0
            out.append((x, y))
            x += w * k + gap
            rowh = max(rowh, h * k)
        return out, y + rowh

    lo, hi = 0.01, 100.0
    for _ in range(40):
        k = math.sqrt(lo * hi)
        if lay(k)[1] <= 1.0:
            lo = k
        else:
            hi = k
    places, _h = lay(lo)
    for (w, h, turn, u0, v0, faces), (x, y) in zip(boxes, places):
        for f in faces:
            for l in f.loops:
                u = l[ul].uv.x - u0
                v = l[ul].uv.y - v0
                if turn:
                    u, v = v, h - u
                l[ul].uv = (x + u * lo, y + v * lo)
    area = sum(b[0] * b[1] for b in boxes) * lo * lo
    log("%d islands, %.0f%% of the atlas" % (len(boxes), area * 100.0))


def setup_cycles(samples):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    prefs = bpy.context.preferences.addons['cycles'].preferences
    for kind in ('OPTIX', 'CUDA'.replace('D', 'D')):
        try:
            prefs.compute_device_type = kind
            prefs.get_devices()
            devs = [d for d in prefs.devices if d.type == kind]
            if devs:
                for d in prefs.devices:
                    d.use = d.type == kind
                sc.cycles.device = 'GPU'
                log("cycles on", kind, devs[0].name)
                return
        except TypeError:
            pass
    sc.cycles.device = 'CPU'
    log("cycles on the CPU")


def plate_shader():
    """The worn plate. Reads the colours given part by part (scout_col: colour
    + rust share; scout_pbr: metal, roughness). Three outputs, one wired up at
    a time: `surface` (the lit look, whose normal is what gets baked), `albedo`
    and `orm` (emission)."""
    mat = bpy.data.materials.new("ScoutHigh")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    N = nt.nodes.new
    L = nt.links.new

    def math_(op, a, b=None, clamp_=False):
        n = N("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp_
        for i, x in enumerate((a, b)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                n.inputs[i].default_value = x
            else:
                L(x, n.inputs[i])
        return n.outputs[0]

    def noise(scale, detail, rough, stretch=None):
        n = N("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough
        if stretch is None:
            L(pos, n.inputs["Vector"])
        else:
            vm = N("ShaderNodeVectorMath")
            vm.operation = 'MULTIPLY'
            L(pos, vm.inputs[0])
            vm.inputs[1].default_value = stretch
            L(vm.outputs[0], n.inputs["Vector"])
        return n.outputs[0]

    def ramp(x, a, b, c=None, d=None):
        n = N("ShaderNodeMapRange")
        n.interpolation_type = 'SMOOTHSTEP'
        L(x, n.inputs[0])
        n.inputs[1].default_value = a
        n.inputs[2].default_value = b
        n.inputs[3].default_value = 0.0 if c is None else c
        n.inputs[4].default_value = 1.0 if d is None else d
        return n.outputs[0]

    def mix(f, a, b):
        n = N("ShaderNodeMix")
        n.data_type = 'RGBA'
        L(f, n.inputs[0]) if not isinstance(f, float) else None
        for i, x in ((6, a), (7, b)):
            if isinstance(x, tuple):
                n.inputs[i].default_value = x
            else:
                L(x, n.inputs[i])
        return n.outputs[2]

    geo = N("ShaderNodeNewGeometry")
    pos = geo.outputs["Position"]
    col = N("ShaderNodeAttribute")
    col.attribute_name = "scout_col"
    pbr = N("ShaderNodeAttribute")
    pbr.attribute_name = "scout_pbr"
    sep = N("ShaderNodeSeparateColor")
    L(pbr.outputs["Color"], sep.inputs[0])
    n_big = noise(6.5, 6.0, 0.62)
    n_mid = noise(26.0, 8.0, 0.66)
    n_fine = noise(150.0, 6.0, 0.6)
    n_streak = noise(34.0, 5.0, 0.55, (1.0, 1.0, 0.12))
    ao = N("ShaderNodeAmbientOcclusion")
    ao.samples = 12
    ao.inputs["Distance"].default_value = 0.045
    open_ = ao.outputs["AO"]
    bev = N("ShaderNodeBevel")
    bev.samples = 8
    bev.inputs["Radius"].default_value = 0.0035
    dot = N("ShaderNodeVectorMath")
    dot.operation = 'DOT_PRODUCT'
    L(geo.outputs["Normal"], dot.inputs[0])
    L(bev.outputs[0], dot.inputs[1])
    # Where the bevel turned the normal is an edge; open to the air, a worn one.
    edge = ramp(math_('SUBTRACT', 1.0, dot.outputs["Value"]), 0.012, 0.11)
    worn = math_('MULTIPLY', edge, ramp(open_, 0.55, 0.92), True)
    worn = math_('MULTIPLY', worn, ramp(n_mid, 0.3, 0.6, 0.45, 1.0), True)
    # Rust: patches where the share and the noise agree, thicker in the crevices.
    cav = math_('SUBTRACT', 1.0, open_)
    t = math_('ADD', math_('MULTIPLY', n_big, 0.6), math_('MULTIPLY', n_mid, 0.4))
    t = math_('ADD', t, math_('MULTIPLY', col.outputs["Alpha"], 0.4))
    t = math_('ADD', t, math_('MULTIPLY', cav, 0.3))
    t = math_('ADD', t, math_('MULTIPLY', n_streak, 0.1))
    rust = math_('MULTIPLY', ramp(t, 0.73, 0.87), ramp(col.outputs["Alpha"], 0.02, 0.12), True)
    rc = N("ShaderNodeValToRGB")
    L(math_('ADD', math_('MULTIPLY', n_fine, 0.5), math_('MULTIPLY', n_mid, 0.5)), rc.inputs[0])
    els = rc.color_ramp.elements
    els[0].position = 0.34
    els[0].color = (0.065, 0.03, 0.016, 1.0)
    els[1].position = 0.66
    els[1].color = (0.36, 0.14, 0.05, 1.0)
    m = rc.color_ramp.elements.new(0.5)
    m.color = (0.2, 0.085, 0.03, 1.0)
    # The base, mottled.
    mott = ramp(n_big, 0.3, 0.7, 0.78, 1.12)
    mulc = N("ShaderNodeVectorMath")
    mulc.operation = 'SCALE'
    L(col.outputs["Color"], mulc.inputs[0])
    L(mott, mulc.inputs["Scale"])
    base = mulc.outputs[0]
    bright = N("ShaderNodeVectorMath")
    bright.operation = 'SCALE'
    L(col.outputs["Color"], bright.inputs[0])
    bright.inputs["Scale"].default_value = 1.5
    c1 = mix(worn, base, bright.outputs[0])
    c2 = mix(rust, c1, rc.outputs[0])
    grime = ramp(open_, 0.2, 0.95, 0.3, 1.0)
    muls = N("ShaderNodeVectorMath")
    muls.operation = 'SCALE'
    L(c2, muls.inputs[0])
    L(grime, muls.inputs["Scale"])
    albedo = muls.outputs[0]
    # Roughness, metal.
    rough = math_('ADD', sep.outputs[1], math_('MULTIPLY', rust, 0.42))
    rough = math_('ADD', rough, math_('MULTIPLY', math_('SUBTRACT', n_fine, 0.5), 0.3))
    rough = math_('SUBTRACT', rough, math_('MULTIPLY', worn, 0.2), True)
    metal = math_('MULTIPLY', sep.outputs[0], math_('SUBTRACT', 1.0, rust), True)
    metal = math_('ADD', metal, math_('MULTIPLY', worn, 0.2), True)
    orm = N("ShaderNodeCombineColor")
    orm.inputs[0].default_value = 1.0
    L(rough, orm.inputs[1])
    L(metal, orm.inputs[2])
    # The pitted surface.
    bump = N("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.7
    bump.inputs["Distance"].default_value = 0.0035
    h = math_('ADD', math_('MULTIPLY', rust, 0.55), math_('MULTIPLY', n_fine, 0.22))
    h = math_('ADD', h, math_('MULTIPLY', n_mid, 0.16))
    L(h, bump.inputs["Height"])
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
    out = N("ShaderNodeOutputMaterial")
    outs = {"surface": p.outputs[0], "albedo": e_a.outputs[0], "orm": e_o.outputs[0]}

    def show(which):
        L(outs[which], out.inputs["Surface"])

    show("surface")
    return mat, show


def blank_image(name, size, non_color, alpha=False):
    img = bpy.data.images.new(name, size, size, alpha=alpha)
    if non_color:
        img.colorspace_settings.name = 'Non-Color'
    return img


def fill_corner(img, rgb):
    """The inner faces' patch, one flat colour (as the image stores it)."""
    import numpy as np
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    k = int(INNER_FIT * w) + 2
    px[k:, k:, :3] = rgb
    px[k:, k:, 3] = 1.0
    img.pixels.foreach_set(px.ravel())
    img.update()


def bake_plate(low, high, show):
    sc = bpy.context.scene
    setup_cycles(48)
    mat = bpy.data.materials.new("ScoutPlateBake")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    tex = nt.nodes.new("ShaderNodeTexImage")
    nt.nodes.active = tex
    low.data.materials.clear()
    low.data.materials.append(mat)
    b = sc.render.bake
    b.use_selected_to_active = True
    b.cage_extrusion = 0.0075
    b.max_ray_distance = 0.02
    b.margin = 10
    b.margin_type = 'EXTEND'
    b.use_clear = True
    b.target = 'IMAGE_TEXTURES'
    bpy.ops.object.select_all(action='DESELECT')
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    results = {}
    for name, kind, non_color, which, ext in (("scout_plate_col", 'EMIT', False, "albedo", "jpg"),
                                              ("scout_plate_orm", 'EMIT', True, "orm", "jpg"),
                                              ("scout_plate_nor", 'NORMAL', True, "surface", "png")):
        img = blank_image(name, ATLAS, non_color)
        tex.image = img
        show(which)
        log("baking", name)
        bpy.ops.object.bake(type=kind, normal_space='TANGENT', normal_r='POS_X', normal_g='POS_Y', normal_b='POS_Z')
        fill_corner(img, {"albedo": (0.16, 0.14, 0.12), "orm": (1.0, 0.8, 0.1), "surface": (0.5, 0.5, 1.0)}[which])
        img.filepath_raw = os.path.join(SRC, name + "." + ext)
        img.file_format = 'JPEG' if ext == "jpg" else 'PNG'
        img.save(quality=93) if ext == "jpg" else img.save()
        results[name] = img.filepath_raw
    bpy.data.materials.remove(mat)
    return results


def cloth_maps():
    """The mantle's maps: a coarse dark wool, stained, thin toward the hem;
    tears and holes in the alpha, long ones, running with the threads."""
    import numpy as np
    n = CLOTH_TEX
    rng = np.random.default_rng(6151)

    def smooth_noise(fx, fy, oct_=4):
        out = np.zeros((n, n))
        amp = 1.0
        tot = 0.0
        for o in range(oct_):
            gx = int(fx * 2 ** o) + 2
            gy = int(fy * 2 ** o) + 2
            g = rng.random((gy + 1, gx + 1))
            g[:, -1] = g[:, 0]
            xs = np.linspace(0.0, gx - 1.0, n, endpoint=False)
            ys = np.linspace(0.0, gy - 1.0, n, endpoint=False)
            x0 = xs.astype(int)
            y0 = ys.astype(int)
            fx_ = xs - x0
            fy_ = ys - y0
            fx_ = fx_ * fx_ * (3 - 2 * fx_)
            fy_ = fy_ * fy_ * (3 - 2 * fy_)
            top = g[np.ix_(y0, x0)] * (1 - fx_)[None, :] + g[np.ix_(y0, x0 + 1)] * fx_[None, :]
            bot = g[np.ix_(y0 + 1, x0)] * (1 - fx_)[None, :] + g[np.ix_(y0 + 1, x0 + 1)] * fx_[None, :]
            out += amp * (top * (1 - fy_)[:, None] + bot * fy_[:, None])
            tot += amp
            amp *= 0.55
        return out / tot

    v = (np.arange(n) + 0.5)[:, None] / n        # 0 at the collar, 1 at the hem
    u = (np.arange(n) + 0.5)[None, :] / n
    big = smooth_noise(5, 4)
    mid = smooth_noise(22, 18, 4)
    long_ = smooth_noise(48, 4, 3)     # streaks with the threads
    across = smooth_noise(6, 60, 2)
    # The weave.
    wx = np.sin(u * n * 2.0 * np.pi / 3.2 + 2.0 * (mid - 0.5))
    wy = np.sin(v * n * 2.0 * np.pi / 3.2 + 2.0 * (long_ - 0.5))
    weave = 0.5 + 0.25 * wx * np.sign(np.sin(v * n * 2.0 * np.pi / 6.4)) + 0.25 * wy * np.sign(np.sin(u * n * 2.0 * np.pi / 6.4))
    slub = (long_ - 0.5) * 0.9 + (across - 0.5) * 0.5
    height = weave * 0.6 + slub * 0.5
    base = np.array([0.15, 0.13, 0.105])
    tint = 0.72 + 0.72 * (big - 0.5) + 0.42 * (weave - 0.5) + 0.5 * slub
    albedo = base[None, None, :] * tint[:, :, None]
    # Road dirt up from the hem; old damp stains, brown and green-grey.
    dirt = np.clip((v - 0.48) * 1.5 + (mid - 0.5) * 1.4, 0.0, 1.0)[:, :, None]
    albedo = albedo * (1.0 - dirt * 0.52) + np.array([0.075, 0.056, 0.038])[None, None, :] * dirt * 0.52
    stain = np.clip((big - 0.56) * 7.0, 0.0, 1.0)[:, :, None]
    albedo = albedo * (1.0 - stain * 0.36) + np.array([0.06, 0.062, 0.042])[None, None, :] * stain * 0.36
    # Worn threadbare in the wind.
    thin = np.clip((v - 0.72) * 2.4, 0.0, 1.0)
    edge = long_ * 0.72 + across * 0.12 + mid * 0.16
    tears = 0.5 + (edge - 0.5) * 2.6 - (v - 0.86) * 2.1
    holes = smooth_noise(26, 32, 3)
    alpha = (tears > 0.42) & (holes + (1.0 - v) * 0.8 > 0.72 - 0.0)
    alpha = alpha | (v[:, :] < 0.46)
    # Frayed: threads hanging where the cloth stops.
    fray = (np.sin(u * n * 2.0 * np.pi / 2.5) > 0.2) & (tears > 0.33)
    alpha = alpha | fray
    a = alpha.astype(np.float32)
    albedo = albedo * (1.0 - (thin * 0.3)[:, :, None])
    # The normal map from the height.
    gx = np.roll(height, -1, 1) - np.roll(height, 1, 1)
    gy = np.roll(height, -1, 0) - np.roll(height, 1, 0)
    s = 1.3
    nor = np.dstack((-gx * s, -gy * s, np.ones_like(gx)))
    nor /= np.linalg.norm(nor, axis=2, keepdims=True)
    nor = nor * 0.5 + 0.5

    def save(name, rgb, alpha_=None, non_color=False):
        img = bpy.data.images.new(name, n, n, alpha=alpha_ is not None)
        if non_color:
            img.colorspace_settings.name = 'Non-Color'
        a2 = np.ones((n, n, 1)) if alpha_ is None else alpha_[:, :, None]
        if not non_color:
            # A byte image's pixels are as stored, so sRGB here.
            rgb = np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * np.power(np.maximum(rgb, 1e-6), 1.0 / 2.4) - 0.055)
        # Row 0 is Blender's bottom row, UV v 0: as these arrays have it.
        rgba = np.concatenate((rgb, a2), axis=2)
        img.pixels.foreach_set(rgba.astype(np.float32).ravel())
        img.filepath_raw = os.path.join(SRC, name + ".png")
        img.file_format = 'PNG'
        img.save()
        return img

    save("scout_cloth_col", np.clip(albedo, 0.0, 1.0), a)
    save("scout_cloth_nor", nor, None, True)


def final_materials():
    """What the game gets: the three surfaces, by name (scout_body.gd finds the
    glow by "ScoutGlow")."""

    def image(name):
        for ext in (".jpg", ".png"):
            p = os.path.join(SRC, name + ext)
            if os.path.exists(p):
                img = bpy.data.images.load(p, check_existing=True)
                # Godot names what it extracts <glb>_<image>.
                img.name = name[len("scout_"):]
                return img
        raise RuntimeError("no map " + name)

    def pbr(name, col, nor, orm=None, cloth=False):
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
        t.image = image(col)
        L(t.outputs["Color"], p.inputs["Base Color"])
        tn = N("ShaderNodeTexImage")
        tn.image = image(nor)
        tn.image.colorspace_settings.name = 'Non-Color'
        nm = N("ShaderNodeNormalMap")
        L(tn.outputs["Color"], nm.inputs["Color"])
        L(nm.outputs[0], p.inputs["Normal"])
        if orm:
            to = N("ShaderNodeTexImage")
            to.image = image(orm)
            to.image.colorspace_settings.name = 'Non-Color'
            sp = N("ShaderNodeSeparateColor")
            L(to.outputs["Color"], sp.inputs[0])
            L(sp.outputs[1], p.inputs["Roughness"])
            L(sp.outputs[2], p.inputs["Metallic"])
        if cloth:
            p.inputs["Roughness"].default_value = 1.0
            p.inputs["Metallic"].default_value = 0.0
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
        return mat

    plate = pbr("ScoutPlate", "scout_plate_col", "scout_plate_nor", "scout_plate_orm")
    cloth = pbr("ScoutCloth", "scout_cloth_col", "scout_cloth_nor", None, True)
    glow = bpy.data.materials.new("ScoutGlow")
    glow.use_nodes = True
    nt = glow.node_tree
    p = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs["Base Color"].default_value = (0.02, 0.12, 0.14, 1.0)
    p.inputs["Emission Color"].default_value = (0.0, 0.91, 1.0, 1.0)
    p.inputs["Emission Strength"].default_value = 3.2
    p.inputs["Roughness"].default_value = 0.2
    return plate, cloth, glow


def build_armature():
    data = bpy.data.armatures.new("ScoutRig")
    arm = bpy.data.objects.new("ScoutRig", data)
    bpy.context.scene.collection.objects.link(arm)
    activate(arm)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = data.edit_bones

    def add(name, parent, p):
        b = eb.new(name)
        b.head = p
        # Along +Y, no roll: Blender's identity, and so the rig's own rest.
        b.tail = p + V(0.0, 0.06, 0.0)
        b.roll = 0.0
        b.use_connect = False
        if parent:
            b.parent = eb[parent]

    for name, parent, g in BONES:
        add(name, parent, V(g[0], -g[2], g[1]))
    for k, (root, mid, _bottom) in enumerate(strand_rest()):
        add("Cloak%dA" % k, "Chest", root)
        add("Cloak%dB" % k, "Cloak%dA" % k, mid)
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm


def assign_weights(ob, arm, per_vert):
    names = [b.name for b in arm.data.bones]
    groups = {n: ob.vertex_groups.new(name=n) for n in names}
    for i, bones in enumerate(per_vert):
        for n, w in bones:
            groups[n].add([i], w, 'REPLACE')
    m = ob.modifiers.new("Rig", 'ARMATURE')
    m.object = arm
    ob.parent = arm


def set_preview_scene(objs, out_dir, tag, res=(900, 1000)):
    sc = bpy.context.scene
    setup_cycles(96)
    sc.cycles.use_denoising = True
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.image_settings.file_format = 'PNG'
    sc.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.get("Prev") or bpy.data.worlds.new("Prev")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.02, 0.02, 0.025, 1.0)
    sc.world = world
    if bpy.data.objects.get("PrevCam") is None:
        cd = bpy.data.cameras.new("PrevCam")
        cd.lens = 70.0
        cam = bpy.data.objects.new("PrevCam", cd)
        sc.collection.objects.link(cam)
        for name, loc, power, col in (("Key", (2.0, 2.4, 2.6), 90.0, (1.0, 0.8, 0.6)), ("Fill", (-2.6, 1.6, 1.4), 26.0, (0.7, 0.8, 1.0)),
                                      ("Rim", (0.4, -3.0, 2.2), 70.0, (1.0, 0.85, 0.7))):
            ld = bpy.data.lights.new(name, 'POINT')
            ld.energy = power
            ld.color = col
            ld.shadow_soft_size = 0.2
            l = bpy.data.objects.new(name, ld)
            l.location = loc
            sc.collection.objects.link(l)
        gm = bpy.data.meshes.new("PrevFloor")
        gm.from_pydata([(-6, -6, 0), (6, -6, 0), (6, 6, 0), (-6, 6, 0)], [], [(0, 1, 2, 3)])
        fl = bpy.data.objects.new("PrevFloor", gm)
        sc.collection.objects.link(fl)
    cam = bpy.data.objects["PrevCam"]
    sc.camera = cam
    os.makedirs(out_dir, exist_ok=True)
    views = (("q", V(1.7, 3.1, 1.5), V(0, 0, 0.98), 50.0), ("side", V(3.9, 0.2, 1.1), V(0, 0, 0.98), 50.0),
             ("back", V(-1.8, -3.2, 1.6), V(0, 0, 0.98), 50.0), ("head", V(0.55, 1.15, 1.75), V(0, 0.03, 1.72), 90.0),
             ("hand", V(1.05, 0.55, 0.95), V(0.21, 0.0, 0.86), 90.0), ("foot", V(0.8, 0.9, 0.3), V(0.1, 0.05, 0.1), 90.0))
    for name, loc, at, lens in views:
        cam.location = loc
        cam.data.lens = lens
        cam.rotation_euler = (at - loc).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = os.path.join(out_dir, "%s_%s.png" % (tag, name))
        bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    preview = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    no_bake = "--no-bake" in argv
    os.makedirs(SRC, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build_head()
    build_torso()
    for s in (1.0, -1.0):
        build_arm(s)
        build_leg(s)
    build_cloak()
    build_spear()
    log("low: plate %d faces, glow %d, cloth %d, spear %d; high detail %d" % (len(A.f), len(G.f), len(C.f), len(SP.f), len(H.f) + len(SH.f)))

    # The plate and the spear unwrapped and baked as one, the spear beside it.
    both = Acc()
    n_body = len(A.v)
    both.v = A.v + [p + V(SPEAR_BAKE_X, 0, 0) for p in SP.v]
    both.f = A.f + [[i + n_body for i in f] for f in SP.f]
    both.col = A.col + SP.col
    both.pbr = A.pbr + SP.pbr
    both.bones = A.bones + SP.bones
    both.luv = A.luv + SP.luv
    both.inner = A.inner + SP.inner
    both.fd = A.fd + SP.fd
    n_body_faces = len(A.f)
    low = make_mesh("ScoutLow", both)
    fix_normals(low)
    hi = Acc()
    hi.v = list(both.v) + list(H.v) + [p + V(SPEAR_BAKE_X, 0, 0) for p in SH.v]
    m = len(both.v)
    hi.f = list(both.f) + [[i + m for i in f] for f in H.f]
    m2 = m + len(H.v)
    hi.f += [[i + m2 for i in f] for f in SH.f]
    hi.col = both.col + H.col + SH.col
    hi.pbr = both.pbr + H.pbr + SH.pbr
    high = make_mesh("ScoutHigh", hi)
    fix_normals(high)
    shader, show = plate_shader()
    high.data.materials.append(shader)
    unwrap(low, both)
    if not no_bake:
        bake_plate(low, high, show)
        cloth_maps()
    plate, cloth, glow = final_materials()
    low.data.materials.clear()
    low.data.materials.append(plate)

    # Split the bake's mesh back into body and spear.
    spear = low.copy()
    spear.data = low.data.copy()
    spear.name = spear.data.name = "ScoutSpear"
    bpy.context.scene.collection.objects.link(spear)
    for ob, keep_body in ((low, True), (spear, False)):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.faces.ensure_lookup_table()
        kill = [f for i, f in enumerate(bm.faces) if (i < n_body_faces) != keep_body]
        bmesh.ops.delete(bm, geom=kill, context='FACES')
        if not keep_body:
            for v in bm.verts:
                v.co.x -= SPEAR_BAKE_X
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()
    low.name = low.data.name = "ScoutPlateBody"

    arm = build_armature()
    cl = make_mesh("ScoutClothMesh", C, uv=True, attrs=False)
    # Cloth faces outward, smooth all over.
    cl.data.polygons.foreach_set("use_smooth", [True] * len(cl.data.polygons))
    cl.data.materials.append(cloth)
    gl = make_mesh("ScoutGlowMesh", G, attrs=False)
    fix_normals(gl, 60.0)
    gl.data.uv_layers.new(name="UV")
    gl.data.materials.append(glow)
    for attr in ("scout_col", "scout_pbr"):
        for ob in (low, spear):
            a = ob.data.attributes.get(attr)
            if a:
                ob.data.attributes.remove(a)
    # One body, three surfaces, weights by name.
    per_vert = list(both.bones[:n_body])
    per_vert_all = per_vert + list(C.bones) + list(G.bones)
    # The body's verts survived in order: faces went, verts of the spear with them.
    low.data.update()
    activate(low)
    cl.select_set(True)
    gl.select_set(True)
    bpy.context.view_layer.objects.active = low
    bpy.ops.object.join()
    body = low
    body.name = body.data.name = "ScoutBody"
    if len(body.data.vertices) != len(per_vert_all):
        raise RuntimeError("vertex count %d, weights for %d" % (len(body.data.vertices), len(per_vert_all)))
    assign_weights(body, arm, per_vert_all)
    # The exporter's tangents want triangles (cut as the bake cut them); no
    # vertex moves or renumbers.
    for ob in (body, spear):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method='FIXED', ngon_method='BEAUTY')
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    tris2 = sum(len(p.vertices) - 2 for p in spear.data.polygons)
    log("body %d tris, %d verts; spear %d tris" % (tris, len(body.data.vertices), tris2))
    # Keep the high mesh in the source, out of the way.
    col_hi = bpy.data.collections.new("High (bake only)")
    bpy.context.scene.collection.children.link(col_hi)
    col_hi.objects.link(high)
    bpy.context.scene.collection.objects.unlink(high)
    col_hi.hide_render = True

    if preview:
        set_preview_scene([body, spear], preview, "model")
        return
    bpy.context.view_layer.update()
    # No scout.blend1 beside it.
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "scout.blend"), compress=True)
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    body.select_set(True)
    spear.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format='GLB',
        use_selection=True,
        export_animations=False,
        export_skins=True,
        export_def_bones=False,
        export_yup=True,
        export_apply=False,
        export_tangents=True,
        export_image_format='AUTO',
    )
    log("wrote", OUT)


# tools/build_sword_skeleton.py borrows the modelling helpers above.
if __name__ == "__main__":
    main()
