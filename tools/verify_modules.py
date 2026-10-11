"""Check the built modules answer the two questions the maze depends on.

    PASSAGE  can the player walk out through each side that should be open,
             and is every side that should be shut actually solid?
    SKY      standing anywhere on the floor, is there something overhead?

Both are measured by casting rays at the mesh, not by filling a voxel grid.
An earlier version did use a grid, deciding solid-versus-air by counting
surface crossings down each column, and it was wrong twice over. First it
reported every module as having no walls at all: the roofs overhang, so a
flood from the middle escaped through an archway, wrapped around the OUTSIDE
of the piece while still inside its bounding box, and touched all four faces.
Then, once the modules were capped, the single lid sheet added one crossing to
every column and inverted solid and air everywhere. Parity needs a closed
surface; these are not closed surfaces. Rays do not care.

Run it after tools/build_modules.py:

    blender -b -P tools/verify_modules.py

Exits non-zero if any module disagrees with EXPECTED, so a bad rebuild is
noticed rather than shipped.
"""
import os
import sys
import bpy
import bmesh
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT = os.path.join(HERE, "models", "kit")

## Sides each module must be open on. Blender +Y is the maze's north; see
## the axis note in build_modules.py.
EXPECTED = {
    "straight": {"+Y", "-Y"},
    "cross": {"+X", "-X", "+Y", "-Y"},
    "tee": {"+X", "+Y", "-Y"},
    "corner": {"+X", "+Y"},
    "dead": {"+Y"},
    "gate": {"+Y"},
}

DIRS = {
    "+X": (1.0, 0.0, 0.0),
    "-X": (-1.0, 0.0, 0.0),
    "+Y": (0.0, 1.0, 0.0),
    "-Y": (0.0, -1.0, 0.0),
}

## Heights to sample a side at, in METRES ABOVE THE FLOOR SURFACE.
##
## Not fractions of the module any more. The old fractions started at 0.10 --
## about half a metre up -- which is above a gap at the base of a wall, so a
## "rectangular hole at the bottom of the wall" passed the test cleanly. They
## also could not be trusted low down: at a fixed fraction of the module, a
## ray can start buried inside the floor slab and report the wall as solid
## because it hit the floor.
##
## Measuring from the floor the player actually stands on fixes both. The
## bottom entries are ankle and knee height, where the reported holes are;
## the top ones are there because these pieces have parapets above their
## vaults and a wall open near the ceiling leaks torchlight between corridors.
BANDS_ABOVE_FLOOR = (0.06, 0.15, 0.30, 0.60, 1.20, 2.00, 3.00, 4.00)
## Lateral offsets across the mouth, as a fraction of the cell.
OFFSETS = (-0.24, -0.12, 0.0, 0.12, 0.24)
## A side counts as open when at least this fraction of its rays escape.
OPEN_AT = 0.20
## ...and as shut when at most this fraction do. Between the two is a fail:
## a side that is neither a clean doorway nor a solid wall is a light leak.
SHUT_AT = 0.04


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    tree = BVHTree.FromBMesh(bm)
    pts = [tuple(c) for c in ob.bound_box]
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    return tree, lo, hi, tris


def escapes(tree, origin, direction, reach):
    """True when a ray leaves the module without hitting anything."""
    loc, _n, _i, dist = tree.ray_cast(origin, direction, reach)
    return loc is None or dist >= reach - 1e-4


