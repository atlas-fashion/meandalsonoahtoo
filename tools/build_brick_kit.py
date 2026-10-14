"""Turn the eight raw Tripo pieces (models/source/brick_kit_raw) into the brick kit.

The raw pieces were generated from the user's reference photos
(models/source/brick_kit_refs): a plain wall, a wall with an iron cage window, a
pillar, a pillar with a torch, a pointed arch, an arched door, a barrel vault
section and a flagstone floor slab. Every piece comes back normalised to a unit
box with rubble scattered round its foot.

This script crops the loose rubble, scales each piece to its size in the maze,
cuts the vault variants, and writes ONE file, models/brick/brick_kit.glb, with a
named object per piece. One file, because the variants share their source's
textures: exported separately, the wall and its two variants would put the same
maps in video memory three times.

## The cell (see scripts/brick_level.gd, which places these)

A cell is 6 m. The corridor is 3.8 m between wall faces (WALL_FACE 1.9) and the
vault springs from the walls at 3.0 m to an inner crown at 5.1 m -- the old
modules' height, which the boss hall's floor (7.0, slab from 5.6) and every
"above the roof" rule still assume. A pointed arch stands across every opening
between two cells, centred on the boundary, 1.2 m deep, and hides both the
joint between the two cells' vaults and the ends of their walls.

## Frames

Everything is written in Blender's frame with +Y = the maze's north, which the
glTF exporter turns into Godot -Z. Pieces that are placed per side (walls,
arches, the door, torch pillars) face Blender -Y = Godot +Z: their FRONT is at
y = 0 and their body runs back into +Y. Vault pieces are already in the cell's
own frame (centred, springing at 3.0 m) and in the canonical orientation of
module_maze.gd's kinds (straight N-S, corner N+E, tee N+E+S, dead N).

    blender -b --factory-startup -P tools/build_brick_kit.py
"""
import os
import sys
import math
import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(HERE, "models", "source", "brick_kit_raw")
OUT_DIR = os.path.join(HERE, "models", "brick")
OUT = os.path.join(OUT_DIR, "brick_kit.glb")

WALL_FACE = 1.9
SPRING = 3.0
CROWN = 5.1
WALL_LEN = 5.2
## Out to the cell boundary (and a hair past it), so a vault runs into the arch
## and meets its neighbour's inside it. Ending at 2.5 m -- just inside the
## arch's face -- left a crescent beside every arch through which the space
## above the vault, and the void, showed.
VAULT_HALF = 3.03
ARCH_WIDTH_SCALE = 8.6
ARCH_HEIGHT = 5.6
ARCH_DEPTH = 1.2
PILLAR_SHAFT = 0.9
PILLAR_HEIGHT = 3.2
FLOOR_TILE = 3.0
DOOR_SCALE = 5.0
RIB_HALF = 0.2
RIB_DROP = 0.07
TEXTURE_PX = 2048
ORM_PX = 1024

## Triangle budgets. The game is per-pixel bound (CLAUDE.md section 2), but a
## straight now draws two walls, a vault, half of two arches and four floor
## slabs where it used to draw one 15k module, so the pieces are thinned.
BUDGET = {
    "wall": 7000, "wall_top": 4000, "wall_niche": 7000, "wall_cage": 8000,
    "pillar": 1500, "pillar_torch": 2200, "arch": 6000, "door": 8000,
    "floor": 1500, "vault": 7000,
    "door_frame": 99999, "door_leaf": 99999, "cage_door": 99999, "torch_mount": 99999,
    "cart_body": 6000, "cart_wheels": 2400, "cart_lid": 1500,
    "wood_support": 3000, "prison_dome": 16000, "jail_gate_l": 99999, "jail_gate_r": 99999, "wood_planks": 2500, "wood_crate": 2500,
}


