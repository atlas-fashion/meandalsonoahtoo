extends RefCounted

## The boss room (2026-10-06): a grand stair from the boss room's one doorway,
## up above the corridor roofs, to a throne hall that is free of the 6 m grid.
##
## Laid out from `module_level.plan_boss_hall` -- read that first. Everything
## here is placed in the stair's own frame: `u` across it, `v` from the doorway
## inward, `y` up. The hall is open to the blood-red sky, like the courts were:
## a ruined throne hall.
##
## The dressing is PLACEHOLDER geometry, named for what replaces it, until the
## Tripo pieces arrive: "Throne", "Dais", "Columns", "Braziers", "Banners".
## The gameplay parts are final -- the collision, the stair ramps, the
## portcullis spot, the wall that keeps the boss in, the boss's spot and the
## "ThroneSeat" marker -- and swapping a model in does not move any of them.
##
## Collision:
##   floor slab, stairs, dais   layers 1+2  everyone stands on it; blocks sight
##   walls, columns             2+9+10      sight, the player, enemies + navmesh
##   throne                     9           the PLAYER only: the boss sits in it
##   boss wall                  11          the boss only, across the hall's arch
## Stairs are RAMPS under the steps, a half tread back from the noses: the
## player's capsule cannot climb 19 cm steps, and the navmesh needs a slope.

const ModuleLevel := preload("res://scripts/module_level.gd")
const TORCH := preload("res://scenes/torch.tscn")

const LAYER_WORLD := 1 | 2
const LAYER_SOLID := 2 | 256 | 512
const LAYER_PLAYER_ONLY := 256
## Same as maze.gd BOSS_WALL_LAYER.
const LAYER_BOSS_WALL := 1 << 10

const SLAB := 1.4
const HALL_WALL_HEIGHT := 14.0
## The arch from the stair into the hall: the stair's width, this tall.
const ARCH_HEIGHT := 8.0
const STAIR_WALL := 1.2
## The stair's side walls stand this far above the hall floor at the top.
const PARAPET := 1.4
## The doorway at the bottom, where the corridor's archway meets the stairwell.
const DOOR_WIDTH := 3.6
const DOOR_HEIGHT := 4.0

## The dais the throne stands on, at the far end of the hall.
const DAIS_WIDTH := 16.0
const DAIS_STEPS := 12
const DAIS_RISE := 0.2
const DAIS_TREAD := 0.5
const DAIS_TOP_DEPTH := 6.0
const DAIS_BACK_GAP := 1.0

## The throne, sized for a boss about 5 m tall (boss.tscn's capsule).
const SEAT_WIDTH := 3.4
const SEAT_DEPTH := 2.8
const SEAT_HEIGHT := 1.8
const BACK_HEIGHT := 7.5

const COLUMN_RADIUS := 0.85
const COLUMN_PITCH := 8.0
const CARPET_WIDTH := 3.4

const CRIMSON := Color(0.13, 0.012, 0.016)
## The sky over the hall. The courts' 22 blew the red carpet and the paving out
## to flat scarlet here: 14 m walls hold the light in, and there is more floor.
const HALL_SKY_ENERGY := 10.0
const PALE_GOLD := Color(0.86, 0.76, 0.5)


## The stair's frame: a point is door + across * u + up * y + into * v.
class Frame extends RefCounted:
	var door: Vector3
	var across: Vector3
	var into: Vector3
	var basis: Basis

	func _init(plan: Dictionary) -> void:
		door = plan["door"]
		across = plan["across"]
		into = plan["into"]
		basis = Basis(across, Vector3.UP, into)

	func p(u: float, y: float, v: float) -> Vector3:
		return door + across * u + Vector3.UP * y + into * v

	func at(u: float, y: float, v: float) -> Transform3D:
		return Transform3D(basis, p(u, y, v))


