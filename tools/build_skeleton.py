"""Rebuild the ossuary skeleton as a *rigged* GLB with a full clip set.

The shipped mesh was a baked A-pose with the armature thrown away. This puts the
rig back, but trims it: 58 of the 80 bones are fingers and toes that are never
readable on a 2.1 m skeleton at combat range, so their weights are folded into
the parent hand/foot and the bones are deleted. 22 bones survive.

Axis conventions for the pose specs below (Blender, armature space):
    +X = the skeleton's LEFT, -Y = FORWARD, +Z = UP
A rotation of +theta about X tips the whole body "top forwards". So for bones
that point UP (spine, neck, head) +X leans forward, and for bones that point
DOWN (arms, legs) +X swings backward and -X swings forward.
"""

import bpy
import bmesh
import os
import math
import sys
from mathutils import Matrix, Quaternion, Vector, kdtree

OUT = sys.argv[sys.argv.index("--") + 1]
## Optional second argument, so the budget can be swept without editing this
## file. Thin bones are the first thing collapse decimation destroys, and
## finding the floor where the arms stop reading as bone needs a sweep.
_argv = sys.argv[sys.argv.index("--") + 1:]
## 6000, up from the 3500 the hand-modelled skeleton shipped at. The generated
## body is cut into one island per bone, so the decimator cannot merge across
## the seams, and thin parts -- cervical vertebrae, clavicles, ribs -- collapse
## into loose shards well before the thick ones do. At 3500 the neck was a mess
## of triangles; 6000 is where it holds together.
TARGET_TRIS = int(_argv[1]) if len(_argv) > 1 else 6000
FPS = 24
## Yaw applied to the generated body so it faces the way the rig does.
##
## The rig's forward is -Y (see the axis note above). Which way a generated mesh
## comes out facing is a property of that particular generation, so this is
## established by rendering all four sides and reading it off -- never assumed.
## A skeleton is symmetric enough that a 180-degree error still looks like a
## skeleton from the front and only shows up when it walks.
BODY_YAW = -90.0
## Multiplied into the generated body's albedo to age it.
##
## Linear, not sRGB: glTF carries baseColorFactor as linear and Godot shows
## albedo_color as sRGB, the same trap the old flat bone colour documents below.
## Warm and dark, for earth in the grain rather than a grey wash.
BONE_TINT = (0.52, 0.48, 0.40, 1.0)
## Height fraction of the skull, measured up from its lowest point, below which
## geometry is cut away to remove the fused mandible. Tuned by rendering the
## head, because the only way to know where the jaw ends on a generated skull
## is to look at it.
JAW_CUT = 0.3

# --------------------------------------------------------------------------
# bone aliases
# --------------------------------------------------------------------------
RT, PV = "root", "pelvis"
SP1, SP2, CH, NK, HD, JW = "spine.01", "spine.02", "chest", "neck", "head", "jaw"
CL_L, UA_L, FA_L, HN_L = "clavicle.L", "upper_arm.L", "forearm.L", "hand.L"
CL_R, UA_R, FA_R, HN_R = "clavicle.R", "upper_arm.R", "forearm.R", "hand.R"
TH_L, SH_L, FT_L = "thigh.L", "shin.L", "foot.L"
TH_R, SH_R, FT_R = "thigh.R", "shin.R", "foot.R"

# The jaw is gone: the reference these were remade against is a jawless skull,
# worn down to the cranium and upper teeth. `JW` is still named above because
# the MANDIBLE GEOMETRY has to be found and deleted by vertex group before the
# fold below, but the bone itself does not survive into the rig.
KEEP = [RT, PV, SP1, SP2, CH, NK, HD,
        CL_L, UA_L, FA_L, HN_L, CL_R, UA_R, FA_R, HN_R,
        TH_L, SH_L, FT_L, TH_R, SH_R, FT_R]
# root carries only the vertical hop; everything else is rotation.
ANIM_BONES = [b for b in KEEP]


def log(*a):
    print("[build]", *a)


# --------------------------------------------------------------------------
# 1. strip the studio collection
# --------------------------------------------------------------------------
studio = bpy.data.collections.get("03 | Studio")
if studio:
    for o in list(studio.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.collections.remove(studio)
log("studio removed")

arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
arm.name = "Armature"
arm.data.name = "Armature"
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
log("armature:", arm.name, "bones:", len(arm.data.bones), "meshes:", len(meshes))

# --------------------------------------------------------------------------
# 1b. take the jaw off
# --------------------------------------------------------------------------
# Done HERE, before the fold below, and that ordering is the point: the fold
# redirects a doomed bone's weights onto its surviving parent and then deletes
# the vertex group. Run it first and the mandible's vertices are indistinguishable
# from the cranium's -- both weighted to `head` -- and there is no way left to
# tell them apart.
#
# A vertex belongs to the jaw if the jaw group is its HEAVIEST group, not merely
# one of its groups. The skull and mandible share a seam at the joint, and
# testing "has any jaw weight" takes a ring of the cranium away with it.
jaw_removed = 0
for obj in list(meshes):
    vgs = obj.vertex_groups
    if JW not in vgs:
        continue
    jaw_index = vgs[JW].index
    doomed_verts = []
    for v in obj.data.vertices:
        best_weight = 0.0
        best_group = -1
        for g in v.groups:
            if g.weight > best_weight:
                best_weight = g.weight
                best_group = g.group
        if best_group == jaw_index:
            doomed_verts.append(v.index)
    if not doomed_verts:
        continue
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.verts[i] for i in doomed_verts], context='VERTS')
    bm.to_mesh(obj.data)
    bm.free()
    jaw_removed += len(doomed_verts)

# Whole pieces can empty out -- the mandible is its own skinned object in this
# rig -- and an empty mesh joined into the body contributes nothing but is still
# carried through every later step.
for obj in list(meshes):
    if len(obj.data.vertices) == 0:
        meshes.remove(obj)
        bpy.data.objects.remove(obj, do_unlink=True)
