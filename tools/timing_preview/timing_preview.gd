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
##   HIT n start / end   -> window n of *_HITS, [start, end] (a move may land
##                          several blows; the shield's hitbox is live between
##                          them -- shield_hitbox.gd)
##   parry cue n         -> element n of *_CUES (each its own marker: moving a
##                          hit does not move it; its label says how long it
##                          listens, *_LISTEN, and where that window closes
##                          against the next hit)
##   move ends           -> *_END
##   lunge -> slide      -> DASH_LUNGE (the dash's first hit is its arrival;
##                          the slide's real length is DASH_SLIDE_TIME)
##
## ADDING and DELETING (the decrepit's moves, the enforcer's swipe): insert a
## marker on a clip (right-click the timeline -> Insert Marker) and name it
## "hit" or "parry": a "hit" adds a window from there to NEW_WINDOW later (drag
## its end), a "parry" a cue. Delete a HIT n start / end (the window goes) or a
## parry cue n marker and it is taken out (a move keeps at least one hit: the
## one its lunge aims at; the last one cannot be deleted). Renumbered after.
##   settled: the recoil starts -> BEAM_SET_EARLY (= the clip's length - the marker)
##   BEAM ON (the kick)          -> RECOIL_BEAM (frames)
## Gold "info" markers with no single value behind them (cannon up)
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
## A hit window added by hand lasts this long until its end is dragged.
const NEW_WINDOW := 0.1
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
## Per clip: &"hit" / &"parry" -> the binding a new marker of that name appends to.
var _lists := {}
## The last rebuild could not read the enemy's script (a file it uses not yet
## scanned by the editor, an edit half saved...): it is tried again, RETRY_EVERY.
var _failed := false
var _retry_in := 0.0
const RETRY_EVERY := 2.0


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
	if _failed:
		_retry_in -= 0.25
		if _retry_in <= 0.0:
			_rebuild()
		return
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
	# The script read first: if it cannot be, the timeline is left as it was
	# and it is tried again (it used to swap in bare copies and stop there --
	# found 2026-10-17: a new file the script preloads, not yet scanned by an
	# editor that was already open, failed the compile, and every marker went).
	var path := DECREPIT if enemy == "decrepit" else ENFORCER
	_watch([path])
	if not _readable(path):
		if not _failed:
			push_warning("timing preview: cannot read %s yet (a file it uses may not be scanned, or it has an error) -- retrying every %d s" % [path, int(RETRY_EVERY)])
		_failed = true
		_retry_in = RETRY_EVERY
		return
	if _failed:
		print("[timing preview] %s read: markers rebuilt" % path)
	_failed = false
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
	_lists.clear()
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

## The timeline against what was put on it, one change per call (the script's
## save rebuilds everything): a bound marker moved -> its value; a new marker
## named "hit" / "parry" -> added to the clip's move; a bound marker gone ->
## its value taken out. Times snap to the clip's frames. Public so a test can
## drive it.
func check_drags() -> bool:
	var tl := _timeline()
	if tl == null:
		return false
	for clip in _bound:
		if not tl.has_animation(clip):
			continue
		var a := tl.get_animation(clip)
		var known: Dictionary = _bound[clip]
		# Added by hand.
		for name in a.get_marker_names():
			if known.has(String(name)):
				continue
			var kind := _added_kind(String(name))
			if kind == &"" or not _lists.has(clip) or not (_lists[clip] as Dictionary).has(kind):
				continue
			var t := _snap(a.get_marker_time(name), a.length)
			a.remove_marker(name)
			if _edit_list(_lists[clip][kind], &"add", -1, t):
				return true
		for label in known.keys():
			var bind = known[label][1]
			# Deleted.
			if not a.has_marker(label):
				if bind != null and bind.get("index") != null:
					known.erase(label)
					if _edit_list(bind, &"remove", int(bind["index"]), 0.0):
						return true
					# Refused (the last hit): put back at the next rebuild.
					_rebuild.call_deferred()
					return false
				continue
			# Moved.
			var was: float = known[label][0]
			var t := a.get_marker_time(label)
			if absf(t - was) < 0.0005 or bind == null:
				continue
			t = _snap(t, a.length)
			known[label][0] = t
			if bind.get("index") != null:
				if _edit_list(bind, &"set", int(bind["index"]), t, int(bind.get("part", -1))):
					return true
			elif _write_back(bind, t, a.length):
				return true
	return false


