extends Node3D

## A haul convoy (2026-10-09): skeletons moving a wheelbarrow cart of gold
## coins and red and gold crystals through the corridors -- from a refinery to
## a consolidator, by the lore, though neither exists yet -- with an enforcer
## (enforcer.gd) walking behind. Spawned by maze.gd (`_spawn_convoys`) on every
## repopulate, already on the move.
##
## THE ROUTE never goes near a dead end: the corridor graph (`network`) is cut
## down to its loops -- every cell with fewer than two ways on is removed, again
## and again, until none is left (the graph's 2-core). Rooms and shut doors are
## not part of it. A shortest path between two loop cells never steps off the
## loops, so it never enters a branch that ends. Legs are BFS paths of 8-26
## cells to a random loop cell, never turning back the way it came; a new leg
## is joined on 14 m before the old one ends, so the convoy never stops at a
## corner, and at the end of each leg it may stand a few seconds.
##
## THE CREW are real skeletons (enemy.tscn) with `hauled_by` set: no AI of
## their own, placed and posed by the convoy each tick (enemy.gd calls
## `pose_hauler`). One PUSHES at the handles, one PULLS on a rope in front, one
## STEADIES the load at the side. The enforcer escorts a marker 4.6 m behind the
## cart.
##
## SET UPON -- the player seen in front of the puller or close to any of them,
## any of them hurt or alerted, the enforcer engaged -- they let go and fight as
## ordinary enemies; the cart stays where it stopped, and E on it takes the load.

const MM := preload("res://scripts/module_maze.gd")
const SPEED := 1.0
const ACCEL := 0.9
## Distances along the route from the cart's centre, and to the side (+right).
const PUSH_AT := -1.9
const PULL_AT := 2.5
const STEADY_AT := -0.1
const STEADY_SIDE := 0.85
const ENFORCER_AT := -4.6
## Joined on before the route runs out; trimmed this far behind the marker.
const LOOK_AHEAD := 14.0
const KEEP_BEHIND := 12.0
## The player is noticed this close to any of them, or this far in front of the
## puller (in its cone, with a clear line).
const NOTICE_NEAR := 4.0
const NOTICE_FAR := 16.0
const NOTICE_CONE := 1.2
const WHEEL_R := 0.33
## The wheel's axle, ahead of the cart's centre.
const WHEEL_AHEAD := 0.95
## How far ahead of the cart's centre the steadier goes to cross in front of
## the wheel (wheel 0.95 + tyre 0.33 + its own body 0.35, and a little).
const STEADY_CROSS := 1.8
## In line behind the pusher (who walks 1.9 m behind the cart's centre), when
## neither side has room.
const STEADY_BEHIND := -2.75
## A convoy waits while another's cart is this close ahead of it.
const GIVE_WAY := 8.0
## The steadier looks for room only within this of the player.
const STEADY_CARE := 40.0
## The cart is not drawn further off than this.
const CART_SEEN := 50.0
## Further than this from the player a convoy moves in steps of FAR_STEP s.
const FAR_STEP_FROM := 60.0
const FAR_STEP := 0.1
var _far_debt := 0.0

var maze: Node
var built
var net: Dictionary = {}

var broken := false
var looted := false
var crew: Array[Dictionary] = []
var enforcer: Node3D

var _rng := RandomNumberGenerator.new()
## The cells the route runs through, and the smoothed polyline over them.
var _cells: Array[Vector2i] = []
var _pts: PackedVector3Array = PackedVector3Array()
var _len: PackedFloat32Array = PackedFloat32Array()
var _s := 6.0
var _speed := 0.0
var _pause_until := 0.0
var _stops: Array[float] = []
var _next_check := 0.0
var _player: Node3D

var _cart: AnimatableBody3D
var _wheel: Node3D
var _load: Node3D
var _rope: MeshInstance3D
var _marker: Node3D
var _prompt: Interact.Prompt
var _focus := false
## The steadier's place in the cart's frame: across (+right) and ahead.
var _steady_x := STEADY_SIDE
var _steady_z := STEADY_AT
var _steady_want := 1.0
var _next_side_check := 0.0

static var _mats := {}


# --- The network ------------------------------------------------------------------

## The corridor cells that lie on loops, and how they join: {cells: Array of
## Vector2i, adj: Dictionary Vector2i -> Array of Vector2i}.
static func network(level) -> Dictionary:
	var shut := {}
	for door in level.doors:
		var a: Vector2i = door["cell"]
		var b: Vector2i = door["other"]
		shut[Vector4i(a.x, a.y, b.x, b.y)] = true
		shut[Vector4i(b.x, b.y, a.x, a.y)] = true
	var adj := {}
	for key: Vector2i in level.cells:
		var cell = level.cells[key]
		if cell.room >= 0 or cell.court:
			continue
		var ways: Array = []
		for side: int in MM.ORDER:
			if not (cell.open & side):
				continue
			var to: Vector2i = key + MM.DIRS[side]
			var other = level.cells.get(to)
			if other == null or other.room >= 0 or other.court or shut.has(Vector4i(key.x, key.y, to.x, to.y)):
				continue
			ways.append(to)
		adj[key] = ways
	# Peel off every cell with fewer than two ways on until none is left: what
	# remains is the loops. Dead ends, and every corridor that only leads to one,
	# are gone.
	var gone := true
	while gone:
		gone = false
		for key in adj.keys():
			if (adj[key] as Array).size() < 2:
				for to in adj[key]:
					if adj.has(to):
						(adj[to] as Array).erase(key)
				adj.erase(key)
				gone = true
	# Rooms and shut doors can split what is left into separate pieces; a
	# convoy started on a small one had nowhere to go (two seeds of four: a
	# loop of a few cells, no cell 8 away). Only the largest piece is kept.
	var seen := {}
	var best: Array = []
	for key in adj:
		if seen.has(key):
			continue
		var part: Array = [key]
		seen[key] = true
		var i := 0
		while i < part.size():
			for to in adj[part[i]]:
				if not seen.has(to):
					seen[to] = true
					part.append(to)
			i += 1
		if part.size() > best.size():
			best = part
	var keep := {}
	for key in best:
		keep[key] = true
	for key in adj.keys():
		if not keep.has(key):
			adj.erase(key)
	return {"cells": adj.keys(), "adj": adj}


