extends Node3D

## The intro (note 131): before the dungeon, outside it.
##
## A new game from the title (maze.gd `level_built`, `wanted()`) starts here
## instead of on the cell floor:
## 1. THE STORY (skippable: hold jump). Night on a forest road: a dying knight
##    against a tree presses a hilt with no blade -- a crystal in its pommel --
##    into a boy's hands. A study, years of books: one word, Vardia, and a set of
##    coordinates. A forested hill at dusk: he walks the last of the path up.
## 2. THE SEARCH. Control is theirs at the gate of the ruins (intro_world.gd),
##    and the lessons (intro_lessons.gd) teach every control while they search;
##    the Vardian sentinel (intro_sentinel.gd) wakes for the guard lessons.
## 3. TAKEN. At the altar the handle answers the place -- and from behind, a
##    sack over the head, a blow, the black. They wake on the cell floor, as a
##    new game always did (player.gd `wake_up`), and the game is created.
##
## While it runs the dungeon is built but hidden (maze `visible` off, its
## minimap too), its saves held (`maze.intro_running`, save_system.gd `_safe`),
## and the Environment it lights with is set to the intro's own look, every
## property kept and put back after (as the sewer's haze does). The world it
## builds is far out at intro_world.gd ORIGIN and freed at the end.
##
## STAND-INS: the forest, the figures, the posts are made in code (see
## intro_world.gd); the user chose that while no Higgsfield generation was
## available, to be replaced by generated models.

const World := preload("res://scripts/intro_world.gd")
const Lessons := preload("res://scripts/intro_lessons.gd")
const Figure := preload("res://scripts/intro_figure.gd")
const Sentinel := preload("res://scripts/intro_sentinel.gd")
const Subtitles := preload("res://scripts/subtitles.gd")
const WOOD_DOOR := preload("res://scripts/wood_door.gd")
const BAG_SHADER := preload("res://shaders/burlap_bag.gdshader")

## Held this long, jump skips the story.
const SKIP_HOLD := 1.0
## Every Environment property the intro sets (`World.profile`), kept to restore.
const ENV_KEYS := ["sky", "background_mode", "background_energy_multiplier", "ambient_light_source",
	"ambient_light_color", "ambient_light_energy", "ambient_light_sky_contribution", "fog_mode",
	"fog_light_color", "fog_light_energy", "fog_density", "fog_sun_scatter", "fog_sky_affect",
	"volumetric_fog_density", "volumetric_fog_albedo", "volumetric_fog_anisotropy",
	"volumetric_fog_length", "volumetric_fog_ambient_inject", "volumetric_fog_sky_affect",
	"tonemap_exposure"]

signal finished

var maze: Node3D
var world: Node3D
var lessons: Node
var sentinel: CharacterBody3D
var players: Array[Node] = []

var _env_saved := {}
var _moons := {}
var _home := {}
var _cams := {}
var _huds_hidden := []
var _minimaps := []
var _black: ColorRect
var _black_layer: CanvasLayer
var _card: Label
var _skip_label: Label
var _skip := false
var _skip_held := 0.0
var _in_story := false
var _sub: CanvasLayer
var _bars: CanvasLayer
var _bags := []
var _shot_from := Transform3D()
var _shot_to := Transform3D()
var _shot_t := 0.0
var _shot_len := 1.0
var _shooting := false


## A new game from the title gets the intro. `-- --intro` forces it (testing),
## `-- --no-intro` leaves it out; the sandbox, a loaded save and the harnesses
## (slot -1) never get it.
static func wanted(save: Dictionary) -> bool:
	var args := OS.get_cmdline_user_args()
	if "--no-intro" in args or Sandbox.active or save.has("seed"):
		return false
	if "--intro" in args:
		return true
	return Saves.slot >= 0


static func begin(maze_: Node3D) -> Node:
	var i := Node3D.new()
	i.set_script(load("res://scripts/intro.gd"))
	i.name = "Intro"
	i.set("maze", maze_)
	# Beside the maze, not in it: the maze is hidden while this runs.
	maze_.get_parent().add_child(i)
	i.call("_run")
	return i


# --- Running ---------------------------------------------------------------------

