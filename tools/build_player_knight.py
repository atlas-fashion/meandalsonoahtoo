"""Build models/player_knight.glb, the player's body, from the user's dark knight.

Source: models/source/armor/dark_knight.glb -- the user's "dark fantasy armored
knight 3d model" (Tripo, note 166): blackened plate with gold seams and a torn
cloth tabard, T-pose, facing glTF +Z, 31k triangles, one 4096 albedo and
nothing else (no normal, roughness or metal maps), NO skeleton, 0.854 high.
(Note 159's fantasy armor, models/source/armor/fantasy_armor.glb, was built the
same way and is kept beside it.)

The rig is borrowed: models/source/knight/knight_meshy.glb (the molten rust
knight Meshy auto-rigged, note 155) has 24 bones with the names the game poses
(scripts/coop_avatar.gd, scripts/first_person_arms.gd) and the same T-pose
proportions (span / height 1.18; this knight 1.17). So:
  - the armor is scaled to the knight's 1.70 m and moved `NUDGE` back to sit on
    its bones, the arms `ARM_NUDGE` more (this knight holds its arms 3.5 cm
    further forward than the last; slices, note 166);
  - that knight's skeleton is kept EXACTLY -- bone lengths and joints unchanged,
    so the arms' IK, the guard's measured lengths (note 158) and every pose hold;
  - each armor vertex takes the knight's skin weights at the nearest point of
    the knight's surface (barycentric), then a few passes of smoothing along the
    armor's own edges so a plate does not tear where two bones meet;
  - WELDED: Tripo splits a vertex wherever its UVs do (36k vertices, 16k
    places), and this atlas is thousands of tiny islands. Weights are worked out
    per PLACE, smoothed over the welded edges, and every copy of a place gets
    the same weights -- otherwise the copies drift apart under the bones and
    the seams open into holes;
  - the knight's mesh is then dropped;
  - FINGERS (note 169): the borrowed rig has none, so each hand gets them here --
    a three-joint chain for the four fingers (one plate of gauntlet: they move
    as one) from the knuckle line out, and a two-joint thumb along the front of
    the palm -- and the gauntlet's finger and thumb vertices are skinned to them
    (`FINGER_JOINTS`, `THUMB_JOINTS`). first_person_arms.gd curls them round
    whatever the hand holds.

The look -- Tripo gave only colour (metallic 0, roughness 0.9, flat). Baked here
in Cycles, in the T-pose:
  - a normal map: a bump from a height worked out of the albedo (dark grime and
    carving low, the gold seams lowest, as grooves between plates);
  - ambient occlusion;
  - roughness and metal from the albedo: the gold seams polished gold metal,
    the blackened plate worn steel (rougher where darker, in grime and in the
    occluded creases). The tabard is welded to the body, so it is metal too.
Packed as glTF ORM (R occlusion, G roughness, B metal). Albedo and normal stay
4096 (the gauntlets are a hand's breadth from the eye), ORM 2048, all JPEG.
Double-sided: the tabard is one sheet of cloth.

Run (Blender 5.2):
  blender -b --factory-startup -P tools/build_player_knight.py
then `godot --headless --import --path .`. Never hand-edit the output.
"""
import os
import sys

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "models", "source", "armor", "dark_knight.glb")
RIG = os.path.join(ROOT, "models", "source", "knight", "knight_meshy.glb")
OUT = os.path.join(ROOT, "models", "player_knight.glb")
TEX = 4096
ORM_TEX = 2048
HEIGHT = 1.70
# Blender +Y is the knight's back. Slices put the torso at the old armor's
# (note 159: 2.5 cm back onto the knight), the arms 3.5 cm further forward than
# its, so they go back that much more, faded in across the shoulder.
NUDGE = Vector((0.0, 0.025, 0.0))
ARM_NUDGE = 0.035
ARM_FADE = (0.22, 0.40)
SMOOTH_PASSES = 3
MAX_INFLUENCES = 4
WELD = 1e-5
# The hand (Blender space, the T-pose: arms along X, +Y the back, the palm down),
# from slices of the gauntlet (note 169): it runs from the wrist at |x| 0.76 to
# the fingertips at 0.995; the fingers are everything past the knuckle line
# (|x| > KNUCKLE), 18 cm across front to back, their middle at FINGER_Z; the
# thumb hangs forward of the palm and below it (y < THUMB_Y, z < THUMB_Z) between
# |x| 0.84 and 0.93.
KNUCKLE = 0.935
FINGER_Z = 1.345
FINGER_Y = 0.075
# The finger chain's joints along |x| (knuckle, middle, last, tip) and the blend
# either side of each joint (m).
FINGER_JOINTS = (0.935, 0.957, 0.976, 0.996)
FINGER_BLEND = 0.005
# The thumb's joints (|x|, y, z): its root, its knuckle, its tip.
THUMB_JOINTS = ((0.858, -0.004, 1.306), (0.888, -0.024, 1.292), (0.918, -0.040, 1.281))
THUMB_Y = 0.003
THUMB_Z = 1.33
THUMB_X = (0.84, 0.93)
# The bump: metres of relief over the height's 0..1.
BUMP_DISTANCE = 0.0018
BAKE_SAMPLES = 64
# How far the occlusion looks (m).
AO_DISTANCE = 0.12

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


