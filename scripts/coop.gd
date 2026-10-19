extends Node

## LOCAL CO-OP SPLIT-SCREEN (autoload `Coop`, 2026-10-18). Two players in the
## same dungeon on one screen, side by side: PLAYER 1 (index 0, the left half)
## on keyboard and mouse, PLAYER 2 (index 1, the right half) on a controller.
## Started from the title's Co-op button (title_screen.gd); off, everything is
## exactly the one-player game, and every helper here answers as it always did.
##
## What this owns:
##   * who is playing -- `players` (registered by player.gd, in index order),
##     `player(i)`, `nearest(pos)` for whatever hunts or watches them;
##   * whose input an event is -- `owns(p, event)`: keys and the mouse are
##     player 1's, joypad buttons and sticks player 2's. Event-driven code
##     (`_input` / `_unhandled_input`) for a player asks this first and leaves
##     the rest alone;
##   * POLLED input per player -- `start` splits every game action A into
##     "p1_A" (its keyboard / mouse events) and "p2_A" (its joypad events),
##     and `act(p, A)` / `held` / `just_pressed` / `vector` read the right one.
##     The originals stay as they were (both devices), for menus and for the
##     event-driven code behind `owns`. The ui_* actions are not split;
##   * the mouse -- only player 1 may capture or free it (`set_mouse`), and
##     only player 1 needs it captured to attack (`aim_ready`);
##   * where a player's screens go -- `ui_root(p)` (their half's viewport in
##     co-op), their HUD (`hud(p)`, `huds()`), and the camera that draws their
##     half (`camera(p)`), from split_screen.gd.

signal players_changed

## In a co-op session.
var active := false
## The players, by index (player.gd registers itself).
var players: Array[Node] = []
## split_screen.gd, while one is up.
var split: Node = null

## An InputEventAction a test builds for player 2 carries this device.
const ACTION_DEVICE_P2 := 99
const PREFIX := ["p1_", "p2_"]

var _split_actions: Array[StringName] = []


## Into co-op: the actions split by device (see above). Idempotent.
func start() -> void:
	active = true
	_split_input()


## Out of it (the title, a one-player game): the actions as the project has
## them, no split screen.
func stop() -> void:
	active = false
	for a in _split_actions:
		if InputMap.has_action(a):
			InputMap.erase_action(a)
	_split_actions.clear()
	split = null


func _split_input() -> void:
	if not _split_actions.is_empty():
		return
	for action in InputMap.get_actions():
		var name_ := String(action)
		if name_.begins_with("ui_") or name_.begins_with("p1_") or name_.begins_with("p2_"):
			continue
		var dz := InputMap.action_get_deadzone(action)
		for i in 2:
			var copy := StringName(PREFIX[i] + name_)
			InputMap.add_action(copy, dz)
			_split_actions.append(copy)
			for e in InputMap.action_get_events(action):
				var pad := e is InputEventJoypadButton or e is InputEventJoypadMotion
				if pad == (i == 1):
					InputMap.action_add_event(copy, e)


# --- The players --------------------------------------------------------------------

func register(p: Node) -> void:
	if not players.has(p):
		players.append(p)
		players.sort_custom(func(a, b): return int(a.get("player_index")) < int(b.get("player_index")))
		players_changed.emit()


func unregister(p: Node) -> void:
	if players.has(p):
		players.erase(p)
		players_changed.emit()


func count() -> int:
	return players.size()


## Player `i` (0 or 1), or null.
func player(i: int) -> Node:
	for p in players:
		if is_instance_valid(p) and int(p.get("player_index")) == i:
			return p
	return null


func index_of(p: Node) -> int:
	return int(p.get("player_index")) if p != null and is_instance_valid(p) else 0


## Every player there is (one outside co-op).
func all() -> Array[Node]:
	var out: Array[Node] = []
	for p in players:
		if is_instance_valid(p):
			out.append(p)
	return out


## The player nearest `pos` -- standing (not dead), and by default not shut in
## a hiding place either; falls back to any player, then null.
func nearest(pos: Vector3, skip_hidden := true) -> Node:
	var best: Node = null
	var best_d := INF
	for p in players:
		if not is_instance_valid(p) or p.get("_dead") == true:
			continue
		if skip_hidden and p.has_method("is_hidden") and p.is_hidden():
			continue
		var d := (p as Node3D).global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = p
	if best == null:
		for p in players:
			if is_instance_valid(p):
				return p
	return best


## The player who is to use `node` -- a chest, a door, a cage, a hazard:
## `current` while they are in the middle of a scene with it (or shut in it),
## else the nearest player standing. Outside co-op, the one player.
func user_for(node: Node3D, current: Node = null) -> Node3D:
	if current != null and is_instance_valid(current):
		if current.get("in_cutscene") == true:
			return current as Node3D
		if current.has_method("hidden_in") and current.call("hidden_in") == node:
			return current as Node3D
	return nearest(node.global_position, false) as Node3D