func _snap(t: float, length: float) -> float:
	return clampf(roundf(t * FPS) / FPS, 0.0, length)


## A marker the user added: &"hit", &"parry" or &"" (anything else is theirs).
static func _added_kind(name: String) -> StringName:
	var n := name.strip_edges().to_lower()
	if n.begins_with("hit"):
		return &"hit"
	if n.begins_with("parry") or n.begins_with("cue"):
		return &"parry"
	return &""


## Adds `t` to, moves element `index` of, or removes element `index` from the
## list constant a binding names; sorted and written back. A *_HITS list never
## goes empty.
func _edit_list(bind: Dictionary, op: StringName, index: int, t: float, part := -1) -> bool:
	var c := _consts(bind["script"])
	var windows := String(bind["const"]).ends_with("_HITS")
	var list: Array = _sorted(c.get(bind["const"], []) as Array, windows)
	match op:
		&"add":
			list.append([t, t + NEW_WINDOW] if windows else t)
		&"set":
			if index < 0 or index >= list.size():
				return false
			if windows:
				list[index][maxi(part, 0)] = t
			else:
				list[index] = t
		&"remove":
			if index < 0 or index >= list.size():
				return false
			if windows and list.size() <= 1:
				push_warning("timing preview: a move keeps at least one hit (%s)" % bind["const"])
				return false
			list.remove_at(index)
	list = _sorted(list, windows)
	var items: PackedStringArray = []
	for v in list:
		if windows:
			items.append("[%s, %s]" % [_num(v[0]), _num(v[1])])
		else:
			items.append(_num(v))
	var text := "[" + ", ".join(items) + "]"
	var ok := write_const(bind["script"], bind["const"], text)
	if ok:
		print("[timing preview] %s := %s" % [bind["const"], text])
	return ok


static func _num(v) -> String:
	return String.num(snappedf(float(v), 0.0001), 4)


## A list in order: cue times sorted; hit windows each [min, max], by start.
static func _sorted(list: Array, windows: bool) -> Array:
	var out: Array = []
	for v in list:
		if windows:
			out.append([minf(float(v[0]), float(v[1])), maxf(float(v[0]), float(v[1]))])
		else:
			out.append(float(v))
	if windows:
		out.sort_custom(func(x, y): return x[0] < y[0])
	else:
		out.sort()
	return out


## A single value (not a list): {"script", "const", "mode"} -- mode &"at" (the
## value is the time), &"before" (the value is `ref` minus the time: an offset
## from the clip's end), with "ref"; "frames" writes N.0 / 60.0.
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


## Whether the script compiles and has what the markers are built from.
static func _readable(path: String) -> bool:
	var c := _consts(path)
	var need := ["SWIPE_HITS", "SWIPE_CUES", "JUMP_HITS", "DASH_HITS", "DASH_LUNGE"] if path == DECREPIT 		else ["SWIPE_HITS", "SWIPE_CUES", "SWIPE_END", "SWIPE_CHAIN", "SWIPE2_HITS", "SWIPE2_CUES", "SWIPE2_END", "SWIPE2_LUNGE", "SWIPE2_CHAIN", "SWIPE1_LOOP_ENTRY", "BEAM_SET_EARLY", "RECOIL_BEAM"]
	for k in need:
		if not c.has(k):
			return false
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


## Element `index` of the (sorted) list constant `name`; `part` 0 / 1 for a
## hit window's start / end.
static func _bind_item(script: String, name: String, index: int, part := -1) -> Dictionary:
	return {"script": script, "const": name, "mode": &"at", "index": index, "part": part}


