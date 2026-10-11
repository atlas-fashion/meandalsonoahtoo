extends Node

## Autoload `Graphics`. One place that owns every quality knob, so the pause
## menu, the presets and the benchmark all drive the same switches.
##
## Measured on this project, the frame cost is per-PIXEL, not per-triangle: the
## worst station runs 125 draw calls and 65k triangles and still costs 25 ms.
## So the presets spend their budget on resolution, MSAA, SSAO, glow and the
## shadow-casting torch, and treat geometry as nearly free.
##
## Values live as plain properties so the settings UI can bind to them by name
## without a schema. Authored values are stashed on each node with `set_meta`,
## which means a node that gets freed takes its own originals with it.

signal changed

enum Preset { ULTRA, HIGH, MEDIUM, LOW, POTATO, CUSTOM }

const PRESET_NAMES := ["Ultra", "High", "Medium", "Low", "Potato", "Custom"]

## Everything a preset sets. The UI edits these; CUSTOM just means "the player
## moved something by hand".
## Weighted by measurement, not by taste. Against an 11.42 ms baseline at the
## worst spot in the level, halving the render scale returned 6.87 ms -- more
## than bloom, SSAO, shadows, MSAA and textures put together. Cutting the view
## distance to 70% returned *nothing* (-0.11 ms, i.e. noise), because the scene
## is nowhere near geometry bound at 125 draw calls.
##
## So the low presets spend almost everything on resolution and keep the draw
## distance and the textures, which is where the game's look actually lives.
const PRESETS := {
	Preset.ULTRA: {
		"render_scale": 1.0, "msaa": 2, "shadows": 2, "shadow_atlas": 4096,
		"ssao": true, "glow": true, "fog": true, "effects": true,
		"light_detail": 1.15, "view_distance": 1.25, "texture_detail": 2,
		"lod_threshold": 1.0, "anim_quality": 2, "npc_detail": 1.25,
	},
	Preset.HIGH: {
		"render_scale": 1.0, "msaa": 1, "shadows": 2, "shadow_atlas": 2048,
		"ssao": true, "glow": true, "fog": true, "effects": true,
		"light_detail": 1.0, "view_distance": 1.0, "texture_detail": 2,
		"lod_threshold": 1.0, "anim_quality": 2, "npc_detail": 1.0,
	},
	Preset.MEDIUM: {
		"render_scale": 0.8, "msaa": 0, "shadows": 1, "shadow_atlas": 1024,
		"ssao": false, "glow": true, "fog": true, "effects": true,
		"light_detail": 1.0, "view_distance": 1.0, "texture_detail": 2,
		"lod_threshold": 2.0, "anim_quality": 1, "npc_detail": 0.9,
	},
	Preset.LOW: {
		"render_scale": 0.62, "msaa": 0, "shadows": 1, "shadow_atlas": 512,
		"ssao": false, "glow": false, "fog": true, "effects": true,
		"light_detail": 0.9, "view_distance": 0.9, "texture_detail": 2,
		"lod_threshold": 4.0, "anim_quality": 1, "npc_detail": 0.75,
	},
	Preset.POTATO: {
		"render_scale": 0.45, "msaa": 0, "shadows": 0, "shadow_atlas": 256,
		"ssao": false, "glow": false, "fog": false, "effects": false,
		"light_detail": 0.7, "view_distance": 0.75, "texture_detail": 0,
		"lod_threshold": 8.0, "anim_quality": 0, "npc_detail": 0.55,
	},
}

## Resolution the 3D scene renders at, as a fraction of the window. The single
## biggest lever on a fill-rate bound machine.
var render_scale := 0.62
## 0 off, 1 = 2x, 2 = 4x. Maps to Viewport.msaa_3d.
var msaa := 0
## 0 none, 1 hard, 2 soft. Drives the player's torch and the filter quality.
var shadows := 1
var shadow_atlas := 512
var ssao := false
var glow := false
var fog := true
## Death bursts and other non-essential flourishes.
var effects := true
## Scales the reach of the dressing lights (torches, chandeliers).
var light_detail := 0.9
## Scales every authored visibility_range_end in the level.
var view_distance := 0.9
## 0 untextured, 1 textured but no triplanar, 2 full.
var texture_detail := 2
## Pixel threshold for automatic mesh LOD. Higher swaps to cheaper meshes sooner.
var lod_threshold := 4.0
## 0 = only animate what is close, 1 = reduced rate at range, 2 = always full.
var anim_quality := 1
## Scales how far away enemies keep simulating.
var npc_detail := 0.75
var vsync := true
var fps_cap := 0

## Low by default, deliberately. Measured at 3440x1440 the shipped settings were
## 12.8 fps at the worst spot in the level; Low is 56.6 fps there and still
## keeps the textures, the fog, the torch shadows and the full draw distance --
## it buys the frame back almost entirely out of render resolution.
var preset := Preset.LOW

var _loaded := false
var _sweeping := false

