"""The holding cells' kit (note 177), modelled in Blender from nothing and baked PBR.

    blender -b --python tools/build_cell_kit.py

Writes models/cell_kit.glb: one object per piece, all on ONE material whose
textures are baked here into a shared atlas (albedo 4096, normal 4096, ORM 2048:
R occlusion, G roughness, B metal), plus `lantern_glass` (Godot gives it its own
glass material). Pieces, in Godot's frame (y up), with their origins:

  gate_l, gate_r   the cell's two leaves of rusted bars, origin on the hinge, the
                   left leaf running +X from it (the right one -X), front +Z.
                   They fit the brick arch (3.28 wide, apex 4.74, springing at
                   3.3), as the Tripo gate did. Where they meet, the big bronze
                   gear lock: a gear wheel behind radial straps, a small brass
                   gear, and a brass piston on the right leaf throwing the bolt.
                   (No door at the back: the user wants none there.)
  lantern          a caged brass lantern; origin at its hook, hanging down -Y;
                   the flame sits at y -0.30.
  lantern_glass    its glass.
  lantern_chain    0.5 m of chain hanging down -Y from its origin.
  wall_chains      two eye plates, a chain slung between them, two hanging
                   chains ending in open manacles. Wall piece: x along the wall,
                   back on z 0, the room +Z.
  bench            a chipped wet stone bench (1.2 long, 0.5 deep, top at 0.48) with a frayed
                   burlap cloth draped over it by a cloth simulation. Wall piece.
  shelf            a stone shelf on two corbels at 1.15-1.21 m, a pewter bowl and
                   a tin cup on it. Wall piece.
  drain            a square iron grate in a stone frame over a black pit. Floor
                   piece, origin on the floor.
  straw_tuft       a flattened clump of straw, origin on the floor.

Everything is built in Godot's frame and turned into Blender's at the end of each
piece (x, y, z) -> (x, -z, y). Materials are procedural Cycles node trees, one
per kind (rust, bronze, brass, stone, burlap, pewter, straw, pit), baked into the
one atlas: colour, roughness and metal as emission (a metal's diffuse colour
bakes black), the normal from each kind's bump, the occlusion from the geometry
with a stand-in wall and floor behind each piece. Pieces are spread apart while
baking so none shades another.
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
OUT = os.path.join(ROOT, "models", "cell_kit.glb")
ATLAS = 4096
ORM_TEX = 2048
MARGIN = 8
PREVIEW = "--preview" in sys.argv
# Each piece's share of the atlas against even texel density (see the UV step).
UV_SHARE = {"gate_l": 0.55, "gate_r": 0.55, "lantern_chain": 0.6, "bench": 1.5, "shelf": 1.5, "drain": 1.2}

random.seed(0x63656c6c)

# Godot -> Blender.
G2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))

# The brick arch's opening, as build_brick_kit.py fitted the Tripo gate to it.
GATE_HALF = 1.64
GATE_SPRING = 3.3
GATE_APEX = 4.74



def log(*a):
    print("[cell_kit]", *a, flush=True)


# --- geometry accumulator (Godot frame) -------------------------------------------

class Acc:
    def __init__(self):
        self.v = []
        self.f = []
        self.m = []
        self.mats = []

    def mat(self, kind):
        if kind not in self.mats:
            self.mats.append(kind)
        return self.mats.index(kind)

    def add_v(self, p):
        self.v.append(Vector(p))
        return len(self.v) - 1

    def face(self, idx, kind):
        self.f.append(list(idx))
        self.m.append(self.mat(kind))


def frames_along(path, closed):
    """Parallel-transported (tangent, normal, binormal) along a polyline."""
    n = len(path)
    tangents = []
    for i in range(n):
        if closed:
            t = path[(i + 1) % n] - path[(i - 1) % n]
        elif i == 0:
            t = path[1] - path[0]
        elif i == n - 1:
            t = path[-1] - path[-2]
        else:
            t = path[i + 1] - path[i - 1]
        tangents.append(t.normalized())
    up = Vector((0, 1, 0)) if abs(tangents[0].y) < 0.9 else Vector((1, 0, 0))
    nrm = tangents[0].cross(up).normalized()
    out = []
    for i in range(n):
        t = tangents[i]
        if i > 0:
            nrm = nrm - t * nrm.dot(t)
            if nrm.length < 1e-6:
                nrm = t.orthogonal()
            nrm.normalize()
        out.append((t, nrm, t.cross(nrm)))
    return out


def sweep(acc, path, profile, kind, closed=False, caps=True, twist=0.0, frames=None):
    """A 2D profile (list of (a, b), counter-clockwise) swept along a 3D path."""
    path = [Vector(p) for p in path]
    fr = frames or frames_along(path, closed)
    rings = []
    for i, p in enumerate(path):
        t, nrm, bi = fr[i]
        ang = twist * i
        c, s = math.cos(ang), math.sin(ang)
        n2 = nrm * c + bi * s
        b2 = bi * c - nrm * s
        rings.append([acc.add_v(p + n2 * a + b2 * b) for a, b in profile])
    k = len(profile)
    segs = len(path) if closed else len(path) - 1
    for i in range(segs):
        r0, r1 = rings[i], rings[(i + 1) % len(path)]
        for j in range(k):
            acc.face((r0[j], r0[(j + 1) % k], r1[(j + 1) % k], r1[j]), kind)
    if caps and not closed:
        acc.face(list(reversed(rings[0])), kind)
        acc.face(rings[-1], kind)


def circle(r, n, phase=0.0):
    return [(r * math.cos(phase + 2 * math.pi * i / n), r * math.sin(phase + 2 * math.pi * i / n)) for i in range(n)]


def rect(w, h):
    return [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]


def lathe(acc, prof, segs, kind, xf=Matrix.Identity(4)):
    """Revolves (r, y) points round the local Y axis. r == 0 closes to a point."""
    rings = []
    for r, y in prof:
        if r < 1e-6:
            rings.append([acc.add_v(xf @ Vector((0, y, 0)))])
        else:
            rings.append([acc.add_v(xf @ Vector((r * math.cos(2 * math.pi * i / segs), y,
                                                   -r * math.sin(2 * math.pi * i / segs))))
                          for i in range(segs)])
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1:
            for i in range(segs):
                acc.face((a[0], b[(i + 1) % segs], b[i]), kind)
        elif len(b) == 1:
            for i in range(segs):
                acc.face((a[i], a[(i + 1) % segs], b[0]), kind)
        else:
            for i in range(segs):
                acc.face((a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i]), kind)


def box(acc, centre, size, kind, rot=Matrix.Identity(3)):
    c = Vector(centre)
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    corners = [Vector((x, y, z)) for x in (-hx, hx) for y in (-hy, hy) for z in (-hz, hz)]
    idx = [acc.add_v(c + rot @ p) for p in corners]
    # index = xi*4 + yi*2 + zi
    for quad in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        acc.face([idx[q] for q in quad], kind)


def cyl(acc, a, b, r, n, kind, caps=True):
    sweep(acc, [a, b], circle(r, n), kind, caps=caps)


def rivet(acc, at, normal, r, kind, segs=7):
    n = Vector(normal).normalized()
    xf = Matrix.Translation(Vector(at)) @ Vector((0, 1, 0)).rotation_difference(n).to_matrix().to_4x4()
    lathe(acc, [(r, -0.004), (r, 0.0), (r * 0.85, r * 0.45), (r * 0.45, r * 0.8), (0.0, r * 0.9)], segs, kind, xf)


def link(acc, centre, along, spin, length, width, wire, kind, loop_n=12, prof_n=5):
    """One chain link: a stadium loop of wire, its long axis on `along`, turned
    `spin` about it."""
    along = Vector(along).normalized()
    side = along.orthogonal().normalized()
    side = Matrix.Rotation(spin, 3, along) @ side
    half = (length - width) / 2 - 0.0
    rad = (width - wire * 2) / 2 + wire
    rad = width / 2 - wire
    pts = []
    for i in range(loop_n):
        a = 2 * math.pi * i / loop_n
        x = math.cos(a) * rad
        y = math.sin(a) * rad
        y += half * (1 if y > 0 else -1) if abs(math.sin(a)) > 1e-6 else 0.0
        pts.append(Vector(centre) + side * x + along * y)
    sweep(acc, pts, circle(wire, prof_n), kind, closed=True)


def chain(acc, path_pts, kind, length, width, wire, loop_n=12, prof_n=5, start_spin=0.0):
    """Links along a polyline, each pitched (length - 2 wire) on from the last,
    turned 90 degrees from its neighbour."""
    path = [Vector(p) for p in path_pts]
    seg_len = [(b - a).length for a, b in zip(path, path[1:])]
    total = sum(seg_len)
    pitch = length - wire * 2.2
    count = max(1, int(total / pitch))

    def at(s):
        for i, l in enumerate(seg_len):
            if s <= l or i == len(seg_len) - 1:
                return path[i].lerp(path[i + 1], min(s / l, 1.0) if l > 0 else 0.0), (path[i + 1] - path[i]).normalized()
            s -= l

    for i in range(count):
        s = (i + 0.5) * pitch
        p, d = at(s)
        jitter = random.uniform(-0.12, 0.12)
        link(acc, p, d, start_spin + (math.pi / 2) * (i % 2) + jitter, length, width, wire, kind, loop_n, prof_n)
    return count


def stone_block(acc, centre, size, kind, cuts=6, chip=0.012, seed=0.0, taper=None):
    """A box subdivided into a grid on each face and pushed in by noise, more at
    its edges and corners: chipped stone. `taper` (fz_top, fz_bottom) scales the
    z extent of the top and bottom faces (a corbel)."""
    c = Vector(centre)
    h = Vector(size) / 2
    n = cuts + 1
    start = len(acc.v)
    faces_axes = [(0, 1, 2), (0, 2, 1), (1, 2, 0)]
    for axis in range(3):
        for sign in (-1, 1):
            u_ax, v_ax = [a for a in range(3) if a != axis]
            grid = []
            for iu in range(n + 1):
                row = []
                for iv in range(n + 1):
                    p = [0.0, 0.0, 0.0]
                    p[axis] = sign
                    p[u_ax] = -1 + 2 * iu / n
                    p[v_ax] = -1 + 2 * iv / n
                    row.append(p)
                grid.append(row)
            ids = []
            for iu in range(n + 1):
                r = []
                for iv in range(n + 1):
                    q = Vector(grid[iu][iv])
                    local = Vector((q.x * h.x, q.y * h.y, q.z * h.z))
                    if taper is not None:
                        f = taper[0] + (taper[1] - taper[0]) * (0.5 - 0.5 * q.y)
                        local.z = (q.z * 0.5 + 0.5) * h.z * 2 * f - h.z
                    edge = sum(1.0 for comp in q if abs(comp) > 0.999)
                    near = max(0.0, max(abs(q.x), abs(q.y), abs(q.z)))
                    sharp = (abs(q.x) ** 6 + abs(q.y) ** 6 + abs(q.z) ** 6) / 3.0
                    world = c + local
                    nz = noise.noise(world * 9.0 + Vector((seed, seed * 1.7, seed * 2.3)))
                    fine = noise.noise(world * 31.0 + Vector((seed, 0, 0)))
                    depth = 0.002 + 0.002 * fine
                    depth += chip * max(0.0, nz + 0.15) * (0.3 + 1.4 * sharp)
                    d = local.normalized() if local.length > 1e-6 else Vector((0, 1, 0))
                    r.append(acc.add_v(world - d * depth))
                ids.append(r)
            for iu in range(n):
                for iv in range(n):
                    quad = [ids[iu][iv], ids[iu + 1][iv], ids[iu + 1][iv + 1], ids[iu][iv + 1]]
                    # Outward winding: u x v must point along +axis * sign.
                    uvec = [0, 0, 0]
                    uvec[u_ax] = 1
                    vvec = [0, 0, 0]
                    vvec[v_ax] = 1
                    cr = Vector(uvec).cross(Vector(vvec))
                    if cr[axis] * sign < 0:
                        quad.reverse()
                    acc.face(quad, kind)
    return start


# --- objects -------------------------------------------------------------------------

MATS = {}


def make_object(name, acc, weld=0.0, recalc=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(p) for p in acc.v], [], acc.f)
    me.update(calc_edges=True)
    for kind in acc.mats:
        me.materials.append(MATS[kind])
    for poly, mi in zip(me.polygons, acc.m):
        poly.material_index = mi
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.transform(G2B)
    bm = bmesh.new()
    bm.from_mesh(me)
    if weld > 0:
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=weld)
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return ob


def smooth_by_angle(ob, deg):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(deg))
    except Exception as ex:  # noqa: BLE001
        log("smooth by angle failed:", ex)


def tris(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


# --- the gate -------------------------------------------------------------------------

def arch_y(x, inset):
    """The arch's inner edge, `inset` in from the opening: half an ellipse
    springing vertically at the jambs."""
    a = GATE_HALF - inset
    b = GATE_APEX - GATE_SPRING - inset
    return GATE_SPRING + b * math.sqrt(max(1.0 - (x / a) ** 2, 0.0))


def build_leaf(lock):
    """The left leaf in the gate's frame (x -1.64 .. 0), before moving it to its hinge."""
    acc = Acc()
    st = 0.07           # stile section
    edge = -GATE_HALF + 0.012
    sx = edge + st / 2  # hinge stile's centre line
    mx = -0.045         # meeting stile's centre line
    # Hinge stile, meeting stile, bottom rail.
    box(acc, (sx, (0.03 + GATE_SPRING) / 2, 0), (st, GATE_SPRING - 0.03, st), "rust")
    top_m = arch_y(mx, 0.012 + st / 2)
    box(acc, (mx, (0.03 + top_m) / 2 + 0.01, 0), (0.08, top_m - 0.03 + 0.02, 0.08), "rust")
    box(acc, ((sx + mx) / 2, 0.09, 0), (mx - sx, 0.1, 0.06), "rust")
    # The arch: a flat iron sweep from the springing to the apex.
    inset = 0.012 + st / 2
    ea = GATE_HALF - inset
    eb = GATE_APEX - GATE_SPRING - inset
    a0 = math.pi
    a1 = math.acos(max(-1.0, min(1.0, (mx + 0.02) / ea)))
    pts = []
    for i in range(25):
        a = a0 + (a1 - a0) * i / 24
        pts.append(Vector((ea * math.cos(a), GATE_SPRING + eb * math.sin(a), 0)))
    pts[0].y -= 0.02
    sweep(acc, pts, rect(st, st), "rust")
    # Flat rails either side of the bars.
    rails = [0.62, 1.95, GATE_SPRING - 0.02]
    for y in rails:
        for z in (0.033, -0.033):
            box(acc, ((sx + mx) / 2, y, z), (mx - sx - 0.02, 0.085, 0.022), "rust")
    # The bars.
    xs = [sx + 0.12 + i * (mx - sx - 0.2) / 8 for i in range(9)]
    for i, x in enumerate(xs):
        top = arch_y(x, 0.012 + st) + 0.02
        lean = random.uniform(-0.004, 0.004)
        mid = Vector((x + lean * 2, (0.12 + top) / 2, random.uniform(-0.003, 0.003)))
        sweep(acc, [Vector((x, 0.12, 0)), mid, Vector((x, top, 0))], rect(0.034, 0.034), "rust")
        for y in rails:
            if y < top - 0.05:
                rivet(acc, (x, y, 0.044), (0, 0, 1), 0.016, "rust")
                rivet(acc, (x, y, -0.044), (0, 0, -1), 0.016, "rust")
    # Hinge knuckles on the outer edge.
    for y in (0.55, 2.0, 3.05):
        cyl(acc, (-GATE_HALF + 0.02, y - 0.1, 0), (-GATE_HALF + 0.02, y + 0.1, 0), 0.035, 10, "rust")
    if lock:
        # The big bronze gear lock where the leaves meet: a riveted case, a
        # large gear wheel behind radial straps and a small one meshing with it,
        # a brass piston bolt (on the right leaf) running into it. Below eye
        # height: a solid plate there hid prisoners on the middle line (note 153).
        lc = Vector((-0.2, 1.08, 0.0))
        box(acc, (lc.x, lc.y, 0.062), (0.34, 0.44, 0.05), "bronze")
        box(acc, (lc.x, lc.y, -0.056), (0.3, 0.4, 0.03), "bronze")
        for dx in (-0.15, 0.15):
            for dy in (-0.2, 0.2):
                rivet(acc, (lc.x + dx, lc.y + dy, 0.087), (0, 0, 1), 0.012, "bronze")
                rivet(acc, (lc.x + dx * 0.9, lc.y + dy * 0.9, -0.071), (0, 0, -1), 0.01, "bronze")
        gc = Vector((lc.x - 0.01, lc.y + 0.04, 0.1))
        gear(acc, gc, 0.135, 0.105, 18, 0.022, "bronze", spokes=6, hub=0.03)
        for k in range(6):
            a = 2 * math.pi * k / 6
            d = Vector((math.cos(a), math.sin(a), 0))
            rot = Matrix.Rotation(a, 3, "Z")
            box(acc, gc + d * 0.1 + Vector((0, 0, 0.018)), (0.15, 0.024, 0.008), "bronze", rot)
        gear(acc, Vector((lc.x + 0.105, lc.y - 0.15, 0.094)), 0.05, 0.036, 9, 0.016, "brass", spokes=3, hub=0.013)
        box(acc, (lc.x - 0.09, lc.y - 0.165, 0.09), (0.016, 0.05, 0.006), "pit")
        cyl(acc, (lc.x + 0.17, lc.y - 0.02, 0.075), (lc.x + 0.21, lc.y - 0.02, 0.075), 0.03, 12, "brass")
    return acc


