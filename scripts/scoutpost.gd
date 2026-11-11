extends Node3D

## A scoutpost (notes 180, 181; the user named them): one of maze.gd
## `module_scoutpost_rooms` rooms of the maze (module_level `_make_scoutposts`),
## enclosed and vaulted like the morgue and dressed after the user's photo of a
## great root-choked hall:
## - brick piers where the vaults meet (slim inside) and pilasters along the
##   walls, torches on the pilasters and caged lanterns hanging over the nave;
## - one wall buried in roots (gold-veined, some tips alive), roots crawling out
##   from its foot across the floor, roots over the archways, fewer on the rest;
## - timber balconies along the closed walls up a stair, posts and knee braces,
##   a railing with rags and banners hung over it -- the user's "little balcony
##   in them, with stairs", modelled and baked in Blender
##   (tools/build_scoutpost_kit.py, models/scoutpost_kit.glb) -- crates and
##   barrels under them, a table with a lantern and candles and a stool;
## - red banners, chains with big hooks from the vaults, a fire basket, a cart, a
##   pile of crates and barrels, floor grates, fallen blocks, candles, the dead;
## - loot lying about (`_scatter_loot`), several scouts (maze.gd
##   `_spawn_scoutpost_scouts`).
## The first (`identical`, the one nearest the start) is laid out as the photo,
## seen from its way in: the roots and a balcony on the left wall, another along
## the back, the fire basket front right, the cart behind it, the crates and
## barrels front left, the grates down the nave. The others are the same pieces
## dealt out again.
##
## Its archways are the dungeon doors: the cell kit's barred gate in each, hung
## raised. Walk in and every gate crashes down; hold E on the bronze winch's
## gear wheel (wheel_room.gd's, `make_winch`) and they wind up together; let go
## and they sink back, a hit breaks the grip. Wound up they stay up until
## everyone has left; with nobody alive inside a shut one opens itself again.
## Its beacon (maze.gd `_add_beacon`) stands in the middle, so rising there
## shuts you in too. Only the loot taken is saved.
##
## Frame: origin the middle of the block on the floor, +Z towards its first way in.

const Morgue := preload("res://scripts/morgue.gd")
const HoldingCell := preload("res://scripts/holding_cell.gd")
const WheelRoom := preload("res://scripts/wheel_room.gd")
const BrickLevel := preload("res://scripts/brick_level.gd")
const ModuleMaze := preload("res://scripts/module_maze.gd")
const Crate := preload("res://scripts/breakable_crate.gd")
const Roots := preload("res://scripts/ruin_roots.gd")

const PIER_HALF := 1.1
const PIER_TOP := 7.8
## The inside piers stand on a slim shaft (the junction pillar) up to here.
const SHAFT_TOP := 2.95
const PILASTER_PROUD := 0.25
const TORCH_HEIGHT := 2.6
## The gate in each archway, as far out of its ring cell as a holding cell's.
const GATE_Z := HoldingCell.GATE_Z
const GATE_HALF := HoldingCell.GATE_HALF
const GATE_HEIGHT := HoldingCell.GATE_HEIGHT
const LIFT := WheelRoom.LIFT
const DROP_TIME := WheelRoom.DROP_TIME
const CRANK_TIME := 3.6
const SINK := WheelRoom.SINK
## Shut once a player is this far in from the walls, after DROP_DELAY.
const TRIGGER_IN := 1.0
const DROP_DELAY := 0.35
## With nobody alive inside, a shut hall opens again after this.
const EMPTY_OPEN := 1.5
const WHEEL_Y := 1.45
const WHEEL_REACH := 2.4
## The lanterns over the nave: hook height, and a share of a corridor torch.
const LANTERN_HOOK_Y := 3.75
const LANTERN_SHARE := 3.0
## The galleries: deck top, depth out from the wall, half length.
const DECK_Y := 2.15
const DECK_DEPTH := 1.75
const DECK_HALF := 10.4
const RAIL_Y := 1.0
## The kit's measures (tools/build_scoutpost_kit.py): a deck bay's length, the
## post line out from the wall, the stair's run and width, and how far out of
## the wall it stands (clear of the pilasters).
const BAY := 3.0
const FRONT := 1.65
const STAIR_RUN := 3.4
const STAIR_W := 1.1
const STAIR_Z := 0.3
## A stair's foot keeps this far along from the hall's middle where a way in is
## in the corner beyond it.
const STAIR_CLEAR := 10.3
const DRAWN_TO := 60.0
const LAYERS := 256 | 512

var built
var room: Dictionary = {}
var maze: Node
var ruins: Node
var identical := false
## Its beacon (respawn_anchor.gd), set by maze.gd.
var beacon: Node3D
## What stands on the floor, [{at, half}] (world), for maze.gd `_mark_solid`.
var solid: Array = []

var _rng := RandomNumberGenerator.new()
var _wall := 13.9
var _ring := 12.0
var _cell := 6.0
var _walls: Array = []
var _gates: Array[Node3D] = []
var _blockers: Array[CollisionShape3D] = []
var _body: StaticBody3D
var _wood_st: SurfaceTool
var _lift := 1.0
var _locked := false
var _armed := true
var _drop_in := -1.0
var _empty_for := 0.0
var _wheel: Node3D
var _wheel_spin: Node3D
var _prompt: Interact.Prompt
var _player: Node3D
var _holder: Node3D
var _holder_health := 0.0
var _lanterns: Array[Node3D] = []
var counts := {}
## Corner cells the stairs stand in: no props there.
var _stair_cells := {}
## For tests: per stair {foot, top, far} (hall frame).
var _stairs: Array = []
var _loot_spots: Array[Vector3] = []
var _table_spot := Vector3.INF
## The loot lying here (item_drop.gd) and which of it has been taken, by index.
var loot: Array = []
var loot_taken: Array = []