func _run() -> void:
	maze.set("intro_running", true)
	players = Coop.all()
	_make_black()
	for p in players:
		var n := p as Node3D
		_home[p] = [n.global_transform, float(p.get("_look_pitch"))]
		p.call("begin_cutscene")
		p.set("hands_busy", true)
		var hud := Coop.hud(p)
		if hud != null and hud.visible:
			hud.visible = false
			_huds_hidden.append(hud)
	# Two frames for the black to be up before the long build.
	await _frame()
	await _frame()
	_hide_dungeon(true)
	_coins(false)
	# From the title the HUD holds its own black over the level's build (hud.gd),
	# on a layer above everything here. Only now: a new ColorRect is not drawn on
	# its first frame, and without this black the cell shows through the stall.
	for hud in Coop.huds():
		hud.call("fade_black", 0.0, 0.0)
	world = World.new()
	add_child(world)
	world.call("build")
	sentinel = Sentinel.new()
	world.add_child(sentinel)
	sentinel.global_position = world.call("at", &"sentinel")
	sentinel.rotation.y = PI * 0.62
	_set_look(&"dusk")
	_in_story = true
	await _story()
	_in_story = false
	if _skip_label != null:
		_skip_label.queue_free()
		_skip_label = null
	await _arrive()
	await _search()
	await _taken()
	_finish()


func _process(delta: float) -> void:
	if _in_story and not _skip:
		var held := false
		for p in players:
			if Coop.held(p, &"jump"):
				held = true
		_skip_held = _skip_held + delta if held else 0.0
		if _skip_label != null:
			_skip_label.modulate.a = 0.55 + 0.45 * clampf(_skip_held / SKIP_HOLD, 0.0, 1.0)
		if _skip_held >= SKIP_HOLD:
			_skip = true
			if _sub != null and is_instance_valid(_sub):
				_sub.visible = false
	if _shooting:
		_shot_t = minf(_shot_t + delta, _shot_len)
		var k := _shot_t / _shot_len
		k = k * k * (3.0 - 2.0 * k)
		var xf := _shot_from.interpolate_with(_shot_to, k)
		for p in _cams:
			(_cams[p] as Camera3D).global_transform = xf


## One frame of a scene. The pause menu is open throughout, so they can leave for
## the title mid-intro: this node is then out of the tree but not yet freed, and
## would run the rest of the intro with no tree. It stops here, on a signal that
## will never come.
func _frame(physics := false) -> void:
	await (get_tree().physics_frame if physics else get_tree().process_frame)
	if not is_inside_tree():
		await finished


## Left for the title: what the intro put on the root would stay over the title.
func _exit_tree() -> void:
	if lessons != null:
		lessons.call("close")
	for n in [_black_layer, _bars, _sub] + _bags + _cams.values():
		if is_instance_valid(n):
			n.queue_free()


## Waits `seconds` (paused with the game), or less once the story is skipped.
func _beat(seconds: float) -> void:
	var left := seconds
	while left > 0.0 and not (_in_story and _skip):
		await _frame()
		if not get_tree().paused:
			left -= get_process_delta_time()


# --- Looks: the environment and the lights ----------------------------------------

func _envs() -> Array[Environment]:
	var out: Array[Environment] = []
	if Coop.active and Coop.split != null and is_instance_valid(Coop.split):
		for p in players:
			var c := Coop.view_camera(p)
			if c != null and c.environment != null and not out.has(c.environment):
				out.append(c.environment)
	var w := get_viewport().find_world_3d()
	if w != null and w.environment != null and not out.has(w.environment):
		out.append(w.environment)
	return out


func _set_look(which: StringName) -> void:
	var prof: Dictionary = world.call("profile", which)
	for env in _envs():
		var key := env.get_instance_id()
		if not _env_saved.has(key):
			var saved := {"env": env}
			for k in ENV_KEYS:
				saved[k] = env.get(k)
			_env_saved[key] = saved
		env.background_mode = Environment.BG_SKY
		for k in prof:
			env.set(k, prof[k])
	world.call("set_lights", which)


func _restore_look() -> void:
	for key in _env_saved:
		var saved: Dictionary = _env_saved[key]
		var env: Environment = saved["env"]
		if not is_instance_valid(env):
			continue
		for k in ENV_KEYS:
			env.set(k, saved[k])
	_env_saved.clear()