def gear(acc, c, r_out, r_in, teeth, thick, kind, spokes=6, hub=0.06, tooth=None):
    """A spur gear facing +Z: a toothed rim, spokes and a hub."""
    tooth = tooth or (r_out - r_in) * 0.45
    n = teeth * 4
    outer, inner = [], []
    for i in range(n):
        a = 2 * math.pi * i / n
        phase = i % 4
        r = r_out if phase in (1, 2) else r_out - tooth
        outer.append((r, a))
        inner.append((r_in, a))
    z0, z1 = c.z - thick / 2, c.z + thick / 2

    def P(r, a, z):
        return Vector((c.x + r * math.cos(a), c.y + r * math.sin(a), z))

    fo = [acc.add_v(P(r, a, z1)) for r, a in outer]
    fi = [acc.add_v(P(r, a, z1)) for r, a in inner]
    bo = [acc.add_v(P(r, a, z0)) for r, a in outer]
    bi = [acc.add_v(P(r, a, z0)) for r, a in inner]
    for i in range(n):
        j = (i + 1) % n
        acc.face((fi[i], fo[i], fo[j], fi[j]), kind)
        acc.face((bi[j], bo[j], bo[i], bi[i]), kind)
        acc.face((fo[i], bo[i], bo[j], fo[j]), kind)
        acc.face((fi[j], bi[j], bi[i], fi[i]), kind)
    for s in range(spokes):
        a = 2 * math.pi * s / spokes + math.pi / spokes
        mid = (r_in + hub) / 2
        rot = Matrix.Rotation(a, 3, "Z")
        box(acc, P(mid, a, c.z), ((r_in - hub) + 0.01, max(0.012, r_in * 0.16), thick * 0.7), kind, rot)
    xf = Matrix.Translation(c) @ Matrix.Rotation(math.pi / 2, 4, "X")
    lathe(acc, [(0.0, -thick * 0.8), (hub, -thick * 0.8), (hub, thick * 0.9), (hub * 0.6, thick * 1.3), (0.0, thick * 1.35)],
          12, kind, xf)