static func build(parent: Node3D, level, room_: Dictionary, owner_maze: Node, ruin_dressing: Node,
		torch_energy: float, first: bool) -> Node3D:
	var hall := Node3D.new()
	hall.set_script(load("res://scripts/scoutpost.gd"))
	hall.name = "Scoutpost%d_%d" % [room_["centre"].x, room_["centre"].y]
	hall.set("built", level)
	hall.set("room", room_)
	hall.set("maze", owner_maze)
	hall.set("ruins", ruin_dressing)
	hall.set("identical", first)
	parent.add_child(hall)
	hall.call("_build", torch_energy)
	return hall


## Where maze.gd stands the beacon: the middle of the hall.
func beacon_spot() -> Vector3:
	return Vector3.ZERO


func _count(what: String, n := 1) -> void:
	counts[what] = int(counts.get(what, 0)) + n


# --- The plan ----------------------------------------------------------------------------

func _build(torch_energy: float) -> void:
	var centre: Vector3 = built.room_world(room)
	var out := Vector3(0.0, 0.0, 1.0)
	var doors: Array = built.room_doors(room)
	if not doors.is_empty():
		var step: Vector2i = doors[0]["outward"]
		out = Vector3(float(step.x), 0.0, float(step.y))
	global_transform = Transform3D(Basis.looking_at(-out, Vector3.UP), centre)
	_rng.seed = hash(room["centre"]) ^ 0x4a11b
	_cell = built.cell_size
	var h: int = room["half"]
	_ring = float(h) * _cell
	_wall = _ring + BrickLevel.WALL_FACE
	_body = StaticBody3D.new()
	_body.name = "HallCollision"
	_body.collision_layer = LAYERS
	_body.collision_mask = 0
	add_child(_body)
	_wood_st = SurfaceTool.new()
	_wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# The four walls, each a row of ring cells: [d into the wall, a along it].
	for d: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var a := Vector3(-d.z, 0.0, d.x)
		var cells: Array = []
		var closed := true
		for k in range(-h, h + 1):
			var local := d * _ring + a * (float(k) * _cell)
			var key := _key(local)
			var side := _side(d)
			var entrance: bool = built.cells.has(key) and (built.cells[key].open & side) != 0
			closed = closed and not entrance
			cells.append({"key": key, "side": side, "along": float(k) * _cell, "entrance": entrance,
				"corner": absi(k) == h, "local": local})
		_walls.append({"d": d, "a": a, "cells": cells, "closed": closed, "gallery": false,
			"heavy": false, "winch": -1})

	# Roles. The photo, seen from the way in: the roots and a gallery on the
	# left, a gallery along the back, the winch on the right.
	var order: Array = [0, 1, 2, 3]
	if identical:
		order = [1, 2, 0, 3]
	else:
		_shuffle(order)
	var winch_wall := -1
	for pass_i in 2:
		for i in order:
			var w: Dictionary = _walls[i]
			var ks: Array = [h] if pass_i == 0 else range(w["cells"].size())
			for k in ks:
				if winch_wall < 0 and not w["cells"][k]["entrance"]:
					w["winch"] = k
					winch_wall = i
	var heavy := 0 if identical else _rng.randi_range(0, 3)
	_walls[heavy]["heavy"] = true
	var galleries := 0
	var want_galleries := 2 if identical else (1 if _rng.randf() < 0.65 else 2)
	var gallery_order: Array = [0, 2, 1, 3] if identical else order
	for i in gallery_order:
		var w: Dictionary = _walls[i]
		if galleries < want_galleries and w["closed"] and i != winch_wall:
			w["gallery"] = true
			galleries += 1

	_build_piers(h)
	_hang_torches(h, torch_energy)
	_hang_lanterns(torch_energy)
	_build_gates()
	if winch_wall >= 0:
		_build_winch(_walls[winch_wall])
	for w in _walls:
		if w["gallery"]:
			_gallery(w)
	_dress()
	_commit_wood()
	_scatter_loot()
	_draw_to(self)
	print("[scoutposts] scoutpost at %v%s: %d ways in, %d balconies, winch %s; %s" % [room["centre"],
		" (the photo's)" if identical else "", _gates.size(), galleries,
		"on the %s wall" % ["left", "right", "back", "front"][winch_wall] if winch_wall >= 0 else "NONE",
		", ".join(counts.keys().map(func(k): return "%s %d" % [k, counts[k]]))])


## The grid cell under a point in the hall's frame.
func _key(local: Vector3) -> Vector2i:
	var w := global_basis * local
	return Vector2i(room["centre"]) + Vector2i(roundi(w.x / _cell), roundi(w.z / _cell))


## The grid side a direction in the hall's frame points to.
func _side(local_dir: Vector3) -> int:
	var w := global_basis * local_dir
	var step := Vector2i(roundi(w.x), roundi(w.z))
	for side in ModuleMaze.ORDER:
		if ModuleMaze.DIRS[side] == step:
			return side
	return 0


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = list[i]
		list[i] = list[j]
		list[j] = tmp


# --- Stone and light ---------------------------------------------------------------------