## A move's markers for its hit windows and cues: HIT n start / end, and each cue
## with how its window closes against the next blow's start (and whether a later
## cue replaces it first). `clock` puts clip seconds on the move's own clock.
func _hit_marks(script: String, k: String, hits: Array, cues: Array, listen: float, damage: int,
		clock: Callable, first_note := "") -> Array:
	var marks: Array = []
	for i in hits.size():
		var start_label := "HIT %d start (%d)" % [i + 1, damage]
		if i == 0 and first_note != "":
			start_label += " " + first_note
		marks.append([start_label, float(hits[i][0]), HIT, _bind_item(script, k + "_HITS", i, 0)])
		marks.append(["HIT %d end" % (i + 1), float(hits[i][1]), HIT, _bind_item(script, k + "_HITS", i, 1)])
	for i in cues.size():
		var cue_t: float = clock.call(float(cues[i]))
		var closes := cue_t + listen
		var next := -1
		for j in hits.size():
			if float(clock.call(float(hits[j][0]))) >= cue_t - 0.0001:
				next = j
				break
		var note := "no hit after it"
		var replaced := next >= 0 and i + 1 < cues.size() \
			and float(clock.call(float(cues[i + 1]))) <= float(clock.call(float(hits[next][0])))
		if replaced:
			note = "REPLACED by cue %d before HIT %d (no effect)" % [i + 2, next + 1]
		elif next >= 0:
			var h: float = clock.call(float(hits[next][0]))
			if absf(closes - h) < 0.004:
				note = "closes as HIT %d opens" % (next + 1)
			else:
				note = "closes %s %s HIT %d opens" % [_s(absf(closes - h)), "after" if closes > h else "BEFORE", next + 1]
		marks.append(["parry cue %d: listens %s, %s" % [i + 1, _s(listen), note], float(cues[i]), PARRY,
			_bind_item(script, k + "_CUES", i)])
	return marks


# --- The decrepit enforcer (scripts/decrepit.gd) ---------------------------------------

func _decrepit() -> Dictionary:
	_watch([DECREPIT])
	var c := _consts(DECREPIT)
	var out := {}
	for move in [["SWIPE", "SWIPE_BAKED", "SWIPE_DAMAGE"], ["JUMP", "JUMP_BAKED", "JUMP_DAMAGE"],
			["DROPKICK", "DROPKICK_BAKED", "DROPKICK_DAMAGE"], ["DASH", "DASH_BAKED", "DASH_DAMAGE"]]:
		var k: String = move[0]
		var clip := StringName(move[1])
		var hits := _sorted(c[k + "_HITS"] as Array, true)
		var cues := _sorted(c[k + "_CUES"] as Array, false)
		var listen: float = c[k + "_LISTEN"]
		var dash := k == "DASH"
		var lunge: float = c.get("DASH_LUNGE", 0.0)
		var slide: float = c.get("DASH_SLIDE_TIME", 0.0)
		var arrive: float = hits[0][0] if not hits.is_empty() else lunge
		# The move's own clock (the dash's clip runs slowed through its slide).
		var clock := func(x: float) -> float:
			if not dash or x <= lunge:
				return x
			var span := maxf(arrive - lunge, 0.0001)
			if x <= arrive:
				return lunge + (x - lunge) / span * slide
			return lunge + slide + (x - arrive)
		var marks := _hit_marks(DECREPIT, k, hits, cues, listen, int(c[move[2]]), clock,
			"arrives" if dash else ("(left-foot box)" if k == "DROPKICK" else ""))
		marks.append(["move ends (%s_END)" % k, float(c[k + "_END"]), END, _bind(DECREPIT, k + "_END")])
		if dash:
			marks.push_front(["lunge -> SLIDE (%s of slide to HIT 1)" % _s(slide), lunge, INFO,
				_bind(DECREPIT, "DASH_LUNGE")])
		out[clip] = marks
		_lists[clip] = {&"hit": _bind_item(DECREPIT, k + "_HITS", -1),
			&"parry": _bind_item(DECREPIT, k + "_CUES", -1)}
	return out


# --- The enforcer (scripts/enforcer.gd) ------------------------------------------------