# --- animation LOD bands, read every frame by enemy.gd ----------------------
## Inside this, rigs pose every physics frame.
var anim_full_distance := 14.0
## Out to here they pose at `anim_near_rate`; beyond, at `anim_far_rate`.
var anim_half_distance := 30.0
## Poses per second in the middle band.
var anim_near_rate := 24.0
## Poses per second in the far band. Zero freezes them outright.
var anim_far_rate := 10.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	# The level builds asynchronously behind a navmesh bake, so most of what
	# needs touching does not exist yet at startup.
	get_tree().node_added.connect(_on_node_added)
	apply_all.call_deferred()


func _on_node_added(node: Node) -> void:
	if node is MeshInstance3D or node is MultiMeshInstance3D or node is Light3D:
		# Deferred: the spawner usually sets its properties after add_child, and
		# reading them now would cache the wrong "authored" value.
		_apply_to_node.call_deferred(node)


# ---------------------------------------------------------------------------
# presets
# ---------------------------------------------------------------------------
## `persist` false applies the preset for this run only. The benchmark's
## `--preset=` used to go through the saving path, and a harness run that way
## silently left the player's settings on High (see CLAUDE.md).
func set_preset(which: int, persist := true) -> void:
	preset = which
	if PRESETS.has(which):
		for key in PRESETS[which]:
			set(key, PRESETS[which][key])
	apply_all()
	if persist:
		save_settings()


## Called by the UI whenever an individual control moves.
func mark_custom() -> void:
	preset = Preset.CUSTOM
	apply_all()
	save_settings()


func preset_name() -> String:
	return PRESET_NAMES[preset] if preset < PRESET_NAMES.size() else "Custom"


# ---------------------------------------------------------------------------
# apply
# ---------------------------------------------------------------------------
func apply_all() -> void:
	_apply_anim_bands()
	_apply_window()
	_apply_viewport()
	_apply_environment()
	_sweep(get_tree().root)
	changed.emit()


## Posing a 22-bone rig costs the same whether or not the player can make it
## out, and most of the cast is somewhere across the level. These bands are read
## every frame by enemy.gd to decide how often to advance each rig.
func _apply_anim_bands() -> void:
	match anim_quality:
		0:
			# Anything you are not nearly on top of simply holds its pose.
			anim_full_distance = 9.0 * npc_detail
			anim_half_distance = 9.0 * npc_detail
			anim_near_rate = 12.0
			anim_far_rate = 0.0
		1:
			anim_full_distance = 14.0 * npc_detail
			anim_half_distance = 30.0 * npc_detail
			anim_near_rate = 24.0
			anim_far_rate = 10.0
		_:
			anim_full_distance = 1.0e9
			anim_half_distance = 1.0e9
			anim_near_rate = 60.0
			anim_far_rate = 60.0


func _apply_window() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_cap


func _apply_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	# Bilinear rather than FSR: FSR's own pass costs more than it gives back on
	# the hardware this is for.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = render_scale
	vp.msaa_3d = msaa
	vp.mesh_lod_threshold = lod_threshold
	vp.positional_shadow_atlas_size = shadow_atlas
	vp.use_occlusion_culling = true
	# FXAA is far cheaper than MSAA and is what keeps the low presets from
	# looking like broken glass once MSAA is gone.
	vp.screen_space_aa = (Viewport.SCREEN_SPACE_AA_FXAA if msaa == 0
		else Viewport.SCREEN_SPACE_AA_DISABLED)
	vp.use_debanding = glow
	match shadows:
		0:
			RenderingServer.positional_soft_shadow_filter_set_quality(
				RenderingServer.SHADOW_QUALITY_HARD)
		1:
			RenderingServer.positional_soft_shadow_filter_set_quality(
				RenderingServer.SHADOW_QUALITY_HARD)
		_:
			RenderingServer.positional_soft_shadow_filter_set_quality(
				RenderingServer.SHADOW_QUALITY_SOFT_LOW)


func _apply_environment() -> void:
	for node in get_tree().get_nodes_in_group("world_environment"):
		var we := node as WorldEnvironment
		if we == null or we.environment == null:
			continue
		var env := we.environment
		env.ssao_enabled = ssao
		env.glow_enabled = glow
		env.fog_enabled = fog
		# Without fog the sky reads as a flat band on the horizon, so the
		# background goes dark instead of showing a seam.
		env.ssil_enabled = false


# ---------------------------------------------------------------------------
# per-node sweep
# ---------------------------------------------------------------------------
func _sweep(from: Node) -> void:
	_apply_to_node(from)
	for child in from.get_children():
		_sweep(child)


## Untyped on purpose: it is called deferred, and a node freed in between (a
## room taking down a light it no longer needs) cannot be passed to a typed
## parameter -- the call fails before the validity check can run.
func _apply_to_node(node) -> void:
	if not is_instance_valid(node):
		return
	if node is GeometryInstance3D:
		_apply_visibility(node as GeometryInstance3D)
		_apply_textures(node as GeometryInstance3D)
	if node is Light3D:
		_apply_light(node as Light3D)


func _apply_visibility(g: GeometryInstance3D) -> void:
	if not g.has_meta("gfx_vis_end"):
		if g.visibility_range_end <= 0.0:
			return
		g.set_meta("gfx_vis_end", g.visibility_range_end)
		g.set_meta("gfx_vis_margin", g.visibility_range_end_margin)
	var base: float = g.get_meta("gfx_vis_end")
	g.visibility_range_end = base * view_distance
	g.visibility_range_end_margin = float(g.get_meta("gfx_vis_margin")) * view_distance