## The morgue's piers and pilasters (morgue.gd `_build_piers`): a square brick
## pier at every vertex inside, a pilaster at every one along the walls.
func _build_piers(h: int) -> void:
	var face: Mesh = BrickLevel.standalone("pier_face")
	var pilaster_in := _wall - PILASTER_PROUD
	var faces: Array[Transform3D] = []
	var cores: Array[Transform3D] = []
	var verts: Array[float] = []
	for k in range(-h, h):
		verts.append((float(k) + 0.5) * _cell)
	var mid := pilaster_in + PIER_HALF
	var piers: Array = []
	for vx in verts:
		for vz in verts:
			piers.append([Vector3(vx, 0.0, vz), [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]])
	for v in verts:
		piers.append([Vector3(v, 0.0, -mid), [Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]])
		piers.append([Vector3(v, 0.0, mid), [Vector3.FORWARD, Vector3.LEFT, Vector3.RIGHT]])
		piers.append([Vector3(-mid, 0.0, v), [Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]])
		piers.append([Vector3(mid, 0.0, v), [Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]])
	var rock := StaticBody3D.new()
	rock.name = "Piers"
	rock.collision_layer = BrickLevel.LAYER_WALLS
	rock.collision_mask = 0
	add_child(rock)
	# Inside, the morgue's 2.2 m piers made a forest of stone with 1.9 m between
	# them (seen in the first shots): here the 2.2 m block only fills the vaults'
	# meeting from SHAFT_TOP up, on the corridors' own junction pillar
	# (0.9 m), so the floor is open. Not under the boss hall's floor, where
	# the raised block would reach through it: there the whole pier.
	var pillar: Mesh = BrickLevel.meshes(1.0).get("pillar")
	var level = load("res://scripts/module_level.gd")
	var shafts: Array[Transform3D] = []
	for i in piers.size():
		var pier: Array = piers[i]
		var c: Vector3 = pier[0]
		var slim: bool = i < verts.size() * verts.size() and pillar != null \
			and not level.under_boss_hall(built, to_global(c), 2.0)
		var lift := SHAFT_TOP if slim else 0.0
		cores.append(Transform3D(Basis(), c + Vector3(0.0, lift + PIER_TOP * 0.5, 0.0)))
		for d: Vector3 in pier[1]:
			faces.append(Transform3D(Basis.looking_at(-d, Vector3.UP), c + d * PIER_HALF + Vector3(0.0, lift, 0.0)))
		var shape := BoxShape3D.new()
		shape.size = Vector3(PIER_HALF * 2.0, 6.0 - lift, PIER_HALF * 2.0)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = c + Vector3(0.0, lift + (6.0 - lift) * 0.5, 0.0)
		rock.add_child(cs)
		if slim:
			shafts.append(Transform3D(Basis(Vector3.UP, PI * 0.5 * float(_rng.randi_range(0, 3))), c))
			var shaft := BoxShape3D.new()
			shaft.size = Vector3(BrickLevel.PILLAR_HALF * 2.0, lift, BrickLevel.PILLAR_HALF * 2.0)
			var ss := CollisionShape3D.new()
			ss.shape = shaft
			ss.position = c + Vector3(0.0, lift * 0.5, 0.0)
			rock.add_child(ss)
	if face != null:
		_multi(face, faces, "PierFaces")
	if not shafts.is_empty():
		_multi(pillar, shafts, "PierShafts")
		_count("slim piers", shafts.size())
	var core := BoxMesh.new()
	core.size = Vector3(PIER_HALF * 2.0 - 0.12, PIER_TOP, PIER_HALF * 2.0 - 0.12)
	core.material = Morgue._mat(&"core")
	_multi(core, cores, "PierCores")


func _multi(mesh: Mesh, xfs: Array[Transform3D], name_: String) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)


## A torch on the inner face of the pilasters next to each wall's middle.
func _hang_torches(h: int, energy: float) -> void:
	if energy <= 0.0:
		return
	var level = load("res://scripts/module_level.gd")
	var scene: PackedScene = load(level.TORCH_SCENE)
	var pilaster_in := _wall - PILASTER_PROUD
	for w in _walls:
		var d: Vector3 = w["d"]
		var a: Vector3 = w["a"]
		for s: float in [-0.5, 0.5]:
			var at := d * (pilaster_in - 0.02) + a * (s * _cell) + Vector3(0.0, TORCH_HEIGHT, 0.0)
			level._hang_torch(self, scene, at, d, energy, 13.0)
			_count("torches")


## Caged lanterns on their chains from the vaults over the four cells round the
## middle, each a torch light (holding_cell.gd `make_lantern`).
func _hang_lanterns(energy: float) -> void:
	for p: Vector3 in [Vector3(-_cell, 0, 0), Vector3(_cell, 0, 0), Vector3(0, 0, -_cell), Vector3(0, 0, _cell)]:
		var at := p + Vector3(_rng.randf_range(-0.6, 0.6), LANTERN_HOOK_Y + _rng.randf_range(-0.25, 0.2),
			_rng.randf_range(-0.6, 0.6))
		_lanterns.append(HoldingCell.make_lantern(self, at, energy * LANTERN_SHARE))
		_count("lanterns")
	_hang_chains.call_deferred()


## Each lantern's chain up into the vault, once collision is live.
func _hang_chains() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for lantern in _lanterns:
		if not is_instance_valid(lantern):
			continue
		var from := lantern.global_position
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 8.0, 2 | 256))
		var reach := 1.5 if hit.is_empty() else (hit["position"] as Vector3).y - from.y + 0.15
		var runs := clampi(ceili(reach / HoldingCell.CHAIN_RUN), 1, 12)
		for i in runs:
			var run := MeshInstance3D.new()
			run.mesh = HoldingCell.kit_mesh("lantern_chain")
			run.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			run.position = Vector3(0.0, HoldingCell.CHAIN_RUN * float(i + 1), 0.0)
			run.rotation.y = PI * 0.5 * float(i % 2)
			run.visibility_range_end = DRAWN_TO
			lantern.add_child(run)


# --- The dungeon doors and the wheel ----------------------------------------------------

## The cell kit's barred gate in every archway, raised (holding_cell.gd
## `_build_gate`); its blocker off until it drops.
func _build_gates() -> void:
	for w in _walls:
		for c in w["cells"]:
			if not c["entrance"]:
				continue
			var d: Vector3 = w["d"]
			var gate := Node3D.new()
			gate.name = "Gate%d" % _gates.size()
			add_child(gate)
			gate.transform = Transform3D(Basis.looking_at(-d, Vector3.UP), c["local"] + d * GATE_Z + Vector3(0.0, LIFT, 0.0))
			for s: float in [-1.0, 1.0]:
				var hinge := Node3D.new()
				hinge.position = Vector3(s * GATE_HALF, 0.0, 0.0)
				gate.add_child(hinge)
				var leaf := MeshInstance3D.new()
				leaf.mesh = HoldingCell.kit_mesh("gate_l" if s < 0.0 else "gate_r")
				leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				hinge.add_child(leaf)
			var body := StaticBody3D.new()
			body.name = "Blocker"
			body.collision_layer = 1
			body.collision_mask = 0
			gate.add_child(body)
			var box := BoxShape3D.new()
			box.size = Vector3(GATE_HALF * 2.0 + 0.1, GATE_HEIGHT, 0.15)
			var cs := CollisionShape3D.new()
			cs.shape = box
			cs.position = Vector3(0.0, GATE_HEIGHT * 0.5, 0.0)
			cs.disabled = true
			body.add_child(cs)
			_gates.append(gate)
			_blockers.append(cs)


