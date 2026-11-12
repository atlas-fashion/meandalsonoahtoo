"""The dungeon's architecture kit (note 183), modelled in Blender from nothing.

    blender -b --python tools/dungeon_kit_textures.py     # the three materials' maps
    blender -b --python tools/build_dungeon_kit.py        # models/dungeon/dungeon_kit.glb
    blender -b --python tools/build_dungeon_kit.py -- --preview=<dir> [--only=wall,arch]

One object per piece, in the frames and sizes of the Tripo brick kit it replaces
(tools/build_brick_kit.py, scripts/brick_level.gd), so every measure in the game
that was taken off the old pieces still holds: the corridor 3.8 m between wall
faces, the vault springing at 3.0 m to a crown at 5.1, an arch 3.38 m wide on
every cell boundary with its soffit at ~4.76, a pillar 0.9 m square and 3.2 high.

## How a piece is made

Every stone is its own little shell: a face, a worn bevel round it and sides
going back into the joint, laid on a SURFACE (a plane, the vault's pointed
barrel, an arch's intrados) in that surface's own metres. Stones are laid in
courses with broken joints; each takes its own patch of ONE tiling stone
texture (turned, flipped, shifted), its own shade in the vertex colours, and
sits a few millimetres proud of or behind its neighbours. Behind every stone a
dark backing closes the joint, so a piece has no hole anywhere a stone is.

Three materials for the whole kit, by name: `dk_stone`, `dk_wood`, `dk_iron`.
The glb carries NO textures: scripts/brick_level.gd builds the three materials
from models/dungeon/dk_*.jpg and hands them to every surface by name. Vertex
colour is the stones' shade times the dirt (dark in the joints, dark at the
foot of a wall, sooty under the vault).

Everything is built in Godot's frame (y up, a wall's front +Z) and turned into
Blender's at the end of each piece: (x, y, z) -> (x, -z, y).
"""
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "models", "dungeon")
OUT = os.path.join(OUT_DIR, "dungeon_kit.glb")
G2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

## Metres one repeat of each material covers (u, v).
TILE = {"stone": (2.0, 2.0), "wood": (1.0, 2.0), "iron": (1.0, 1.0)}

# The cell (scripts/brick_level.gd).
WALL_FACE = 1.9
WALL_LEN = 5.2
WALL_HEIGHT = 3.5
SPRING = 3.0
CROWN = 5.1
VAULT_HALF = 3.03
# The vault's profile: two arcs, each struck from a centre VAULT_C past the
# middle on the springing line -- a pointed barrel, 2.1 m of rise on 1.9 of span.
VAULT_C = ((CROWN - SPRING) ** 2 - WALL_FACE ** 2) / (2.0 * WALL_FACE)
VAULT_R = WALL_FACE + VAULT_C
VAULT_L = VAULT_R * math.acos(VAULT_C / VAULT_R)   # arc length of one side
# The arch on a cell boundary: an opening ARCH_A either side of the middle up to
# ARCH_SPRING, then half an ellipse ARCH_B high. The cells' gates (build_cell_kit.py:
# 1.64 / 3.3 / apex 4.74) hang inside it.
ARCH_A = 1.69
ARCH_SPRING = 3.3
ARCH_B = 1.46
ARCH_OUTER = 3.3
ARCH_TOP = 5.6
ARCH_Z = 0.6
PILLAR_HALF = 0.45
PILLAR_HEIGHT = 3.2
FLOOR_TILE = 3.0
MANHOLE_R = 0.5
# The wooden door's own stone arch (module_level `_build_brick_door`): the leaf's
# outline (build_brick_kit.py DOOR_LEAF_HEAD, drawn 1.05 x 1.03 larger so its
# edges tuck in), in a slab DOOR_OUTER wide and DOOR_TOP high, DOOR_Z deep.
DOOR_HEAD = [(0.95, 3.10), (0.88, 3.30), (0.74, 3.50), (0.59, 3.70), (0.46, 3.90), (0.24, 4.10), (0.0, 4.30)]
DOOR_OUTER = 1.8
DOOR_TOP = 5.0
DOOR_Z = (-1.14, -0.02)
# The torch pillar's torch: where its head's top is (brick_level.TORCH_HEAD).
TORCH_HEAD = Vector((0.0, 2.72, 0.63))

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = next((a.split("=", 1)[1] for a in ARGS if a.startswith("--preview=")), "")
ONLY = next((a.split("=", 1)[1].split(",") for a in ARGS if a.startswith("--only=")), [])


def log(*a):
    print("[dungeon_kit]", *a, flush=True)


def smooth(x, lo, hi):
    t = min(max((x - lo) / (hi - lo), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


# --- geometry accumulator (Godot frame) ---------------------------------------------

class Acc:
    def __init__(self):
        self.v = []
        self.f = []
        self.uv = []
        self.col = []
        self.m = []

    def vert(self, p):
        self.v.append(Vector(p))
        return len(self.v) - 1

    def face(self, idx, uvs, cols, mat):
        self.f.append(tuple(idx))
        self.uv.append([tuple(x) for x in uvs])
        self.col.append([tuple(c) for c in cols])
        self.m.append(mat)

    def flip_from(self, start):
        for i in range(start, len(self.f)):
            self.f[i] = tuple(reversed(self.f[i]))
            self.uv[i].reverse()
            self.col[i].reverse()

    def tris(self):
        return sum(len(f) - 2 for f in self.f)


# --- surfaces: metres (u, v) and a distance d in front, to a point -------------------

class Plane:
    def __init__(self, origin, u_axis, v_axis):
        self.o = Vector(origin)
        self.u = Vector(u_axis).normalized()
        self.v = Vector(v_axis).normalized()
        self.n = self.u.cross(self.v).normalized()

    def at(self, u, v, d=0.0):
        return self.o + self.u * u + self.v * v + self.n * d


class Barrel:
    """The vault's inside: u the arc length from the west springing over the
    crown to the east one, v along the corridor (Godot z), d down into the room."""

    def at(self, u, v, d=0.0):
        right = u > VAULT_L
        s = (2.0 * VAULT_L - u) if right else u
        a = s / VAULT_R
        x = VAULT_C - VAULT_R * math.cos(a)
        y = SPRING + VAULT_R * math.sin(a)
        nx, ny = math.cos(a), -math.sin(a)
        x += nx * d
        y += ny * d
        return Vector((-x if right else x, y, v))


def vault_y(x):
    """The vault's inner height over a point `x` across the corridor."""
    return SPRING + math.sqrt(max(VAULT_R ** 2 - (abs(x) + VAULT_C) ** 2, 0.0))


class Intrados:
    """A doorway's inside curve, springing to springing, as a polyline in (x, y):
    u the arc length from the left springing, v along the wall's thickness
    (Godot z), d into the opening. `face(sign)` gives the wall face round it:
    u along the curve, v out from it, d out of the wall."""

    def __init__(self, pts, n0=None, n1=None):
        self._init(pts)
        # The normals at the two ends, where the curve stops at a point (a
        # pointed arch's apex: the two halves meet on a plumb joint).
        if n0 is not None:
            self.n[0] = Vector(n0).normalized()
        if n1 is not None:
            self.n[-1] = Vector(n1).normalized()

    def _init(self, pts):
        self.p = [Vector((x, y)) for x, y in pts]
        self.s = [0.0]
        for a, b in zip(self.p, self.p[1:]):
            self.s.append(self.s[-1] + (b - a).length)
        self.length = self.s[-1]
        # Outward normals at the points: the average of the two segments'.
        seg = []
        for a, b in zip(self.p, self.p[1:]):
            t = (b - a).normalized()
            seg.append(Vector((-t.y, t.x)))   # left of travel: out, going left to right over the top
        self.n = []
        for i in range(len(self.p)):
            n = (seg[max(i - 1, 0)] + seg[min(i, len(seg) - 1)]).normalized()
            self.n.append(n)

    def point(self, u):
        u = min(max(u, 0.0), self.length)
        for i in range(len(self.s) - 1):
            if u <= self.s[i + 1] or i == len(self.s) - 2:
                t = (u - self.s[i]) / max(self.s[i + 1] - self.s[i], 1e-9)
                return self.p[i].lerp(self.p[i + 1], t), self.n[i].lerp(self.n[i + 1], t).normalized()

    def soffit(self):
        return _Soffit(self)

    def face(self, z, sign):
        return _Ring(self, z, sign)


class _Soffit:
    def __init__(self, intr):
        self.i = intr

    def at(self, u, v, d=0.0):
        p, n = self.i.point(u)
        q = p - n * d
        return Vector((q.x, q.y, v))


class _Ring:
    def __init__(self, intr, z, sign):
        self.i = intr
        self.z = z
        self.sign = sign

    def at(self, u, v, d=0.0):
        p, n = self.i.point(u)
        q = p + n * v
        return Vector((q.x, q.y, self.z + self.sign * d))


class Polar:
    """A flat ring on the floor round `centre`: u the arc at radius `r0` from
    angle `a0`, v outward from r0, d up."""

    def __init__(self, centre, r0, a0):
        self.c = Vector(centre)
        self.r0 = r0
        self.a0 = a0

    def at(self, u, v, d=0.0):
        a = self.a0 + u / self.r0
        r = self.r0 + v
        return self.c + Vector((r * math.cos(a), d, -r * math.sin(a)))


class Drum:
    """A round shaft about the y axis through `centre`: u round it at radius r, v up."""

    def __init__(self, centre, r, axis_rot=None):
        self.c = Vector(centre)
        self.r = r
        self.rot = axis_rot or Matrix.Identity(3)

    def at(self, u, v, d=0.0):
        a = u / self.r
        r = self.r + d
        return self.c + self.rot @ Vector((r * math.sin(a), v, r * math.cos(a)))


# --- stones ----------------------------------------------------------------------------

def stone_tint(rng):
    g = rng.uniform(0.80, 1.10)
    k = rng.random()
    if k < 0.12:
        g *= 0.72
    elif k > 0.92:
        g *= 1.2
    w = rng.uniform(-0.05, 0.05)
    return (g * (1.0 + w), g, g * (1.0 - w * 1.2))


def mul(c, k):
    return (c[0] * k, c[1] * k, c[2] * k)


def no_shade(_p):
    return 1.0


def tex_map(rng, mat, cu, cv, turn=None):
    """A stone's own patch of the tiling texture: (u, v) metres -> uv."""
    rot = rng.randrange(4) if turn is None else turn
    flip = rng.random() < 0.5 if turn is None else False
    ou, ov = rng.random(), rng.random()
    tu, tv = TILE[mat]

    def f(u, v):
        du, dv = u - cu, v - cv
        if flip:
            du = -du
        for _ in range(rot):
            du, dv = -dv, du
        return (ou + du / tu, ov + dv / tv)
    return f


def stone(acc, surf, u0, u1, v0, v1, rng, mat="stone", gap=0.012, bevel=None, depth=0.045,
          proud=0.0, grid=0.26, rough=0.005, bulge=0.004, chip=0.25, tint=None, shade=no_shade,
          back=True, warp=None, turn=None, joint=0.36, open="", bed=0.075):
    """One stone on `surf` over (u0..u1, v0..v1): its face, its bevel going back
    to the joint `depth` behind the surface, and the dark backing behind it
    (`bed` behind the surface, the SAME for every stone on it, so the backings
    of neighbours meet whatever each stone's own depth). `warp(u, v) -> (u, v)`
    bends it (to tuck it under something); `proud` stands it out of the surface
    (a base course, a keystone) or sets it back. `open` names the edges ("u",
    "U", "v", "V" for u0, u1, v0, v1) that are an arris -- where the stone turns
    a corner onto another face: there the bevel is half a chamfer, met by the
    other face's half, and is not darkened as a joint is."""
    bu0, bu1, bv0, bv1 = u0, u1, v0, v1
    if "u" not in open:
        u0 += gap * 0.5
    if "U" not in open:
        u1 -= gap * 0.5
    if "v" not in open:
        v0 += gap * 0.5
    if "V" not in open:
        v1 -= gap * 0.5
    w, h = u1 - u0, v1 - v0
    if w < 0.03 or h < 0.03:
        return
    b = rng.uniform(0.014, 0.03) if bevel is None else bevel
    b = min(b, w * 0.3, h * 0.3)
    nu = max(1, int(round(w / grid)))
    nv = max(1, int(round(h / grid)))
    t = tint or stone_tint(rng)
    tex = tex_map(rng, mat, (u0 + u1) * 0.5, (v0 + v1) * 0.5, turn)
    seed = Vector((rng.uniform(0, 50), rng.uniform(0, 50), rng.uniform(0, 50)))
    wp = warp or (lambda a, c: (a, c))
    start = len(acc.f)
    back_d = min(-depth, proud - depth)

    # Corner chips.
    chips = {}
    for ci, cj in ((0, 0), (nu, 0), (nu, nv), (0, nv)):
        if rng.random() < chip:
            c = rng.uniform(0.025, max(0.03, min(0.10, w * 0.28, h * 0.28)))
            chips[(ci, cj)] = (c, c * rng.uniform(0.5, 1.0), rng.uniform(0.006, 0.02))
    ids = {}
    pos = {}
    moved = {}
    for j in range(nv + 1):
        for i in range(nu + 1):
            fu, fv = i / nu, j / nv
            u = u0 + b + fu * (w - 2 * b)
            v = v0 + b + fv * (h - 2 * b)
            edge = i in (0, nu) or j in (0, nv)
            d = proud + bulge * math.sin(math.pi * fu) * math.sin(math.pi * fv)
            if (i, j) in chips:
                c = chips[(i, j)]
                u += c[0] if i == 0 else -c[0]
                v += c[1] if j == 0 else -c[1]
                d -= c[2]
            wu, wv = wp(u, v)
            moved[(i, j)] = abs(wu - u) + abs(wv - v) > 1e-9
            u, v = wu, wv
            p0 = surf.at(u, v, 0.0)
            d += rough * noise.noise(p0 * 6.0 + seed) - (0.003 if edge else 0.0)
            p = surf.at(u, v, d)
            ids[(i, j)] = acc.vert(p)
            pos[(i, j)] = (u, v, p)
    s_face = {k: shade(pos[k][2]) for k in pos}
    for j in range(nv):
        for i in range(nu):
            ks = ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))
            if all(moved[k] for k in ks):
                continue   # wholly tucked away: it would span whatever it was tucked round
            acc.face([ids[k] for k in ks], [tex(pos[k][0], pos[k][1]) for k in ks],
                     [mul(t, s_face[k]) for k in ks], mat)
    # The bevel: the face's edge out to the stone's full size, down in the joint.
    loop = [(i, 0) for i in range(nu + 1)] + [(nu, j) for j in range(1, nv + 1)] \
        + [(i, nv) for i in range(nu - 1, -1, -1)] + [(0, j) for j in range(nv - 1, 0, -1)]
    ring = []
    for (i, j) in loop:
        fu, fv = i / nu, j / nv
        uo, vo = u0 + fu * w, v0 + fv * h
        d = back_d
        arris = False
        if (i == 0 and "u" in open) or (i == nu and "U" in open):
            uo += b * 0.5 if i == 0 else -b * 0.5
            arris = True
        if (j == 0 and "v" in open) or (j == nv and "V" in open):
            vo += b * 0.5 if j == 0 else -b * 0.5
            arris = True
        if arris:
            d = proud - b * 0.5
        uo, vo = wp(uo, vo)
        p = surf.at(uo, vo, d)
        ui, vi, _ = pos[(i, j)]
        ring.append((acc.vert(p), tex(uo + (uo - ui) * 1.5, vo + (vo - vi) * 1.5), shade(p) * (0.92 if arris else joint)))
    n = len(loop)
    for k in range(n):
        a, c = loop[k], loop[(k + 1) % n]
        ra, rc = ring[k], ring[(k + 1) % n]
        if moved[a] and moved[c]:
            continue
        acc.face([ids[a], ra[0], rc[0], ids[c]],
                 [tex(pos[a][0], pos[a][1]), ra[1], rc[1], tex(pos[c][0], pos[c][1])],
                 [mul(t, s_face[a]), mul(t, ra[2]), mul(t, rc[2]), mul(t, s_face[c])], mat)
    if back:
        # The joint's bed: dark, one sheet behind every stone of the surface.
        su = max(1, nu) if (warp or nu > 1) else 1
        sv = max(1, nv) if warp else 1
        bp = {}
        for j in range(sv + 1):
            for i in range(su + 1):
                uu = bu0 + (bu1 - bu0) * i / su
                vv = bv0 + (bv1 - bv0) * j / sv
                wq = wp(uu, vv)
                p = surf.at(wq[0], wq[1], -bed)
                bp[(i, j)] = (acc.vert(p), tex(uu, vv), mul((1, 1, 1), shade(p) * 0.2), abs(wq[0] - uu) + abs(wq[1] - vv) > 1e-9)
        for j in range(sv):
            for i in range(su):
                ks = ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))
                if all(bp[k][3] for k in ks):
                    continue
                acc.face([bp[k][0] for k in ks], [bp[k][1] for k in ks], [bp[k][2] for k in ks], mat)
    # Facing the front of the surface, whichever way its u and v run.
    um, vm = wp((u0 + u1) * 0.5, (v0 + v1) * 0.5)
    e = 0.01
    o = surf.at(um, vm, 0.0)
    nrm = (surf.at(um + e, vm, 0.0) - o).cross(surf.at(um, vm + e, 0.0) - o)
    if nrm.dot(surf.at(um, vm, e) - o) < 0.0:
        acc.flip_from(start)