def build_gate():
    left = build_leaf(lock=True)
    for i, p in enumerate(left.v):
        left.v[i] = p + Vector((GATE_HALF, 0, 0))
    gl = make_object("gate_l", left)
    right = build_leaf(lock=False)
    # The keeper, and the brass piston that throws the bolt into the lock.
    box(right, (-0.11, 1.06, 0.055), (0.15, 0.3, 0.035), "bronze")
    for dy in (-0.11, 0.11):
        rivet(right, (-0.11, 1.06 + dy, 0.074), (0, 0, 1), 0.01, "bronze")
    cyl(right, (-0.2, 1.06, 0.09), (-0.04, 1.06, 0.09), 0.032, 14, "brass")
    for x in (-0.19, -0.12):
        cyl(right, (x, 1.06, 0.09), (x + 0.012, 1.06, 0.09), 0.038, 14, "brass")
    cyl(right, (-0.04, 1.06, 0.09), (0.035, 1.06, 0.09), 0.014, 10, "brass")
    for i, p in enumerate(right.v):
        right.v[i] = Vector((-p.x - GATE_HALF, p.y, p.z))
    # The mirror reversed every face's winding; recalc_face_normals in
    # make_object puts them back outward.
    gr = make_object("gate_r", right)
    return [gl, gr]


