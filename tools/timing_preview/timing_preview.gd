@tool
extends Node3D

## TIMING PREVIEW (2026-10-17): every enemy's attack timings as named, coloured
## MARKERS on its clips in Godot's Animation timeline, so they can be seen
## against the animation itself and scrubbed through.
##
## Open one of the scenes beside this script (decrepit.tscn, enforcer.tscn,
## skeleton.tscn, boss.tscn), select its "Timeline" AnimationPlayer, pick a clip
## in the Animation panel at the bottom. The markers are LIVE: they are read
## from the enemy's own script and scene (the single source of truth the game
## uses) and rebuilt whenever one of those files is saved -- change a timing,
## save, and the marker moves. Nothing here is used by the game.
##
## Why markers are not simply authored on the clips: the clips are imported from
## .glb files and Godot rebuilds them on every reimport, so anything added to
## them in the editor would be lost. "Timeline" plays a COPY of the model's
## clips (its library is made fresh on load and cleared before the scene is
## saved, so the .tscn stays small); its root is the model, so scrubbing poses
## the model in the viewport.
##
## Marker colours: purple = parry, red = the blow, gold = a moment worth knowing,
## grey = the move ends. Clips that are stretched at runtime to fit a duration
## (skeletons, the boss, the enforcer's swipe) say so in their marker names: the
## timeline shows the clip at its authored speed.

const PARRY := Color(0.66, 0.28, 1.0)
const HIT := Color(0.95, 0.2, 0.15)
const INFO := Color(0.95, 0.75, 0.3)
const END := Color(0.6, 0.6, 0.6)

## Which enemy this preview shows: decrepit, enforcer, skeleton, boss.
@export_enum("decrepit", "enforcer", "skeleton", "boss") var enemy := "decrepit":
	set(v):
		enemy = v
		_rebuild.call_deferred()

## The files whose saving rebuilds the markers, with their last seen times.
var _watched := {}
var _poll := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.5
	for path in _watched:
		var m := FileAccess.get_modified_time(path)
		if m != _watched[path]:
			_rebuild()
			return


func _notification(what: int) -> void:
	# The copied clips are rebuilt on every load: never written into the .tscn.
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		var tl := _timeline()
		if tl != null:
			for lib in tl.get_animation_library_list():
				tl.remove_animation_library(lib)
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_rebuild()


func _timeline() -> AnimationPlayer:
	return get_node_or_null(^"Timeline") as AnimationPlayer


func _model() -> Node:
	return get_node_or_null(^"Model")


func _watch(paths: Array) -> void:
	_watched.clear()
	for p in paths:
		_watched[p] = FileAccess.get_modified_time(p)


## Copies the model's clips onto Timeline and marks them.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	var tl := _timeline()
	var model := _model()
	if tl == null or model == null:
		return
	var src: AnimationPlayer = null
	for n in model.find_children("*", "AnimationPlayer", true, false):
		src = n
		break
	if model is AnimationPlayer:
		src = model
	if src == null:
		push_warning("timing preview: no AnimationPlayer in the model")
		return
	for lib in tl.get_animation_library_list():
		tl.remove_animation_library(lib)
	var copy := AnimationLibrary.new()
	for name in src.get_animation_list():
		if name == &"RESET":
			continue
		copy.add_animation(name, src.get_animation(name).duplicate(true))
	tl.add_animation_library(&"", copy)
	# Same root as the model's own player, so the tracks find the same bones.
	var root := src.get_node_or_null(src.root_node)
	if root != null:
		tl.root_node = tl.get_path_to(root)
	var marks: Dictionary = {}
	match enemy:
		"decrepit":
			marks = _decrepit()
		"enforcer":
			marks = _enforcer()
		"skeleton":
			marks = _skeleton("res://scenes/enemy.tscn")
		"boss":
			marks = _skeleton("res://scenes/boss.tscn")
	for clip in marks:
		if not copy.has_animation(clip):
			continue
		var a := copy.get_animation(clip)
		# One marker per moment (a second at the same time replaces the first):
		# what falls together is joined, in the colour of the first given.
		var at := {}
		var order: Array = []
		for m in marks[clip]:
			var t: float = snappedf(clampf(float(m[1]), 0.0, a.length), 0.0001)
			if not at.has(t):
				at[t] = [[], m[2]]
				order.append(t)
			at[t][0].append(m[0])
		for t in order:
			var label: String = "  |  ".join(at[t][0])
			# Names must be unique per clip.
			while a.has_marker(label):
				label += " "
			a.add_marker(label, t)
			a.set_marker_color(label, at[t][1])
		a.emit_changed()


## The script's constants as they are on disk NOW: a fresh compile of its
## source, not the editor's cached copy (which can lag behind an edit made
## outside Godot).
static func _consts(path: String) -> Dictionary:
	var fresh := GDScript.new()
	fresh.source_code = FileAccess.get_file_as_string(path)
	if fresh.reload() == OK:
		return fresh.get_script_constant_map()
	var s := load(path) as Script
	return s.get_script_constant_map() if s != null else {}


func _s(x: float) -> String:
	return "%.2f s" % x


