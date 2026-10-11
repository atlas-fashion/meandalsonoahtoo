"""Cut the Tripo gate -- the pointed-arch double door in the `gate` module --
out of models/kit/module_gate.glb and export it as the corridor door.

    blender -b --factory-startup -P tools/build_gate_door.py -- models/kit/gate_door.glb

Three meshes: "LeafL" and "LeafR" (each with its origin on its hinge) and
"GateFrame" (the moulded stone arch round them). Materials keep the module's
names but carry NO images: module_level.place_doors gives them the module's own
materials, already fixed by `_fix_material`, so the textures are not loaded
twice.

The cut follows the gate's measured shape, not a guess. Ray-cast on the
module's -X wall (Godot frame): the leaves lie in the plane x = -1.776 and the
frame stands 0.18-0.24 m proud of it; the opening is two concentric
two-centred (pointed) arches -- inner half-width 1.21 m, springing 2.0 m, arc
radius 1.929 about centres 0.719 m either side of the door's middle, apex
3.79 m; the moulding is the same arch 0.43 m wider (apex 4.25). The two leaves
meet at z = -0.335. Every measured row matched those curves within ~3 cm.

Output frame: the door's own. +Y up, X across the doorway, +Z the side the
leaves swing towards (the gate's front, which faces into the junction). Scaled
by SCALE so it fills the bored junction arches the doors stand in.
"""

import bpy
import bmesh
import math
import os
import sys
from mathutils import Vector

OUT = sys.argv[sys.argv.index("--") + 1]
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "models", "kit", "module_gate.glb")

PLANE_X = -1.776     # the leaves' plane, Godot x
CENTRE_Z = -0.335    # the seam between the leaves, Godot z
HALF_W = 1.21
SPRING = 2.0
OFFSET_C = 0.719
RADIUS = 1.929
RING = 0.43          # the moulding's width
BACK_LIMIT = -1.88   # nothing deeper than this belongs to the gate
SCALE = 1.15
THICK = 0.05         # leaves are a sheet; the back is a mirrored copy this far behind
SHEET_DEPTH = 0.06   # door-local z below which a face is board, not iron


def log(*a):
    print("[gate_door]", *a)


def inside(z, y, grow=0.0):
    """Inside the pointed arch, `grow` wider all round. z from the middle."""
    w = HALF_W + grow
    if abs(z) > w or y < 0.0:
        return False
    if y <= SPRING:
        return True
    r = RADIUS + grow
    return (abs(z) + OFFSET_C) ** 2 + (y - SPRING) ** 2 <= r * r


def godot(v):
    # glTF import: Blender (x, y, z) = Godot (x, -z, y).
    return Vector((v.x, v.z, -v.y))


def to_door(g):
    """Godot module coords -> door-local coords (before the hinge shift)."""
    lx = -(g.z - CENTRE_Z)
    ly = g.y
    lz = g.x - PLANE_X
    return Vector((lx, ly, lz)) * SCALE


def to_blender(l):
    # glTF export: Godot (x, y, z) = Blender (x, -y... ) i.e. Blender = (x, -z, y).
    return Vector((l.x, -l.z, l.y))


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
src = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]
src.data.transform(src.matrix_world)
src.matrix_world.identity()
mats = list(src.data.materials)


