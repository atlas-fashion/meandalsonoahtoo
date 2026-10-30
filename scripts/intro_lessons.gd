extends Node

## The intro's lessons (note 131): searching the ruins of Vardia, the player is
## taught every control, one at a time, each watched for in the player's own
## state (no fake buttons): looking, walking, jumping, using things, the pack and
## the map, the sword's three attacks, the weapon wheel, the spear's and the
## axe's, ghost mode, blocking and parrying the sentinel, putting it down, and
## drinking from the quick wheel. Then the altar, and `finished`.
##
## A card at the top of each player's view says what to do and with which key
## (the pad's when that player last used one). Co-op: a lesson moves on once
## every player has done it; whoever has waits.

signal finished
## A lesson began (its id): the director narrates some of them.
signal lesson_started(id: StringName)

const Subtitles := preload("res://scripts/subtitles.gd")

var world: Node3D
var sentinel: CharacterBody3D

## Each: {id, title, kb, pad}. The checks are in `_done_now`.
var LESSONS: Array[Dictionary] = [
	{"id": &"look", "title": "Look around", "kb": "Move the [k]MOUSE[/k] to look around.", "pad": "Tilt the [k]RIGHT STICK[/k] to look around."},
	{"id": &"walk", "title": "Walk up to the gate", "kb": "[k]W A S D[/k] to walk.", "pad": "The [k]LEFT STICK[/k] to walk."},
	{"id": &"jump", "title": "Jump the fallen trunk", "kb": "[k]SPACE[/k] to jump.", "pad": "[k]A[/k] to jump."},
	{"id": &"read", "title": "Read the standing stone", "kb": "Look at it and press [k]E[/k]. E uses anything: doors, chests, ladders.", "pad": "Look at it and press [k]X[/k]. X uses anything: doors, chests, ladders."},
	{"id": &"pack", "title": "Check your pack", "kb": "[k]TAB[/k] opens your inventory. Close it again.", "pad": "[k]Y[/k] opens your inventory. Close it again."},
	{"id": &"map", "title": "Look at your map", "kb": "[k]M[/k] opens your map. It fills in as you explore. Close it again.", "pad": "[k]SELECT[/k] opens your map. It fills in as you explore. Close it again."},
	{"id": &"cut", "title": "Strike a training post  ·  3 times", "kb": "[k]LEFT CLICK[/k] swings your sword.", "pad": "[k]RB[/k] swings your sword."},
	{"id": &"spin", "title": "Spin", "kb": "[k]Q[/k] spins the blade in a full circle.", "pad": "[k]RT[/k] spins the blade in a full circle."},
	{"id": &"slam", "title": "Slam", "kb": "[k]F[/k] brings the blade down hard. In the air, it dives.", "pad": "[k]LT[/k] brings the blade down hard. In the air, it dives."},
	{"id": &"to_spear", "title": "Take up the spear", "kb": "Hold [k]C[/k], point at the spear, let go.", "pad": "Hold [k]R3[/k], point at the spear with the stick, let go."},
	{"id": &"stab", "title": "Stab a post  ·  3 times", "kb": "[k]LEFT CLICK[/k] stabs.", "pad": "[k]RB[/k] stabs."},
	{"id": &"dash", "title": "Spear dash", "kb": "[k]Q[/k] charges forward with the spear braced.", "pad": "[k]RT[/k] charges forward with the spear braced."},
	{"id": &"throw", "title": "Throw the spear", "kb": "[k]F[/k] hurls it. It bursts where it strikes and comes back.", "pad": "[k]LT[/k] hurls it. It bursts where it strikes and comes back."},
	{"id": &"to_axe", "title": "Take up the axe", "kb": "Hold [k]C[/k], point at the axe, let go.", "pad": "Hold [k]R3[/k], point at the axe, let go."},
	{"id": &"chop", "title": "Chop a post", "kb": "[k]LEFT CLICK[/k]: slow, and very heavy.", "pad": "[k]RB[/k]: slow, and very heavy."},
	{"id": &"axe_throw", "title": "Throw the axe", "kb": "[k]Q[/k] throws it end over end. It comes back.", "pad": "[k]RT[/k] throws it end over end. It comes back."},
	{"id": &"berserk", "title": "Berserk", "kb": "[k]F[/k]: a roar, then seconds of speed and fury that heal you.", "pad": "[k]LT[/k]: a roar, then seconds of speed and fury that heal you."},
	{"id": &"to_sword", "title": "Back to the sword", "kb": "Hold [k]C[/k], point at the sword, let go.", "pad": "Hold [k]R3[/k], point at the sword, let go."},
	{"id": &"ghost", "title": "Ghost", "kb": "Hold [k]SHIFT[/k] to slip into ghost form: fast, and hard to hurt. It runs out; let it refill.", "pad": "Hold [k]L3[/k] to slip into ghost form: fast, and hard to hurt. It runs out; let it refill."},
	{"id": &"block", "title": "Block  ·  2 blows", "kb": "Hold [k]RIGHT CLICK[/k] to raise your guard as its glaive comes down.", "pad": "Hold [k]LB[/k] to raise your guard as its glaive comes down."},
	{"id": &"parry", "title": "Parry", "kb": "Tap [k]RIGHT CLICK[/k] the moment its glaive flashes. A parry throws it back.", "pad": "Tap [k]LB[/k] the moment its glaive flashes. A parry throws it back."},
	{"id": &"fell", "title": "Bring it down", "kb": "Anything you have learned.", "pad": "Anything you have learned."},
	{"id": &"drink", "title": "Drink a potion", "kb": "Hold [k]X[/k], point at the potion, let go.", "pad": "Press the [k]D-PAD[/k] toward the potion."},
	{"id": &"altar", "title": "The altar", "kb": "Something here answers the handle.", "pad": "Something here answers the handle."},
]