def quad(acc, pts, facing, mat="stone", col=0.5, rng=None, scale=1.0):
    """A plain quad, wound to face `facing`; its texture laid flat over it."""
    pts = [Vector(p) for p in pts]
    n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
    if n.length < 1e-9:
        n = (pts[2] - pts[1]).cross(pts[3] - pts[1])
    if n.dot(Vector(facing)) < 0.0:
        pts.reverse()
        n = -n
    n.normalize()
    ua = (pts[1] - pts[0]).normalized()
    va = n.cross(ua)
    ou, ov = (rng.random(), rng.random()) if rng else (0.0, 0.0)
    tu, tv = TILE[mat]
    uvs = [(ou + (p - pts[0]).dot(ua) / tu * scale, ov + (p - pts[0]).dot(va) / tv * scale) for p in pts]
    c = col if isinstance(col, tuple) else (col, col, col)
    acc.face([acc.vert(p) for p in pts], uvs, [c] * 4, mat)


def courses(rng, total, lo, hi, first=None, last=None):
    """Course heights summing to `total`."""
    out = [first] if first else []
    left = total - sum(out) - (last or 0.0)
    while left > 1e-6:
        h = rng.uniform(lo, hi)
        if left - h < lo:
            if left <= hi:
                h = left
            else:
                h = left * 0.5
        out.append(h)
        left -= h
    if last:
        out.append(last)
    return out


def lay(rng, a, b, lmin, lmax, avoid=(), clear=0.13):
    """Joints along one course from a to b, none within `clear` of the course
    below's (`avoid`). Returns the stones' (start, end)."""
    xs = [a]
    while True:
        x = xs[-1] + rng.uniform(lmin, lmax)
        if b - x < lmin * 0.6:
            break
        for _ in range(8):
            if all(abs(x - j) > clear for j in avoid):
                break
            x += clear * 0.9
        if b - x < lmin * 0.6:
            break
        xs.append(x)
    xs.append(b)
    return list(zip(xs, xs[1:]))


def stone_box(acc, lo, hi, rng, faces="xXyYzZ", rot=None, origin=None, **kw):
    """A dressed block, each named face a stone ('x' = the -X face, 'X' = +X ...).
    `rot` (3x3) turns it about `origin` (its middle by default)."""
    lo, hi = Vector(lo), Vector(hi)
    mid = (lo + hi) * 0.5 if origin is None else Vector(origin)
    r = rot or Matrix.Identity(3)

    def P(p):
        return mid + r @ (Vector(p) - mid)

    def D(d):
        return r @ Vector(d)
    kw.setdefault("gap", 0.0)
    kw.setdefault("back", False)
    kw.setdefault("open", "uUvV")
    kw.setdefault("tint", stone_tint(rng))
    sx, sy, sz = hi - lo
    spec = {
        "Z": ((lo.x, lo.y, hi.z), (1, 0, 0), (0, 1, 0), sx, sy),
        "z": ((hi.x, lo.y, lo.z), (-1, 0, 0), (0, 1, 0), sx, sy),
        "X": ((hi.x, lo.y, hi.z), (0, 0, -1), (0, 1, 0), sz, sy),
        "x": ((lo.x, lo.y, lo.z), (0, 0, 1), (0, 1, 0), sz, sy),
        "Y": ((lo.x, hi.y, hi.z), (1, 0, 0), (0, 0, -1), sx, sz),
        "y": ((lo.x, lo.y, lo.z), (1, 0, 0), (0, 0, 1), sx, sz),
    }
    for f in faces:
        o, ua, va, w, h = spec[f]
        stone(acc, Plane(P(o), D(ua), D(va)), 0.0, w, 0.0, h, rng, **kw)


