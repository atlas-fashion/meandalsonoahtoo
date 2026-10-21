"""Builds the surgery's Higgsfield kit, models/surgery/*.glb (note 95).

    blender -b --factory-startup -P tools/build_surgery_kit.py -- models/surgery
    blender -b --factory-startup -P tools/build_surgery_kit.py -- --preview <dir>
    godot --headless --import --path .

Sources: models/source/surgery_hf/ (under models/source/.gdignore). Each
raw_*.glb is a Tripo H3.1 image-to-3D model made on Higgsfield from a
gpt_image_2_5 picture (ref_*.png beside it) drawn after the user's reference
image of the surgery -- the riveted iron table on its gear base, the ceiling
ring, the claw and one arm segment of the long arm, the apothecary shelf, the
worktable with its skull and book, the candle chandelier, the specimen jar, the
iron-bound chest. chart.png is the anatomy chart on the wall (a texture, not a
model).

Tripo returns every model in a 1 m box, centred, with three 2048-4096 maps.
For each piece this script:
- joins and applies its transforms, turns it so its front faces Blender -Y
  (Godot +Z after the exporter's Y-up swap) and scales it to SIZE metres along
  the axis named,
- puts the origin where the game places it from (the floor under it, its top
  for hanging things, the middle for the arm pieces),
- decimates it to its triangle budget (welded first: Tripo's surface arrives
  unwelded, and collapse tears an unwelded mesh into shards -- prep_kit_asset.py),
- sets the metallic factor (Tripo ships 1.0 on everything, which in this
  unlit-by-sky dungeon renders iron black and wood as chrome) and shrinks the
  maps to TEX px.
"""

import bpy
import math
import os
import sys
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "models", "source", "surgery_hf")

# name: (axis to size "x"/"y"/"z" after turning, metres, origin, yaw degrees
#        about Z applied first, triangle budget, texture px, metallic)
# origin: "bottom" (floor centre), "top" (top centre), "centre",
#         "top_axis" (the arm pieces: top centre, they hang from it).
PIECES = {
    "table": ("y", 3.0, "bottom", 0.0, 0, 2048, 0.45),
    "ring": ("x", 3.4, "top", 0.0, 12000, 1024, 0.45),
    "claw": ("z", 1.7, "top", 0.0, 12000, 1024, 0.5),
    "segment": ("z", 1.0, "centre", 0.0, 6000, 512, 0.45),
    "shelf": ("z", 3.0, "bottom", -90.0, 9000, 1024, 0.0),
    "worktable": ("y", 2.0, "bottom", 0.0, 8000, 1024, 0.1),
    "chandelier": ("z", 1.7, "top", 0.0, 6000, 512, 0.3),
    "jar": ("z", 2.1, "bottom", 0.0, 7000, 1024, 0.3),
    "chest": ("y", 1.15, "bottom", 0.0, 5000, 512, 0.1),
}


def log(*a):
    print("[surgery_kit]", *a)


def load(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, "raw_%s.glb" % name))
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    target = meshes[0]
    with bpy.context.temp_override(active_object=target, object=target, selected_objects=meshes,
                                   selected_editable_objects=meshes):
        if len(meshes) > 1:
            bpy.ops.object.join()
    for o in list(bpy.data.objects):
        if o != target:
            bpy.data.objects.remove(o)
    target.name = name
    target.data.name = name
    with bpy.context.temp_override(active_object=target, object=target, selected_objects=[target],
                                   selected_editable_objects=[target]):
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return target


def bounds(o):
    vs = [v.co for v in o.data.vertices]
    lo = Vector([min(v[i] for v in vs) for i in range(3)])
    hi = Vector([max(v[i] for v in vs) for i in range(3)])
    return lo, hi