log("jaw removed:", jaw_removed, "vertices;", len(meshes), "meshes left")
assert jaw_removed > 0, "no jaw geometry found -- has the source rig changed?"

# --------------------------------------------------------------------------
# 2. fold finger/toe weights into the surviving ancestor, then drop those bones
# --------------------------------------------------------------------------
redirect = {}
for b in arm.data.bones:
    if b.name in KEEP:
        continue
    p = b.parent
    while p is not None and p.name not in KEEP:
        p = p.parent
    redirect[b.name] = p.name if p else PV
log("bones to fold away:", len(redirect))

for obj in meshes:
    vgs = obj.vertex_groups
    doomed = {vg.index: redirect[vg.name] for vg in vgs if vg.name in redirect}
    if not doomed:
        continue
    for tgt in set(doomed.values()):
        if tgt not in vgs:
            vgs.new(name=tgt)
    moves = []
    for v in obj.data.vertices:
        for g in v.groups:
            if g.group in doomed and g.weight > 0.0:
                moves.append((v.index, doomed[g.group], g.weight))
    for vi, tgt, w in moves:
        vgs[tgt].add([vi], w, 'ADD')
    for vg in [vg for vg in vgs if vg.name in redirect]:
        vgs.remove(vg)
log("weights folded")

bpy.context.view_layer.objects.active = arm
with bpy.context.temp_override(active_object=arm, object=arm,
                               selected_objects=[arm],
                               selected_editable_objects=[arm]):
    bpy.ops.object.mode_set(mode='EDIT')
    ebs = arm.data.edit_bones
    for name in list(redirect.keys()):
        eb = ebs.get(name)
        if eb:
            ebs.remove(eb)
    bpy.ops.object.mode_set(mode='OBJECT')
log("bones after trim:", len(arm.data.bones))
assert len(arm.data.bones) == len(KEEP), "unexpected bone count"

# --------------------------------------------------------------------------
# 3. join the 79 skinned pieces into one object
# --------------------------------------------------------------------------
target = meshes[0]
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = target
with bpy.context.temp_override(active_object=target, object=target,
                               selected_objects=meshes,
                               selected_editable_objects=meshes):
    bpy.ops.object.join()
target.name = "Skeleton"
target.data.name = "Skeleton"
target.data.calc_loop_triangles()
before = len(target.data.loop_triangles)
log("joined ->", before, "tris,", len(target.vertex_groups), "vertex groups")

# --------------------------------------------------------------------------
# 4. decimate, keeping the armature modifier intact
# --------------------------------------------------------------------------
dec = target.modifiers.new("Decimate", 'DECIMATE')
dec.decimate_type = 'COLLAPSE'
dec.ratio = min(1.0, TARGET_TRIS / float(before))
dec.use_collapse_triangulate = True
with bpy.context.temp_override(active_object=target, object=target,
                               selected_objects=[target],
                               selected_editable_objects=[target]):
    bpy.ops.object.modifier_move_to_index(modifier="Decimate", index=0)
    bpy.ops.object.modifier_apply(modifier="Decimate")
target.data.calc_loop_triangles()
log("decimated ->", len(target.data.loop_triangles), "tris")

# --------------------------------------------------------------------------
# 5. one bone material, matching the tone already shipping
# --------------------------------------------------------------------------
mat = bpy.data.materials.new("Bone")
mat.use_nodes = True
bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
# glTF carries baseColorFactor as LINEAR and Godot shows albedo_color as sRGB,
# so these are the linear values that land on the approved (0.604, 0.561, 0.471)
# in the inspector. Handing Blender the sRGB numbers directly imports ~0.80 and
# the bones go back to looking bleached.
bsdf.inputs["Base Color"].default_value = (0.3231, 0.2747, 0.1878, 1.0)
bsdf.inputs["Roughness"].default_value = 0.86
bsdf.inputs["Metallic"].default_value = 0.0
# A trace of emission so glTF carries an emissive factor and Godot imports the
# material with emission_enabled. The enemy script drives the energy from there
# to colour each state; a pure-black emissive would import the flag off and the
# state colours would silently do nothing.
bsdf.inputs["Emission Color"].default_value = (0.3231, 0.2747, 0.1878, 1.0)
bsdf.inputs["Emission Strength"].default_value = 0.05
target.data.materials.clear()
target.data.materials.append(mat)
log("material applied")

# --------------------------------------------------------------------------
# 5b. swap the WHOLE BODY for the generated one
# --------------------------------------------------------------------------
# (pose helpers are defined here rather than further down because the arm-pose
#  search below needs to_local; the clips use the same helper later.)
AXES = (Vector((1.0, 0.0, 0.0)), Vector((0.0, 1.0, 0.0)), Vector((0.0, 0.0, 1.0)))


def to_local(pbone, degrees):
    """Turn an armature-space XYZ rotation into this bone's local quaternion."""
    R = Matrix.Identity(3)
    for axis, deg in zip(AXES, degrees):
        if deg:
            R = Matrix.Rotation(math.radians(deg), 3, axis) @ R
    rest = pbone.bone.matrix_local.to_3x3()
    return (rest.inverted() @ R @ rest).to_quaternion()

