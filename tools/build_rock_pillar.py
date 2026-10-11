"""Build a procedural natural-rock column/pillar as a single GLB, headless.

    blender --background --factory-startup --python tools/build_rock_pillar.py -- \\
        models/kit/rock_pillar.glb [SIDES] [RINGS] [TEX_PX] \\
        [HEIGHT] [RADIUS] [BUMP_AMOUNT] [CRACK_DEPTH] [TEX_BASENAME]

Replaces the coursed-masonry `v2_pillar` for the boss-room columns and the
chest-room pedestals: the direction ruling was explicit that this had to read
as a rugged natural rock column, not bricks, so there is no coursing, no
mortar line and no repeating block pattern anywhere in the geometry or the
material -- both are built from continuous noise fields instead.

Shape: a tapered cylinder of rings, each ring's radius perturbed by 3D noise
(`mathutils.noise`, no external dependency) for an irregular silhouette, with
a second sharper/ridged noise carving crack-like grooves into the same radius
field. The first and last rings are pinned to an exact radius and exact
height (no noise on Z) so the pillar has a genuinely FLAT top and base --
chest pedestals sit a chest on top. Every other ring gets both radius noise
AND a little Z jitter, which is what keeps the faces from reading as a
smooth lathe-turned column.

**Built at its final, real-world size, not normalised-then-scaled.** The
first version of this tool always built a 1.0 m unit mesh and let the
in-game transform scale it up to a 9 m boss column -- which stretched the
baked crack texture into wood grain, and also meant `maze.gd` had to fall
back to world-triplanar to hide it, which in turn showed the UV island seams
as horizontal bands (a baked, non-tileable texture is not a tileable
triplanar texture). The material's noise/Voronoi nodes read `Object`
(world-space, absolute-metre) coordinates, so building directly at the
target HEIGHT/RADIUS gives the same crack density -- cracks per metre -- at
any final size with NO parameter changes below: bake `rock_column.glb` at
1.3 x 9.0 and `rock_pillar.glb` at 1.0 x 0.5-radius and both read as the same
family of stone, each on its own UVs, no triplanar needed.

Built along Blender +Z so `export_yup` lands it on Godot +Y -- see
`tools/build_sword.py` for the same convention. Origin at the centre of the
flat base.

Texture: no Tripo/photo source to grade here, so albedo + normal are baked
straight off a procedural Cycles material (noise + voronoi cracks feeding a
Bump node) onto the low-poly UV, the same "flat geometry, detail in the
normal map" trade `organic_maze.gd`'s kit stone already relies on. The albedo
is leaned cool (see `STONE_CAST` in `module_level.gd`) rather than neutral
grey, because every light in this game is a fire and a neutral grey reads as
brown under one -- this is baked into the texture itself so the lead does
not need a tint override to get grey back. Roughness is left a constant on
the material rather than baked, to keep this to two textures per mesh.
"""

import bpy
import bmesh
import sys
import math
from mathutils import Vector, noise

ARGV = sys.argv[sys.argv.index("--") + 1:]
OUT = ARGV[0] if len(ARGV) > 0 else "models/kit/rock_pillar.glb"
SIDES = int(ARGV[1]) if len(ARGV) > 1 else 28
RINGS = int(ARGV[2]) if len(ARGV) > 2 else 52
TEX_PX = int(ARGV[3]) if len(ARGV) > 3 else 2048
HEIGHT = float(ARGV[4]) if len(ARGV) > 4 else 1.0
BASE_RADIUS = float(ARGV[5]) if len(ARGV) > 5 else 0.5
# How much the silhouette wanders off the taper curve, in absolute metres --
# NOT a fraction of the radius, because the column's collision cylinder is a
# hard 0.65 m +/- 0.03 m budget regardless of how tall the mesh is.
BUMP_AMOUNT = float(ARGV[6]) if len(ARGV) > 6 else 0.10
# Depth of the crack grooves cut by the ridged/voronoi-style noise, also
# absolute metres.
CRACK_DEPTH = float(ARGV[7]) if len(ARGV) > 7 else 0.06
TEX_BASENAME = ARGV[8] if len(ARGV) > 8 else "rock"
# Scales the foot flare and the authored ledges (below), separately from the
# noise bump/crack -- the boss column wants a properly craggy monolith with
# a wide foot and distinct shelves, but the SAME feature list at full
# strength on the short pedestal/step range nearly doubled its footprint,
# which nothing asked for and which the existing step spacing was not
# measured against. 1.0 for the column, small for the pedestal.
SHAPE_FEATURE_SCALE = float(ARGV[9]) if len(ARGV) > 9 else 0.15