def build(name, out_dir):
    axis, size, origin, yaw, budget, tex, metal = PIECES[name]
    o = load(name)
    if yaw != 0.0:
        o.data.transform(Matrix.Rotation(math.radians(yaw), 4, 'Z'))
    span = max(o.dimensions)
    with bpy.context.temp_override(active_object=o, object=o, selected_objects=[o], selected_editable_objects=[o]):
        bpy.ops.object.mode_set(mode='EDIT')
        bpy.ops.mesh.select_all(action='SELECT')
        bpy.ops.mesh.remove_doubles(threshold=span * 0.0004)
        bpy.ops.object.mode_set(mode='OBJECT')
    o.data.calc_loop_triangles()
    tris = len(o.data.loop_triangles)
    if budget > 0 and tris > budget:
        mod = o.modifiers.new(name="Budget", type='DECIMATE')
        mod.decimate_type = 'COLLAPSE'
        mod.use_collapse_triangulate = True
        mod.ratio = budget / float(tris)
        with bpy.context.temp_override(active_object=o, object=o, selected_objects=[o], selected_editable_objects=[o]):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        with bpy.context.temp_override(active_object=o, object=o, selected_objects=[o], selected_editable_objects=[o]):
            bpy.ops.object.mode_set(mode='EDIT')
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.mesh.dissolve_degenerate()
            bpy.ops.mesh.select_all(action='SELECT')
            bpy.ops.mesh.delete_loose(use_verts=True, use_edges=True, use_faces=True)
            bpy.ops.object.mode_set(mode='OBJECT')
    o.data.calc_loop_triangles()
    lo, hi = bounds(o)
    k = size / (hi - lo)["xyz".index(axis)]
    o.data.transform(Matrix.Scale(k, 4))
    lo, hi = bounds(o)
    mid = (lo + hi) * 0.5
    if origin == "bottom":
        shift = Vector((-mid.x, -mid.y, -lo.z))
    elif origin == "top":
        shift = Vector((-mid.x, -mid.y, -hi.z))
    else:
        shift = -mid
    o.data.transform(Matrix.Translation(shift))
    lo, hi = bounds(o)
    for m in o.data.materials:
        if m is None or not m.use_nodes:
            continue
        for n in m.node_tree.nodes:
            if n.type == 'BSDF_PRINCIPLED':
                n.inputs["Metallic"].default_value = metal
    for img in bpy.data.images:
        if img.size[0] > tex:
            img.scale(tex, tex)
    size_m = hi - lo
    log("%s: %d -> %d tris, %.2f x %.2f x %.2f m (Blender x y z), maps %d px, metallic %.2f"
        % (name, tris, len(o.data.loop_triangles), size_m.x, size_m.y, size_m.z, tex, metal))
    if out_dir is not None:
        path = os.path.join(out_dir, "%s.glb" % name)
        bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True,
                                  export_image_format='JPEG', export_jpeg_quality=90, export_apply=True)
    return o


def preview(name, out_dir):
    o = build(name, None)
    lo, hi = bounds(o)
    centre = (lo + hi) * 0.5
    r = (hi - lo).length
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.color_type = 'TEXTURE'
    scene.display.shading.light = 'STUDIO'
    scene.render.resolution_x = 512
    scene.render.resolution_y = 512
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    # From the front (-Y) and a little to the right and above.
    eye = centre + Vector((0.45 * r, -1.3 * r, 0.35 * r))
    cam.location = eye
    cam.rotation_euler = (centre - eye).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = os.path.join(out_dir, "%s.png" % name)
    bpy.ops.render.render(write_still=True)


argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
only = [a for a in argv[1:] if not a.startswith("--")] if argv and argv[0] == "--preview" else argv[1:]
if argv and argv[0] == "--preview":
    out = argv[1]
    names = argv[2:] or list(PIECES)
    os.makedirs(out, exist_ok=True)
    for n in names:
        if os.path.exists(os.path.join(SRC, "raw_%s.glb" % n)):
            preview(n, out)
else:
    out = os.path.join(ROOT, argv[0]) if argv and not os.path.isabs(argv[0]) else (argv[0] if argv else os.path.join(ROOT, "models", "surgery"))
    names = argv[1:] or list(PIECES)
    os.makedirs(out, exist_ok=True)
    for n in names:
        if os.path.exists(os.path.join(SRC, "raw_%s.glb" % n)):
            build(n, out)
        else:
            log("missing raw_%s.glb -- skipped" % n)
