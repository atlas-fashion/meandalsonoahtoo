"""The scoutposts' timber balcony and stair (note 181), modelled in Blender from nothing
and baked PBR.

    blender -b --python tools/build_scoutpost_kit.py

Writes models/scoutpost_kit.glb: one object per piece, all on ONE material whose
textures are baked here into a shared atlas (albedo 4096, normal 4096, ORM 2048:
R occlusion, G roughness, B metal). Reuses build_cell_kit.py's geometry helpers,
its iron and stone materials and its Graph node builder. Pieces, in Godot's frame
(y up), the wall at z 0 and the hall at +z:

  deck_bay    one BAY (3.0 m) of the balcony's deck: six hand-sawn planks with
              gaps, three joists under them, the front beam (at z FRONT) and the
              ledger against the wall, bolts and nails. Origin on the deck's top
              at the wall, in the bay's middle; x -1.5..1.5. Laid end to end.
  post        a hewn post on a stone pad, floor to the railing's top, a knee
              brace each way up to the front beam, bolted, an iron band. Origin
              on the floor at its middle.
  post_end    the same with one brace, towards +x (mirrored for the other end).
  rail_bay    one bay of railing between two posts: top and middle rails and
              three balusters. Origin on the deck's top at the post line.
  stair       a closed-string stair against the wall, rising towards -x: its
              foot at x 0, the deck's edge at x -RUN; z 0 (wall side) .. STAIR_W;
              twelve risers, a handrail on newels on the open side.

The timbers carry their axis as a vertex attribute ("axis"), so the wood's grain
runs along each one whatever way it lies.
"""
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_cell_kit as ck  # noqa: E402

OUT = os.path.join(ck.ROOT, "models", "scoutpost_kit.glb")
ATLAS = 4096
ORM_TEX = 2048
MARGIN = 8
PREVIEW = "--preview" in sys.argv

# Must match scoutpost.gd.
DECK_Y = 2.15
BAY = 3.0
DEPTH = 1.75
FRONT = 1.65
RAIL = 1.0
RUN = 3.4
STAIR_W = 1.1
STEPS = 12

random.seed(0x73636f75)


def log(*a):
    print("[scoutpost_kit]", *a, flush=True)


class WAcc(ck.Acc):
    """The cell kit's accumulator, recording each vertex's timber axis."""

    def __init__(self):
        super().__init__()
        self.ax = []
        self.cur = Vector((1, 0, 0))

    def add_v(self, p):
        self.ax.append(self.cur.copy())
        return super().add_v(p)


def chamfer_rect(w, h, c):
    hw, hh = w / 2, h / 2
    return [(-hw + c, -hh), (hw - c, -hh), (hw, -hh + c), (hw, hh - c),
            (hw - c, hh), (-hw + c, hh), (-hw, hh - c), (-hw, -hh + c)]


