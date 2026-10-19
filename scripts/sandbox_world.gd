extends Node3D

## The SANDBOX's world (sandbox.gd, 2026-10-17), a child of the maze, built
## only in a sandbox session: a flat, lit test plane well outside the level
## (where the player starts and rises after a death), the enemies spawned from
## the sandbox menu, and the places it teleports to. The menu itself is
## scripts/sandbox_menu.gd.
##
## The plane: PLANE_SIZE square at PLANE_ORIGIN, a grid of 1 m lines with a
## stronger line every 10 m, lit by a few shadowless lights overhead (the
## dungeon's darkness and fog are the world's own), with its own navmesh baked
## from its floor. Nothing on it.
##
## Spawned enemies are children of this node, not the maze's population: a
## death does not clear them (the maze resets only its own), "Clear spawned"
## does. They are made the way the maze makes each kind (maze.gd `_spawn_*`).

const PLANE_ORIGIN := Vector3(1500.0, 0.0, 0.0)
const PLANE_SIZE := 160.0
## Lights over the plane: a LIGHTS_ACROSS square grid, LIGHT_HEIGHT up.
const LIGHTS_ACROSS := 3
const LIGHT_HEIGHT := 24.0
const LIGHT_RANGE := 70.0
const LIGHT_ENERGY := 2.2
## Spawned this far in front of the player, spread SPAWN_SPREAD apart.
const SPAWN_AHEAD := 7.0
const SPAWN_SPREAD := 2.6

const ARCHER_SCRIPT := preload("res://scripts/archer.gd")
const ENFORCER_SCRIPT := preload("res://scripts/enforcer.gd")
const DECREPIT_SCRIPT := preload("res://scripts/decrepit.gd")
const LIZARD_SCRIPT := preload("res://scripts/sewer_lizard.gd")
const STALKER_SCRIPT := preload("res://scripts/stalker.gd")
const RAT_SCRIPT := preload("res://scripts/rat.gd")

## What the menu offers: id -> label. Kept in this order.
const KINDS := [
	[&"skeleton_sword", "Skeleton (sword)"],
	[&"skeleton_pick", "Skeleton (pick)"],
	[&"archer", "Skeleton archer"],
	[&"enforcer", "Enforcer"],
	[&"crier", "Crier"],
	[&"decrepit", "Decrepit enforcer"],
	[&"lizard", "Sewer lizard"],
	[&"stalker", "The Remnant"],
	[&"mimic", "Mimic (press E on it)"],
	[&"boss", "The Warden (boss)"],
	[&"rat", "Rat (harmless; E to grab)"],
]

var maze: Node3D
var spawned: Array[Node] = []
var _nav: NavigationRegion3D


## Builds the plane. Called by the maze before its own navmesh bake.
func build(owner_maze: Node3D) -> void:
	maze = owner_maze
	name = "Sandbox"
	_build_plane()


func spawn_point() -> Vector3:
	return PLANE_ORIGIN + Vector3(0.0, 0.3, PLANE_SIZE * 0.25)