def log(*a):
    print("[brick]", *a)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_piece(name):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(RAW, name + ".glb"))
    fresh = [o for o in set(bpy.context.scene.objects) - before if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in fresh:
        o.select_set(True)
    bpy.context.view_layer.objects.active = fresh[0]
    if len(fresh) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.name = name
    weld(ob)
    return ob


def weld(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(ob.data)
    bm.free()


def strip_rubble(ob, keep_fraction=0.04):
    """Delete the loose shells (scattered rubble) much smaller than the body."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    seen = set()
    shells = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        shell = []
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            shell.append(cur)
            for e in cur.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        shells.append(shell)
    biggest = max(len(s) for s in shells)
    doomed = [f for s in shells if len(s) < biggest * keep_fraction for f in s]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    log("  %s: %d shells, dropped %d rubble faces" % (ob.name, len(shells), len(doomed)))


def points(ob):
    return np.array([tuple(ob.matrix_world @ v.co) for v in ob.data.vertices])


def apply(ob, matrix):
    ob.data.transform(matrix)
    ob.data.update()


def band(p, axis, lo, hi):
    return p[(p[:, axis] >= lo) & (p[:, axis] <= hi)]


def rot_z(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Z")


def scale(x, y, z):
    return Matrix.Diagonal((x, y, z, 1.0))


def move(x, y, z):
    return Matrix.Translation((x, y, z))


def clip(ob, co, no):
    """Keep the half-space on the side `no` points to."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(co), plane_no=Vector(no),
                           clear_inner=True, dist=1e-5)
    bm.to_mesh(ob.data)
    bm.free()


def duplicate(ob, name):
    c = ob.copy()
    c.data = ob.data.copy()
    c.name = name
    bpy.context.scene.collection.objects.link(c)
    return c


def join(obs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    return ob


def decimate(ob, budget):
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris > budget:
        mod = ob.modifiers.new("dec", "DECIMATE")
        mod.ratio = budget / float(tris)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier="dec")
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def shade(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    try:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    except Exception:
        pass
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(50.0))
    except Exception:
        bpy.ops.object.shade_smooth()


def stats(ob):
    p = points(ob)
    lo, hi = p.min(axis=0), p.max(axis=0)
    tris = sum(len(q.vertices) - 2 for q in ob.data.polygons)
    log("  %-14s %6d tris  x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f"
        % (ob.name, tris, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))


# ---------------------------------------------------------------------------
# Pieces placed per side: raw front is +X, length along Y. A -90 degree turn
# puts the front on -Y (Godot +Z) and the length along X.
# ---------------------------------------------------------------------------

def build_wall(name="wall"):
    ob = import_piece(name)
    strip_rubble(ob)
    apply(ob, rot_z(-90.0))
    p = points(ob)
    z0, z1 = p[:, 2].min(), p[:, 2].max()
    mid = band(p, 2, z0 + 0.3 * (z1 - z0), z0 + 0.7 * (z1 - z0))
    # Front face = the outer brick faces (5th percentile of y, the front is -y).
    front = float(np.percentile(mid[:, 1], 5 if name == "wall" else 2))
    if name == "wall_cage":
        # The cage stands out of the wall; measure the WALL away from it.
        away = mid[np.abs(mid[:, 0]) > 0.25]
        front = float(np.percentile(away[:, 1], 5))
    s = WALL_LEN / (p[:, 0].max() - p[:, 0].min())
    cx = (p[:, 0].max() + p[:, 0].min()) * 0.5
    apply(ob, scale(s, s, s) @ move(-cx, -front, -z0))
    # Rubble at the foot ran 0.43 m out into the corridor, under hiding carts
    # and torch pillars. A little is kept: it hides the wall/floor joint.
    clip(ob, (0, -0.18 if name == "wall" else -0.7, 0), (0, 1, 0))
    clip(ob, (0, 1.2, 0), (0, -1, 0))
    return ob


def build_pillar(name):
    ob = import_piece(name)
    strip_rubble(ob)
    apply(ob, rot_z(-90.0))
    p = points(ob)
    z0, z1 = p[:, 2].min(), p[:, 2].max()
    mid = band(p, 2, z0 + 0.3 * (z1 - z0), z0 + 0.8 * (z1 - z0))
    x0, x1 = np.percentile(mid[:, 0], 2), np.percentile(mid[:, 0], 98)
    y0, y1 = np.percentile(mid[:, 1], 2), np.percentile(mid[:, 1], 98)
    if name == "pillar_torch":
        # The torch is on the -y face; keep it out of the shaft measure.
        core = mid[(mid[:, 1] > y0 + 0.02)]
        x0, x1 = np.percentile(core[:, 0], 2), np.percentile(core[:, 0], 98)
    sxy = PILLAR_SHAFT / max(x1 - x0, y1 - y0)
    sz = PILLAR_HEIGHT / (z1 - z0)
    apply(ob, scale(sxy, sxy, sz) @ move(-(x0 + x1) * 0.5, -(y0 + y1) * 0.5, -z0))
    # The mud and rubble round the foot spread over a metre; it would poke
    # through walls and arch legs. Cropped to the shaft, the torch side kept.
    lim = PILLAR_SHAFT * 0.5 + 0.08
    clip(ob, (-lim, 0, 0), (1, 0, 0))
    clip(ob, (lim, 0, 0), (-1, 0, 0))
    clip(ob, (0, lim, 0), (0, -1, 0))
    clip(ob, (0, -(0.8 if name == "pillar_torch" else lim), 0), (0, 1, 0))
    if name == "pillar_torch":
        q = points(ob)
        half = PILLAR_SHAFT * 0.5
        out = q[(q[:, 1] < -half - 0.06) & (q[:, 2] > 1.2)]
        if len(out):
            top = out[out[:, 2] > np.percentile(out[:, 2], 85)]
            c = top.mean(axis=0)
            log("  TORCH HEAD (blender) %.3f %.3f %.3f  -> godot (%.3f, %.3f, %.3f)"
                % (c[0], c[1], c[2], c[0], c[2], -c[1]))
    return ob


def build_arch(name="arch"):
    ob = import_piece(name)
    strip_rubble(ob)
    apply(ob, rot_z(-90.0))
    p = points(ob)
    z0, z1 = p[:, 2].min(), p[:, 2].max()
    mid = band(p, 2, z0 + 0.1 * (z1 - z0), z0 + 0.5 * (z1 - z0))
    x0, x1 = np.percentile(mid[:, 0], 1), np.percentile(mid[:, 0], 99)
    y0, y1 = np.percentile(mid[:, 1], 2), np.percentile(mid[:, 1], 98)
    if name == "arch":
        sx = ARCH_WIDTH_SCALE
        sz = ARCH_HEIGHT / (z1 - z0)
        sy = ARCH_DEPTH / (y1 - y0)
        # Centred on the boundary: depth runs both ways from y = 0.
        apply(ob, scale(sx, sy, sz) @ move(-(x0 + x1) * 0.5, -(y0 + y1) * 0.5, -z0))
        # Rubble at the legs' feet flared to +-4 m, past the cell boundary.
        clip(ob, (-3.3, 0, 0), (1, 0, 0))
        clip(ob, (3.3, 0, 0), (-1, 0, 0))
        clip(ob, (0, -0.75, 0), (0, 1, 0))
        clip(ob, (0, 0.75, 0), (0, -1, 0))
    else:
        s = DOOR_SCALE
        # Front (stone face) on y = 0, body behind.
        front = np.percentile(mid[:, 1], 3)
        apply(ob, scale(s, s, s) @ move(-(x0 + x1) * 0.5, -front, -z0))
    q = points(ob)
    # Report the opening as the arch's free span at a few heights.
    for h in (1.0, 2.0, 3.0, 3.5, 4.0, 4.5):
        b = band(q, 2, h - 0.06, h + 0.06)
        b = band(b, 1, -0.3, 0.3) if name == "arch" else band(b, 1, -0.2, 0.6)
        xs = np.sort(b[:, 0])
        gaps = np.diff(xs)
        if len(gaps):
            i = int(np.argmax(gaps))
            log("    %s at %.1f m: outer %.2f..%.2f  opening %.2f..%.2f"
                % (name, h, xs[0], xs[-1], xs[i], xs[i + 1]))
    return ob


## The wet floor's gloss (2026-10-14). Tripo painted the water -- puddles in the
## hollows, wet cracks, darkened stone -- into the COLOUR of floor_wet.glb, a
## retexture of the floor task from a wet edit of the user's own reference
## photo (tools/tripo_image.ps1, tools/tripo_texture.ps1). Its roughness map is
## matte everywhere (0.90-1.0; three retextures never went below 0.79), so the
## shine is derived from where Tripo put the water: the wet colour against the
## dry original (floor.glb), same UVs. Darker than dry = wet. Blurred, because
## the two textures' fine grain does not line up.
WET_BASE_ROUGH = 0.62      # the whole floor: kinda wet
WET_POOL_ROUGH = 0.1       # where Tripo painted standing water
WET_BLUR = 40              # texels at 4096


def _pixels(im):
    a = np.empty(im.size[0] * im.size[1] * im.channels, np.float32)
    im.pixels.foreach_get(a)
    return a.reshape(im.size[1], im.size[0], im.channels)


def _box(a, r):
    """Separable box blur, twice (close to a gaussian)."""
    for _ in range(2):
        for axis in (0, 1):
            c = np.cumsum(np.pad(a, [(r + 1, r) if i == axis else (0, 0) for i in range(2)],
                                 mode="edge"), axis=axis)
            hi = np.take(c, range(2 * r + 1, c.shape[axis]), axis=axis)
            lo = np.take(c, range(0, c.shape[axis] - 2 * r - 1), axis=axis)
            a = (hi - lo) / (2 * r + 1)
    return a


def wet_gloss(ob, dry_source):
    lum = np.array([0.2126, 0.7152, 0.0722], np.float32)
    colour = rough_node = None
    for mat in ob.data.materials:
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image is not None:
                if "color" in node.image.name.lower():
                    colour = node.image
                elif "rough" in node.image.name.lower():
                    rough_node = node
    before = set(bpy.data.images)
    keep = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(RAW, dry_source + ".glb"))
    for o in list(set(bpy.context.scene.objects) - keep):
        bpy.data.objects.remove(o)
    dry = [im for im in set(bpy.data.images) - before if "color" in im.name.lower()]
    if colour is None or rough_node is None or not dry or tuple(dry[0].size) != tuple(colour.size):
        log("    wet_gloss: missing maps, floor left as Tripo made it")
        return
    lw = _pixels(colour)[:, :, :3] @ lum
    ld = _pixels(dry[0])[:, :, :3] @ lum
    darker = np.clip((1.0 - lw / np.maximum(ld, 0.02)) / 0.5, 0.0, 1.0)
    wet = _box(darker, WET_BLUR)
    wet = np.clip((wet - 0.18) / (0.5 - 0.18), 0.0, 1.0)
    wet = wet * wet * (3.0 - 2.0 * wet)
    rough = WET_BASE_ROUGH + (WET_POOL_ROUGH - WET_BASE_ROUGH) * wet
    h, w = rough.shape
    px = np.zeros((h, w, 4), np.float32)
    px[:, :, 0] = 1.0
    px[:, :, 1] = rough
    px[:, :, 3] = 1.0
    out = bpy.data.images.new("floor_wet_roughness", w, h, alpha=False)
    out.colorspace_settings.name = "Non-Color"
    out.pixels.foreach_set(px.ravel())
    out.pack()
    rough_node.image = out
    log("    wet gloss: roughness %.2f..%.2f, %.0f%% of texels below 0.3"
        % (rough.min(), rough.max(), 100.0 * (rough < 0.3).mean()))


