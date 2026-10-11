"""Turn the four raw Tripo tunnel sections into the five the maze needs.

Tripo was asked for straight / corner / T / gated-dead-end and returned
straight / CROSS / dead-end / gated-dead-end. Measured, not guessed: see the
probe in the session notes, and `verify_modules.py` next to this file, which
re-checks every claim below against the exported meshes.

Rather than spend another 80 credits, the missing pieces are cut from what
arrived. A corner is a cross with two adjacent sides walled up and a T is a
cross with one side walled up, so the only thing actually missing is wall to
fill an archway with -- and the dead-end piece has three genuine stone walls
built in the same style, one of which is donated.

    straight   <- mod_straight, turned to run along +/-Y
    cross      <- mod_corner (open on all four sides)
    tee        <- cross, -X archway plugged
    corner     <- cross, -X and -Y archways plugged
    dead       <- cross, three archways plugged
    gate       <- mod_gate, turned so its doors face -Y

A spanning-tree maze is mostly dead ends, and the gated piece cannot stand in
for them: its enormous barred doors are meant to mark the two exits to other
zones, and they say nothing if they are behind every third corner. Hence a
plain dead end, walled with the same donated stone as the corner and the T.

## Axis convention

Everything is normalised so that **Blender +Y is the maze's north**. The glTF
exporter maps Blender (x, y, z) to (x, z, -y), so Blender +Y becomes Godot -Z,
which is the direction `module_maze.gd` calls N. That means the placer needs no
correction yaw, and a module that looks right here looks right in game.

Open sides, after this script:

    straight   +Y -Y
    corner     +Y +X
    tee        +Y +X -Y      (wall on -X)
    cross      all four
    dead       +Y
    gate       +Y            (doors on -Y)

## Usage

    blender -b -P tools/build_modules.py -- [TRI_BUDGET] [CELL_SIZE]

Writes models/kit/module_*.glb. The raw mod_*.glb files are the inputs and are
left alone.
"""
import os
import sys
import math
import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
## High on purpose. The sources are ~14k triangles and the budget sits above
## that, so in practice nothing is decimated. Cutting them to 6k is what made
## the stone read as triangles: the detail lives in a normal map authored for
## the original mesh, and it only looks like carved stone on that mesh. The
## game is per-pixel bound (CLAUDE.md section 2), so the extra geometry is not
## where the frame time goes.
TRI_BUDGET = int(ARGV[0]) if len(ARGV) > 0 else 18000
## Edge length of one maze cell in metres. Modules are scaled to exactly this
## on both horizontal axes so neighbours abut with no seam to fall through.
CELL = float(ARGV[1]) if len(ARGV) > 1 else 6.0
## Ceiling height is driven by the cell so the proportions stay put.
HEIGHT = CELL * 0.85
## 2K, Tripo's native size. At 1K an atlas covering a whole 6 m module works
## out to under 100 texels per metre, which is mush at arm's length.
TEXTURE_PX = int(ARGV[2]) if len(ARGV) > 2 else 2048
## How far the base colour is pulled toward neutral, how much it is darkened,
## and how hard the mortar and staining are pushed apart. Deliberately short
## of full desaturation -- stone with no colour variation left in it reads as
## poured concrete, not as old masonry.
GREY_AMOUNT = float(ARGV[3]) if len(ARGV) > 3 else 0.70
GREY_LIFT = float(ARGV[4]) if len(ARGV) > 4 else 0.82
GREY_CONTRAST = float(ARGV[5]) if len(ARGV) > 5 else 1.35

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT = os.path.join(HERE, "models", "kit")

## How far a plugged archway sits inside the module face, as a fraction of the
## cell. Recessed rather than flush: two stone surfaces in the same plane
## z-fight, and a blocked-up arch reads better than a flat panel anyway.
PLUG_INSET = 0.025
## The plug is oversized so it laps into the floor, roof and side walls instead
## of leaving a hairline of daylight at its edges.
PLUG_OVERSIZE = 1.12
## Slice of the donor taken for the plug, as a fraction of its depth.
DONOR_SLICE = 0.22


