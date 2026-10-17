@tool
extends Node3D

## TIMING PREVIEW (2026-10-17): the enforcers' attack timings -- the enforcer's
## and the decrepit enforcer's -- as named, coloured MARKERS on their clips in
## Godot's Animation timeline, seen against the animation itself; and DRAGGING a
## marker changes the timing.
##
## Open enforcer.tscn or decrepit.tscn beside this script, select its "Timeline"
## AnimationPlayer, pick a clip in the Animation panel at the bottom. Scrubbing
## poses the model in the viewport.
##
## ONE SOURCE OF TRUTH: the enemy's own script constants, which the game reads.
## The markers are built from them (a fresh compile of the source on disk) and
## rebuilt whenever the script is saved. A marker bound to a constant can be
## DRAGGED: the new time is snapped to the clip's frame (60 fps), turned into
## the constant's value, and written into the script in place of the old one
## (its formatting and comment kept) -- then the markers rebuild from it. If the
## script is open in the script editor, Godot will offer to reload it.
##
##   HIT                 -> *_CONTACT (the parry cue moves with it: its listen
##                          length is kept)
##   parry cue           -> *_LISTEN (= the hit - the cue: the window always
##                          closes on the blow)
##   move ends           -> *_END
##   lunge -> slide      -> DASH_LUNGE
##   settled: BEAM FIRES -> BEAM_SET_EARLY (= the clip's length - the marker)
## Gold "info" markers with no single value behind them (cannon up, the recoil)
## do not move anything; dragging one is undone at the next rebuild.
##
## Why markers are not simply authored on the clips: the clips are imported from
## .glb files and Godot rebuilds them on every reimport, so anything added to
## them in the editor would be lost. "Timeline" plays a COPY of the model's
## clips (made on load; its library is removed before the scene is saved and
## rebuilt after, so the .tscn stays small). An Animation keeps ONE marker per
## moment: markers that fall together are joined into one label (bound to the
## first, the draggable one).
##
## Colours: purple = parry, red = the blow, gold = worth knowing, grey = the
## move ends. The skeletons and the boss are early prototypes due a rework and
## have no preview (git history has one, 2026-10-17).

const PARRY := Color(0.66, 0.28, 1.0)
const HIT := Color(0.95, 0.2, 0.15)
const INFO := Color(0.95, 0.75, 0.3)
const END := Color(0.6, 0.6, 0.6)
const FPS := 60.0
const DECREPIT := "res://scripts/decrepit.gd"
const ENFORCER := "res://scripts/enforcer.gd"

## Which enemy this preview shows.
@export_enum("decrepit", "enforcer") var enemy := "decrepit":
	set(v):
		enemy = v
		_rebuild.call_deferred()

## The files whose saving rebuilds the markers, with their last seen times.
var _watched := {}
var _poll := 0.0
## Per clip: marker label -> [the time it was put at, its binding or null].
var _bound := {}


func _ready() -> void:
	if Engine.is_editor_hint():
		_rebuild()


func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.25
	for path in _watched:
		if FileAccess.get_modified_time(path) != _watched[path]:
			_rebuild()
			return
	check_drags()


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
	var marks: Dictionary = _decrepit() if enemy == "decrepit" else _enforcer()
	_bound.clear()
	for clip in marks:
		if not copy.has_animation(clip):
			continue
		var a := copy.get_animation(clip)
		# One marker per moment: what falls together is joined, in the first's
		# colour and bound as the first (the draggable ones are listed first).
		var at := {}
		var order: Array = []
		for m in marks[clip]:
			var t: float = snappedf(clampf(float(m[1]), 0.0, a.length), 0.0001)
			if not at.has(t):
				at[t] = [[], m[2], m[3] if m.size() > 3 else null]
				order.append(t)
			at[t][0].append(m[0])
		var bound := {}
		for t in order:
			var label: String = "  |  ".join(at[t][0])
			while a.has_marker(label):
				label += " "
			a.add_marker(label, t)
			a.set_marker_color(label, at[t][1])
			bound[label] = [t, at[t][2]]
		_bound[clip] = bound
		a.emit_changed()


# --- Dragging: a moved marker is written back into the script ------------------------

## Any bound marker no longer where it was put has been dragged: its new time,
## snapped to a frame, becomes its constant's value. One per call; the save
## rebuilds the rest. Public so a test can drive it.
func check_drags() -> bool:
	var tl := _timeline()
	if tl == null:
		return false
	for clip in _bound:
		if not tl.has_animation(clip):
			continue
		var a := tl.get_animation(clip)
		for label in _bound[clip]:
			if not a.has_marker(label):
				continue
			var was: float = _bound[clip][label][0]
			var t := a.get_marker_time(label)
			if absf(t - was) < 0.0005:
				continue
			var bind = _bound[clip][label][1]
			if bind == null:
				continue
			t = clampf(roundf(t * FPS) / FPS, 0.0, a.length)
			_bound[clip][label][0] = t
			if _write_back(bind, t, a.length):
				return true
	return false