def build_floor():
    wet = os.path.exists(os.path.join(RAW, "floor_wet.glb"))
    ob = import_piece("floor_wet" if wet else "floor")
    if wet:
        ob.name = "floor"
        wet_gloss(ob, "floor")
    strip_rubble(ob, 0.1)
    p = points(ob)
    mid = band(p, 2, -0.02, 0.02)
    x0, x1 = np.percentile(mid[:, 0], 2), np.percentile(mid[:, 0], 98)
    y0, y1 = np.percentile(mid[:, 1], 2), np.percentile(mid[:, 1], 98)
    top = p[p[:, 2] > np.percentile(p[:, 2], 60)]
    t = float(np.median(top[:, 2]))
    sx, sy, sz = FLOOR_TILE / (x1 - x0), FLOOR_TILE / (y1 - y0), 3.4
    apply(ob, scale(sx, sy, sz) @ move(-(x0 + x1) * 0.5, -(y0 + y1) * 0.5, -t))
    return ob


def build_vault():
    """The barrel, running north-south, springing at SPRING, crown at CROWN."""
    ob = import_piece("vault")
    strip_rubble(ob)
    # Raw: axis along X, span along Y. A quarter turn runs it along Y.
    apply(ob, rot_z(90.0))
    p = points(ob)
    z0 = p[:, 2].min()
    mid = band(p, 1, -0.2, 0.2)
    base = band(mid, 2, z0 + 0.03, z0 + 0.06)
    half = float(np.abs(base[:, 0]).min())
    crown = band(mid, 0, -0.03, 0.03)
    inner_crown = float(crown[:, 2].min())
    rise = inner_crown - z0
    s_span = WALL_FACE / half
    s_up = (CROWN - SPRING) / rise
    s_len = (2.0 * VAULT_HALF) / (p[:, 1].max() - p[:, 1].min())
    cy = (p[:, 1].max() + p[:, 1].min()) * 0.5
    apply(ob, move(0, 0, SPRING) @ scale(s_span, s_len, s_up) @ move(0, -cy, -z0))
    log("  vault scale span %.2f  len %.2f  up %.2f" % (s_span, s_len, s_up))
    # Thinned BEFORE the variants are cut, never after: decimating a clipped
    # piece moves the vertices on its cut edge, and the groin lines opened
    # into hairline gaps to the sky.
    decimate(ob, BUDGET["vault"])
    return ob