# --- the lantern -----------------------------------------------------------------------

LANTERN_FLAME_Y = -0.30


def build_lantern():
    acc = Acc()
    link(acc, (0, -0.03, 0), (0, 1, 0), 0.0, 0.06, 0.04, 0.006, "rust", 12, 5)
    lathe(acc, [(0.0, -0.055), (0.012, -0.055), (0.022, -0.075), (0.03, -0.085), (0.09, -0.15),
                (0.102, -0.158), (0.102, -0.172), (0.0, -0.172)], 16, "iron")
    lathe(acc, [(0.08, -0.17), (0.092, -0.172), (0.092, -0.195), (0.08, -0.197)], 16, "iron")
    for i in range(6):
        a = 2 * math.pi * i / 6
        pts = []
        for k in range(5):
            y = -0.195 - k * (0.43 - 0.195) / 4
            r = 0.09 + 0.008 * math.sin(math.pi * k / 4)
            pts.append(Vector((r * math.cos(a), y, -r * math.sin(a))))
        sweep(acc, pts, circle(0.0055, 6), "iron")
    for y in (-0.26, -0.36):
        pts = [Vector((0.097 * math.cos(2 * math.pi * i / 20), y, -0.097 * math.sin(2 * math.pi * i / 20))) for i in range(20)]
        sweep(acc, pts, circle(0.0045, 5), "iron", closed=True)
    lathe(acc, [(0.0, -0.418), (0.098, -0.418), (0.1, -0.43), (0.1, -0.445), (0.07, -0.47), (0.03, -0.49),
                (0.012, -0.505), (0.0, -0.51)], 16, "iron")
    # The candle's cup and a stub of candle.
    lathe(acc, [(0.0, -0.418), (0.03, -0.418), (0.032, -0.39), (0.026, -0.39), (0.0, -0.395)], 12, "iron")
    lathe(acc, [(0.0, -0.392), (0.018, -0.392), (0.018, -0.34), (0.0, -0.335)], 10, "wax")
    lant = make_object("lantern", acc)
    gacc = Acc()
    lathe(gacc, [(0.079, -0.196), (0.079, -0.418)], 18, "glass")
    glass = make_object("lantern_glass", gacc, recalc=False)
    cacc = Acc()
    chain(cacc, [(0, 0, 0), (0, -0.5, 0)], "rust", 0.064, 0.038, 0.0068, 12, 5)
    ch = make_object("lantern_chain", cacc)
    return [lant, ch], glass


# --- chains on the wall ------------------------------------------------------------------

def manacle(acc, top, kind):
    """An open cuff hanging from `top`: a flat band bent nearly round, its hinge up."""
    c = Vector(top) + Vector((0, -0.065, 0))
    pts = []
    for i in range(17):
        a = math.radians(110 + 300 * i / 16)
        pts.append(c + Vector((0.055 * math.cos(a), 0.055 * math.sin(a), 0.012 * math.sin(a * 0.5))))
    sweep(acc, pts, rect(0.008, 0.034), kind)
    cyl(acc, Vector(top) + Vector((0, -0.02, -0.02)), Vector(top) + Vector((0, -0.02, 0.02)), 0.009, 8, kind)


def eye_plate(acc, at, kind="rust"):
    x, y = at
    box(acc, (x, y, 0.012), (0.14, 0.16, 0.024), kind)
    for dx in (-0.048, 0.048):
        for dy in (-0.055, 0.055):
            rivet(acc, (x + dx, y + dy, 0.024), (0, 0, 1), 0.012, kind)
    cyl(acc, (x, y, 0.02), (x, y, 0.055), 0.016, 8, kind)
    link(acc, (x, y - 0.045, 0.066), (0, 1, 0), math.pi / 2, 0.12, 0.085, 0.015, kind, 14, 6)
    return Vector((x, y - 0.1, 0.066))


def build_wall_chains():
    """As in the photo: a heavy chain hanging from high on the wall to a big ring
    above the bench's back, and lower down a pair of manacles on a short chain."""
    acc = Acc()
    n = 0
    top = eye_plate(acc, (-0.32, 2.75))
    n += chain(acc, [top, Vector((-0.31, 1.72, 0.075))], "rust", 0.125, 0.078, 0.016, 14, 6)
    # The ring it ends in.
    sweep(acc, [Vector((-0.31 + 0.075 * math.sin(2 * math.pi * i / 22), 1.63 + 0.075 * math.cos(2 * math.pi * i / 22), 0.085))
                for i in range(22)], circle(0.016, 6), "rust", closed=True)
    low = eye_plate(acc, (0.22, 1.42))
    k = chain(acc, [low, Vector((0.22, 1.12, 0.07))], "rust", 0.1, 0.062, 0.013, 12, 6, start_spin=math.pi / 2)
    n += k
    for dx in (-0.055, 0.055):
        manacle(acc, (0.22 + dx, 1.08, 0.07 + abs(dx) * 0.3), "rust")
    cyl(acc, (0.16, 1.08, 0.07), (0.28, 1.08, 0.07), 0.01, 8, "rust")
    log("wall chains: %d links" % n)
    return [make_object("wall_chains", acc)]

# --- bench, shelf, drain, straw ----------------------------------------------------------

def build_bench():
    acc = Acc()
    stone_block(acc, (0, 0.43, 0.25), (1.2, 0.1, 0.5), "stone", cuts=12, chip=0.03, seed=1.0)
    # A solid block under the slab, as in the photo, a little inset.
    stone_block(acc, (0, 0.19, 0.23), (1.12, 0.38, 0.44), "stone", cuts=9, chip=0.025, seed=3.0)
    ob = make_object("bench", acc, weld=1e-5)
    return ob