## The nearest of any player to `pos`, dead or hidden or not (for culling and
## other things about where the cameras are).
func nearest_any(pos: Vector3) -> Node:
	var best: Node = null
	var best_d := INF
	for p in players:
		if not is_instance_valid(p):
			continue
		var d := (p as Node3D).global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = p
	return best


## Flat distance from `pos` to the nearest player (INF with none).
func nearest_distance(pos: Vector3) -> float:
	var p := nearest_any(pos)
	return INF if p == null else (p as Node3D).global_position.distance_to(pos)


# --- Input ---------------------------------------------------------------------------

## Whether `event` is `p`'s to act on. Always, outside co-op.
func owns(p: Node, event: InputEvent) -> bool:
	if not active:
		return true
	return index_of(p) == device_player(event)


## Which player an event belongs to (0 or 1); 0 outside co-op.
func device_player(event: InputEvent) -> int:
	if not active:
		return 0
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return 1
	# The pad cursor's made-up mouse (pad.gd) is player 2's.
	if event is InputEventMouse and event.device == Pad.SYNTH_DEVICE:
		return 1
	if event is InputEventAction:
		return 1 if event.device == ACTION_DEVICE_P2 else 0
	return 0


## The player an event belongs to.
func player_of(event: InputEvent) -> Node:
	return player(device_player(event)) if active else (players[0] if not players.is_empty() else null)


## The polled action for `p`.
func act(p: Node, action: StringName) -> StringName:
	if not active:
		return action
	return StringName(PREFIX[clampi(index_of(p), 0, 1)] + String(action))


func held(p: Node, action: StringName) -> bool:
	return Input.is_action_pressed(act(p, action))


func just_pressed(p: Node, action: StringName) -> bool:
	return Input.is_action_just_pressed(act(p, action))


func vector(p: Node, neg_x: StringName, pos_x: StringName, neg_y: StringName, pos_y: StringName) -> Vector2:
	return Input.get_vector(act(p, neg_x), act(p, pos_x), act(p, neg_y), act(p, pos_y))


func axis(p: Node, neg: StringName, pos: StringName) -> float:
	return Input.get_axis(act(p, neg), act(p, pos))


## Whether `p` uses a controller (player 2 in co-op; outside it, the HUD
## decides by what was touched last).
func on_pad(p: Node) -> bool:
	return active and index_of(p) == 1


# --- The mouse -----------------------------------------------------------------------

## Captures or frees the mouse for `p` -- only player 1's say counts in co-op.
func set_mouse(p: Node, mode: Input.MouseMode) -> void:
	if not active or index_of(p) == 0:
		Input.mouse_mode = mode


## Whether `p`'s attack keys may attack now: player 1 needs the mouse captured
## (a click with it free takes it back); a controller always may.
func aim_ready(p: Node) -> bool:
	if active and index_of(p) == 1:
		return true
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


# --- Where things go -----------------------------------------------------------------

## The node a full-screen panel of `p`'s (the workbench, the sandbox menu, the
## rat's-eye overlay) goes under: their half of the screen in co-op.
func ui_root(p: Node) -> Node:
	if active and split != null and is_instance_valid(split) and p != null:
		var v = split.call("view_of", p)
		if v != null:
			return v
	return get_tree().root


## The camera `p` looks along -- their own (the head's), for aiming and
## "looked at" tests.
func camera(p: Node) -> Camera3D:
	return p.get("camera") as Camera3D if p != null else null


## The camera that DRAWS `p`'s view: co-op, their half's (split_screen.gd),
## which carries that half's own Environment and its shape for frustum tests.
func view_camera(p: Node) -> Camera3D:
	if active and split != null and is_instance_valid(split) and p != null:
		var c = split.call("camera_of", p)
		if c != null:
			return c
	return p.get("camera") as Camera3D if p != null else null


## `p`'s HUD.
func hud(p: Node) -> Node:
	for h in get_tree().get_nodes_in_group(&"hud"):
		if h.get("player") == p:
			return h
	return get_tree().get_first_node_in_group(&"hud")


## Every HUD there is (one outside co-op).
func huds() -> Array[Node]:
	var out: Array[Node] = []
	for h in get_tree().get_nodes_in_group(&"hud"):
		out.append(h)
	return out


## Announces to everyone: a zone, the boss falling.
func announce_all(title: String, subtitle := "") -> void:
	for h in huds():
		if h.has_method("announce"):
			h.call("announce", title, subtitle)


## Announces to `p` alone (their pickups, their workbench).
func announce(p: Node, title: String, subtitle := "") -> void:
	var h := hud(p)
	if h != null and h.has_method("announce"):
		h.call("announce", title, subtitle)