## The road other convoys have claimed: no leg is planned through it, so two
## never meet head on in a corridor.
func _others_claims() -> Dictionary:
	var out := {}
	for other in maze.get("_convoys"):
		if other == self or not is_instance_valid(other):
			continue
		out.merge(other.call("claimed"))
	return out


## From behind its enforcer to the end of its road (just its own cell once it has
## been dropped): the whole convoy and everywhere it is going.
func claimed() -> Dictionary:
	var out := {}
	if _cart == null:
		return out
	out[_cell_at(_cart.global_position)] = true
	if broken:
		return out
	var from_s := _s + ENFORCER_AT - 2.0
	for i in _cells.size():
		if _length_to_cell(i) >= from_s:
			out[_cells[i]] = true
	return out


func _cell_at(p: Vector3) -> Vector2i:
	var rel: Vector3 = (p - built.origin) / float(built.cell_size)
	return Vector2i(int(round(rel.x)), int(round(rel.z)))


## Cells from `from` to a random loop cell 8-26 cells away, never stepping back
## onto `behind`, and keeping off other convoys' road if it can. Empty if there
## is none.
func _leg(from: Vector2i, behind: Vector2i, strict := true) -> Array[Vector2i]:
	var path := _leg_avoiding(from, behind, _others_claims())
	if path.is_empty() and not strict:
		path = _leg_avoiding(from, behind, {})
	return path


func _leg_avoiding(from: Vector2i, behind: Vector2i, blocked: Dictionary) -> Array[Vector2i]:
	var adj: Dictionary = net["adj"]
	var came := {from: from}
	var depth := {from: 0}
	var queue: Array[Vector2i] = [from]
	var head := 0
	var pool: Array[Vector2i] = []
	var near: Array[Vector2i] = []
	while head < queue.size():
		var at: Vector2i = queue[head]
		head += 1
		if int(depth[at]) >= 8:
			pool.append(at)
		elif int(depth[at]) >= 3:
			near.append(at)
		if int(depth[at]) >= 26:
			continue
		for to: Vector2i in adj.get(at, []):
			if came.has(to) or (at == from and to == behind) or blocked.has(to):
				continue
			came[to] = at
			depth[to] = int(depth[at]) + 1
			queue.append(to)
	var path: Array[Vector2i] = []
	if pool.is_empty():
		# Hemmed in by other convoys' road: a short hop if there is one.
		pool = near
	if pool.is_empty():
		return path
	var at: Vector2i = pool[_rng.randi_range(0, pool.size() - 1)]
	while at != from:
		path.push_front(at)
		at = came[at]
	return path


# --- Building -----------------------------------------------------------------------

## A convoy under way from `start`, or null if it has no road there that is
## clear of the others'.
static func spawn(maze_: Node, level, net_: Dictionary, start: Vector2i, seed_value: int) -> Node3D:
	var c := Node3D.new()
	c.set_script(load("res://scripts/convoy.gd"))
	c.name = "Convoy"
	c.set("maze", maze_)
	c.set("built", level)
	c.set("net", net_)
	maze_.add_child(c)
	if not c.call("_setup", start, seed_value):
		c.free()
		return null
	return c


func _setup(start: Vector2i, seed_value: int) -> bool:
	_rng.seed = seed_value
	# A first leg, and a second joined on, so there is road behind the crew as
	# well as in front of it: it starts already under way. Both clear of the
	# other convoys' road.
	if _others_claims().has(start):
		return false
	_cells = [start]
	var first := _leg(start, Vector2i(-9999, -9999))
	if first.size() < 3:
		return false
	_cells.append_array(first)
	_smooth()
	if not _extend():
		return false
	_smooth()
	_s = 6.0
	_speed = SPEED
	_build_cart()
	_marker = Node3D.new()
	_marker.name = "EnforcerMark"
	add_child(_marker)
	_place(0.0)
	_spawn_crew()
	_prompt = Interact.prompt("E   Loot")
	add_child(_prompt)
	_prompt.visible = false
	return true


func _spawn_crew() -> void:
	var scene: PackedScene = maze.get("enemy_scene")
	var members: Array[Node3D] = []
	for role: StringName in [&"push", &"pull", &"steady"]:
		var e: Node3D = scene.instantiate()
		e.set("wanders", false)
		maze.call("adopt_enemy", e)
		e.set("hauled_by", self)
		var entry := {"node": e, "role": role, "sk": null, "bones": {}}
		var found := e.find_children("*", "Skeleton3D", true, false)
		if not found.is_empty():
			var sk := found[0] as Skeleton3D
			entry["sk"] = sk
			for b: StringName in [&"upper_arm.L", &"forearm.L", &"hand.L", &"upper_arm.R", &"forearm.R", &"hand.R"]:
				entry["bones"][b] = sk.find_bone(b)
		crew.append(entry)
		members.append(e)
		(e as PhysicsBody3D).add_collision_exception_with(_cart)
	_place(0.0)
	var tile: Vector2i = maze.call("world_to_tile", _marker.global_position)
	enforcer = maze.call("_spawn_enforcer", tile, _marker, members)
	if enforcer != null:
		enforcer.set("wander_speed", 1.5)
		enforcer.set("pack", members)
		for m in members:
			(enforcer as PhysicsBody3D).add_collision_exception_with(m)
		(enforcer as PhysicsBody3D).add_collision_exception_with(_cart)


