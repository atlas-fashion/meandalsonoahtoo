"""Fit the Meshy sword to the player's sword pivot and export it as a GLB.

    blender -b --factory-startup -P tools/build_meshy_sword.py -- models/player_sword_meshy.glb

Source: models/source/meshy_sword/ (the FBX and its four 2K maps, exactly as
Meshy delivered them; the folder carries a .gdignore so Godot never imports
the raw FBX). The output is a BUILD ARTIFACT -- rebuild it, never hand-edit.

The pivot convention is the one tools/build_sword.py set for the old sword:
the sword lies along Blender +Z, which the glTF exporter turns into Godot +Y,
the axis `Head/SwordPivot` points down; the end of the pommel at 0 and the tip
at TIP = 2.65, so the swing animations, the hit box (0.45 -> 2.65 along +Y)
and the first-person framing all stay where they were. Blade width runs along
X, thickness along Blender Y (Godot Z).

Measured on the delivered mesh, not assumed: 46,442 triangles, 1.914 m long
on Blender Z, hilt at -Z (the 0.38 m crossguard slice is 0.4 m above the -Z
end; the tip slices narrow to 0.048 at +Z). One uniform scale (2.65 / 1.914)
keeps its proportions, so its blade is slimmer than the old one's.

Kept at full resolution: in this project decimating a generated mesh is what
broke its normal-mapped shading (see CLAUDE.md, "Full-resolution modules"),
and one viewmodel's triangles are not what this game is short of.
"""

import bpy
import os
import sys
from mathutils import Vector, Matrix

OUT = sys.argv[sys.argv.index("--") + 1]
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "models", "source", "meshy_sword")
FBX = os.path.join(SRC, "Meshy_AI_model.fbx")
MAPS = {
    "base": "Meshy_AI_sword_final_1_1001002531_texture.png",
    "normal": "Meshy_AI_texture_0_normal.png",
    "metallic": "Meshy_AI_texture_0_metallic.png",
    "roughness": "Meshy_AI_texture_0_roughness.png",
}
TIP = 2.65


def log(*a):
    print("[meshy_sword]", *a)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=FBX)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
if len(meshes) != 1:
    raise SystemExit("expected one mesh in the FBX, found %d" % len(meshes))
sword = meshes[0]
# Bake whatever transform the FBX carried into the vertices first.
sword.data.transform(sword.matrix_world)
sword.matrix_world = Matrix.Identity(4)
for o in list(bpy.data.objects):
    if o is not sword:
        bpy.data.objects.remove(o)

pts = [v.co.copy() for v in sword.data.vertices]
lo_z = min(p.z for p in pts)
hi_z = max(p.z for p in pts)
length = hi_z - lo_z

# The hilt must be at -Z: the widest slice (the crossguard) has to sit in the
# lower half. If a future download arrives the other way up, flip it.
def widest_slice_z():
    best, best_w = 0.0, -1.0
    for k in range(20):
        a0 = lo_z + length * k / 20.0
        a1 = lo_z + length * (k + 1) / 20.0
        sl = [p for p in pts if a0 <= p.z <= a1]
        if sl:
            w = max(p.x for p in sl) - min(p.x for p in sl)
            if w > best_w:
                best, best_w = (a0 + a1) * 0.5, w
    return best

if widest_slice_z() > (lo_z + hi_z) * 0.5:
    log("hilt was at +Z; turning the sword over")
    sword.data.transform(Matrix.Rotation(3.14159265358979, 4, 'X'))
    pts = [v.co.copy() for v in sword.data.vertices]
    lo_z = min(p.z for p in pts)
    hi_z = max(p.z for p in pts)

# Centre on the BLADE, not the bounding box: the guard and pommel are not
# symmetric, and the blade is what has to run down the pivot's axis.
blade = [p for p in pts if lo_z + length * 0.35 <= p.z <= lo_z + length * 0.85]
cx = (max(p.x for p in blade) + min(p.x for p in blade)) * 0.5
cy = (max(p.y for p in blade) + min(p.y for p in blade)) * 0.5
scale = TIP / length
fit = Matrix.Scale(scale, 4) @ Matrix.Translation(Vector((-cx, -cy, -lo_z)))
sword.data.transform(fit)
sword.data.update()

# A fresh material from the four delivered maps, so the result does not depend
# on whatever the FBX importer guessed.
mat = bpy.data.materials.new("SwordMeshy")
mat.use_nodes = True
nt = mat.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
out = nt.nodes.new("ShaderNodeOutputMaterial")
bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])


def image(key, colour):
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = bpy.data.images.load(os.path.join(SRC, MAPS[key]))
    node.image.colorspace_settings.name = "sRGB" if colour else "Non-Color"
    return node


nt.links.new(image("base", True).outputs["Color"], bsdf.inputs["Base Color"])
nt.links.new(image("metallic", False).outputs["Color"], bsdf.inputs["Metallic"])
nt.links.new(image("roughness", False).outputs["Color"], bsdf.inputs["Roughness"])
normal_map = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(image("normal", False).outputs["Color"], normal_map.inputs["Color"])
nt.links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
sword.data.materials.clear()
sword.data.materials.append(mat)

sword.name = "Sword"
sword.data.name = "Sword"
sword.data.calc_loop_triangles()
pts = [v.co for v in sword.data.vertices]
log("triangles:", len(sword.data.loop_triangles))
log("scale applied: %.4f" % scale)
for axis, i in (("x", 0), ("y", 1), ("z", 2)):
    log("bounds %s: %.4f -> %.4f" % (axis, min(p[i] for p in pts), max(p[i] for p in pts)))

bpy.ops.export_scene.gltf(
    filepath=OUT,
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