func _enforcer() -> Dictionary:
	_watch([ENFORCER])
	var c := _consts(ENFORCER)
	var out := {}
	# The swipe, a move like the decrepit's (2026-10-17): its clip at 1x, its
	# hit windows (the shield's box), parry cues and end all clip seconds.
	var hits := _sorted(c["SWIPE_HITS"] as Array, true)
	var cues := _sorted(c["SWIPE_CUES"] as Array, false)
	var marks := _hit_marks(ENFORCER, "SWIPE", hits, cues, float(c["SWIPE_LISTEN"]),
		int(_init_value(ENFORCER, "attack_damage", 22.0)), func(x: float) -> float: return x)
	marks.append(["move ends, a blow connected (SWIPE_END)", float(c["SWIPE_END"]), END, _bind(ENFORCER, "SWIPE_END")])
	marks.append(["nothing connected: on into SWIPE 2 (SWIPE_CHAIN; not before the last HIT end)",
		float(c["SWIPE_CHAIN"]), INFO, _bind(ENFORCER, "SWIPE_CHAIN")])
	marks.append(["the loop comes back in here from SWIPE 2 (SWIPE1_LOOP_ENTRY)",
		float(c["SWIPE1_LOOP_ENTRY"]), INFO, _bind(ENFORCER, "SWIPE1_LOOP_ENTRY")])
	out[&"SWIPE_1_BAKED"] = marks
	_lists[&"SWIPE_1_BAKED"] = {&"hit": _bind_item(ENFORCER, "SWIPE_HITS", -1),
		&"parry": _bind_item(ENFORCER, "SWIPE_CUES", -1)}
	# Swipe 2, the loop's backhand: it dashes from the lunge, the clip from there
	# to HIT 1's start slowed to fill the slide (its length set by the distance:
	# the markers are clip times, a cue inside the slide moves with it).
	var hits2 := _sorted(c["SWIPE2_HITS"] as Array, true)
	var cues2 := _sorted(c["SWIPE2_CUES"] as Array, false)
	var marks2 := _hit_marks(ENFORCER, "SWIPE2", hits2, cues2, float(c["SWIPE2_LISTEN"]),
		int(_init_value(ENFORCER, "attack_damage", 22.0)), func(x: float) -> float: return x, "the slide arrives")
	marks2.push_front(["lunge -> DASH (slides until HIT 1)", float(c["SWIPE2_LUNGE"]), INFO,
		_bind(ENFORCER, "SWIPE2_LUNGE")])
	marks2.append(["nothing connected: on into SWIPE 1 (SWIPE2_CHAIN; not before the last HIT end)",
		float(c["SWIPE2_CHAIN"]), INFO, _bind(ENFORCER, "SWIPE2_CHAIN")])
	marks2.append(["move ends, a blow connected (SWIPE2_END)", float(c["SWIPE2_END"]), END,
		_bind(ENFORCER, "SWIPE2_END")])
	out[&"SWIPE_2_BAKED"] = marks2
	_lists[&"SWIPE_2_BAKED"] = {&"hit": _bind_item(ENFORCER, "SWIPE2_HITS", -1),
		&"parry": _bind_item(ENFORCER, "SWIPE2_CUES", -1)}
	# The charge plays BEAM_BAKED at 1x up to where it settles.
	var beam := _clip_length(&"BEAM_BAKED")
	out[&"BEAM_BAKED"] = [
		["settled: the recoil starts (charge %s)" % _s(beam - float(c["BEAM_SET_EARLY"])), beam - float(c["BEAM_SET_EARLY"]), INFO,
			_bind(ENFORCER, "BEAM_SET_EARLY", &"before")],
		["cannon up (f37)", 37.0 / 60.0, INFO],
	]
	# The recoil plays once; the beam comes on at its kick, then the clip holds
	# its last frame while the beam lasts.
	out[&"BEAM_RECOIL_BAKED"] = [
		["BEAM ON: the kick (fires %s, then vent %s)" % [_s(float(c["BEAM_TIME"])), _s(float(c["VENT_TIME"]))],
			float(c["RECOIL_BEAM"]), HIT, _bind(ENFORCER, "RECOIL_BEAM", &"at", null, true)],
	]
	return out


## A value an enemy sets in its `_init` ("windup_time = 0.6"), read off the
## source: those never reach an inspector.
static func _init_value(path: String, prop: String, fallback: float) -> float:
	var src := FileAccess.get_file_as_string(path)
	var rx := RegEx.create_from_string("(?m)^\\t" + prop + " = ([0-9.]+)")
	var m := rx.search(src)
	return float(m.get_string(1)) if m != null else fallback
