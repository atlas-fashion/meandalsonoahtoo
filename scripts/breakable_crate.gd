extends StaticBody3D

## A wooden crate that breaks (note 176), as crates do in a soulslike: one blow
## -- sword, spear, a thrown spear's blast, or dashing into it -- and it bursts
## into its own planks, which tumble and come to rest on the floor, with a puff
## of dust and a spray of splinters. Now and then there are coins in it, more
## rarely a small health potion. A crate stacked on it drops down in its place.
##
## Built in code from boxes: four corner posts, a side of planks between them
## with a rail top and bottom (and a diagonal brace on two sides), a lid of
## planks with two battens. Each box is mapped on one plank of
## textures/surgery_planks.png along its grain, so the debris is the crate's own
## planks. The whole crate is one mesh; its 14 chunks (posts, half-sides, half
## lids) are kept as separate meshes for the break. Meshes are cached per size.
##
## Solid on the player's and enemies' layers (256, 512); blows find a taller
## volume of its own on the damageable layer (4, `HitVolume`, 1.75 m high) --
## a sword's cut passes at chest height, over a crate, and a swing at one has to
## break it. NOT on layer 2: the player's line of sight to whatever they swing
## at is tested on 2, and a crate stacked above another would hide the one
## under it.
## Not saved: a level built afresh has its crates whole again.

const PLANKS := preload("res://textures/surgery_planks.png")
const FX_DUST := preload("res://textures/surgery_fx_dust.png")

## Solid for the player (256) and the enemies and their navmesh (512); blows
## find its `Hit` volume, on the damageable layer (4).
const LAYERS := 256 | 512
## How high that volume reaches.
const HIT_HEIGHT := 1.75


## The volume a blow finds: hands the blow to its crate.
class HitVolume extends StaticBody3D:
	var crate: Node = null

	func take_damage(amount: float, from_direction := Vector3.ZERO, _attacker: Node = null) -> void:
		if crate != null and is_instance_valid(crate):
			crate.call("take_damage", amount, from_direction)
## Debris: hits the floor (1) and walls and crates (256), nothing hits it.
const DEBRIS_MASK := 1 | 256
## Seconds a piece tumbles before it is laid down for good (a plain mesh).
const DEBRIS_SETTLE := 3.2
## Its plank texture's columns.
const COLUMNS := 7.0
## Metres of plank the texture's height covers.
const TEX_HEIGHT := 1.0
## What may be inside.
const COIN_CHANCE := 0.22
const POTION_CHANCE := 0.06

const SIZES := [Vector3(0.86, 0.8, 0.86), Vector3(0.7, 0.62, 0.7), Vector3(1.12, 0.66, 0.74), Vector3(0.58, 0.52, 0.58)]
const TINTS := [Color(1.0, 1.0, 1.0), Color(0.86, 0.8, 0.72), Color(0.7, 0.66, 0.62)]

static var _cache := {}
static var _mats: Array = []
## Every whole crate, for the dash check (`watch`).
static var _all: Array = []

var size := Vector3(0.86, 0.8, 0.86)
var tint := 0
## The crate this one is stacked on; it drops when that one breaks.
var resting_on: Node3D = null
var _stacked: Array = []
var _broken := false
var _mesh: MeshInstance3D
var _rng := RandomNumberGenerator.new()


## A crate of SIZES[`kind`] standing at `xf` (its base's middle on the floor).
static func make(kind: int, xf: Transform3D, seed_: int) -> StaticBody3D:
	var c: StaticBody3D = load("res://scripts/breakable_crate.gd").new()
	c.name = "Crate"
	c.size = SIZES[clampi(kind, 0, SIZES.size() - 1)]
	c.tint = posmod(seed_, TINTS.size())
	c.transform = xf
	c.set_meta("seed", seed_)
	return c