func _build_plane() -> void:
	_nav = NavigationRegion3D.new()
	_nav.name = "SandboxNav"
	add_child(_nav)
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1 | 2
	floor_body.collision_mask = 0
	floor_body.position = PLANE_ORIGIN + Vector3(0.0, -0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(PLANE_SIZE, 1.0, PLANE_SIZE)
	shape.shape = box
	floor_body.add_child(shape)
	_nav.add_child(floor_body)
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(PLANE_SIZE, PLANE_SIZE)
	mi.mesh = plane
	mi.position = PLANE_ORIGIN
	mi.material_override = _grid_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var step := PLANE_SIZE / float(LIGHTS_ACROSS)
	for ix in LIGHTS_ACROSS:
		for iz in LIGHTS_ACROSS:
			var light := OmniLight3D.new()
			light.position = PLANE_ORIGIN + Vector3((ix + 0.5) * step - PLANE_SIZE * 0.5, LIGHT_HEIGHT,
				(iz + 0.5) * step - PLANE_SIZE * 0.5)
			light.omni_range = LIGHT_RANGE
			light.omni_attenuation = 0.6
			light.light_energy = LIGHT_ENERGY
			light.light_color = Color(0.96, 0.93, 0.86)
			light.shadow_enabled = false
			add_child(light)
	# Its own navmesh, from its own floor: the maze's settings (cell size, the
	# agents' radius), so the two regions share one navigation map.
	var nm: NavigationMesh
	var maze_nav = maze.get("nav_region")
	if maze_nav != null and maze_nav.navigation_mesh != null:
		nm = maze_nav.navigation_mesh.duplicate()
	else:
		nm = NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 2
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	_nav.navigation_mesh = nm
	_nav.bake_navigation_mesh(true)


func _grid_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 base_col = vec3(0.32, 0.31, 0.30);
uniform vec3 line_col = vec3(0.12, 0.11, 0.105);
uniform vec3 major_col = vec3(0.55, 0.36, 0.22);
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float grid_line(vec2 p, float spacing, float width) {
	vec2 g = abs(fract(p / spacing - 0.5) - 0.5) * spacing;
	vec2 w = fwidth(p) * width;
	vec2 l = 1.0 - smoothstep(vec2(0.0), w, g);
	return max(l.x, l.y);
}
void fragment() {
	float minor = grid_line(world_pos.xz, 1.0, 1.0);
	float major = grid_line(world_pos.xz, 10.0, 2.0);
	vec3 c = mix(base_col, line_col, minor * 0.8);
	ALBEDO = mix(c, major_col, major);
	ROUGHNESS = 0.9;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


# --- Spawning ------------------------------------------------------------------------

## Spawns `count` of `kind` in a row across the player's view, SPAWN_AHEAD in
## front of them, each dropped onto whatever floor is there. Returns them.
func spawn(kind: StringName, count: int) -> Array[Node]:
	var out: Array[Node] = []
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return out
	var fwd := -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP)
	for i in count:
		var lateral := (float(i) - float(count - 1) * 0.5) * SPAWN_SPREAD
		var at := _floor_at(player.global_position + fwd * SPAWN_AHEAD + side * lateral)
		var e := _make(kind, at)
		if e == null:
			continue
		# Facing the player.
		if e is Node3D:
			var to := player.global_position - (e as Node3D).global_position
			(e as Node3D).rotation.y = atan2(-to.x, -to.z)
		spawned.append(e)
		out.append(e)
	if not out.is_empty():
		Graphics.apply_all.call_deferred()
	return out


## Frees every enemy spawned here.
func clear_spawned() -> int:
	var n := 0
	for e in spawned:
		if is_instance_valid(e):
			e.queue_free()
			n += 1
	spawned.clear()
	return n


func alive_count() -> int:
	var n := 0
	for e in spawned:
		if is_instance_valid(e) and e.get("_dying") != true:
			n += 1
	return n


## The floor under `p` (a ray from above), or `p` itself.
func _floor_at(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0.0, 3.0, 0.0), p + Vector3(0.0, -8.0, 0.0), 1 | 2)
	var hit := space.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else p


## One `kind`, made as the maze makes it, at `at`.
func _make(kind: StringName, at: Vector3) -> Node:
	var enemy_scene: PackedScene = maze.get("enemy_scene")
	var aggro: float = maze.get("enemy_aggro_range")
	match kind:
		&"skeleton_sword", &"skeleton_pick":
			var e: CharacterBody3D = enemy_scene.instantiate()
			# Armed and placed before it enters the tree (its home is taken
			# in _ready; the weapon is built then).
			e.set("armed", true)
			e.set("weapon", &"pick" if kind == &"skeleton_pick" else &"sword")
			e.position = at + Vector3(0.0, 0.1, 0.0)
			add_child(e)
			e.set("aggro_range", aggro)
			return e
		&"archer":
			var e: CharacterBody3D = enemy_scene.instantiate()
			e.set_script(ARCHER_SCRIPT)
			e.position = at + Vector3(0.0, 0.1, 0.0)
			add_child(e)
			e.set("aggro_range", aggro)
			return e
		&"enforcer":
			var e: CharacterBody3D = enemy_scene.instantiate()
			e.set_script(ENFORCER_SCRIPT)
			e.position = at + Vector3(0.0, 0.1, 0.0)
			add_child(e)
			e.set("aggro_range", 22.0)
			return e
		&"crier":
			var flyer: PackedScene = maze.get("flyer_scene")
			var e: Node3D = flyer.instantiate()
			e.position = at + Vector3(0.0, 1.6, 0.0)
			add_child(e)
			return e
		&"decrepit", &"lizard":
			var e: CharacterBody3D = enemy_scene.instantiate()
			e.set_script(DECREPIT_SCRIPT if kind == &"decrepit" else LIZARD_SCRIPT)
			# The sewer's cells to wander only down there; elsewhere the plain
			# wander (enemy.gd).
			if at.y < -4.0:
				e.set("sewer", maze.get("_sewer"))
			add_child(e)
			e.global_position = at + Vector3(0.0, 0.3, 0.0)
			return e
		&"stalker":
			var e := CharacterBody3D.new()
			e.set_script(STALKER_SCRIPT)
			var spots: Array[Vector3] = []
			for k in 8:
				var a := TAU * float(k) / 8.0
				spots.append(_floor_at(at + Vector3(cos(a), 0.0, sin(a)) * 14.0))
			e.set("wander_spots", spots)
			e.position = at + Vector3(0.0, 0.2, 0.0)
			add_child(e)
			return e
		&"mimic":
			var mimic_scene: PackedScene = maze.get("mimic_scene")
			var e: Node3D = mimic_scene.instantiate()
			e.position = at
			add_child(e)
			return e
		&"boss":
			var boss_scene: PackedScene = maze.get("boss_scene")
			var e: CharacterBody3D = boss_scene.instantiate()
			e.position = at + Vector3(0.0, 0.1, 0.0)
			add_child(e)
			return e
		&"rat":
			var e := CharacterBody3D.new()
			e.set_script(RAT_SCRIPT)
			e.position = at + Vector3(0.0, 0.05, 0.0)
			add_child(e)
			return e
	return null