func _build_cart() -> void:
	_cart = AnimatableBody3D.new()
	_cart.name = "Cart"
	_cart.collision_layer = 1
	_cart.collision_mask = 0
	_cart.sync_to_physics = false
	add_child(_cart)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 0.95, 2.5)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0.0, 0.5, 0.2)
	_cart.add_child(cs)
	# Merged per rigid part and material, and shared by every cart: the body,
	# the wheel, the coins and the two kinds of crystal are five meshes (as ~28
	# separate pieces a cart cost ~30 draw calls wherever it was on screen).
	# The Tripo hand cart from the brick kit (2026-10-10), exported at this
	# cart's size: two wheels under the middle of the tray, spun on their axle.
	# Without the kit, the old primitive barrow.
	var kit_body: Mesh = BRICK.standalone("cart_body")
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = kit_body if kit_body != null else _shared(&"body", _fill_body)
	_cart.add_child(body)
	_wheel = Node3D.new()
	_wheel.position = Vector3(0.0, KIT_AXLE.y, KIT_AXLE.x) if kit_body != null \
		else Vector3(0.0, WHEEL_R, -WHEEL_AHEAD)
	_cart.add_child(_wheel)
	var wheel := MeshInstance3D.new()
	wheel.mesh = BRICK.standalone("cart_wheels") if kit_body != null else _shared(&"wheel", _fill_wheel)
	_wheel.add_child(wheel)
	# The load: a heap of coins with crystals standing out of it. Laid out by
	# this cart's own draw of the dice, so no two loads are alike.
	_load = Node3D.new()
	_load.name = "Load"
	# Sunk a little so the crystals sit under the lid (2026-10-10).
	_load.position.y = -LOAD_DROP
	_cart.add_child(_load)
	# A plank lid on hinges along the cart's left side, shut while it is hauled;
	# it is thrown open when the load is taken (`_unhandled_input`).
	_lid = Node3D.new()
	_lid.name = "Lid"
	_lid.position = Vector3(-LID_HALF, 0.955, 0.0) if kit_body != null else Vector3(-LID_HALF, 0.975, 0.05)
	_cart.add_child(_lid)
	var lid := MeshInstance3D.new()
	lid.mesh = BRICK.standalone("cart_lid") if kit_body != null else _shared(&"lid", _fill_lid)
	_lid.add_child(lid)
	var coins := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var coin := CylinderMesh.new()
	coin.top_radius = 0.04
	coin.bottom_radius = 0.04
	coin.height = 0.01
	coin.radial_segments = 10
	coin.rings = 1
	mm.mesh = coin
	mm.instance_count = 170
	for i in mm.instance_count:
		var x := _rng.randf_range(-0.34, 0.34)
		var z := _rng.randf_range(-0.48, 0.6)
		var top := 0.66 + 0.3 * maxf(0.0, 1.0 - pow(x / 0.4, 2.0) - pow((z - 0.06) / 0.62, 2.0))
		var y := _rng.randf_range(0.66, top)
		var b := Basis.from_euler(Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.0, TAU), _rng.randf_range(-0.6, 0.6)))
		mm.set_instance_transform(i, Transform3D(b, Vector3(x, y, z)))
	coins.multimesh = mm
	coins.material_override = _mat(&"coin")
	_load.add_child(coins)
	var gems := {&"red": SurfaceTool.new(), &"gold": SurfaceTool.new()}
	for key in gems:
		(gems[key] as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 8:
		var s := SphereMesh.new()
		s.radius = _rng.randf_range(0.06, 0.09)
		s.height = _rng.randf_range(0.2, 0.34)
		s.radial_segments = 4
		s.rings = 2
		var x := _rng.randf_range(-0.28, 0.28)
		var z := _rng.randf_range(-0.4, 0.5)
		var at := Vector3(x, 0.78 + 0.18 * maxf(0.0, 1.0 - pow(x / 0.4, 2.0) - pow(z / 0.6, 2.0)), z)
		var b := Basis.from_euler(Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(0.0, TAU), _rng.randf_range(-0.6, 0.6)))
		(gems[&"red" if k % 2 == 0 else &"gold"] as SurfaceTool).append_from(s, 0, Transform3D(b, at))
	for key: StringName in gems:
		var st: SurfaceTool = gems[key]
		st.generate_normals()
		var gem := MeshInstance3D.new()
		gem.mesh = st.commit()
		gem.material_override = _mat(key)
		_load.add_child(gem)
	# The puller's rope, from a ring at the front to its hand.
	_rope = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = 1.0
	cyl.radial_segments = 5
	cyl.rings = 1
	_rope.mesh = cyl
	_rope.material_override = _mat(&"rope")
	_rope.top_level = true
	add_child(_rope)
	for mi in find_children("*", "GeometryInstance3D", true, false):
		var g := mi as GeometryInstance3D
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# Nothing in these corridors is seen 50 m off.
		g.visibility_range_end = CART_SEEN
		g.visibility_range_end_margin = 4.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


static var _shared_meshes := {}


## A mesh made of primitives, one surface per material, built once.
static func _shared(key: StringName, fill: Callable) -> ArrayMesh:
	if _shared_meshes.has(key):
		return _shared_meshes[key]
	var tools := {}
	var add := func(mesh: PrimitiveMesh, xf: Transform3D, mat: Material) -> void:
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		(tools[mat] as SurfaceTool).append_from(mesh, 0, xf)
	fill.call(add)
	var am := ArrayMesh.new()
	for mat in tools:
		var st: SurfaceTool = tools[mat]
		st.generate_normals()
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, mat)
	_shared_meshes[key] = am
	return am