def arm_fade(x: float) -> float:
    t = (abs(x) - ARM_FADE[0]) / (ARM_FADE[1] - ARM_FADE[0])
    t = min(max(t, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


for v, p in zip(mesh.data.vertices, pts):
    q = Vector((p.x * s, p.y * s, (p.z - zmin) * s)) + NUDGE
    q.y += ARM_NUDGE * arm_fade(q.x)
    v.co = q
mesh.data.update()
for o in new:
    if o != mesh:
        bpy.data.objects.remove(o)
mesh.parent = None
mesh.matrix_world = arm.matrix_world.inverted() @ arm.matrix_world  # identity
mesh.name = "knight"
mesh.data.name = "knight"
print("armor scaled x%.4f to %.2f m: %d vertices, %d faces" % (s, HEIGHT, len(mesh.data.vertices), len(mesh.data.polygons)))

# --- welded places --------------------------------------------------------------
av = [v.co.copy() for v in mesh.data.vertices]
key = {}
place = np.zeros(len(av), dtype=np.int64)
for i, p in enumerate(av):
    k = (round(p.x / WELD), round(p.y / WELD), round(p.z / WELD))
    place[i] = key.setdefault(k, len(key))
n_places = len(key)
first = np.full(n_places, -1, dtype=np.int64)
for i in range(len(av)):
    if first[place[i]] < 0:
        first[place[i]] = i
print("welded: %d vertices are %d places" % (len(av), n_places))

# --- weights: the knight's, at the nearest point of its surface ----------------
W = np.zeros((n_places, len(names)), dtype=np.float64)
far = 0
for pi in range(n_places):
    p = av[first[pi]]
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
        W[pi] += max(w, 0.0) * dW[k]
    if dist > 0.06:
        far += 1
print("weights from the knight: %d of %d places more than 6 cm from its surface" % (far, n_places))

# Smooth along the welded edges.
edges = np.array([tuple(e.vertices) for e in mesh.data.edges], dtype=np.int64)
pe = place[edges]
pe = pe[pe[:, 0] != pe[:, 1]]
for _ in range(SMOOTH_PASSES):
    acc = W.copy()
    cnt = np.ones(n_places)
    np.add.at(acc, pe[:, 0], W[pe[:, 1]])
    np.add.at(acc, pe[:, 1], W[pe[:, 0]])
    np.add.at(cnt, pe[:, 0], 1.0)
    np.add.at(cnt, pe[:, 1], 1.0)
    W = 0.5 * W + 0.5 * acc / cnt[:, None]
# Keep the strongest four, normalised.
order = np.argsort(-W, axis=1)
for i in range(n_places):
    keep = order[i, :MAX_INFLUENCES]
    row = np.zeros(len(names))
    row[keep] = W[i, keep]
    t = row.sum()
    W[i] = row / t if t > 0 else row

groups = [mesh.vertex_groups.new(name=n) for n in names]
for i in range(len(av)):
    row = W[place[i]]
    for j in np.nonzero(row > 1e-4)[0]:
        groups[j].add([i], float(row[j]), "REPLACE")

mesh.parent = arm
mesh.matrix_parent_inverse = arm.matrix_world.inverted()
mod = mesh.modifiers.new("Armature", "ARMATURE")
mod.object = arm
bpy.data.objects.remove(donor)


# --- fingers (note 169) -------------------------------------------------------------
def lin(u: float, a: float, b: float) -> float:
    return min(max((u - a) / (b - a), 0.0), 1.0)


def finger_weights(u: float) -> list:
    """[hand, finger 1, 2, 3] at `u` metres past the knuckle line."""
    j = [x - FINGER_JOINTS[0] for x in FINGER_JOINTS]
    b = FINGER_BLEND
    s1 = lin(u, j[0] - b, j[0] + b)
    s2 = lin(u, j[1] - b, j[1] + b)
    s3 = lin(u, j[2] - b, j[2] + b)
    return [1.0 - s1, s1 * (1.0 - s2), s2 * (1.0 - s3), s3]


def thumb_weights(p: Vector, side: float) -> list:
    """[hand, thumb 1, thumb 2] along the thumb from its root."""
    a = Vector((side * THUMB_JOINTS[0][0], THUMB_JOINTS[0][1], THUMB_JOINTS[0][2]))
    k = Vector((side * THUMB_JOINTS[1][0], THUMB_JOINTS[1][1], THUMB_JOINTS[1][2]))
    t = Vector((side * THUMB_JOINTS[2][0], THUMB_JOINTS[2][1], THUMB_JOINTS[2][2]))
    run = (p - a).dot((t - a).normalized()) / (t - a).length
    mid = (k - a).length / (t - a).length
    s1 = lin(run, -0.1, 0.1)
    s2 = lin(run, mid - 0.1, mid + 0.1)
    return [1.0 - s1, s1 * (1.0 - s2), s2]


bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
to_arm = arm.matrix_world.inverted()
new_bones = {}
for side, pre in ((1.0, "Left"), (-1.0, "Right")):
    hand = arm.data.edit_bones[pre + "Hand"]
    parent = hand
    for k in range(3):
        b = arm.data.edit_bones.new(pre + "HandFinger%d" % (k + 1))
        b.head = to_arm @ Vector((side * FINGER_JOINTS[k], FINGER_Y, FINGER_Z))
        b.tail = to_arm @ Vector((side * FINGER_JOINTS[k + 1], FINGER_Y, FINGER_Z))
        b.parent = parent
        b.use_connect = k > 0
        parent = b
    parent = hand
    for k in range(2):
        b = arm.data.edit_bones.new(pre + "HandThumb%d" % (k + 1))
        h = THUMB_JOINTS[k]
        t = THUMB_JOINTS[k + 1]
        b.head = to_arm @ Vector((side * h[0], h[1], h[2]))
        b.tail = to_arm @ Vector((side * t[0], t[1], t[2]))
        b.parent = parent
        b.use_connect = k > 0
        parent = b
bpy.ops.object.mode_set(mode="OBJECT")
vg = {g.name: g for g in mesh.vertex_groups}
for pre in ("Left", "Right"):
    for n in ["HandFinger1", "HandFinger2", "HandFinger3", "HandThumb1", "HandThumb2"]:
        vg[pre + n] = mesh.vertex_groups.new(name=pre + n)
hand_idx = {vg["LeftHand"].index: "Left", vg["RightHand"].index: "Right"}
n_finger = 0
n_thumb = 0
for v in mesh.data.vertices:
    if not v.groups:
        continue
    best = max(v.groups, key=lambda e: e.weight)
    pre = hand_idx.get(best.group)
    if pre is None:
        continue
    p = v.co
    side = 1.0 if pre == "Left" else -1.0
    x = abs(p.x)
    names_w = None
    if x > KNUCKLE - FINGER_BLEND:
        w = finger_weights(x - KNUCKLE)
        names_w = [(pre + "Hand", w[0]), (pre + "HandFinger1", w[1]),
            (pre + "HandFinger2", w[2]), (pre + "HandFinger3", w[3])]
        n_finger += 1
    elif THUMB_X[0] < x < THUMB_X[1] and p.y < THUMB_Y and p.z < THUMB_Z:
        w = thumb_weights(p, side)
        names_w = [(pre + "Hand", w[0]), (pre + "HandThumb1", w[1]), (pre + "HandThumb2", w[2])]
        n_thumb += 1
    if names_w is None:
        continue
    # The finger is the hand's and its own bones' alone: any share of the
    # forearm (or anything else) the borrowed weights left out here held the
    # fingers half straight however far they were curled.
    for gi in [ge.group for ge in v.groups]:
        mesh.vertex_groups[gi].remove([v.index])
    for n, w in names_w:
        if w > 1e-4:
            vg[n].add([v.index], w, "REPLACE")
print("fingers: %d finger vertices and %d thumb vertices skinned to the new bones" % (n_finger, n_thumb))

# --- material: bakes ----------------------------------------------------------------
mat = mesh.data.materials[0]
mat.name = "knight"
mat.use_backface_culling = False
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
albedo_node = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
img = albedo_node.image
w, h = img.size
print("albedo", img.name, w, h)
# Exported as models/player_knight_Image_0.jpg, the name the earlier knights'
# had, so its .import (VRAM compressed, mipmaps -- note 155) carries over.
img.name = "Image_0"
if max(w, h) > TEX:
    img.scale(TEX, TEX * h // w)
    w, h = img.size
uv_link = next((l for l in albedo_node.inputs["Vector"].links), None)

px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
lin = np.where(px[..., :3] <= 0.04045, px[..., :3] / 12.92, ((px[..., :3] + 0.055) / 1.055) ** 2.4)
r, g, b = px[..., 0], px[..., 1], px[..., 2]
lum = 0.2126 * lin[..., 0] + 0.7152 * lin[..., 1] + 0.0722 * lin[..., 2]
mx = np.maximum(np.maximum(r, g), b)
mn = np.minimum(np.minimum(r, g), b)
sat = (mx - mn) / np.maximum(mx, 1e-4)
# Gold: brighter, warm (red over green over blue), saturated.
gold = np.clip((mx - 0.30) / 0.20, 0.0, 1.0) * np.clip((sat - 0.35) / 0.2, 0.0, 1.0)
gold *= ((r >= g) & (g > b * 1.15)).astype(np.float32)
print("albedo: luminance median %.3f p90 %.3f; gold %.2f%% of texels" % (
    float(np.median(lum)), float(np.percentile(lum, 90)), 100.0 * float((gold > 0.5).mean())))

# Height: the plate's own shading, dark low; the gold seams lowest.
plate = np.clip(lum / max(float(np.percentile(lum, 95)), 1e-3), 0.0, 1.0) ** 0.6
height = np.clip(plate * (1.0 - gold) * 0.85 + 0.15 * (1.0 - gold), 0.0, 1.0)
himg = bpy.data.images.new("knight_height", w, h, alpha=False, float_buffer=True)
himg.colorspace_settings.name = "Non-Color"
hp = np.ones((h, w, 4), dtype=np.float32)
hp[..., 0] = hp[..., 1] = hp[..., 2] = height
himg.pixels[:] = hp.ravel()

scn = bpy.context.scene
scn.render.engine = "CYCLES"
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    scn.cycles.device = "GPU"
except Exception as ex:  # noqa: BLE001 - CPU is only slower
    print("bake on CPU:", ex)
scn.cycles.samples = BAKE_SAMPLES
scn.render.bake.margin = 6
# Occlusion only from what is close: the creases between plates, not the far
# side of the body.
scn.world = bpy.data.worlds.new("bake")
scn.world.light_settings.distance = AO_DISTANCE
for o in bpy.context.scene.objects:
    o.select_set(False)
mesh.select_set(True)
bpy.context.view_layer.objects.active = mesh


def bake_into(name: str, size: int, kind: str) -> np.ndarray:
    out = bpy.data.images.new(name, size, size, alpha=False, float_buffer=True)
    out.colorspace_settings.name = "Non-Color"
    node = nt.nodes.new("ShaderNodeTexImage")
    node.image = out
    for n in nt.nodes:
        n.select = False
    node.select = True
    nt.nodes.active = node
    if kind == "NORMAL":
        bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=6)
    else:
        bpy.ops.object.bake(type=kind, margin=6)
    nt.nodes.remove(node)
    return np.array(out.pixels[:], dtype=np.float32).reshape(size, size, 4)


# The bump, for the normal bake only.
hnode = nt.nodes.new("ShaderNodeTexImage")
hnode.image = himg
hnode.interpolation = "Linear"
if uv_link is not None:
    nt.links.new(uv_link.from_socket, hnode.inputs["Vector"])
bump = nt.nodes.new("ShaderNodeBump")
bump.inputs["Distance"].default_value = BUMP_DISTANCE
bump.inputs["Strength"].default_value = 1.0
nt.links.new(hnode.outputs["Color"], bump.inputs["Height"])
nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
nrm = bake_into("bake_normal", w, "NORMAL")
nt.nodes.remove(bump)
nt.nodes.remove(hnode)
dev = np.abs(nrm[..., 0] - 0.5) + np.abs(nrm[..., 1] - 0.5)
print("normal map: mean tilt %.3f, p95 %.3f" % (float(dev.mean()), float(np.percentile(dev, 95))))

ao = bake_into("bake_ao", ORM_TEX, "AO")[..., 0]
print("ao: mean %.3f p5 %.3f" % (float(ao.mean()), float(np.percentile(ao, 5))))

# --- roughness and metal, from the albedo ----------------------------------------
def down(a: np.ndarray, size: int) -> np.ndarray:
    f = a.shape[0] // size
    return a.reshape(size, f, size, f).mean(axis=(1, 3))


lum_s = down(lum, ORM_TEX)
gold_s = down(gold, ORM_TEX)
dark = 1.0 - np.clip(lum_s / max(float(np.percentile(lum_s, 90)), 1e-3), 0.0, 1.0)
crease = 1.0 - ao
rough = 0.55 + 0.20 * dark + 0.20 * crease
rough = rough * (1.0 - gold_s) + 0.38 * gold_s
metal = 0.60 * (1.0 - gold_s) + 0.90 * gold_s
orm = np.ones((ORM_TEX, ORM_TEX, 4), dtype=np.float32)
orm[..., 0] = np.clip(ao, 0.0, 1.0)
orm[..., 1] = np.clip(rough, 0.05, 1.0)
orm[..., 2] = np.clip(metal, 0.0, 1.0)
print("roughness mean %.2f, metal mean %.2f" % (float(orm[..., 1].mean()), float(orm[..., 2].mean())))

# --- the material, as glTF wants it ----------------------------------------------
def image(name: str, data: np.ndarray, size: int) -> bpy.types.Image:
    im = bpy.data.images.new(name, size, size, alpha=False)
    im.colorspace_settings.name = "Non-Color"
    im.pixels[:] = data.ravel()
    im.file_format = "JPEG"
    return im


nimg = image("knight_normal", nrm, w)
oimg = image("knight_orm", orm, ORM_TEX)

nnode = nt.nodes.new("ShaderNodeTexImage")
nnode.image = nimg
nmap = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(nnode.outputs["Color"], nmap.inputs["Color"])
nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
onode = nt.nodes.new("ShaderNodeTexImage")
onode.image = oimg
sep = nt.nodes.new("ShaderNodeSeparateColor")
nt.links.new(onode.outputs["Color"], sep.inputs["Color"])
nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
gltf_out = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
gltf_out.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
gnode = nt.nodes.new("ShaderNodeGroup")
gnode.node_tree = gltf_out
nt.links.new(sep.outputs["Red"], gnode.inputs["Occlusion"])
if uv_link is not None:
    for n in (nnode, onode):
        nt.links.new(uv_link.from_socket, n.inputs["Vector"])
img.file_format = "JPEG"
for im in list(bpy.data.images):
    if im not in (img, nimg, oimg):
        bpy.data.images.remove(im)

if "--preview" in sys.argv:
    out = sys.argv[-1]
    for im in (nimg, oimg):
        im.filepath_raw = os.path.join(out, im.name + ".png")
        im.file_format = "PNG"
        im.save()
        im.file_format = "JPEG"

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    export_animations=False,
    export_image_format="JPEG",
    export_jpeg_quality=90,
    export_yup=True,
)
print("wrote", OUT, os.path.getsize(OUT))