## The photo's bronze gear door, the winch, on the wall's middle cell (wheel_room.gd).
func _build_winch(w: Dictionary) -> void:
	var c: Dictionary = w["cells"][int(w["winch"])]
	var d: Vector3 = w["d"]
	var frame := Node3D.new()
	frame.name = "WinchWall"
	add_child(frame)
	# Its +Z out of the wall into the hall.
	frame.transform = Transform3D(Basis.looking_at(d, Vector3.UP), c["local"] + d * (BrickLevel.WALL_FACE - 0.12))
	var parts := WheelRoom.make_winch(frame, Vector3(0.0, WHEEL_Y, 0.0))
	_wheel = parts[0]
	_wheel_spin = parts[1]
	_prompt = Interact.prompt("Hold E   Turn the wheel", Vector3(0.0, 0.2, 0.35))
	_wheel.add_child(_prompt)
	_prompt.visible = false
	if ruins != null:
		ruins._reserve(c["key"], c["side"], 0.0, 1.3)


## Built before the navmesh with every gate raised: nothing changes.
func arm() -> void:
	pass


func _inside(p: Node3D) -> bool:
	var l := to_local(p.global_position)
	var reach := _wall - TRIGGER_IN
	return absf(l.x) < reach and absf(l.z) < reach and l.y > -1.0 and l.y < 4.5


func _set_lift(v: float) -> void:
	_lift = v
	for g in _gates:
		g.position.y = LIFT * v


func _process(delta: float) -> void:
	var players: Array = []
	for p in Coop.all():
		if is_instance_valid(p) and p.get("_dead") != true:
			players.append(p)
	var anyone := players.any(func(p) -> bool: return _inside(p))
	if not _locked:
		if not anyone:
			_armed = true
			_drop_in = -1.0
		elif _armed and _lift >= 1.0 and _wheel != null:
			if _drop_in < 0.0:
				_drop_in = DROP_DELAY
			_drop_in -= delta
			if _drop_in <= 0.0:
				_slam()
	if _wheel == null:
		return
	_player = Coop.user_for(_wheel, _player)
	var near := false
	if _player != null and _locked:
		var to := _player.global_position - _wheel.global_position
		near = Vector2(to.x, to.z).length() <= WHEEL_REACH and absf(to.y) < 2.5 \
			and Interact.looked_at(_wheel, 3.2, 0.15, [], _player) and _player.get("in_cutscene") != true
	if _holder != null and (_holder != _player or not near or not is_instance_valid(_holder)
			or not Coop.held(_holder, &"interact")):
		_let_go_wheel()
	if _locked:
		var was := _lift
		_empty_for = 0.0 if anyone else _empty_for + delta
		if _holder != null or _empty_for > EMPTY_OPEN:
			_set_lift(minf(_lift + delta / CRANK_TIME, 1.0))
		else:
			_set_lift(maxf(_lift - delta * SINK / CRANK_TIME, 0.0))
		_wheel_spin.rotation.z += (_lift - was) * TAU * 3.0
		if _lift >= 1.0:
			_unlock()
	_prompt.visible = near and _locked
	_prompt.player = _player
	_prompt.progress = _lift if _holder != null else -1.0


func _unhandled_input(event: InputEvent) -> void:
	if not _locked or _player == null or _prompt == null or not _prompt.visible \
			or not Interact.pressed(event, _player):
		return
	get_viewport().set_input_as_handled()
	_let_go_wheel()
	_holder = _player
	if _holder.has_signal("health_changed"):
		_holder.connect("health_changed", _on_holder_health)
	_holder_health = float(_holder.get("health"))


func _on_holder_health(current: float, _maximum: float) -> void:
	if current < _holder_health - 0.001:
		_let_go_wheel()
		return
	_holder_health = current


func _let_go_wheel() -> void:
	if _holder != null and is_instance_valid(_holder) and _holder.is_connected("health_changed", _on_holder_health):
		_holder.disconnect("health_changed", _on_holder_health)
	_holder = null


func _slam() -> void:
	_locked = true
	_armed = false
	_drop_in = -1.0
	_empty_for = 0.0
	for b in _blockers:
		b.set_deferred("disabled", false)
	var tw := create_tween()
	tw.tween_method(_set_lift, _lift, 0.0, DROP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_landed)


func _landed() -> void:
	for p in Coop.all():
		if is_instance_valid(p) and p.get("_shake") != null and _inside(p):
			p.set("_shake", maxf(float(p.get("_shake")), 0.35))
	var gfx := get_node_or_null("/root/Graphics")
	if gfx != null and not bool(gfx.get("effects")):
		return
	for g in _gates:
		var dust := CPUParticles3D.new()
		dust.one_shot = true
		dust.emitting = false
		dust.amount = 14
		dust.lifetime = 1.6
		dust.explosiveness = 0.95
		dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		dust.emission_box_extents = Vector3(GATE_HALF, 0.05, 0.1)
		dust.direction = Vector3(0.0, 0.3, -1.0)
		dust.spread = 80.0
		dust.initial_velocity_min = 0.6
		dust.initial_velocity_max = 1.8
		dust.damping_min = 2.0
		dust.damping_max = 3.0
		dust.gravity = Vector3(0.0, 0.2, 0.0)
		dust.scale_amount_min = 0.6
		dust.scale_amount_max = 1.2
		var ramp := Gradient.new()
		ramp.set_color(0, Color(0.55, 0.5, 0.44, 0.55))
		ramp.set_color(ramp.get_point_count() - 1, Color(0.5, 0.46, 0.4, 0.0))
		dust.color_ramp = ramp
		var quad := QuadMesh.new()
		quad.size = Vector2(0.9, 0.9)
		var m := StandardMaterial3D.new()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = load("res://textures/surgery_fx_dust.png")
		m.roughness = 1.0
		quad.material = m
		dust.mesh = quad
		g.add_child(dust)
		dust.position = Vector3(0.0, 0.1, 0.0)
		dust.restart()
		get_tree().create_timer(2.0).timeout.connect(dust.queue_free)