# --- The decrepit (scripts/decrepit.gd) -----------------------------------------------

func _decrepit() -> Dictionary:
	_watch(["res://scripts/decrepit.gd"])
	var c := _consts("res://scripts/decrepit.gd")
	var out := {}
	for move in [["SWIPE", "SWIPE_BAKED", "SWIPE_DAMAGE", "SWIPE_END"],
			["JUMP", "JUMP_BAKED", "JUMP_DAMAGE", "JUMP_END"],
			["DROPKICK", "DROPKICK_BAKED", "DROPKICK_DAMAGE", "DROPKICK_END"]]:
		var contact: float = c[move[0] + "_CONTACT"]
		var listen: float = c[move[0] + "_LISTEN"]
		out[StringName(move[1])] = [
			["parry cue (listen %s)" % _s(listen), contact - listen, PARRY],
			["HIT %d / parry window closes" % int(c[move[2]]), contact, HIT],
			["move ends (%s)" % move[3], float(c[move[3]]), END],
		]
	var lunge: float = c["DASH_LUNGE"]
	out[&"DASH_BAKED"] = [
		["lunge held -> SLIDE (hit on arrival, %d)" % int(c["DASH_DAMAGE"]), lunge, INFO],
		["parry cue: %s before arrival" % _s(float(c["DASH_LISTEN"])), lunge, PARRY],
	]
	return out


# --- The enforcer (scripts/enforcer.gd) -----------------------------------------------

func _enforcer() -> Dictionary:
	_watch(["res://scripts/enforcer.gd"])
	var c := _consts("res://scripts/enforcer.gd")
	var windup := _init_value("res://scripts/enforcer.gd", "windup_time", 0.6)
	var contact: float = c["SWIPE_CONTACT"]
	var out := {}
	out[&"SWIPE_1_BAKED"] = [
		["HIT (plays at x%.2f: lands at windup %s)" % [contact / windup, _s(windup)], contact, HIT],
		["parry: guard up <= 0.5 s before the HIT", contact, PARRY],
	]
	var beam := _clip_length(&"BEAM_BAKED")
	out[&"BEAM_BAKED"] = [
		["cannon up (f37)", 37.0 / 60.0, INFO],
		["settled: BEAM FIRES (charge %s)" % _s(float(c["CHARGE_TIME"])), beam - float(c["BEAM_SET_EARLY"]), HIT],
	]
	out[&"BEAM_RECOIL_BAKED"] = [
		["firing: ping-pong x%.1f for %s, then vent %s" % [float(c["RECOIL_RATE"]), _s(float(c["BEAM_TIME"])),
			_s(float(c["VENT_TIME"]))], 0.0, INFO],
	]
	return out


## A value an enemy sets in its `_init` ("windup_time = 0.6"), read off the
## source: those never reach an inspector.
static func _init_value(path: String, prop: String, fallback: float) -> float:
	var src := FileAccess.get_file_as_string(path)
	var rx := RegEx.create_from_string("(?m)^\\t" + prop + " = ([0-9.]+)")
	var m := rx.search(src)
	return float(m.get_string(1)) if m != null else fallback


func _clip_length(clip: StringName) -> float:
	var tl := _timeline()
	if tl != null and tl.has_animation(clip):
		return tl.get_animation(clip).length
	return 0.0


# --- Skeletons and the boss (scripts/enemy.gd + their scene's values) -----------------

func _skeleton(scene_path: String) -> Dictionary:
	_watch(["res://scripts/enemy.gd", scene_path])
	var c := _consts("res://scripts/enemy.gd")
	var packed := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var inst := packed.instantiate()
	var v := func(prop: String) -> float: return float(inst.get(prop))
	var windup: float = v.call("windup_time")
	var recover: float = v.call("recover_time")
	var durations := {&"attack": v.call("normal_duration"), &"slam": v.call("slam_duration"),
		&"spin": v.call("spin_duration"), &"lunge": v.call("lunge_duration")}
	inst.free()
	var out := {}
	var wl := _clip_length(&"windup")
	if wl > 0.0:
		out[&"windup"] = [
			["telegraph (windup_time %s, x%.2f)" % [_s(windup), wl / maxf(windup, 0.01)], 0.0, INFO],
			["attack starts", wl, HIT],
		]
	var attack_clips := {}
	for clip in durations:
		attack_clips[clip] = durations[clip]
	for clip in c.get("NORMAL_ANIMS", []):
		attack_clips[clip] = durations[&"attack"]
	for clip in attack_clips:
		var l := _clip_length(clip)
		if l <= 0.0:
			continue
		var dur: float = attack_clips[clip]
		out[clip] = [
			["HITS from here, whenever in reach (lasts %s, x%.2f)" % [_s(dur), l / maxf(dur, 0.01)], 0.0, HIT],
			["parry: guard up <= 0.5 s before it lands", 0.0, PARRY],
			["attack over -> recover", l, END],
		]
	var rl := _clip_length(&"recover")
	if rl > 0.0:
		out[&"recover"] = [["recovered (recover_time %s)" % _s(recover), rl, END]]
	return out