# Taper -- real load-bearing columns are rarely perfect cylinders, and a
# dead-uniform radius top to bottom is exactly what reads as lathe-turned /
# smooth concrete rather than quarried rock.
TOP_RADIUS_FACTOR = 0.78
# A wider foot: real monoliths stand on a broader base than their shaft.
# Fraction of BASE_RADIUS added at z=0, decaying with height.
FOOT_FLARE_FRAC = 0.30
FOOT_FLARE_DECAY = 5.5
# Explicit ledge/bulge features: ONE mesh reading as uniformly corrugated
# noise does not read as a natural monolith the way a couple of distinct
# shelves and bulges do. Each entry is
# (height_frac, angle_rad, angular_half_width, height_half_width, strength
# as a fraction of BASE_RADIUS). Fixed, not randomised, so the silhouette is
# authored rather than left entirely to noise.
LEDGES = [
    (0.10, 0.9, 1.1, 0.10, 0.34),
    (0.30, 3.7, 1.4, 0.16, 0.24),
    (0.62, 5.1, 1.0, 0.13, 0.22),
    (0.85, 2.1, 1.3, 0.11, 0.16),
]
# How far alternating rings jitter in Z, as a fraction of the ring spacing --
# what keeps mid-column faces from reading as a smooth lathe curve.
Z_JITTER = 0.22


def _angle_diff(a, b):
    d = (a - b) % (2.0 * math.pi)
    if d > math.pi:
        d -= 2.0 * math.pi
    return d


def ledge_bump(z_frac, angle):
    """Authored bulges/shelves, in metres, added on top of the noise field."""
    total = 0.0
    for hc, ac, aw, hw, strength in LEDGES:
        dz = (z_frac - hc) / hw
        da = _angle_diff(angle, ac) / aw
        total += (BASE_RADIUS * strength) * math.exp(-(dz * dz + da * da))
    return total * SHAPE_FEATURE_SCALE


def foot_flare(z_frac):
    return BASE_RADIUS * FOOT_FLARE_FRAC * math.exp(-z_frac * FOOT_FLARE_DECAY) * SHAPE_FEATURE_SCALE


def log(*a):
    print("[rock_pillar]", *a)


def radius_noise(angle, height_frac, seed):
    """3D noise sampled around the column's own cylinder, so it wraps with no
    seam at angle 0 / 2*pi -- sampling a 3D field on the cylinder's surface
    avoids the seam a 2D noise indexed by angle directly would show."""
    p = Vector((
        math.cos(angle) * 1.6 + seed,
        math.sin(angle) * 1.6 + seed * 0.7,
        height_frac * 2.4 + seed * 1.3,
    ))
    return noise.noise(p, noise_basis="PERLIN_ORIGINAL")


def crack_noise(angle, height_frac, seed):
    """A second, higher-frequency field standing in for a crack pattern:
    `turbulence` folds negative lobes back positive, which produces the thin
    sharp ridges/valleys a crack network needs instead of Perlin's rounded
    blobs."""
    p = Vector((
        math.cos(angle) * 4.2 + seed * 1.7,
        math.sin(angle) * 4.2 - seed,
        height_frac * 5.0 + seed * 2.1,
    ))
    t = noise.turbulence(p, 3, True, noise_basis="PERLIN_ORIGINAL")
    # Sharpen into thin grooves rather than broad bands.
    return max(0.0, t - 0.55)