## The dungeon out of sight (and its moon dark, its minimap hidden) while the
## intro runs, or back.
func _hide_dungeon(hide: bool) -> void:
	maze.visible = not hide
	if hide:
		for n in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			if (n.has_meta("moon") or String(n.name).to_lower().contains("moon")) and not world_has(n):
				_moons[n] = (n as DirectionalLight3D).light_energy
				(n as DirectionalLight3D).light_energy = 0.0
		for m in maze.find_children("ExploreMap*", "", false, false):
			var root = m.get("_minimap_root")
			if root != null and (root as Control).visible:
				(root as Control).visible = false
				_minimaps.append(root)
	else:
		for n in _moons:
			if is_instance_valid(n):
				(n as DirectionalLight3D).light_energy = _moons[n]
		_moons.clear()
		for root in _minimaps:
			if is_instance_valid(root):
				(root as Control).visible = true
		_minimaps.clear()


## The coin counter (the explore map's, under the minimap): off for the
## scenes, on for the search.
func _coins(on: bool) -> void:
	for m in maze.find_children("ExploreMap*", "", false, false):
		var row = m.get("_currency_row")
		if row != null and is_instance_valid(row):
			(row as Control).visible = on


func world_has(n: Node) -> bool:
	return world != null and world.is_ancestor_of(n)


# --- The screen -------------------------------------------------------------------

func _make_black() -> void:
	_black_layer = CanvasLayer.new()
	_black_layer.layer = 45
	get_tree().root.add_child(_black_layer)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black_layer.add_child(_black)
	_card = Label.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_theme_font_size_override("font_size", 30)
	_card.add_theme_color_override("font_color", Color(0.86, 0.8, 0.68))
	_card.modulate.a = 0.0
	_black_layer.add_child(_card)
	_skip_label = Label.new()
	_skip_label.anchor_left = 1.0
	_skip_label.anchor_right = 1.0
	_skip_label.anchor_top = 1.0
	_skip_label.anchor_bottom = 1.0
	_skip_label.offset_left = -320
	_skip_label.offset_right = -36
	_skip_label.offset_top = -56
	_skip_label.offset_bottom = -24
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_label.add_theme_font_size_override("font_size", 15)
	_skip_label.add_theme_color_override("font_color", Color(0.75, 0.72, 0.66))
	var pad := not players.is_empty() and Coop.on_pad(players[0])
	_skip_label.text = "Hold  A  to skip" if pad else "Hold  SPACE  to skip"
	_skip_label.modulate.a = 0.55
	_black_layer.add_child(_skip_label)


func _fade(to_alpha: float, time: float) -> void:
	var t := _black.create_tween()
	t.tween_property(_black, "color:a", to_alpha, time)
	await _beat(time)


func _card_text(text: String, hold: float) -> void:
	if _skip:
		return
	_card.text = text
	var t := _card.create_tween()
	t.tween_property(_card, "modulate:a", 1.0, 0.8)
	await _beat(0.8 + hold)
	var t2 := _card.create_tween()
	t2.tween_property(_card, "modulate:a", 0.0, 0.8)
	await _beat(0.8)


## A line spoken (or narrated, speaker ""), typed out. Skippable.
func _say(speaker: String, text: String, per_char := 0.04, hold := 1.5) -> void:
	if _in_story and _skip:
		return
	if _sub == null or not is_instance_valid(_sub):
		_sub = Subtitles.open(self)
	var done := [false]
	var run := func() -> void:
		await _sub.say(speaker, text, per_char, hold)
		done[0] = true
	run.call()
	while not done[0] and not (_in_story and _skip):
		await _frame()


func _end_subs() -> void:
	if _sub != null and is_instance_valid(_sub):
		var s := _sub
		_sub = null
		# Let a line cut short by a skip finish its timers before it goes.
		s.visible = false
		get_tree().create_timer(12.0).timeout.connect(s.queue_free)


## A cinematic camera for every player, current; `xf` where it starts.
func _cameras_on(xf: Transform3D) -> void:
	for p in players:
		if not _cams.has(p):
			var c := Camera3D.new()
			c.fov = 55.0
			c.near = 0.05
			c.far = 900.0
			p.get_viewport().add_child(c)
			_cams[p] = c
		var cam: Camera3D = _cams[p]
		cam.global_transform = xf
		cam.make_current()
	_shooting = false