var index := -1
## Per player: {card, title, body, header, done, track...}.
var _per := {}
var _prompt: Interact.Prompt
var _lesson_start := 0.0


func begin(players: Array[Node]) -> void:
	for p in players:
		_per[p] = {"track": {}}
		_build_card(p)
		if p.has_signal("guarded"):
			p.connect("guarded", _on_guarded)
	_prompt = Interact.prompt("E   Read", Vector3(0, 1.0, 0.4))
	world.get("inscription").add_child(_prompt)
	_next()


func _on_guarded(was_parry: bool, attacker: Node3D) -> void:
	if attacker == sentinel and sentinel != null:
		sentinel.call("on_guarded", was_parry)


# --- The card --------------------------------------------------------------------

func _build_card(p: Node) -> void:
	var layer := CanvasLayer.new()
	layer.name = "IntroLesson"
	layer.layer = 15
	Coop.ui_root(p).add_child(layer)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.035, 0.72)
	sb.border_color = Color(0.78, 0.62, 0.34, 0.55)
	sb.border_width_bottom = 2
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = 22
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var header := Label.new()
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.78, 0.64, 0.4))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(header)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("normal_font_size", 18)
	body.add_theme_font_size_override("bold_font_size", 18)
	body.add_theme_color_override("default_color", Color(0.82, 0.8, 0.76))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body)
	var foot := Label.new()
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color(0.6, 0.58, 0.54))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(foot)
	_per[p]["layer"] = layer
	_per[p]["panel"] = panel
	_per[p]["header"] = header
	_per[p]["title"] = title
	_per[p]["body"] = body
	_per[p]["foot"] = foot


func _fill(p: Node) -> void:
	var e: Dictionary = _per[p]
	var l: Dictionary = LESSONS[index]
	var pad := Coop.on_pad(p)
	e["pad_shown"] = pad
	(e["header"] as Label).text = "VARDIA   ·   %d / %d" % [index + 1, LESSONS.size()]
	(e["title"] as Label).text = String(l["title"])
	var text := String(l["pad"] if pad else l["kb"])
	text = text.replace("[k]", "[b][color=#e8c37a]").replace("[/k]", "[/color][/b]")
	(e["body"] as RichTextLabel).text = "[center]" + text + "[/center]"
	(e["foot"] as Label).text = ("Start pauses" if pad else "Esc pauses") if index == 0 else ""
	(e["title"] as Label).add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))


