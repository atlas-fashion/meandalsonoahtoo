"""Old dead vines with huge, fantastical leaves, wrapped round a rock pillar.

    blender -b -P tools/build_vines.py -- ROCK_GLB OUT_GLB SX SY SZ SEED VINES LEAVES LEAF_SCALE

ROCK_GLB is the pillar the vines are for (`rock_column.glb`, or the unit
`rock_pillar.glb`), scaled by (SX, SY, SZ) -- Blender axes, Z up -- to the size
it is actually drawn at in the game, so the vines hug the real surface and not
a stand-in cylinder. The pillars are lumpy (their radius runs 0.62 m median to
~1 m at the foot), so a vine laid on a fixed radius would float off one side
and sink in on the other: every point on a vine is found by casting a ray at
the rock from outside and sitting it on what it hits.

Writes one GLB holding two objects, `Vines` (woody stems and dead tendrils)
and `Leaves`. The game gives each its own material; the leaves' wind sway is
a vertex shader, driven by the colours written here:

    COLOR.r   0 at the stem, rising to 1 at the leaf tip: how far that
              vertex may move. The stem end must not move, or the leaf tears
              away from its vine.
    COLOR.g   a random phase per leaf, so they do not all nod in unison.

Built along Blender +Z so the glTF exporter lands it on Godot +Y, with the
origin at the pillar's base centre -- the same convention as the rock, so the
game instances both with the same transform.
"""
import bpy
import bmesh
import math
import random
import sys
from mathutils import Vector, noise
from mathutils.bvhtree import BVHTree

ARGV = sys.argv[sys.argv.index("--") + 1:]
ROCK = ARGV[0]
OUT = ARGV[1]
SCALE = Vector((float(ARGV[2]), float(ARGV[3]), float(ARGV[4])))
SEED = int(ARGV[5]) if len(ARGV) > 5 else 1
VINES = int(ARGV[6]) if len(ARGV) > 6 else 3
LEAVES = int(ARGV[7]) if len(ARGV) > 7 else 24
LEAF_SCALE = float(ARGV[8]) if len(ARGV) > 8 else 1.0

rng = random.Random(SEED)


def log(*a):
    print("[vines]", *a, flush=True)


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load_rock():
    bpy.ops.import_scene.gltf(filepath=ROCK)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    rock = meshes[0]
    rock.scale = SCALE
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bm = bmesh.new()
    bm.from_object(rock, depsgraph)
    bm.transform(rock.matrix_world)
    tree = BVHTree.FromBMesh(bm)
    lo = min(v.co.z for v in bm.verts)
    hi = max(v.co.z for v in bm.verts)
    bm.free()
    return rock, tree, lo, hi


def surface(tree, angle, z, standoff):
    """The rock's surface at this bearing and height, pushed out by `standoff`,
    plus the outward normal there."""
    d = Vector((math.cos(angle), math.sin(angle), 0.0))
    origin = d * 4.0 + Vector((0.0, 0.0, z))
    hit, normal, _i, _dist = tree.ray_cast(origin, -d, 8.0)
    if hit is None:
        return d * 0.7 + Vector((0.0, 0.0, z)), d
    n = Vector((normal.x, normal.y, 0.0))
    n = n.normalized() if n.length > 1e-4 else d
    return hit + n * standoff, n


def vine_path(tree, lo, hi, a0, turns, samples):
    """A wandering helix up the pillar, sitting on the stone."""
    pts = []
    top = lo + (hi - lo) * 0.93
    for i in range(samples):
        t = i / (samples - 1)
        z = lo + 0.05 + (top - lo) * t
        wander = noise.noise(Vector((t * 3.0, a0, SEED * 0.37))) * 0.9
        angle = a0 + turns * math.tau * t + wander
        p, n = surface(tree, angle, z, 0.035)
        pts.append((p, n, angle, t))
    return pts


def add_tube(name, points, radii, bevel_res=2):
    """A tube along `points`, radius per point, converted to a mesh."""
    cu = bpy.data.curves.new(name, type="CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = 1.0
    cu.bevel_resolution = bevel_res
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(points) - 1)
    for i, p in enumerate(points):
        sp.points[i].co = (p.x, p.y, p.z, 1.0)
        sp.points[i].radius = radii[i]
    ob = bpy.data.objects.new(name, cu)
    bpy.context.scene.collection.objects.link(ob)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target="MESH")
    return bpy.context.view_layer.objects.active


def tendril(root, outward, length):
    """A dead curl of stem, spiralling off the vine."""
    pts = []
    up = Vector((0.0, 0.0, 1.0))
    side = outward.cross(up).normalized()
    curl = rng.uniform(1.5, 3.0)
    lift = rng.uniform(-0.3, 0.6)
    for i in range(14):
        t = i / 13.0
        a = t * curl * math.pi
        r = length * (1.0 - t * 0.7)
        p = root + outward * (math.sin(a) * r * 0.6 + t * length * 0.4) \
            + side * (math.cos(a) - 1.0) * r * 0.4 + up * lift * t * length
        pts.append(p)
    return pts