def piece(name, keep, split=None, hinge=0.0, mirror=False):
    """A new object from the source faces for which keep(centroid) is true."""
    bm = bmesh.new()
    bm.from_mesh(src.data)
    if split is not None:
        # Cut cleanly along the seam before choosing a side.
        res = bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                     plane_co=Vector((0.0, -CENTRE_Z, 0.0)),
                                     plane_no=Vector((0.0, 1.0, 0.0)))
        # ...and along both hinge lines: the strap ends run a few cm past them,
        # with thick knuckles that swung into the moulding when the leaf opened.
        # Cut there, the outboard bits fall outside the leaf and are dropped.
        for hz in (CENTRE_Z - HALF_W, CENTRE_Z + HALF_W):
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                   plane_co=Vector((0.0, -hz, 0.0)),
                                   plane_no=Vector((0.0, 1.0, 0.0)))
    drop = [f for f in bm.faces if not keep(godot(f.calc_center_median()), f)]
    bmesh.ops.delete(bm, geom=drop, context='FACES')
    # Deleting faces can leave their edges and verts behind, unused.
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context='VERTS')
    for v in bm.verts:
        l = to_door(godot(v.co))
        l.x += hinge
        v.co = to_blender(l)
    if mirror:
        # Only the boards themselves: the iron bands and the latch stand up to
        # 0.35 m proud, and mirroring them would put the back that deep, too far
        # for the stone surround behind to sit close and keep the light out.
        sheet = [f for f in bm.faces if all(-v.co.y < SHEET_DEPTH for v in f.verts)]
        dup = bmesh.ops.duplicate(bm, geom=sheet)
        new_faces = [g for g in dup["geom"] if isinstance(g, bmesh.types.BMFace)]
        new_verts = [g for g in dup["geom"] if isinstance(g, bmesh.types.BMVert)]
        # Door-local z -> -z - THICK; Blender y = -z, so y -> -y + THICK.
        for v in new_verts:
            v.co.y = -v.co.y + THICK
        bmesh.ops.reverse_faces(bm, faces=new_faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for m in mats:
        mesh.materials.append(m)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def is_tripo(f):
    return "tripo" in mats[f.material_index].name if mats else True


## A face's centre is not enough: the Tripo mesh has a few huge triangles that
## cross the whole module and happen to have their centre in the doorway. Every
## vertex must lie in the gate's own slab of space.
def compact(f, grow):
    for v in f.verts:
        g = godot(v.co)
        z = g.z - CENTRE_Z
        if g.x < BACK_LIMIT - 0.02 or g.x > PLANE_X + 0.4:
            return False
        if g.y < -0.05 or abs(z) > HALF_W + grow + 0.08:
            return False
        if g.y > SPRING + math.sqrt((RADIUS + grow) ** 2 - OFFSET_C ** 2) + 0.12:
            return False
    return True


def leaf_side(sign):
    def keep(g, f):
        z = g.z - CENTRE_Z
        lx = -z
        return (is_tripo(f) and g.x > BACK_LIMIT and g.y > 0.03 and compact(f, 0.0)
                and inside(z, g.y) and (lx < 0.0 if sign < 0 else lx > 0.0))
    return keep


def frame_keep(g, f):
    z = g.z - CENTRE_Z
    return (is_tripo(f) and g.x > BACK_LIMIT and g.y > 0.03 and compact(f, RING)
            and inside(z, g.y, RING + 0.03) and not inside(z, g.y))


hinge = HALF_W * SCALE
left = piece("LeafL", leaf_side(-1.0), split=True, hinge=hinge, mirror=True)
right = piece("LeafR", leaf_side(1.0), split=True, hinge=-hinge, mirror=True)
frame = piece("GateFrame", frame_keep)
bpy.data.objects.remove(src)

for o in (left, right, frame):
    o.data.calc_loop_triangles()
    used = {i for t in o.data.loop_triangles for i in t.vertices}
    pts = [o.data.vertices[i].co for i in used]
    # Reported in the door's (Godot) frame: x across, y up, z towards the junction.
    log("%-9s tris %6d  x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % (
        o.name, len(o.data.loop_triangles),
        min(p.x for p in pts), max(p.x for p in pts),
        min(p.z for p in pts), max(p.z for p in pts),
        min(-p.y for p in pts), max(-p.y for p in pts)))

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    export_animations=False,
    export_skins=False,
    export_apply=True,
    export_yup=True,
    export_materials='EXPORT',
    export_image_format='NONE',
    use_selection=False,
)
log("hinge at +/-%.3f, apex %.3f, frame apex %.3f" % (
    hinge, (SPRING + math.sqrt(RADIUS ** 2 - OFFSET_C ** 2)) * SCALE,
    (SPRING + math.sqrt((RADIUS + RING) ** 2 - OFFSET_C ** 2)) * SCALE))
log("wrote", OUT)