func _cameras_off() -> void:
	for p in _cams:
		var c: Camera3D = _cams[p]
		if is_instance_valid(c):
			c.queue_free()
		var own = p.get("camera")
		if own != null:
			(own as Camera3D).make_current()
	_cams.clear()
	_shooting = false


## The cameras move from `a` to `b` (eased) over `time`.
func _shot(a: Transform3D, b: Transform3D, time: float) -> void:
	_shot_from = a
	_shot_to = b
	_shot_t = 0.0
	_shot_len = maxf(time, 0.01)
	_shooting = true
	for p in _cams:
		(_cams[p] as Camera3D).global_transform = a


static func look(from: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(at - from, Vector3.UP), from)


# --- 1. The story -------------------------------------------------------------------

func _story() -> void:
	await _beat(0.6)
	await _card_text("Many years ago", 1.6)
	if _skip:
		return
	# --- The north road, at night.
	_set_look(&"night")
	var tree: Vector3 = world.call("at", &"knight_tree")
	var pad: Vector3 = world.call("at", &"knight_pad")
	var out := (pad - tree)
	out.y = 0.0
	out = out.normalized()
	var knight := Figure.new()
	knight.set("style", &"knight")
	world.add_child(knight)
	knight.global_position = tree + out * 0.75 + Vector3(0, 0.32, 0)
	knight.rotation.y = atan2(out.x, out.z)
	knight.call("snap", &"sit_slump")
	var hilt := Figure.make_hilt()
	knight.get("hand_r").add_child(hilt)
	hilt.position = Vector3(0, -0.06, 0.02)
	hilt.rotation = Vector3(PI * 0.5, 0, 0)
	var kid := Figure.new()
	kid.set("style", &"kid")
	world.add_child(kid)
	var kid_at := knight.global_position + out * 1.25 + out.cross(Vector3.UP) * 0.25
	kid_at.y = world.call("height", kid_at.x - world.global_position.x, kid_at.z - world.global_position.z) + world.global_position.y
	kid.global_position = kid_at
	kid.rotation.y = atan2(-out.x, -out.z)
	kid.call("snap", &"kneel")
	var side := out.cross(Vector3.UP).normalized()
	# A dim fill on the two of them (the moon through the leaves).
	var fill := OmniLight3D.new()
	fill.light_color = Color(0.55, 0.62, 0.9)
	fill.light_energy = 0.9
	fill.omni_range = 5.5
	world.add_child(fill)
	fill.global_position = knight.global_position + out * 2.2 + side * -1.2 + Vector3(0, 2.2, 0)
	var face: Vector3 = knight.global_position + Vector3(0, 0.95, 0)
	_cameras_on(look(pad + out * 7.0 + side * 4.0 + Vector3(0, 2.4, 0), face))
	_shot(look(pad + out * 7.5 + side * 4.5 + Vector3(0, 2.6, 0), face),
		look(pad + out * 4.6 + side * 2.6 + Vector3(0, 1.8, 0), face), 9.0)
	_bars = WOOD_DOOR.letterbox(self)
	await _fade(0.0, 1.6)
	await _say("", "I was nine when I found him on the north road.", 0.045, 1.4)
	await _say("", "His cart was burning. He had dragged himself as far as the trees.", 0.04, 1.2)
	if _skip:
		return
	# Over the boy's shoulder, onto him.
	var behind_kid: Vector3 = kid.global_position - out * -0.9 + side * 0.55 + Vector3(0, 0.95, 0)
	_shot(look(kid.global_position + out * 1.1 + side * 0.6 + Vector3(0, 1.05, 0), face),
		look(kid.global_position + out * 0.85 + side * 0.45 + Vector3(0, 1.0, 0), face + Vector3(0, -0.1, 0)), 7.0)
	knight.call("pose", &"offer", 1.6)
	await _say("THE KNIGHT", "...Come here, boy.", 0.06, 1.0)
	await _say("THE KNIGHT", "Take it. Don't let them have it.", 0.05, 1.0)
	await _say("THE BOY", "Who? Sir -- who?", 0.04, 0.8)
	if _skip:
		return
	# The hilt changes hands.
	var kid_hand: Node3D = kid.get("hand_r")
	hilt.reparent(kid_hand, false)
	hilt.position = Vector3(-0.08, -0.08, 0.06)
	hilt.rotation = Vector3(0.2, 0.0, PI * 0.5)
	kid.call("pose", &"hold", 3.0)
	_shot(look(behind_kid + out * 1.6 + Vector3(0, 0.15, 0), kid.global_position + Vector3(0, 0.45, 0)),
		look(behind_kid + out * 1.25 + Vector3(0, 0.05, 0), kid.global_position + Vector3(0, 0.4, 0)), 6.0)
	await _say("THE KNIGHT", "It remembers where it came from... take it home...", 0.065, 1.4)
	knight.call("pose", &"dead", 0.9)
	await _beat(1.6)
	_shot(look(pad + out * 5.5 + side * -3.5 + Vector3(0, 2.0, 0), face),
		look(pad + out * 6.5 + side * -4.2 + Vector3(0, 2.6, 0), face), 6.0)
	await _say("", "He never told me his name. Only that.", 0.045, 1.6)

	if _skip:
		return
	await _fade(1.0, 1.2)
	# --- The study, the years.
	_set_look(&"study")
	var desk: Vector3 = world.call("at", &"study_desk")
	var map_at: Vector3 = world.call("at", &"study_map")
	var desk_hilt := Figure.make_hilt()
	world.add_child(desk_hilt)
	desk_hilt.global_position = desk + Vector3(-0.15, 0.03, 0.22)
	desk_hilt.rotation = Vector3(0.0, 0.7, PI * 0.5)
	_cameras_on(look(desk + Vector3(0.9, 0.75, 1.5), desk + Vector3(0, 0.05, 0)))
	_shot(look(desk + Vector3(1.1, 0.85, 1.7), desk + Vector3(0, 0.05, 0)),
		look(desk + Vector3(0.55, 0.55, 0.95), desk + Vector3(0, 0.0, 0.1)), 12.0)
	await _fade(0.0, 1.4)
	await _say("", "I spent my life on it. Every library. Every scholar who would see me.", 0.04, 1.2)
	await _say("", "A handle with no blade. A crystal that never dims.", 0.045, 1.4)
	if _skip:
		return
	_shot(look(map_at + Vector3(0.25, 0.55, 0.45), map_at),
		look(map_at + Vector3(0.1, 0.32, 0.2), map_at), 9.0)
	await _say("", "One word, in every margin I ever found: Vardia.", 0.045, 1.4)
	await _say("", "A people gone without a trace. And a place where they had been.", 0.042, 1.6)
	if _skip:
		return
	await _fade(1.0, 1.2)
	# --- The hill, at last.
	_set_look(&"dusk")
	await _card_text("Thirty years later", 1.4)
	if _skip:
		return
	var vista: Vector3 = world.call("at", &"vista")
	var crown: Vector3 = world.call("at", &"crown")
	_cameras_on(look(vista, crown + Vector3(0, 6.0, 0)))
	_shot(look(vista, crown + Vector3(0, 9.0, 0)), look(vista + Vector3(0, 1.2, 0) + (crown - vista).normalized() * 6.0, crown + Vector3(0, 5.0, 0)), 9.0)
	await _fade(0.0, 1.6)
	await _say("", "I followed the numbers here.", 0.05, 2.2)