def rock(acc, centre, size, rng, tint=None, shade=no_shade, points=16):
    """A broken lump: the hull of a few points on a squashed ball."""
    bm = bmesh.new()
    for _ in range(points):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        k = rng.uniform(0.75, 1.0)
        bm.verts.new((d.x * size[0] * 0.5 * k, d.y * size[1] * 0.5 * k, d.z * size[2] * 0.5 * k))
    res = bmesh.ops.convex_hull(bm, input=bm.verts)
    junk = list({e for e in res.get("geom_interior", []) + res.get("geom_unused", []) if isinstance(e, bmesh.types.BMVert)})
    if junk:
        bmesh.ops.delete(bm, geom=junk, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    rot = Matrix.Rotation(rng.uniform(0, math.tau), 3, "Y") @ Matrix.Rotation(rng.uniform(-0.4, 0.4), 3, "X")
    t = tint or stone_tint(rng)
    c = Vector(centre)
    ids = {}
    for v in bm.verts:
        ids[v.index] = acc.vert(c + rot @ v.co)
    ou, ov = rng.random(), rng.random()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a1, a2 = [i for i in range(3) if i != ax]
        cols = []
        for v in f.verts:
            p = c + rot @ v.co
            cols.append(mul(t, shade(p) * (0.55 + 0.45 * smooth(v.co.y, -size[1] * 0.5, size[1] * 0.2))))
        acc.face([ids[v.index] for v in f.verts],
                 [(ou + v.co[a1] / 2.0 + ax * 0.31, ov + v.co[a2] / 2.0) for v in f.verts], cols, "stone")
    bm.free()


# --- swept things: mouldings, ribs, timber, iron ------------------------------------------

def sweep(acc, path, profile, mat, ups=None, closed=False, caps=True, col=1.0, tint=(1, 1, 1),
          rng=None, v_scale=1.0, joints=None):
    """`profile` ((a, b) pairs, counter-clockwise looking along the path) swept
    along `path`. At each point a is `side` (tangent x up) and b is the up hint
    made square to the tangent. u runs round the profile, v along the path."""
    path = [Vector(p) for p in path]
    n = len(path)
    k = len(profile)
    per = [0.0]
    for i in range(k):
        a, b = profile[i], profile[(i + 1) % k]
        per.append(per[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    tu, tv = TILE[mat]
    ou, ov = (rng.random(), rng.random()) if rng else (0.0, 0.0)
    rings = []
    dist = 0.0
    cols = col if isinstance(col, (list, tuple)) else [col] * n
    for i, p in enumerate(path):
        if closed:
            t = path[(i + 1) % n] - path[i - 1]
        elif i == 0:
            t = path[1] - path[0]
        elif i == n - 1:
            t = path[-1] - path[-2]
        else:
            t = path[i + 1] - path[i - 1]
        t.normalize()
        up = Vector(ups[i]) if ups else (Vector((0, 1, 0)) if abs(t.y) < 0.95 else Vector((0, 0, 1)))
        side = t.cross(up).normalized()
        up = side.cross(t).normalized()
        if i > 0:
            dist += (p - path[i - 1]).length
        c = cols[i]
        if joints:
            c = c * (1.0 - 0.55 * max(0.0, 1.0 - min(abs(dist - j) for j in joints) / 0.02))
        rings.append(([acc.vert(p + side * a + up * b) for a, b in profile], dist, mul(tint, c)))
    segs = n if closed else n - 1
    for i in range(segs):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for j in range(k):
            j2 = (j + 1) % k
            acc.face((r0[0][j], r0[0][j2], r1[0][j2], r1[0][j]),
                     [(ou + per[j] / tu, ov + r0[1] / tv * v_scale), (ou + per[j + 1] / tu, ov + r0[1] / tv * v_scale),
                      (ou + per[j + 1] / tu, ov + r1[1] / tv * v_scale), (ou + per[j] / tu, ov + r1[1] / tv * v_scale)],
                     [r0[2], r0[2], r1[2], r1[2]], mat)
    if caps and not closed:
        for ring, rev in ((rings[0], True), (rings[-1], False)):
            idx = list(ring[0])
            uvs = [(ou + 0.37 + a / tu, ov + 0.11 + b / tu) for a, b in profile]
            if rev:
                idx.reverse()
                uvs.reverse()
            acc.face(idx, uvs, [mul(ring[2], 0.7)] * k, mat)


def circle(r, n, phase=0.0):
    return [(r * math.cos(phase + math.tau * i / n), r * math.sin(phase + math.tau * i / n)) for i in range(n)]


def rect(w, h, chamfer=0.0):
    if chamfer <= 0.0:
        return [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    c = chamfer
    return [(-w / 2 + c, -h / 2), (w / 2 - c, -h / 2), (w / 2, -h / 2 + c), (w / 2, h / 2 - c),
            (w / 2 - c, h / 2), (-w / 2 + c, h / 2), (-w / 2, h / 2 - c), (-w / 2, -h / 2 + c)]


def beam(acc, a, b, w, h, rng, mat="wood", up=None, chamfer=0.012, wobble=0.012, tint=None, seg=0.6, col=1.0):
    """A hewn timber from a to b, w across and h on the up side: not quite
    straight, its corners worn, the grain along it."""
    a, b = Vector(a), Vector(b)
    length = (b - a).length
    n = max(2, int(round(length / seg)) + 1)
    axis = (b - a).normalized()
    hint = Vector(up) if up else (Vector((0, 1, 0)) if abs(axis.y) < 0.9 else Vector((0, 0, 1)))
    side = axis.cross(hint).normalized()
    upv = side.cross(axis).normalized()
    ph = rng.uniform(0, 30)
    path = []
    for i in range(n):
        t = i / (n - 1)
        env = math.sin(math.pi * t)
        path.append(a.lerp(b, t) + side * wobble * env * noise.noise(Vector((t * 2.3, ph, 0.0)))
                    + upv * wobble * env * noise.noise(Vector((t * 2.3, ph, 7.0))))
    g = rng.uniform(0.78, 1.1) if tint is None else 1.0
    tn = tint or (g * rng.uniform(0.96, 1.06), g, g * rng.uniform(0.92, 1.02))
    prof = [(x * rng.uniform(0.97, 1.03), y * rng.uniform(0.97, 1.03)) for x, y in rect(w, h, chamfer)]
    cols = [col * (0.72 if i in (0, n - 1) else 1.0) for i in range(n)]
    sweep(acc, path, prof, mat, ups=[upv] * n, col=cols, tint=tn, rng=rng)


def bar(acc, a, b, w, h, rng, up=None, tint=(1, 1, 1), col=1.0):
    """A straight iron bar."""
    a, b = Vector(a), Vector(b)
    axis = (b - a).normalized()
    hint = Vector(up) if up else (Vector((0, 1, 0)) if abs(axis.y) < 0.9 else Vector((0, 0, 1)))
    side = axis.cross(hint).normalized()
    upv = side.cross(axis).normalized()
    sweep(acc, [a, b], rect(w, h), "iron", ups=[upv, upv], col=col, tint=tint, rng=rng)


def lathe(acc, prof, segs, mat, xf=None, col=1.0, tint=(1, 1, 1), rng=None):
    """Revolves (r, y) points round the local Y axis; r == 0 closes to a point."""
    xf = xf or Matrix.Identity(4)
    ou, ov = (rng.random(), rng.random()) if rng else (0.0, 0.0)
    tu, tv = TILE[mat]
    rings = []
    run = 0.0
    for k, (r, y) in enumerate(prof):
        if k > 0:
            run += math.hypot(r - prof[k - 1][0], y - prof[k - 1][1])
        if r < 1e-6:
            rings.append(([acc.vert(xf @ Vector((0, y, 0)))], run, r))
        else:
            rings.append(([acc.vert(xf @ Vector((r * math.cos(math.tau * i / segs), y, -r * math.sin(math.tau * i / segs))))
                           for i in range(segs)], run, r))
    c = mul(tint, col)
    for a, b in zip(rings, rings[1:]):
        ra = max(a[2], b[2])
        for i in range(segs):
            j = (i + 1) % segs
            u0, u1 = ou + ra * math.tau * i / segs / tu, ou + ra * math.tau * (i + 1) / segs / tu
            va, vb = ov + a[1] / tv, ov + b[1] / tv
            if len(a[0]) == 1 and len(b[0]) == 1:
                continue
            if len(a[0]) == 1:
                acc.face((a[0][0], b[0][j], b[0][i]), [(u0, va), (u1, vb), (u0, vb)], [c] * 3, mat)
            elif len(b[0]) == 1:
                acc.face((a[0][i], a[0][j], b[0][0]), [(u0, va), (u1, va), (u0, vb)], [c] * 3, mat)
            else:
                acc.face((a[0][i], a[0][j], b[0][j], b[0][i]), [(u0, va), (u1, va), (u1, vb), (u0, vb)], [c] * 4, mat)


def ibox(acc, lo, hi, rng, mat="iron", tint=(1, 1, 1), col=1.0, rot=None, origin=None):
    """A plain box of iron (or wood), every face mapped flat."""
    lo, hi = Vector(lo), Vector(hi)
    mid = (lo + hi) * 0.5 if origin is None else Vector(origin)
    r = rot or Matrix.Identity(3)
    c = [mid + r @ (Vector((x, y, z)) - mid) for x in (lo.x, hi.x) for y in (lo.y, hi.y) for z in (lo.z, hi.z)]
    cm = mid + r @ ((lo + hi) * 0.5 - mid)
    for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        pts = [c[i] for i in q]
        fc = sum(pts, Vector()) / 4.0
        quad(acc, pts, fc - cm, mat, mul(tint, col), rng)


# --- objects ------------------------------------------------------------------------------

MATS = {}


def material(kind):
    if kind in MATS:
        return MATS[kind]
    mat = bpy.data.materials.new("dk_" + kind)
    mat.use_nodes = True
    if PREVIEW:
        nt = mat.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        imgs = {}
        for part in ("albedo", "normal", "orm"):
            path = os.path.join(OUT_DIR, "dk_%s_%s.jpg" % (kind, part))
            if os.path.exists(path):
                im = bpy.data.images.load(path)
                im.colorspace_settings.name = "sRGB" if part == "albedo" else "Non-Color"
                node = nt.nodes.new("ShaderNodeTexImage")
                node.image = im
                imgs[part] = node
        if "albedo" in imgs:
            vc = nt.nodes.new("ShaderNodeVertexColor")
            vc.layer_name = "Col"
            mx = nt.nodes.new("ShaderNodeMix")
            mx.data_type = "RGBA"
            mx.blend_type = "MULTIPLY"
            mx.inputs[0].default_value = 1.0
            nt.links.new(imgs["albedo"].outputs["Color"], mx.inputs[6])
            nt.links.new(vc.outputs["Color"], mx.inputs[7])
            nt.links.new(mx.outputs[2], bsdf.inputs["Base Color"])
        if "normal" in imgs:
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nt.links.new(imgs["normal"].outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        if "orm" in imgs:
            sep = nt.nodes.new("ShaderNodeSeparateColor")
            nt.links.new(imgs["orm"].outputs["Color"], sep.inputs["Color"])
            nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
            nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    MATS[kind] = mat
    return mat


def make_object(name, acc, smooth_normals=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in acc.v], [], acc.f)
    me.update(calc_edges=True)
    kinds = sorted(set(acc.m))
    for kind in kinds:
        me.materials.append(material(kind))
    for poly, m in zip(me.polygons, acc.m):
        poly.material_index = kinds.index(m)
        poly.use_smooth = True
    uv = me.uv_layers.new(name="UVMap")
    flat = np.array([c for f in acc.uv for xy in f for c in xy], dtype=np.float32)
    uv.data.foreach_set("uv", flat)
    col = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
    rgba = np.array([c for f in acc.col for rgb in f for c in (rgb[0], rgb[1], rgb[2], 1.0)], dtype=np.float32)
    col.data.foreach_set("color", np.clip(rgba, 0.0, 1.5))
    me.color_attributes.active_color = col
    me.color_attributes.render_color_index = 0
    me.transform(G2B)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if smooth_normals:
        weighted_normals(ob)
    return ob


def weighted_normals(ob):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    mod = ob.modifiers.new("wn", "WEIGHTED_NORMAL")
    mod.mode = "FACE_AREA"
    mod.weight = 50
    mod.keep_sharp = False
    try:
        bpy.ops.object.modifier_apply(modifier=mod.name)
    except Exception as ex:  # noqa: BLE001
        log("weighted normals failed on", ob.name, ex)


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def report(ob):
    co = np.array([tuple(v.co) for v in ob.data.vertices])
    lo, hi = co.min(axis=0), co.max(axis=0)
    # Blender (x, y, z) -> Godot (x, z, -y)
    log("%-16s %6d tris  x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f"
        % (ob.name, tri_count(ob), lo[0], hi[0], lo[2], hi[2], -hi[1], -lo[1]))


# --- walls -----------------------------------------------------------------------------------

def wall_shade(p):
    """Dirt: damp and dark at the foot, soot under the vault."""
    return (0.60 + 0.40 * smooth(p.y, 0.0, 1.0)) * (1.0 - 0.22 * smooth(p.y, 2.5, 3.5))


def lay_wall(acc, surf, rng, u0, u1, heights, missing=None, proud_of=None, lmin=0.55, lmax=1.15,
             shade=wall_shade, pit_depth=0.24, v0=0.0, keep=None, warp=None):
    """Courses of stones on `surf` from u0 to u1, bottom up from v0. `missing(u,
    v)` leaves a stone out and lines the hole it leaves; `proud_of(course)`
    stands a whole course out; `keep(u0, u1, v0, v1)` drops stones nobody sees."""
    v = v0
    prev = []
    gone = []
    rows = []
    for ci, h in enumerate(heights):
        segs = lay(rng, u0, u1, lmin, lmax, prev)
        prev = [b for _, b in segs[:-1]]
        rows.append((v, h, segs, ci))
        v += h
    for (v, h, segs, ci) in rows:
        for (a, b) in segs:
            if missing and missing((a + b) * 0.5, v + h * 0.5):
                gone.append((a, b, v, v + h))
    for (v, h, segs, ci) in rows:
        cp = proud_of(ci) if proud_of else 0.0
        for (a, b) in segs:
            if keep and not keep(a, b, v, v + h):
                continue
            if (a, b, v, v + h) in gone:
                _pit(acc, surf, rng, a, b, v, v + h, gone, pit_depth, shade)
                continue
            ext = cp if cp > 0.0 else 0.0
            stone(acc, surf, a - (ext if a <= u0 + 1e-6 else 0.0), b + (ext if b >= u1 - 1e-6 else 0.0), v, v + h, rng,
                  proud=cp + (rng.gauss(0.0, 0.006) if cp == 0.0 else 0.0), shade=shade, warp=warp,
                  bevel=None if cp == 0.0 else 0.03)
    return rows


def _pit(acc, surf, rng, a, b, v0, v1, gone, depth, shade):
    """Where a stone has fallen out: the rubble core behind it, and the sides
    of the hole wherever a stone still stands next to it."""
    core = depth * rng.uniform(0.8, 1.1)
    n = 2 if (b - a) > 0.6 else 1
    dark = lambda p: shade(p) * 0.55
    for i in range(n):
        ua = a + (b - a) * i / n
        ub = a + (b - a) * (i + 1) / n
        cuts = [v0, v1]
        if rng.random() < 0.5 and (v1 - v0) > 0.3:
            cuts.insert(1, v0 + (v1 - v0) * rng.uniform(0.4, 0.6))
        for va, vb in zip(cuts, cuts[1:]):
            stone(acc, surf, ua, ub, va, vb, rng, proud=-core + rng.uniform(-0.03, 0.04), depth=0.05, rough=0.02,
                  chip=0.7, shade=dark, gap=0.02, grid=0.18, back=False)

    def is_gone(u, v):
        return any(g[0] < u < g[1] and g[2] < v < g[3] for g in gone)
    front, deep = -0.04, -depth * 1.1 - 0.2
    e = 0.03
    sides = (((a, v0), (b, v0), (0, -e)), ((b, v0), (b, v1), (e, 0)), ((b, v1), (a, v1), (0, e)), ((a, v1), (a, v0), (-e, 0)))
    mid = surf.at((a + b) / 2, (v0 + v1) / 2, (front + deep) / 2)
    # Each side in short runs: a stone of the next course may stand against only
    # part of it.
    for p, q, off in sides:
        k = max(1, int(math.hypot(q[0] - p[0], q[1] - p[1]) / 0.08))
        for i in range(k):
            pa = (p[0] + (q[0] - p[0]) * i / k, p[1] + (q[1] - p[1]) * i / k)
            pb = (p[0] + (q[0] - p[0]) * (i + 1) / k, p[1] + (q[1] - p[1]) * (i + 1) / k)
            if is_gone((pa[0] + pb[0]) / 2 + off[0], (pa[1] + pb[1]) / 2 + off[1]):
                continue
            pts = [surf.at(pa[0], pa[1], front), surf.at(pb[0], pb[1], front), surf.at(pb[0], pb[1], deep), surf.at(pa[0], pa[1], deep)]
            c = sum(pts, Vector()) / 4.0
            s = shade(c)
            quad(acc, pts, mid - c, "stone", (0.42 * s, 0.4 * s, 0.38 * s), rng)
    # And the back of the hole, behind the core.
    pts = [surf.at(a, v0, deep + 0.01), surf.at(b, v0, deep + 0.01), surf.at(b, v1, deep + 0.01), surf.at(a, v1, deep + 0.01)]
    quad(acc, pts, surf.at((a + b) / 2, (v0 + v1) / 2, 0.0) - pts[0], "stone", 0.12, rng)


def wall_heights(rng, total=WALL_HEIGHT):
    return courses(rng, total, 0.30, 0.46, first=rng.uniform(0.44, 0.5))


def wall_caps(acc, rng, half, height, depth=0.5):
    """The top and the two ends, a little way back: a wall on its own still reads
    as a solid block."""
    z0, z1 = -depth, -0.04
    quad(acc, [(-half, height, z1), (half, height, z1), (half, height, z0), (-half, height, z0)], (0, 1, 0), "stone", 0.45, rng)
    for s in (-1, 1):
        quad(acc, [(s * half, 0, z1), (s * half, height, z1), (s * half, height, z0), (s * half, 0, z0)], (s, 0, 0), "stone", 0.45, rng)


def build_wall(name, seed, broken=False):
    rng = random.Random(seed)
    acc = Acc()
    surf = Plane((0, 0, 0), (1, 0, 0), (0, 1, 0))
    half = WALL_LEN * 0.5
    missing = None
    if broken:
        holes = [(rng.uniform(-1.6, 1.6), rng.uniform(1.5, 2.9), rng.uniform(0.35, 0.6)) for _ in range(2)]
        holes.append((rng.uniform(-1.8, 1.8), rng.uniform(0.9, 2.0), 0.22))

        def missing(u, v):
            return any(math.hypot((u - hx) * 0.8, v - hy) < hr for hx, hy, hr in holes)
    lay_wall(acc, surf, rng, -half, half, wall_heights(rng), missing=missing,
             proud_of=lambda ci: 0.045 if ci == 0 else 0.0)
    wall_caps(acc, rng, half, WALL_HEIGHT)
    return [make_object(name, acc)]


def build_wall_top():
    """The lunette over a dead end's end wall: courses up under the barrel,
    from LUNETTE_BASE (its origin is 3.1 m up the wall face)."""
    rng = random.Random(3101)
    acc = Acc()
    surf = Plane((0, 0, 0), (1, 0, 0), (0, 1, 0))
    base = 3.1

    def keep(a, b, v0, v1):
        x = min(abs(a), abs(b)) if a * b > 0 else 0.0
        return vault_y(x) + 0.12 > base + v0 if x < WALL_FACE else False
    lay_wall(acc, surf, rng, -2.3, 2.3, courses(rng, 2.25, 0.3, 0.42), keep=keep,
             shade=lambda p: 0.74 - 0.14 * smooth(p.y, 0.5, 2.0))
    return [make_object("wall_top", acc)]


def build_pier_face():
    """One face of the big square piers (the morgue's, the scoutposts'): 2.2 wide,
    up past the vault's crown, banded where the vault springs."""
    rng = random.Random(7907)
    acc = Acc()
    surf = Plane((0, 0, 0), (1, 0, 0), (0, 1, 0))
    hs = [0.5] + courses(rng, 2.42, 0.34, 0.5) + [0.16, 0.24] + courses(rng, 7.9 - 3.32, 0.36, 0.52)
    n_low = len(hs) - 2 - len(courses(random.Random(1), 1.0, 0.4, 0.6))

    def proud(ci):
        if ci == 0:
            return 0.05
        y = sum(hs[:ci])
        if abs(y - 2.92) < 0.02:
            return 0.035
        if abs(y - 3.08) < 0.02:
            return 0.07
        return 0.0
    lay_wall(acc, surf, rng, -1.1, 1.1, hs, proud_of=proud, lmin=0.5, lmax=1.0,
             shade=lambda p: (0.60 + 0.40 * smooth(p.y, 0.0, 1.0)) * (1.0 - 0.25 * smooth(p.y, 3.4, 6.5)))
    return [make_object("pier_face", acc)]


# --- the cage wall ---------------------------------------------------------------------------

def build_wall_cage():
    """A wall with an iron cage standing on a stone shelf (the bone cages,
    module_level `_brick_cage`): the cage's inside is 0.77 x 0.78 x 0.35 from
    (0.18, 1.67, 0.13); its gate, `cage_door`, is the front grille, hinged on
    its left edge at x -0.03, z 0.6."""
    rng = random.Random(4402)
    acc = Acc()
    surf = Plane((0, 0, 0), (1, 0, 0), (0, 1, 0))
    half = WALL_LEN * 0.5
    lay_wall(acc, surf, rng, -half, half, wall_heights(rng), proud_of=lambda ci: 0.045 if ci == 0 else 0.0)
    wall_caps(acc, rng, half, WALL_HEIGHT)
    sh = lambda p: 0.9
    # The shelf and its two corbels, each in two steps.
    stone_box(acc, (-0.08, 1.50, -0.02), (1.18, 1.63, 0.66), rng, faces="xXyYZ", shade=sh, grid=0.3, bevel=0.02)
    for x in (0.04, 0.88):
        stone_box(acc, (x, 1.26, -0.02), (x + 0.2, 1.50, 0.46), rng, faces="xXyZ", shade=sh, bevel=0.025)
        stone_box(acc, (x + 0.02, 1.04, -0.02), (x + 0.18, 1.26, 0.24), rng, faces="xXyZ", shade=sh, bevel=0.025)
    it = (0.95, 0.95, 0.95)
    x0, x1, y0, y1, z0, z1 = 0.02, 1.08, 1.63, 2.56, 0.03, 0.535
    # Corner posts, the top frame and its plate, bars down both sides.
    for x in (x0, x1):
        for z in (z0, z1):
            bar(acc, (x, y0, z), (x, y1, z), 0.04, 0.04, rng, tint=it)
        bar(acc, (x, y1 - 0.02, z0), (x, y1 - 0.02, z1), 0.045, 0.04, rng, tint=it)
        bar(acc, (x, y0 + 0.02, z0), (x, y0 + 0.02, z1), 0.045, 0.04, rng, tint=it)
        bar(acc, (x, (y0 + y1) / 2, z0), (x, (y0 + y1) / 2, z1), 0.012, 0.05, rng, tint=it, up=(1, 0, 0))
        for k in range(1, 4):
            z = z0 + (z1 - z0) * k / 4
            bar(acc, (x, y0, z), (x, y1, z), 0.022, 0.022, rng, tint=it)
    for z in (z0, z1):
        bar(acc, (x0, y1 - 0.02, z), (x1, y1 - 0.02, z), 0.045, 0.04, rng, tint=it)
    ibox(acc, (x0 - 0.03, y1, z0 - 0.03), (x1 + 0.03, y1 + 0.025, z1 + 0.06), rng, tint=it)
    # Four hold-fasts into the wall.
    for x in (x0, x1):
        for y in (y0 + 0.12, y1 - 0.12):
            ibox(acc, (x - 0.03, y - 0.03, -0.01), (x + 0.03, y + 0.03, 0.035), rng, tint=it)
    wall = make_object("wall_cage", acc)

    d = Acc()
    zf = 0.585
    fx0, fx1, fy0, fy1 = 0.0, 1.10, 1.645, 2.545
    for x in (fx0 + 0.02, fx1 - 0.02):
        bar(d, (x, fy0, zf), (x, fy1, zf), 0.04, 0.035, rng, tint=it)
    for y in (fy0 + 0.02, fy1 - 0.02):
        bar(d, (fx0, y, zf), (fx1, y, zf), 0.035, 0.04, rng, tint=it, up=(0, 0, 1))
    for k in range(1, 8):
        x = fx0 + (fx1 - fx0) * k / 8
        bar(d, (x, fy0, zf), (x, fy1, zf), 0.024, 0.024, rng, tint=it)
    bar(d, (fx0, (fy0 + fy1) / 2, zf + 0.018), (fx1, (fy0 + fy1) / 2, zf + 0.018), 0.012, 0.055, rng, tint=it, up=(0, 0, 1))
    # Hinge knuckles on the left, a hasp and a ring on the right.
    for y in (fy0 + 0.14, fy1 - 0.14):
        sweep(d, [(-0.03, y - 0.05, 0.6), (-0.03, y + 0.05, 0.6)], circle(0.022, 8), "iron", rng=rng)
        ibox(d, (-0.03, y - 0.02, zf - 0.01), (0.06, y + 0.02, zf + 0.025), rng, tint=it)
    ibox(d, (fx1 - 0.1, 2.05, zf + 0.015), (fx1 + 0.03, 2.13, zf + 0.04), rng, tint=it)
    ring = [Vector((fx1 - 0.05 + 0.04 * math.cos(math.tau * i / 12), 2.03 + 0.04 * math.sin(math.tau * i / 12), zf + 0.05))
            for i in range(12)]
    sweep(d, ring, circle(0.008, 5), "iron", closed=True, rng=rng)
    door = make_object("cage_door", d)
    return [wall, door]


# --- pillars -----------------------------------------------------------------------------------

def pier(acc, rng, half, bands, shade, faces=4):
    """A square pier of `bands` [(height, proud, split)] bottom up, about the y axis."""
    for f in range(faces):
        rot = Matrix.Rotation(math.pi / 2 * f, 3, "Y")
        y = 0.0
        for (h, proud, split) in bands:
            e = half + max(proud, 0.0)
            surf = Plane(rot @ Vector((-e, y, half)), rot @ Vector((1, 0, 0)), (0, 1, 0))
            cuts = [0.0, 2 * e]
            if split:
                cuts.insert(1, e + rng.uniform(-0.2, 0.2) * half * 2)
            for a, b in zip(cuts, cuts[1:]):
                stone(acc, surf, a, b, 0.0, h, rng, proud=proud, shade=shade, gap=0.01, bevel=0.03 if proud else 0.024,
                      grid=0.3, open=("u" if a == cuts[0] else "") + ("U" if b == cuts[-1] else ""))
            y += h


def pillar_bands(rng):
    shaft = courses(rng, 2.48, 0.42, 0.56)
    return [(0.36, 0.07, False)] + [(h, 0.0, rng.random() < 0.45) for h in shaft] + [(0.08, 0.035, False), (0.28, 0.09, False)]


def pillar_shade(p):
    return (0.60 + 0.40 * smooth(p.y, 0.0, 0.9)) * (1.0 - 0.18 * smooth(p.y, 2.4, 3.2))


def build_pillar(name, seed, torch=False):
    rng = random.Random(seed)
    acc = Acc()
    pier(acc, rng, PILLAR_HALF, pillar_bands(rng), pillar_shade)
    e = PILLAR_HALF + 0.09
    quad(acc, [(-e, PILLAR_HEIGHT, e), (e, PILLAR_HEIGHT, e), (e, PILLAR_HEIGHT, -e), (-e, PILLAR_HEIGHT, -e)], (0, 1, 0), "stone", 0.4, rng)
    if torch:
        torch_on(acc, rng, PILLAR_HALF)
    return [make_object(name, acc)]


def torch_on(acc, rng, face_z):
    """An iron bracket on the +Z face and a torch standing in its ring, leaning
    out, its wrapped head's top at TORCH_HEAD."""
    it = (0.9, 0.9, 0.9)
    head = TORCH_HEAD
    foot = Vector((0.0, 2.02, face_z + 0.07))
    axis = (head - foot).normalized()
    # Back plate with two studs, an arm out to the ring, a strut under it.
    ibox(acc, (-0.055, 2.10, face_z - 0.005), (0.055, 2.40, face_z + 0.018), rng, tint=it)
    for y in (2.14, 2.36):
        lathe(acc, [(0.016, 0.0), (0.014, 0.008), (0.0, 0.012)], 7, "iron",
              Matrix.Translation((0, y, face_z + 0.018)) @ Matrix.Rotation(math.pi / 2, 4, "X"), tint=it, rng=rng)
    ring_c = foot + axis * 0.33
    bar(acc, (0, 2.30, face_z + 0.01), (0, ring_c.y, ring_c.z - 0.045), 0.03, 0.014, rng, tint=it, up=(1, 0, 0))
    bar(acc, (0, 2.13, face_z + 0.01), (0, ring_c.y - 0.01, ring_c.z - 0.05), 0.022, 0.012, rng, tint=it, up=(1, 0, 0))
    side = Vector((1, 0, 0))
    other = axis.cross(side).normalized()
    ring = [ring_c + (side * math.cos(math.tau * i / 14) + other * math.sin(math.tau * i / 14)) * 0.047 for i in range(14)]
    sweep(acc, ring, rect(0.012, 0.03), "iron", closed=True, tint=it, rng=rng, ups=[axis] * 14)
    # The cup under the foot.
    xf = Matrix.Translation(foot) @ Vector((0, 1, 0)).rotation_difference(axis).to_matrix().to_4x4()
    lathe(acc, [(0.0, -0.03), (0.03, -0.03), (0.042, 0.0), (0.046, 0.05), (0.038, 0.05)], 10, "iron", xf, tint=it, rng=rng)
    # The torch: a rough stave, thicker at the head, bound with pitch-soaked cloth.
    length = (head - foot).length
    wd = (0.62, 0.5, 0.42)
    lathe(acc, [(0.0, 0.0), (0.026, 0.0), (0.03, length * 0.55), (0.034, length - 0.2)], 9, "wood", xf, tint=wd, rng=rng)
    wrap = (0.22, 0.2, 0.19)
    prof = [(0.036, length - 0.21)]
    for k in range(6):
        y = length - 0.20 + k * 0.032
        prof += [(0.052 + 0.004 * (k % 2), y), (0.05, y + 0.016), (0.046, y + 0.03)]
    prof += [(0.04, length - 0.008), (0.0, length)]
    lathe(acc, prof, 10, "wood", xf, tint=wrap, rng=rng)


# --- the arch on a cell boundary, and the door's own -------------------------------------------

def ellipse_pts(a, b, y0, n=48):
    return [(-a * math.cos(math.pi * i / n), y0 + b * math.sin(math.pi * i / n)) for i in range(n + 1)]


def arch_shade(p):
    return (0.60 + 0.40 * smooth(p.y, 0.0, 1.0)) * (1.0 - 0.28 * smooth(p.y, 3.6, 5.2))


def build_arch_like(name, seed, half, spring, head, outer, top, z0, z1, ring_w, n_vous, impost=0.18,
                    key_extra=0.14, shade=arch_shade):
    """A wall `outer` either side of the middle and `top` high, z0..z1 thick,
    with a doorway through it: jambs `half` out up to `spring`, then `head` (the
    intrados, a polyline in x, y from the left springing to the right). Dressed
    both faces, down the jambs and under the head."""
    rng = random.Random(seed)
    acc = Acc()
    # `head` is one curve (a round arch, with a keystone) or two halves meeting
    # at a point on a plumb joint: [(points, start normal, end normal), ...].
    halves = head if isinstance(head[0][0], (list, tuple)) else [(head, None, None)]
    hs = [0.44] + courses(rng, spring - 0.44 - impost, 0.32, 0.48) + [impost]
    tuck_pts = []
    bz = 0.022
    for pts, n0, n1 in halves:
        intr = Intrados(pts, n0, n1)
        # Voussoirs: under the head, and round it on both faces.
        count = n_vous // len(halves)
        step = intr.length / count
        sof = intr.soffit()
        for k in range(count):
            ua, ub = k * step, (k + 1) * step
            key = (len(halves) == 1 and k == count // 2)
            # The ring stands a little out of the wall (the spandrel's stones
            # tuck under it), the keystone further; the soffit runs out to meet it.
            pr = 0.03 + (0.03 if key else 0.0)
            if k % 2 == 0 or (z1 - z0) < 0.9:
                stone(acc, sof, ua, ub, z0 - pr, z1 + pr, rng, shade=shade, grid=0.34, open="vV", bevel=bz, gap=0.014)
            else:
                zm = (z0 + z1) / 2 + rng.uniform(-0.12, 0.12)
                stone(acc, sof, ua, ub, z0 - pr, zm, rng, shade=shade, grid=0.34, open="v", bevel=bz, gap=0.014)
                stone(acc, sof, ua, ub, zm, z1 + pr, rng, shade=shade, grid=0.34, open="V", bevel=bz, gap=0.014)
            for z, sign in ((z1, 1.0), (z0, -1.0)):
                stone(acc, intr.face(z, sign), ua, ub, 0.0, ring_w + (key_extra if key else 0.0), rng, shade=shade,
                      proud=pr, grid=0.3, gap=0.014, bevel=bz, open="v")
        # The curve the spandrel's stones are tucked under: half way through the ring.
        tuck_pts += [(p.x + n.x * ring_w * 0.5, p.y + n.y * ring_w * 0.5) for p, n in zip(intr.p, intr.n)]
    tuck = Intrados(tuck_pts)

    def tuck_y(x):
        for i in range(len(tuck.p) - 1):
            a, b = tuck.p[i], tuck.p[i + 1]
            if a.x <= x <= b.x and b.x - a.x > 1e-9:
                return a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
        return None

    def inside(x, y):
        # Under the tucking curve? (x across, y up)
        if y < spring:
            return abs(x) < half
        ty = tuck_y(x)
        return ty is not None and y < ty

    def tuck_in(x, y):
        if y < spring or not inside(x, y):
            return (x, y)
        return (x, tuck_y(x))   # straight up onto the curve
    for z, sign in ((z1, 1.0), (z0, -1.0)):
        # u runs +x on the front and -x on the back, so both read left to right.
        surf = Plane((0, 0, z), (sign, 0, 0), (0, 1, 0))
        wp = lambda u, v, s=sign: (lambda q: (q[0] * s, q[1]))(tuck_in(u * s, v))
        # Legs: quoins at the jamb, a block or two out to the edge.
        y = 0.0
        for ci, h in enumerate(hs):
            proud = 0.05 if ci == 0 else (0.05 if ci == len(hs) - 1 else 0.0)
            for s in (-1.0, 1.0):
                q = rng.uniform(0.42, 0.78)
                cuts = [half - proud, half + q] + ([half + q + (outer - half - q) * rng.uniform(0.4, 0.6)] if outer - half - q > 0.9 else []) + [outer]
                for a, b in zip(cuts, cuts[1:]):
                    lo_u, hi_u = (a, b) if s > 0 else (-b, -a)
                    arris = ("u" if s > 0 else "U") if a == cuts[0] else ""
                    stone(acc, surf, lo_u, hi_u, y, y + h, rng, proud=proud + (rng.gauss(0, 0.005) if not (proud or arris) else 0.0),
                          shade=shade, bevel=0.03 if proud else bz, open=arris)
            y += h
        # The spandrel: courses over everything, tucked under the ring.
        sp = courses(rng, top - spring, 0.36, 0.5)

        def keep(a, b, v0, v1, s=sign):
            xs = [a * s, b * s, (a + b) * 0.5 * s]
            return not all(inside(x, yy) for x in xs for yy in (v0, v1))
        lay_wall(acc, surf, rng, -outer, outer, sp, v0=spring, shade=shade, keep=keep, warp=wp, lmin=0.6, lmax=1.2)
    # Jambs: the same courses, through the thickness.
    for s in (-1.0, 1.0):
        surf = Plane((s * half, 0, 0), (0, 0, 1), (0, 1, 0))
        y = 0.0
        for ci, h in enumerate(hs):
            proud = 0.05 if ci in (0, len(hs) - 1) else 0.0
            cuts = [z0 - proud, z1 + proud]
            if ci % 2 == 1 and (z1 - z0) > 0.9:
                cuts.insert(1, (z0 + z1) / 2 + rng.uniform(-0.15, 0.15))
            for a, b in zip(cuts, cuts[1:]):
                stone(acc, surf, a, b, y, y + h, rng, proud=proud, shade=shade, bevel=0.03 if proud else bz,
                      open=("u" if a == cuts[0] else "") + ("U" if b == cuts[-1] else ""))
            y += h
    # Top and ends.
    quad(acc, [(-outer, top, z1), (outer, top, z1), (outer, top, z0), (-outer, top, z0)], (0, 1, 0), "stone", 0.35, rng)
    for s in (-1, 1):
        quad(acc, [(s * outer, 0, z1), (s * outer, top, z1), (s * outer, top, z0), (s * outer, 0, z0)], (s, 0, 0), "stone", 0.35, rng)
    return [make_object(name, acc)]


def build_arch(name="arch", seed=5501, n_vous=15, ring_w=0.44):
    return build_arch_like(name, seed, ARCH_A, ARCH_SPRING, ellipse_pts(ARCH_A, ARCH_B, ARCH_SPRING),
                           ARCH_OUTER, ARCH_TOP, -ARCH_Z, ARCH_Z, ring_w, n_vous)


def build_door_arch():
    left = ([(-x, y) for x, y in DOOR_HEAD], (-1, 0), (0, 1))
    right = ([(x, y) for x, y in reversed(DOOR_HEAD)], (0, 1), (1, 0))
    return build_arch_like("door_arch", 5602, DOOR_HEAD[0][0], DOOR_HEAD[0][1], [left, right], DOOR_OUTER, DOOR_TOP,
                           DOOR_Z[0], DOOR_Z[1], 0.36, 10, impost=0.16)


# --- vaults --------------------------------------------------------------------------------------

def vault_shade(p):
    return 0.80 - 0.22 * smooth(p.y, 3.2, 5.0)


def barrel(name, seed, hole=None, ridge=True):
    """The pointed barrel over one cell, along Godot z: an impost band on each
    wall, eight courses a side with broken joints, a ridge rib. `hole` (x half,
    z half) leaves the skylight's shaft open at the crown."""
    rng = random.Random(seed)
    acc = Acc()
    surf = Barrel()
    L = VAULT_L
    band = 0.2
    hs = [band] + courses(rng, L - band, 0.34, 0.42)
    cut = None
    if hole:
        # The hole in the surface's own metres: across the crown, along the corridor.
        a = math.acos((hole[0] + VAULT_C) / VAULT_R)   # angle of the hole's edge on its arc
        du = L - VAULT_R * a
        cut = (L - du, L + du, -hole[1], hole[1])

    def emit(u0, u1, v0, v1, proud):
        rects = [(u0, u1, v0, v1)]
        if cut and u1 > cut[0] and u0 < cut[1] and v1 > cut[2] and v0 < cut[3]:
            rects = []
            if u0 < cut[0]:
                rects.append((u0, cut[0], v0, v1))
            if u1 > cut[1]:
                rects.append((cut[1], u1, v0, v1))
            ua, ub = max(u0, cut[0]), min(u1, cut[1])
            if v0 < cut[2]:
                rects.append((ua, ub, v0, cut[2]))
            if v1 > cut[3]:
                rects.append((ua, ub, cut[3], v1))
        for r in rects:
            stone(acc, surf, r[0], r[1], r[2], r[3], rng, proud=proud + (rng.gauss(0, 0.005) if not proud else 0.0),
                  shade=vault_shade, grid=0.42, bevel=0.03 if proud else None, bulge=0.0, depth=0.05)
    for side in (0, 1):
        u = 0.0
        prev = []
        for ci, h in enumerate(hs):
            segs = lay(rng, -VAULT_HALF, VAULT_HALF, 0.6, 1.2, prev)
            prev = [b for _, b in segs[:-1]]
            for (a, b) in segs:
                if side == 0:
                    emit(u, u + h, a, b, 0.07 if ci == 0 else 0.0)
                else:
                    emit(2 * L - u - h, 2 * L - u, a, b, 0.07 if ci == 0 else 0.0)
            u += h
    if ridge:
        spans = [(-VAULT_HALF, VAULT_HALF)]
        if hole:
            spans = [(-VAULT_HALF, -hole[1]), (hole[1], VAULT_HALF)]
        for z0, z1 in spans:
            n = max(2, int((z1 - z0) / 0.25) + 1)
            path = [Vector((0, CROWN - 0.005, z0 + (z1 - z0) * i / (n - 1))) for i in range(n)]
            joints = [0.7 * k + rng.uniform(-0.1, 0.1) for k in range(1, 9)]
            sweep(acc, path, [(-0.085, 0.03), (-0.085, -0.02), (-0.045, -0.075), (0.045, -0.075), (0.085, -0.02), (0.085, 0.03)],
                  "stone", col=0.66, rng=rng, joints=joints, caps=False)
    return acc


def groin_rib(acc, rng, angle, t0, t1, n=14):
    """A moulded rib under a groin: along the diagonal at `angle` (degrees, in
    plan from +x towards -z, Godot) from t0 to t1 metres from the middle."""
    a = math.radians(angle)
    dirv = Vector((math.cos(a), 0.0, -math.sin(a)))
    side = Vector((dirv.z, 0.0, -dirv.x))
    path = []
    ups = []
    for i in range(n + 1):
        t = t0 + (t1 - t0) * i / n
        x = abs(t) / math.sqrt(2.0)
        y = vault_y(min(x, WALL_FACE - 1e-4))
        path.append(dirv * t + Vector((0, y + 0.03, 0)))
    for i in range(n + 1):
        tan = (path[min(i + 1, n)] - path[max(i - 1, 0)]).normalized()
        ups.append(side.cross(tan).normalized() if side.cross(tan).y > 0 else tan.cross(side).normalized())
    prof = [(-0.11, 0.0), (-0.11, -0.07), (-0.075, -0.10), (-0.055, -0.17), (0.0, -0.205), (0.055, -0.17), (0.075, -0.10),
            (0.11, -0.07), (0.11, 0.0)]
    total = sum((b - a_).length for a_, b in zip(path, path[1:]))
    joints = [k * total / 6.0 for k in range(1, 6)]
    sweep(acc, path, prof, "stone", ups=ups, col=0.7, rng=rng, joints=joints, caps=True)


def boss(acc, rng):
    """The carved boss where the ribs cross."""
    xf = Matrix.Translation((0, CROWN + 0.04, 0)) @ Matrix.Rotation(math.pi, 4, "X")
    lathe(acc, [(0.27, 0.0), (0.27, 0.11), (0.23, 0.16), (0.16, 0.18), (0.15, 0.235), (0.08, 0.27), (0.0, 0.28)], 14, "stone",
          xf, col=0.7, rng=rng)


TRI = {
    "N": [((0, 0, 0), (-1, 1, 0)), ((0, 0, 0), (1, 1, 0))],
    "S": [((0, 0, 0), (1, -1, 0)), ((0, 0, 0), (-1, -1, 0))],
    "E": [((0, 0, 0), (1, 1, 0)), ((0, 0, 0), (1, -1, 0))],
    "W": [((0, 0, 0), (-1, -1, 0)), ((0, 0, 0), (-1, 1, 0))],
}
HALF = {"NW": [((0, 0, 0), (-1, 1, 0))], "SE": [((0, 0, 0), (1, -1, 0))]}


def clip(ob, co, no):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(co), plane_no=Vector(no).normalized(), clear_inner=True, dist=1e-5)
    bm.to_mesh(ob.data)
    bm.free()


def join(obs, name):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def build_vaults():
    out = []
    out.append(make_object("vault_straight", barrel("vault_straight", 6101)))
    out.append(make_object("vault_b", barrel("vault_b", 6102)))
    out.append(make_object("vault_sky", barrel("vault_sky", 6103, hole=(0.6, 1.3))))
    # The junctions: in Blender's frame (+y north), the N-S barrel over some of the
    # cell's plan and the E-W one over the rest, as build_brick_kit.py cut them.
    plans = {
        "vault_cross": ([("N", "NS"), ("S", "NS"), ("E", "EW"), ("W", "EW")], [45, 135, 225, 315]),
        "vault_tee": ([("NW", "NS"), ("S", "NS"), ("E", "EW")], [45, 135, 225, 315]),
        "vault_corner": ([("NW", "NS"), ("SE", "EW")], [45, 225]),
    }
    for k, (name, (plan, ribs)) in enumerate(plans.items()):
        parts = []
        for j, (region, axis) in enumerate(plan):
            ob = make_object("%s_%d" % (name, j), barrel(name, 6200 + k * 10 + j, ridge=False), smooth_normals=False)
            if axis == "EW":
                ob.data.transform(Matrix.Rotation(math.radians(90.0), 4, "Z"))
            for co, no in TRI.get(region, HALF.get(region)):
                clip(ob, co, no)
            parts.append(ob)
        racc = Acc()
        rng = random.Random(6300 + k)
        end = WALL_FACE * math.sqrt(2.0) - 0.02
        for ang in ribs:
            groin_rib(racc, rng, ang, 0.2, end)
        boss(racc, rng)
        parts.append(make_object(name + "_ribs", racc, smooth_normals=False))
        ob = join(parts, name)
        shade_by_angle(ob, 50.0)
        out.append(ob)
    return out


def shade_by_angle(ob, deg):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(deg))
    except Exception as ex:  # noqa: BLE001
        log("smooth by angle failed on", ob.name, ex)


# --- floors ----------------------------------------------------------------------------------------

def split_rects(rng, x0, x1, z0, z1, lo, hi, out):
    w, d = x1 - x0, z1 - z0
    if (w <= hi and d <= hi and rng.random() < 0.75) or (w < lo * 2 and d < lo * 2):
        out.append((x0, x1, z0, z1))
        return
    if (w > d and w >= lo * 2) or d < lo * 2:
        c = x0 + w * rng.uniform(0.35, 0.65)
        c = min(max(c, x0 + lo), x1 - lo)
        split_rects(rng, x0, c, z0, z1, lo, hi, out)
        split_rects(rng, c, x1, z0, z1, lo, hi, out)
    else:
        c = z0 + d * rng.uniform(0.35, 0.65)
        c = min(max(c, z0 + lo), z1 - lo)
        split_rects(rng, x0, x1, z0, c, lo, hi, out)
        split_rects(rng, x0, x1, c, z1, lo, hi, out)


def build_floor(name, seed, notch=False, broken=False):
    """A 3 m tile of flagstones, their tops about y 0. `notch`: half the manhole's
    round hole bitten out of the +X edge, a curb of small stones round it."""
    rng = random.Random(seed)
    acc = Acc()
    half = FLOOR_TILE * 0.5
    # u = x, v = -z: u x v is up.
    surf = Plane((0, 0, 0), (1, 0, 0), (0, 0, -1))
    rects = []
    split_rects(rng, -half, half, -half, half, 0.42, 1.25, rects)
    centre = Vector((half, 0.0))
    r_tuck = MANHOLE_R + 0.15

    def warp(u, v):
        d = Vector((u, v)) - centre
        if d.length < r_tuck:
            d = d.normalized() * r_tuck if d.length > 1e-6 else Vector((-r_tuck, 0))
            return (min(centre.x + d.x, half), centre.y + d.y)
        return (u, v)
    shade = lambda p: 0.8
    for i, (x0, x1, z0, z1) in enumerate(rects):
        if notch:
            corners = [Vector((x, z)) for x in (x0, x1) for z in (z0, z1)]
            if all((c - centre).length < r_tuck for c in corners):
                continue
        near = notch and (Vector((min(max(centre.x, x0), x1), min(max(centre.y, z0), z1))) - centre).length < r_tuck
        if broken and i % 5 == 2:
            # A flag broken into pieces that have settled.
            sub = []
            split_rects(rng, x0, x1, z0, z1, 0.16, 0.42, sub)
            for (a0, a1, b0, b1) in sub:
                stone(acc, surf, a0, a1, b0, b1, rng, gap=0.03, depth=0.04, proud=rng.gauss(-0.008, 0.008), rough=0.004,
                      bulge=0.0, grid=0.5, chip=0.7, shade=shade)
            continue
        stone(acc, surf, x0, x1, z0, z1, rng, gap=0.022, depth=0.04, proud=rng.gauss(0.0, 0.004), rough=0.003,
              bulge=0.0, grid=0.16 if near else 0.5, chip=0.3, bevel=rng.uniform(0.012, 0.022), shade=shade,
              warp=warp if near else None, joint=0.3)
    if notch:
        # The curb: half a ring of small stones, and the shaft's lip under them.
        pol = Polar((half, 0, 0), MANHOLE_R, math.pi / 2)
        arc = math.pi * MANHOLE_R
        n = 7
        for k in range(n):
            stone(acc, pol, arc * k / n, arc * (k + 1) / n, 0.0, 0.17, rng, gap=0.014, depth=0.04, proud=0.012,
                  grid=0.2, shade=shade, bevel=0.016)
        m = 12
        for k in range(m):
            a0 = math.pi / 2 + math.pi * k / m
            a1 = math.pi / 2 + math.pi * (k + 1) / m
            p = [Vector((half + MANHOLE_R * math.cos(a), y, -MANHOLE_R * math.sin(a))) for a, y in
                 ((a0, 0.0), (a1, 0.0), (a1, -0.4), (a0, -0.4))]
            c = sum(p, Vector()) / 4
            quad(acc, p, Vector((half, c.y, 0)) - c, "stone", 0.4, rng)
    return [make_object(name, acc)]


# --- timber ------------------------------------------------------------------------------------------

def spike(acc, at, normal, rng, r=0.016):
    n = Vector(normal).normalized()
    xf = Matrix.Translation(Vector(at)) @ Vector((0, 1, 0)).rotation_difference(n).to_matrix().to_4x4()
    lathe(acc, [(r, -0.004), (r, 0.004), (r * 0.6, 0.012), (0.0, 0.015)], 6, "iron", xf, rng=rng)


def build_wood_support():
    """Shoring against a wall (its back on z 0, the corridor +Z): two posts at
    x +-1.15, a head beam on them, knee braces, a raking shore, a rail broken
    off short. brick_level.place_clutter boxes the posts."""
    rng = random.Random(8101)
    acc = Acc()
    top = 2.22
    for s in (-1.0, 1.0):
        lean = rng.uniform(-0.03, 0.03)
        beam(acc, (s * 1.15 + lean, 0.0, 0.2), (s * 1.15, top, 0.16), 0.2, 0.19, rng, up=(0, 0, 1))
        # A stone pad under the post.
        stone_box(acc, (s * 1.15 - 0.2, 0.0, 0.03), (s * 1.15 + 0.2, 0.07, 0.4), rng, faces="xXYZ", shade=lambda p: 0.7)
        beam(acc, (s * 1.12, 1.45, 0.17), (s * 0.5, top - 0.03, 0.15), 0.12, 0.11, rng, up=(0, 0, 1))
        for y in (1.5, top - 0.1):
            spike(acc, (s * (1.1 if y < 2 else 0.56), y, 0.23), (0, 0, 1), rng)
    beam(acc, (-1.38, top + 0.09, 0.16), (1.38, top + 0.09, 0.17), 0.22, 0.18, rng, up=(0, 1, 0))
    # The raking shore, footed on a block out in the corridor.
    beam(acc, (0.28, 0.06, 0.66), (0.18, top - 0.02, 0.3), 0.16, 0.15, rng, up=(0, 0, 1))
    stone_box(acc, (0.06, 0.0, 0.5), (0.5, 0.1, 0.74), rng, faces="xXYZz", shade=lambda p: 0.7)
    # A rail nailed across, snapped off.
    beam(acc, (-1.2, 1.02, 0.28), (0.34, 1.08, 0.275), 0.04, 0.17, rng, up=(0, 1, 0), chamfer=0.006, wobble=0.004)
    beam(acc, (-1.25, 0.52, 0.275), (1.25, 0.47, 0.28), 0.04, 0.15, rng, up=(0, 1, 0), chamfer=0.006, wobble=0.004)
    for x in (-1.15, 1.15):
        spike(acc, (x, 0.5, 0.3), (0, 0, 1), rng, 0.012)
    spike(acc, (-1.15, 1.03, 0.3), (0, 0, 1), rng, 0.012)
    # Two iron straps binding the head beam to the posts.
    for s in (-1.0, 1.0):
        ibox(acc, (s * 1.15 - 0.03, top - 0.22, 0.255), (s * 1.15 + 0.03, top + 0.2, 0.27), rng)
    ob = make_object("wood_support", acc, smooth_normals=False)
    shade_by_angle(ob, 40.0)
    return [ob]


def build_wood_planks():
    """A heap of fallen boards on the floor, some snapped."""
    rng = random.Random(8202)
    acc = Acc()
    y = 0.02
    for k in range(9):
        a = rng.uniform(0, math.pi)
        length = rng.uniform(0.7, 1.45)
        c = Vector((rng.uniform(-0.18, 0.18), y, rng.uniform(-0.18, 0.18)))
        d = Vector((math.cos(a), rng.uniform(-0.06, 0.1), math.sin(a))).normalized() * length * 0.5
        beam(acc, c - d, c + d, rng.uniform(0.14, 0.2), 0.032, rng, up=(rng.uniform(-0.2, 0.2), 1, rng.uniform(-0.2, 0.2)),
             chamfer=0.005, wobble=0.006, seg=0.4)
        y += rng.uniform(0.022, 0.04)
    beam(acc, (-0.5, 0.05, 0.42), (0.45, 0.24, -0.3), 0.13, 0.12, rng)
    ob = make_object("wood_planks", acc, smooth_normals=False)
    shade_by_angle(ob, 40.0)
    return [ob]


def build_tie_beam():
    """Timber holding a tired vault up, all of it over head height: a tie beam
    across the corridor on two stone corbels, a king post up to the crown and a
    strut to each haunch, strapped with iron, a hook hanging from the middle.
    In the vault's frame (the corridor along z), at z 0."""
    rng = random.Random(8303)
    acc = Acc()
    y = SPRING + 0.07
    sh = lambda p: 0.8
    for s in (-1.0, 1.0):
        stone_box(acc, (s * 1.93 - 0.17, y - 0.42, -0.16), (s * 1.93 + 0.17, y - 0.12, 0.16), rng, faces="xXyzZ", shade=sh, bevel=0.03)
        stone_box(acc, (s * 1.93 - 0.11, y - 0.62, -0.12), (s * 1.93 + 0.11, y - 0.42, 0.12), rng, faces="xXyzZ", shade=sh, bevel=0.03)
    beam(acc, (-1.94, y, 0.0), (1.94, y + 0.015, 0.0), 0.22, 0.24, rng, up=(0, 1, 0), wobble=0.01)
    top = vault_y(0.0) - 0.03
    beam(acc, (0.0, y + 0.1, 0.0), (0.0, top, 0.0), 0.17, 0.17, rng, up=(0, 0, 1), wobble=0.006)
    for s in (-1.0, 1.0):
        x = 1.32
        beam(acc, (s * 0.2, y + 0.16, 0.0), (s * x, vault_y(x) - 0.05, 0.0), 0.14, 0.14, rng, up=(0, 0, 1), wobble=0.008)
        # A wedge driven in at the strut's head, and the straps.
        ibox(acc, (s * 0.86 - 0.02, y - 0.14, -0.125), (s * 0.86 + 0.02, y + 0.15, 0.125), rng)
        spike(acc, (s * 0.86, y + 0.02, 0.125), (0, 0, 1), rng, 0.014)
    ibox(acc, (-0.11, y - 0.135, -0.126), (0.11, y - 0.12, 0.126), rng)
    for z in (-0.126, 0.112):
        ibox(acc, (-0.11, y - 0.135, z), (0.11, y + 0.3, z + 0.014), rng)
    # The hook.
    bar(acc, (0.5, y - 0.12, 0.0), (0.5, y - 0.42, 0.0), 0.022, 0.022, rng)
    hook = [Vector((0.5 + 0.05 - 0.05 * math.cos(a), y - 0.42 - 0.05 * math.sin(a), 0.0)) for a in [math.pi * i / 6 for i in range(6)]]
    sweep(acc, hook, rect(0.02, 0.02), "iron", rng=rng, ups=[(0, 0, 1)] * 6)
    ob = make_object("tie_beam", acc, smooth_normals=False)
    shade_by_angle(ob, 40.0)
    return [ob]


def build_portcullis():
    """A portcullis hauled up into an arch and left there: its lowest bars and
    their spikes hang in the head of the opening, clear of anyone walking under
    (nothing below 3.15 m). In the arch's frame, in the middle of its depth."""
    rng = random.Random(8404)
    acc = Acc()
    bot = 3.3
    it = (0.9, 0.9, 0.9)

    def head(x):
        return ARCH_SPRING + ARCH_B * math.sqrt(max(1.0 - (x / ARCH_A) ** 2, 0.0))

    def reach(yy):
        return ARCH_A * math.sqrt(max(1.0 - ((yy - ARCH_SPRING) / ARCH_B) ** 2, 0.0))
    n = 11
    for k in range(n):
        x = -1.5 + 3.0 * k / (n - 1)
        top = head(x) + 0.03
        if top - bot < 0.2:
            continue
        bar(acc, (x, bot, 0.0), (x, top, 0.0), 0.05, 0.05, rng, tint=it)
        xf = Matrix.Translation((x, bot, 0.0)) @ Matrix.Rotation(math.pi, 4, "X") @ Matrix.Rotation(math.pi / 4, 4, "Y")
        lathe(acc, [(0.036, 0.0), (0.03, 0.03), (0.0, 0.17)], 4, "iron", xf, tint=it, rng=rng)
    for yy in (bot + 0.08, bot + 0.5, bot + 0.92):
        r = reach(yy) + 0.04 if yy > ARCH_SPRING else ARCH_A + 0.04
        bar(acc, (-r, yy, 0.0), (r, yy, 0.0), 0.075, 0.02, rng, tint=it, up=(0, 0, 1))
        for k in range(n):
            x = -1.5 + 3.0 * k / (n - 1)
            if abs(x) < r - 0.05 and head(x) + 0.03 - bot >= 0.2:
                for z in (0.012, -0.012):
                    spike(acc, (x, yy, z), (0, 0, 1 if z > 0 else -1), rng, 0.016)
    ob = make_object("portcullis_up", acc, smooth_normals=False)
    shade_by_angle(ob, 35.0)
    return [ob]


# --- rubble ------------------------------------------------------------------------------------------

def build_rubble(name, seed, spread, count, blocks):
    """Fallen stone on the floor: lumps heaped against z 0 side (a wall's foot)
    when `spread` z is small; `blocks` dressed stones among them."""
    rng = random.Random(seed)
    acc = Acc()
    sh = lambda p: 0.55 + 0.4 * smooth(p.y, 0.0, 0.35)
    for k in range(count):
        t = k / max(count - 1, 1)
        s = 0.42 - 0.3 * t
        size = (s * rng.uniform(0.7, 1.3), s * rng.uniform(0.5, 0.9), s * rng.uniform(0.7, 1.3))
        x = rng.gauss(0, spread[0] * (0.35 + 0.5 * t))
        z = abs(rng.gauss(0, spread[1] * (0.35 + 0.5 * t)))
        heap = max(0.0, 0.22 - 0.25 * math.hypot(x / spread[0], z / spread[1])) * (1.0 - t)
        rock(acc, (x, size[1] * 0.42 + heap, z + size[2] * 0.3), size, rng, shade=sh, points=14 if s > 0.2 else 9)
    for k in range(blocks):
        w, h, d = rng.uniform(0.4, 0.62), rng.uniform(0.24, 0.34), rng.uniform(0.26, 0.36)
        c = Vector((rng.uniform(-spread[0], spread[0]) * 0.8, h * 0.5 + rng.uniform(0.0, 0.1), spread[1] * rng.uniform(0.5, 1.0)))
        rot = Matrix.Rotation(rng.uniform(0, math.tau), 3, "Y") @ Matrix.Rotation(rng.uniform(-0.35, 0.35), 3, "X") \
            @ Matrix.Rotation(rng.uniform(-0.3, 0.3), 3, "Z")
        stone_box(acc, c - Vector((w, h, d)) / 2, c + Vector((w, h, d)) / 2, rng, rot=rot, shade=sh, chip=0.8, rough=0.01)
    ob = make_object(name, acc, smooth_normals=False)
    shade_by_angle(ob, 42.0)
    return [ob]


def build_column_broken():
    """A round column snapped off: a square base, three drums standing, the next
    drum lying by it."""
    rng = random.Random(9303)
    acc = Acc()
    sh = lambda p: 0.6 + 0.4 * smooth(p.y, 0.0, 0.8)
    stone_box(acc, (-0.42, 0.0, -0.42), (0.42, 0.22, 0.42), rng, faces="xXYzZ", shade=sh, grid=0.3)
    r = 0.29
    per = math.tau * r
    y = 0.22
    for k, h in enumerate((0.16, 0.62, 0.55)):
        rr = r + (0.06 if k == 0 else 0.0)
        dr = Drum((0, 0, 0), rr)
        n = 3
        off = rng.uniform(0, 1)
        tn = stone_tint(rng)
        for i in range(n):
            stone(acc, dr, math.tau * rr * (i + off) / n, math.tau * rr * (i + 1 + off) / n, y, y + h, rng, gap=0.012,
                  grid=0.1, bulge=0.0, shade=sh, depth=0.03, chip=0.0, back=False, open="uU", bevel=0.004, tint=tn,
                  rough=0.008)
        y += h
    # The broken top: a ragged cap.
    rock(acc, (0.0, y - 0.02, 0.0), (r * 2.0, 0.2, r * 2.0), rng, shade=lambda p: 0.75, points=22)
    # The fallen drum.
    rot = Matrix.Rotation(math.radians(86), 3, "Z") @ Matrix.Rotation(0.5, 3, "Y")
    c = Vector((0.82, r * 0.98, 0.35))
    dr = Drum(c, r, rot)
    tn = stone_tint(rng)
    for i in range(3):
        stone(acc, dr, per * i / 3, per * (i + 1) / 3, -0.3, 0.3, rng, gap=0.0, grid=0.1, bulge=0.0, shade=lambda p: 0.8,
              depth=0.03, chip=0.0, back=False, open="uUvV", bevel=0.004, tint=tn, rough=0.008)
    for s in (-1.0, 1.0):
        ring = [c + rot @ Vector((r * 0.97 * math.sin(math.tau * i / 10), s * 0.3, r * 0.97 * math.cos(math.tau * i / 10))) for i in range(10)]
        mid = c + rot @ Vector((0, s * 0.31, 0))
        for i in range(10):
            pts = [mid, ring[i], ring[(i + 1) % 10]]
            n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
            if n.dot(rot @ Vector((0, s, 0))) < 0:
                pts.reverse()
            acc.face([acc.vert(p) for p in pts], [(0.5, 0.5), (0.5 + 0.1 * math.cos(i), 0.5 + 0.1 * math.sin(i)),
                                                  (0.5 + 0.1 * math.cos(i + 1), 0.5 + 0.1 * math.sin(i + 1))],
                     [(0.6, 0.6, 0.6)] * 3, "stone")
    ob = make_object("column_broken", acc, smooth_normals=False)
    shade_by_angle(ob, 48.0)
    return [ob]


# --- the build ----------------------------------------------------------------------------------------

BUILDERS = [
    ("wall", lambda: build_wall("wall", 1101)),
    ("wall_b", lambda: build_wall("wall_b", 1202)),
    ("wall_c", lambda: build_wall("wall_c", 1303)),
    ("wall_broken", lambda: build_wall("wall_broken", 1404, broken=True)),
    ("wall_broken_b", lambda: build_wall("wall_broken_b", 1505, broken=True)),
    ("wall_top", build_wall_top),
    ("wall_cage", build_wall_cage),
    ("pier_face", build_pier_face),
    ("pillar", lambda: build_pillar("pillar", 2101)),
    ("pillar_torch", lambda: build_pillar("pillar_torch", 2202, torch=True)),
    ("arch", build_arch),
    ("door_arch", build_door_arch),
    ("vault", build_vaults),
    ("floor", lambda: build_floor("floor", 3101)),
    ("floor_b", lambda: build_floor("floor_b", 3202)),
    ("floor_c", lambda: build_floor("floor_c", 3303, broken=True)),
    ("floor_notch", lambda: build_floor("floor_notch", 3404, notch=True)),
    ("wood_support", build_wood_support),
    ("wood_planks", build_wood_planks),
    ("rubble_a", lambda: build_rubble("rubble_a", 9101, (0.7, 0.4), 16, 1)),
    ("rubble_b", lambda: build_rubble("rubble_b", 9202, (0.45, 0.45), 11, 2)),
    ("rubble_c", lambda: build_rubble("rubble_c", 9404, (0.85, 0.5), 20, 4)),
    ("tie_beam", build_tie_beam),
    ("portcullis_up", build_portcullis),
    ("arch_b", lambda: build_arch("arch_b", 5707, 13, 0.52)),
    ("column_broken", build_column_broken),
]


def main():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    os.makedirs(OUT_DIR, exist_ok=True)
    built = []
    for key, fn in BUILDERS:
        if ONLY and key not in ONLY:
            continue
        built += fn()
    total = 0
    for ob in built:
        ob.data.name = ob.name
        report(ob)
        total += tri_count(ob)
    log("total %d triangles in %d pieces" % (total, len(built)))
    if PREVIEW:
        import importlib.util
        spec = importlib.util.spec_from_file_location("dk_preview", os.path.join(os.path.dirname(__file__), "dungeon_kit_preview.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        mod.render(built, PREVIEW, sys.modules[__name__])
        return
    for o in bpy.context.scene.objects:
        o.select_set(o in built)
    bpy.ops.export_scene.gltf(
        filepath=OUT, export_format="GLB", use_selection=True, export_animations=False,
        export_image_format="NONE", export_yup=True, export_apply=True,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_tangents=False,
    )
    log("wrote", OUT, os.path.getsize(OUT))


if __name__ == "__main__":
    main()
