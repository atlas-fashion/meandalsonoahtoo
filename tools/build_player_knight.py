"""Build models/player_knight.glb, the player's body, from the user's fantasy armor.

Source: models/source/armor/fantasy_armor.glb -- the user's "fantasy armor 3d
model" (Tripo): a knight in dark plate with glowing gold cracks, T-pose, facing
glTF +Z, 10.5k triangles, one 4096 albedo, NO skeleton, 0.845 high.

The rig is borrowed: models/source/knight/knight_meshy.glb (the molten rust
knight Meshy auto-rigged, note 155) has 24 bones with the names the game poses
(scripts/coop_avatar.gd, scripts/first_person_arms.gd) and the same T-pose
proportions (span / height 1.18 both). So:
  - the armor is scaled to the knight's 1.70 m and moved `NUDGE` back to sit on
    its bones (measured slice by slice, note 159);
  - that knight's skeleton is kept EXACTLY -- bone lengths and joints unchanged,
    so the arms' IK, the guard's measured lengths (note 158) and every pose hold;
  - each armor vertex takes the knight's skin weights at the nearest point of
    the knight's surface (barycentric), then a few passes of smoothing along the
    armor's own edges so a plate does not tear where two bones meet;
  - the knight's mesh is then dropped.

The look: an emission map cut out of the albedo where it is hot (bright,
yellow-orange, saturated) so only the cracks glow; metallic 0.55, roughness 0.62
(Tripo gave 0 / 0.9); albedo down to 2048, JPEG.

Run (Blender 5.2):
  blender -b --factory-startup -P tools/build_player_knight.py
then `godot --headless --import --path .`, then tools/build_player_knight_arms.py
(it reads this output). Never hand-edit the output.
"""
import os
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "models", "source", "armor", "fantasy_armor.glb")
RIG = os.path.join(ROOT, "models", "source", "knight", "knight_meshy.glb")
OUT = os.path.join(ROOT, "models", "player_knight.glb")
MAX_TEX = 2048
HEIGHT = 1.70
# Blender +Y is the knight's back. Slices through both at the same heights put
# the armor's torso and legs 2-4 cm ahead of the knight's, its arms 2 cm.
NUDGE = Vector((0.0, 0.025, 0.0))
SMOOTH_PASSES = 3
MAX_INFLUENCES = 4

bpy.ops.wm.read_factory_settings(use_empty=True)

# --- the rig, from the Meshy knight -------------------------------------------
bpy.ops.import_scene.gltf(filepath=RIG)
for act in list(bpy.data.actions):
    bpy.data.actions.remove(act)
for ob in bpy.context.scene.objects:
    if ob.animation_data:
        ob.animation_data_clear()
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
donor = next(o for o in meshes if any(m.type == "ARMATURE" for m in o.modifiers))
for o in meshes:
    if o != donor:
        bpy.data.objects.remove(o)
names = [g.name for g in donor.vertex_groups]
dmw = donor.matrix_world
dverts = [dmw @ v.co for v in donor.data.vertices]
dW = np.zeros((len(dverts), len(names)), dtype=np.float64)
for v in donor.data.vertices:
    for ge in v.groups:
        dW[v.index, ge.group] = ge.weight
dtris = []
donor.data.calc_loop_triangles()
for t in donor.data.loop_triangles:
    dtris.append(tuple(t.vertices))
bvh = BVHTree.FromPolygons(dverts, dtris)

# --- the armor ----------------------------------------------------------------
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=SRC)
new = [o for o in bpy.data.objects if o not in before]
mesh = next(o for o in new if o.type == "MESH")
mw = mesh.matrix_world.copy()
pts = [mw @ v.co for v in mesh.data.vertices]
zmin = min(p.z for p in pts)
zmax = max(p.z for p in pts)
s = HEIGHT / (zmax - zmin)
for v, p in zip(mesh.data.vertices, pts):
    v.co = Vector((p.x * s, p.y * s, (p.z - zmin) * s)) + NUDGE
mesh.data.update()
for o in new:
    if o != mesh:
        bpy.data.objects.remove(o)
mesh.parent = None
mesh.matrix_world = arm.matrix_world.inverted() @ arm.matrix_world  # identity
mesh.name = "knight"
mesh.data.name = "knight"
print("armor scaled x%.4f to %.2f m: %d vertices, %d faces" % (s, HEIGHT, len(mesh.data.vertices), len(mesh.data.polygons)))

# --- weights: the knight's, at the nearest point of its surface ----------------
av = [v.co.copy() for v in mesh.data.vertices]
W = np.zeros((len(av), len(names)), dtype=np.float64)
far = 0
for i, p in enumerate(av):
    loc, _n, ti, dist = bvh.find_nearest(p)
    a, b, c = (dverts[k] for k in dtris[ti])
    # Barycentric weights of `loc` in the triangle.
    v0, v1, v2 = b - a, c - a, loc - a
    d00, d01, d11 = v0.dot(v0), v0.dot(v1), v1.dot(v1)
    d20, d21 = v2.dot(v0), v2.dot(v1)
    den = d00 * d11 - d01 * d01
    if abs(den) < 1e-12:
        bw = (1.0, 0.0, 0.0)
    else:
        y = (d11 * d20 - d01 * d21) / den
        z = (d00 * d21 - d01 * d20) / den
        bw = (1.0 - y - z, y, z)
    for k, w in zip(dtris[ti], bw):
        W[i] += max(w, 0.0) * dW[k]
    if dist > 0.06:
        far += 1
print("weights from the knight: %d of %d vertices more than 6 cm from its surface" % (far, len(av)))

# Smooth along the armor's own edges.
edges = np.array([tuple(e.vertices) for e in mesh.data.edges], dtype=np.int64)
for _ in range(SMOOTH_PASSES):
    acc = W.copy()
    cnt = np.ones(len(av))
    np.add.at(acc, edges[:, 0], W[edges[:, 1]])
    np.add.at(acc, edges[:, 1], W[edges[:, 0]])
    np.add.at(cnt, edges[:, 0], 1.0)
    np.add.at(cnt, edges[:, 1], 1.0)
    W = 0.5 * W + 0.5 * acc / cnt[:, None]
# Keep the strongest four, normalised.
order = np.argsort(-W, axis=1)
for i in range(len(av)):
    keep = order[i, :MAX_INFLUENCES]
    row = np.zeros(len(names))
    row[keep] = W[i, keep]
    t = row.sum()
    W[i] = row / t if t > 0 else row

groups = [mesh.vertex_groups.new(name=n) for n in names]
for i in range(len(av)):
    for j in np.nonzero(W[i] > 1e-4)[0]:
        groups[j].add([i], float(W[i, j]), "REPLACE")
mesh.parent = arm
mesh.matrix_parent_inverse = arm.matrix_world.inverted()
mod = mesh.modifiers.new("Armature", "ARMATURE")
mod.object = arm
bpy.data.objects.remove(donor)

# --- material -------------------------------------------------------------------
mat = mesh.data.materials[0]
mat.name = "knight"
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
albedo_node = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
img = albedo_node.image
w, h = img.size
print("albedo", img.name, w, h)
# Exported as models/player_knight_Image_0.jpg, the name the Meshy knight's had,
# so its .import (VRAM compressed, mipmaps -- note 155) carries over.
img.name = "Image_0"
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
k = hot.copy()
for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
    k = np.maximum(k, np.roll(np.roll(hot, dy, 0), dx, 1) * 0.6)
emit = np.zeros_like(px)
# The cracks' own colour, so gold stays gold.
emit[..., 0] = k * r
emit[..., 1] = k * g
emit[..., 2] = k * b
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