func _ready() -> void:
	collision_layer = LAYERS
	collision_mask = 0
	add_to_group("breakable")
	_rng.seed = int(get_meta("seed", 7))
	var built := _built(size)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.mesh = built["whole"]
	_mesh.material_override = _material(tint)
	_mesh.visibility_range_end = 55.0
	_mesh.visibility_range_end_margin = 5.0
	add_child(_mesh)
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	cs.shape = shape
	cs.position = Vector3(0.0, size.y * 0.5, 0.0)
	add_child(cs)
	# What a blow finds: taller than the crate, up to where a sword cut
	# passes, so a swing at a crate breaks it without stooping to it. On
	# the damageable layer only; the crate itself is what stands in the way.
	var hit := HitVolume.new()
	hit.name = "Hit"
	hit.crate = self
	hit.collision_layer = 4
	hit.collision_mask = 0
	add_child(hit)
	var tall := BoxShape3D.new()
	tall.size = Vector3(size.x + 0.1, HIT_HEIGHT, size.z + 0.1)
	var hcs := CollisionShape3D.new()
	hcs.name = "CollisionShape3D"
	hcs.shape = tall
	hcs.position = Vector3(0.0, HIT_HEIGHT * 0.5, 0.0)
	hit.add_child(hcs)
	if resting_on != null and is_instance_valid(resting_on):
		(resting_on.get("_stacked") as Array).append(self)
	_all.append(self)


func _exit_tree() -> void:
	_all.erase(self)


static func _material(i: int) -> StandardMaterial3D:
	if _mats.is_empty():
		for t in TINTS:
			var m := StandardMaterial3D.new()
			m.albedo_texture = PLANKS
			m.albedo_color = t
			m.roughness = 0.9
			m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
			m.metallic_specular = 0.25
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			_mats.append(m)
	return _mats[posmod(i, _mats.size())]


# --- Building ----------------------------------------------------------------------

## {"whole": ArrayMesh, "chunks": [[ArrayMesh, Vector3 centre, Vector3 extent]]}
static func _built(s: Vector3) -> Dictionary:
	var key := str(s)
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var boxes := _layout(s, rng)
	var whole := SurfaceTool.new()
	whole.begin(Mesh.PRIMITIVE_TRIANGLES)
	var groups := {}
	for b in boxes:
		_box(whole, b["xf"], b["size"], b["col"], b["v0"])
		var g: int = b["group"]
		if not groups.has(g):
			groups[g] = []
		groups[g].append(b)
	var chunks: Array = []
	for g in groups:
		# Each chunk's own mesh about its own middle.
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for b in groups[g]:
			var xf: Transform3D = b["xf"]
			var h: Vector3 = b["size"] * 0.5
			for i in 8:
				var corner := Vector3(h.x * (1 if i & 1 else -1), h.y * (1 if i & 2 else -1), h.z * (1 if i & 4 else -1))
				var p := xf * corner
				lo = lo.min(p)
				hi = hi.max(p)
		var mid := (lo + hi) * 0.5
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for b in groups[g]:
			var xf: Transform3D = b["xf"]
			_box(st, Transform3D(xf.basis, xf.origin - mid), b["size"], b["col"], b["v0"])
		chunks.append([st.commit(), mid, (hi - lo).max(Vector3.ONE * 0.03)])
	var out := {"whole": whole.commit(), "chunks": chunks}
	_cache[key] = out
	return out


