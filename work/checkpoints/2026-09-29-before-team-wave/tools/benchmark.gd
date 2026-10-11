extends Node

## Repeatable in-game benchmark. Dormant unless the game is launched with
## `--bench`, so it costs a single string check during normal play.
##
##   godot --path <project> --windowed --resolution 1280x720 -- --bench
##
## It parks the player at a few representative spots, spins a full circle at
## each (which is what actually stresses culling and draw-call submission), and
## reports frame-time percentiles plus renderer counters. GPU counters only mean
## anything with a real window, so this must NOT be run with --headless.

const STATION_SECONDS := 6.0
const WARMUP_SECONDS := 2.0

var _active := false
var _player: Node3D
var _rows: Array[Dictionary] = []
var _label: Label
var _preset := -1
var _tag := "current"
var _ablate := false
var _shot := false
var _swing := false
var _no_trail := false
var _size := Vector2i(1280, 720)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--bench":
			_active = true
		elif arg == "--ablate":
			_ablate = true
			_tag = "ablation"
		elif arg == "--shot":
			_shot = true
			_tag = "screenshot"
		elif arg == "--swing":
			# Swinging continuously, so the sweep trail is actually on screen.
			# Without this the benchmark never attacks and never measures it.
			_swing = true
			_tag += "+swing"
		elif arg == "--no-trail":
			_no_trail = true
			_tag += "+notrail"
		elif arg.begins_with("--preset="):
			_tag = arg.substr(9)
			var idx := Graphics.PRESET_NAMES.find(_tag.capitalize())
			if idx >= 0:
				_preset = idx
		elif arg.begins_with("--size="):
			var wh := arg.substr(7).split("x")
			if wh.size() == 2:
				_size = Vector2i(int(wh[0]), int(wh[1]))
	if not _active:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Fixed window, so two runs are actually comparable. --resolution on the
	# command line loses to the project's fullscreen window mode.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_size)
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	layer.add_child(_label)
	_run.call_deferred()


func _environment() -> Environment:
	for w in get_tree().get_nodes_in_group("world_environment"):
		if w is WorldEnvironment:
			return (w as WorldEnvironment).environment
	return null


func _torch_shadows() -> String:
	for p in get_tree().get_nodes_in_group("player"):
		var l := p.find_child("Light", true, false) as OmniLight3D
		if l != null:
			return str(l.shadow_enabled)
	return "?"


func _floor_under(where: Vector3) -> Vector3:
	var space := get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		where + Vector3(0, 30, 0), where + Vector3(0, -30, 0))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return where
	return (hit["position"] as Vector3) + Vector3(0, 1.2, 0)


func _run() -> void:
	# The level finishes building behind an async navmesh bake.
	await get_tree().create_timer(6.0).timeout
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		push_error("benchmark: no player")
		get_tree().quit(1)
		return
	_player = players[0]
	# Nothing useful is measured by a benchmark run that dies half way through.
	if "health" in _player:
		_player.set("health", 100000.0)

	if _shot:
		await _screenshots()
		get_tree().quit()
		return

	if _preset >= 0:
		Graphics.set_preset(_preset)
	# Held on the settings object rather than forced on the DisplayServer, so
	# that later apply_all() calls during ablation do not put the cap back.
	Graphics.vsync = false
	Graphics.fps_cap = 0
	Graphics.apply_all()
	await get_tree().create_timer(1.0).timeout

	var start := _player.global_position
	var stations := {
		"spawn corridor": _floor_under(start),
		"boss room centre": _floor_under(Vector3(0, 0, 0)),
		"boss room edge": _floor_under(Vector3(14, 0, 14)),
		"outer maze": _floor_under(start + Vector3(0, 0, -26)),
	}
	# The module level puts its rooms where the layout wants them, not at the
	# origin, so its stations are the rooms it actually built -- the fixed
	# coordinates above dropped two stations onto the level's roof. The names
	# are kept so results stay comparable with earlier runs.
	var level = _module_level()
	if level != null:
		var boss: Dictionary = level.boss_room()
		if not boss.is_empty():
			var mid: Vector3 = level.room_world(boss)
			stations["boss room centre"] = _floor_under(mid)
			stations["boss room edge"] = _floor_under(
				mid + Vector3(1, 0, 1) * level.court_half_span(boss) * 0.8)
		var chests: Array = level.chest_rooms()
		if not chests.is_empty():
			# Off to one side: the middle of a chest room is its pedestal.
			stations["chest room"] = _floor_under(level.room_world(chests[0])
				+ Vector3(level.court_half_span(chests[0]) * 0.55, 0, 0))

	print("=== BENCHMARK [%s] ===" % _tag)
	print("window %s   3D render target %s   scale %.2f   msaa %d" % [
		DisplayServer.window_get_size(), get_viewport().size,
		get_viewport().scaling_3d_scale, get_viewport().msaa_3d,
	])
	var env := _environment()
	if env != null:
		print("ssao %s   glow %s   fog %s   torch shadows %s" % [
			env.ssao_enabled, env.glow_enabled, env.fog_enabled, _torch_shadows()])

	if _ablate:
		await _run_ablation(stations["boss room edge"])
	else:
		for name in stations:
			await _station(name, stations[name])
	_report()
	get_tree().quit()


