"""Turn a raw Tripo GLB into a game-ready modular kit piece.

Tripo output is never drop-in. Measured on an earlier run: ~5,000 triangles
(fine, `face_limit` is honoured) but **three 2048x2048 maps** per asset. Twelve
assets at that size is roughly 150 MB of texture on a card with 2 GB, which
would cost more than the entire rest of the level. Downscaling the maps is the
whole point of this pass; the geometry needs almost nothing.

It also fixes the things that stop a generated mesh behaving as a module:

* origin placed where the piece is positioned from, not at the mesh centre;
* scaled to the kit's dimensions so copies line up;
* oriented so Godot's -Z is the face that should point outward.

Geometry needs work after all. Every piece arrives at ~4,750 triangles, which is
reasonable for one prop and ruinous for a module: the placer emits 3,736 wall
panels, so the walls alone would be 17.5 M triangles. A module is drawn hundreds
of times, so its triangle budget is hundreds, not thousands -- the silhouette is
flat and the stone detail lives in the normal map either way.

Usage:
    blender --background --factory-startup --python tools/prep_kit_asset.py -- \\
        in.glb out.glb SIZE_X SIZE_Y SIZE_Z ORIGIN [TEXTURE_PX] [TRI_BUDGET]

Sizes are Blender axes -- X and Y are the footprint, Z is up. They become the
glTF/Godot X, Z, Y on export (`export_yup`), so a 2.0 x 0.857 x 2.237 panel is
2.0 wide, 0.857 thick and 2.237 tall in the game.

ORIGIN is one of: bottom (base centre), centre, top (top-face centre).
TRI_BUDGET of 0 leaves the geometry alone.
"""

import bpy
import bmesh
import sys
import math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, DST = argv[0], argv[1]
TARGET = Vector((float(argv[2]), float(argv[3]), float(argv[4])))
ORIGIN = argv[5] if len(argv) > 5 else "bottom"
TEX_PX = int(argv[6]) if len(argv) > 6 else 512
TRI_BUDGET = int(argv[7]) if len(argv) > 7 else 0
## Fraction trimmed off each side of the FACE plane (the two long axes) before
## scaling. Generators like to put a raised border round a flat panel however
## firmly the prompt says not to, and a border repeated every panel tiles as a
## visible grid. Cropping to the field inside it is what makes the piece
## actually modular. 0 disables.
CROP = float(argv[8]) if len(argv) > 8 else 0.0


def log(*a):
    print("[kit]", *a)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

meshes = [o for o in bpy.data.objects if o.type == 'MESH']
if not meshes:
    raise SystemExit("no mesh in " + SRC)

target = meshes[0]
bpy.context.view_layer.objects.active = target
for o in meshes:
    o.select_set(True)
if len(meshes) > 1:
    with bpy.context.temp_override(active_object=target, object=target,
                                   selected_objects=meshes,
                                   selected_editable_objects=meshes):
        bpy.ops.object.join()
target.name = "Module"
target.data.name = "Module"

# --- flatten transforms so measurements mean something ----------------------
with bpy.context.temp_override(active_object=target, object=target,
                               selected_objects=[target],
                               selected_editable_objects=[target]):
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- weld before decimating ---------------------------------------------------
# Tripo's surface arrives with coincident-but-separate vertices, so most edges
# have no second face and collapse cannot merge across them. Decimating in that
# state does not simplify the block, it tears it: at a 300-triangle budget the
# wall panel came out as a cloud of disconnected shards that passed every
# numeric check -- exact size, exact triangle count -- and was unusable.
#
# Welding first gives collapse a connected surface to work on.
verts_in = len(target.data.vertices)
span = max(target.dimensions)
with bpy.context.temp_override(active_object=target, object=target,
                               selected_objects=[target],
                               selected_editable_objects=[target]):
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.remove_doubles(threshold=span * 0.0004)
    bpy.ops.object.mode_set(mode='OBJECT')
log("welded %d -> %d vertices" % (verts_in, len(target.data.vertices)))

target.data.calc_loop_triangles()
tris_in = len(target.data.loop_triangles)

# --- decimate to the module budget --------------------------------------------
# Before scaling and re-origining, so the numbers reported below describe what
# actually ships. Collapse rather than un-subdivide: the generated mesh has no
# subdivision history to undo, and collapse is the one that respects UV seams.
# When a crop is coming, decimation waits for it. Budgeting before the crop
# means budgeting triangles that are about to be thrown away: a 2000-triangle
# request came out as 875 because the border took 56% of the faces with it.
if TRI_BUDGET > 0 and tris_in > TRI_BUDGET and CROP <= 0.0:
    mod = target.modifiers.new(name="Budget", type='DECIMATE')
    mod.decimate_type = 'COLLAPSE'
    mod.use_collapse_triangulate = True
    mod.ratio = TRI_BUDGET / float(tris_in)
    with bpy.context.temp_override(active_object=target, object=target,
                                   selected_objects=[target],
                                   selected_editable_objects=[target]):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    target.data.calc_loop_triangles()
    log("decimated %d -> %d triangles (budget %d)"
        % (tris_in, len(target.data.loop_triangles), TRI_BUDGET))