## The two diagonals of the cell divide its plan into four triangles, one
## against each side. A groin vault is the N-S barrel over the N and S
## triangles and the E-W barrel over the E and W ones; they meet exactly on
## the diagonals because the two barrels share a profile.
TRI = {
    "N": [((0, 0, 0), (-1, 1, 0)), ((0, 0, 0), (1, 1, 0))],
    "S": [((0, 0, 0), (1, -1, 0)), ((0, 0, 0), (-1, -1, 0))],
    "E": [((0, 0, 0), (1, 1, 0)), ((0, 0, 0), (1, -1, 0))],
    "W": [((0, 0, 0), (-1, -1, 0)), ((0, 0, 0), (-1, 1, 0))],
}


## Half-planes: keep the side the normal points to.
HALF = {
    "NW": [((0, 0, 0), (-1, 1, 0))],    # y >= x: the N and W triangles
    "SE": [((0, 0, 0), (1, -1, 0))],    # y <= x: the S and E triangles
}


def vault_variant(barrel, rib, name, plan, ribs):
    """plan: [(region, "NS" | "EW")], a region from TRI or HALF; ribs: the
    groin diagonals (+45 = y = x, -45 = y = -x) to cover with a rib."""
    parts = []
    for region, axis in plan:
        c = duplicate(barrel, "%s_%s" % (name, region))
        if axis == "EW":
            apply(c, rot_z(90.0))
        for co, no in TRI.get(region, HALF.get(region)):
            clip(c, co, Vector(no).normalized())
        parts.append(c)
    for angle in ribs:
        r = duplicate(rib, "%s_rib%d" % (name, angle))
        apply(r, rot_z(angle))
        parts.append(r)
    return join(parts, name)


def make_rib(barrel):
    """A rib for a groin line: a narrow profile slice of the barrel itself,
    stretched by sqrt(2) across so it follows the groin's curve (on a diagonal
    the barrels are at height h(|x|) with |x| = |y|), and dropped a little so
    it stands proud of both vault surfaces and covers the seam between them.
    The cut barrels meet exactly in theory and leave hairline cracks to the
    void in practice: a magenta-void probe saw them in 40 of 40 corners."""
    r = duplicate(barrel, "vault_rib")
    clip(r, (0, -RIB_HALF, 0), (0, 1, 0))
    clip(r, (0, RIB_HALF, 0), (0, -1, 0))
    apply(r, move(0, 0, -RIB_DROP) @ scale(math.sqrt(2.0), 1.0, 1.0))
    return r