## Builds the stair and the hall under `parent` (the level, under NavRegion, so
## the navmesh bakes it). Returns what the gameplay needs, all in world space:
##   seat        Transform3D  the throne's seat, facing the doorway (-Z out)
##   boss_spot   Vector3      where the boss waits, on the dais before the seat
##   boss_yaw    float        rotation.y for him to face the doorway
##   zone_centre / zone_extents  the hall's interior, for his guarded zone
##   gate        Transform3D  the portcullis in the hall's arch (local Z through it)
##   gate_size   Vector2      its width and height
##   stair       {u0, u1, v0, v1}  the stairwell's walkable channel, for the grid
##   bench       {centre, edge}  benchmark stations on the hall floor
static func build(parent: Node3D, out, tint: float, detail: float, torch_energy: float) -> Dictionary:
	var plan: Dictionary = out.boss_hall
	if plan.is_empty():
		return {}
	var f := Frame.new(plan)
	var root := Node3D.new()
	root.name = "BossHall"
	parent.add_child(root)

	var y_top: float = plan["floor_y"]
	var sw: float = plan["stair_width"]
	var t: float = plan["tread"]
	var r: float = plan["rise"]
	var steps: int = plan["steps"]
	var lead: float = plan["lead"]
	var landing: float = plan["landing"]
	var top: float = plan["top"]
	var wall: float = plan["wall"]
	var hw: float = float(plan["width"]) * 0.5
	var depth: float = plan["depth"]
	var flight := float(steps) * t
	var y_mid := y_top * 0.5

	var stone := ModuleLevel._synth_arch_material(tint).duplicate() as StandardMaterial3D
	# These meshes carry no vertex colours; with it on they render black.
	stone.vertex_color_use_as_albedo = false
	var paving := _paving(tint)

	var world := _body(root, "HallFloor", LAYER_WORLD)
	var solid := _body(root, "HallWalls", LAYER_SOLID)
	var player_only := _body(root, "ThroneCollision", LAYER_PLAYER_ONLY)
	var boss_wall := _body(root, "BossHallWall", LAYER_BOSS_WALL)

	var walls: Array = []
	var floors: Array = []

	# --- The stair ------------------------------------------------------------
	# Side walls, from the doorway up to the hall's front wall.
	var wall_h := y_top + PARAPET
	for s: float in [-1.0, 1.0]:
		var u := s * (sw * 0.5 + STAIR_WALL * 0.5)
		_box(walls, solid, f, Vector3(STAIR_WALL, wall_h, top), Vector3(u, wall_h * 0.5, top * 0.5))
	# The facade at the bottom, round the corridor's archway.
	var side_w := (sw - DOOR_WIDTH) * 0.5
	for s: float in [-1.0, 1.0]:
		_box(walls, solid, f, Vector3(side_w, wall_h, 0.6),
			Vector3(s * (DOOR_WIDTH * 0.5 + side_w * 0.5), wall_h * 0.5, 0.3))
	_box(walls, solid, f, Vector3(DOOR_WIDTH, wall_h - DOOR_HEIGHT, 0.6),
		Vector3(0.0, DOOR_HEIGHT + (wall_h - DOOR_HEIGHT) * 0.5, 0.3))
	# The steps, each a solid block down to the ground; the landing between.
	for i in steps:
		_box(floors, null, f, Vector3(sw, r * float(i + 1), t),
			Vector3(0.0, r * float(i + 1) * 0.5, lead + t * (float(i) + 0.5)))
	_box(floors, null, f, Vector3(sw, y_mid, landing), Vector3(0.0, y_mid * 0.5, lead + flight + landing * 0.5))
	var v2 := lead + flight + landing
	for i in steps:
		var h := y_mid + r * float(i + 1)
		_box(floors, null, f, Vector3(sw, h, t), Vector3(0.0, h * 0.5, v2 + t * (float(i) + 0.5)))
	# What the feet actually walk on: ramps half a tread behind the noses.
	_ramp(world, f, sw, lead - t * 0.5, 0.0, lead + flight - t * 0.5, y_mid)
	_add_box(world, f, Vector3(sw, 0.4, landing), Vector3(0.0, y_mid - 0.2, lead + flight - t * 0.5 + landing * 0.5))
	_ramp(world, f, sw, v2 - t * 0.5, y_mid, top - t * 0.5, y_top)
	_add_box(world, f, Vector3(sw, 0.4, t * 0.5 + 0.05), Vector3(0.0, y_top - 0.2, top - t * 0.25))
	# Floor of the bottom landing, in from the doorway.
	_box(floors, world, f, Vector3(sw, 0.2, lead + 0.2), Vector3(0.0, -0.1, (lead + 0.2) * 0.5))

	# --- The hall ---------------------------------------------------------------
	var outer_w := hw * 2.0 + wall * 2.0
	var v_in := top + wall
	var v_back := top + depth
	var mesh_floor: Array = []
	_box(mesh_floor, world, f, Vector3(outer_w, SLAB, depth + wall),
		Vector3(0.0, y_top - SLAB * 0.5, top + (depth + wall) * 0.5))
	var wall_bottom := y_top - SLAB
	var wall_total := HALL_WALL_HEIGHT + SLAB
	var wall_mid := wall_bottom + wall_total * 0.5
	for s: float in [-1.0, 1.0]:
		_box(walls, solid, f, Vector3(wall, wall_total, depth + wall),
			Vector3(s * (hw + wall * 0.5), wall_mid, top + (depth + wall) * 0.5))
	_box(walls, solid, f, Vector3(outer_w, wall_total, wall), Vector3(0.0, wall_mid, v_back + wall * 0.5))
	# The front wall, round the arch the stair comes up through.
	var front_side := (outer_w - sw) * 0.5
	for s: float in [-1.0, 1.0]:
		_box(walls, solid, f, Vector3(front_side, wall_total, wall),
			Vector3(s * (sw * 0.5 + front_side * 0.5), wall_mid, top + wall * 0.5))
	var lintel := wall_total - SLAB - ARCH_HEIGHT
	_box(walls, solid, f, Vector3(sw, lintel, wall),
		Vector3(0.0, y_top + ARCH_HEIGHT + lintel * 0.5, top + wall * 0.5))
	# Keeps the boss in the hall: across the arch, just inside it.
	_add_box(boss_wall, f, Vector3(sw + 1.0, ARCH_HEIGHT, 0.5), Vector3(0.0, y_top + ARCH_HEIGHT * 0.5, v_in + 0.25))

	# Columns down both sides -- the cover the old courtyard's pillars gave.
	var col_u := hw - 5.0
	var col_v0 := v_in + 6.0
	var col_v1 := v_back - DAIS_TOP_DEPTH - float(DAIS_STEPS) * DAIS_TREAD - DAIS_BACK_GAP - 3.0
	var columns := Node3D.new()
	columns.name = "Columns"
	root.add_child(columns)
	var column_mesh := _column_mesh(stone)
	var v := col_v0
	while v <= col_v1 + 0.01:
		for s: float in [-1.0, 1.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = column_mesh
			mi.transform = f.at(s * col_u, y_top, v)
			columns.add_child(mi)
			var shape := CylinderShape3D.new()
			shape.radius = COLUMN_RADIUS + 0.1
			shape.height = HALL_WALL_HEIGHT
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.position = f.p(s * col_u, y_top + HALL_WALL_HEIGHT * 0.5, v)
			solid.add_child(cs)
		v += COLUMN_PITCH

	# --- The dais and the throne -------------------------------------------------
	var dais_h := DAIS_RISE * float(DAIS_STEPS)
	var dais_back := v_back - DAIS_BACK_GAP
	var dais_top_v := dais_back - DAIS_TOP_DEPTH
	var dais_v0 := dais_top_v - float(DAIS_STEPS) * DAIS_TREAD
	var dais: Array = []
	for i in DAIS_STEPS:
		var h := DAIS_RISE * float(i + 1)
		_box(dais, null, f, Vector3(DAIS_WIDTH, h, DAIS_TREAD),
			Vector3(0.0, y_top + h * 0.5, dais_v0 + DAIS_TREAD * (float(i) + 0.5)))
	_box(dais, null, f, Vector3(DAIS_WIDTH, dais_h, DAIS_TOP_DEPTH),
		Vector3(0.0, y_top + dais_h * 0.5, dais_top_v + DAIS_TOP_DEPTH * 0.5))
	_ramp(world, f, DAIS_WIDTH, dais_v0 - DAIS_TREAD * 0.5, y_top, dais_top_v - DAIS_TREAD * 0.5, y_top + dais_h)
	_add_box(world, f, Vector3(DAIS_WIDTH, dais_h, DAIS_TOP_DEPTH + DAIS_TREAD * 0.5),
		Vector3(0.0, y_top + dais_h * 0.5, dais_top_v - DAIS_TREAD * 0.5 + (DAIS_TOP_DEPTH + DAIS_TREAD * 0.5) * 0.5))
	_add_mesh(root, "Dais", _merged(dais, stone))

	var throne_v := dais_back - SEAT_DEPTH * 0.5 - 0.6
	var throne_y := y_top + dais_h
	_add_mesh(root, "Throne", _throne_placeholder(f, throne_v, throne_y))
	_add_box(player_only, f, Vector3(SEAT_WIDTH + 1.4, SEAT_HEIGHT + BACK_HEIGHT, SEAT_DEPTH + 0.8),
		Vector3(0.0, throne_y + (SEAT_HEIGHT + BACK_HEIGHT) * 0.5, throne_v + 0.2))
	var seat_marker := Marker3D.new()
	seat_marker.name = "ThroneSeat"
	root.add_child(seat_marker)
	# -Z of the marker looks back down the hall at the doorway.
	seat_marker.global_transform = Transform3D(f.basis, f.p(0.0, throne_y + SEAT_HEIGHT, throne_v - 0.2))

	# --- Carpet, braziers, banners, lights -----------------------------------------
	var carpet_len := dais_v0 - v_in
	var carpet := StandardMaterial3D.new()
	carpet.albedo_color = CRIMSON
	carpet.roughness = 1.0
	carpet.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	var trim := StandardMaterial3D.new()
	trim.albedo_color = PALE_GOLD * 0.7
	trim.metallic = 0.6
	trim.roughness = 0.5
	var cloth: Array = []
	_box(cloth, null, f, Vector3(CARPET_WIDTH, 0.03, carpet_len), Vector3(0.0, y_top + 0.015, v_in + carpet_len * 0.5))
	_add_mesh(root, "Carpet", _merged(cloth, carpet))
	var trims: Array = []
	for s: float in [-1.0, 1.0]:
		_box(trims, null, f, Vector3(0.12, 0.035, carpet_len),
			Vector3(s * (CARPET_WIDTH * 0.5 - 0.15), y_top + 0.018, v_in + carpet_len * 0.5))
	_add_mesh(root, "CarpetTrim", _merged(trims, trim))

	var banners: Array = []
	var banner_trim: Array = []
	for s: float in [-1.0, 1.0]:
		var bu := s * (SEAT_WIDTH * 0.5 + 3.5)
		_box(banners, null, f, Vector3(2.6, 8.0, 0.06), Vector3(bu, y_top + 10.5 - 4.0, v_back - 0.05))
		_box(banner_trim, null, f, Vector3(3.0, 0.12, 0.12), Vector3(bu, y_top + 10.6, v_back - 0.1))
	_add_mesh(root, "Banners", _merged(banners, carpet))
	_add_mesh(root, "BannerRods", _merged(banner_trim, trim))

	var braziers := Node3D.new()
	braziers.name = "Braziers"
	root.add_child(braziers)
	var spots: Array[Vector3] = [
		f.p(-(DAIS_WIDTH * 0.5 + 1.6), y_top, dais_v0 - 0.5),
		f.p(DAIS_WIDTH * 0.5 + 1.6, y_top, dais_v0 - 0.5),
	]
	if detail >= 0.5:
		spots.append(f.p(-(sw * 0.5 + 2.2), y_top, v_in + 2.0))
		spots.append(f.p(sw * 0.5 + 2.2, y_top, v_in + 2.0))
	for spot in spots:
		_brazier(braziers, spot)

	var torches := Node3D.new()
	torches.name = "HallTorches"
	root.add_child(torches)
	# Between the columns on both long walls, and two up each side of the stair.
	v = col_v0 + COLUMN_PITCH * 0.5
	while v < col_v1:
		for s: float in [-1.0, 1.0]:
			ModuleLevel._hang_torch(torches, TORCH, f.p(s * (hw - 0.12), y_top + 3.2, v),
				f.across * s, torch_energy, ModuleLevel.TORCH_RANGE)
		v += COLUMN_PITCH * 2.0
	for k in 2:
		var sv := lead + flight * 0.5 + float(k) * (flight + landing)
		var sy := (y_mid * 0.5 if k == 0 else y_mid * 1.5) + 2.2
		for s: float in [-1.0, 1.0]:
			ModuleLevel._hang_torch(torches, TORCH, f.p(s * (sw * 0.5 - 0.12), sy, sv),
				f.across * s, torch_energy, ModuleLevel.TORCH_RANGE)

	# The sky over the hall, as over the courts (see place_room_lights).
	var sky := Node3D.new()
	sky.name = "HallSkyLights"
	root.add_child(sky)
	for i in 2:
		for j in 2:
			var light := OmniLight3D.new()
			light.light_color = ModuleLevel.SKY_LIGHT_COLOUR
			light.light_energy = HALL_SKY_ENERGY
			light.omni_range = maxf(hw, (depth - wall) * 0.5) * 1.5
			light.omni_attenuation = 0.75
			light.light_specular = 0.0
			light.shadow_enabled = false
			light.distance_fade_enabled = true
			light.distance_fade_begin = 55.0
			light.distance_fade_length = 15.0
			sky.add_child(light)
			light.global_position = f.p((float(i) - 0.5) * hw, y_top + ModuleLevel.SKY_LIGHT_HEIGHT,
				v_in + (depth - wall) * (0.25 + 0.5 * float(j)))

	_add_mesh(root, "HallWalls", _merged(walls, stone))
	_add_mesh(root, "Stair", _merged(floors, stone))
	_add_mesh(root, "HallFloor", _merged(mesh_floor, paving))

	# --- What the game needs ---------------------------------------------------------
	var interior_d := depth - wall
	var hall_centre := f.p(0.0, y_top, v_in + interior_d * 0.5)
	var along_x := absf(f.into.x) > 0.5
	var half_w_zone := hw - 0.5
	var half_d_zone := interior_d * 0.5 - 0.5
	var extents := Vector3(half_d_zone if along_x else half_w_zone, 4.0, half_w_zone if along_x else half_d_zone)
	var boss_spot := f.p(0.0, throne_y + 0.1, throne_v - SEAT_DEPTH * 0.5 - 1.4)
	var face := -f.into
	return {
		"seat": seat_marker.global_transform,
		"boss_spot": boss_spot,
		"boss_yaw": atan2(-face.x, -face.z),
		"zone_centre": hall_centre + Vector3(0.0, 2.0, 0.0),
		"zone_extents": extents,
		"gate": Transform3D(Basis(Vector3.UP, atan2(f.into.x, f.into.z)), f.p(0.0, y_top, top + wall * 0.5)),
		"gate_size": Vector2(sw, ARCH_HEIGHT),
		"stair": {"u0": -sw * 0.5, "u1": sw * 0.5, "v0": 0.0, "v1": top},
		"frame": f,
		"floor_y": y_top,
		"bench": {
			"centre": hall_centre,
			"edge": f.p(hw - 3.0, y_top, v_in + 3.0),
		},
	}


# --- Building blocks ---------------------------------------------------------------

static func _body(parent: Node3D, name: String, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = layer
	body.collision_mask = 0
	parent.add_child(body)
	return body


## Queues a box for a merged mesh (`list`) and, given a body, its collision.
static func _box(list: Array, body: StaticBody3D, f: Frame, size: Vector3, centre: Vector3) -> void:
	list.append([size, f.at(centre.x, centre.y, centre.z)])
	if body != null:
		_add_box(body, f, size, centre)


static func _add_box(body: StaticBody3D, f: Frame, size: Vector3, centre: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = f.at(centre.x, centre.y, centre.z)
	body.add_child(cs)


## A wedge whose top runs from (v0, y0) to (v1, y1), the full `width` across.
static func _ramp(body: StaticBody3D, f: Frame, width: float, v0: float, y0: float, v1: float, y1: float) -> void:
	var pts := PackedVector3Array()
	for u: float in [-width * 0.5, width * 0.5]:
		pts.append(f.p(u, y0, v0))
		pts.append(f.p(u, y1, v1))
		pts.append(f.p(u, y0 - 0.3, v1))
		pts.append(f.p(u, y0 - 0.3, v0))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


## One mesh from many boxes: [size, transform] each.
static func _merged(boxes: Array, material: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var unit := BoxMesh.new()
	for b in boxes:
		var size: Vector3 = b[0]
		var xf: Transform3D = b[1]
		unit.size = size
		st.append_from(unit, 0, xf)
	st.set_material(material)
	return st.commit()


static func _add_mesh(parent: Node3D, name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## The courts' paving, world triplanar, for the hall's floor.
static func _paving(tint: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(ModuleLevel.COURT_ALBEDO)
	mat.normal_enabled = true
	mat.normal_texture = load(ModuleLevel.COURT_NORMAL)
	mat.normal_scale = 1.4
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * ModuleLevel.COURT_SCALE
	mat.albedo_color = Color(0.72 * tint, 0.72 * tint, 0.74 * tint)
	mat.roughness = 0.95
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


## PLACEHOLDER for the Tripo column: an eight-sided shaft on a plinth under a
## block capital, the hall's full height.
static func _column_mesh(stone: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shaft := CylinderMesh.new()
	shaft.top_radius = COLUMN_RADIUS
	shaft.bottom_radius = COLUMN_RADIUS
	shaft.height = HALL_WALL_HEIGHT - 2.0
	shaft.radial_segments = 8
	shaft.rings = 1
	st.append_from(shaft, 0, Transform3D(Basis(), Vector3(0.0, 1.0 + shaft.height * 0.5, 0.0)))
	var block := BoxMesh.new()
	block.size = Vector3(2.4, 1.0, 2.4)
	st.append_from(block, 0, Transform3D(Basis(), Vector3(0.0, 0.5, 0.0)))
	block.size = Vector3(2.2, 1.0, 2.2)
	st.append_from(block, 0, Transform3D(Basis(), Vector3(0.0, HALL_WALL_HEIGHT - 0.5, 0.0)))
	st.set_material(stone)
	return st.commit()


## PLACEHOLDER for the Tripo throne: seat, tall back, arms and three spires in
## pale gold, sized for the 5 m boss.
static func _throne_placeholder(f: Frame, v_c: float, y0: float) -> ArrayMesh:
	var parts: Array = []
	var half_d := SEAT_DEPTH * 0.5
	_box(parts, null, f, Vector3(SEAT_WIDTH, SEAT_HEIGHT, SEAT_DEPTH), Vector3(0.0, y0 + SEAT_HEIGHT * 0.5, v_c))
	var back_y := y0 + SEAT_HEIGHT + BACK_HEIGHT * 0.5 - 0.6
	_box(parts, null, f, Vector3(SEAT_WIDTH + 0.4, BACK_HEIGHT + 1.2, 0.7), Vector3(0.0, back_y, v_c + half_d + 0.1))
	for s: float in [-1.0, 1.0]:
		_box(parts, null, f, Vector3(0.6, SEAT_HEIGHT + 1.0, SEAT_DEPTH),
			Vector3(s * (SEAT_WIDTH * 0.5 + 0.3), y0 + (SEAT_HEIGHT + 1.0) * 0.5, v_c))
		_box(parts, null, f, Vector3(0.35, 2.2, 0.35),
			Vector3(s * (SEAT_WIDTH * 0.5 - 0.1), y0 + SEAT_HEIGHT + BACK_HEIGHT + 1.1, v_c + half_d + 0.1))
	_box(parts, null, f, Vector3(0.45, 3.2, 0.45), Vector3(0.0, y0 + SEAT_HEIGHT + BACK_HEIGHT + 1.6, v_c + half_d + 0.1))
	_box(parts, null, f, Vector3(SEAT_WIDTH + 1.6, 0.35, 1.4), Vector3(0.0, y0 + 0.175, v_c - half_d - 0.7))
	var gold := StandardMaterial3D.new()
	gold.albedo_color = PALE_GOLD
	gold.metallic = 0.85
	gold.roughness = 0.32
	return _merged(parts, gold)


## A brazier: an iron stand and bowl (PLACEHOLDER for the Tripo brazier) holding
## a wall torch's fire -- the same flame card, flicker, embers and light, with
## the bracket hidden and the fire made big.
static func _brazier(parent: Node3D, at: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "Brazier"
	parent.add_child(holder)
	holder.global_position = at
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.06, 0.05, 0.045)
	iron.metallic = 0.6
	iron.roughness = 0.6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stand := CylinderMesh.new()
	stand.top_radius = 0.12
	stand.bottom_radius = 0.3
	stand.height = 1.5
	stand.radial_segments = 8
	st.append_from(stand, 0, Transform3D(Basis(), Vector3(0.0, 0.75, 0.0)))
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.75
	bowl.bottom_radius = 0.35
	bowl.height = 0.45
	bowl.radial_segments = 12
	st.append_from(bowl, 0, Transform3D(Basis(), Vector3(0.0, 1.72, 0.0)))
	st.set_material(iron)
	_add_mesh(holder, "Stand", st.commit())

	var fire := TORCH.instantiate() as Node3D
	fire.name = "Fire"
	# A brazier's fire: no torch body under it.
	fire.set("kit_mount", false)
	fire.position = Vector3(0.0, 1.95, 0.0)
	fire.set("base_energy", 3.2)
	fire.set("light_range", 14.0)
	holder.add_child(fire)
	for part in ["Plate", "Arm", "Ring", "Handle", "Head"]:
		var n := fire.get_node_or_null(part) as Node3D
		if n != null:
			n.visible = false
	for part: Array in [["Flame", 0.85, 2.4], ["Halo", 1.1, 2.6], ["Embers", 0.6, 2.0]]:
		var n := fire.get_node_or_null(String(part[0])) as Node3D
		if n != null:
			n.position = Vector3(0.0, float(part[1]), 0.0)
			n.scale = Vector3.ONE * float(part[2])
	var light := fire.get_node_or_null("Light") as OmniLight3D
	if light != null:
		light.position = Vector3(0.0, 1.4, 0.0)
		light.shadow_enabled = false
		light.light_specular = 0.0
		light.light_color = ModuleLevel.TORCH_COLOUR