func _unlock() -> void:
	_locked = false
	_armed = false
	_empty_for = 0.0
	_let_go_wheel()
	for b in _blockers:
		b.set_deferred("disabled", true)


# --- Timber -------------------------------------------------------------------------------

## A box of timber `size` big at `xf` (its middle) in the hall's frame, into the
## one wood mesh.
func _timber(xf: Transform3D, size: Vector3) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_wood_st.append_from(bm, 0, xf)


## A timber from `a` to `b` (the hall's frame), `t` square.
func _strut(a: Vector3, b: Vector3, t: float) -> void:
	var along := b - a
	var y := along.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	_timber(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(t, along.length(), t))


func _solid_box(xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = xf
	_body.add_child(cs)


func _commit_wood() -> void:
	var mesh := _wood_st.commit()
	if mesh.get_surface_count() == 0:
		return
	mesh.surface_set_material(0, Morgue._mat(&"wood_dark"))
	var mi := MeshInstance3D.new()
	mi.name = "Timber"
	mi.mesh = mesh
	add_child(mi)
	if ruins != null:
		ruins._casters.append(mi)


## The balcony's pieces (note 181): models/scoutpost_kit.glb, modelled and baked
## in Blender by tools/build_scoutpost_kit.py, read once by name.
const KIT := "res://models/scoutpost_kit.glb"
static var _kit_meshes := {}


static func kit_mesh(piece: String) -> Mesh:
	if _kit_meshes.is_empty():
		var scene := load(KIT) as PackedScene
		if scene != null:
			var root := scene.instantiate()
			for found in root.find_children("*", "MeshInstance3D", true, false):
				_kit_meshes[String(found.name)] = (found as MeshInstance3D).mesh
			root.free()
	return _kit_meshes.get(piece)


func _kit(piece: String, xf: Transform3D) -> MeshInstance3D:
	var mesh := kit_mesh(piece)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = piece.capitalize().replace(" ", "")
	mi.mesh = mesh
	mi.transform = xf
	add_child(mi)
	if ruins != null:
		ruins._casters.append(mi)
	return mi


## The photo's balcony along wall `w` (note 181): deck bays end to end on posts
## with knee braces, a railing along the front and across the far end, and a
## stair up to it against the wall beyond the near end -- all solid, so it is
## walked. Rags and banners over the rail; loot up on it (`_scatter_loot`).
func _gallery(w: Dictionary) -> void:
	var d: Vector3 = w["d"]
	var a: Vector3 = w["a"]
	# The balcony's own frame: x along the wall, z out of it into the hall.
	var g := Transform3D(Basis(a, Vector3.UP, -d), d * _wall)
	var cells: Array = w["cells"]
	var open_lo: bool = (built.cells[cells[0]["key"]].open & _side(-a)) != 0
	var open_hi: bool = (built.cells[cells[cells.size() - 1]["key"]].open & _side(a)) != 0
	# A corner whose other wall has a way in: the deck stops short of it, its
	# posts out of the path of anyone coming through.
	var lo := -DECK_HALF + (3.0 if open_lo else 0.0)
	var hi := DECK_HALF - (3.0 if open_hi else 0.0)
	# The stair against the wall past one end: one with no way in by it if
	# there is one; else the deck shortens so the stair's foot stays clear.
	var up := 1.0
	if open_hi and not open_lo:
		up = -1.0
	elif not open_hi and not open_lo and _rng.randf() < 0.5:
		up = -1.0
	if (up > 0.0 and open_hi) or (up < 0.0 and open_lo):
		if up > 0.0:
			hi = minf(hi, STAIR_CLEAR - STAIR_RUN)
		else:
			lo = maxf(lo, -STAIR_CLEAR + STAIR_RUN)
	var n := maxi(roundi((hi - lo) / BAY), 1)
	var sx := (hi - lo) / (float(n) * BAY)
	var stretch := Basis.from_scale(Vector3(sx, 1.0, 1.0))
	for i in n:
		var x := lo + (float(i) + 0.5) * BAY * sx
		_kit("deck_bay", g * Transform3D(stretch, Vector3(x, DECK_Y, 0.0)))
		_kit("rail_bay", g * Transform3D(stretch, Vector3(x, DECK_Y, FRONT)))
	for i in n + 1:
		var x := lo + float(i) * BAY * sx
		var piece := "post"
		var b := Basis()
		if i == 0:
			piece = "post_end"
		elif i == n:
			piece = "post_end"
			b = Basis.from_scale(Vector3(-1.0, 1.0, 1.0))
		_kit(piece, g * Transform3D(b, Vector3(x, 0.0, FRONT)))
		_solid_box(g * Transform3D(Basis(), Vector3(x, 1.0, FRONT)), Vector3(0.26, 2.0, 0.26))
	# The deck, solid; the railing along the front and across the far end.
	var mid := (hi + lo) * 0.5
	var span_len := hi - lo
	_solid_box(g * Transform3D(Basis(), Vector3(mid, DECK_Y - 0.06, DECK_DEPTH * 0.5)), Vector3(span_len, 0.12, DECK_DEPTH))
	_solid_box(g * Transform3D(Basis(), Vector3(mid, DECK_Y + 0.55, FRONT)), Vector3(span_len, 1.1, 0.12))
	var far := lo if up > 0.0 else hi
	var near := hi if up > 0.0 else lo
	_kit("rail_bay", g * Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(FRONT / BAY, 1.0, 1.0)),
		Vector3(far, DECK_Y, FRONT * 0.5)))
	_solid_box(g * Transform3D(Basis(), Vector3(far, DECK_Y + 0.55, FRONT * 0.5)), Vector3(0.12, 1.1, FRONT))
	# The stair, rising to the near end, and its ramp: a wedge under the treads.
	var foot := near + up * STAIR_RUN
	# No props where it stands (`_dress`, `_blocks`).
	for c in cells:
		var along: float = c["along"]
		if along + 3.0 > minf(foot, near) and along - 3.0 < maxf(foot, near):
			_stair_cells[c["key"]] = true
	_kit("stair", g * Transform3D(Basis.from_scale(Vector3(up, 1.0, 1.0)), Vector3(foot, 0.0, STAIR_Z)))
	var wedge := ConvexPolygonShape3D.new()
	var z0 := STAIR_Z
	var z1 := STAIR_Z + STAIR_W
	wedge.points = PackedVector3Array([
		Vector3(foot, 0.0, z0), Vector3(foot, 0.0, z1), Vector3(near, 0.0, z0), Vector3(near, 0.0, z1),
		Vector3(near, DECK_Y, z0), Vector3(near, DECK_Y, z1)])
	var ramp := CollisionShape3D.new()
	ramp.name = "Stair"
	ramp.shape = wedge
	ramp.transform = g
	_body.add_child(ramp)
	_stairs.append({"foot": g * Vector3(foot - up * 0.6, 0.0, (z0 + z1) * 0.5),
		"top": g * Vector3(near - up * 1.2, DECK_Y, 0.9), "far": g * Vector3(far + up * 1.0, DECK_Y, 0.9)})
	_count("balconies")
	# Spots up on the deck for the loot, clear of the stair's head.
	for i in 3:
		var x := lerpf(near - up * 2.0, far + up * 1.0, (float(i) + 0.5) / 3.0)
		_loot_spots.append(g * Vector3(x, DECK_Y + 0.25, 0.7))
	if ruins == null:
		return
	# A crate against the wall at the far end.
	var c := Crate.make(_rng.randi_range(0, Crate.SIZES.size() - 1),
		global_transform * g * Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.2, 0.2)), Vector3(far + up * 0.6, DECK_Y, 0.55)),
		hash(room["centre"]) + _stairs.size())
	ruins.add_child(c)
	# Rags and banners over the rail.
	var span := span_len / float(n)
	for i in n:
		if _rng.randf() > 0.6:
			continue
		var x := lo + (float(i) + 0.5) * span + _rng.randf_range(-0.6, 0.6)
		var xf := global_transform * g * Transform3D(Basis(), Vector3(x, DECK_Y + RAIL_Y + 0.05, FRONT + 0.07))
		if _rng.randf() < 0.3:
			ruins.hang_cloth(xf, _rng.randf_range(0.8, 1.0), _rng.randf_range(1.6, 2.1),
				[Color(0.3, 0.035, 0.03), Color(0.24, 0.03, 0.035)][_rng.randi_range(0, 1)])
		else:
			ruins.hang_cloth(xf, _rng.randf_range(0.5, 0.9), _rng.randf_range(0.8, 1.5),
				Color(0.3, 0.27, 0.21) * _rng.randf_range(0.8, 1.15), true)
		_count("rags")


