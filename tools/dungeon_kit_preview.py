"""Pictures of the dungeon kit, straight out of Blender (called by
build_dungeon_kit.py with --preview=<dir>): the pieces assembled into two
corridor bays and a crossing exactly as scripts/brick_level.gd lays them, and
each piece on its own under a raking light. For judging the modelling and the
joins before the game is run; the game's own light and grade differ (note 6.08).
"""
import math
import os

import bpy
from mathutils import Matrix, Vector

G2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def g2b(p):
    return (G2B @ Vector((p[0], p[1], p[2], 1.0))).to_3d()


def place(ob, pos, yaw=0.0, coll=None):
    c = ob.copy()
    mg = Matrix.Translation(Vector(pos)) @ Matrix.Rotation(yaw, 4, "Y")
    c.matrix_world = G2B @ mg @ G2B.inverted()
    (coll or bpy.context.scene.collection).objects.link(c)
    return c


def facing(into):
    return math.atan2(into[0], into[2])


def light(pos, watts, colour=(1.0, 0.6, 0.34), radius=0.08):
    d = bpy.data.lights.new("torch", "POINT")
    d.energy = watts
    d.color = colour
    d.shadow_soft_size = radius
    o = bpy.data.objects.new("torch", d)
    o.location = g2b(pos)
    bpy.context.scene.collection.objects.link(o)
    return o


def camera(pos, look, fov=75.0):
    cam = bpy.data.cameras.new("cam")
    cam.sensor_fit = "HORIZONTAL"
    cam.angle = math.radians(fov)
    cam.clip_start = 0.05
    o = bpy.data.objects.new("cam", cam)
    o.location = g2b(pos)
    d = g2b(look) - g2b(pos)
    o.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(o)
    bpy.context.scene.camera = o
    return o


def shoot(path):
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[preview] wrote", path, flush=True)


def clear(keep):
    for o in list(bpy.context.scene.objects):
        if o not in keep:
            bpy.data.objects.remove(o)