def cut_hole(ob, x0, x1, y0, y1, z_min):
    """Delete every face whose centre lies inside a vertical shaft."""
    for co, no in (((x0, 0, 0), (1, 0, 0)), ((x1, 0, 0), (1, 0, 0)),
                   ((0, y0, 0), (0, 1, 0)), ((0, y1, 0), (0, 1, 0))):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(co), plane_no=Vector(no), dist=1e-5)
        bm.to_mesh(ob.data)
        bm.free()
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    doomed = []
    for f in bm.faces:
        c = f.calc_center_median()
        if x0 < c.x < x1 and y0 < c.y < y1 and c.z > z_min:
            doomed.append(f)
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    log("  %s: hole %.2f x %.2f, %d faces" % (ob.name, x1 - x0, y1 - y0, len(doomed)))


def shrink_textures():
    for img in bpy.data.images:
        if img.size[0] <= 0:
            continue
        px = ORM_PX if "ORM" in img.name else TEXTURE_PX
        if max(img.size) > px:
            img.scale(px, px)


def main():
    reset()
    os.makedirs(OUT_DIR, exist_ok=True)
    built = []

    wall = build_wall("wall")
    built.append(wall)
    top = duplicate(wall, "wall_top")
    # A band of the wall for the lunette above a dead end's end wall: clear of
    # the rubble at its foot and the broken top course.
    clip(top, (0, 0, 0.6), (0, 0, 1))
    clip(top, (0, 0, 3.0), (0, 0, -1))
    apply(top, move(0, 0, -0.6))
    built.append(top)
    niche = duplicate(wall, "wall_niche")
    # Same opening the old module_straight_niche had (NICHE_W x NICHE_H at the sill).
    cut_hole_wall(niche)
    built.append(niche)
    cage = build_wall("wall_cage")
    # Thinned before the gate is cut out, so the two still meet.
    decimate(cage, BUDGET["wall_cage"])
    built.append(cage)
    built.append(split_cage(cage))
    built.append(build_pillar("pillar"))
    torch_pillar = build_pillar("pillar_torch")
    # Cut from the full-detail pillar: thinned first, the small torch kept 38 faces.
    mount = cut_torch_mount(torch_pillar)
    decimate(mount, 1800)
    built.append(mount)
    built.append(torch_pillar)
    built.append(build_arch("arch"))
    body, wheels = build_cart()
    built += [body, wheels, build_lid()]
    built.append(build_wood("wood_support", 2.4, True))
    built.append(build_wood("wood_planks", 1.6, False))
    built.append(build_wood("wood_crate", 0.95, False))
    built.append(build_dome_inside())
    built.extend(build_jail_gate())
    door = build_arch("door")
    # Thinned before it is split, so the leaf's edge and the frame's still meet.
    decimate(door, BUDGET["door"])
    built.append(door)
    built.extend(split_door(door))
    built.append(build_floor())

    barrel = build_vault()
    straight = duplicate(barrel, "vault_straight")
    built.append(straight)
    sky = duplicate(barrel, "vault_sky")
    cut_hole(sky, -0.5, 0.5, -1.2, 1.2, SPRING + 1.0)
    built.append(sky)
    rib = make_rib(barrel)
    built.append(vault_variant(barrel, rib, "vault_cross",
                               [("N", "NS"), ("S", "NS"), ("E", "EW"), ("W", "EW")], [45, -45]))
    built.append(vault_variant(barrel, rib, "vault_tee",
                               [("NW", "NS"), ("S", "NS"), ("E", "EW")], [45, -45]))
    built.append(vault_variant(barrel, rib, "vault_corner",
                               [("NW", "NS"), ("SE", "EW")], [45]))
    bpy.data.objects.remove(rib)
    bpy.data.objects.remove(barrel)

    for ob in built:
        key = ob.name
        if not key.startswith("vault"):
            decimate(ob, BUDGET.get(key, 6000))
        shade(ob)
        ob.data.name = ob.name
        stats(ob)

    shrink_textures()
    bpy.ops.object.select_all(action="DESELECT")
    for ob in built:
        ob.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, use_selection=True, export_format="GLB",
                              export_image_format="JPEG", export_jpeg_quality=90)
    log("wrote", OUT, "%.1f MB" % (os.path.getsize(OUT) / 1e6))


## The door piece's wooden leaf, ray-mapped from the front at DOOR_SCALE: 1.9 m
## wide up to its springing at 3.05 m, a pointed head to ~4.2 m, its boards
## 0.42-0.87 m behind the stone's face (Blender +y), iron straps a little proud.
DOOR_LEAF_HEAD = [(3.05, 0.97), (3.25, 0.89), (3.45, 0.74), (3.65, 0.59),
                  (3.85, 0.46), (4.05, 0.24), (4.25, 0.0)]
DOOR_LEAF_FRONT = 0.15
DOOR_LEAF_BACK = 1.0


def leaf_half_width(z):
    if z <= DOOR_LEAF_HEAD[0][0]:
        return DOOR_LEAF_HEAD[0][1]
    for (z0, w0), (z1, w1) in zip(DOOR_LEAF_HEAD, DOOR_LEAF_HEAD[1:]):
        if z <= z1:
            return w0 + (w1 - w0) * (z - z0) / (z1 - z0)
    return -1.0