# --- 2. Arriving, and the search -----------------------------------------------------

func _arrive() -> void:
	var skipped := _skip
	if skipped:
		_black.color.a = 1.0
	_end_subs()
	_set_look(&"dusk")
	# Walked up the last of the path, in their own eyes.
	var from: Vector3 = world.call("at", &"walk_from")
	var mid: Vector3 = world.call("at", &"walk_mid")
	var arrive: Vector3 = world.call("at", &"arrive")
	var gate: Vector3 = world.call("at", &"gate")
	for i in players.size():
		var p := players[i] as Node3D
		var side := (mid - from).cross(Vector3.UP).normalized() * (1.4 * float(i))
		var start := (arrive - (gate - arrive).normalized() * 2.0 + side) if skipped else from + side
		p.global_position = start
		p.velocity = Vector3.ZERO
		p.rotation.y = atan2(-(mid - from).x, -(mid - from).z)
		p.set("_look_pitch", 0.0)
	_cameras_off()
	if not skipped:
		await _fade(1.0, 0.6)
	await _frame(true)
	await _fade(0.0, 1.0)
	if not skipped:
		for i in players.size():
			var side := (mid - from).cross(Vector3.UP).normalized() * (1.4 * float(i))
			players[i].call("scene_walk_to", mid + side, 12.0)
		await _walk_all()
		for i in players.size():
			var side := (arrive - mid).cross(Vector3.UP).normalized() * (1.4 * float(i))
			players[i].call("scene_walk_to", arrive + side, 12.0)
		await _walk_all()
	for p in players:
		p.call("scene_look_at", gate + Vector3(0, 2.4, 0), 2.5)
	Coop.announce_all("VARDIA", "The coordinates end here.")
	await _beat(2.6)
	world.call("close_path")
	if _bars != null and is_instance_valid(_bars):
		WOOD_DOOR.letterbox_out(_bars)
		_bars = null
	for hud in _huds_hidden:
		if is_instance_valid(hud):
			hud.visible = true
	_coins(true)
	for p in players:
		p.call("end_cutscene")
		p.set("hands_busy", false)
	_black_layer.visible = true