def check(name):
    path = os.path.join(KIT, "module_%s.glb" % name)
    tree, lo, hi, tris = load(path)
    size = [hi[i] - lo[i] for i in range(3)]
    cx = (lo[0] + hi[0]) * 0.5
    cy = (lo[1] + hi[1]) * 0.5
    reach = max(size[0], size[1])

    # Where the player's feet are, so the bands below mean what they say.
    down = tree.ray_cast((cx, cy, lo[2] + size[2] * 0.45), (0, 0, -1), size[2])
    floor_z = down[0].z if down[0] is not None else lo[2]

    open_frac = {}
    lowest_gap = {}
    for side, d in DIRS.items():
        hits = 0
        total = 0
        gap_at = -1.0
        for band in BANDS_ABOVE_FLOOR:
            z = floor_z + band
            if z >= hi[2]:
                continue
            for off in OFFSETS:
                # Step across the mouth on whichever axis the side is not on.
                if d[0] != 0.0:
                    origin = (cx, cy + size[1] * off, z)
                else:
                    origin = (cx + size[0] * off, cy, z)
                total += 1
                if escapes(tree, origin, d, reach):
                    hits += 1
                    if gap_at < 0.0:
                        gap_at = band
        open_frac[side] = hits / float(total)
        lowest_gap[side] = gap_at

    # Sky: find the floor under a grid of points, then look up from it.
    leaks = 0
    floors = 0
    steps = 24
    for i in range(steps):
        for j in range(steps):
            x = lo[0] + size[0] * (0.18 + 0.64 * i / (steps - 1.0))
            y = lo[1] + size[1] * (0.18 + 0.64 * j / (steps - 1.0))
            down = tree.ray_cast((x, y, lo[2] + size[2] * 0.45), (0, 0, -1), size[2])
            if down[0] is None:
                continue
            # Only floor counts; a hit high up is the top of a wall.
            if down[0].z > lo[2] + size[2] * 0.2:
                continue
            floors += 1
            if escapes(tree, (x, y, down[0].z + 0.15), (0, 0, 1), size[2] * 1.2):
                leaks += 1

    # Archway size, for the collision boxes. The corridor is not the full cell
    # wide: each opening has stone jambs, and collision that ignored them
    # would let the player stand inside the arch. Measured as the widest run
    # of adjacent clear rays across a known-open side, and the highest clear
    # band, both at a fine step.
    span = 0.0
    head = 0.0
    probe_side = sorted(EXPECTED[name])[0]
    d = DIRS[probe_side]
    steps = 61
    run = 0
    for i in range(steps):
        off = -0.5 + i / (steps - 1.0)
        z = floor_z + 0.9
        origin = (cx, cy + size[1] * off, z) if d[0] != 0.0 else (cx + size[0] * off, cy, z)
        if escapes(tree, origin, d, reach):
            run += 1
            span = max(span, run * (size[1] if d[0] != 0.0 else size[0]) / (steps - 1.0))
        else:
            run = 0
    for i in range(steps):
        z = lo[2] + size[2] * (i / (steps - 1.0))
        origin = (cx, cy, z)
        if escapes(tree, origin, d, reach):
            head = max(head, z - lo[2])

    # Widest clear span across SEVERAL heights, not the one band `span` used.
    # module_level.gd sizes the jamb filler that plugs the archway seam
    # (task 1 follow-up: fillers were sized off ARCH_WIDTH alone and turned
    # out wider than the real pier at some heights, so they stood in front of
    # it as visible slabs). The widest clear width at ANY height the filler
    # spans (floor to ~1.85 m) is the one that has to be respected everywhere.
    jamb_clear = span
    for jz in (0.2, 0.6, 1.2, 1.85):
        z = floor_z + jz
        if z >= hi[2]:
            continue
        run = 0
        this_span = 0.0
        for i in range(steps):
            off = -0.5 + i / (steps - 1.0)
            origin = (cx, cy + size[1] * off, z) if d[0] != 0.0 else (cx + size[0] * off, cy, z)
            if escapes(tree, origin, d, reach):
                run += 1
                this_span = max(this_span, run * (size[1] if d[0] != 0.0 else size[0]) / (steps - 1.0))
            else:
                run = 0
        jamb_clear = max(jamb_clear, this_span)

    # Floor coverage right out to the cell boundary.
    #
    # Modules are scaled so their BOUNDING BOX is exactly one cell, but the
    # bounding box is set by whatever sticks out furthest -- on these pieces
    # the roof overhangs the walls. If the floor slab stops short of the box,
    # every join in the level has a slot in it that the player can see down.
    # Sampled as a ring near the edge against the middle, because a hole in
    # the seam is invisible in an average taken over the whole cell.
    floor_edge = 0
    floor_edge_total = 0
    floor_mid = 0
    floor_mid_total = 0
    grid = 40
    for i in range(grid):
        for j in range(grid):
            fx = (i + 0.5) / grid
            fy = (j + 0.5) / grid
            x = lo[0] + size[0] * fx
            y = lo[1] + size[1] * fy
            hit = tree.ray_cast((x, y, lo[2] + size[2] * 0.45), (0, 0, -1), size[2])
            near_edge = min(fx, 1.0 - fx, fy, 1.0 - fy) < 0.06
            if near_edge:
                floor_edge_total += 1
                if hit[0] is not None:
                    floor_edge += 1
            else:
                floor_mid_total += 1
                if hit[0] is not None:
                    floor_mid += 1

    # Distance from the cell centre to the inside face of a solid wall, at
    # torch height. Needed to hang torches: the walls are inset from the cell
    # boundary by an unknown amount, so placing a torch a fixed distance from
    # the centre either buries it in stone or leaves it floating.
    wall_at = 0.0
    for side, d in DIRS.items():
        if side in EXPECTED[name]:
            continue
        origin = (cx, cy, floor_z + 2.3)
        hit = tree.ray_cast(origin, d, reach)
        if hit[0] is not None:
            wall_at = max(wall_at, hit[3])

    want = EXPECTED[name]
    problems = []
    for side in DIRS:
        f = open_frac[side]
        if side in want and f < OPEN_AT:
            problems.append("%s should be open (%.2f)" % (side, f))
        elif side not in want and f > SHUT_AT:
            problems.append("%s should be shut (%.2f)" % (side, f))
    if floors == 0:
        problems.append("no floor found")
    elif leaks:
        problems.append("%d of %d floor points see sky" % (leaks, floors))

    state = "ok  " if not problems else "FAIL"
    print("%s module_%-9s %5d tris  %.2f x %.2f x %.2f  open %s  sky-leak %d/%d"
          % (state, name, tris, size[0], size[1], size[2],
             ",".join(s for s in DIRS if open_frac[s] >= OPEN_AT) or "none",
             leaks, floors))
    print("       arch %.2f m wide, clear to %.2f m up" % (span, head))
    print("       jamb-safe clear width %.2f m (widest across floor-1.85m band)" % jamb_clear)
    print("       wall face at %.2f m from centre" % wall_at)
    print("       floor: middle %3.0f%%   EDGE RING %3.0f%%"
          % (100.0 * floor_mid / max(1, floor_mid_total),
             100.0 * floor_edge / max(1, floor_edge_total)))
    for p in problems:
        print("       - %s" % p)
    return not problems


ok = True
for name in ("straight", "corner", "tee", "cross", "dead", "gate"):
    ok = check(name) and ok
print("modules: %s" % ("all good" if ok else "PROBLEMS ABOVE"))
if not ok:
    sys.exit(1)