def split_door(door):
    """The door piece as two objects: "door_frame" (the stone) and "door_leaf"
    (the boards, straps and ring), so the leaf can be kicked to pieces. A face
    goes to the leaf only if EVERY vertex lies in the leaf's slab and inside its
    outline -- a face's centre is not enough to crop a Tripo mesh (CLAUDE.md,
    the gate door)."""
    frame = duplicate(door, "door_frame")
    leaf = duplicate(door, "door_leaf")
    margin = 0.03

    def in_leaf(v):
        return (DOOR_LEAF_FRONT <= v.co.y <= DOOR_LEAF_BACK and v.co.z >= -0.01
                and abs(v.co.x) <= leaf_half_width(v.co.z) + margin)

    for ob, keep_leaf in ((frame, False), (leaf, True)):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        doomed = [f for f in bm.faces if all(in_leaf(v) for v in f.verts) != keep_leaf]
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        bm.to_mesh(ob.data)
        bm.free()
    log("  door split: frame %d faces, leaf %d faces"
        % (len(frame.data.polygons), len(leaf.data.polygons)))
    return frame, leaf


## --- The cart (Tripo, text prompt) ---------------------------------------------
##
## Exported at the CONVOY's size (rim 0.95 m), in the convoy's frame: handles
## toward +Z (Godot), the tray centred, the ground at y = 0. The hiding cart
## uses the same mesh scaled up (hiding_spot.gd). Raw: length along x with the
## handles at +x, a two-wheeled hand cart, wheels under the middle of the tray
## outside |y| > 0.24, tray x -0.45..0.22, rim at z 0.25, ground at z -0.25.
CART_SCALE = 1.9
CART_TRAY_CENTRE_X = -0.115


def build_cart():
    ob = import_piece("cart")
    strip_rubble(ob, 0.02)
    p = points(ob)
    z0 = p[:, 2].min()
    apply(ob, move(-CART_TRAY_CENTRE_X, 0, -z0))
    wheels = duplicate(ob, "cart_wheels")
    body = ob
    body.name = "cart_body"

    def is_wheel(v):
        return abs(v.co.y) > 0.24

    for o, keep in ((body, False), (wheels, True)):
        bm = bmesh.new()
        bm.from_mesh(o.data)
        doomed = [f for f in bm.faces if all(is_wheel(v) for v in f.verts) != keep]
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        bm.to_mesh(o.data)
        bm.free()
    # The axle: the wheels' centre, in raw units, before the turn and scale.
    q = points(wheels)
    axle = ((q[:, 0].min() + q[:, 0].max()) * 0.5, 0.0, (q[:, 2].min() + q[:, 2].max()) * 0.5)
    radius = (q[:, 2].max() - q[:, 2].min()) * 0.5
    s = CART_SCALE
    # Raw +x (handles) -> Blender -y (Godot +z).
    apply(body, scale(s, s, s) @ rot_z(-90.0))
    apply(wheels, scale(s, s, s) @ rot_z(-90.0) @ move(-axle[0], 0, -axle[2]))
    log("  cart: axle (godot) z %.3f y %.3f  wheel radius %.3f"
        % (axle[0] * s, axle[2] * s, radius * s))
    return body, wheels


## The lid: the top boards and straps of the crate Tripo returned for "a lid",
## sized for the convoy cart (across 0.88, long 1.37, 6 cm), its hinge along
## the -X edge at the origin, reaching out along +X.
CART_LID = (0.88, 1.37, 0.06)


def build_lid():
    ob = import_piece("cart_lid")
    strip_rubble(ob)
    p = points(ob)
    top = p[:, 2].max()
    clip(ob, (0, 0, top - 0.07), (0, 0, 1))
    p = points(ob)
    lo, hi = p.min(axis=0), p.max(axis=0)
    sx = CART_LID[0] / (hi[0] - lo[0])
    sy = CART_LID[1] / (hi[1] - lo[1])
    sz = CART_LID[2] / (hi[2] - lo[2])
    apply(ob, scale(sx, sy, sz) @ move(-lo[0], -(lo[1] + hi[1]) * 0.5, -lo[2]))
    ob.name = "cart_lid"
    return ob


## Broken wood for the corridors (Tripo, text prompts). The support stands
## against a wall: its back on y = 0 (Godot z = 0), reaching out to the
## corridor (Godot +Z); the planks and the crate are centred on the floor.
def build_wood(name, size, against_wall):
    ob = import_piece(name)
    strip_rubble(ob, 0.02)
    p = points(ob)
    if against_wall:
        # Raw: width along y, thin along x. Turn the width onto x.
        apply(ob, rot_z(-90.0))
        p = points(ob)
    s = size / (p[:, 2].max() - p[:, 2].min()) if against_wall else \
        size / max(p[:, 0].max() - p[:, 0].min(), p[:, 1].max() - p[:, 1].min())
    cx = (p[:, 0].max() + p[:, 0].min()) * 0.5
    if against_wall:
        apply(ob, scale(s, s, s) @ move(-cx, -p[:, 1].max(), -p[:, 2].min()))
    else:
        cy = (p[:, 1].max() + p[:, 1].min()) * 0.5
        apply(ob, scale(s, s, s) @ move(-cx, -cy, -p[:, 2].min()))
    return ob


