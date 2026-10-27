extends SceneTree

## Photographs the new sky and takes a rough read on what it costs.
##
##   godot --path . --windowed --script res://tools/preview_sky.gd
##
## NOT headless -- CLAUDE.md is explicit that the dummy renderer reports
## fiction, and a sky shader never touches a single real pixel under it; this
## needs a real swapchain to draw anything at all, let alone time it.
##
## This is a preview and an estimate, not the project benchmark: it isolates
## the sky's own cost by swapping `background_mode` on the same camera, same
## resolution, nothing else in the scene to confound it. The lead's real
## benchmark (`tools/benchmark.gd`) measures it inside the actual level.

const SkySetup = preload("res://scripts/sky_setup.gd")
## `builder` in `maze.gd` -- loaded the same way, since `module_level.gd` has
## no `class_name` and exposes its statics straight off the script resource.
const ModuleLevel = preload("res://scripts/module_level.gd")

const WIDTH := 1600
const HEIGHT := 900
const OUT_DIR := "user://team/sky"
const COST_FRAMES := 180


func _initialize() -> void:
	# The first benchmark written for this project read a flat 20.00 ms at
	# every station because vsync was still on -- that was the refresh rate,
	# not the game.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	var root := Node3D.new()
	get_root().add_child(root)

	var env := Environment.new()
	# The REAL pipeline, in the REAL order `maze.gd` uses it
	# (`_apply_module_environment`): `configure_environment()` first --
	# ACES white 4.0, the brightness/contrast/saturation adjustment, AND
	# `background_energy_multiplier = SKY_ENERGY (0.42)` -- then
	# `SkySetup.apply()`, which only ever touches `env.sky` and
	# `env.background_mode` so it cannot undo any of that. A preview that
	# skips the 0.42 multiplier is not previewing what the game draws: this
	# project's CLAUDE.md already logs three rounds of a preview lying about
	# brightness for exactly this kind of omission.
	ModuleLevel.configure_environment(env, 1.0, true)
	SkySetup.apply(env)
	# (Since note 112 `configure_environment()` sets `fog_sky_affect` itself
	# (FOG_SKY); this preview still forces 0, to judge the sky shader alone.)
	# Before that it never touched `fog_sky_affect` -- it was set
	# once, in `scenes/main.tscn`'s authored Environment resource (0.0, fog
	# does not touch the sky), and this preview builds a FRESH `Environment`
	# that does not carry that. Its engine default is 1.0, which means dense
	# fog at "infinite" sky depth saturates to the fog colour completely --
	# the first run of this corrected preview showed a pure black sky purely
	# from that, nothing to do with the shader. Match the scene file.
	env.fog_sky_affect = 0.0

	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.current = true
	root.add_child(cam)

	var shots: Array[String] = []

	# Looking up ~60 degrees, toward the cloud deck.
	cam.look_at_from_position(Vector3.ZERO, _dir(60.0, 0.0), Vector3.UP)
	await _settle()
	shots.append(await _shoot("up_60"))

	# ~30 degrees: roughly what the game's own shots show over a courtyard
	# wall (look_boss_0.png etc. are close to level, sky visible in a strip
	# above the silhouettes) -- this is the pitch that actually matters.
	cam.look_at_from_position(Vector3.ZERO, _dir(30.0, 10.0), Vector3.UP)
	await _settle()
	shots.append(await _shoot("up_30"))

	# Level with the horizon, where the gradient and the coverage fade matter.
	cam.look_at_from_position(Vector3.ZERO, _dir(0.0, 40.0), Vector3.UP)
	await _settle()
	shots.append(await _shoot("horizon"))

	# Two shots of the same framing, ~3 seconds apart, to prove the clouds
	# actually drift rather than sitting still under a moving camera.
	cam.look_at_from_position(Vector3.ZERO, _dir(25.0, 15.0), Vector3.UP)
	await _settle()
	shots.append(await _shoot("drift_a"))
	await _wait_seconds(3.0)
	shots.append(await _shoot("drift_b"))

	for s in shots:
		print("SHOT %s" % ProjectSettings.globalize_path(s))

	await _cost_estimate(env)
	quit(0)


## Unit view direction, `pitch_deg` above the horizontal, `yaw_deg` around it.
func _dir(pitch_deg: float, yaw_deg: float) -> Vector3:
	var pitch := deg_to_rad(pitch_deg)
	var yaw := deg_to_rad(yaw_deg)
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


func _settle() -> void:
	# MultiMesh/material upload settle time is not the concern here -- this is
	# a pure shader background -- but the first frame or two after a camera
	# move can still be black while the sky's cubemap capture catches up.
	for i in 8:
		await process_frame


func _wait_seconds(t: float) -> void:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(t * 1000.0):
		await process_frame


func _shoot(name: String) -> String:
	await RenderingServer.frame_post_draw
	var img := get_root().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	img.save_png(path)
	return path


## Rough estimate only, per CLAUDE.md's rule to never claim a speed-up (or a
## cost) without numbers -- these are the numbers, but the lead's own
## benchmark is the one that counts.
func _cost_estimate(env: Environment) -> void:
	var mode := DisplayServer.window_get_vsync_mode()
	if mode != DisplayServer.VSYNC_DISABLED:
		push_error("vsync is still %d -- these timings are the refresh rate, not the shader" % mode)

	env.background_mode = Environment.BG_SKY
	for i in 20:
		await process_frame
	var t_sky := await _time_frames(COST_FRAMES)

	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.01, 0.01)
	for i in 20:
		await process_frame
	var t_flat := await _time_frames(COST_FRAMES)

	env.background_mode = Environment.BG_SKY

	print("")
	print("COST estimate at %dx%d, %d frames each" % [WIDTH, HEIGHT, COST_FRAMES])
	print("  sky-filled view   avg %.3f ms" % t_sky)
	print("  flat colour view  avg %.3f ms" % t_flat)
	print("  estimated sky cost %+.3f ms" % (t_sky - t_flat))


func _time_frames(n: int) -> float:
	var samples: Array[float] = []
	for i in n:
		var t0 := Time.get_ticks_usec()
		await process_frame
		samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var total := 0.0
	for s in samples:
		total += s
	return total / float(samples.size())