func _apply_light(l: Light3D) -> void:
	if not l.has_meta("gfx_light"):
		l.set_meta("gfx_light", {
			"shadow": l.shadow_enabled,
			"range": (l as OmniLight3D).omni_range if l is OmniLight3D else 0.0,
			"fade_begin": l.distance_fade_begin,
			"fade_enabled": l.distance_fade_enabled,
			"fade_length": l.distance_fade_length,
		})
	var saved: Dictionary = l.get_meta("gfx_light")
	# Only lights that were authored to cast shadows are candidates; this never
	# switches one on that the artist left off.
	if saved["shadow"]:
		l.shadow_enabled = shadows > 0
	if l is OmniLight3D and saved["range"] > 0.0:
		(l as OmniLight3D).omni_range = float(saved["range"]) * light_detail
	if saved["fade_enabled"]:
		l.distance_fade_enabled = true
		l.distance_fade_begin = float(saved["fade_begin"]) * light_detail
	elif light_detail < 0.75:
		# Cheap presets fade out even the lights that were meant to be always on.
		l.distance_fade_enabled = true
		l.distance_fade_begin = 26.0 * light_detail
		l.distance_fade_length = 8.0
	else:
		# Back to how it was authored. Without this the branch above was one-way:
		# an always-on light (the moon) stayed fading after Ultra -> Potato -> Ultra.
		l.distance_fade_enabled = false
		l.distance_fade_begin = float(saved["fade_begin"])
		l.distance_fade_length = float(saved.get("fade_length", l.distance_fade_length))


func _apply_textures(g: GeometryInstance3D) -> void:
	for m in _materials_of(g):
		var mat := m as StandardMaterial3D
		if mat == null:
			continue
		if not mat.has_meta("gfx_tex"):
			mat.set_meta("gfx_tex", {
				"albedo": mat.albedo_texture,
				"normal": mat.normal_texture,
				"normal_enabled": mat.normal_enabled,
				"roughness": mat.roughness_texture,
				"triplanar": mat.uv1_triplanar,
				"world_triplanar": mat.uv1_world_triplanar,
			})
		var s: Dictionary = mat.get_meta("gfx_tex")
		if texture_detail <= 0:
			mat.albedo_texture = null
			mat.normal_texture = null
			mat.normal_enabled = false
			mat.roughness_texture = null
		else:
			mat.albedo_texture = s["albedo"]
			mat.normal_texture = s["normal"]
			mat.normal_enabled = s["normal_enabled"]
			mat.roughness_texture = s["roughness"]
		# World triplanar samples every texture three times and blends, so it is
		# six fetches per pixel on a wall. It is the first thing to go.
		var flat := texture_detail < 2
		mat.uv1_triplanar = false if flat else s["triplanar"]
		mat.uv1_world_triplanar = false if flat else s["world_triplanar"]


func _materials_of(g: GeometryInstance3D) -> Array:
	var out := []
	if g.material_override != null:
		out.append(g.material_override)
	var mesh: Mesh = null
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		mesh = mi.mesh
		for i in mi.get_surface_override_material_count():
			var o := mi.get_surface_override_material(i)
			if o != null:
				out.append(o)
	elif g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm != null:
			mesh = mm.mesh
	if mesh != null:
		for i in mesh.get_surface_count():
			var sm := mesh.surface_get_material(i)
			if sm != null:
				out.append(sm)
	return out


# ---------------------------------------------------------------------------
# persistence
# ---------------------------------------------------------------------------
const SAVE_PATH := "user://graphics.cfg"
const KEYS := [
	"render_scale", "msaa", "shadows", "shadow_atlas", "ssao", "glow", "fog",
	"effects", "light_detail", "view_distance", "texture_detail",
	"lod_threshold", "anim_quality", "npc_detail", "vsync", "fps_cap",
]


## Not a quality knob: lives here because this is where the player's settings
## are kept, but it is in no preset and moving it never flips to Custom. A
## multiplier on the player's own `mouse_sensitivity`.
var mouse_sensitivity := 1.0
const SENSITIVITY_MIN := 0.1
const SENSITIVITY_MAX := 3.0


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX)
	save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "preset", preset)
	for key in KEYS:
		cfg.set_value("graphics", key, get(key))
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.save(SAVE_PATH)


func load_settings() -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		# No saved profile yet. Values only -- _ready applies once, deferred,
		# rather than twice from here.
		preset = Preset.LOW
		for key in PRESETS[Preset.LOW]:
			set(key, PRESETS[Preset.LOW][key])
		return
	preset = cfg.get_value("graphics", "preset", Preset.LOW)
	for key in KEYS:
		if cfg.has_section_key("graphics", key):
			set(key, cfg.get_value("graphics", key))
	mouse_sensitivity = clampf(float(cfg.get_value("controls", "mouse_sensitivity", 1.0)),
		SENSITIVITY_MIN, SENSITIVITY_MAX)