## The iron cage on the cage wall, measured by rays from the front at WALL_LEN:
## x -0.03..1.13 along the wall, 1.55..2.63 m up, standing 0.13..0.68 m out of
## the face (Blender -y). Its front -- frame and bars, the gate -- is the part in
## front of y = -0.46; it is cut free so bone_cage.gd can swing it.
CAGE_BOX = (-0.06, 1.17, 1.5, 2.7)
CAGE_FRONT = -0.46


def split_cage(cage):
    door = duplicate(cage, "cage_door")
    x0, x1, z0, z1 = CAGE_BOX

    def in_door(v):
        return v.co.y <= CAGE_FRONT and x0 <= v.co.x <= x1 and z0 <= v.co.z <= z1

    for o, keep in ((cage, False), (door, True)):
        bm = bmesh.new()
        bm.from_mesh(o.data)
        doomed = [f for f in bm.faces if all(in_door(v) for v in f.verts) != keep]
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        bm.to_mesh(o.data)
        bm.free()
    log("  cage door: %d faces" % len(door.data.polygons))
    return door


## The torch on the torch pillar -- its ring bracket, wooden handle and wrapped
## head -- as a piece of its own, "torch_mount": every torch.tscn in the game
## wears it instead of its old procedural bracket and handle (torch.gd). Origin:
## the head's top, pushed back onto the pillar's face (the wall), so +Y up and
## the torch reaching out along -Blender y (Godot +Z).
def cut_torch_mount(pillar):
    mount = duplicate(pillar, "torch_mount")
    # Ray-mapped: on the torch's side the pillar's face is 0.31 m in front of its
    # centre (not the shaft's nominal 0.45); the torch leans out from it, its
    # handle's foot ~1.4 m up, its head at ~2.78 m, 0.56 m out.
    wall = -0.31
    face = -0.33
    bm = bmesh.new()
    bm.from_mesh(mount.data)
    doomed = [f for f in bm.faces if not all(v.co.y < face and v.co.z > 1.3 for v in f.verts)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(mount.data)
    bm.free()
    p = points(mount)
    top = p[p[:, 2] > np.percentile(p[:, 2], 90)]
    head = top.mean(axis=0)
    apply(mount, move(-head[0], -wall, -p[:, 2].max()))
    q = points(mount)
    log("  torch mount: %d faces, %.2f m long, reaches %.2f m off the wall"
        % (len(mount.data.polygons), q[:, 2].max() - q[:, 2].min(), -q[:, 1].min()))
    return mount


## The prison's dome (Tripo, text prompt): a ribbed hemisphere of dark stone
## with an open oculus. It came back lying on its side -- probed by radius along
## each axis: its open base faces +x (radius ~0.5) and the oculus collar -x
## (radius ~0.1-0.2). Stood up (oculus at the top), its base at z = 0 and
## scaled to radius 1, so the room scales it to whatever it covers.
def build_dome_first_pass():
    ob = import_piece("prison_dome")
    strip_rubble(ob, 0.02)
    apply(ob, Matrix.Rotation(math.radians(90.0), 4, "Y"))
    p = points(ob)
    base = band(p, 2, p[:, 2].min(), p[:, 2].min() + 0.03 * (p[:, 2].max() - p[:, 2].min()))
    r = float(np.percentile(np.sqrt(base[:, 0] ** 2 + base[:, 1] ** 2), 90))
    apply(ob, scale(1.0 / r, 1.0 / r, 1.0 / r) @ move(0, 0, -p[:, 2].min()))
    q = points(ob)
    top = q[q[:, 2] > q[:, 2].max() - 0.05]
    log("  dome: base radius %.3f raw -> 1.0; height %.2f; oculus radius ~%.2f"
        % (r, q[:, 2].max(), float(np.sqrt(top[:, 0] ** 2 + top[:, 1] ** 2).min())))
    return ob


## The jail gate: Tripo's "prison cell" came back as a small roofed hut, but its
## front holds a rusty spiked iron gate in a pointed arch. Ray-mapped from the
## front (+x raw): the bars stand 0.10-0.245 in from... out along x, across
## |y| <= 0.18, from the foot (z -0.475) to the pointed top (~0.27). Cut out,
## faced like every other piece (front to Godot +Z), stretched to fill the
## brick arch's opening (3.36 x 4.55 m) and split down the middle into two
## leaves, each with its origin on its hinge (the opening's edge).
JAIL_GATE = (3.36, 4.55)


def build_jail_gate_first_pass():
    ob = import_piece("prison_cell")
    strip_rubble(ob, 0.01)

    def in_gate(v):
        return 0.10 <= v.co.x <= 0.245 and abs(v.co.y) <= 0.18 and v.co.z <= 0.27

    bm = bmesh.new()
    bm.from_mesh(ob.data)
    doomed = [f for f in bm.faces if not all(in_gate(v) for v in f.verts)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    apply(ob, rot_z(-90.0))
    p = points(ob)
    lo, hi = p.min(axis=0), p.max(axis=0)
    sx = JAIL_GATE[0] / (hi[0] - lo[0])
    sz = JAIL_GATE[1] / (hi[2] - lo[2])
    # Depth held to 0.22 m: at the height's stretch the bars were 0.86 m deep.
    sd = 0.22 / (hi[1] - lo[1])
    apply(ob, scale(sx, sd, sz) @ move(-(lo[0] + hi[0]) * 0.5, -(lo[1] + hi[1]) * 0.5, -lo[2]))
    left = duplicate(ob, "jail_gate_l")
    right = ob
    right.name = "jail_gate_r"
    clip(left, (0, 0, 0), (-1, 0, 0))
    clip(right, (0, 0, 0), (1, 0, 0))
    half = JAIL_GATE[0] * 0.5
    apply(left, move(half, 0, 0))
    apply(right, move(-half, 0, 0))
    log("  jail gate: %d + %d faces, raw %.3f x %.3f" % (len(left.data.polygons),
        len(right.data.polygons), hi[0] - lo[0], hi[2] - lo[2]))
    return left, right


## The prison's dome, second Tripo pass (2026-10-11): "prison_dome2" came back a
## symmetrical closed ribbed dome -- but an EXTERIOR, on a solid base disc. The
## disc is cut away and every face turned to face inward, so its brick lines a
## ceiling seen from below. Normalised: base flange radius 1, base at z = 0,
## centred on its own axis. Exported as "prison_dome" (replacing the lopsided
## first pass, whose collar sat half a radius off its base).
def build_dome_inside():
    ob = import_piece("prison_dome2")
    strip_rubble(ob, 0.02)
    p = points(ob)
    z0, z1 = p[:, 2].min(), p[:, 2].max()
    cx = (p[:, 0].min() + p[:, 0].max()) * 0.5
    cy = (p[:, 1].min() + p[:, 1].max()) * 0.5
    r = max(p[:, 0].max() - p[:, 0].min(), p[:, 1].max() - p[:, 1].min()) * 0.5
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    low = z0 + 0.04 * (z1 - z0)
    floor = [f for f in bm.faces if f.normal.z < -0.6 and all(v.co.z < low for v in f.verts)]
    bmesh.ops.delete(bm, geom=floor, context="FACES")
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:], flip_multires=False)
    bm.to_mesh(ob.data)
    bm.free()
    apply(ob, scale(1.0 / r, 1.0 / r, 1.0 / r) @ move(-cx, -cy, -z0))
    ob.name = "prison_dome"
    q = points(ob)
    log("  dome (inside): %d base faces cut, radius %.3f raw -> 1, height %.2f"
        % (len(floor), r, q[:, 2].max()))
    return ob


