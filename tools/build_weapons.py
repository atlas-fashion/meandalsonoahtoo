"""Fit the user's sword and spear (his Blender files) to the player's weapon
conventions and export each as a GLB.

    blender -b --factory-startup -P tools/build_weapons.py -- sword models/sword.glb
    blender -b --factory-startup -P tools/build_weapons.py -- spear models/spear.glb

Sources: models/source/weapons/sword.blend and spear.blend, exactly as the user
made them (Tripo pieces kitbashed in Blender, textures packed; the folder is
under models/source/, which carries a .gdignore). The outputs are BUILD
ARTIFACTS -- rebuild them, never hand-edit. See docs/notes/163.

Each .blend holds one mesh standing along +Z, hilt / butt at the bottom.
Measured, not assumed: the script finds the long axis' ends and turns the mesh
over if the wide end (the guard, the spear's head) is the wrong way.

SWORD -- the convention build_meshy_sword.py set: along Blender +Z (Godot +Y,
the axis `Head/SwordPivot` points the sword down), the pommel's end at 0, the
tip at TIP = 2.65, the blade centred on the axis, its width along X. One
uniform scale. player.gd `_measure_sword` reads guard, pommel and tip off the
mesh, so nothing in code needs the numbers.

SPEAR -- spear.gd's convention: along Godot -Z (Blender +Y), the tip forward;
the hand at the origin, the butt's end at +BUTT (0.67, Godot +Z) and the tip at
-TIP_REACH (2.07), the shaft centred on the axis, the blade's flat along X. Its
three materials are named SpearShaft / SpearSocket / SpearBlade so spear.gd can
light the head when it is thrown.
"""

import bpy
import os
import sys
from mathutils import Vector, Matrix

ARGS = sys.argv[sys.argv.index("--") + 1:]
KIND, OUT = ARGS[0], ARGS[1]
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "models", "source", "weapons", KIND + ".blend")

SWORD_TIP = 2.65
SPEAR_BUTT = 0.67
SPEAR_TIP = 2.07
# The spear's materials, by the Tripo name each piece arrived with.
SPEAR_MATS = {
    "tripo_mat_f62a1a4d": "SpearShaft",
    "tripo_mat_ffd16e72": "SpearSocket",
    "tripo_mat_4faf9576": "SpearBlade",
}
SWORD_MATS = {
    "tripo_mat_a6864adb": "SwordBlade",
    "tripo_mat_4859e0b7": "SwordHilt",
}


def log(*a):
    print("[weapons:%s]" % KIND, *a)


bpy.ops.wm.open_mainfile(filepath=SRC, load_ui=False, use_scripts=False)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
if len(meshes) != 1:
    raise SystemExit("expected one mesh in %s, found %d" % (SRC, len(meshes)))
obj = meshes[0]
for o in list(bpy.data.objects):
    if o is not obj:
        bpy.data.objects.remove(o)
obj.parent = None
obj.data.transform(obj.matrix_world)
obj.matrix_world = Matrix.Identity(4)
me = obj.data


def bounds():
    pts = [v.co for v in me.vertices]
    return (Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))),
            Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))))


lo, hi = bounds()
length = hi.z - lo.z


def slab(a, b):
    """Vertices whose height is between fractions a and b of the length."""
    z0, z1 = lo.z + length * a, lo.z + length * b
    return [v.co for v in me.vertices if z0 <= v.co.z <= z1]


def width(pts):
    return max(p.x for p in pts) - min(p.x for p in pts) if pts else 0.0


# The sword's guard is its widest slice and must be in the lower half; the
# spear's head (socket and blade) is wider than the haft and must be on top.
widest = max(range(20), key=lambda k: width(slab(k / 20.0, (k + 1) / 20.0)))
flip = widest >= 10 if KIND == "sword" else widest < 10
if flip:
    log("upside down; turning it over")
    me.transform(Matrix.Rotation(3.14159265358979, 4, 'X'))
    lo, hi = bounds()

# Centre on the part that must run down the axis: the blade, or the haft.
core = slab(0.4, 0.8) if KIND == "sword" else slab(0.3, 0.7)
cx = (max(p.x for p in core) + min(p.x for p in core)) * 0.5
cy = (max(p.y for p in core) + min(p.y for p in core)) * 0.5

if KIND == "sword":
    scale = SWORD_TIP / length
    fit = Matrix.Scale(scale, 4) @ Matrix.Translation(Vector((-cx, -cy, -lo.z)))
    names = SWORD_MATS
else:
    scale = (SPEAR_BUTT + SPEAR_TIP) / length
    # Butt at Blender y = -BUTT (Godot +Z), tip at +TIP (Godot -Z).
    turn = Matrix.Rotation(-3.14159265358979 * 0.5, 4, 'X')
    fit = (Matrix.Translation(Vector((0.0, -SPEAR_BUTT, 0.0))) @ turn @ Matrix.Scale(scale, 4)
           @ Matrix.Translation(Vector((-cx, -cy, -lo.z))))
    names = SPEAR_MATS
me.transform(fit)
me.update()

for slot in me.materials:
    if slot is not None and slot.name in names:
        slot.name = names[slot.name]
used = {m.name for m in me.materials if m is not None}
missing = set(names.values()) - used
if missing:
    raise SystemExit("materials not found: %s (have %s)" % (sorted(missing), sorted(used)))

obj.name = KIND.capitalize()
me.name = KIND.capitalize()
me.calc_loop_triangles()
log("triangles:", len(me.loop_triangles))
log("scale applied: %.5f" % scale)
lo, hi = bounds()
for axis, i in (("x", 0), ("y", 1), ("z", 2)):
    log("bounds %s: %.4f -> %.4f" % (axis, lo[i], hi[i]))
if KIND == "sword":
    # What player.gd `_measure_sword` will find: the guard as the mean height of
    # the outermost vertices on X.
    left = min(me.vertices, key=lambda v: v.co.x).co
    right = max(me.vertices, key=lambda v: v.co.x).co
    log("guard at %.4f (pommel 0, tip %.4f)" % ((left.z + right.z) * 0.5, hi.z))
for m in me.materials:
    imgs = [n.image for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image]
    log("material", m.name, [(im.name, tuple(im.size)) for im in imgs])

bpy.ops.export_scene.gltf(
    filepath=os.path.abspath(OUT),
    export_format='GLB',
    export_animations=False,
    export_skins=False,
    export_apply=False,
    export_yup=True,
    export_materials='EXPORT',
    export_image_format='AUTO',
    use_selection=False,
)
log("wrote", OUT)
