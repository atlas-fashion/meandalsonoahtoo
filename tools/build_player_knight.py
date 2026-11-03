"""Build models/player_knight.glb, the player's body, from the Meshy knight.

Source: models/source/knight/knight_meshy.glb -- Higgsfield's Meshy multi-image
to 3D, from the user's front and back views (knight_front.png, knight_back.png),
textured and auto-rigged (24 bones: Hips .. Head, Left/Right Shoulder, Arm,
ForeArm, Hand, UpLeg, Leg, Foot, ToeBase). 31k triangles, 1.70 m, T-pose,
facing glTF +Z.

What this does to it:
  - the molten cracks glow: an emission map cut out of the albedo where it is
    hot (bright, yellow-orange, saturated), so only the cracks shine;
  - the plate reads as metal: metallic 0.55, roughness 0.62 (Meshy gave 0 / 0.8);
  - the one-frame `clip0` action is dropped -- the game poses the bones itself
    (scripts/player_knight.gd);
  - textures stay 2048 or under, written as JPEG.

Run (Blender 5.2):
  blender -b --factory-startup -P tools/build_player_knight.py
then `godot --headless --import --path .`. Never hand-edit the output.
"""
import os
import sys

import bpy
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "models", "source", "knight", "knight_meshy.glb")
OUT = os.path.join(ROOT, "models", "player_knight.glb")
MAX_TEX = 2048

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

for act in list(bpy.data.actions):
    bpy.data.actions.remove(act)
for ob in bpy.context.scene.objects:
    if ob.animation_data:
        ob.animation_data_clear()

# Meshy's GLB carries a stray unskinned Icosphere beside the body; only the
# mesh bound to the armature is the knight.
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
skinned = [o for o in meshes if any(m.type == "ARMATURE" for m in o.modifiers)]
assert len(skinned) == 1, meshes
mesh = skinned[0]
for o in meshes:
    if o != mesh:
        print("dropped", o.name, tuple(round(d, 3) for d in o.dimensions), len(o.data.polygons), "faces")
        bpy.data.objects.remove(o)
mat = mesh.data.materials[0]
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
albedo_node = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
img = albedo_node.image
w, h = img.size
print("albedo", img.name, w, h)
if max(w, h) > MAX_TEX:
    img.scale(MAX_TEX, MAX_TEX * h // w)
    w, h = img.size

px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
r, g, b = px[..., 0], px[..., 1], px[..., 2]
mx = np.maximum(np.maximum(r, g), b)
mn = np.minimum(np.minimum(r, g), b)
sat = (mx - mn) / np.maximum(mx, 1e-4)
# Hot: bright, and yellow-orange (red over green over blue), and saturated.
hot = np.clip((mx - 0.55) / 0.25, 0.0, 1.0) * np.clip((sat - 0.45) / 0.2, 0.0, 1.0)
hot *= ((r >= g) & (g > b * 1.2)).astype(np.float32)
# A little bloom of the mask so a crack is not a single texel wide.
k = hot.copy()
for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
    k = np.maximum(k, np.roll(np.roll(hot, dy, 0), dx, 1) * 0.6)
emit = np.zeros_like(px)
emit[..., 0] = k * 1.0
emit[..., 1] = k * 0.42
emit[..., 2] = k * 0.08
emit[..., 3] = 1.0
print("hot texels %.2f%%" % (100.0 * float((k > 0.2).mean())))

eimg = bpy.data.images.new("knight_emission", w, h, alpha=False)
eimg.pixels[:] = emit.ravel()
eimg.file_format = "JPEG"
enode = nt.nodes.new("ShaderNodeTexImage")
enode.image = eimg
enode.interpolation = "Linear"
uv_link = next((l for l in albedo_node.inputs["Vector"].links), None)
if uv_link is not None:
    nt.links.new(uv_link.from_socket, enode.inputs["Vector"])
emit_in = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
nt.links.new(enode.outputs["Color"], emit_in)
if "Emission Strength" in bsdf.inputs:
    bsdf.inputs["Emission Strength"].default_value = 1.0
bsdf.inputs["Metallic"].default_value = 0.55
bsdf.inputs["Roughness"].default_value = 0.62
img.file_format = "JPEG"

if "--preview" in sys.argv:
    eimg.filepath_raw = os.path.join(sys.argv[-1], "knight_emission.png")
    eimg.file_format = "PNG"
    eimg.save()

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    export_animations=False,
    export_image_format="JPEG",
    export_jpeg_quality=88,
    export_yup=True,
)
print("wrote", OUT, os.path.getsize(OUT))