## The cells' gate, second Tripo pass: "jail_gate" is a flat pointed-arch gate
## filled with bars (raw: thin along x, width along y, height along z, a little
## plinth at its foot). Faced like the other pieces (front to Godot +Z), fitted
## inside the brick arch's opening (probed: 3.32 m between the legs to 3.3 m,
## apex 4.8 m) with a hair of clearance, 0.2 m deep, and split down the middle
## into two leaves with their origins on their hinges. Replaces the first
## pass's gate cut from Tripo's cell hut, whose bars were sparse and broken.
JAIL_GATE = (3.28, 4.74, 0.2)


def build_jail_gate():
    ob = import_piece("jail_gate")
    strip_rubble(ob, 0.01)
    apply(ob, rot_z(-90.0))
    p = points(ob)
    lo, hi = p.min(axis=0), p.max(axis=0)
    sx = JAIL_GATE[0] / (hi[0] - lo[0])
    sz = JAIL_GATE[1] / (hi[2] - lo[2])
    sd = JAIL_GATE[2] / (hi[1] - lo[1])
    apply(ob, scale(sx, sd, sz) @ move(-(lo[0] + hi[0]) * 0.5, -(lo[1] + hi[1]) * 0.5, -lo[2]))
    left = duplicate(ob, "jail_gate_l")
    right = ob
    right.name = "jail_gate_r"
    clip(left, (0, 0, 0), (-1, 0, 0))
    clip(right, (0, 0, 0), (1, 0, 0))
    half = JAIL_GATE[0] * 0.5
    apply(left, move(half, 0, 0))
    apply(right, move(-half, 0, 0))
    log("  jail gate: %d + %d faces" % (len(left.data.polygons), len(right.data.polygons)))
    return left, right


NICHE_W = 0.9
NICHE_H = 0.8
NICHE_SILL = 1.05


def cut_hole_wall(ob):
    """A rectangular hole straight through the wall, centred along it."""
    hx = NICHE_W * 0.5
    for co, no in (((-hx, 0, 0), (1, 0, 0)), ((hx, 0, 0), (1, 0, 0)),
                   ((0, 0, NICHE_SILL), (0, 0, 1)), ((0, 0, NICHE_SILL + NICHE_H), (0, 0, 1))):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=Vector(co), plane_no=Vector(no), dist=1e-5)
        bm.to_mesh(ob.data)
        bm.free()
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    doomed = [f for f in bm.faces
              if -hx < f.calc_center_median().x < hx
              and NICHE_SILL < f.calc_center_median().z < NICHE_SILL + NICHE_H]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()
    log("  wall_niche: %d faces cut" % len(doomed))


main()