# --- clean up, THEN measure ---------------------------------------------------
# Collapse leaves degenerate slivers behind, and quadric collapse can place a
# merged vertex outside the original hull: this mesh's box GREW from 0.494 to
# 0.566 across decimation. The glTF exporter then drops those degenerate
# triangles, so Blender measured a 2.000 m panel and the file on disk was
# 1.781 m -- 11% short, from a stage that reported success.
#
# So the junk is removed here, before anything is measured, and the box is taken
# from geometry that will survive export.
with bpy.context.temp_override(active_object=target, object=target,
                               selected_objects=[target],
                               selected_editable_objects=[target]):
    before = len(target.data.vertices)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.dissolve_degenerate()
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.delete_loose(use_verts=True, use_edges=True, use_faces=True)
    bpy.ops.object.mode_set(mode='OBJECT')
    if len(target.data.vertices) != before:
        log("cleaned %d degenerate/loose vertices"
            % (before - len(target.data.vertices)))

verts = [v.co for v in target.data.vertices]
lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
size = hi - lo
log("imported %.3f x %.3f x %.3f" % (size.x, size.y, size.z))

# --- orient before scaling ---------------------------------------------------
# A generated mesh does not arrive with its width on the axis you wanted. The
# door came in 0.104 x 0.697 x 1.000 -- thin on X, wide on Y -- and scaling that
# straight onto a 2.2 x 0.2 x 3.0 target stretched one axis 74x and produced a
# smear rather than a door.
#
# So the axes are matched by RANK: the source's longest dimension becomes the
# target's longest, and so on. That gets the piece the right way round without
# needing to know how the generator happened to orient it.
def rank(v):
    return sorted(range(3), key=lambda i: -v[i])


src_rank = rank(size)
dst_rank = rank(TARGET)
# permutation[target_axis] = source_axis supplying it
permutation = [0, 0, 0]
for i in range(3):
    permutation[dst_rank[i]] = src_rank[i]

if permutation != [0, 1, 2]:
    # An odd permutation mirrors the mesh, which turns the stonework inside out
    # and flips the normals. Negate one axis to put the handedness back.
    parity = (permutation[0] - permutation[1]) * (permutation[1] - permutation[2]) \
        * (permutation[2] - permutation[0])
    flip = -1.0 if parity < 0 else 1.0
    for v in target.data.vertices:
        o = v.co.copy()
        v.co = Vector((o[permutation[0]] * flip, o[permutation[1]], o[permutation[2]]))
    verts = [v.co for v in target.data.vertices]
    lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
    hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
    size = hi - lo
    log("reoriented axes %s -> %.3f x %.3f x %.3f"
        % (permutation, size.x, size.y, size.z))