def build_pillar(sides, rings, seed):
    bm = bmesh.new()
    ring_verts = []
    radii = []

    for i in range(rings + 1):
        z_frac = i / rings
        pinned = (i == 0 or i == rings)
        taper = 1.0 + (TOP_RADIUS_FACTOR - 1.0) * z_frac
        base_r = BASE_RADIUS * taper
        z = HEIGHT * z_frac

        verts = []
        for j in range(sides):
            angle = 2.0 * math.pi * j / sides
            # The flat-cap contract only pins Z -- the footprint on the cap
            # rings can (and should) be just as irregular as the shaft, or
            # the base reads as a lathe-turned disc under a craggy shaft.
            bump = radius_noise(angle, z_frac, seed) * BUMP_AMOUNT
            crack = crack_noise(angle, z_frac, seed) * CRACK_DEPTH
            r = max(base_r * 0.55, base_r + bump - crack
                + ledge_bump(z_frac, angle) + foot_flare(z_frac))
            if pinned:
                zz = z
            else:
                # Small, per-vertex height jitter -- lumpy faces rather than a
                # lathe-smooth curve. Scaled by the noise so it is not just a
                # uniform corrugation.
                zz = z + (radius_noise(angle * 1.7, z_frac + 0.5, seed + 4.1)
                    * (HEIGHT / rings) * Z_JITTER)
            x = math.cos(angle) * r
            y = math.sin(angle) * r
            verts.append(bm.verts.new((x, y, zz)))
            radii.append(r)
        ring_verts.append(verts)

    # Side faces.
    for i in range(rings):
        a = ring_verts[i]
        b = ring_verts[i + 1]
        for j in range(sides):
            j2 = (j + 1) % sides
            try:
                bm.faces.new((a[j], a[j2], b[j2], b[j]))
            except ValueError:
                pass

    # Flat caps. Centre vertices sit exactly on the pinned rings, so both
    # caps are true planes.
    base_centre = bm.verts.new((0.0, 0.0, 0.0))
    top_centre = bm.verts.new((0.0, 0.0, HEIGHT))
    base_ring = ring_verts[0]
    top_ring = ring_verts[-1]
    for j in range(sides):
        j2 = (j + 1) % sides
        try:
            bm.faces.new((base_centre, base_ring[j2], base_ring[j]))
        except ValueError:
            pass
        try:
            bm.faces.new((top_centre, top_ring[j], top_ring[j2]))
        except ValueError:
            pass

    bm.normal_update()
    mesh = bpy.data.meshes.new("RockPillar")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("RockPillar", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj, radii


def build_material():
    mat = bpy.data.materials.new("RockStone")
    mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    for n in list(nodes):
        nodes.remove(n)

    out = nodes.new("ShaderNodeOutputMaterial")
    out.location = (900, 0)
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (600, 0)
    bsdf.inputs["Roughness"].default_value = 0.92
    bsdf.inputs["Metallic"].default_value = 0.0
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    coord = nodes.new("ShaderNodeTexCoord")
    coord.location = (-1000, 0)

    # Patchy variation between two dark greys, leaned cool the same way
    # `STONE_CAST` in `module_level.gd` leans the rest of the level's stone
    # (0.88, 0.94, 1.06): every light in this game is a fire, and a neutral
    # grey came back tan/pink in the actual game shots. Baking the cool cast
    # into the texture itself is what lets the lead drop the albedo tint
    # override entirely.
    #
    # Scale 3.2 put maybe one whole patch across a 1 m pedestal's visible
    # face -- in the actual game shot that read as a couple of big pink/grey
    # camouflage blotches, not stone. Scale 12 gives roughly the same patch
    # density the corridor wall stone reads at; the colours are also pulled
    # much darker and closer together (median corridor-wall value, not a
    # pale concrete tone) so the relief -- not the paint -- does the work.
    noise1 = nodes.new("ShaderNodeTexNoise")
    noise1.location = (-800, 200)
    noise1.inputs["Scale"].default_value = 12.0
    noise1.inputs["Detail"].default_value = 4.0
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.location = (-550, 200)
    # Darkened again from an already-dark first pass: the boss columns carry
    # FOUR torches mounted flush against their own faces (`maze.gd`'s
    # per-pillar torch loop, ~6 cm standoff) rather than one torch shared
    # over a stretch of corridor wall, so the surface takes far more direct,
    # close-range light than anything else in the room reads under. No
    # amount of darkening fixes an overexposed point-light hotspot, but this
    # gives the un-lit / ambient-only parts of the column a real chance of
    # reading as dark stone instead of pale concrete.
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.014, 0.016, 0.021, 1.0)
    ramp.color_ramp.elements[1].position = 0.68
    ramp.color_ramp.elements[1].color = (0.036, 0.040, 0.048, 1.0)
    links.new(coord.outputs["Object"], noise1.inputs["Vector"])
    links.new(noise1.outputs["Fac"], ramp.inputs["Fac"])

    # Fine facet variation, mixed in lightly.
    noise2 = nodes.new("ShaderNodeTexNoise")
    noise2.location = (-800, -50)
    noise2.inputs["Scale"].default_value = 18.0
    noise2.inputs["Detail"].default_value = 5.0
    links.new(coord.outputs["Object"], noise2.inputs["Vector"])

    # Voronoi "distance to edge" reads as a crack network between cells.
    voro = nodes.new("ShaderNodeTexVoronoi")
    voro.location = (-800, -300)
    voro.voronoi_dimensions = "3D"
    voro.feature = "DISTANCE_TO_EDGE"
    voro.inputs["Scale"].default_value = 6.0
    links.new(coord.outputs["Object"], voro.inputs["Vector"])
    crack_ramp = nodes.new("ShaderNodeValToRGB")
    crack_ramp.location = (-550, -300)
    crack_ramp.color_ramp.elements[0].position = 0.0
    crack_ramp.color_ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    # `DISTANCE_TO_EDGE` ranges roughly 0 (on a cell edge) to about half the
    # cell spacing (on this project's first pass, scale 6.0 gave a ~0.08
    # half-width, and a 0.06 threshold here read most of each cell's AREA as
    # "near an edge" -- the crack read as solid dark polygons with a small
    # bright core, the opposite of a hairline crack in a mostly-intact facet.
    # A narrow threshold keeps the dark band to an actual thin seam.
    crack_ramp.color_ramp.elements[1].position = 0.012
    crack_ramp.color_ramp.elements[1].color = (1.0, 1.0, 1.0, 1.0)
    links.new(voro.outputs["Distance"], crack_ramp.inputs["Fac"])

    # Albedo: base ramp, darkened along the crack lines, with a touch of the
    # fine noise mixed in so flat-shaded facets do not look pasted-on.
    mix_fine = nodes.new("ShaderNodeMix")
    mix_fine.location = (-300, 100)
    mix_fine.data_type = "RGBA"
    mix_fine.inputs["Factor"].default_value = 0.18
    links.new(ramp.outputs["Color"], mix_fine.inputs[6])
    links.new(noise2.outputs["Fac"], mix_fine.inputs[7])

    darken = nodes.new("ShaderNodeMix")
    darken.location = (-60, 100)
    darken.data_type = "RGBA"
    darken.blend_type = "MULTIPLY"
    darken.inputs["Factor"].default_value = 0.85
    links.new(mix_fine.outputs[2], darken.inputs[6])
    crack_dark = nodes.new("ShaderNodeMix")
    crack_dark.location = (-300, -150)
    crack_dark.data_type = "RGBA"
    crack_dark.inputs["Factor"].default_value = 1.0
    # This was (0.42, 0.40, 0.38) -- R > B, i.e. slightly WARM -- which was
    # fighting the cool cast everywhere else and reads as the crack lines
    # being the one part of the rock that goes brown under torchlight. Cool
    # to match.
    crack_dark.inputs[6].default_value = (0.38, 0.40, 0.45, 1.0)
    crack_dark.inputs[7].default_value = (1.0, 1.0, 1.0, 1.0)
    links.new(crack_ramp.outputs["Color"], crack_dark.inputs["Factor"])
    links.new(crack_dark.outputs[2], darken.inputs[7])

    albedo_img = bpy.data.images.new(TEX_BASENAME + "_albedo", TEX_PX, TEX_PX, alpha=False)
    albedo_node = nodes.new("ShaderNodeTexImage")
    albedo_node.location = (-350, 450)
    albedo_node.image = albedo_img
    links.new(darken.outputs[2], bsdf.inputs["Base Color"])

    # Bump height: mostly the crack grooves (deep, sharp) plus a little of
    # the fine noise (shallow, broad) so the normal map carries both.
    bump_mix = nodes.new("ShaderNodeMix")
    bump_mix.location = (200, -250)
    bump_mix.data_type = "FLOAT"
    bump_mix.inputs["Factor"].default_value = 0.7
    links.new(noise2.outputs["Fac"], bump_mix.inputs[2])
    links.new(crack_ramp.outputs["Color"], bump_mix.inputs[3])
    bump = nodes.new("ShaderNodeBump")
    bump.location = (400, -250)
    # Turned up from 0.38: with the albedo now much flatter (see noise1
    # above), the crack/facet relief is what has to read as "rock" rather
    # than "smooth concrete", especially on the boss column.
    bump.inputs["Strength"].default_value = 0.68
    bump.inputs["Distance"].default_value = 0.04
    links.new(bump_mix.outputs[0], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    normal_img = bpy.data.images.new(TEX_BASENAME + "_normal", TEX_PX, TEX_PX, alpha=False)
    normal_img.colorspace_settings.name = "Non-Color"
    normal_node = nodes.new("ShaderNodeTexImage")
    normal_node.location = (-350, -600)
    normal_node.image = normal_img

    return mat, albedo_node, normal_node, albedo_img, normal_img


def bake(obj, node, image, bake_type, pass_filter=None):
    nt = obj.active_material.node_tree
    for n in nt.nodes:
        n.select = False
    node.select = True
    nt.nodes.active = node
    kwargs = {"type": bake_type}
    if bake_type == "NORMAL":
        kwargs["normal_space"] = "TANGENT"
    if pass_filter is not None:
        kwargs["pass_filter"] = pass_filter
    with bpy.context.temp_override(active_object=obj, object=obj,
                                   selected_objects=[obj],
                                   selected_editable_objects=[obj]):
        bpy.ops.object.bake(**kwargs)
    log("baked", bake_type, image.name)


# ---------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)

obj, radii = build_pillar(SIDES, RINGS, seed=7.31)
obj.data.calc_loop_triangles()
tris_in = len(obj.data.loop_triangles)
log("built %d sides x %d rings -> %d triangles" % (SIDES, RINGS, tris_in))

radii.sort()
n = len(radii)
p50 = radii[int(n * 0.50)]
p75 = radii[int(n * 0.75)]
p90 = radii[int(n * 0.90)]
p99 = radii[int(n * 0.99)]
rmax = radii[-1]
log("radius stats: median %.4f  p75 %.4f  p90 %.4f  p99 %.4f  max %.4f (nominal %.4f)"
    % (p50, p75, p90, p99, rmax, BASE_RADIUS))

bpy.context.view_layer.objects.active = obj
obj.select_set(True)
with bpy.context.temp_override(active_object=obj, object=obj,
                               selected_objects=[obj],
                               selected_editable_objects=[obj]):
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    # Smart UV project needs face-angle-based islands; the flat caps and the
    # ringed sides naturally split into sane islands with the default angle.
    bpy.ops.uv.smart_project(angle_limit=math.radians(60.0), island_margin=0.02)
    bpy.ops.object.mode_set(mode='OBJECT')
log("UV unwrapped (smart project)")

mat, albedo_node, normal_node, albedo_img, normal_img = build_material()
obj.data.materials.append(mat)

# Auto-smooth: enough angle to keep the ring facets and the flat caps crisp
# while still smoothing across each facet's own triangulation, so the low
# side/ring count doesn't read as an obviously faceted drum.
try:
    with bpy.context.temp_override(active_object=obj, object=obj,
                                   selected_objects=[obj],
                                   selected_editable_objects=[obj]):
        bpy.ops.object.shade_auto_smooth(angle=math.radians(42.0))
except Exception as exc:
    log("auto smooth unavailable, leaving flat:", exc)

# --- bake ---------------------------------------------------------------
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 24
scene.render.bake.margin = 8

sun = bpy.data.objects.new("BakeSun", bpy.data.lights.new("BakeSun", type='SUN'))
sun.data.energy = 2.0
scene.collection.objects.link(sun)

bake(obj, albedo_node, albedo_img, "DIFFUSE", pass_filter={"COLOR"})
bake(obj, normal_node, normal_img, "NORMAL")

# Wire the baked textures back into the material so both the export AND a
# live Blender preview show the same result the bake produced -- leaving the
# procedural graph connected would export those unbaked node types instead.
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
nt.links.new(albedo_node.outputs["Color"], bsdf.inputs["Base Color"])
normal_map = nt.nodes.new("ShaderNodeNormalMap")
normal_map.location = (-60, -450)
nt.links.new(normal_node.outputs["Color"], normal_map.inputs["Color"])
nt.links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])