## The tray (a floor, sides leaning out, a front and a back board, iron rails),
## the handles from under the front out past the back, legs and the axle. -Z is
## the front, where the wheel is.
static func _fill_body(add: Callable) -> void:
	var wood := _mat(&"wood")
	var iron := _mat(&"iron")
	add.call(_bx(Vector3(0.8, 0.05, 1.15)), Transform3D(Basis(), Vector3(0.0, 0.62, 0.05)), wood)
	for side: float in [-1.0, 1.0]:
		add.call(_bx(Vector3(0.04, 0.34, 1.22)), Transform3D(Basis(Vector3.FORWARD, 0.28 * side),
			Vector3(0.43 * side, 0.79, 0.05)), wood)
		add.call(_bx(Vector3(0.05, 0.05, 1.24)), Transform3D(Basis(), Vector3(0.48 * side, 0.95, 0.05)), iron)
		add.call(_rod(Vector3(0.3 * side, 0.42, -0.95), Vector3(0.3 * side, 0.82, 1.5), 0.03),
			_rod_xf(Vector3(0.3 * side, 0.42, -0.95), Vector3(0.3 * side, 0.82, 1.5)), wood)
		add.call(_bx(Vector3(0.05, 0.6, 0.05)), Transform3D(Basis(), Vector3(0.3 * side, 0.3, 0.5)), wood)
	add.call(_bx(Vector3(0.88, 0.34, 0.04)), Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0.0, 0.79, -0.56)), wood)
	add.call(_bx(Vector3(0.88, 0.34, 0.04)), Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.0, 0.79, 0.66)), wood)
	var axle := CylinderMesh.new()
	axle.top_radius = 0.035
	axle.bottom_radius = 0.035
	axle.height = 0.68
	axle.radial_segments = 8
	axle.rings = 1
	add.call(axle, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0.0, WHEEL_R, -WHEEL_AHEAD)), iron)


## A wooden disc with an iron tyre and spokes, about its axle (the X axis).
static func _fill_wheel(add: Callable) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = WHEEL_R - 0.02
	disc.bottom_radius = WHEEL_R - 0.02
	disc.height = 0.07
	disc.radial_segments = 16
	disc.rings = 1
	add.call(disc, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), _mat(&"wood"))
	var tyre := TorusMesh.new()
	tyre.inner_radius = WHEEL_R - 0.035
	tyre.outer_radius = WHEEL_R
	tyre.rings = 24
	tyre.ring_segments = 6
	add.call(tyre, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO), _mat(&"iron"))
	for k in 4:
		add.call(_bx(Vector3(0.09, WHEEL_R * 1.8, 0.03)), Transform3D(Basis(Vector3.RIGHT, PI * float(k) / 4.0),
			Vector3.ZERO), _mat(&"iron"))