def timber(acc, a, b, w, h, kind="wood", c=0.015, warp=0.006):
    """A hewn timber from a to b: a chamfered section, a little out of true."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    acc.cur = d
    n = max(2, int((b - a).length / 0.3) + 1)
    seed = random.random() * 100.0
    pts = []
    for i in range(n + 1):
        t = i / n
        p = a + (b - a) * t
        if 0 < i < n:
            off = Vector((noise.noise(Vector((t * 2.5 + seed, seed, 0.0))),
                          noise.noise(Vector((seed, t * 2.5 + seed, 1.0))),
                          noise.noise(Vector((0.0, seed, t * 2.5 + seed)))))
            off -= d * off.dot(d)
            p += off * warp
        pts.append(p)
    ck.sweep(acc, pts, chamfer_rect(w, h, c), kind)


def bolt(acc, a, b, r=0.016):
    acc.cur = Vector((1, 0, 0))
    ck.cyl(acc, a, b, r, 8, "iron")


def finish(name, acc):
    ob = ck.make_object(name, acc)
    attr = ob.data.attributes.new("axis", "FLOAT_VECTOR", "POINT")
    vals = []
    for v in acc.ax:
        vals += [v.x, -v.z, v.y]
    attr.data.foreach_set("vector", vals)
    return ob


# --- pieces ----------------------------------------------------------------------------

def build_deck_bay():
    acc = WAcc()
    x0, x1 = -BAY / 2, BAY / 2
    n = 6
    gap = 0.012
    pw = (DEPTH - 0.05 - gap * (n - 1)) / n
    joists = (-1.0, 0.0, 1.0)
    for i in range(n):
        z = 0.05 + pw / 2 + i * (pw + gap) + random.uniform(-0.005, 0.005)
        y = -0.025 + random.uniform(-0.004, 0.003)
        timber(acc, (x0 + random.uniform(-0.02, 0.015), y, z), (x1 + random.uniform(-0.015, 0.02), y, z),
               pw, 0.05, "plank", c=0.007, warp=0.004)
        for xj in joists:
            for s in (-0.3, 0.3):
                bolt(acc, (xj + random.uniform(-0.01, 0.01), -0.004, z + s * pw), (xj, 0.004, z + s * pw), 0.007)
    for xj in joists:
        timber(acc, (xj, -0.13, 0.32), (xj, -0.13, FRONT - 0.1), 0.1, 0.16, "wood", c=0.01)
    timber(acc, (x0, -0.17, FRONT), (x1, -0.17, FRONT), 0.22, 0.24, "wood", c=0.02, warp=0.01)
    timber(acc, (x0, -0.15, 0.33), (x1, -0.15, 0.33), 0.14, 0.2, "wood", c=0.015)
    for xb in (-0.9, 0.9):
        bolt(acc, (xb, -0.15, 0.24), (xb, -0.15, 0.42), 0.012)
        bolt(acc, (xb, -0.15, 0.4), (xb, -0.15, 0.415), 0.03)
    return [finish("deck_bay", acc)]


def build_post(name, sides):
    acc = WAcc()
    top = DECK_Y + RAIL + 0.08
    acc.cur = Vector((0, 1, 0))
    ck.stone_block(acc, (0.0, 0.06, 0.0), (0.38, 0.12, 0.38), "stone", cuts=3, chip=0.01, seed=random.random() * 9)
    timber(acc, (0.0, 0.12, 0.0), (0.0, top, 0.0), 0.22, 0.22, "wood", c=0.022, warp=0.008)
    acc.cur = Vector((0, 1, 0))
    ck.box(acc, (0.0, DECK_Y - 0.33, 0.0), (0.235, 0.05, 0.235), "iron")
    for s in sides:
        timber(acc, (s * 0.1, DECK_Y - 1.0, 0.0), (s * 0.86, DECK_Y - 0.3, 0.0), 0.12, 0.12, "wood", c=0.012)
        for p in ((s * 0.16, DECK_Y - 0.97), (s * 0.8, DECK_Y - 0.33)):
            bolt(acc, (p[0], p[1], -0.072), (p[0], p[1], 0.072), 0.014)
    return finish(name, acc)


def build_rail_bay():
    acc = WAcc()
    x0, x1 = -BAY / 2 + 0.11, BAY / 2 - 0.11
    timber(acc, (x0, RAIL - 0.045, 0.0), (x1, RAIL - 0.045, 0.0), 0.1, 0.09, "wood", c=0.015)
    timber(acc, (x0, 0.48, 0.0), (x1, 0.48, 0.0), 0.06, 0.07, "wood", c=0.01)
    for xb in (-0.75, 0.0, 0.75):
        xb += random.uniform(-0.04, 0.04)
        timber(acc, (xb, 0.0, 0.0), (xb, RAIL - 0.09, 0.0), 0.06, 0.06, "wood", c=0.008, warp=0.004)
    return [finish("rail_bay", acc)]


def build_stair():
    acc = WAcc()
    rise = DECK_Y / STEPS
    tr = RUN / (STEPS - 1)
    for z in (0.035, STAIR_W - 0.035):
        timber(acc, (0.06, -0.02, z), (-RUN, DECK_Y - 0.19, z), 0.06, 0.3, "wood", c=0.01, warp=0.006)
    for k in range(1, STEPS):
        x = -(k - 0.5) * tr
        y = k * rise - 0.022
        timber(acc, (x, y, 0.0), (x, y, STAIR_W), tr + 0.04, 0.045, "plank", c=0.008, warp=0.003)
        for z in (0.035, STAIR_W - 0.035):
            for s in (-0.25, 0.25):
                bolt(acc, (x + s * tr, y + 0.018, z), (x + s * tr, y + 0.027, z), 0.008)
    hz = STAIR_W + 0.02
    timber(acc, (0.02, 0.0, hz), (0.02, RAIL + 0.08, hz), 0.12, 0.12, "wood", c=0.015)
    timber(acc, (-RUN + 0.08, 0.0, hz), (-RUN + 0.08, DECK_Y + RAIL + 0.08, hz), 0.14, 0.14, "wood", c=0.016)
    timber(acc, (0.02, RAIL, hz), (-RUN + 0.08, DECK_Y + RAIL, hz), 0.08, 0.08, "wood", c=0.012)
    for f in (0.25, 0.5, 0.75):
        x = -RUN * f
        foot = int(f * (STEPS - 1)) * rise + rise
        timber(acc, (x, foot, hz), (x, RAIL + DECK_Y * f - 0.04, hz), 0.05, 0.05, "wood", c=0.007, warp=0.003)
    return [finish("stair", acc)]


# --- the wood --------------------------------------------------------------------------

def vm(g, op, a, b=None, s=None):
    n = g.n("ShaderNodeVectorMath", operation=op)
    g.link(a, n.inputs[0])
    if b is not None:
        g.link(b, n.inputs[1])
    if s is not None:
        if isinstance(s, (int, float)):
            n.inputs[3].default_value = s
        else:
            g.link(s, n.inputs[3])
    return n


def wood_material(kind):
    """Old dark timber: grain streaked along each piece's axis, checks, worn pale
    edges, grime in the joints, dust on what faces up."""
    mat = bpy.data.materials.new("k_" + kind)
    mat.use_nodes = True
    g = ck.Graph(mat)
    ao = g.ao.outputs["AO"]
    crev = g.math("SUBTRACT", 1.0, ao, clamp=True)
    edge = g.ramp(g.geo.outputs["Pointiness"], 0.53, 0.62)
    pos = g.tc.outputs["Object"]
    axis = g.n("ShaderNodeAttribute", attribute_name="axis").outputs["Vector"]
    along = vm(g, "DOT_PRODUCT", pos, axis).outputs["Value"]
    squash = vm(g, "SCALE", axis, s=g.math("MULTIPLY", along, 0.94)).outputs["Vector"]
    grain_vec = vm(g, "SUBTRACT", pos, squash).outputs["Vector"]
    grain = g.noise(7.0, 9, 0.62, vec=grain_vec)
    fine = g.noise(55.0, 4, 0.5, vec=grain_vec)
    blotch = g.noise(1.6, 5, 0.6)
    check = g.ramp(g.noise(16.0, 3, 0.4, vec=grain_vec), 0.66, 0.72)
    sep = g.n("ShaderNodeSeparateXYZ")
    g.link(g.geo.outputs["Normal"], sep.inputs[0])
    up = g.ramp(sep.outputs["Z"], 0.55, 0.95)
    if kind == "plank":
        lo, hi = (0.05, 0.034, 0.022), (0.12, 0.085, 0.055)
    else:
        lo, hi = (0.04, 0.027, 0.018), (0.1, 0.07, 0.045)
    col = g.mix(lo, hi, g.ramp(grain, 0.3, 0.72))
    col = g.scale_col(col, g.lerp(0.75, 1.15, g.ramp(fine, 0.35, 0.65)))
    col = g.scale_col(col, g.lerp(0.7, 1.1, blotch))
    # Worn bright at the arrises, grey dust on what faces up, black in the checks.
    col = g.mix(col, (0.17, 0.13, 0.09), g.math("MULTIPLY", edge, 0.55))
    col = g.mix(col, (0.09, 0.085, 0.078), g.math("MULTIPLY", up, g.math("MULTIPLY", g.ramp(blotch, 0.4, 0.7), 0.5)))
    col = g.mix(col, (0.008, 0.006, 0.005), g.math("MULTIPLY", check, 0.85))
    col = g.scale_col(col, g.math("SUBTRACT", 1.0, g.math("MULTIPLY", crev, 0.65)))
    rough = g.math("ADD", g.lerp(0.72, 0.9, fine), g.math("MULTIPLY", edge, -0.12))
    metal = 0.0
    height = g.math("ADD", g.math("MULTIPLY", grain, 0.45), g.math("MULTIPLY", fine, 0.35))
    height = g.math("SUBTRACT", height, g.math("MULTIPLY", check, 0.6))
    bsdf = g.n("ShaderNodeBsdfPrincipled")
    g.link(col, bsdf.inputs["Base Color"])
    g.link(rough, bsdf.inputs["Roughness"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bump = g.n("ShaderNodeBump")
    bump.inputs["Distance"].default_value = 0.003
    g.link(height, bump.inputs["Height"])
    g.link(bump.outputs["Normal"], bsdf.inputs["Normal"])
    emit = g.n("ShaderNodeEmission")
    target = g.n("ShaderNodeTexImage")
    target.name = "BAKE"
    ck.MATS[kind] = mat
    return mat, g, {"color": col, "rough": rough, "metal": metal, "bsdf": bsdf, "emit": emit, "target": target}


# --- the build -----------------------------------------------------------------------------

def main():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    for kind in ("iron", "stone"):
        ck.GRAPHS[kind] = ck.build_material(kind)
    for kind in ("wood", "plank"):
        ck.GRAPHS[kind] = wood_material(kind)

    groups = [
        ("deck_bay", build_deck_bay(), "wall"),
        ("post", [build_post("post", (-1.0, 1.0))], "floor"),
        ("post_end", [build_post("post_end", (1.0,))], "floor"),
        ("rail_bay", build_rail_bay(), "none"),
        ("stair", build_stair(), "wall+floor"),
    ]
    targets = [o for _, obs, _ in groups for o in obs]
    for o in targets:
        ck.smooth_by_angle(o, 35)
        log("%-10s %6d triangles" % (o.name, ck.tris(o)))
    log("total %d triangles" % sum(ck.tris(o) for o in targets))

    helpers = []
    for i, (gname, obs, backing) in enumerate(groups):
        off = Vector((i * 9.0, 0, 0))
        for o in obs:
            o.location = off
        if "wall" in backing:
            bpy.ops.mesh.primitive_plane_add(size=6.0, location=off + Vector((0, 0.003, 1.0)), rotation=(math.pi / 2, 0, 0))
            helpers.append(bpy.context.active_object)
        if "floor" in backing:
            bpy.ops.mesh.primitive_plane_add(size=6.0, location=off + Vector((0, -2.0, -0.002)))
            helpers.append(bpy.context.active_object)
    for h in helpers:
        h.data.materials.append(ck.MATS["stone"])

    for o in targets:
        me = o.data
        lay = me.uv_layers.get("atlas") or me.uv_layers.new(name="atlas")
        me.uv_layers.active = lay
        lay.active_render = True
    for o in bpy.context.scene.objects:
        o.select_set(o in targets)
    bpy.context.view_layer.objects.active = targets[0]
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    bpy.ops.uv.pack_islands(rotate=True, margin=0.0015)
    bpy.ops.object.mode_set(mode="OBJECT")

    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        scn.cycles.device = "GPU"
    except Exception as ex:  # noqa: BLE001
        log("bake on CPU:", ex)
    scn.render.bake.margin = MARGIN
    scn.world = bpy.data.worlds.new("bake")
    scn.world.light_settings.distance = 0.35

    def bake(name, kind, size, samples):
        img = bpy.data.images.new(name, size, size, alpha=False, float_buffer=True)
        img.colorspace_settings.name = "Non-Color"
        ck.set_pass(kind if kind in ("NORMAL", "AO") else name.split("_")[-1], img)
        scn.cycles.samples = samples
        for o in bpy.context.scene.objects:
            o.select_set(o in targets)
        bpy.context.view_layer.objects.active = targets[0]
        if kind == "NORMAL":
            bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=MARGIN)
        elif kind == "AO":
            bpy.ops.object.bake(type="AO", margin=MARGIN)
        else:
            bpy.ops.object.bake(type="EMIT", margin=MARGIN)
        buf = np.empty(size * size * 4, dtype=np.float32)
        img.pixels.foreach_get(buf)
        log("baked", name)
        return buf.reshape(size, size, 4)

    col = bake("bake_color", "EMIT", ATLAS, 4)
    nrm = bake("bake_normal", "NORMAL", ATLAS, 8)
    rough = bake("bake_rough", "EMIT", ORM_TEX, 4)[..., 0]
    metal = bake("bake_metal", "EMIT", ORM_TEX, 4)[..., 0]
    ao = bake("bake_ao", "AO", ORM_TEX, 64)[..., 0]
    log("albedo mean %.3f; rough mean %.2f; metal mean %.2f; ao mean %.2f" % (
        float(col[..., :3].mean()), float(rough.mean()), float(metal.mean()), float(ao.mean())))

    def image(name, data, size, srgb):
        im = bpy.data.images.new(name, size, size, alpha=False)
        im.colorspace_settings.name = "sRGB" if srgb else "Non-Color"
        im.pixels.foreach_set(np.ascontiguousarray(data, dtype=np.float32).ravel())
        im.file_format = "JPEG"
        return im

    lin = np.clip(col[..., :3], 0.0, 1.0)
    srgb = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)
    alb = np.ones((ATLAS, ATLAS, 4), dtype=np.float32)
    alb[..., :3] = srgb
    orm = np.ones((ORM_TEX, ORM_TEX, 4), dtype=np.float32)
    orm[..., 0] = np.clip(ao, 0, 1)
    orm[..., 1] = np.clip(rough, 0.04, 1)
    orm[..., 2] = np.clip(metal, 0, 1)
    aimg = image("scoutpost_kit_albedo", alb, ATLAS, True)
    nimg = image("scoutpost_kit_normal", nrm, ATLAS, False)
    oimg = image("scoutpost_kit_orm", orm, ORM_TEX, False)

    kit = bpy.data.materials.new("scoutpost_kit")
    kit.use_nodes = True
    nt = kit.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    an = nt.nodes.new("ShaderNodeTexImage")
    an.image = aimg
    nt.links.new(an.outputs["Color"], bsdf.inputs["Base Color"])
    nn = nt.nodes.new("ShaderNodeTexImage")
    nn.image = nimg
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    on = nt.nodes.new("ShaderNodeTexImage")
    on.image = oimg
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(on.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    gltf_out = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
    gltf_out.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    gn = nt.nodes.new("ShaderNodeGroup")
    gn.node_tree = gltf_out
    nt.links.new(sep.outputs["Red"], gn.inputs["Occlusion"])

    for o in targets:
        me = o.data
        for lay in list(me.uv_layers):
            if lay.name != "atlas":
                me.uv_layers.remove(lay)
        if "axis" in me.attributes:
            me.attributes.remove(me.attributes["axis"])
        me.materials.clear()
        me.materials.append(kit)
        o.location = (0, 0, 0)
    for h in helpers:
        bpy.data.objects.remove(h)

    if PREVIEW:
        out = sys.argv[-1]
        for im in (aimg, nimg, oimg):
            im.filepath_raw = os.path.join(out, im.name + ".png")
            im.file_format = "PNG"
            im.save()
            im.file_format = "JPEG"

    for o in bpy.context.scene.objects:
        o.select_set(o in targets)
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        use_selection=True,
        export_animations=False,
        export_image_format="JPEG",
        export_jpeg_quality=92,
        export_yup=True,
        export_apply=True,
    )
    log("wrote", OUT, os.path.getsize(OUT))


main()