func _walk_all() -> void:
	# In an array: a lambda captures a local by value, so it would count down its own copy.
	var left := [players.size()]
	var done := func() -> void:
		left[0] -= 1
	for p in players:
		p.connect("scene_walk_finished", done, CONNECT_ONE_SHOT)
	while left[0] > 0:
		await _frame()


func _search() -> void:
	lessons = Lessons.new()
	lessons.set("world", world)
	lessons.set("sentinel", sentinel)
	add_child(lessons)
	lessons.connect("lesson_started", _on_lesson)
	lessons.call("begin", players)
	await lessons.finished


func _on_lesson(id: StringName) -> void:
	match id:
		&"block":
			# The handle stirs the sentinel.
			for p in players:
				p.call("begin_cutscene")
				p.call("scene_look_at", sentinel.global_position + Vector3(0, 2.0, 0), 3.0)
			lessons.call("set_visible", false)
			await _say("", "The handle is humming in my hand...", 0.045, 0.6)
			sentinel.call("wake")
			await _beat(1.9)
			_end_subs()
			lessons.call("set_visible", true)
			for p in players:
				p.call("end_cutscene")
		&"altar":
			await _say("", "It's pulling toward the altar. It knows this place.", 0.045, 1.4)
			_end_subs()


# --- 3. Taken ---------------------------------------------------------------------