## Name of the material given to every surface this script INVENTS rather
## than inherits from Tripo: boolean cut faces, the lid, the floor slab.
##
## Those surfaces have no meaningful UVs -- they are made after the atlas was
## painted -- so textured with the module's own atlas they came out as flat
## grey smears, which is what "textures for every part" was about. Tagging
## them with a named material lets `module_level.gd` give them the project's
## tileable stone, projected in world space, which needs no UVs at all and
## runs continuously across module seams.
SYNTH_MATERIAL = "synth_stone"


def synth_material():
    mat = bpy.data.materials.get(SYNTH_MATERIAL)
    if mat is None:
        mat = bpy.data.materials.new(SYNTH_MATERIAL)
        mat.diffuse_color = (0.2, 0.2, 0.2, 1.0)
    return mat


def synth_slot(ob):
    """Index of the synth material on `ob`, adding the slot if needed."""
    mat = synth_material()
    for i, slot in enumerate(ob.data.materials):
        if slot is not None and slot.name == SYNTH_MATERIAL:
            return i
    ob.data.materials.append(mat)
    return len(ob.data.materials) - 1


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path):
    """Import, join to one object, and bake transforms so bounds are honest."""
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    fresh = [o for o in set(bpy.context.scene.objects) - before if o.type == "MESH"]
    if not fresh:
        raise SystemExit("no mesh in %s" % path)
    bpy.ops.object.select_all(action="DESELECT")
    for o in fresh:
        o.select_set(True)
    bpy.context.view_layer.objects.active = fresh[0]
    if len(fresh) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    # Empties left behind by the glTF scene graph would otherwise keep their
    # transforms and confuse later parenting.
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def bounds(ob):
    pts = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def spin(ob, degrees):
    """Rotate about Z. Set the mode first: glTF import leaves objects in
    quaternion mode, where assigning rotation_euler is silently ignored."""
    ob.rotation_mode = "XYZ"
    ob.rotation_euler = (0.0, 0.0, math.radians(degrees))
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)


def fit_cell(ob):
    """Scale to exactly CELL x CELL in plan and HEIGHT tall, floor at y=0.

    Non-uniform on purpose. The pieces came back 0.81-1.00 on their short axis
    and a shared grid cannot absorb that: a module even a centimetre short
    leaves a crack to the skybox at every join.
    """
    lo, hi = bounds(ob)
    size = hi - lo
    ob.scale = (CELL / size.x, CELL / size.y, HEIGHT / size.z)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    lo, hi = bounds(ob)
    mid = (lo + hi) * 0.5
    # Origin at the centre of the floor: the placer positions cells by their
    # floor, and a mid-height origin would sink every module half a storey.
    ob.location = (-mid.x, -mid.y, -lo.z)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)


def make_plug(donor_path):
    """Cut a wall slab off the donor's solid -X face."""
    ob = import_glb(donor_path)
    lo, hi = bounds(ob)
    size = hi - lo
    cut_x = lo.x + size.x * DONOR_SLICE

    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.bisect_plane(
        bm,
        geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
        plane_co=(cut_x, 0.0, 0.0),
        plane_no=(1.0, 0.0, 0.0),
        clear_outer=True,
    )
    bm.to_mesh(me)
    bm.free()

    # Park it so its outer face is the x=0 plane and it is centred otherwise;
    # placing it against a module is then a translate, with no bookkeeping.
    lo, hi = bounds(ob)
    mid = (lo + hi) * 0.5
    ob.location = (-lo.x, -mid.y, -mid.z)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    ob.name = "plug_master"
    return ob