## A plank table and a stool against wall (`key`, `side`) at `x`, a lantern and
## candles on it.
func _table(key: Vector2i, side: int, x: float) -> void:
	var w: Transform3D = global_transform.affine_inverse() * ruins._wall_xf(key, side)
	var top := 0.86
	var mid := Vector3(x, 0.0, 0.62)
	_timber(w * Transform3D(Basis(), mid + Vector3(0.0, top - 0.03, 0.0)), Vector3(1.6, 0.06, 0.78))
	for sx: float in [-0.7, 0.7]:
		for sz: float in [-0.3, 0.3]:
			_timber(w * Transform3D(Basis(), mid + Vector3(sx, (top - 0.06) * 0.5, sz)), Vector3(0.08, top - 0.06, 0.08))
	_timber(w * Transform3D(Basis(), mid + Vector3(0.0, 0.18, 0.0)), Vector3(1.4, 0.05, 0.06))
	_solid_box(w * Transform3D(Basis(), mid + Vector3(0.0, top * 0.5, 0.0)), Vector3(1.6, top, 0.78))
	var stool := mid + Vector3(0.55, 0.0, 0.75)
	_timber(w * Transform3D(Basis(Vector3.UP, 0.3), stool + Vector3(0.0, 0.46, 0.0)), Vector3(0.42, 0.05, 0.42))
	for sx: float in [-0.15, 0.15]:
		for sz: float in [-0.15, 0.15]:
			_timber(w * Transform3D(Basis(Vector3.UP, 0.3), stool + Vector3(sx, 0.22, sz)), Vector3(0.05, 0.44, 0.05))
	var lantern := HoldingCell.make_lantern(self, w * (mid + Vector3(-0.35, top + 0.5, 0.05)), 0.0)
	lantern.name = "TableLantern"
	ruins._candles(global_transform * w * Transform3D(Basis(), mid + Vector3(0.2, top, 0.05)), _rng.randi_range(3, 5), true)
	_count("tables")
	_table_spot = w * (mid + Vector3(0.35, top + 0.15, -0.1))


# --- Dressing ------------------------------------------------------------------------------