# --------------------------------------------------------------------------
# Tripo produces a static mesh. This enemy is a rigged character with 21 bones
# and nine clips, and the clips live on the ARMATURE, not on the mesh -- so a
# generated body can replace the old one as long as it gets skinned to the same
# armature. That is what this does: the original mesh stays just long enough to
# act as a weight donor, its per-bone weights are projected onto the new body by
# proximity, and then it is thrown away.
#
# The donor and the replacement have to be standing in the same pose for that
# projection to mean anything. The generated body is prompted for the A-pose the
# source rig rests in; if a future regeneration comes back with its arms down,
# the arm vertices will land nearest the ribcage and be weighted to the chest,
# and the arms will tear off when the clip plays. That failure is visible
# immediately in a posed render, which is why one is taken below.
BODY = "models/skeleton_worn_ready.glb"
body_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                         BODY.replace("/", os.sep))
if not os.path.exists(body_path):
    raise SystemExit("[build] missing %s -- generate it with tools/tripo.ps1" % BODY)

donor = target
dlo = Vector((1e9, 1e9, 1e9))
dhi = Vector((-1e9, -1e9, -1e9))
for v in donor.data.vertices:
    w = donor.matrix_world @ v.co
    for i in range(3):
        dlo[i] = min(dlo[i], w[i])
        dhi[i] = max(dhi[i], w[i])
dsize = dhi - dlo
log("donor body: %.3f x %.3f x %.3f" % (dsize.x, dsize.y, dsize.z))

before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=body_path)
fresh = [o for o in bpy.data.objects if o not in before and o.type == 'MESH']
if not fresh:
    raise SystemExit("[build] body glb imported no mesh")
body = fresh[0]
for o in fresh[1:]:
    o.select_set(True)
if len(fresh) > 1:
    with bpy.context.temp_override(active_object=body, object=body,
                                   selected_objects=fresh,
                                   selected_editable_objects=fresh):
        bpy.ops.object.join()

# glTF nests the mesh under a root empty holding the Y-up to Z-up conversion, so
# the object's own transform is not its world transform. Unparent keeping the
# placement and bake it, or every rotation below lands in the wrong space.
world = body.matrix_world.copy()
body.parent = None
body.matrix_world = world
with bpy.context.temp_override(active_object=body, object=body,
                               selected_objects=[body],
                               selected_editable_objects=[body]):
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# `rotation_mode` first: the glTF importer leaves objects in QUATERNION mode, in
# which `rotation_euler` is assignable, readable back, and silently ignored when
# the world matrix is built. The skull's yaw was discarded twice that way.
body.rotation_mode = 'XYZ'
body.rotation_euler = (0.0, 0.0, math.radians(BODY_YAW))
bpy.context.view_layer.update()

corners = [body.matrix_world @ Vector(c) for c in body.bound_box]
blo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
bhi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
bsize = bhi - blo
log("generated body extents after yaw: %.3f x %.3f x %.3f"
    % (bsize.x, bsize.y, bsize.z))

# Uniform, from HEIGHT. Height is what the eye reads as the size of a figure,
# and matching each axis separately would squash the generated proportions into
# the old mesh's and undo the point of generating it. Sizing from the largest
# axis instead -- the mistake made when fitting the skull -- inflates the other
# two and produces a body that no longer matches its own collision capsule.
scale = dsize.z / max(bsize.z, 1e-6)
body.scale = (scale, scale, scale)
bpy.context.view_layer.update()
corners = [body.matrix_world @ Vector(c) for c in body.bound_box]
blo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
bhi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
# Centred on the donor in plan, and stood on the donor's own floor rather than
# centred vertically: the feet have to meet the ground the capsule stands on.
body.location = body.location + Vector((
    (dlo.x + dhi.x) * 0.5 - (blo.x + bhi.x) * 0.5,
    (dlo.y + dhi.y) * 0.5 - (blo.y + bhi.y) * 0.5,
    dlo.z - blo.z))
bpy.context.view_layer.update()
log("body fitted: scale %.3f" % scale)