func _show_done(p: Node) -> void:
	var e: Dictionary = _per[p]
	(e["title"] as Label).add_theme_color_override("font_color", Color(0.92, 0.78, 0.45))
	(e["title"] as Label).text = "✓   " + String(LESSONS[index]["title"])
	if Coop.count() > 1:
		(e["foot"] as Label).text = "Waiting for your companion..."


func set_visible(on: bool) -> void:
	for p in _per:
		var layer: CanvasLayer = _per[p].get("layer")
		if layer != null:
			layer.visible = on


func close() -> void:
	for p in _per:
		var layer: CanvasLayer = _per[p].get("layer")
		if layer != null and is_instance_valid(layer):
			layer.queue_free()
	if _prompt != null and is_instance_valid(_prompt):
		_prompt.queue_free()


# --- Running ---------------------------------------------------------------------

var _advancing := false


func _next() -> void:
	index += 1
	if index >= LESSONS.size():
		finished.emit()
		return
	_lesson_start = Time.get_ticks_msec() / 1000.0
	for p in _per:
		_per[p]["done"] = false
		_per[p]["track"] = _fresh_track(p)
		_fill(p)
	var id: StringName = LESSONS[index]["id"]
	_setup(id)
	lesson_started.emit(id)


func _fresh_track(p: Node) -> Dictionary:
	var posts_hits := {}
	for post in world.get("posts"):
		var h: Dictionary = post.get("hits")
		for k in h:
			posts_hits[k] = int(posts_hits.get(k, 0)) + int(h[k])
	var spear = p.get("spear")
	return {"yaw": (p as Node3D).rotation.y, "pitch": float(p.get("_look_pitch")), "looked": 0.0,
		"air_at": -INF, "opened": false, "map_opened": false, "spin": false, "slam": false,
		"hits0": posts_hits, "dash0": float(spear.get("_dash_until")) if spear != null else 0.0,
		"ghost_t": 0.0, "drank": false}


func _setup(id: StringName) -> void:
	match id:
		&"fell":
			if sentinel != null:
				sentinel.set("mortal", true)
		&"drink":
			# Hurt, so there is something to drink for (the sentinel's last blow).
			for p in _per:
				var mx := float(p.get("max_health"))
				if float(p.get("health")) > mx * 0.7:
					p.set("health", mx * 0.6)
					p.emit_signal("health_changed", mx * 0.6, mx)


func _physics_process(delta: float) -> void:
	if index < 0 or index >= LESSONS.size() or _advancing:
		return
	_update_prompt()
	var all := true
	for p in _per:
		if not is_instance_valid(p):
			continue
		var e: Dictionary = _per[p]
		if Coop.on_pad(p) != bool(e.get("pad_shown", false)) and not e["done"]:
			_fill(p)
		if not e["done"] and _done_now(p, e["track"], delta):
			e["done"] = true
			_show_done(p)
		all = all and bool(e["done"])
	if all:
		_advance()


func _advance() -> void:
	_advancing = true
	await get_tree().create_timer(0.9, false).timeout
	_advancing = false
	_next()