func _dress() -> void:
	if ruins == null:
		return
	var first: int = ruins.hall_begin(hash(room["centre"]))
	var strands: Array = []
	var live: Array = []
	var table_done := false
	for w in _walls:
		var d: Vector3 = w["d"]
		for i in w["cells"].size():
			var c: Dictionary = w["cells"][i]
			var key: Vector2i = c["key"]
			var side: int = c["side"]
			if c["entrance"]:
				# Roots over the archway, the gate in it.
				if _rng.randf() < (0.9 if w["heavy"] else 0.45):
					var arch: Dictionary = ruins._arch_frame(key, side)
					if not arch.is_empty():
						var relief = ruins._relief_arch_pos if arch["sign"] > 0.0 else ruins._relief_arch_neg
						for s in Roots.arch_strands(ruins._rng, relief, _rng.randi_range(1, 3), arch["sign"]):
							strands.append(s.transformed(arch["xf"]))
				continue
			var is_winch: bool = int(w["winch"]) == i
			# Roots: the heavy wall buried, the rest here and there.
			if w["heavy"] and not is_winch:
				ruins._wall_roots(key, side, _rng.randi_range(14, 20), 1 if not c["corner"] or _rng.randf() < 0.5 else 0,
					strands, live)
				ruins._hanging_roots(key, built.cells[key], _rng.randi_range(5, 10), strands)
			elif not is_winch and _rng.randf() < 0.55:
				ruins._wall_roots(key, side, _rng.randi_range(4, 9), 1 if _rng.randf() < 0.35 else 0, strands, live)
			if is_winch or _stair_cells.has(key):
				continue
			if w["gallery"]:
				# Under the deck: a table in the photo's place, stores elsewhere.
				if identical and not table_done and i == (w["cells"].size() - 1) >> 1:
					_table(key, side, 0.0)
					table_done = true
				elif _rng.randf() < 0.55:
					ruins._crates(key, side, _rng.randi_range(1, 3))
				elif _rng.randf() < 0.5:
					var x: float = ruins._spot(key, side, 0.85)
					if not is_nan(x):
						ruins._piece("barrels", ruins._against(key, side, x, 0.8, PI * 0.5), 0.72, Vector3(2.0, 1.1, 2.1) * 0.9)
				continue
			# Open walls: banners, candles at the foot, shackles and the dead.
			if not c["corner"] and _rng.randf() < 0.7 and ruins._reserve(key, side, 0.0, 0.7):
				ruins._banner(key, side, 0.0)
			if _rng.randf() < 0.45:
				var x: float = ruins._spot(key, side, 0.4)
				if not is_nan(x):
					ruins._candles(ruins._against(key, side, x, 0.3), _rng.randi_range(3, 7), _rng.randf() < 0.5)
			if _rng.randf() < 0.25:
				var x: float = ruins._spot(key, side, 0.35)
				if not is_nan(x):
					ruins._shackles(key, side, x)
			if c["corner"] and _rng.randf() < 0.6:
				ruins._crates(key, side, _rng.randi_range(1, 3))
			var walls: Array[int] = [side]
			ruins._rubble(key, walls, 1.0)

	# Roots crawling out across the floor from the heavy wall's foot.
	for w in _walls:
		if not w["heavy"]:
			continue
		var d: Vector3 = w["d"]
		var a: Vector3 = w["a"]
		for k in range(-1, 2):
			for j in _rng.randi_range(1, 2):
				var from := d * (_wall - 0.05) + a * (float(k) * _cell + _rng.randf_range(-1.0, 1.0))
				var dir := (-d + a * _rng.randf_range(-0.08, 0.08)).normalized()
				strands.append(ruins.floor_strand(to_global(from), global_basis * dir, _rng.randf_range(3.5, 6.0),
					_rng.randf_range(0.06, 0.12)))
				_count("floor roots")
	ruins._root_mesh(room["centre"], strands, live)

	# The open floor: the photo's places on the first hall, dealt out on the rest.
	var spots: Array = [Vector3(_cell, 0, _cell), Vector3(-_cell, 0, _cell), Vector3(_cell, 0, -_cell), Vector3(-_cell, 0, -_cell)]
	if not identical:
		_shuffle(spots)
	_fire_basket(spots[0])
	_pile(spots[1])
	_cart(spots[2])
	_hooks(spots[3])
	# Grates down the nave, either side of the beacon.
	for z: float in [_cell, -_cell]:
		_grate(Vector3(_rng.randf_range(-0.4, 0.4), 0.0, z + _rng.randf_range(-0.6, 0.6)))
	# A few fallen blocks.
	_blocks()
	solid.append_array(ruins.hall_end(first))


func _fire_basket(at: Vector3) -> void:
	var xf := global_transform * Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), at)
	var b: Node3D = ruins._piece("brazier", xf, 1.0, Vector3(0.8, 1.4, 0.8))
	if b == null:
		return
	ruins._coals(xf * Vector3(0.0, 1.38, 0.0))
	ruins._light(xf * Vector3(0.0, 1.9, 0.0), Color(1.0, 0.5, 0.2), 1.6, 5.5)
	ruins._candles(global_transform * Transform3D(Basis(), at + Vector3(0.9, 0.0, 0.4)), _rng.randi_range(2, 4), false)


## A heap of crates with a barrel store beside it.
func _pile(at: Vector3) -> void:
	var yaw := _rng.randf() * TAU
	for i in _rng.randi_range(3, 5):
		var kind := _rng.randi_range(0, Crate.SIZES.size() - 1)
		var off := Vector3(_rng.randf_range(-1.3, 1.3), 0.0, _rng.randf_range(-1.0, 1.0))
		var xf := global_transform * Transform3D(Basis(Vector3.UP, yaw + _rng.randf_range(-0.4, 0.4)), at + off)
		ruins._crate_at(xf, kind, null)
	ruins._piece("barrels", global_transform * Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0.0, 0.0, 1.5)), 0.72,
		Vector3(2.0, 1.1, 2.1) * 0.9)


## The big-wheeled cart, left standing.
func _cart(at: Vector3) -> void:
	ruins._piece("handcart", global_transform * Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.6, 0.6) + PI * 0.5), at),
		1.3, Vector3(1.8, 1.0, 1.0))
	if _rng.randf() < 0.6:
		ruins._crate_at(global_transform * Transform3D(Basis(Vector3.UP, _rng.randf() * TAU),
			at + Vector3(_rng.randf_range(-1.6, 1.6), 0.0, 1.5)), 1, null)