static func _bx(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _rod(a: Vector3, b: Vector3, radius: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = a.distance_to(b)
	c.radial_segments = 8
	c.rings = 1
	return c


## Turns a unit-height cylinder along Y onto the line a -> b (its height is
## already the length).
static func _rod_xf(a: Vector3, b: Vector3) -> Transform3D:
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 1e-4:
		x = Vector3.RIGHT
	x = x.normalized()
	return Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)


# --- The road -----------------------------------------------------------------------

## Joins a further leg on at the end of the route. `strict`: only on road no
## other convoy has claimed -- otherwise none, and the convoy goes on to the end
## of what it has and waits there until a clear leg turns up (it is retried).
## Taking a claimed leg anyway sent two head on into each other.
func _extend(strict := true) -> bool:
	var end: Vector2i = _cells[_cells.size() - 1]
	var behind: Vector2i = _cells[_cells.size() - 2] if _cells.size() > 1 else Vector2i(-9999, -9999)
	var leg := _leg(end, behind, strict)
	if leg.is_empty():
		return false
	_stops.append(_length_to_cell(_cells.size() - 1))
	_cells.append_array(leg)
	return true


## Arc length along the CURRENT polyline to roughly where cell `index` is
## (worked out once per smoothing: searched for every cell every tick, it cost
## ~1 ms a frame for four convoys).
func _length_to_cell(index: int) -> float:
	if index < 0 or index >= _cell_len.size():
		return INF
	return _cell_len[index]


var _cell_len := PackedFloat32Array()


func _measure_cells() -> void:
	_cell_len.resize(_cells.size())
	var j := 0
	for c in _cells.size():
		var target: Vector3 = built.to_world(_cells[c])
		# Cells come in order along the curve: search on from the last one.
		var best := INF
		var best_i := j
		for i in range(j, _pts.size()):
			var d := _pts[i].distance_squared_to(target)
			if d < best:
				best = d
				best_i = i
			elif d > best + 40.0:
				break
		j = best_i
		_cell_len[c] = _len[best_i]


## The cell centres, corners rounded off (Chaikin, twice), with arc lengths.
func _smooth() -> void:
	var raw: Array[Vector3] = []
	for c in _cells:
		raw.append(built.to_world(c))
	for pass_ in 2:
		if raw.size() < 3:
			break
		var out: Array[Vector3] = [raw[0]]
		for i in range(raw.size() - 1):
			out.append(raw[i].lerp(raw[i + 1], 0.25))
			out.append(raw[i].lerp(raw[i + 1], 0.75))
		out.append(raw[raw.size() - 1])
		raw = out
	_pts = PackedVector3Array(raw)
	_len = PackedFloat32Array()
	_len.resize(_pts.size())
	var total := 0.0
	for i in _pts.size():
		if i > 0:
			total += _pts[i].distance_to(_pts[i - 1])
		_len[i] = total
	_measure_cells()


## Position and heading at arc length `s`.
func _at(s: float) -> Array:
	var n := _pts.size()
	if n < 2:
		return [_pts[0] if n == 1 else Vector3.ZERO, Vector3.FORWARD]
	s = clampf(s, 0.0, _len[n - 1])
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if _len[mid] <= s:
			lo = mid
		else:
			hi = mid
	var seg := _len[hi] - _len[lo]
	var t := 0.0 if seg < 1e-4 else (s - _len[lo]) / seg
	var dir := (_pts[hi] - _pts[lo]).normalized() if seg >= 1e-4 else Vector3.FORWARD
	return [_pts[lo].lerp(_pts[hi], t), dir]


var _next_extend := 0.0


## Keeps road ahead and drops road far behind, holding the cart where it is.
func _maintain() -> void:
	var total: float = _len[_len.size() - 1]
	if total - _s >= LOOK_AHEAD:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_extend:
		return
	var here: Vector3 = _at(_s)[0]
	if not _extend():
		# Hemmed in: go on to the end of the road and try again shortly.
		_next_extend = now + 0.5
		return
	# Drop cells far behind the enforcer's mark.
	var drop := 0
	while drop < _cells.size() - 4:
		var behind_s := _s + ENFORCER_AT - KEEP_BEHIND
		if _length_to_cell(drop + 1) >= behind_s:
			break
		drop += 1
	var dropped_len := 0.0
	if drop > 0:
		dropped_len = _length_to_cell(drop)
		_cells = _cells.slice(drop)
	_smooth()
	for i in _stops.size():
		_stops[i] -= dropped_len
	# Re-find the cart on the new curve (the rounding only changed far ahead
	# and far behind, so this is exact).
	var best := INF
	for i in range(_pts.size() - 1):
		var a := _pts[i]
		var b := _pts[i + 1]
		var ab := b - a
		var t := clampf((here - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := here.distance_squared_to(a + ab * t)
		if d < best:
			best = d
			_s = _len[i] + ab.length() * t


# --- Running ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	if broken:
		return
	# Out of anyone's sight it moves ten times a second in bigger steps rather
	# than every tick: placing a dozen bodies and a cart every tick cost about
	# half a millisecond of physics for four convoys.
	if _player != null and is_instance_valid(_player) \
			and _player.global_position.distance_to(_cart.global_position) > FAR_STEP_FROM:
		_far_debt += delta
		if _far_debt < FAR_STEP:
			return
		delta = _far_debt
	_far_debt = 0.0
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next_check:
		_next_check = now + 0.2
		if _set_upon():
			_let_go()
			return
	var target := 0.0 if now < _pause_until else SPEED
	# The end of the road (waiting for a clear leg): the puller stops at it.
	var road_end: float = _len[_len.size() - 1] - PULL_AT - 0.3
	if _s >= road_end - 1.0:
		target = 0.0
	# Another convoy just ahead: wait for it to move on (and, should two ever
	# wait on each other, go on after a while rather than stand forever).
	if _held_up():
		if _waiting_since < 0.0:
			_waiting_since = now
		# Claims keep two convoys' roads apart, so this is a guard only.
		if now - _waiting_since < 30.0:
			target = 0.0
	else:
		_waiting_since = -1.0
	_speed = move_toward(_speed, target, ACCEL * delta)
	var ds := minf(_speed * delta, maxf(road_end - _s, 0.0))
	_s += ds
	# The end of a leg: a chance to stand a moment.
	while not _stops.is_empty() and _s >= _stops[0]:
		_stops.pop_front()
		if _rng.randf() < 0.5:
			_pause_until = now + _rng.randf_range(2.0, 4.0)
	_maintain()
	_place(ds)


var _waiting_since := -1.0


## Where the cart stands when its centre is at `s`: axis from the pusher's
## point on the road to the wheel's.
func _cart_xf(s: float) -> Transform3D:
	var wheel_pt: Vector3 = (_at(s + WHEEL_AHEAD) as Array)[0]
	var push_pt: Vector3 = (_at(s + PUSH_AT) as Array)[0]
	var dir := wheel_pt - push_pt
	dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 1e-4 else (_at(s) as Array)[1]
	return Transform3D(Basis.looking_at(dir, Vector3.UP), wheel_pt - dir * WHEEL_AHEAD)

## Lagging further than this behind its mark, out of the player's sight, the
## enforcer is put back on it.
const ENFORCER_LAG := 8.0


## Keeps the enforcer with the cart.
##   * Far from the player it sleeps like every enemy (enemy.gd dormancy) while
##     the cart goes on: carried along at its mark, it is where it should be
##     when it wakes. Without this: 55 m behind in a minute.
##   * Awake, it walks -- and a pack standing in the corridor stops it dead
##     (the crew are placed, and the cart shoves skeletons aside, but a walking
##     body only slides along another). Whatever enemy it bumps it stops
##     colliding with. Without this: 14 m behind.
##   * Still lagging and out of the player's sight, it is put back on its mark.
func _tend_enforcer() -> void:
	if enforcer == null or not is_instance_valid(enforcer) or enforcer.get("_dying") == true:
		return
	if enforcer.get("_dormant") == true:
		enforcer.global_transform = _marker.global_transform
		return
	if enforcer.get("engaged") == true:
		return
	var body := enforcer as CharacterBody3D
	for i in body.get_slide_collision_count():
		var other := body.get_slide_collision(i).get_collider() as Node
		if other != null and other is CharacterBody3D and other.has_method("alert") and other != _player:
			body.add_collision_exception_with(other)
	if enforcer.global_position.distance_to(_marker.global_position) > ENFORCER_LAG and not _player_sees(enforcer):
		enforcer.global_transform = _marker.global_transform


## Could the player see `n` -- near enough, with a clear line from their eyes?
func _player_sees(n: Node3D) -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var eye := _player.global_position + Vector3(0.0, 1.6, 0.0)
	if eye.distance_to(n.global_position) > 40.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(eye, n.global_position + Vector3(0.0, 1.2, 0.0), 2)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Another convoy's cart (or the enforcer walking behind it) on this one's road
## just ahead. Claims keep their roads apart, so this is a guard -- asked five
## times a second, not every tick.
var _held := false
var _next_held_check := 0.0


func _held_up() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_held_check:
		return _held
	_next_held_check = now + 0.2
	_held = _held_up_now()
	return _held


func _held_up_now() -> bool:
	var next := {}
	for i in _cells.size():
		var at := _length_to_cell(i)
		if at >= _s and at <= _s + PULL_AT + GIVE_WAY:
			next[_cells[i]] = true
	for other in maze.get("_convoys"):
		if other == self or not is_instance_valid(other) or other.get("broken") == true:
			continue
		for n: Node3D in [other.get("_cart") as Node3D, other.get("_marker") as Node3D]:
			if n != null and next.has(_cell_at(n.global_position)):
				return true
	return false


## Everyone to their place along the road.
##
## The cart is steered like a real barrow: its wheel on the road ahead of its
## centre, its handles at the pusher on the road behind, and its axis the line
## between them. Placed on the curve by its centre, the handles swung half a
## metre away from the pusher's hands on every bend.
func _place(ds: float) -> void:
	var push_pt: Vector3 = (_at(_s + PUSH_AT) as Array)[0]
	var xf := _cart_xf(_s)
	var dir := -xf.basis.z
	_cart.global_transform = xf
	_wheel.rotation.x -= ds / WHEEL_R
	_update_steady_side(ds)
	var m: Array = _at(_s + ENFORCER_AT)
	# Facing along the road: an escorting enforcer at rest turns to its escort's
	# heading.
	_marker.global_transform = Transform3D(Basis.looking_at(m[1], Vector3.UP), m[0])
	_tend_enforcer()
	for entry in crew:
		var e: Node3D = entry["node"]
		if not is_instance_valid(e):
			continue
		match entry["role"]:
			&"push":
				e.global_position = push_pt
				e.rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
			&"pull":
				var p: Array = _at(_s + PULL_AT)
				var pdir: Vector3 = p[1]
				e.global_position = p[0]
				e.rotation = Vector3(0.0, atan2(-pdir.x, -pdir.z), 0.0)
			_:
				# Beside the cart, with it, on whichever side is clear.
				e.global_position = _cart.to_global(Vector3(_steady_x, 0.0, -_steady_z))
				e.rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
		e.set("haul_speed", _speed)
	_draw_rope()


## The steadier walks beside the cart on the side that is clear. Coffins (the
## hiding places) stand 0.7 m out from a corridor's centre: a 1 m cart passes
## one, a skeleton beside it does not -- measured, the steadier walked through
## them. It looks ahead along each side; when its side is blocked and the other
## is clear it crosses over IN FRONT of the wheel (`_steady_z` goes out to the
## front while it crosses), never through the cart.
func _update_steady_side(ds: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# Its checks are ~90 rays a go: only near enough to be seen (four convoys
	# checking everywhere cost about half a millisecond a frame).
	var near := _player != null and is_instance_valid(_player) \
		and _player.global_position.distance_to(_cart.global_position) < STEADY_CARE
	if near and now >= _next_side_check:
		_next_side_check = now + 0.12
		# Its own side if clear, else the other, else in line behind the pusher.
		var side := signf(_steady_want) if _steady_want != 0.0 else 1.0
		if _slot_clear(side):
			_steady_want = side
		elif _slot_clear(-side):
			_steady_want = -side
		else:
			_steady_want = 0.0
	var step := maxf(ds, 0.0) * 3.0 + 0.012
	if _steady_want == 0.0:
		# Behind: back along its own side first, then in line.
		if absf(_steady_x) > 0.05 and _steady_z > STEADY_BEHIND + 0.01:
			_steady_z = move_toward(_steady_z, STEADY_BEHIND, step)
		else:
			_steady_x = move_toward(_steady_x, 0.0, step)
		return
	var goal_x := STEADY_SIDE * _steady_want
	if absf(_steady_x) < 0.05 and _steady_z < STEADY_AT - 0.5:
		# Coming out from behind: out to the side first.
		_steady_x = move_toward(_steady_x, goal_x, step)
	elif signf(_steady_x) == signf(_steady_want) or absf(_steady_x) < 0.05 and _steady_z >= STEADY_AT:
		# Its own side: fully out to the side first (just across in front of
		# the wheel, cutting back diagonally went through it), then alongside.
		if absf(_steady_x) < STEADY_SIDE - 0.01:
			_steady_x = move_toward(_steady_x, goal_x, step)
		else:
			_steady_z = move_toward(_steady_z, STEADY_AT, step)
	elif _steady_z < STEADY_CROSS - 0.01:
		# The far side: out ahead of the wheel first...
		_steady_z = move_toward(_steady_z, STEADY_CROSS, step)
	else:
		# ...then across.
		_steady_x = move_toward(_steady_x, goal_x, step)


## Is the place beside the cart on `side` free -- now, and where it will be a
## little further on (on a bend the cart swings it toward the outside wall) --
## and the corridor ahead on that side clear?
func _slot_clear(side: float) -> bool:
	if not _side_clear(side):
		return false
	# Far enough ahead to finish crossing before it gets there (measured: with
	# 1.2 m it noticed a coffin too late and brushed it while crossing).
	for ahead: float in [0.0, 0.8, 1.6, 2.4, 3.2]:
		if not _spot_clear(_cart_xf(_s + ahead) * Vector3(STEADY_SIDE * side, 0.0, -STEADY_AT)):
			return false
	return true


## No stone within a body's reach (0.42 m) of `at`, at hip and chest height.
func _spot_clear(at: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	for a in 8:
		var dir := Vector3(cos(TAU * a / 8.0), 0.0, sin(TAU * a / 8.0))
		var from := at + Vector3(0.0, 0.6 if a % 2 == 0 else 1.3, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 0.42, 2 | 256)
		q.exclude = [_cart.get_rid()]
		if not space.intersect_ray(q).is_empty():
			return false
	return true


## Is the corridor clear beside the cart on `side` (+1 right), over the next
## few metres of road?
func _side_clear(side: float) -> bool:
	var space := get_world_3d().direct_space_state
	for ahead: float in [0.0, 1.5, 3.0, 4.5]:
		var p: Array = _at(_s + ahead)
		var at: Vector3 = (p[0] as Vector3) + Vector3(0.0, 0.7, 0.0)
		var right := (p[1] as Vector3).cross(Vector3.UP).normalized()
		var q := PhysicsRayQueryParameters3D.create(at, at + right * side * (STEADY_SIDE + 0.45), 2 | 256)
		q.exclude = [_cart.get_rid()]
		if not space.intersect_ray(q).is_empty():
			return false
	return true


func _draw_rope() -> void:
	var puller: Dictionary = {}
	for entry in crew:
		if entry["role"] == &"pull":
			puller = entry
	if broken or puller.is_empty() or not is_instance_valid(puller["node"]):
		_rope.visible = false
		return
	var anchor := _cart.to_global(Vector3(0.0, 0.55, -1.15))
	var hand := _hand(puller, &"hand.R")
	var d := hand - anchor
	var length := d.length()
	if length < 0.05:
		_rope.visible = false
		return
	_rope.visible = true
	var y := d / length
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 1e-4:
		x = Vector3.RIGHT
	x = x.normalized()
	_rope.global_transform = Transform3D(Basis(x, y * length, x.cross(y)), (anchor + hand) * 0.5)


func _hand(entry: Dictionary, bone: StringName) -> Vector3:
	var sk: Skeleton3D = entry["sk"]
	var b := int(entry["bones"].get(bone, -1))
	var e: Node3D = entry["node"]
	if sk == null or b < 0:
		return e.global_position + Vector3(0.0, 1.0, 0.0)
	return sk.global_transform * sk.get_bone_global_pose(b).origin


## Called by a hauled skeleton (enemy.gd) after its walk has been posed: the
## arms go to the handles, the rope, or the load.
func pose_hauler(e: Node3D) -> void:
	var entry: Dictionary = {}
	for x in crew:
		if x["node"] == e:
			entry = x
	if entry.is_empty() or entry["sk"] == null:
		return
	var sk: Skeleton3D = entry["sk"]
	match entry["role"]:
		&"push":
			_reach(entry, &"L", _cart.to_global(Vector3(-0.3, 0.84, 1.48)))
			_reach(entry, &"R", _cart.to_global(Vector3(0.3, 0.84, 1.48)))
		&"pull":
			# The rope over the shoulder: the hand hangs back toward the cart.
			var shoulder := sk.global_transform * sk.get_bone_global_pose(int(entry["bones"][&"upper_arm.R"])).origin
			var to_cart := _cart.to_global(Vector3(0.0, 0.55, -1.15)) - shoulder
			_reach(entry, &"R", shoulder + (to_cart.normalized() + Vector3.DOWN * 1.2).normalized() * 0.6)
		_:
			# The near hand on the rim: the left on the cart's right side.
			var s := signf(_steady_x)
			_reach(entry, &"L" if s > 0.0 else &"R", _cart.to_global(Vector3(0.47 * s, 0.96, -0.05)))


## Points the side's upper arm and forearm straight at `target`.
func _reach(entry: Dictionary, side: StringName, target: Vector3) -> void:
	var sk: Skeleton3D = entry["sk"]
	var upper := int(entry["bones"].get(StringName("upper_arm." + side), -1))
	var fore := int(entry["bones"].get(StringName("forearm." + side), -1))
	if upper < 0 or fore < 0:
		return
	var to_skel := sk.global_transform.affine_inverse().basis
	var shoulder := sk.global_transform * sk.get_bone_global_pose(upper).origin
	var dir := (target - shoulder).normalized()
	_point(sk, upper, to_skel * dir)
	_point(sk, fore, to_skel * dir)


static func _point(sk: Skeleton3D, bone: int, dir: Vector3) -> void:
	if dir.length_squared() < 1e-6:
		return
	var pose := sk.get_bone_global_pose(bone)
	var basis := pose.basis.orthonormalized()
	pose.basis = Basis(Quaternion(basis.y.normalized(), dir.normalized())) * basis
	sk.set_bone_global_pose(bone, pose)


## Why it broke, for anyone asking (harnesses).
var broke_because := ""


## Has anyone noticed the player, or been hurt?
func _set_upon() -> bool:
	for entry in crew:
		var e: Node = entry["node"]
		if not is_instance_valid(e) or e.get("_dying") == true:
			broke_because = "crew lost"
			return true
		if float(e.get("health")) < float(e.get("max_health")):
			broke_because = "crew hurt"
			return true
		if float(e.get("_seen_until")) > Time.get_ticks_msec() / 1000.0:
			broke_because = "crew alerted"
			return true
	if enforcer != null and is_instance_valid(enforcer) and enforcer.get("engaged") == true:
		broke_because = "enforcer engaged"
		return true
	var p := _player
	if p == null or p.get("_dead") == true or (p.has_method("is_hidden") and p.call("is_hidden")):
		return false
	for body: Node3D in _bodies():
		var to := p.global_position - body.global_position
		if Vector2(to.x, to.z).length() < NOTICE_NEAR and absf(to.y) < 2.5:
			broke_because = "player close"
			return true
	var lead := _crew_node(&"pull")
	if lead != null:
		var to := p.global_position - lead.global_position
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() < NOTICE_FAR and absf(to.y) < 2.5 \
				and (-lead.global_basis.z).angle_to(flat.normalized()) < NOTICE_CONE:
			var q := PhysicsRayQueryParameters3D.create(lead.global_position + Vector3(0.0, 1.5, 0.0),
				p.global_position + Vector3(0.0, 1.2, 0.0), 2)
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				broke_because = "player seen"
				return true
	return false


func _bodies() -> Array[Node3D]:
	var out: Array[Node3D] = [_cart]
	for entry in crew:
		if is_instance_valid(entry["node"]):
			out.append(entry["node"])
	return out


func _crew_node(role: StringName) -> Node3D:
	for entry in crew:
		if entry["role"] == role and is_instance_valid(entry["node"]):
			return entry["node"]
	return null


## The cart is dropped where it stands and the crew turn on the player.
func _let_go() -> void:
	broken = true
	_speed = 0.0
	_rope.visible = false
	for entry in crew:
		var e: Node = entry["node"]
		if not is_instance_valid(e) or e.get("_dying") == true:
			continue
		e.set("hauled_by", null)
		e.set("velocity", Vector3.ZERO)
		e.set("_home", (e as Node3D).global_position)
		var none: Array[Vector3] = []
		e.set("wander_spots", none)
		e.call("alert")
	if enforcer != null and is_instance_valid(enforcer) and enforcer.has_method("alert"):
		enforcer.call("alert")


func is_broken() -> bool:
	return broken


# --- Looting the dropped cart ---------------------------------------------------------

func _process(_delta: float) -> void:
	_focus = false
	if broken and not looted and _player != null and is_instance_valid(_player) \
			and _player.get("_dead") != true and _player.get("in_cutscene") != true:
		var to := _cart.global_position - _player.global_position
		if Vector2(to.x, to.z).length() < 2.9 and Interact.looked_at(_cart, 3.4, 0.1):
			_focus = true
	_prompt.visible = _focus
	if _focus:
		_prompt.global_position = _cart.global_position + Vector3(0.0, 1.0, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not _focus or not Interact.pressed(event):
		return
	get_viewport().set_input_as_handled()
	looted = true
	_focus = false
	_prompt.visible = false
	# The lid thrown back over its hinges, and the load scooped out.
	var t := create_tween()
	t.tween_property(_lid, "rotation:z", LID_OPEN, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void: _load.visible = false)
	if _player.has_method("add_currency"):
		_player.call("add_currency", _rng.randi_range(20, 40))
	if _player.has_method("add_item"):
		_player.call("add_item", &"red_crystal", _rng.randi_range(1, 2))
		_player.call("add_item", &"gold_crystal", _rng.randi_range(1, 3))


## The lid (2026-10-10): half its width across the cart (it hinges at -X), how
## far it falls open, and how far the load is sunk to sit under it.
const LID_HALF := 0.44
const BRICK := preload("res://scripts/brick_level.gd")
## The kit cart's axle: along +Z by this, this high (tools/build_brick_kit.py).
const KIT_AXLE := Vector2(0.028, 0.375)
const LID_OPEN := 1.95
const LOAD_DROP := 0.18
var _lid: Node3D


## Five planks running the length of the tray from the hinge across (+X), three
## iron straps over them, a hasp on the free edge and the hinge pins. -Z is the
## cart's front, as everywhere here.
static func _fill_lid(add: Callable) -> void:
	var wood := _mat(&"wood")
	var iron := _mat(&"iron")
	var across := LID_HALF * 2.0
	var long := 1.34
	var planks := 5
	var each := across / float(planks)
	for i in planks:
		add.call(_bx(Vector3(each - 0.008, 0.04, long)), Transform3D(Basis(), Vector3(each * (float(i) + 0.5), 0.02, 0.0)), wood)
	for z: float in [-long * 0.34, 0.0, long * 0.34]:
		add.call(_bx(Vector3(across + 0.02, 0.016, 0.06)), Transform3D(Basis(), Vector3(across * 0.5, 0.048, z)), iron)
	add.call(_bx(Vector3(0.03, 0.12, 0.1)), Transform3D(Basis(), Vector3(across + 0.01, -0.02, 0.0)), iron)
	for z: float in [-long * 0.34, long * 0.34]:
		add.call(_rod(Vector3(0.0, 0.0, z - 0.08), Vector3(0.0, 0.0, z + 0.08), 0.022),
			_rod_xf(Vector3(0.0, 0.0, z - 0.08), Vector3(0.0, 0.0, z + 0.08)), iron)


# --- Helpers -------------------------------------------------------------------------

static func _mat(key: StringName) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		&"wood":
			m.albedo_texture = load("res://textures/wood_door_albedo.png")
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(1.4, 1.4, 1.4)
			m.albedo_color = Color(0.42, 0.34, 0.27)
			m.roughness = 0.9
		&"iron":
			m.albedo_color = Color(0.22, 0.2, 0.19)
			m.metallic = 0.45
			m.roughness = 0.6
		&"coin":
			# Old gold: bright gold reads as neon under the red sky.
			m.albedo_color = Color(0.62, 0.45, 0.16)
			m.metallic = 0.65
			m.roughness = 0.38
		&"red":
			m.albedo_color = Color(0.4, 0.05, 0.03)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.16, 0.08)
			m.emission_energy_multiplier = 1.8
			m.roughness = 0.25
		&"gold":
			m.albedo_color = Color(0.4, 0.28, 0.06)
			m.emission_enabled = true
			# At 2.4 the gold read as white blots through the bloom.
			m.emission = Color(1.0, 0.66, 0.18)
			m.emission_energy_multiplier = 1.3
			m.roughness = 0.25
		&"rope":
			m.albedo_color = Color(0.3, 0.24, 0.15)
			m.roughness = 1.0
	_mats[key] = m
	return m