## What each switch is actually worth, measured one at a time at the worst spot
## in the level. Presets are guesses until this says otherwise.
func _run_ablation(where: Vector3) -> void:
	var variants := [
		["High (baseline)", {}],
		["- MSAA off", {"msaa": 0}],
		["- SSAO off", {"ssao": false}],
		["- bloom off", {"glow": false}],
		["- torch shadows off", {"shadows": 0}],
		["- triplanar off", {"texture_detail": 1}],
		["- textures off", {"texture_detail": 0}],
		["- render scale 0.70", {"render_scale": 0.7}],
		["- render scale 0.50", {"render_scale": 0.5}],
		["- view distance 0.70", {"view_distance": 0.7}],
		["- anim LOD aggressive", {"anim_quality": 0}],
	]
	for v in variants:
		_reset_to_high()
		for key in (v[1] as Dictionary):
			Graphics.set(key, v[1][key])
		Graphics.apply_all()
		await get_tree().create_timer(0.6).timeout
		await _station(v[0], where)


func _reset_to_high() -> void:
	for key in Graphics.PRESETS[Graphics.Preset.HIGH]:
		Graphics.set(key, Graphics.PRESETS[Graphics.Preset.HIGH][key])
	Graphics.vsync = false
	Graphics.fps_cap = 0


## Grabs the pause menu as the player actually sees it. Assertions confirm the
## widgets exist; only a picture shows whether they are legible.
## Reports what the scene's Environment is actually doing to the image.
##
## The level preview builds a fresh Environment with linear tonemapping and
## no colour adjustment, while the game's is authored. The same geometry and
## the same lights can therefore come out looking completely different, which
## is exactly what happened: previews that looked right, a game that was
## almost black.
func _report_environment() -> void:
	var env := _environment()
	if env == null:
		print("env: NONE")
		return
	print(("env: tonemap mode %d exposure %.2f white %.2f | adjust %s "
		+ "bright %.2f contrast %.2f sat %.2f | glow %s | ambient %.2f %s")
		% [env.tonemap_mode, env.tonemap_exposure, env.tonemap_white,
			env.adjustment_enabled, env.adjustment_brightness,
			env.adjustment_contrast, env.adjustment_saturation,
			env.glow_enabled, env.ambient_light_energy, env.ambient_light_color])


## The Maze's built module level, if this is the module level.
func _module_level():
	for node in get_tree().root.find_children("*", "Node3D", true, false):
		if "_module_level" in node and node.get("_module_level") != null:
			return node.get("_module_level")
	return null