## Whether player `p` has done the current lesson (`t` is its tracking).
func _done_now(p: Node, t: Dictionary, delta: float) -> bool:
	var id: StringName = LESSONS[index]["id"]
	var n := p as Node3D
	if p.get("in_cutscene") == true:
		return false
	match id:
		&"look":
			var yaw := n.rotation.y
			var pitch := float(p.get("_look_pitch"))
			t["looked"] = float(t["looked"]) + absf(wrapf(yaw - float(t["yaw"]), -PI, PI)) + absf(pitch - float(t["pitch"]))
			t["yaw"] = yaw
			t["pitch"] = pitch
			return float(t["looked"]) > 2.4
		&"walk":
			return n.global_position.distance_to(world.call("at", &"gate")) < 3.6
		&"jump":
			if not (n as CharacterBody3D).is_on_floor():
				t["air_at"] = Time.get_ticks_msec() / 1000.0
			var local: Vector3 = world.to_local(n.global_position)
			var crossed := local.z > float(world.get("marks")["log_z"]) + 0.7
			return crossed and Time.get_ticks_msec() / 1000.0 - float(t["air_at"]) < 3.0
		&"read":
			return bool(t.get("read", false))
		&"pack":
			var inv = _inv(p)
			if inv != null and inv.call("is_open") and inv.call("page") != &"map":
				t["opened"] = true
			return bool(t["opened"]) and inv != null and not inv.call("is_open")
		&"map":
			var inv = _inv(p)
			if inv != null and inv.call("is_open") and inv.call("page") == &"map":
				t["map_opened"] = true
			return bool(t["map_opened"]) and inv != null and not inv.call("is_open")
		&"cut":
			return _hits_since(t, &"sword") >= 3
		&"spin":
			return p.get("_pose_kind") == &"spin"
		&"slam":
			return p.get("_slamming") == true or p.get("_pose_kind") == &"slam"
		&"to_spear":
			return p.call("held_item") == &"spear"
		&"stab":
			return _hits_since(t, &"spear") >= 3
		&"dash":
			var spear = p.get("spear")
			return spear != null and float(spear.get("_dash_until")) > float(t["dash0"]) + 0.01
		&"throw":
			var spear = p.get("spear")
			return spear != null and bool(spear.call("is_away"))
		&"to_axe":
			var spear = p.get("spear")
			return p.call("held_item") == &"axe" and (spear == null or not bool(spear.call("is_away")))
		&"chop":
			return _hits_since(t, &"axe") >= 1
		&"axe_throw":
			var axe = p.get("axe")
			return axe != null and bool(axe.call("is_away"))
		&"berserk":
			var axe = p.get("axe")
			return axe != null and (bool(axe.call("is_berserk")) or bool(axe.call("is_roaring")))
		&"to_sword":
			var axe = p.get("axe")
			return p.call("held_item") == &"sword" and (axe == null or not bool(axe.call("is_away")))
		&"ghost":
			if p.get("_ghosting") == true:
				t["ghost_t"] = float(t["ghost_t"]) + delta
			return float(t["ghost_t"]) > 0.7
		&"block":
			return sentinel != null and int(sentinel.get("blocked")) + int(sentinel.get("parried")) >= 2
		&"parry":
			return sentinel != null and int(sentinel.get("parried")) >= 1
		&"fell":
			return sentinel == null or int(sentinel.get("state")) == 4
		&"drink":
			if p.has_method("is_drinking") and bool(p.call("is_drinking")):
				t["drank"] = true
			return bool(t["drank"])
		&"altar":
			return n.global_position.distance_to(world.call("at", &"altar")) < 2.6
	return false


func _inv(p: Node):
	var hud := Coop.hud(p)
	return hud.get("_inventory_screen") if hud != null else null


## Blows on the posts with `weapon` since the lesson began.
func _hits_since(t: Dictionary, weapon: StringName) -> int:
	var now := 0
	for post in world.get("posts"):
		now += int((post.get("hits") as Dictionary).get(weapon, 0))
	return now - int((t["hits0"] as Dictionary).get(weapon, 0))


# --- The standing stone -------------------------------------------------------------

var _reading := false


func _update_prompt() -> void:
	if _prompt == null:
		return
	var reading_lesson: bool = index >= 0 and LESSONS[index]["id"] == &"read"
	var who: Node = Interact.chooser(world.get("inscription"), 2.8, 2.0, 3.6) if reading_lesson and not _reading else null
	_prompt.visible = who != null
	_prompt.player = who


func _unhandled_input(event: InputEvent) -> void:
	if _prompt == null or not _prompt.visible or _reading:
		return
	var who: Node = _prompt.player
	if who == null or not Interact.pressed(event, who):
		return
	get_viewport().set_input_as_handled()
	_read(who)


func _read(_who: Node) -> void:
	_reading = true
	_prompt.visible = false
	var sub := Subtitles.open(self)
	await sub.say("THE STONE", "Here the people of Vardia kept the Hollow Flame.", 0.035, 1.4)
	await sub.say("THE STONE", "No hand but the Crown's may bear it. Whoever takes it from this place takes the Crown's enemies with it.", 0.03, 2.2)
	sub.call("close")
	_reading = false
	# Co-op: one reading is heard by everyone (`who` read it aloud).
	for p in _per:
		(_per[p]["track"] as Dictionary)["read"] = true