## Every board of a crate `s` big, its base's middle at the origin:
## [{xf, size, col, v0, group}].
static func _layout(s: Vector3, rng: RandomNumberGenerator) -> Array:
	var boxes: Array = []
	var add := func(centre: Vector3, sz: Vector3, group: int, basis: Basis) -> void:
		boxes.append({"xf": Transform3D(basis, centre), "size": sz, "col": rng.randi_range(0, 6),
			"v0": rng.randf(), "group": group})
	var post := 0.055
	var board := 0.022
	var rail := 0.07
	var hx := s.x * 0.5
	var hz := s.z * 0.5
	# Posts: groups 0-3.
	var g := 0
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			add.call(Vector3(sx * (hx - post * 0.5), s.y * 0.5, sz * (hz - post * 0.5)),
				Vector3(post, s.y, post), g, Basis())
			g += 1
	# Sides: +X, -X, +Z, -Z; each two chunks.
	var sides := [[Vector3(1, 0, 0), s.z], [Vector3(-1, 0, 0), s.z], [Vector3(0, 0, 1), s.x], [Vector3(0, 0, -1), s.x]]
	for si in sides.size():
		var n: Vector3 = sides[si][0]
		var length: float = sides[si][1]
		var across := Vector3(n.z, 0.0, n.x).abs()
		var face := (hx if absf(n.x) > 0.5 else hz)
		var inner := length - post * 2.0
		var count := maxi(3, roundi(inner / 0.16))
		var w := inner / float(count)
		for k in count:
			var off := -inner * 0.5 + w * (float(k) + 0.5)
			var centre := n * (face - board * 0.5 - 0.006) + across * off + Vector3(0.0, s.y * 0.5, 0.0)
			var size_ := across * (w - 0.008) + Vector3(0.0, s.y - 0.012, 0.0) + n.abs() * board
			add.call(centre, size_, 4 + si * 2 + (0 if k < count / 2 else 1), Basis())
		# Rails, proud of the boards.
		for top in [0, 1]:
			var y := (rail * 0.5 + 0.004) if top == 0 else (s.y - rail * 0.5 - 0.004)
			var centre := n * (face + 0.011) + Vector3(0.0, y, 0.0)
			add.call(centre, across * inner + Vector3(0.0, rail, 0.0) + n.abs() * 0.026, 4 + si * 2 + top, Basis())
		# A diagonal brace on two of the sides.
		if si % 2 == 0:
			var rise := s.y - rail * 2.0
			var run := inner
			var diag := sqrt(rise * rise + run * run)
			var angle := atan2(rise, run)
			var axis := n
			var basis := Basis(axis, angle if si == 0 else -angle)
			var long_size := across * diag + Vector3(0.0, rail * 0.9, 0.0) + n.abs() * 0.024
			add.call(n * (face + 0.011) + Vector3(0.0, s.y * 0.5, 0.0), long_size, 4 + si * 2 + 1, basis)
	# Lid: boards across X, two battens across Z on top; groups 12, 13.
	var lid_inner := s.x - 0.01
	var lid_count := maxi(3, roundi(lid_inner / 0.17))
	var lw := lid_inner / float(lid_count)
	for k in lid_count:
		var off := -lid_inner * 0.5 + lw * (float(k) + 0.5)
		add.call(Vector3(off, s.y - board * 0.5, 0.0), Vector3(lw - 0.008, board, s.z - 0.01),
			12 if k < lid_count / 2 else 13, Basis())
	for bz: float in [-1.0, 1.0]:
		add.call(Vector3(0.0, s.y + 0.012, bz * (hz - 0.13)), Vector3(s.x - 0.08, 0.026, 0.07),
			12 if bz < 0.0 else 13, Basis())
	return boxes