def leaf(bm, col, root, outward, length, width, phase, lobes, droop, curl):
    """One large, fantastical leaf: a long lobed blade with a pointed tip,
    edges curling up, drooping under its own weight."""
    up = Vector((0.0, 0.0, 1.0))
    tangent = outward.cross(up).normalized()
    # The blade runs out and mostly DOWN, hanging off the vine, with its broad
    # face turned outward. The first version pointed blades straight out from
    # the stone, so from anywhere in the court they were seen edge-on and read
    # as slivers, not huge leaves.
    x_axis = outward * rng.uniform(0.35, 0.8) + tangent * rng.uniform(-0.7, 0.7) \
        + up * rng.uniform(-0.9, 0.35)
    x_axis.normalize()
    y_axis = x_axis.cross(outward)
    if y_axis.length < 1e-3:
        y_axis = tangent
    y_axis.normalize()
    # A small roll about the blade, so they do not all lie flat to the ground.
    roll = rng.uniform(-0.6, 0.6)
    z_axis = y_axis.cross(x_axis).normalized()
    y_axis = (y_axis * math.cos(roll) + z_axis * math.sin(roll)).normalized()
    z_axis = y_axis.cross(x_axis).normalized()

    nu, nv = 14, 6
    grid = []
    for i in range(nu + 1):
        u = i / nu
        # Broad in the middle, a narrow stalk at the base, drawn to a point.
        halfw = width * 0.5 * math.sin(math.pi * min(1.0, u ** 0.75)) * (1.0 - u ** 5)
        halfw *= 1.0 + 0.28 * math.sin(u * math.pi * lobes + phase * 5.0)
        if u < 0.08:
            halfw = width * 0.04
        row = []
        for j in range(nv + 1):
            s = -1.0 + 2.0 * j / nv
            p = root + x_axis * (u * length) + y_axis * (s * halfw) \
                + z_axis * (curl * s * s * halfw) \
                + Vector((0.0, 0.0, -droop * u * u * length))
            row.append(bm.verts.new(p))
        grid.append(row)
    uv = bm.loops.layers.uv.verify()
    for i in range(nu):
        for j in range(nv):
            f = bm.faces.new((grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]))
            for loop in f.loops:
                ii = next(k for k in range(nu + 1) if loop.vert in grid[k])
                jj = grid[ii].index(loop.vert)
                u = ii / nu
                loop[uv].uv = (u, jj / nv)
                loop[col] = (u, phase, 0.0, 1.0)


def main():
    clear()
    rock, tree, lo, hi = load_rock()
    height = hi - lo
    log("rock %s at %.2f x %.2f x %.2f, height %.2f" % (ROCK, SCALE.x, SCALE.y, SCALE.z, height))

    stems = []
    anchors = []
    for v in range(VINES):
        a0 = v * math.tau / VINES + rng.uniform(-0.4, 0.4)
        turns = rng.uniform(0.9, 1.6) * (1 if v % 2 == 0 else -1) * min(1.0, height / 6.0 + 0.35)
        samples = max(40, int(height * 22))
        path = vine_path(tree, lo, hi, a0, turns, samples)
        # Every other vine is a thinner secondary strand, so the pillar reads as
        # wrapped in a tangle rather than striped by a few even lines.
        thick = 0.075 if v % 2 == 0 else 0.035
        radii = [thick * (1.0 - 0.55 * p[3]) + 0.012 for p in path]
        stems.append(add_tube("stem%d" % v, [p[0] for p in path], radii))
        anchors.extend(path)
        # Dead tendrils curling off the stem.
        for k in range(max(2, int(height * 0.9))):
            p, n, _a, t = path[rng.randrange(len(path) // 8, len(path) - 2)]
            pts = tendril(p, n, rng.uniform(0.25, 0.55))
            stems.append(add_tube("tendril", pts, [0.014 * (1.0 - i / 14.0) + 0.004 for i in range(14)], 1))

    bpy.ops.object.select_all(action="DESELECT")
    for s in stems:
        s.select_set(True)
    bpy.context.view_layer.objects.active = stems[0]
    bpy.ops.object.join()
    vines = bpy.context.view_layer.objects.active
    vines.name = "Vines"
    bark = bpy.data.materials.new("vine_bark")
    vines.data.materials.clear()
    vines.data.materials.append(bark)

    # Leaves along the stems, spread through the height.
    me = bpy.data.meshes.new("Leaves")
    bm = bmesh.new()
    col = bm.loops.layers.color.new("Col")
    anchors.sort(key=lambda a: a[3])
    for k in range(LEAVES):
        t = (k + rng.uniform(0.2, 0.8)) / LEAVES
        p, n, _a, _t = anchors[min(len(anchors) - 1, int(t * len(anchors)))]
        length = rng.uniform(1.1, 2.0) * LEAF_SCALE
        width = length * rng.uniform(0.45, 0.62)
        leaf(bm, col, p, n, length, width, rng.random(), rng.choice([3, 4, 5, 6]),
             rng.uniform(0.05, 0.25), rng.uniform(0.25, 0.6))
    bm.to_mesh(me)
    bm.free()
    leaves = bpy.data.objects.new("Leaves", me)
    bpy.context.scene.collection.objects.link(leaves)
    me.materials.append(bpy.data.materials.new("vine_leaf"))
    me.color_attributes.active_color = me.color_attributes["Col"]

    bpy.data.objects.remove(rock)
    for o in list(bpy.context.scene.objects):
        if o.type not in ("MESH",) or o.name not in ("Vines", "Leaves"):
            bpy.data.objects.remove(o)
    for o in (vines, leaves):
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.shade_smooth()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True,
                              export_yup=True, export_vertex_color="ACTIVE",
                              export_apply=True)
    log("vines %d tris, leaves %d tris -> %s" % (
        sum(len(p.vertices) - 2 for p in vines.data.polygons),
        sum(len(p.vertices) - 2 for p in leaves.data.polygons), OUT))


main()