## Binding: {"script", "const", "mode"} -- mode &"at" (the value is the time),
## &"before" (the value is `ref` minus the time: a listen length before the
## hit, an offset from the clip's end), with "ref"; "frames" writes N.0 / 60.0.
func _write_back(bind: Dictionary, t: float, clip_length: float) -> bool:
	var value := t
	if bind["mode"] == &"before":
		var ref: float = clip_length if bind.get("ref") == null else float(bind["ref"])
		value = maxf(ref - t, 1.0 / FPS)
	var text := ""
	if bind.get("frames", false):
		text = "%d.0 / 60.0" % roundi(value * FPS)
	else:
		text = String.num(snappedf(value, 0.0001), 4)
	var ok := write_const(bind["script"], bind["const"], text)
	if ok:
		print("[timing preview] %s := %s" % [bind["const"], text])
	return ok


## Replaces the value of `const NAME := ...` in the script at `path`, keeping
## the rest of the line (a trailing comment). False if it is not there.
static func write_const(path: String, name: String, value_text: String) -> bool:
	var src := FileAccess.get_file_as_string(path)
	var rx := RegEx.create_from_string("(?m)^(const " + name + " := )([^#\\n]*?)([ \\t]*(#[^\\n]*)?)$")
	var m := rx.search(src)
	if m == null:
		push_warning("timing preview: no `const %s` in %s" % [name, path])
		return false
	src = src.substr(0, m.get_start(2)) + value_text + src.substr(m.get_end(2))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(src)
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)
	return true


## The script's constants as they are on disk NOW: a fresh compile of its
## source, not the editor's cached copy (which can lag behind an edit made
## outside Godot, or by this tool).
static func _consts(path: String) -> Dictionary:
	var fresh := GDScript.new()
	fresh.source_code = FileAccess.get_file_as_string(path)
	if fresh.reload() == OK:
		return fresh.get_script_constant_map()
	var s := load(path) as Script
	return s.get_script_constant_map() if s != null else {}


func _s(x: float) -> String:
	return "%.2f s" % x


func _clip_length(clip: StringName) -> float:
	var tl := _timeline()
	if tl != null and tl.has_animation(clip):
		return tl.get_animation(clip).length
	return 0.0


static func _bind(script: String, name: String, mode := &"at", ref = null, frames := false) -> Dictionary:
	return {"script": script, "const": name, "mode": mode, "ref": ref, "frames": frames}


# --- The decrepit enforcer (scripts/decrepit.gd) ---------------------------------------

func _decrepit() -> Dictionary:
	_watch([DECREPIT])
	var c := _consts(DECREPIT)
	var out := {}
	for move in [["SWIPE", "SWIPE_BAKED", "SWIPE_DAMAGE"], ["JUMP", "JUMP_BAKED", "JUMP_DAMAGE"],
			["DROPKICK", "DROPKICK_BAKED", "DROPKICK_DAMAGE"]]:
		var k: String = move[0]
		var contact: float = c[k + "_CONTACT"]
		var listen: float = c[k + "_LISTEN"]
		out[StringName(move[1])] = [
			["HIT %d / parry window closes" % int(c[move[2]]), contact, HIT, _bind(DECREPIT, k + "_CONTACT")],
			["parry cue (listen %s)" % _s(listen), contact - listen, PARRY,
				_bind(DECREPIT, k + "_LISTEN", &"before", contact)],
			["move ends (%s_END)" % k, float(c[k + "_END"]), END, _bind(DECREPIT, k + "_END")],
		]
	var lunge: float = c["DASH_LUNGE"]
	out[&"DASH_BAKED"] = [
		["lunge held -> SLIDE (hit on arrival, %d)" % int(c["DASH_DAMAGE"]), lunge, INFO,
			_bind(DECREPIT, "DASH_LUNGE")],
		["parry cue: %s before arrival" % _s(float(c["DASH_LISTEN"])), lunge, PARRY],
	]
	return out


# --- The enforcer (scripts/enforcer.gd) ------------------------------------------------

func _enforcer() -> Dictionary:
	_watch([ENFORCER])
	var c := _consts(ENFORCER)
	var windup := _init_value(ENFORCER, "windup_time", 0.6)
	var contact: float = c["SWIPE_CONTACT"]
	var out := {}
	out[&"SWIPE_1_BAKED"] = [
		["HIT (plays at x%.2f: lands at windup %s)" % [contact / windup, _s(windup)], contact, HIT,
			_bind(ENFORCER, "SWIPE_CONTACT", &"at", null, true)],
		["parry: guard up <= 0.5 s before the HIT", contact, PARRY],
	]
	var beam := _clip_length(&"BEAM_BAKED")
	out[&"BEAM_BAKED"] = [
		["settled: BEAM FIRES (charge %s)" % _s(float(c["CHARGE_TIME"])), beam - float(c["BEAM_SET_EARLY"]), HIT,
			_bind(ENFORCER, "BEAM_SET_EARLY", &"before")],
		["cannon up (f37)", 37.0 / 60.0, INFO],
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