def seal(target, plug_master, side):
    """Wall up one side of `target`. `side` is '+X', '-X', '+Y' or '-Y'.

    Assumes `target` has already been fitted to the cell, so the module spans
    +/-CELL/2 horizontally and 0..HEIGHT vertically.
    """
    plug = plug_master.copy()
    plug.data = plug_master.data.copy()
    bpy.context.scene.collection.objects.link(plug)

    lo, hi = bounds(plug)
    size = hi - lo
    # The plug's own depth stays as cut; only its face is stretched to cover.
    plug.scale = (1.0, CELL * PLUG_OVERSIZE / size.y, HEIGHT * PLUG_OVERSIZE / size.z)
    bpy.ops.object.select_all(action="DESELECT")
    plug.select_set(True)
    bpy.context.view_layer.objects.active = plug
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    half = CELL * 0.5 - CELL * PLUG_INSET
    yaw = {"-X": 0.0, "+X": 180.0, "-Y": 90.0, "+Y": 270.0}[side]
    spin(plug, yaw)
    offset = {
        "-X": Vector((-half, 0.0, 0.0)),
        "+X": Vector((half, 0.0, 0.0)),
        "-Y": Vector((0.0, -half, 0.0)),
        "+Y": Vector((0.0, half, 0.0)),
    }[side]
    plug.location = offset + Vector((0.0, 0.0, HEIGHT * 0.5))
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

    bpy.ops.object.select_all(action="DESELECT")
    plug.select_set(True)
    target.select_set(True)
    bpy.context.view_layer.objects.active = target
    bpy.ops.object.join()
    return target


## Passage cut through each open side: width, and the height of the straight
## part below the arch head. The head adds another WIDTH/2 on top.
PASSAGE_WIDTH = 3.6
PASSAGE_SHOULDER = 2.0
## How deep the floor patch box goes below the walking surface.
FLOOR_DEPTH = 0.6


def measure_floor(ob):
    """Median height of the walkable floor surface, in module space."""
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    tree = BVHTree.FromBMesh(bm)
    half = CELL * 0.5
    heights = []
    for i in range(28):
        for j in range(28):
            x = -half * 0.75 + CELL * 0.75 * (i + 0.5) / 28.0
            y = -half * 0.75 + CELL * 0.75 * (j + 0.5) / 28.0
            hit = tree.ray_cast((x, y, HEIGHT * 0.45), (0, 0, -1), HEIGHT)
            if hit[0] is not None:
                heights.append(hit[0].z)
    bm.free()
    if not heights:
        return 0.0
    heights.sort()
    return heights[len(heights) // 2]


def stretch_to_full_height(ob, floor_h):
    """Scale Z so that, once the floor is dropped to 0, the ceiling is HEIGHT.

    `fit_cell` makes the module HEIGHT tall from the BOTTOM OF ITS BOUNDING
    BOX, which is the underside of the floor slab, not the surface the player
    walks on. Sinking the floor to zero afterwards therefore leaves the
    ceiling at HEIGHT minus the floor thickness -- and that differs per
    module, from 0.28 m on the straight to nothing on the pieces cut from the
    cross.

    That mismatch is not cosmetic. The lid goes on at a fixed HEIGHT, so on
    the straight it floated a quarter of a metre above the walls, leaving a
    horizontal slot around the top of every one of those cells. Slots line up
    from cell to cell, so standing in the maze you looked out through the
    ceiling and saw the sky.
    """
    if floor_h <= 1e-4:
        return floor_h
    k = HEIGHT / (HEIGHT - floor_h)
    ob.scale = (1.0, 1.0, k)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return floor_h * k


def sink_floor_to_zero(ob, floor_h):
    """Shift the module so its walkable floor is exactly z = 0.

    Every module has to agree on this. They did not: the straight's floor sat
    at +0.276 while the pieces cut from the cross ended up at -0.019, so every
    straight-to-junction join had a 29 cm step in it with nothing underneath,
    and the player -- who stands on a collision slab whose top is y = 0 --
    was knee deep in the floor of every straight.
    """
    if abs(floor_h) < 1e-4:
        return
    ob.location = (0.0, 0.0, -floor_h)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)