def render(built, out_dir, kit):
    os.makedirs(out_dir, exist_ok=True)
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
        print("[preview] CPU:", ex)
    scn.cycles.samples = 64
    scn.cycles.use_denoising = True
    scn.render.resolution_x = 1600
    scn.render.resolution_y = 900
    scn.view_settings.view_transform = "Filmic" if "Filmic" in [v.name for v in scn.view_settings.bl_rna.properties["view_transform"].enum_items] else "AgX"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.5, 0.55, 0.7, 1.0)
    bg.inputs[1].default_value = 0.012
    scn.world = world

    by = {o.name: o for o in built}
    for o in built:
        o.hide_render = True
    keep = set(built)

    def inst(name, pos, yaw=0.0):
        if name in by:
            c = place(by[name], pos, yaw)
            c.hide_render = False
            return c

    def cell(c, kind, opens, walls="wall", vault="vault_straight", floors=("floor", "floor_b", "floor_c", "floor")):
        cx, cz = c
        k = 0
        for fx in (-1.5, 1.5):
            for fz in (-1.5, 1.5):
                inst(floors[k % len(floors)], (cx + fx, 0, cz + fz), math.pi / 2 * k)
                k += 1
        inst(vault, (cx, 0, cz))
        for i, d in enumerate(((0, 0, -1), (1, 0, 0), (0, 0, 1), (-1, 0, 0))):
            into = (-d[0], 0, -d[2])
            if "NESW"[i] in opens:
                inst("arch", (cx + d[0] * 3, 0, cz + d[2] * 3), facing(into))
            else:
                w = walls[i % len(walls)] if isinstance(walls, (list, tuple)) else walls
                inst(w, (cx + d[0] * 1.9, 0, cz + d[2] * 1.9), facing(into))
        if kind == "junction":
            for px in (-2, 2):
                for pz in (-2, 2):
                    inst("pillar", (cx + px, 0, cz + pz))

    if all(n in by for n in ("wall", "arch", "vault_straight", "floor")):
        cell((0, 0), "straight", "NS", walls=["wall", "wall_b", "wall", "wall_broken"])
        cell((0, -6), "straight", "NS", walls=["wall", "wall_c", "wall", "wall_cage"], vault="vault_b")
        cell((0, -12), "junction", "NESW", vault="vault_cross")
        cell((0, 6), "straight", "NS")
        inst("pillar_torch", (1.9 + 0.15, 0, -1.2), facing((-1, 0, 0)))
        inst("wood_support", (-1.9, 0, -6.4), facing((1, 0, 0)))
        inst("rubble_a", (1.9, 0, 1.2), facing((-1, 0, 0)))
        inst("wood_planks", (-1.0, 0, -2.6), 0.6)
        inst("column_broken", (-1.1, 0, -10.2), 0.8)
        inst("tie_beam", (0, 0, -4.6))
        inst("portcullis_up", (0, 0, -3.0))
        inst("rubble_c", (1.9, 0, -7.4), facing((-1, 0, 0)))
        t1 = light((1.25, 2.85, -1.2), 420)
        t2 = light((-1.3, 2.7, -8.0), 380)
        t3 = light((0.0, 3.4, -12.0), 500)
        camera((0.25, 1.65, 2.6), (0.0, 1.9, -6.0), 86)
        shoot(os.path.join(out_dir, "bay_corridor.png"))
        camera((-0.9, 1.65, -7.2), (1.9, 1.9, -5.4), 80)
        shoot(os.path.join(out_dir, "bay_cage_wall.png"))
        camera((0.6, 1.65, -8.6), (-0.6, 3.6, -12.5), 88)
        shoot(os.path.join(out_dir, "bay_crossing.png"))
        camera((0.5, 1.65, -4.0), (1.9, 2.2, -1.0), 80)
        shoot(os.path.join(out_dir, "bay_torch.png"))
        camera((0.0, 1.65, -3.2), (0.0, 0.0, -0.4), 80)
        shoot(os.path.join(out_dir, "bay_floor.png"))
        # The same with a flat grey light and a magenta void: holes show.
        bg.inputs[0].default_value = (1.0, 0.0, 0.6, 1.0)
        bg.inputs[1].default_value = 1.0
        for t in (t1, t2, t3):
            t.data.energy = 60
        scn.cycles.samples = 16
        for i, (p, l) in enumerate((((0.25, 1.65, 2.6), (0.0, 2.4, -6.0)), ((0.6, 1.65, -8.6), (-0.6, 3.9, -12.5)),
                                    ((0.0, 1.2, -5.0), (0.0, 5.0, -6.5)), ((1.0, 1.65, -11.0), (-2.0, 2.6, -14.5)))):
            camera(p, l, 95)
            shoot(os.path.join(out_dir, "void_%d.png" % i))
        scn.cycles.samples = 64
        bg.inputs[0].default_value = (0.5, 0.55, 0.7, 1.0)
        bg.inputs[1].default_value = 0.012
    clear(keep)

    # Each piece alone: in front of it, a torch off to one side.
    singles = {
        "wall": ((0.8, 1.6, 4.2), (0, 1.7, 0), (2.6, 2.6, 1.6)),
        "wall_broken": ((-0.8, 1.6, 4.0), (0, 1.8, 0), (2.4, 2.6, 1.4)),
        "wall_cage": ((1.6, 1.8, 2.4), (0.55, 2.0, 0.2), (2.2, 2.9, 1.6)),
        "pillar_torch": ((1.2, 1.9, 2.6), (0, 1.9, 0), (1.6, 2.2, 2.0)),
        "arch": ((1.2, 1.7, 6.0), (0, 2.6, 0), (2.8, 3.0, 2.2)),
        "door_arch": ((1.0, 1.7, 4.4), (0, 2.4, -0.5), (2.2, 3.0, 1.6)),
        "vault_cross": ((0.8, 1.2, 1.6), (0, 4.6, 0), (0.0, 3.2, 0.0)),
        "vault_sky": ((0.4, 1.2, 2.4), (0, 5.0, 0), (0.0, 3.4, 1.0)),
        "floor_notch": ((0.4, 2.2, 1.6), (0.8, 0, 0), (1.4, 1.4, 1.2)),
        "floor_c": ((0.0, 2.6, 1.9), (0, 0, 0), (1.6, 1.3, 1.0)),
        "wood_support": ((1.4, 1.5, 3.4), (0, 1.2, 0.2), (2.0, 2.4, 1.8)),
        "wood_planks": ((1.2, 1.2, 1.6), (0, 0.15, 0), (1.4, 1.4, 1.0)),
        "rubble_a": ((1.2, 1.1, 1.9), (0, 0.15, 0.3), (1.4, 1.3, 1.2)),
        "column_broken": ((1.6, 1.3, 2.2), (0.3, 0.7, 0.1), (1.6, 2.0, 1.4)),
        "pier_face": ((1.5, 1.7, 5.5), (0, 3.2, 0), (2.2, 3.4, 2.2)),
        "tie_beam": ((0.6, 1.7, 3.2), (0, 3.9, 0), (1.2, 3.4, 1.6)),
        "portcullis_up": ((0.5, 1.7, 2.6), (0, 3.9, 0), (1.2, 3.2, 1.4)),
        "rubble_c": ((1.3, 1.2, 2.1), (0, 0.15, 0.3), (1.4, 1.3, 1.2)),
        "arch_b": ((1.2, 1.7, 6.0), (0, 2.6, 0), (2.8, 3.0, 2.2)),
    }
    for name, (cam, look, lamp) in singles.items():
        if name not in by:
            continue
        inst(name, (0, 0, 0))
        if name.startswith(("wood", "rubble", "column", "pillar")):
            inst("floor", (0, 0, 1.5)) if "floor" in by else None
        light(lamp, 300)
        camera(cam, look, 70)
        shoot(os.path.join(out_dir, "piece_%s.png" % name))
        clear(keep)
