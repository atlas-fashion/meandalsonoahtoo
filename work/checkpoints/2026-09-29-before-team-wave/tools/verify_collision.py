"""Does each module's collision sit on its visible stone?

    blender -b -P tools/verify_collision.py

For every module, casts the same horizontal rays at the render mesh and at the
walls-only collision mesh and compares where each one stops.

    WALK-IN     collision further away than the stone: the player's body
                goes into rock that looks solid. This was over a metre before
                collision came from the modules themselves.
    STAND-OFF   collision nearer than the stone: an invisible wall in front
                of a visible one.

This exists because the in-game check compared collision against a single
measured wall distance, taken at one height, and reported a 0.47 m stand-off
that could equally have been a stone jutting out lower down. Comparing the two
meshes along the SAME ray answers the question the player actually asks --
"am I touching what I can see?" -- instead of comparing against a reference.

Rays are only counted where BOTH meshes are hit within the cell: a ray that
leaves through an archway says nothing about collision either way.
"""
import os
import sys
import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT = os.path.join(HERE, "models", "kit")
KINDS = ("straight", "corner", "tee", "cross", "dead", "gate")
## From knee height up. Lower rays hit rubble lying on the floor, which the
## collision deliberately does not have -- everyone walks on one flat slab --
## so a "mismatch" there is floor clutter under the feet, not a wall.
HEIGHTS = (0.8, 1.2, 1.7, 2.4)
OFFSETS = [(-0.45 + i * 0.075) * 6.0 for i in range(13)]
DIRS = ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0))
## Tolerances. Walk-in is the one that matters most -- the player's capsule
## has a radius, so a few centimetres of it is invisible in play. Stand-off is
## allowed a little more, because a 2,500-triangle hull rides slightly proud
## of sharp stone arrises by construction.
WALK_IN_OK = 0.12
STAND_OFF_OK = 0.25


def tree_of(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bm = bmesh.new()
    for o in meshes:
        me = o.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
        me.transform(o.matrix_world)
        bm.from_mesh(me)
    bm.normal_update()
    return BVHTree.FromBMesh(bm)


def main():
    bad = 0
    for kind in KINDS:
        render = tree_of(os.path.join(KIT, "module_%s.glb" % kind))
        col = tree_of(os.path.join(KIT, "module_%s_col.glb" % kind))
        worst_in = 0.0
        worst_off = 0.0
        where_in = where_off = None
        over_in = over_off = 0
        compared = 0
        for h in HEIGHTS:
            for off in OFFSETS:
                for d in DIRS:
                    if d[0] != 0:
                        origin = Vector((0.0, off, h))
                    else:
                        origin = Vector((off, 0.0, h))
                    dv = Vector(d)
                    a = render.ray_cast(origin, dv, 3.2)
                    b = col.ray_cast(origin, dv, 3.2)
                    if a[0] is None or b[0] is None:
                        continue
                    compared += 1
                    # NOT the difference in ray distance. That is
                    # discontinuous at every silhouette edge: a ray grazing a
                    # pier's side face hits the pier at 1.4 m or skims past to
                    # the back wall at 2.8 m depending on a few centimetres of
                    # edge position, and the first version of this test
                    # reported those as metre-scale errors in both directions
                    # at once. What matters is surface-to-surface:
                    #
                    #   walk-in   = how far the stone the player SEES is from
                    #               the nearest collision. Large means their
                    #               body can go into that stone.
                    #   stand-off = how far the collision that STOPS them is
                    #               from the nearest visible stone. Large means
                    #               an invisible wall.
                    near_col = col.find_nearest(a[0])
                    near_ren = render.find_nearest(b[0])
                    walk_in = near_col[3] if near_col[0] is not None else 9.9
                    stand_off = near_ren[3] if near_ren[0] is not None else 9.9
                    if walk_in > worst_in:
                        worst_in, where_in = walk_in, (h, off, d, a[3], b[3], a[1].z)
                    if stand_off > worst_off:
                        worst_off, where_off = stand_off, (h, off, d, a[3], b[3], a[1].z)
                    over_in += walk_in > WALK_IN_OK
                    over_off += stand_off > STAND_OFF_OK
        ok = worst_in <= WALK_IN_OK and worst_off <= STAND_OFF_OK
        if not ok:
            bad += 1
        print("%s module_%-9s walk-in %.3f m (%d rays over)   stand-off %.3f m (%d over)   of %d"
              % ("ok  " if ok else "FAIL", kind, worst_in, over_in, worst_off, over_off, compared))
        for label, w in (("walk-in", where_in), ("stand-off", where_off)):
            if w is None:
                continue
            h, off, d, ra, rb, nz = w
            # The normal of the render surface the ray hit says what it was:
            # near-vertical (|z| small) is a wall; strongly up or down is a
            # floor lump, a step or a vault rib.
            print("       worst %-9s h=%.1f off=%+.2f dir=%s  render %.2f m  collision %.2f m  hit normal.z %+.2f"
                  % (label, h, off, d, ra, rb, nz))
    print("collision: %s" % ("all good" if bad == 0 else "%d PROBLEMS" % bad))
    if bad:
        sys.exit(1)


main()