## A box `size` big at `xf` (its middle), in `st`: its grain along its longest
## axis, on plank column `col` of the texture from `v0`.
static func _box(st: SurfaceTool, xf: Transform3D, size: Vector3, col: int, v0: float) -> void:
	var h := size * 0.5
	var long := 0
	if size.y >= size.x and size.y >= size.z:
		long = 1
	elif size.z >= size.x and size.z >= size.y:
		long = 2
	var u0 := (float(col) + 0.07) / COLUMNS
	var uw := 0.86 / COLUMNS
	var corners: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for a in 3:
		for sgn: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[a] = sgn
			var b := (a + 1) % 3
			var c := (a + 2) % 3
			var pts: Array[Vector3] = []
			var uvs: Array[Vector2] = []
			for k in 4:
				var p := Vector3.ZERO
				p[a] = sgn * h[a]
				p[b] = corners[k].x * h[b]
				p[c] = corners[k].y * h[c]
				pts.append(p)
				var uv := Vector2.ZERO
				if long == a:
					# End grain: a sliver of the board.
					uv = Vector2(u0 + (corners[k].x * 0.5 + 0.5) * uw, v0 + (corners[k].y * 0.5 + 0.5) * 0.03)
				else:
					var across_axis := b if long == c else c
					var t_across := (p[across_axis] / h[across_axis]) * 0.5 + 0.5
					uv = Vector2(u0 + t_across * uw, v0 + (p[long] + h[long]) / TEX_HEIGHT)
				uvs.append(uv)
			var wn := xf.basis * n
			wn = wn.normalized()
			var w0 := xf * pts[0]
			var w1 := xf * pts[1]
			var w2 := xf * pts[2]
			var order := [0, 1, 2, 0, 2, 3]
			# Clockwise from outside (Godot's front face).
			if (w1 - w0).cross(w2 - w0).dot(wn) > 0.0:
				order = [0, 2, 1, 0, 3, 2]
			for k in order:
				st.set_normal(wn)
				st.set_uv(uvs[k])
				st.add_vertex(xf * pts[k])


# --- Breaking -----------------------------------------------------------------------

## Any blow breaks it.
func take_damage(_amount: float, from_direction := Vector3.ZERO, _attacker: Node = null) -> void:
	shatter(from_direction)


func is_broken() -> bool:
	return _broken


## Bursts it: the chunks thrown off along `push`, dust, splinters, what was in it.
func shatter(push := Vector3.ZERO) -> void:
	if _broken:
		return
	_broken = true
	_all.erase(self)
	remove_from_group("breakable")
	for path in ["CollisionShape3D", "Hit/CollisionShape3D"]:
		var cs := get_node_or_null(path) as CollisionShape3D
		if cs != null:
			cs.set_deferred("disabled", true)
	_mesh.visible = false
	var gfx := get_node_or_null("/root/Graphics")
	var effects := gfx == null or bool(gfx.get("effects"))
	var parent := get_parent()
	var centre := global_transform * Vector3(0.0, size.y * 0.5, 0.0)
	var flat := Vector3(push.x, 0.0, push.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO
	for chunk in _built(size)["chunks"]:
		_throw(parent, chunk, centre, flat)
	_dust(parent, centre, effects)
	_splinters(parent, centre, flat, effects)
	_loot(parent, centre)
	# A crate stacked on it comes down where it stood.
	for above in _stacked:
		if is_instance_valid(above) and not above.call("is_broken"):
			above.call("drop_by", size.y)
	_stacked.clear()
	# Gone once its pieces have settled (they are laid down elsewhere).
	get_tree().create_timer(DEBRIS_SETTLE + 0.5).timeout.connect(queue_free)


## The crate under this one broke: down `by` metres onto the floor.
func drop_by(by: float) -> void:
	if _broken:
		return
	resting_on = null
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y - by, sqrt(2.0 * by / 9.8)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "rotation:y", rotation.y + _rng.randf_range(-0.25, 0.25), 0.12)


func _throw(parent: Node, chunk: Array, centre: Vector3, push: Vector3) -> void:
	var body := RigidBody3D.new()
	body.name = "CratePiece"
	body.collision_layer = 0
	body.collision_mask = DEBRIS_MASK
	body.mass = 0.6
	var extent: Vector3 = chunk[2]
	var shape := BoxShape3D.new()
	shape.size = extent
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = chunk[0]
	mi.material_override = _mesh.material_override
	body.add_child(mi)
	parent.add_child(body)
	var at := global_transform * (chunk[1] as Vector3)
	body.global_transform = Transform3D(global_basis, at)
	var out := at - centre
	out.y = maxf(out.y, 0.0)
	out = out.normalized() if out.length_squared() > 0.0001 else Vector3.UP
	body.linear_velocity = out * _rng.randf_range(1.2, 3.0) + push * _rng.randf_range(1.0, 2.6) \
		+ Vector3(0.0, _rng.randf_range(0.8, 2.6), 0.0)
	body.angular_velocity = Vector3(_rng.randf_range(-9.0, 9.0), _rng.randf_range(-6.0, 6.0), _rng.randf_range(-9.0, 9.0))
	var keep := parent
	get_tree().create_timer(DEBRIS_SETTLE + _rng.randf_range(0.0, 0.6)).timeout.connect(func() -> void:
		_lay_down(body, keep))