func _taken() -> void:
	lessons.call("close")
	_coins(false)
	for p in players:
		p.call("begin_cutscene")
		p.set("hands_busy", true)
		p.call("scene_look_at", world.call("at", &"altar") + Vector3(0, 0.2, 0), 2.0)
	# The altar answers: light out of the stone, the runes on the standing stone.
	var glow: OmniLight3D = world.get("altar_glow")
	var tw := create_tween()
	tw.tween_property(glow, "light_energy", 5.0, 2.2)
	for p in players:
		p.set("_shake", 0.18)
	await _beat(2.6)
	# Watched: eyes in the trees behind them, the enforcers' blue.
	var eyes := _eyes()
	await _say("", "...", 0.3, 0.8)
	tw = create_tween()
	tw.tween_property(glow, "light_energy", 0.0, 0.6)
	await _beat(1.0)
	# From behind: the sack.
	_bars = WOOD_DOOR.letterbox(self)
	var bags: Array = []
	for p in players:
		bags.append(_bag(p))
	for b in bags:
		var rect: ColorRect = b[1]
		var t := rect.create_tween()
		t.tween_property(rect, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for p in players:
		p.set("_shake", 0.5)
		p.call("scene_lean", Vector3(0.0, -0.1, 0.2), 8.0)
		p.call("scene_frame", -4.0, 9.0, 6.0)
	await _beat(0.4)
	for k in 5:
		for p in players:
			p.call("scene_lean", Vector3(0.1 * (1.0 if k % 2 == 0 else -1.0), -0.08, 0.18), 9.0)
			p.set("_shake", maxf(float(p.get("_shake")), 0.14))
		await _beat(0.22)
	await _say("???", "Easy. Easy now.", 0.05, 0.5)
	await _say("???", "That's the one. The bearer too -- take them both.", 0.04, 0.4)
	# The blow.
	for p in players:
		p.set("_shake", 0.9)
	_black.color = Color(1, 1, 1, 0.9)
	var flash := _black.create_tween()
	flash.tween_property(_black, "color", Color(0, 0, 0, 1), 0.35)
	_end_subs()
	await _beat(1.6)
	for b in bags:
		(b[0] as CanvasLayer).queue_free()
	for e in eyes:
		e.queue_free()
	_sub = Subtitles.open(self)
	# Heard in the dark: over our black (layer 45).
	_sub.layer = 46
	await _sub.say("???", "Below. With the others.", 0.06, 1.6)
	_end_subs()
	await _beat(0.8)


## Three pairs of blue eyes among the trees, behind the players.
func _eyes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var p0 := players[0] as Node3D
	var back := p0.global_basis.z
	back.y = 0.0
	back = back.normalized()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.0, 0.91, 1.0)
	mat.emission_enabled = true
	var dot := SphereMesh.new()
	dot.radius = 0.05
	dot.height = 0.1
	for i in 3:
		var a := (float(i) - 1.0) * 0.45
		var dir := back.rotated(Vector3.UP, a)
		var at := p0.global_position + dir * (24.0 + i * 3.0)
		var local: Vector3 = world.to_local(at)
		at.y = world.call("height", local.x, local.z) + world.global_position.y + 1.65
		var pair := Node3D.new()
		world.add_child(pair)
		pair.global_position = at
		pair.look_at(p0.global_position + Vector3(0, 1.6, 0), Vector3.UP)
		for s: float in [-1.0, 1.0]:
			var e := MeshInstance3D.new()
			e.mesh = dot
			e.material_override = mat
			e.position = Vector3(0.09 * s, 0, 0)
			pair.add_child(e)
		out.append(pair)
	return out


func _bag(p: Node) -> Array:
	var layer := CanvasLayer.new()
	layer.layer = 38
	Coop.ui_root(p).add_child(layer)
	_bags.append(layer)
	var size := layer.get_viewport().get_visible_rect().size
	var mat := ShaderMaterial.new()
	mat.shader = BAG_SHADER
	mat.set_shader_parameter(&"aspect", size.x / maxf(size.y, 1.0))
	mat.set_shader_parameter(&"see", 0.35)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	rect.size = size * 1.2
	rect.position = Vector2(-size.x * 0.1, -size.y * 1.3)
	layer.add_child(rect)
	return [layer, rect]


# --- The end: into the cell -------------------------------------------------------

func _finish() -> void:
	_restore_look()
	_hide_dungeon(false)
	_coins(true)
	_cameras_off()
	if _bars != null and is_instance_valid(_bars):
		_bars.queue_free()
	for p in players:
		if not is_instance_valid(p):
			continue
		var home: Array = _home[p]
		var n := p as CharacterBody3D
		n.global_transform = home[0]
		n.velocity = Vector3.ZERO
		p.set("_look_pitch", home[1])
		p.call("end_cutscene")
		p.set("hands_busy", false)
		if p.has_method("set_spawn_point"):
			p.call("set_spawn_point", (home[0] as Transform3D).origin)
		# They wake with what a new game starts with (the intro's potions and
		# blows were a lesson): full health, the new game's pack.
		if p.has_method("_reset_inventory"):
			p.call("_reset_inventory", true)
		p.set("health", float(p.get("max_health")))
		p.emit_signal("health_changed", float(p.get("health")), float(p.get("max_health")))
	for hud in _huds_hidden:
		if is_instance_valid(hud):
			hud.visible = true
	world.queue_free()
	world = null
	maze.set("intro_running", false)
	# The wake holds its own black (hud.gd), so ours can go.
	for p in players:
		if p.has_method("wake_up"):
			p.call("wake_up")
	await _frame()
	_black_layer.queue_free()
	Saves.request("new game")
	print("[intro] done: into the cell")
	finished.emit()
	queue_free()