def widen_passages(ob, sides, floor_h=0.0):
    """Cut a proper archway through each open side.

    Tripo returned a four-way CROSS in place of the corner that was ordered,
    and the corner, T and dead end are all cut from it. Its openings are only
    1.60 m wide in a 6 m room 5.1 m tall, against 3.80 m on the straight. At
    standing eye height that does not read as a corridor at all -- it reads
    as a small chamber with holes low in the walls, which is exactly how it
    was reported.

    Rather than spend credits regenerating the piece, the openings are bored
    out with a round-headed arch: a box up to the shoulder with a cylinder on
    top. The cut removes the original moulding around the opening, which is a
    fair trade for a passage the player can see and walk down.
    """
    half = CELL * 0.5
    for side in sides:
        # Sprung from the FLOOR, not from the bottom of the bounding box.
        # Starting at zero bored the floor out along with the wall, which is
        # what dropped these modules' floors 29 cm below the straight's.
        cutter = _arch_cutter(side, half, floor_h)
        mod = ob.modifiers.new("passage_%s" % side, "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.object = cutter
        # EXACT rather than FAST: the fast solver leaves shards and flipped
        # normals on meshes this noisy, which show up as black slivers.
        mod.solver = "EXACT"
        # Tripo meshes are not perfectly closed, and each cut leaves the
        # result a little worse for the next one. Without this the cuts
        # silently stopped happening part way through a module -- the tee
        # came out with one opening instead of three, and no error anywhere.
        mod.use_hole_tolerant = True
        mod.use_self = False
        # The faces the cut creates -- the soffit and reveals of each new
        # archway -- take the CUTTER's material. They have no sensible UVs
        # into the module's atlas, and tagged like this they are textured
        # with the tileable stone instead of a stretched smear.
        mod.material_mode = "TRANSFER"
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter)
        # Tidy between cuts, so degenerate slivers from one do not feed the
        # next.
        weld(ob)