# --- Teleporting ---------------------------------------------------------------------

## The places worth going, as [label, position, yaw], from what the level built.
## Only what exists is listed.
func destinations() -> Array:
	var out: Array = []
	out.append(["Test plane", spawn_point(), 0.0])
	var ml = maze.get("_module_level")
	if ml != null:
		out.append(["Start cell", ml.get("spawn") + Vector3(0.0, 0.1, 0.0), float(ml.get("spawn_yaw"))])
		var kinds_seen := {}
		var puzzles: Array = maze.get("_puzzles")
		var rooms: Array = ml.chest_rooms()
		for i in rooms.size():
			var kind := "chest room"
			if i < puzzles.size() and is_instance_valid(puzzles[i]):
				kind = "%s room" % String(puzzles[i].get("kind"))
			kinds_seen[kind] = int(kinds_seen.get(kind, 0)) + 1
			out.append(["%s %d" % [kind.capitalize(), kinds_seen[kind]], ml.room_world(rooms[i]) + Vector3(2.0, 0.3, 2.0), 0.0])
		var hall: Dictionary = ml.get("boss_hall") if ml.get("boss_hall") != null else {}
		if hall.has("door"):
			out.append(["Boss stair (foot)", Vector3(hall["door"]) + Vector3(0.0, 0.3, 0.0), 0.0])
	var bench := get_tree().get_first_node_in_group(&"workbench") as Node3D
	if bench != null:
		out.append(["Workbench", bench.global_position + bench.global_basis.z * 1.8 + Vector3(0.0, 0.3, 0.0),
			bench.global_rotation.y])
	var morgue = maze.call("morgue_centre")
	if morgue != null:
		out.append(["Morgue", Vector3(morgue) + Vector3(0.0, 0.3, 0.0), 0.0])
	var hall_info: Dictionary = maze.get("_boss_hall")
	if hall_info.has("zone_centre"):
		# On its floor (the zone's centre is in the air).
		var c: Vector3 = hall_info["zone_centre"]
		if hall_info.has("floor_y"):
			c.y = float(hall_info["floor_y"])
		out.append(["Boss hall", c + Vector3(0.0, 0.3, 0.0), 0.0])
	var door = maze.call("shard_door")
	if door != null and is_instance_valid(door):
		out.append(["Great shard door", (door as Node3D).global_position + (door as Node3D).global_basis.z * 3.0
			+ Vector3(0.0, 0.3, 0.0), (door as Node3D).global_rotation.y])
	var sewer = maze.get("_sewer")
	if sewer != null:
		var shafts: Array = sewer.get("shafts")
		if not shafts.is_empty():
			out.append(["Sewer (ladder foot)", Vector3(shafts[0]["foot"]) + Vector3(0.0, 0.3, 0.0), 0.0])
	var anchors: Array = maze.get("_anchors")
	for i in anchors.size():
		var a = anchors[i]
		if is_instance_valid(a) and a.has_method("spawn_point"):
			out.append(["Anchor %d" % (i + 1), a.spawn_point(), float(a.spawn_yaw())])
	return out


## Puts the player at `at` facing `yaw`, out of anything that holds them.
func teleport(at: Vector3, yaw: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		return
	if player.has_method("is_hidden") and player.is_hidden() and player.has_method("leave_hiding"):
		player.call("leave_hiding", at, yaw)
	if player.get("climbing") == true and player.has_method("end_climb"):
		player.call("end_climb")
	if player.has_method("_release_phasing"):
		player.call("_release_phasing", true)
	player.global_position = _floor_at(at) + Vector3(0.0, 0.1, 0.0)
	player.velocity = Vector3.ZERO
	player.rotation.y = yaw
	player.set("_look_pitch", 0.0)
	player.set("_was_grounded", true)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("fade_black"):
		hud.call("fade_black", 1.0, 0.0)
		hud.call("fade_black", 0.0, 0.35)