## Flattens the lighting so holes in the geometry are unmistakable.
func _flat_mode() -> void:
	var env := _environment()
	if env == null:
		return
	env.background_mode = Environment.BG_COLOR
	# Anything open to the outside becomes magenta instead of one more black
	# patch in a dark corridor.
	env.background_color = Color(1.0, 0.0, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_sky_contribution = 0.0
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 2.5
	env.fog_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.adjustment_enabled = false

	# Also lift every visibility range in the level.
	#
	# A chunk's range is measured from its node ORIGIN, which for these is the
	# corner cell of a 24 m block, not its centre. A block can therefore be
	# culled while part of it is still well inside the range and right in
	# front of the player -- which looks exactly like a chunk of wall missing.
	# If the magenta disappears when these are off, that is the cause.
	if "--nocull" in OS.get_cmdline_user_args():
		for node in _all_nodes(get_tree().root):
			if node is GeometryInstance3D:
				(node as GeometryInstance3D).visibility_range_end = 0.0


func _all_nodes(from: Node) -> Array[Node]:
	var out: Array[Node] = [from]
	for child in from.get_children():
		out.append_array(_all_nodes(child))
	return out


func _screenshots() -> void:
	_label.visible = false
	_report_environment()
	var flat: bool = "--flat" in OS.get_cmdline_user_args()
	if flat:
		_flat_mode()

	# Several places, not one. A single frame at the spawn said the level was
	# fine while the player walking it found holes everywhere.
	var where := {"spawn": _player.global_position}
	# Into the rooms the level really built, rather than at fixed coordinates:
	# the old stations were chosen for a boss room at the origin, and after the
	# rebuild two of them landed on top of the level's roof.
	var level = _module_level()
	if level != null:
		var boss: Dictionary = level.boss_room()
		if not boss.is_empty():
			var mid: Vector3 = level.room_world(boss)
			var back: float = level.court_half_span(boss) * 0.75
			where["boss"] = _floor_under(mid + Vector3(-back, 0, -back))
			where["bossarcade"] = _floor_under(mid + Vector3(
				-(level.court_half_span(boss) + level.cell_size * 0.5), 0, 0))
		var chests: Array = level.chest_rooms()
		if not chests.is_empty():
			var c: Vector3 = level.room_world(chests[0])
			var cb: float = level.court_half_span(chests[0]) * 0.7
			where["chest"] = _floor_under(c + Vector3(-cb, 0, -cb))
	for name in where:
		_player.global_position = where[name]
		for turn in 2:
			# In a courtyard, face across it toward the far corner; elsewhere,
			# two quarter turns.
			_player.rotation.y = float(turn) * PI * 0.5 + (
				-PI * 0.75 if name == "boss" or name == "chest" else 0.0)
			for i in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var p := "user://look_%s_%d.png" % [name, turn]
			img.save_png(p)
			print("shot: %s" % ProjectSettings.globalize_path(p))
	if flat:
		get_tree().quit()
		return

	var menu = get_parent().get_node_or_null("PauseMenu")
	if menu == null:
		push_error("no PauseMenu")
		return
	# Mid-swing, so the sweep trail is on screen for the shot.
	if _player.has_method("_start_attack"):
		_player._start_attack()
		await get_tree().physics_frame
		_player._hitbox_on()
		for i in 7:
			await get_tree().physics_frame
	for i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.save_png("user://gameplay.png")
	print("shot: %s" % ProjectSettings.globalize_path("user://gameplay.png"))

	menu._open()
	for page in [[false, "pause_root"], [true, "pause_settings"]]:
		menu._show_page(page[0])
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "user://%s.png" % page[1]
		img.save_png(path)
		print("shot: %s" % ProjectSettings.globalize_path(path))


func _station(name: String, where: Vector3) -> void:
	_label.text = "warmup: %s" % name
	var t := 0.0
	while t < WARMUP_SECONDS:
		_park(where, t / WARMUP_SECONDS)
		t += await _tick()

	var frames: Array[float] = []
	var draw := 0.0
	var objs := 0.0
	var prims := 0.0
	var proc := 0.0
	var phys := 0.0
	var n := 0
	t = 0.0
	while t < STATION_SECONDS:
		_label.text = "measuring: %s  (%.1fs)" % [name, STATION_SECONDS - t]
		_park(where, t / STATION_SECONDS)
		var dt := await _tick()
		t += dt
		frames.append(dt * 1000.0)
		draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		n += 1

	frames.sort()
	_rows.append({
		"station": name,
		"frames": n,
		"avg_ms": _mean(frames),
		"p50_ms": _pct(frames, 0.50),
		"p95_ms": _pct(frames, 0.95),
		"p99_ms": _pct(frames, 0.99),
		"low1_fps": 1000.0 / maxf(_pct(frames, 0.99), 0.001),
		"avg_fps": 1000.0 / maxf(_mean(frames), 0.001),
		"draw_calls": draw / maxi(n, 1),
		"objects": objs / maxi(n, 1),
		"primitives": prims / maxi(n, 1),
		"cpu_process_ms": proc / maxi(n, 1) * 1000.0,
		"cpu_physics_ms": phys / maxi(n, 1) * 1000.0,
	})


func _park(where: Vector3, phase: float) -> void:
	_player.global_position = where
	_player.rotation.y = phase * TAU
	if "velocity" in _player:
		_player.set("velocity", Vector3.ZERO)
	if _no_trail and "sweep_trail_enabled" in _player:
		_player.set("sweep_trail_enabled", false)
	if _swing and _player.has_method("_start_attack") and not _player._attacking:
		_player._start_attack()


func _tick() -> float:
	await get_tree().process_frame
	return get_process_delta_time()


func _mean(a: Array[float]) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


func _pct(sorted: Array[float], p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(sorted.size() * p), 0, sorted.size() - 1)]


func _report() -> void:
	print("")
	print("%-18s %7s %7s %7s %8s %8s %9s %10s %8s %8s" % [
		"station", "avg fps", "1% low", "avg ms", "p95 ms", "p99 ms",
		"draws", "prims", "cpu ms", "phys ms"])
	for r in _rows:
		print("%-18s %7.1f %7.1f %7.2f %8.2f %8.2f %9.0f %10.0f %8.2f %8.2f" % [
			r["station"], r["avg_fps"], r["low1_fps"], r["avg_ms"], r["p95_ms"],
			r["p99_ms"], r["draw_calls"], r["primitives"],
			r["cpu_process_ms"], r["cpu_physics_ms"]])
	var worst := 0.0
	var total := 0.0
	for r in _rows:
		worst = maxf(worst, r["p99_ms"])
		total += r["avg_fps"]
	print("")
	print("OVERALL avg fps %.1f   worst p99 %.2f ms   video mem %.1f MB" % [
		total / maxi(_rows.size(), 1), worst,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	var f := FileAccess.open("user://benchmark.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_rows, "  "))
		f.close()
		print("wrote %s" % ProjectSettings.globalize_path("user://benchmark.json"))
	print("=== END BENCHMARK ===")