import os
# OUT is normally "models/kit/rock_pillar.glb"; textures/ is a sibling of
# models/ at the project root, matching every other file this worker owns.
proj_root = os.getcwd()
tex_dir = os.path.join(proj_root, "textures")
os.makedirs(tex_dir, exist_ok=True)
albedo_path = os.path.join(tex_dir, TEX_BASENAME + "_albedo.png")
normal_path = os.path.join(tex_dir, TEX_BASENAME + "_normal.png")
albedo_img.filepath_raw = albedo_path
albedo_img.file_format = 'PNG'
albedo_img.save()
normal_img.filepath_raw = normal_path
normal_img.file_format = 'PNG'
normal_img.save()
log("saved", albedo_path)
log("saved", normal_path)

# --- measure before export ------------------------------------------------
verts = [v.co for v in obj.data.vertices]
lo = Vector((min(v.x for v in verts), min(v.y for v in verts), min(v.z for v in verts)))
hi = Vector((max(v.x for v in verts), max(v.y for v in verts), max(v.z for v in verts)))
size = hi - lo
log("bounds %.4f x %.4f x %.4f, origin offset from base centre (%.4f, %.4f, %.4f)"
    % (size.x, size.y, size.z, lo.x + size.x * 0.5, lo.y + size.y * 0.5, lo.z))

out_path = OUT if os.path.isabs(OUT) else os.path.join(proj_root, OUT)
os.makedirs(os.path.dirname(out_path), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path,
    export_format='GLB',
    export_animations=False,
    export_skins=False,
    export_apply=False,
    export_yup=True,
    export_materials='EXPORT',
    export_image_format='AUTO',
    use_selection=False,
)
log("wrote", out_path)

# --- verify the file, not the scene ---------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=out_path)
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
log("VERIFY on disk %.4f x %.4f x %.4f (Blender Z-up), %d triangles"
    % (shipped.x, shipped.y, shipped.z, out_tris))
log("VERIFY base at z=%.4f (want ~0.0)" % lo.z)