## A tumbling piece laid down where it lies: a plain mesh from now on.
static func _lay_down(body, keep) -> void:
	if not is_instance_valid(body):
		return
	if is_instance_valid(keep):
		for child in body.get_children():
			if child is MeshInstance3D:
				var mi := MeshInstance3D.new()
				mi.name = "CrateDebris"
				mi.set_meta("crate_debris", true)
				mi.mesh = (child as MeshInstance3D).mesh
				mi.material_override = (child as MeshInstance3D).material_override
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_end = 40.0
				keep.add_child(mi)
				mi.global_transform = (child as MeshInstance3D).global_transform
	body.queue_free()


## The puff: the generated dust, billboards rolling out low and rising slowly,
## swelling and thinning. Lit, so in the dark it is a shadow of dust, not a glow.
func _dust(parent: Node, at: Vector3, effects: bool) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 16 if effects else 6
	p.lifetime = 2.2
	p.explosiveness = 0.9
	p.lifetime_randomness = 0.35
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = size.x * 0.4
	p.direction = Vector3(0.0, 0.35, 0.0)
	p.spread = 180.0
	p.flatness = 0.5
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 2.4
	p.damping_min = 2.0
	p.damping_max = 3.5
	p.gravity = Vector3(0.0, 0.25, 0.0)
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -25.0
	p.angular_velocity_max = 25.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(0.3, 1.0))
	grow.add_point(Vector2(1.0, 1.7))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.57, 0.5, 0.0))
	ramp.add_point(0.08, Color(0.62, 0.57, 0.5, 0.7))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.5, 0.46, 0.4, 0.0))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = FX_DUST
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.disable_receive_shadows = true
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = at
	p.restart()
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)


## Splinters of the planks, thrown out and tumbling down.
func _splinters(parent: Node, at: Vector3, push: Vector3, effects: bool) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 22 if effects else 8
	p.lifetime = 1.3
	p.explosiveness = 1.0
	p.lifetime_randomness = 0.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = size * 0.4
	p.direction = (Vector3.UP + push * 0.6).normalized()
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0.0, -13.0, 0.0)
	p.angular_velocity_min = -720.0
	p.angular_velocity_max = 720.0
	p.particle_flag_rotate_y = true
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.3
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.012, 0.028)
	box.material = _mesh.material_override
	p.mesh = box
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = at
	p.restart()
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


func _loot(parent: Node, at: Vector3) -> void:
	var roll := _rng.randf()
	var drop := load("res://scripts/item_drop.gd")
	if roll < POTION_CHANCE:
		drop.spawn(parent, at, &"small_health_potion", 1)
	elif roll < POTION_CHANCE + COIN_CHANCE:
		drop.spawn(parent, at, &"coins", _rng.randi_range(3, 9))


## Dashing into a crate breaks it. Called once a physics tick by ruin_dressing.gd.
static func watch(players: Array) -> void:
	for p in players:
		var body := p as Node3D
		if body == null or not is_instance_valid(body) or body.get("_dashing") != true:
			continue
		var at := body.global_position
		for c in _all.duplicate():
			var crate := c as Node3D
			if not is_instance_valid(crate):
				continue
			var local := crate.global_transform.affine_inverse() * at
			var s: Vector3 = crate.get("size")
			if absf(local.x) < s.x * 0.5 + 0.6 and absf(local.z) < s.z * 0.5 + 0.6 \
					and local.y > -1.0 and local.y < s.y + 0.5:
				var v: Vector3 = body.get("velocity") if body.get("velocity") != null else Vector3.ZERO
				crate.call("shatter", v)
