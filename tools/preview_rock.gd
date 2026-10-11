extends SceneTree

## Photographs the rock meshes at the scales the lead actually uses, using
## EACH MESH'S OWN UVs -- no triplanar override -- since that is what this
## correction round is meant to prove out: a native-proportion column plus a
## unit pillar, both without the triplanar/tint patch `maze.gd` applied to
## paper over the old unit-mesh-stretched-9x approach.
##
##   godot --path . --windowed --script res://tools/preview_rock.gd
##
## NOT headless -- CLAUDE.md is explicit the dummy renderer reports fiction.
##
## This is a supplementary check, not the real verification -- the real one
## is `godot --path . --windowed --resolution 1600x900 -- --bench --shot`
## inside the actual level, because this project's own history is three
## rounds of a preview lying about lighting (see CLAUDE.md). Use this for a
## quick, isolated look at UV stretch and colour; trust the game shot for
## everything else.

const OUT_DIR := "user://team/rock"

## (name, mesh path, scale) -- rock_column.glb is baked at its final 1.3 x
## 9.0 size already, so it is used at scale 1; rock_pillar.glb is the unit
## mesh, scaled across the full pedestal/step range the brief gave.
const CASES := [
	["column_native", "res://models/kit/rock_column.glb", Vector3(1.0, 1.0, 1.0)],
	["pillar_tall_step", "res://models/kit/rock_pillar.glb", Vector3(2.2, 2.4, 2.2)],
	["pillar_short_step", "res://models/kit/rock_pillar.glb", Vector3(2.2, 0.3, 2.2)],
]


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var root := Node3D.new()
	get_root().add_child(root)
	_light(root)

	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.current = true
	root.add_child(cam)

	var shots: Array[String] = []
	for entry in CASES:
		var name: String = entry[0]
		var path: String = entry[1]
		var scale: Vector3 = entry[2]

		var mesh := _mesh_of(path)
		if mesh == null:
			push_error("%s missing or not imported" % path)
			continue

		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.scale = scale
		root.add_child(mi)

		# Real mesh height before scale differs (column is baked at 9.0
		# already; pillar is baked at 1.0), so read it off the AABB rather
		# than assuming.
		var real_height: float = mesh.get_aabb().size.y * scale.y
		var real_radius: float = mesh.get_aabb().size.x * 0.5 * scale.x

		# A single framing centred on mid-height cannot show a 9 m column's
		# foot flare or its lowest ledge at all -- the first pass of this
		# preview looked "straight-sided" purely because the base was
		# off-frame, not because the geometry lacked it. Tall meshes get an
		# extra shot centred low.
		var mid_path := await _shoot(cam, real_radius, real_height * 0.5, real_height * 0.5, name)
		shots.append(mid_path)
		if real_height > 3.0:
			var base_h := real_height * 0.18
			var base_path := await _shoot(cam, real_radius * 1.3, base_h, base_h * 1.6, name + "_base")
			shots.append(base_path)

		print("%-18s %-32s scale %s  height %.2f  draws %d  prims %d" % [name, path, scale,
			real_height,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])

		mi.queue_free()
		await process_frame

	for s in shots:
		print("SHOT %s" % ProjectSettings.globalize_path(s))
	quit(0)


func _shoot(cam: Camera3D, radius: float, look_at_h: float, eye_h: float, name: String) -> String:
	cam.look_at_from_position(
		Vector3(radius * 2.8, eye_h, radius * 2.8),
		Vector3(0.0, look_at_h, 0.0), Vector3.UP)
	for i in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var out_path := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(out_path)
	return out_path


func _mesh_of(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path)
	if packed == null:
		return null
	var inst = packed.instantiate()
	var found: Mesh = null
	var stack: Array = [inst]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and found == null:
			found = (n as MeshInstance3D).mesh
		for c in n.get_children():
			stack.append(c)
	inst.queue_free()
	return found


func _light(parent: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.02, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.40, 0.36)
	env.ambient_light_energy = 0.7
	# The game's own grade (maze.gd / module_level.gd configure_environment):
	# ACES at white 4.0 plus a colour adjustment.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 4.0
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.95
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.92
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	# A warm torch-like light, as asked for -- this kit's only shadow caster
	# in the real level is the player's hand torch, so this stands in for it.
	# Kept modest: an earlier pass here used energy 6.0 at close range and it
	# saturated the whole material orange and blew the crack shading to
	# near-black once the game's own ACES + contrast grade was applied on
	# top -- that made a legitimate (if too-strong) crack texture look like
	# holes in the mesh. This is closer to what `torch.gd` actually ships.
	var torch := OmniLight3D.new()
	torch.position = Vector3(1.6, 2.4, 1.6)
	torch.light_color = Color(1.0, 0.78, 0.52)
	torch.light_energy = 1.3
	torch.omni_range = 12.0
	torch.shadow_enabled = true
	parent.add_child(torch)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.55
	fill.rotation_degrees = Vector3(-52.0, 38.0, 0.0)
	parent.add_child(fill)
	# Soft opposite-side fill so the crack/bump shading reads from noise, not
	# from one harsh light direction carving out one whole face.
	var fill2 := DirectionalLight3D.new()
	fill2.light_energy = 0.25
	fill2.rotation_degrees = Vector3(-40.0, -150.0, 0.0)
	parent.add_child(fill2)