def _arch_cutter(side, half, floor_h=0.0):
    """A round-headed arch prism running through one face of the cell.

    Built as ONE extruded profile. The first version stacked a box and a
    cylinder as two overlapping shells and handed that to the boolean, which
    is not a solid: the exact solver produced garbage, grew every module's
    bounding box to the cutter's length and left the dead end with no opening
    at all. A boolean cutter has to be a single closed manifold.
    """
    w = PASSAGE_WIDTH * 0.5
    # Over-long, so it passes cleanly through the wall at both ends.
    depth = CELL * 1.4

    base = floor_h + 0.02
    profile = [(-w, base), (w, base)]
    steps = 12
    for i in range(steps + 1):
        t = math.pi * i / steps
        profile.append((w * math.cos(t), base + PASSAGE_SHOULDER + w * math.sin(t)))

    bm = bmesh.new()
    verts = [bm.verts.new((x, -depth * 0.5, z)) for x, z in profile]
    bm.faces.new(verts)
    bm.normal_update()
    ret = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    moved = [e for e in ret["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0.0, depth, 0.0), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    me = bpy.data.meshes.new("cutter")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(synth_material())
    ob = bpy.data.objects.new("cutter", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.rotation_mode = "XYZ"
    ob.rotation_euler = (0.0, 0.0, math.radians(
        {"+Y": 0.0, "-Y": 180.0, "+X": -90.0, "-X": 90.0}[side]))
    bpy.context.view_layer.update()
    return ob


def clip_to_cell(ob):
    """Trim anything outside the one-cell envelope.

    The plug is deliberately oversized so it laps into the floor, roof and
    side walls rather than leaving a hairline of daylight at its edges. Left
    alone it also laps OUT of the module, and a sealed side faces a real
    neighbouring corridor, so a slab of stone would jut through that corridor's
    wall. Overlap inside the module is wanted; overlap outside it is not, so
    the finished piece is cut back to the cell it occupies.
    """
    half = CELL * 0.5
    planes = (
        ((half, 0.0, 0.0), (1.0, 0.0, 0.0)),
        ((-half, 0.0, 0.0), (-1.0, 0.0, 0.0)),
        ((0.0, half, 0.0), (0.0, 1.0, 0.0)),
        ((0.0, -half, 0.0), (0.0, -1.0, 0.0)),
        ((0.0, 0.0, -FLOOR_DEPTH - 0.15), (0.0, 0.0, -1.0)),
        ((0.0, 0.0, HEIGHT), (0.0, 0.0, 1.0)),
    )
    me = ob.data
    for co, no in planes:
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.bisect_plane(
            bm,
            geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
            plane_co=co,
            plane_no=no,
            clear_outer=True,
        )
        bm.to_mesh(me)
        bm.free()


def add_floor(ob):
    """Lay a full-cell slab under the module's own floor.

    The pieces are scaled so their BOUNDING BOX is one cell, but the box is
    set by whatever sticks out furthest, and on these the roof overhangs the
    walls. So the floor stops short of the boundary -- measured at 42-67%
    coverage in a ring around the edge -- and every join in the level has a
    slot the player can see down. That is the "large gaps in the stone".

    Scaling the piece up until the floor reaches instead would push the roof
    out past the cell and into the neighbour, where `clip_to_cell` would cut
    it off and trade a hole in the floor for one in the ceiling.

    Height comes from the module's own floor rather than from zero: the slab
    has to sit at or just under the real walking surface, low enough never to
    poke through it and high enough not to leave a step at every seam.
    """
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    tree = BVHTree.FromBMesh(bm)
    half = CELL * 0.5
    heights = []
    for i in range(24):
        for j in range(24):
            x = -half + CELL * (i + 0.5) / 24.0
            y = -half + CELL * (j + 0.5) / 24.0
            hit = tree.ray_cast((x, y, HEIGHT * 0.45), (0, 0, -1), HEIGHT)
            if hit[0] is not None:
                heights.append(hit[0].z)
    bm.free()
    heights.sort()
    # Low decile, not the minimum: one stray dip would drop the whole slab.
    z = heights[len(heights) // 10] - 0.02 if heights else 0.0

    # A BOX, not a quad.
    #
    # A single plane has no underside, so anywhere the eye catches it edge-on
    # -- a seam, a ragged wall foot, a neighbour a centimetre lower -- the
    # line of sight passes straight out of the level. Measured: below the
    # floor plane every module was open on all four sides. Giving the patch
    # depth means a mismatch shows stone instead of the void.
    slot = synth_slot(ob)
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    corners = ((-half, -half), (half, -half), (half, half), (-half, half))
    top = [bm.verts.new((x, y, z)) for x, y in corners]
    bottom = [bm.verts.new((x, y, z - FLOOR_DEPTH)) for x, y in corners]
    made = [bm.faces.new(top), bm.faces.new(list(reversed(bottom)))]
    for i in range(4):
        j = (i + 1) % 4
        made.append(bm.faces.new([top[j], top[i], bottom[i], bottom[j]]))
    for f in made:
        f.material_index = slot
        f.smooth = False
    bmesh.ops.recalc_face_normals(bm, faces=made)
    bm.to_mesh(me)
    bm.free()
    return z


def add_lid(ob):
    """Cap the module so the player can never look up into the skybox.

    Four of the five pieces came back open-topped -- Tripo builds interiors as
    doll's-house cutaways so the camera can see in, and the ribbed vaults are
    decoration hanging below an open roof, not a surface. Measured: every
    walkable column in cross, tee and corner had nothing solid above it.

    The cap goes on after decimation, because a two-triangle quad is exactly
    what a collapse pass throws away first.
    """
    half = CELL * 0.5
    slot = synth_slot(ob)
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    z = HEIGHT - 0.01
    verts = [bm.verts.new((x, y, z)) for x, y in
             ((-half, -half), (half, -half), (half, half), (-half, half))]
    # Wound so the visible side faces down, into the corridor.
    face = bm.faces.new(list(reversed(verts)))
    face.material_index = slot
    face.smooth = False
    bm.to_mesh(me)
    bm.free()


## Faces meeting at more than this angle keep a hard edge; below it they are
## shaded smooth. Stone blocks want crisp arrises, the curve of a vault wants
## no seams, and ~45 degrees separates the two on these meshes.
SMOOTH_ANGLE = 45.0


def clean_shading(ob):
    """Throw away the imported normals and shade from the actual geometry.

    The glTF importer stores Tripo's vertex normals as custom split normals.
    Those were authored for Tripo's original mesh, and after the booleans,
    plugs, scaling and any decimation they no longer describe the surface
    they sit on. The mismatch shows up as shading that breaks along triangle
    edges -- the "stones look like triangles" complaint -- because the
    tangent-space normal map is applied on top of a normal that is wrong for
    that triangle. Recomputing from the geometry makes the two agree again.
    """
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    try:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    except Exception as err:
        print("      (custom normals: %s)" % err)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(SMOOTH_ANGLE))
    except Exception:
        bpy.ops.object.shade_smooth()


## Triangle budget for the collision copy.
##
## 2,500 was measured as too few. Collapse decimation moves the surface, and at
## that budget it bridged recesses with big flat triangles: one stood 1.28 m
## in front of the plugged archway at the back of the dead end -- an invisible
## wall -- and others left a pier's face or a ledge out entirely, so the
## player's head could go into stone. `tools/verify_collision.py` finds these
## by casting the same rays at both meshes. The shape is shared per kind, so
## this costs six trimeshes whatever the map size.
COLLISION_TRIS = 7000


def export_collision(ob, name):
    """Write a walls-only collision mesh next to the render mesh.

    The level used to collide against boxes derived from the grid, placed at
    the CELL BOUNDARY. The visible wall face is inside the cell -- 1.90 m from
    the centre on a straight, against a boundary at 3.0 m -- so the player
    could walk more than a metre into solid-looking stone. Colliding with the
    module's own surface is the only way that stays right for every piece,
    ragged Tripo stone and bored archways included.

    Floors are stripped out: the player walks on one flat slab, which keeps
    footing steady over broken paving and gives the navmesh a clean plane.
    """
    col = ob.copy()
    col.data = ob.data.copy()
    col.name = "collision_" + name
    bpy.context.scene.collection.objects.link(col)
    me = col.data
    bm = bmesh.new()
    bm.from_mesh(me)
    floors = [f for f in bm.faces
              if f.normal.z > 0.55 and f.calc_center_median().z < 0.6]
    bmesh.ops.delete(bm, geom=floors, context="FACES")
    bm.to_mesh(me)
    bm.free()
    me.materials.clear()
    decimate(col, COLLISION_TRIS)

    bpy.ops.object.select_all(action="DESELECT")
    col.select_set(True)
    bpy.context.view_layer.objects.active = col
    out = os.path.join(KIT, "module_%s_col.glb" % name)
    bpy.ops.export_scene.gltf(
        filepath=out, use_selection=True, export_format="GLB",
        export_materials="NONE", export_texcoords=False, export_normals=False)
    tris = sum(len(p.vertices) - 2 for p in col.data.polygons)
    bpy.data.objects.remove(col)
    print("      collision %d tris (%d floor faces stripped)" % (tris, len(floors)))


def decimate(ob, budget):
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris <= budget:
        return tris
    mod = ob.modifiers.new("dec", "DECIMATE")
    mod.ratio = budget / float(tris)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="dec")
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def weld(ob):
    """Tripo leaves coincident unwelded vertices; decimating before welding
    shatters the mesh into loose shards instead of simplifying it."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges)
    bm.to_mesh(me)
    bm.free()


def grey_albedo(amount, lift, contrast):
    """Rework the base-colour maps into rustic, weathered dark stone.

    Three things happen here, and each is doing a different job.

    DESATURATE. Tripo returns warm sepia stone whatever the prompt asks for,
    and the brief is dark grey brick. Tinting in the engine cannot fix that --
    albedo colour is a multiply, so it can darken the brown or cool it, but it
    cannot take the brown out. Note this is deliberately PARTIAL: taking it all
    the way to neutral gives flat, even, poured-concrete stone, which is the
    opposite of rustic. The leftover colour variation is the grime.

    CONTRAST. Weathered masonry is mostly about the difference between a clean
    face and a dirty recess. Pushing contrast about the midpoint deepens the
    mortar lines and the staining that the scan already contains, which reads
    as age far more cheaply than any extra geometry would.

    DARKEN. `lift` sets where the whole thing sits, so the corridors stay dim
    without the engine having to crush them later.
    """
    for img in bpy.data.images:
        if img.size[0] <= 0 or "Color" not in img.name:
            continue
        px = np.empty(img.size[0] * img.size[1] * img.channels, dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(-1, img.channels)
        rgb = px[:, :3]
        luma = (rgb * np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)).sum(axis=1)
        out = rgb * (1.0 - amount) + luma[:, None] * amount
        # Contrast about the midpoint, then place it. Clipped, because a
        # negative albedo silently turns into nonsense further down the chain.
        out = (out - 0.5) * contrast + 0.5
        px[:, :3] = np.clip(out * lift, 0.0, 1.0)
        img.pixels.foreach_set(px.reshape(-1))
        img.update()


def shrink_textures(px):
    """Cap every texture's longest side at `px`.

    Tripo ships 2K maps. Five modules would be fine; the grafted ones carry
    two sets each, because the plug brings the donor's material with it, and
    a 2 GB card does not have room to be careless about that.
    """
    for img in bpy.data.images:
        if img.size[0] <= 0:
            continue
        longest = max(img.size)
        if longest <= px:
            continue
        scale = px / float(longest)
        img.scale(max(1, int(img.size[0] * scale)), max(1, int(img.size[1] * scale)))


def save(ob, name):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    out = os.path.join(KIT, "module_%s.glb" % name)
    bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_format="GLB")
    lo, hi = bounds(ob)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print("  module_%-9s %6d tris   %.2f x %.2f x %.2f   floor at %.3f"
          % (name, tris, hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, lo.z))
    return out


def build(name, source, yaw, seals, widen=()):
    clear()
    ob = import_glb(os.path.join(KIT, source))
    weld(ob)
    if yaw:
        spin(ob, yaw)
    fit_cell(ob)
    # Widen BEFORE sealing, never after.
    #
    # Sealing joins the plug on as a second overlapping shell and the clip
    # then leaves open boundaries, so the result is neither manifold nor
    # free of self-intersections. The exact boolean solver quietly produces
    # nonsense on that -- it grew the bounding box to the cutter's length and
    # left two modules with no openings at all -- while the unsealed cross
    # cut perfectly. The sides being widened and the sides being plugged are
    # disjoint anyway, so the order costs nothing.
    floor_h = measure_floor(ob)
    floor_h = stretch_to_full_height(ob, floor_h)
    if widen:
        widen_passages(ob, widen, floor_h)
    if seals:
        plug = make_plug(os.path.join(KIT, "mod_tee.glb"))
        weld(plug)
        # Re-fit is not wanted here: make_plug parked the master at the origin
        # and `seal` scales each copy to the face it covers.
        for side in seals:
            ob = seal(ob, plug, side)
        bpy.data.objects.remove(plug)
    # Unconditionally, not just when a plug was added: the exact boolean
    # occasionally leaves a cutter behind as loose geometry, which showed up
    # as the cross growing to the cutter's 8.4 m length.
    sink_floor_to_zero(ob, floor_h)
    clip_to_cell(ob)
    weld(ob)
    # Collision comes from the finished shape, before the lid and floor slab
    # go on: neither is something the player should ever collide with.
    export_collision(ob, name)
    decimate(ob, TRI_BUDGET)
    clean_shading(ob)
    add_lid(ob)
    floor_z = add_floor(ob)
    grey_albedo(GREY_AMOUNT, GREY_LIFT, GREY_CONTRAST)
    shrink_textures(TEXTURE_PX)
    print("      floor slab at z = %.3f" % floor_z)
    save(ob, name)


print("building modules at %d tris, cell %.1f m, height %.1f m" % (TRI_BUDGET, CELL, HEIGHT))
# mod_straight opens on +/-X, so a quarter turn puts its run on +/-Y.
build("straight", "mod_straight.glb", 90.0, [])
# mod_corner is open on all four sides: the cross, used as-is.
build("cross", "mod_corner.glb", 0.0, [], ["+Y", "-Y", "+X", "-X"])
build("tee", "mod_corner.glb", 0.0, ["-X"], ["+Y", "-Y", "+X"])
build("corner", "mod_corner.glb", 0.0, ["-X", "-Y"], ["+Y", "+X"])
build("dead", "mod_corner.glb", 0.0, ["-X", "-Y", "+X"], ["+Y"])
# mod_gate opens on +X with its doors opposite; a quarter turn faces it north.
# It also came back with a small gap on one flank -- 7% of sight lines clear,
# not an archway but enough to see through -- so that side is plugged too.
build("gate", "mod_gate.glb", 90.0, ["+X"])
print("done")