## Chains with big hooks from the vault, a wrapped body on one now and then.
func _hooks(at: Vector3) -> void:
	var key := _key(at)
	ruins._hooks(key, built.cells[key], _rng.randi_range(2, 3))
	for i in _rng.randi_range(1, 3):
		var p := global_transform * (at + Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5)))
		ruins._chain(Vector3(p.x, 4.95, p.z), _rng.randf_range(1.0, 2.2))


## A big iron grate in the flags: the cell kit's drain, scaled to 1.4 m.
func _grate(at: Vector3) -> void:
	var mesh := HoldingCell.kit_mesh("drain")
	if mesh == null:
		return
	var size := mesh.get_aabb().size
	var s := 1.4 / maxf(maxf(size.x, size.z), 0.01)
	var mi := MeshInstance3D.new()
	mi.name = "Grate"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis(Vector3.UP, PI * 0.5 * float(_rng.randi_range(0, 1))).scaled(Vector3(s, 1.0, s)), at)
	add_child(mi)
	_count("grates")


## Big blocks fallen out of the walls, at the foot of a few pilasters.
func _blocks() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	for w in _walls:
		if _rng.randf() > 0.6:
			continue
		var d: Vector3 = w["d"]
		var a: Vector3 = w["a"]
		var along := _cell * (0.5 if _rng.randf() < 0.5 else -0.5) * (3.0 if _rng.randf() < 0.5 else 1.0)
		var off := along + _rng.randf_range(1.3, 1.7) * signf(_rng.randf() - 0.5)
		# Never in a way in or before the winch.
		var k: int = clampi(roundi(off / _cell), -2, 2) + ((w["cells"].size() - 1) >> 1)
		var c: Dictionary = w["cells"][k]
		if c["entrance"] or int(w["winch"]) == k or _stair_cells.has(c["key"]):
			continue
		var base := d * (_wall - PILASTER_PROUD - 0.6) + a * off
		for i in _rng.randi_range(2, 4):
			var size := Vector3(_rng.randf_range(0.35, 0.75), _rng.randf_range(0.25, 0.5), _rng.randf_range(0.3, 0.6))
			var at := base + Vector3(_rng.randf_range(-0.5, 0.5), size.y * 0.42, _rng.randf_range(-0.5, 0.5))
			var bm := BoxMesh.new()
			bm.size = size
			st.append_from(bm, 0, Transform3D(Basis(Vector3(_rng.randf(), _rng.randf(), _rng.randf()).normalized(),
				_rng.randf_range(0.0, 0.35)), at))
			n += 1
		_solid_box(Transform3D(Basis(), base + Vector3(0.0, 0.3, 0.0)), Vector3(1.4, 0.6, 1.4))
		solid.append({"at": to_global(base), "half": Vector2(0.7, 0.7)})
	if n == 0:
		return
	var mi := MeshInstance3D.new()
	mi.name = "FallenBlocks"
	mi.mesh = st.commit()
	mi.material_override = Morgue._mat(&"core")
	add_child(mi)
	_count("fallen blocks", n)


## Loot lying about (note 181, the user: "The player should be able to find
## health potions here scattered around, along with other loot"): a health
## potion and a pile of coins up on the balconies, small potions, coins and a
## gold crystal along the walls, now and then a robot rat; on the photo's table a
## small potion. Laid down as the containment rooms' coins are (item_drop.gd,
## "lying"); what is taken stays taken in the save (maze.gd "scoutpost_loot").
const LOOT := [[&"health_potion", 1], [&"coins", 0], [&"small_health_potion", 1],
	[&"small_health_potion", 1], [&"coins", 0], [&"coins", 0], [&"gold_crystal", 1]]


func _scatter_loot() -> void:
	var ground: Array[Vector3] = []
	for w in _walls:
		var d: Vector3 = w["d"]
		var a: Vector3 = w["a"]
		for i in w["cells"].size():
			var c: Dictionary = w["cells"][i]
			if c["corner"] or c["entrance"] or int(w["winch"]) == i or _stair_cells.has(c["key"]):
				continue
			ground.append(d * (_ring - 1.0) + a * (float(c["along"]) + _rng.randf_range(-1.0, 1.0)) + Vector3(0.0, 0.25, 0.0))
	_shuffle(ground)
	var high := _loot_spots.duplicate()
	_shuffle(high)
	var items: Array = LOOT.duplicate()
	if _rng.randf() < 0.25:
		items.append([&"robot_rat", 1])
	var drops = load("res://scripts/item_drop.gd")
	for i in items.size():
		var at := Vector3.INF
		# The first two -- the potion and a pile of coins -- up on a balcony.
		if i < 2 and not high.is_empty():
			at = high.pop_back()
		elif i == 2 and _table_spot != Vector3.INF:
			at = _table_spot
		elif not ground.is_empty():
			at = ground.pop_back()
		if at == Vector3.INF:
			continue
		var drop := Node3D.new()
		drop.set_script(drops)
		drop.set("id", items[i][0])
		drop.set("count", _rng.randi_range(4, 12) if int(items[i][1]) == 0 else int(items[i][1]))
		drop.set_meta("lying", true)
		drop.name = "Loot%d" % i
		add_child(drop)
		drop.position = at
		drop.tree_exiting.connect(_on_loot_gone.bind(i, drop))
		loot.append(drop)
		_count("loot")


## Picked up (it is freed when it reaches the player), not the level going away.
func _on_loot_gone(i: int, drop: Node) -> void:
	if drop.is_queued_for_deletion() and not loot_taken.has(i):
		loot_taken.append(i)


## From a save: what was taken is gone again.
func take_loot(taken: Array) -> void:
	for t in taken:
		var i := int(t)
		if i < loot.size() and is_instance_valid(loot[i]):
			loot[i].queue_free()
		if not loot_taken.has(i):
			loot_taken.append(i)


## Everything here stops drawing past the fog, as the morgue's does.
static func _draw_to(node: Node3D) -> void:
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		if gi.visibility_range_end > 0.0:
			continue
		gi.visibility_range_end = DRAWN_TO + (20.0 if gi is MultiMeshInstance3D else 0.0)
		gi.visibility_range_end_margin = 4.0