# --- crop the border off ------------------------------------------------------
# Done after reorientation, so "the face plane" is known: the two LONGEST axes
# are the face, and the shortest is the panel's thickness. Cutting on the face
# axes only, never on thickness.
if CROP > 0.0:
    order = sorted(range(3), key=lambda i: -size[i])
    face_axes = order[:2]
    keep_lo = [lo[i] for i in range(3)]
    keep_hi = [hi[i] for i in range(3)]
    for i in face_axes:
        keep_lo[i] = lo[i] + size[i] * CROP
        keep_hi[i] = hi[i] - size[i] * CROP

    # Cut ON the plane, rather than discarding whole faces that stray past it.
    #
    # Deleting by face centre leaves a ragged sawtooth boundary -- every face
    # straddling the line is kept or dropped whole -- and on a panel meant to
    # butt against its neighbours that edge is exactly what shows. It also
    # interacts badly with decimation: the spikes survive at high budgets and
    # only get smoothed away by decimating hard, which is a perverse reason to
    # prefer fewer triangles.
    bm = bmesh.new()
    bm.from_mesh(target.data)
    for i in face_axes:
        for sign, limit in ((1.0, keep_hi[i]), (-1.0, keep_lo[i])):
            normal = [0.0, 0.0, 0.0]
            normal[i] = sign
            plane_co = [0.0, 0.0, 0.0]
            plane_co[i] = limit
            bm.faces.ensure_lookup_table()
            bmesh.ops.bisect_plane(
                bm,
                geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                plane_co=Vector(plane_co),
                plane_no=Vector(normal),
                clear_outer=True)
    bm.verts.ensure_lookup_table()
    orphans = [v for v in bm.verts if not v.link_faces]
    if orphans:
        bmesh.ops.delete(bm, geom=orphans, context='VERTS')
    doomed = []
    bm.to_mesh(target.data)
    bm.free()

    verts = [v.co for v in target.data.vertices]
    if not verts:
        raise SystemExit("[kit] crop removed everything -- CROP is too large")
    lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
    hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
    size = hi - lo
    log("cropped %.0f%% off each face edge, %d faces removed -> %.3f x %.3f x %.3f"
        % (CROP * 100.0, len(doomed), size.x, size.y, size.z))

    # The deferred decimation, now that the geometry is the geometry that ships.
    target.data.calc_loop_triangles()
    have = len(target.data.loop_triangles)
    if TRI_BUDGET > 0 and have > TRI_BUDGET:
        mod = target.modifiers.new(name="Budget", type='DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.use_collapse_triangulate = True
        mod.ratio = TRI_BUDGET / float(have)
        with bpy.context.temp_override(active_object=target, object=target,
                                       selected_objects=[target],
                                       selected_editable_objects=[target]):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        with bpy.context.temp_override(active_object=target, object=target,
                                       selected_objects=[target],
                                       selected_editable_objects=[target]):
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.mesh.dissolve_degenerate()
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.mesh.delete_loose(use_verts=True, use_edges=True, use_faces=True)
            bpy.ops.object.mode_set(mode='OBJECT')
        target.data.calc_loop_triangles()
        log("decimated after crop %d -> %d triangles (budget %d)"
            % (have, len(target.data.loop_triangles), TRI_BUDGET))
        verts = [v.co for v in target.data.vertices]
        lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
        hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
        size = hi - lo

# --- scale to the kit's module size -----------------------------------------
# Per axis rather than uniform: a module has to mate with its neighbours on all
# three, and a generated mesh never comes out at the right proportions. The
# distortion is reported so a badly stretched piece can be regenerated rather
# than silently shipped.
factor = Vector((
    TARGET.x / size.x if size.x > 1e-6 else 1.0,
    TARGET.y / size.y if size.y > 1e-6 else 1.0,
    TARGET.z / size.z if size.z > 1e-6 else 1.0,
))
for v in target.data.vertices:
    v.co = Vector((v.co.x * factor.x, v.co.y * factor.y, v.co.z * factor.z))
spread = max(factor) / max(min(factor), 1e-6)
log("scaled by %.3f, %.3f, %.3f  (anisotropy %.2fx)" % (factor.x, factor.y, factor.z, spread))
if spread > 1.8:
    log("WARNING: stretched more than 1.8x on one axis -- the source proportions")
    log("         were wrong for this module; consider regenerating the prompt.")

# --- re-origin ---------------------------------------------------------------
verts = [v.co for v in target.data.vertices]
lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
mid = (lo + hi) * 0.5
if ORIGIN == "bottom":
    shift = Vector((-mid.x, -mid.y, -lo.z))
elif ORIGIN == "top":
    shift = Vector((-mid.x, -mid.y, -hi.z))
else:
    shift = -mid
for v in target.data.vertices:
    v.co = v.co + shift
log("origin: %s" % ORIGIN)

# --- textures ----------------------------------------------------------------
# Godot compresses on import, but it compresses whatever size it is given, so
# the saving has to happen here.
shrunk = 0
for img in bpy.data.images:
    if img.size[0] <= 0:
        continue
    if img.size[0] > TEX_PX or img.size[1] > TEX_PX:
        log("  %s  %dx%d -> %dx%d" % (img.name, img.size[0], img.size[1], TEX_PX, TEX_PX))
        img.scale(TEX_PX, TEX_PX)
        shrunk += 1
log("textures resized: %d" % shrunk)

target.data.calc_loop_triangles()
log("triangles %d, materials %d"
    % (len(target.data.loop_triangles), len(target.data.materials)))

bpy.ops.export_scene.gltf(
    filepath=DST,
    export_format='GLB',
    export_animations=False,
    export_skins=False,
    export_apply=False,
    export_yup=True,
    export_materials='EXPORT',
    export_image_format='WEBP',
    export_image_quality=85,
    use_selection=False,
)
log("wrote", DST)

# --- verify the file, not the scene -------------------------------------------
# Every number above describes Blender's copy. The exporter silently dropped
# geometry once already, so the only figure worth trusting is the one read back
# off disk. A module that is short by a centimetre tiles with a visible seam,
# and nothing downstream would report it.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=DST)
lo = Vector((1e9, 1e9, 1e9))
hi = Vector((-1e9, -1e9, -1e9))
out_tris = 0
for o in [x for x in bpy.data.objects if x.type == 'MESH']:
    o.data.calc_loop_triangles()
    out_tris += len(o.data.loop_triangles)
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        for i in range(3):
            lo[i] = min(lo[i], w[i])
            hi[i] = max(hi[i], w[i])
shipped = hi - lo
log("VERIFY on disk %.4f x %.4f x %.4f, %d triangles"
    % (shipped.x, shipped.y, shipped.z, out_tris))
worst = max(abs(shipped[i] - TARGET[i]) for i in range(3))
if worst > 0.002:
    raise SystemExit(
        "[kit] FAILED: wanted %.4f x %.4f x %.4f, got %.4f x %.4f x %.4f "
        "(off by %.4f m)" % (TARGET.x, TARGET.y, TARGET.z,
                             shipped.x, shipped.y, shipped.z, worst))
log("VERIFY size matches target within %.4f m" % worst)