# --------------------------------------------------------------------------
# Match the donor's POSE to the generated body before transferring weights.
# --------------------------------------------------------------------------
# Weight transfer is a proximity lookup: each vertex of the new body takes the
# weights of whatever donor surface is nearest. That is only meaningful if the
# two bodies are standing the same way.
#
# They were not. The rig rests in an A-pose with a 1.388 m arm span; the first
# generated body hung its arms down at 0.808 m. Every arm vertex found the
# ribcage nearer than the arm, was weighted to the chest and pelvis, and the
# arms tore into flat sheets from shoulder to hip the moment `run` played.
#
# Prompting for a particular pose is not a fix -- a generator gives you the pose
# it feels like, and it ignored the A-pose instruction outright. So the pipeline
# adapts instead: swing the donor's arms through a sweep of angles, measure how
# well its surface lines up with the generated body at each, and transfer from
# the best match. Whatever pose comes back, the donor is bent to meet it.
def _sample_points(obj, limit):
    """Up to `limit` world-space points from an object's evaluated surface."""
    deps = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(deps)
    tmp = ev.to_mesh()
    # Indexed rather than sliced: a bpy_prop_collection does not accept a
    # slice step, so `vertices[::step]` raises instead of subsampling.
    step = max(1, len(tmp.vertices) // limit)
    pts = [obj.matrix_world @ tmp.vertices[i].co
           for i in range(0, len(tmp.vertices), step)]
    ev.to_mesh_clear()
    return pts


def _swing_arms(degrees):
    """Rotate both upper arms by `degrees` about the bone axis that raises
    them. -X swings a downward-pointing bone forward, so the sign here is the
    one that closes the A-pose toward the body (see the axis note up top)."""
    for name, sign in ((UA_L, 1.0), (UA_R, -1.0)):
        pb = arm.pose.bones[name]
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = to_local(pb, (0.0, 0.0, sign * degrees))
    bpy.context.view_layer.update()


target_pts = _sample_points(body, 600)
kd = kdtree.KDTree(len(target_pts))
for i, p in enumerate(target_pts):
    kd.insert(p, i)
kd.balance()

best_angle = 0.0
best_error = 1e18
# Wide enough to bracket any plausible arm pose, from raised above the
# shoulder to hanging flat against the thigh. The first sweep only ran
# -10..60 and the best fit came out AT -10, which is a boundary hit: the
# answer was outside the range and the search reported the edge as if it had
# found a minimum. The check below catches that rather than trusting it.
SWEEP_LO, SWEEP_HI = -70, 70
for candidate in range(SWEEP_LO, SWEEP_HI + 1, 5):
    _swing_arms(float(candidate))
    err = 0.0
    donor_pts = _sample_points(donor, 600)
    for p in donor_pts:
        _, _, d = kd.find(p)
        err += d
    err /= max(len(donor_pts), 1)
    if err < best_error:
        best_error = err
        best_angle = float(candidate)
log("arm-pose search: best %.0f deg, mean surface error %.4f m"
    % (best_angle, best_error))
if best_angle <= SWEEP_LO or best_angle >= SWEEP_HI:
    log("WARNING: best fit sits at the edge of the sweep -- the real optimum is")
    log("         outside it, and this angle is not a minimum. Widen the range.")
_swing_arms(best_angle)

# --------------------------------------------------------------------------
# Bind RIGIDLY: every vertex to exactly one bone, by nearest bone segment.
# --------------------------------------------------------------------------
# Smooth skinning is for flesh. This is a skeleton -- it is a bag of separate
# rigid bones, and that is how the original model was built, as 79 individually
# skinned pieces one per bone.
#
# Blended weights transferred off the donor surface were tried first and failed
# twice: the arms came out as flat sheets, then as slivers, because a vertex
# pulled between the humerus and the ribcage is stretched between them. There
# is no correct blend for two bones that are not connected by flesh.
#
# So each vertex is given to whichever BONE SEGMENT it is physically closest to,
# at weight 1.0, with the armature posed to match the generated body. The bones
# lie inside the limbs they belong to, so "which bone is this vertex nearest"
# is a reliable question here in a way that "which bit of a differently-shaped
# donor is it nearest" never was. Joints open into gaps rather than stretching,
# which is what a real skeleton does anyway.
def _segment_distance(p, a, b):
    ab = b - a
    denom = ab.dot(ab)
    if denom < 1e-12:
        return (p - a).length
    t = max(0.0, min(1.0, (p - a).dot(ab) / denom))
    return (p - (a + ab * t)).length


# `root` is a control bone standing at the origin, not a piece of the body. It
# is longer than any real bone and sits up the middle of the figure, so left in
# the running it wins the pelvis and lower spine outright.
bind_bones = [n for n in KEEP if n != RT]
bone_spans = [(n, arm.pose.bones[n].head.copy(), arm.pose.bones[n].tail.copy())
              for n in bind_bones]

for vg in list(body.vertex_groups):
    body.vertex_groups.remove(vg)
groups = {n: body.vertex_groups.new(name=n) for n in bind_bones}

to_arm_bind = arm.matrix_world.inverted() @ body.matrix_world


def _nearest_bone_index(p):
    best_i = 0
    best_d = 1e18
    for i, (_, head, tail) in enumerate(bone_spans):
        d = _segment_distance(p, head, tail)
        if d < best_d:
            best_d = d
            best_i = i
    return best_i


# --------------------------------------------------------------------------
# Cut the body into one island per bone before binding.
# --------------------------------------------------------------------------
# This is the step that actually fixes the arms, and it is the one the earlier
# attempts were missing. Rigid weights alone are not enough on a CONTINUOUS
# surface: a triangle with one corner on the humerus and another on the ribcage
# is stretched between them the moment they move apart, and a whole shoulder's
# worth of those triangles is what the flat blades were.
#
# The original model never had this problem because it was 79 SEPARATE skinned
# pieces. Tripo returns one welded shell, so the shell is cut back apart here:
# each face is assigned to the bone nearest its centre, and every edge between
# faces of different bones is split. What comes out is a bag of rigid bones that
# can slide past each other, which is what a skeleton is.
bm = bmesh.new()
bm.from_mesh(body.data)
bm.faces.ensure_lookup_table()

face_bone = {}
for f in bm.faces:
    centre = to_arm_bind @ (sum((v.co for v in f.verts), Vector()) / len(f.verts))
    face_bone[f.index] = _nearest_bone_index(centre)

seams = [e for e in bm.edges
         if len({face_bone[f.index] for f in e.link_faces}) > 1]
bmesh.ops.split_edges(bm, edges=seams)
log("split %d seam edges between bones" % len(seams))

# --------------------------------------------------------------------------
# Cut the jaw off the generated skull.
# --------------------------------------------------------------------------
# The mandible is not a separate part here. Tripo fused it into the cranium as
# one continuous lump, so there is no vertex group, no island and no material
# to select it by -- the earlier `jaw` group removal only ever applied to the
# original rig's mesh, which is discarded. The only handle left is where it is
# in space.
#
# So the head island is cut with a horizontal plane: everything below a
# fraction of its own height goes. That takes the mandible and the lower part
# of the ramus with it and leaves the cranium and the upper tooth row, which is
# what the reference skull is.
head_index = bind_bones.index(HD)
head_faces = [f for f in bm.faces if face_bone.get(f.index) == head_index]
if head_faces:
    zs = [(to_arm_bind @ v.co).z for f in head_faces for v in f.verts]
    z_lo, z_hi = min(zs), max(zs)
    z_cut = z_lo + (z_hi - z_lo) * JAW_CUT
    doomed_faces = []
    for f in head_faces:
        centre = to_arm_bind @ (sum((v.co for v in f.verts), Vector()) / len(f.verts))
        if centre.z < z_cut:
            doomed_faces.append(f)
    if doomed_faces:
        bmesh.ops.delete(bm, geom=doomed_faces, context='FACES')
    log("jaw cut: head spans %.3f..%.3f, cut at %.3f, removed %d of %d faces"
        % (z_lo, z_hi, z_cut, len(doomed_faces), len(head_faces)))
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()
    # Deleting faces leaves the vertices that only belonged to them behind as
    # loose points, which export as nothing but count against the budget.
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
        log("jaw cut: removed %d orphaned vertices" % len(loose))

# Re-read the assignment after the split, when the islands are real.
bm.faces.ensure_lookup_table()
bm.verts.ensure_lookup_table()
vert_bone = {}
for f in bm.faces:
    centre = to_arm_bind @ (sum((v.co for v in f.verts), Vector()) / len(f.verts))
    bi = _nearest_bone_index(centre)
    for v in f.verts:
        vert_bone[v.index] = bi
bm.to_mesh(body.data)
bm.free()

tally = {}
for v in body.data.vertices:
    bi = vert_bone.get(v.index)
    if bi is None:
        # A loose vertex belonging to no face; bind it by its own position so
        # it travels with something rather than being left at the origin.
        bi = _nearest_bone_index(to_arm_bind @ v.co)
    best_name = bone_spans[bi][0]
    groups[best_name].add([v.index], 1.0, 'REPLACE')
    tally[best_name] = tally.get(best_name, 0) + 1

busiest = sorted(tally.items(), key=lambda kv: -kv[1])[:5]
log("rigid bind: %d bones used, busiest %s"
    % (len(tally), ", ".join("%s=%d" % kv for kv in busiest)))
for limb in (UA_L, UA_R, FA_L, FA_R, HN_L, HN_R):
    if tally.get(limb, 0) == 0:
        raise SystemExit("[build] no vertices bound to %s -- the arm pose match "
                         "failed and the arms will not move" % limb)

# --------------------------------------------------------------------------
# Un-pose the generated body into the armature's REST pose.
# --------------------------------------------------------------------------
# Correct weights are not sufficient, and this was the second thing that had to
# be learned the hard way. Skinning assumes the mesh is modelled in the rig's
# REST pose: a vertex weighted to `upper_arm` is rotated about where that bone
# rests. The generated arms hang 50 degrees away from where the rig's arms rest,
# so even perfectly-assigned weights swung them about an axis running through
# nothing, and they came out as the same flat sheets as before.
#
# So the mesh is pushed backwards through the skinning it would receive at the
# matched pose. For each vertex, blend the bone matrices by its own weights,
# invert, and apply. The result deforms to the shape the generator produced when
# the armature is put back into that pose -- which means at rest it now stands
# in the rig's A-pose, and every clip drives it correctly from there.
skin_mats = {}
for pb in arm.pose.bones:
    skin_mats[pb.name] = pb.matrix @ pb.bone.matrix_local.inverted()

to_arm = arm.matrix_world.inverted() @ body.matrix_world
from_arm = to_arm.inverted()
group_name = [vg.name for vg in body.vertex_groups]
unposed = 0
for v in body.data.vertices:
    acc = [0.0] * 16
    total = 0.0
    for g in v.groups:
        name = group_name[g.group]
        m = skin_mats.get(name)
        if m is None or g.weight <= 0.0:
            continue
        for r in range(4):
            for c in range(4):
                acc[r * 4 + c] += m[r][c] * g.weight
        total += g.weight
    if total <= 0.0:
        continue
    blended = Matrix([[acc[r * 4 + c] / total for c in range(4)] for r in range(4)])
    try:
        inv = blended.inverted()
    except ValueError:
        # A vertex whose blended matrix is singular -- weights that cancel out.
        # Leaving it put is better than moving it somewhere arbitrary.
        continue
    v.co = from_arm @ (inv @ (to_arm @ v.co))
    unposed += 1
log("un-posed %d of %d vertices into the rest pose"
    % (unposed, len(body.data.vertices)))

# Back to rest before the clips are authored: the search above left the arms
# swung, and every pose below is written as an absolute orientation from rest.
_swing_arms(0.0)


# Decimate AFTER the transfer: collapsing first would throw away the surface
# detail the projection uses to find its nearest polygon.
dec2 = body.modifiers.new("Decimate", 'DECIMATE')
dec2.decimate_type = 'COLLAPSE'
body.data.calc_loop_triangles()
dec2.ratio = min(1.0, TARGET_TRIS / max(len(body.data.loop_triangles), 1))
with bpy.context.temp_override(active_object=body, object=body,
                               selected_objects=[body],
                               selected_editable_objects=[body]):
    bpy.ops.object.modifier_apply(modifier=dec2.name)

skin = body.modifiers.new("Armature", 'ARMATURE')
skin.object = arm
body.parent = arm
body.name = "Skeleton"
body.data.name = "Skeleton"

bpy.data.objects.remove(donor, do_unlink=True)
target = body
target.data.calc_loop_triangles()
log("body swapped -> %d tris, %d groups, %d material slots"
    % (len(target.data.loop_triangles), len(target.vertex_groups),
       len(target.data.materials)))

# The enemy script drives emission energy to colour each AI state, and it can
# only do that if the imported material has emission_enabled -- which glTF sets
# from a non-zero emissive factor. Tripo's material has none, so a pure-black
# emissive would import the flag off and every state colour would silently do
# nothing.
for slot_mat in target.data.materials:
    if slot_mat is None or not slot_mat.use_nodes:
        continue
    principled = next((n for n in slot_mat.node_tree.nodes
                       if n.type == 'BSDF_PRINCIPLED'), None)
    if principled is None:
        continue
    principled.inputs["Emission Color"].default_value = (0.3231, 0.2747, 0.1878, 1.0)
    principled.inputs["Emission Strength"].default_value = 0.05

    # Dirty the bone down. The reference is a grave-stained skull and the
    # generator returned clean medical white twice, ignoring every word about
    # weathering in the prompt -- so it is done here instead, where it is a
    # number that can be tuned rather than a dice roll.
    #
    # A multiply node between the texture and Base Color, not a plain factor:
    # the albedo is an image, and setting Base Color directly would be
    # overridden by whatever is plugged into it. glTF exports this pattern as
    # baseColorFactor, which is exactly the knob wanted.
    base = principled.inputs["Base Color"]
    if base.is_linked:
        # Multiplied into the IMAGE, not into a node.
        #
        # A MULTIPLY node between the texture and Base Color was the obvious
        # way and it exported as nothing at all: glTF only recognises a narrow
        # set of node patterns for baseColorFactor, the rebuilt skeleton came
        # out as clean white as before, and there was no warning. Scaling the
        # pixels cannot be silently dropped by an exporter.
        node = base.links[0].from_node
        if node.type == 'TEX_IMAGE' and node.image is not None:
            img = node.image
            px = list(img.pixels)
            for i in range(0, len(px), 4):
                px[i] *= BONE_TINT[0]
                px[i + 1] *= BONE_TINT[1]
                px[i + 2] *= BONE_TINT[2]
            img.pixels = px
            log("aged albedo '%s' (%dx%d)" % (img.name, img.size[0], img.size[1]))
    else:
        base.default_value = BONE_TINT
    principled.inputs["Roughness"].default_value = 0.94
    principled.inputs["Metallic"].default_value = 0.0
log("emission restored on %d material(s)" % len(target.data.materials))


# 6. pose helpers
# --------------------------------------------------------------------------

def mirror(pose):
    """Reflect a pose across the body's midline."""
    out = {}
    for name, (rx, ry, rz) in pose.items():
        if name.endswith(".L"):
            name = name[:-2] + ".R"
        elif name.endswith(".R"):
            name = name[:-2] + ".L"
        out[name] = (rx, -ry, -rz)
    return out


def apply_pose(pose, lift=0.0):
    for name in ANIM_BONES:
        pb = arm.pose.bones[name]
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = to_local(pb, pose.get(name, (0.0, 0.0, 0.0)))
    # A bone's local +Y runs head->tail, and `root` points straight up, so the
    # vertical hop goes in local Y. Local Z would slide the body horizontally.
    arm.pose.bones[RT].location = Vector((0.0, lift, 0.0))


def key_all(frame):
    for name in ANIM_BONES:
        arm.pose.bones[name].keyframe_insert("rotation_quaternion", frame=frame)
    arm.pose.bones[RT].keyframe_insert("location", frame=frame)


def make_action(name, frames, loop):
    """frames: list of (frame_number, pose_dict, root_lift)."""
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    # Blender 4.4+ slotted actions: bind a slot so keyframes land somewhere.
    if hasattr(ad, "action_slot") and getattr(ad, "action_slot", None) is None:
        try:
            ad.action_slot = act.slots.new(id_type='OBJECT', name=arm.name)
        except Exception:
            try:
                ad.action_slot = act.slots.new('OBJECT', arm.name)
            except Exception:
                pass
    for frame, pose, lift in frames:
        apply_pose(pose, lift)
        key_all(frame)
    last = frames[-1][0]
    act.use_frame_range = True
    act.frame_start = float(frames[0][0])
    act.frame_end = float(last)
    if loop:
        act.use_cyclic = True
    ad.action = None
    log("action", name, "frames", frames[0][0], "->", last, "keys", len(frames))
    return act


# --------------------------------------------------------------------------
# 7. the clips
# --------------------------------------------------------------------------
# A hunched, head-drooped neutral that every clip starts and ends near, so the
# cross-fades in Godot have something coherent to blend through.
NEUTRAL = {
    SP1: (4, 0, 0), SP2: (3, 0, 0), CH: (2, 0, 0),
    NK: (8, 0, 0), HD: (-5, 0, 0),
    CL_L: (0, 4, 0), CL_R: (0, -4, 0),
    UA_L: (4, 13, 0), UA_R: (4, -13, 0),
    FA_L: (-14, 0, 0), FA_R: (-14, 0, 0),
    TH_L: (-3, 0, 0), TH_R: (-3, 0, 0),
    SH_L: (6, 0, 0), SH_R: (6, 0, 0),
    FT_L: (-4, 0, 0), FT_R: (-4, 0, 0),
}
# Fists up, weight loaded â€” the shape the punches fire from and return to.
GUARD = {
    SP1: (6, 0, 0), SP2: (4, 0, 0), CH: (3, 0, -6),
    NK: (6, 0, 0), HD: (-4, 0, 0),
    CL_L: (-8, 6, 0), CL_R: (-8, -6, 0),
    # Arm angles solved by forward evaluation, not by hand: they put the fists in
    # front of the chest with ~0.35 m of travel left for a punch to use.
    UA_L: (9, 22, -27), UA_R: (9, -22, 27),
    FA_L: (-125, 0, 0), FA_R: (-125, 0, 0),
    TH_L: (-8, 0, 0), TH_R: (-6, 0, 0),
    SH_L: (14, 0, 0), SH_R: (12, 0, 0),
    FT_L: (-7, 0, 0), FT_R: (-6, 0, 0),
}


def blend(a, b, t):
    keys = set(a) | set(b)
    out = {}
    for k in keys:
        pa = a.get(k, (0, 0, 0))
        pb = b.get(k, (0, 0, 0))
        out[k] = tuple(pa[i] + (pb[i] - pa[i]) * t for i in range(3))
    return out


def merged(base, over):
    # NB: takes a dict, not **kwargs -- bone names contain dots, so passing them
    # as keywords would silently key the dict on the alias name ("CH") instead of
    # the bone name ("chest") and every override would be dropped.
    out = dict(base)
    out.update(over)
    return out


# -- idle: near-still, a slow sway and a head that drifts as if listening ----
idle_a = merged(NEUTRAL, {CH: (3, 0, 2), NK: (9, 0, 7), HD: (-6, 0, 6),
                          UA_L: (6, 13, 0), UA_R: (3, -13, 0)})
idle_b = merged(NEUTRAL, {CH: (1, 0, -2), NK: (7, 0, -8), HD: (-4, 0, -7),
                          UA_L: (3, 13, 0), UA_R: (6, -13, 0)})
make_action("idle", [
    (0, NEUTRAL, 0.0),
    (24, idle_a, 0.012),
    (48, idle_b, -0.008),
    (72, NEUTRAL, 0.0),
], loop=True)

# -- walk: a slow shamble, deliberately lopsided -----------------------------
walk_contact = {
    SP1: (7, 0, 0), SP2: (4, 0, 0), CH: (3, 0, -6), NK: (10, 0, 3), HD: (-7, 0, 0),
    CL_L: (0, 4, 0), CL_R: (0, -4, 0),
    UA_L: (15, 11, 0), UA_R: (-13, -11, 0),
    FA_L: (-20, 0, 0), FA_R: (-26, 0, 0),
    TH_L: (-24, 0, 0), SH_L: (9, 0, 0), FT_L: (-9, 0, 0),
    TH_R: (19, 0, 0), SH_R: (22, 0, 0), FT_R: (-16, 0, 0),
}
walk_pass = {
    SP1: (6, 0, 0), SP2: (4, 0, 0), CH: (2, 0, -2), NK: (9, 0, 1), HD: (-6, 0, 0),
    CL_L: (0, 4, 0), CL_R: (0, -4, 0),
    UA_L: (5, 12, 0), UA_R: (-4, -12, 0),
    FA_L: (-17, 0, 0), FA_R: (-19, 0, 0),
    TH_L: (-5, 0, 0), SH_L: (6, 0, 0), FT_L: (-5, 0, 0),
    TH_R: (-7, 0, 0), SH_R: (46, 0, 0), FT_R: (-12, 0, 0),
}
# The mirrored half gets a shorter stride and a heavier drop: the limp.
walk_contact_r = mirror(walk_contact)
walk_contact_r[TH_R] = (-18, 0, 0)
walk_contact_r[NK] = (11, 0, -4)
walk_pass_r = mirror(walk_pass)
make_action("walk", [
    (0, walk_contact, -0.022),
    (6, walk_pass, 0.018),
    (12, walk_contact_r, -0.034),
    (18, walk_pass_r, 0.010),
    (24, walk_contact, -0.022),
], loop=True)

# -- run: lurching sprint, hard forward lean, arms pumping -------------------
run_contact = {
    SP1: (15, 0, 0), SP2: (8, 0, 0), CH: (6, 0, -11), NK: (4, 0, 4), HD: (-14, 0, 0),
    CL_L: (-6, 5, 0), CL_R: (-6, -5, 0),
    UA_L: (34, 14, 0), UA_R: (-38, -14, 0),
    FA_L: (-72, 0, 0), FA_R: (-84, 0, 0),
    TH_L: (-46, 0, 0), SH_L: (16, 0, 0), FT_L: (-12, 0, 0),
    TH_R: (33, 0, 0), SH_R: (38, 0, 0), FT_R: (-22, 0, 0),
}
run_pass = {
    SP1: (16, 0, 0), SP2: (9, 0, 0), CH: (6, 0, -3), NK: (3, 0, 1), HD: (-15, 0, 0),
    CL_L: (-6, 5, 0), CL_R: (-6, -5, 0),
    UA_L: (10, 13, 0), UA_R: (-12, -13, 0),
    FA_L: (-78, 0, 0), FA_R: (-78, 0, 0),
    TH_L: (-12, 0, 0), SH_L: (10, 0, 0), FT_L: (-8, 0, 0),
    TH_R: (-14, 0, 0), SH_R: (86, 0, 0), FT_R: (-16, 0, 0),
}
make_action("run", [
    (0, run_contact, -0.045),
    (4, run_pass, 0.055),
    (8, mirror(run_contact), -0.045),
    (12, mirror(run_pass), 0.055),
    (16, run_contact, -0.045),
], loop=True)

# -- windup: settle into guard ----------------------------------------------
make_action("windup", [
    (0, NEUTRAL, 0.0),
    (7, blend(NEUTRAL, GUARD, 1.12), 0.03),
    (12, GUARD, 0.0),
], loop=False)

# -- attack_1: left straight ------------------------------------------------
jab = merged(GUARD, {
    CH: (4, 0, 14), SP2: (4, 0, 8), SP1: (6, 0, 5),
    CL_L: (-14, 10, 0), UA_L: (-120, 60, -79), FA_L: (-8, 0, 0),
    UA_R: (9, -26, 31), FA_R: (-130, 0, 0)})
make_action("attack_1", [
    (0, GUARD, 0.0),
    (3, jab, 0.01),
    (5, jab, 0.01),
    (9, GUARD, 0.0),
], loop=False)

# -- attack_2: right hook ---------------------------------------------------
hook = merged(GUARD, {
    CH: (4, 0, -22), SP2: (4, 0, -12), SP1: (6, 0, -7), HD: (-4, 0, 14),
    CL_R: (-14, -12, 0), UA_R: (-102, -51, 104), FA_R: (-10, 0, 0),
    UA_L: (9, 26, -31), FA_L: (-130, 0, 0)})
make_action("attack_2", [
    (0, GUARD, 0.0),
    (4, hook, 0.012),
    (6, hook, 0.012),
    (10, GUARD, 0.0),
], loop=False)

# -- attack_3: two-fisted overhead smash ------------------------------------
raise_up = merged(GUARD, {
    SP1: (-10, 0, 0), SP2: (-6, 0, 0), CH: (-5, 0, 0), NK: (-2, 0, 0),
    HD: (4, 0, 0),
    CL_L: (-22, 8, 0), CL_R: (-22, -8, 0),
    # The roll is what closes the V. The arm's rest direction carries a 35-degree
    # sideways component that no amount of X rotation removes, so raising on X
    # alone leaves the fists 1.3 m apart; the roll brings them to 0.43 m.
    UA_L: (-150, -45, 0), UA_R: (-150, 45, 0),
    FA_L: (-20, 0, 0), FA_R: (-20, 0, 0),
    TH_L: (-4, 0, 0), TH_R: (-4, 0, 0), SH_L: (8, 0, 0), SH_R: (8, 0, 0)})
# The spine bends cumulatively down the chain, so these stay modest: 28+16+10+14
# folded the skeleton fully in half and put the skull down by its own knees.
smash = merged(GUARD, {
    SP1: (16, 0, 0), SP2: (9, 0, 0), CH: (6, 0, 0), NK: (8, 0, 0),
    HD: (-8, 0, 0),
    CL_L: (6, 6, 0), CL_R: (6, -6, 0),
    UA_L: (-14, 14, 0), UA_R: (-14, -14, 0),
    FA_L: (-8, 0, 0), FA_R: (-8, 0, 0),
    TH_L: (-16, 0, 0), TH_R: (-16, 0, 0),
    SH_L: (26, 0, 0), SH_R: (26, 0, 0), FT_L: (-10, 0, 0), FT_R: (-10, 0, 0)})
make_action("attack_3", [
    (0, GUARD, 0.0),
    (3, raise_up, 0.04),
    (7, smash, -0.06),
    (9, smash, -0.06),
    (13, GUARD, 0.0),
], loop=False)

# -- lunge: the forward leap. Vertical hop only -- horizontal travel is the
#    controller's job, so the mesh must never drift off its own collider.
crouch = merged(GUARD, {
    SP1: (14, 0, 0), SP2: (8, 0, 0), CH: (5, 0, 0), NK: (8, 0, 0),
    HD: (-10, 0, 0),
    CL_L: (10, 6, 0), CL_R: (10, -6, 0),
    UA_L: (34, 16, 0), UA_R: (34, -16, 0),
    FA_L: (-54, 0, 0), FA_R: (-54, 0, 0),
    TH_L: (-34, 0, 0), TH_R: (-32, 0, 0),
    SH_L: (64, 0, 0), SH_R: (62, 0, 0),
    FT_L: (-24, 0, 0), FT_R: (-23, 0, 0)})
launch = merged(GUARD, {
    SP1: (-12, 0, 0), SP2: (-8, 0, 0), CH: (-6, 0, 0), NK: (-4, 0, 0),
    HD: (6, 0, 0),
    CL_L: (-20, 8, 0), CL_R: (-20, -8, 0),
    UA_L: (-118, 18, 0), UA_R: (-118, -18, 0),
    FA_L: (-30, 0, 0), FA_R: (-30, 0, 0),
    TH_L: (12, 0, 0), TH_R: (10, 0, 0),
    SH_L: (-4, 0, 0), SH_R: (-4, 0, 0),
    FT_L: (14, 0, 0), FT_R: (14, 0, 0)})
soar = merged(GUARD, {
    SP1: (4, 0, 0), SP2: (2, 0, 0), CH: (2, 0, 0), NK: (4, 0, 0),
    HD: (-6, 0, 0),
    CL_L: (-16, 10, 0), CL_R: (-16, -10, 0),
    UA_L: (-96, 20, 0), UA_R: (-96, -20, 0),
    FA_L: (-64, 0, 0), FA_R: (-64, 0, 0),
    TH_L: (-48, 0, 0), TH_R: (-44, 0, 0),
    SH_L: (72, 0, 0), SH_R: (68, 0, 0),
    FT_L: (-18, 0, 0), FT_R: (-18, 0, 0)})
strike = merged(GUARD, {
    SP1: (15, 0, 0), SP2: (8, 0, 0), CH: (5, 0, 0), NK: (8, 0, 0),
    HD: (-8, 0, 0),
    CL_L: (8, 6, 0), CL_R: (8, -6, 0),
    UA_L: (-18, 15, 0), UA_R: (-18, -15, 0),
    FA_L: (-10, 0, 0), FA_R: (-10, 0, 0),
    TH_L: (-30, 0, 0), TH_R: (-28, 0, 0),
    SH_L: (54, 0, 0), SH_R: (52, 0, 0),
    FT_L: (-20, 0, 0), FT_R: (-19, 0, 0)})
make_action("lunge", [
    (0, GUARD, 0.0),
    (4, crouch, -0.22),
    (8, launch, 0.20),
    (14, soar, 0.34),
    (19, strike, -0.14),
    (22, strike, -0.12),
    (26, GUARD, 0.0),
], loop=False)

# -- recover: unwind back to neutral ----------------------------------------
make_action("recover", [
    (0, blend(NEUTRAL, GUARD, 0.55), 0.0),
    (6, blend(NEUTRAL, GUARD, 0.18), -0.02),
    (12, NEUTRAL, 0.0),
], loop=False)

# --------------------------------------------------------------------------
# 8. export
# --------------------------------------------------------------------------
bpy.context.scene.render.fps = FPS
# The model ships with a demo action; it must not become a tenth clip in Godot.
for junk in [a for a in bpy.data.actions if a.name.startswith("DEMO")]:
    bpy.data.actions.remove(junk)
for pb in arm.pose.bones:
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = Quaternion()
    pb.location = Vector((0.0, 0.0, 0.0))

log("actions in file:", [a.name for a in bpy.data.actions])
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    export_animations=True,
    export_animation_mode='ACTIONS',
    export_nla_strips=False,
    export_bake_animation=True,
    export_anim_slide_to_zero=True,
    export_skins=True,
    export_apply=False,
    export_yup=True,
    export_materials='EXPORT',
    use_selection=False,
)
log("wrote", OUT)