def drape_cloth(bench):
    """A frayed burlap cloth dropped over the bench by Blender's cloth solver."""
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=44, y_subdivisions=36, size=1.0, calc_uvs=True)
    cloth = bpy.context.active_object
    cloth.name = "bench_cloth"
    cloth.data.uv_layers[0].name = "weave"
    cloth.scale = (1.0, 0.8, 1.0)
    bpy.ops.object.transform_apply(scale=True)
    # In Blender's frame: the wall is y 0, the room -y, up +z. Over the bench
    # top (0.46), hanging over its front edge.
    cloth.location = (0.12, -0.42, 0.52)
    cloth.rotation_euler = (0.0, 0.0, math.radians(6))
    bpy.ops.object.transform_apply(location=True, rotation=True)
    # Draped over the bench's front edge (Blender's frame: the bench top at z
    # 0.48, its front edge at y -0.5): flat and rumpled on the top, rolling
    # over the edge on a 3 cm radius, then hanging in folds. Shaped here rather
    # than by the cloth solver: headless, the solver let it fall through the
    # stone every time.
    top, edge, r = 0.483, -0.505, 0.03
    for v in cloth.data.vertices:
        x, y = v.co.x, v.co.y
        d = edge - y  # past the edge
        fold = 0.022 * math.sin(x * 17.0 + 1.3 * noise.noise(Vector((x * 3.0, 0.0, 0.7))))
        if d <= 0.0:
            v.co.z = top + 0.004 + 0.008 * max(0.0, noise.noise(Vector((x * 9.0, y * 9.0, 0.2))))
        elif d < r * math.pi / 2:
            a = d / r
            v.co.y = edge - r * math.sin(a)
            v.co.z = top - r + r * math.cos(a) + 0.004
        else:
            hang = d - r * math.pi / 2
            v.co.y = edge - r - 0.004 - fold * min(hang / 0.12, 1.0) - 0.01 * hang
            v.co.z = top - r - hang
    bpy.ops.mesh.primitive_plane_add(size=0.1)
    wall = bpy.context.active_object
    # Fray: eat the edges by noise, and a couple of holes.
    bm = bmesh.new()
    bm.from_mesh(cloth.data)
    uv = bm.loops.layers.uv["weave"]
    gone = []
    for f in bm.faces:
        u = sum(l[uv].uv.x for l in f.loops) / len(f.loops)
        v = sum(l[uv].uv.y for l in f.loops) / len(f.loops)
        d = min(u, 1 - u, v, 1 - v)
        t = 0.012 + 0.05 * max(0.0, noise.noise(Vector((u * 9.0, v * 9.0, 0.3))) + 0.2)
        hole = noise.noise(Vector((u * 4.0 + 7.0, v * 4.0, 1.1)))
        if d < t or (d > 0.18 and hole > 0.62):
            gone.append(f)
    bmesh.ops.delete(bm, geom=gone, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(cloth.data)
    bm.free()
    cloth.data.materials.clear()
    cloth.data.materials.append(MATS["burlap"])
    sol = cloth.modifiers.new("Solidify", "SOLIDIFY")
    sol.thickness = 0.003
    sol.offset = 1.0
    for o in bpy.context.scene.objects:
        o.select_set(False)
    cloth.select_set(True)
    bpy.context.view_layer.objects.active = cloth
    bpy.ops.object.modifier_apply(modifier="Solidify")
    for p in cloth.data.polygons:
        p.use_smooth = True
    log("cloth: %d faces after fraying" % len(cloth.data.polygons))
    # Into the bench, keeping the weave UVs for the burlap's pattern.
    bench.data.uv_layers.new(name="weave")
    for o in bpy.context.scene.objects:
        o.select_set(False)
    cloth.select_set(True)
    bench.select_set(True)
    bpy.context.view_layer.objects.active = bench
    bpy.ops.object.join()
    return bench


def build_shelf():
    acc = Acc()
    # A thick slab on one broad corbel, as in the photo.
    stone_block(acc, (0, 1.15, 0.16), (0.8, 0.1, 0.32), "stone", cuts=8, chip=0.016, seed=11.0)
    stone_block(acc, (0.05, 0.96, 0.12), (0.32, 0.28, 0.24), "stone", cuts=5, chip=0.012, seed=13.0, taper=(1.0, 0.35))
    top = 1.2
    # A pewter bowl, a little dented.
    prof_out = [(0.0, 0.0), (0.05, 0.0), (0.056, 0.004), (0.082, 0.022), (0.098, 0.044), (0.102, 0.052)]
    prof_in = [(0.098, 0.053), (0.094, 0.046), (0.078, 0.026), (0.052, 0.009), (0.0, 0.007)]
    start = len(acc.v)
    xf = Matrix.Translation(Vector((0.12, top, 0.15)))
    lathe(acc, prof_out + prof_in, 22, "pewter", xf)
    for i in range(start, len(acc.v)):
        p = acc.v[i]
        acc.v[i] = p + Vector((0, 0.004 * noise.noise(p * 40.0), 0)) * (1.0 if p.y > top + 0.02 else 0.0)
    # A tin cup with a handle.
    xf = Matrix.Translation(Vector((-0.2, top, 0.15)))
    lathe(acc, [(0.0, 0.0), (0.036, 0.0), (0.04, 0.005), (0.043, 0.115), (0.046, 0.12), (0.041, 0.12),
                (0.038, 0.009), (0.0, 0.008)], 20, "pewter", xf)
    for y in (0.02, 0.1):
        lathe(acc, [(0.039, y - 0.006), (0.045, y - 0.004), (0.045, y + 0.004), (0.039, y + 0.006)], 20, "pewter", xf)
    hp = [Vector((-0.2 - 0.042 - 0.032 * math.sin(math.pi * i / 8), top + 0.025 + 0.075 * i / 8, 0.15)) for i in range(9)]
    sweep(acc, hp, rect(0.006, 0.014), "pewter")
    return [make_object("shelf", acc, weld=1e-5)]


def build_drain():
    acc = Acc()
    o, i_ = 0.6, 0.44
    w = (o - i_) / 2
    for s in (-1, 1):
        stone_block(acc, (s * (i_ / 2 + w / 2), 0.005, 0), (w, 0.04, o), "stone", cuts=4, chip=0.008, seed=20 + s)
        stone_block(acc, (0, 0.005, s * (i_ / 2 + w / 2)), (i_, 0.04, w), "stone", cuts=4, chip=0.008, seed=24 + s)
    box(acc, (0, 0.002, 0), (i_ + 0.01, 0.004, i_ + 0.01), "pit")
    for k in range(9):
        x = -i_ / 2 + 0.03 + k * (i_ - 0.06) / 8
        box(acc, (x, 0.014, 0), (0.022, 0.02, i_ + 0.02), "rust")
    for z in (-0.12, 0.12):
        box(acc, (0, 0.012, z), (i_ + 0.02, 0.018, 0.026), "rust")
    return [make_object("drain", acc, weld=1e-5)]


def build_straw():
    acc = Acc()
    for b in range(90):
        a = random.uniform(0, 2 * math.pi)
        r0 = random.uniform(0.0, 0.16)
        length = random.uniform(0.12, 0.3)
        base = Vector((r0 * math.cos(a), random.uniform(0.002, 0.03), r0 * math.sin(a)))
        d = Vector((math.cos(a + random.uniform(-0.9, 0.9)), 0, math.sin(a + random.uniform(-0.9, 0.9)))).normalized()
        lift = random.uniform(0.0, 0.05)
        side = d.cross(Vector((0, 1, 0))).normalized()
        pts = []
        for k in range(4):
            t = k / 3
            pts.append(base + d * length * t + Vector((0, lift * math.sin(math.pi * t), 0)))
        top, bot = [], []
        for k, p in enumerate(pts):
            wdt = 0.0045 * (1.0 - 0.6 * k / 3)
            top.append(acc.add_v(p + side * wdt + Vector((0, 0.0008, 0))))
            top.append(acc.add_v(p - side * wdt + Vector((0, 0.0008, 0))))
            bot.append(acc.add_v(p + side * wdt))
            bot.append(acc.add_v(p - side * wdt))
        for k in range(3):
            a0, a1, b0, b1 = top[2 * k], top[2 * k + 1], top[2 * k + 2], top[2 * k + 3]
            acc.face((a0, b0, b1, a1), "straw")
            c0, c1, e0, e1 = bot[2 * k], bot[2 * k + 1], bot[2 * k + 2], bot[2 * k + 3]
            acc.face((c0, c1, e1, e0), "straw")
    # Not closed: keep the faces as written (top up, the copy under it down).
    return [make_object("straw_tuft", acc, recalc=False)]


# --- materials ---------------------------------------------------------------------------

class Graph:
    def __init__(self, mat):
        self.nt = mat.node_tree
        self.nt.nodes.clear()
        self.out = self.nt.nodes.new("ShaderNodeOutputMaterial")
        self.tc = self.nt.nodes.new("ShaderNodeTexCoord")
        self.geo = self.nt.nodes.new("ShaderNodeNewGeometry")
        self.ao = self.nt.nodes.new("ShaderNodeAmbientOcclusion")
        self.ao.inputs["Distance"].default_value = 0.06
        self.ao.only_local = True
        self.ao.samples = 16

    def n(self, kind, **kw):
        node = self.nt.nodes.new(kind)
        for k, v in kw.items():
            if hasattr(node, k):
                setattr(node, k, v)
        return node

    def link(self, a, b):
        self.nt.links.new(a, b)

    def noise(self, scale, detail=6.0, rough=0.55, vec=None, w=0.0):
        t = self.n("ShaderNodeTexNoise", noise_dimensions="4D")
        t.inputs["Scale"].default_value = scale
        t.inputs["Detail"].default_value = detail
        t.inputs["Roughness"].default_value = rough
        t.inputs["W"].default_value = w
        self.link(vec if vec is not None else self.tc.outputs["Object"], t.inputs["Vector"])
        return t.outputs["Fac"]

    def math(self, op, a, b=0.0, clamp=False):
        m = self.n("ShaderNodeMath", operation=op, use_clamp=clamp)
        for i, x in enumerate((a, b)):
            if isinstance(x, (int, float)):
                m.inputs[i].default_value = x
            else:
                self.link(x, m.inputs[i])
        return m.outputs[0]

    def ramp(self, x, lo, hi):
        """smoothstep(lo, hi, x)"""
        m = self.n("ShaderNodeMapRange", interpolation_type="SMOOTHSTEP")
        m.inputs["From Min"].default_value = lo
        m.inputs["From Max"].default_value = hi
        self.link(x, m.inputs["Value"])
        return m.outputs["Result"]

    def mix(self, a, b, fac):
        m = self.n("ShaderNodeMix", data_type="RGBA")
        for sock, x in ((m.inputs[6], a), (m.inputs[7], b)):
            if isinstance(x, tuple):
                sock.default_value = (*x, 1.0)
            else:
                self.link(x, sock)
        if isinstance(fac, (int, float)):
            m.inputs[0].default_value = fac
        else:
            self.link(fac, m.inputs[0])
        return m.outputs[2]

    def lerp(self, a, b, fac):
        m = self.n("ShaderNodeMix", data_type="FLOAT")
        for sock, x in ((m.inputs[2], a), (m.inputs[3], b)):
            if isinstance(x, (int, float)):
                sock.default_value = x
            else:
                self.link(x, sock)
        if isinstance(fac, (int, float)):
            m.inputs[0].default_value = fac
        else:
            self.link(fac, m.inputs[0])
        return m.outputs[0]

    def scale_col(self, c, f):
        m = self.n("ShaderNodeMix", data_type="RGBA", blend_type="MULTIPLY")
        m.inputs[0].default_value = 1.0
        self.link(c, m.inputs[6])
        if isinstance(f, (int, float)):
            m.inputs[7].default_value = (f, f, f, 1)
        else:
            self.link(f, m.inputs[7])
        return m.outputs[2]


def build_material(kind):
    mat = bpy.data.materials.new("k_" + kind)
    mat.use_nodes = True
    g = Graph(mat)
    ao = g.ao.outputs["AO"]
    crev = g.math("SUBTRACT", 1.0, ao, clamp=True)
    point = g.geo.outputs["Pointiness"]
    edge = g.ramp(point, 0.52, 0.6)
    bump_dist = 0.002
    if kind in ("rust", "iron"):
        n1 = g.noise(3.5, 10, 0.62)
        n2 = g.noise(24, 6)
        n3 = g.noise(140, 2)
        lo = 0.3 if kind == "rust" else 0.55
        mask = g.ramp(g.math("ADD", n1, g.math("MULTIPLY", crev, 0.35)), lo, lo + 0.17)
        mask = g.math("MULTIPLY", mask, g.math("SUBTRACT", 1.0, g.math("MULTIPLY", edge, 0.15)), clamp=True)
        iron = g.mix((0.022, 0.021, 0.02), (0.07, 0.066, 0.062), g.math("MULTIPLY", edge, 0.3))
        rust = g.mix((0.05, 0.02, 0.008), (0.022, 0.011, 0.006), n2)
        col = g.mix(iron, rust, mask)
        col = g.scale_col(col, g.math("SUBTRACT", 1.0, g.math("MULTIPLY", crev, 0.6)))
        rough = g.math("ADD", g.lerp(0.42, 0.88, mask), g.math("MULTIPLY", n3, 0.08))
        metal = g.lerp(0.7, 0.08, mask)
        height = g.math("ADD", g.math("MULTIPLY", mask, 0.5), g.math("MULTIPLY", n3, 0.35))
    elif kind in ("bronze", "brass"):
        n1 = g.noise(4.0, 8, 0.6)
        n2 = g.noise(30, 5)
        n3 = g.noise(90, 3)
        base = (0.17, 0.085, 0.03) if kind == "bronze" else (0.24, 0.15, 0.045)
        polish = (0.45, 0.25, 0.09) if kind == "bronze" else (0.58, 0.4, 0.13)
        pat = (0.035, 0.09, 0.065) if kind == "bronze" else (0.05, 0.06, 0.035)
        lo = 0.52 if kind == "bronze" else 0.62
        mask = g.ramp(g.math("ADD", g.math("MULTIPLY", n1, 0.6), g.math("MULTIPLY", crev, 1.1)), lo, lo + 0.2)
        col = g.mix(g.mix(base, polish, edge), pat, mask)
        col = g.scale_col(col, g.math("SUBTRACT", 1.0, g.math("MULTIPLY", crev, 0.55)))
        col = g.scale_col(col, g.lerp(0.75, 1.05, n2))
        rough = g.math("ADD", g.lerp(g.lerp(0.4, 0.24, edge), 0.78, mask), g.math("MULTIPLY", n2, 0.1))
        metal = g.lerp(1.0, 0.05, mask)
        height = g.math("ADD", g.math("MULTIPLY", n3, 0.25), g.math("MULTIPLY", mask, 0.3))
        bump_dist = 0.0015
    elif kind == "stone":
        n1 = g.noise(5.0, 10, 0.62)
        n2 = g.noise(2.2, 4)
        n3 = g.noise(60, 4)
        vor = g.n("ShaderNodeTexVoronoi")
        vor.inputs["Scale"].default_value = 18.0
        g.link(g.tc.outputs["Object"], vor.inputs["Vector"])
        chips = g.ramp(vor.outputs["Distance"], 0.0, 0.35)
        n4 = g.noise(16.0, 8, 0.7)
        col = g.mix((0.032, 0.026, 0.02), (0.105, 0.082, 0.062), g.ramp(n1, 0.35, 0.68))
        col = g.scale_col(col, g.lerp(0.55, 1.25, g.ramp(n4, 0.3, 0.7)))
        col = g.mix(col, (0.15, 0.12, 0.09), g.math("MULTIPLY", g.ramp(n3, 0.62, 0.74), 0.6))
        edges = g.n("ShaderNodeTexVoronoi", feature="DISTANCE_TO_EDGE")
        edges.inputs["Scale"].default_value = 7.0
        edges.inputs["Randomness"].default_value = 1.0
        g.link(g.tc.outputs["Object"], edges.inputs["Vector"])
        crack = g.math("MULTIPLY", g.math("SUBTRACT", 1.0, g.ramp(edges.outputs["Distance"], 0.0, 0.025), clamp=True),
                       g.ramp(n2, 0.4, 0.6))
        col = g.mix(col, (0.01, 0.009, 0.008), crack)
        col = g.scale_col(col, g.math("SUBTRACT", 1.0, g.math("MULTIPLY", crev, 0.7)))
        # Wet: glossy, drier where it stands proud.
        rough = g.math("ADD", 0.28, g.math("MULTIPLY", g.ramp(n2, 0.35, 0.7), 0.4))
        rough = g.math("ADD", rough, g.math("MULTIPLY", edge, 0.15))
        metal = 0.0
        height = g.math("ADD", g.math("MULTIPLY", n1, 0.6), g.math("MULTIPLY", chips, 0.4))
        height = g.math("ADD", height, g.math("MULTIPLY", n3, 0.15))
        height = g.math("ADD", height, g.math("MULTIPLY", n4, 0.35))
        height = g.math("SUBTRACT", height, g.math("MULTIPLY", crack, 0.5))
        bump_dist = 0.005
    elif kind == "burlap":
        uvn = g.n("ShaderNodeUVMap", uv_map="weave")
        waves = []
        for d in ("X", "Y"):
            w = g.n("ShaderNodeTexWave", wave_type="BANDS", bands_direction=d, wave_profile="SIN")
            w.inputs["Scale"].default_value = 85.0
            w.inputs["Distortion"].default_value = 1.2
            w.inputs["Detail"].default_value = 1.0
            g.link(uvn.outputs["UV"], w.inputs["Vector"])
            waves.append(w.outputs["Fac"])
        chk = g.n("ShaderNodeTexChecker")
        chk.inputs["Scale"].default_value = 85.0
        g.link(uvn.outputs["UV"], chk.inputs["Vector"])
        weave = g.lerp(waves[0], waves[1], chk.outputs["Fac"])
        stain = g.noise(6.0, 6, 0.6)
        col = g.mix((0.085, 0.058, 0.03), (0.032, 0.022, 0.012), g.ramp(stain, 0.45, 0.7))
        col = g.scale_col(col, g.lerp(0.55, 1.1, weave))
        col = g.scale_col(col, g.math("SUBTRACT", 1.0, g.math("MULTIPLY", crev, 0.5)))
        rough = 0.95
        metal = 0.0
        height = g.math("MULTIPLY", weave, 1.0)
        bump_dist = 0.0012
    elif kind == "pewter":
        n2 = g.noise(18, 5)
        n3 = g.noise(120, 2)
        col = g.mix((0.13, 0.125, 0.118), (0.32, 0.31, 0.3), edge)
        col = g.scale_col(col, g.math("SUBTRACT", 1.0, g.math("MULTIPLY", crev, 0.75)))
        col = g.scale_col(col, g.lerp(0.7, 1.05, n2))
        rough = g.math("ADD", 0.38, g.math("MULTIPLY", n2, 0.25))
        metal = 0.92
        height = g.math("MULTIPLY", n3, 0.3)
        bump_dist = 0.001
    elif kind == "straw":
        n1 = g.noise(40.0, 3)
        n3 = g.noise(300.0, 2)
        col = g.mix((0.11, 0.075, 0.025), (0.045, 0.03, 0.012), g.ramp(n1, 0.4, 0.62))
        col = g.scale_col(col, g.math("SUBTRACT", 1.0, g.math("MULTIPLY", crev, 0.6)))
        rough = 0.82
        metal = 0.0
        height = g.math("MULTIPLY", n3, 0.4)
        bump_dist = 0.0008
    elif kind == "wax":
        col = g.mix((0.32, 0.27, 0.18), (0.18, 0.15, 0.1), g.noise(30, 2))
        rough, metal, height = 0.5, 0.0, 0.0
    else:  # pit, glass
        col = g.mix((0.006, 0.006, 0.006), (0.01, 0.009, 0.008), 0.5)
        rough, metal, height = 0.12, 0.0, 0.0
    bsdf = g.n("ShaderNodeBsdfPrincipled")
    g.link(col, bsdf.inputs["Base Color"])
    for name, val in (("Roughness", rough), ("Metallic", metal)):
        if isinstance(val, (int, float)):
            bsdf.inputs[name].default_value = val
        else:
            g.link(val, bsdf.inputs[name])
    if not isinstance(height, (int, float)):
        bump = g.n("ShaderNodeBump")
        bump.inputs["Distance"].default_value = bump_dist
        bump.inputs["Strength"].default_value = 1.0
        g.link(height, bump.inputs["Height"])
        g.link(bump.outputs["Normal"], bsdf.inputs["Normal"])
    emit = g.n("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    target = g.n("ShaderNodeTexImage")
    target.name = "BAKE"
    mat["passes"] = 1
    MATS[kind] = mat
    mat["_kind"] = kind
    return mat, g, {"color": col, "rough": rough, "metal": metal, "bsdf": bsdf, "emit": emit, "target": target}


GRAPHS = {}


def set_pass(name, image):
    for kind, (mat, g, s) in GRAPHS.items():
        nt = mat.node_tree
        for l in list(g.out.inputs["Surface"].links):
            nt.links.remove(l)
        if name in ("NORMAL", "AO"):
            nt.links.new(s["bsdf"].outputs[0], g.out.inputs["Surface"])
        else:
            val = s[name]
            for l in list(s["emit"].inputs["Color"].links):
                nt.links.remove(l)
            if isinstance(val, (int, float)):
                s["emit"].inputs["Color"].default_value = (val, val, val, 1)
            elif name == "color":
                nt.links.new(val, s["emit"].inputs["Color"])
            else:
                nt.links.new(val, s["emit"].inputs["Color"])
            nt.links.new(s["emit"].outputs[0], g.out.inputs["Surface"])
        s["target"].image = image
        for n in nt.nodes:
            n.select = False
        s["target"].select = True
        nt.nodes.active = s["target"]


# --- the build -----------------------------------------------------------------------------

def main():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    for kind in ("rust", "iron", "bronze", "brass", "stone", "burlap", "pewter", "straw", "pit", "wax", "glass"):
        mat, g, s = build_material(kind)
        GRAPHS[kind] = (mat, g, s)

    groups = []
    groups.append(("gate", build_gate(), "none"))
    lantern_pieces, glass = build_lantern()
    groups.append(("lantern", lantern_pieces[:1], "none"))
    groups.append(("lantern_chain", lantern_pieces[1:], "none"))
    groups.append(("chains", build_wall_chains(), "wall"))
    bench = build_bench()
    bench = drape_cloth(bench)
    groups.append(("bench", [bench], "wall+floor"))
    groups.append(("shelf", build_shelf(), "wall"))
    groups.append(("drain", build_drain(), "floor"))
    groups.append(("straw", build_straw(), "floor"))
    targets = [o for _, obs, _ in groups for o in obs]
    for o in targets:
        smooth_by_angle(o, 50 if o.name in ("bench", "shelf", "drain", "straw_tuft") else 40)
        log("%-14s %6d triangles" % (o.name, tris(o)))
    log("total %d triangles" % sum(tris(o) for o in targets))

    # Spread apart for the bake, with a stand-in wall / floor behind each.
    helpers = []
    for i, (gname, obs, backing) in enumerate(groups):
        off = Vector((i * 8.0, 0, 0))
        for o in obs:
            o.location = off
        if gname == "lantern":
            glass.location = off
        if "wall" in backing:
            bpy.ops.mesh.primitive_plane_add(size=5.0, location=off + Vector((0, 0.003, 2.0)), rotation=(math.pi / 2, 0, 0))
            helpers.append(bpy.context.active_object)
        if "floor" in backing:
            bpy.ops.mesh.primitive_plane_add(size=5.0, location=off + Vector((0, -2.0, -0.002)))
            helpers.append(bpy.context.active_object)
    glass.hide_render = True
    for h in helpers:
        h.data.materials.append(MATS["stone"])

    # One atlas for every piece.
    for o in targets:
        me = o.data
        lay = me.uv_layers.get("atlas") or me.uv_layers.new(name="atlas")
        me.uv_layers.active = lay
        lay.active_render = True
    for o in bpy.context.scene.objects:
        o.select_set(o in targets)
    bpy.context.view_layer.objects.active = targets[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    bpy.ops.object.mode_set(mode="OBJECT")
    # Even texel density gave the long plain bars 70% of the atlas. They get
    # a third of their share; what is seen close (bench, shelf, lock) the rest.
    for o in targets:
        k = UV_SHARE.get(o.name, 1.0)
        if k != 1.0:
            lay = o.data.uv_layers.active
            uv = np.empty(len(lay.data) * 2, dtype=np.float32)
            lay.data.foreach_get("uv", uv)
            lay.data.foreach_set("uv", uv * k)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin=0.0015)
    bpy.ops.object.mode_set(mode="OBJECT")

    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scn.cycles.device = "GPU"
    except Exception as ex:  # noqa: BLE001
        log("bake on CPU:", ex)
    scn.render.bake.margin = MARGIN
    scn.world = bpy.data.worlds.new("bake")
    scn.world.light_settings.distance = 0.35

    def bake(name, kind, size, samples):
        img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=True)
        img.colorspace_settings.name = "Non-Color"
        set_pass(kind if kind in ("NORMAL", "AO") else name.split("_")[-1], img)
        scn.cycles.samples = samples
        for o in bpy.context.scene.objects:
            o.select_set(o in targets)
        bpy.context.view_layer.objects.active = targets[0]
        if kind == "NORMAL":
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=MARGIN)
        elif kind == "AO":
            bpy.ops.object.bake(type="AO", margin=MARGIN)
        else:
            bpy.ops.object.bake(type="EMIT", margin=MARGIN)
        buf = np.empty(size * size * 4, dtype=np.float32)
        img.pixels.foreach_get(buf)
        log("baked", name)
        return buf.reshape(size, size, 4)

    col = bake("bake_color", "EMIT", ATLAS, 4)
    nrm = bake("bake_normal", "NORMAL", ATLAS, 8)
    rough = bake("bake_rough", "EMIT", ORM_TEX, 4)[..., 0]
    metal = bake("bake_metal", "EMIT", ORM_TEX, 4)[..., 0]
    ao = bake("bake_ao", "AO", ORM_TEX, 96)[..., 0]
    log("albedo mean %.3f; rough mean %.2f; metal mean %.2f; ao mean %.2f" % (
        float(col[..., :3].mean()), float(rough.mean()), float(metal.mean()), float(ao.mean())))

    # --- the export material --------------------------------------------------------
    def image(name, data, size, srgb):
        im = bpy.data.images.new(name, size, size, alpha=False)
        im.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
        im.pixels.foreach_set(np.ascontiguousarray(data, dtype=np.float32).ravel())
        im.file_format = "JPEG"
        return im

    lin = np.clip(col[..., :3], 0.0, 1.0)
    srgb = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)
    alb = np.ones((ATLAS, ATLAS, 4), dtype=np.float32)
    alb[..., :3] = srgb
    orm = np.ones((ORM_TEX, ORM_TEX, 4), dtype=np.float32)
    orm[..., 0] = np.clip(ao, 0, 1)
    orm[..., 1] = np.clip(rough, 0.04, 1)
    orm[..., 2] = np.clip(metal, 0, 1)
    aimg = image("cell_kit_albedo", alb, ATLAS, True)
    nimg = image("cell_kit_normal", nrm, ATLAS, False)
    oimg = image("cell_kit_orm", orm, ORM_TEX, False)

    kit = bpy.data.materials.new("cell_kit")
    kit.use_nodes = True
    nt = kit.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    an = nt.nodes.new("ShaderNodeTexImage")
    an.image = aimg
    nt.links.new(an.outputs["Color"], bsdf.inputs["Base Color"])
    nn = nt.nodes.new("ShaderNodeTexImage")
    nn.image = nimg
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    on = nt.nodes.new("ShaderNodeTexImage")
    on.image = oimg
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(on.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    gltf_out = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
    gltf_out.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    gn = nt.nodes.new("ShaderNodeGroup")
    gn.node_tree = gltf_out
    nt.links.new(sep.outputs["Red"], gn.inputs["Occlusion"])
    glass_mat = bpy.data.materials.new("cell_glass")

    for o in targets:
        me = o.data
        for lay in list(me.uv_layers):
            if lay.name != "atlas":
                me.uv_layers.remove(lay)
        me.materials.clear()
        me.materials.append(kit)
        o.location = (0, 0, 0)
    glass.data.materials.clear()
    glass.data.materials.append(glass_mat)
    glass.location = (0, 0, 0)
    glass.hide_render = False
    for h in helpers:
        bpy.data.objects.remove(h)

    if PREVIEW:
        out = sys.argv[-1]
        for im in (aimg, nimg, oimg):
            im.filepath_raw = os.path.join(out, im.name + ".png")
            im.file_format = "PNG"
            im.save()
            im.file_format = "JPEG"

    for o in bpy.context.scene.objects:
        o.select_set(o in targets or o == glass)
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        use_selection=True,
        export_animations=False,
        export_image_format="JPEG",
        export_jpeg_quality=92,
        export_yup=True,
        export_apply=True,
    )
    log("wrote", OUT, os.path.getsize(OUT))


if __name__ == "__main__":
    main()
