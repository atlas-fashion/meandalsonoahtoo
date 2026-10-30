extends Node3D

## A figure for the intro (note 131): the dying knight, the boy, the Vardian
## sentinel. STAND-INS made in code from primitives (the user chose stand-ins
## while no Higgsfield generation was available) -- the surgeon's stand-in body
## (note 109) is the model: every joint a Node3D, named poses eased per frame.
##
## Faces +Z. Limbs hang along -Y at rest. `pose(name)` eases toward a pose;
## `snap(name)` sets it at once. `hand_r` / `hand_l` carry props.

## &"knight", &"kid" or &"sentinel"; set before it enters the tree.
var style := &"knight"
var hand_r: Node3D
var hand_l: Node3D
var head: Node3D
## The sentinel's eyes and its chest crystal, for flaring.
var glow_mat: StandardMaterial3D

var _j := {}
var _goal := {}
var _rate := 6.0
var _mats := {}


func _ready() -> void:
	_build()


func _mat(key: StringName, col: Color, metal := 0.0, rough := 0.7, emit := Color.BLACK, emit_e := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	if emit_e > 0.0:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = emit_e
	_mats[key] = m
	return m


func _joint(key: StringName, parent: Node3D, at: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = String(key)
	j.position = at
	parent.add_child(j)
	_j[key] = j
	return j


func _part(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3, rot := Vector3.ZERO, scale_ := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	mi.rotation = rot
	mi.scale = scale_
	parent.add_child(mi)
	return mi


func _cap(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = maxf(h, r * 2.0)
	c.radial_segments = 12
	c.rings = 4
	return c


func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 8
	return s


func _build() -> void:
	var skin := _mat(&"skin", Color(0.72, 0.52, 0.42), 0.0, 0.6)
	var body_mat: Material
	var limb_mat: Material
	var trim: Material
	match style:
		&"knight":
			body_mat = _mat(&"plate", Color(0.52, 0.53, 0.55), 0.75, 0.38)
			limb_mat = _mat(&"mail", Color(0.3, 0.3, 0.32), 0.6, 0.55)
			trim = _mat(&"surcoat", Color(0.42, 0.06, 0.05), 0.0, 0.85)
		&"kid":
			body_mat = _mat(&"tunic", Color(0.3, 0.32, 0.18), 0.0, 0.9)
			limb_mat = _mat(&"wool", Color(0.32, 0.24, 0.16), 0.0, 0.9)
			trim = _mat(&"belt", Color(0.2, 0.12, 0.07), 0.0, 0.7)
		_:
			body_mat = _mat(&"bronze", Color(0.32, 0.48, 0.42), 0.7, 0.45)
			limb_mat = _mat(&"bronze_dark", Color(0.2, 0.3, 0.27), 0.7, 0.5)
			trim = _mat(&"gold", Color(0.62, 0.48, 0.2), 0.85, 0.35)
			glow_mat = _mat(&"glow", Color(0.1, 0.5, 0.6), 0.0, 0.3, Color(0.3, 0.9, 1.0), 3.0)
	var hips := _joint(&"hips", self, Vector3(0, 0.95, 0))
	_part(hips, _boxm(Vector3(0.34, 0.2, 0.22)), limb_mat, Vector3(0, 0.0, 0))
	var spine := _joint(&"spine", hips, Vector3(0, 0.08, 0))
	_part(spine, _cap(0.16, 0.44), body_mat, Vector3(0, 0.22, 0), Vector3.ZERO, Vector3(1.15, 1.0, 0.8))
	var chest := _joint(&"chest", spine, Vector3(0, 0.3, 0))
	_part(chest, _boxm(Vector3(0.42, 0.32, 0.24)), body_mat, Vector3(0, 0.08, 0))
	var neck := _joint(&"neck", chest, Vector3(0, 0.26, 0))
	_part(neck, _cap(0.05, 0.12), skin if style == &"kid" else limb_mat, Vector3(0, 0.04, 0))
	head = _joint(&"head", neck, Vector3(0, 0.1, 0))
	match style:
		&"knight":
			# The helm, its visor up, his face under it.
			_part(head, _sph(0.125), body_mat, Vector3(0, 0.11, 0), Vector3.ZERO, Vector3(1.0, 1.15, 1.05))
			_part(head, _sph(0.09), skin, Vector3(0, 0.08, 0.06), Vector3.ZERO, Vector3(0.9, 1.0, 0.7))
			_part(head, _boxm(Vector3(0.24, 0.05, 0.08)), body_mat, Vector3(0, 0.2, 0.08), Vector3(-0.5, 0, 0))
			# The surcoat over the plate, the tear and the dark stain in it.
			_part(chest, _boxm(Vector3(0.44, 0.34, 0.25)), trim, Vector3(0, 0.06, 0.006))
			_part(hips, _boxm(Vector3(0.38, 0.42, 0.25)), trim, Vector3(0, -0.16, 0.0))
			_part(chest, _boxm(Vector3(0.16, 0.12, 0.02)), _mat(&"blood", Color(0.12, 0.02, 0.02), 0.0, 0.4), Vector3(0.08, -0.04, 0.13))
		&"kid":
			_part(head, _sph(0.12), skin, Vector3(0, 0.1, 0))
			_part(head, _sph(0.125), _mat(&"hair", Color(0.22, 0.14, 0.08), 0.0, 0.8), Vector3(0, 0.14, -0.02), Vector3.ZERO, Vector3(1.0, 0.8, 1.0))
			_part(hips, _boxm(Vector3(0.36, 0.08, 0.24)), trim, Vector3(0, 0.08, 0))
		_:
			_part(head, _boxm(Vector3(0.22, 0.26, 0.24)), body_mat, Vector3(0, 0.12, 0))
			_part(head, _boxm(Vector3(0.24, 0.05, 0.25)), trim, Vector3(0, 0.22, 0))
			for s: float in [-1.0, 1.0]:
				_part(head, _sph(0.022), glow_mat, Vector3(0.055 * s, 0.13, 0.12))
			_part(chest, _sph(0.05), glow_mat, Vector3(0, 0.1, 0.13), Vector3.ZERO, Vector3(0.8, 1.3, 0.6))
			_part(chest, _boxm(Vector3(0.5, 0.06, 0.28)), trim, Vector3(0, 0.22, 0))
	for s: float in [-1.0, 1.0]:
		var side := &"r" if s > 0.0 else &"l"
		var sh := _joint(StringName("shoulder_" + side), chest, Vector3(0.24 * s, 0.18, 0))
		_part(sh, _sph(0.075 if style != &"kid" else 0.06), body_mat if style != &"kid" else limb_mat, Vector3.ZERO)
		_part(sh, _cap(0.055, 0.3), limb_mat, Vector3(0, -0.15, 0))
		var el := _joint(StringName("elbow_" + side), sh, Vector3(0, -0.3, 0))
		_part(el, _cap(0.048, 0.27), body_mat if style == &"knight" else limb_mat, Vector3(0, -0.13, 0))
		var hand := _joint(StringName("hand_" + side), el, Vector3(0, -0.28, 0))
		_part(hand, _boxm(Vector3(0.08, 0.1, 0.05)), limb_mat if style != &"kid" else skin, Vector3(0, -0.04, 0))
		if s > 0.0:
			hand_r = hand
		else:
			hand_l = hand
		var hip := _joint(StringName("thigh_" + side), hips, Vector3(0.1 * s, -0.06, 0))
		_part(hip, _cap(0.075, 0.45), limb_mat, Vector3(0, -0.22, 0))
		var knee := _joint(StringName("shin_" + side), hip, Vector3(0, -0.45, 0))
		_part(knee, _cap(0.06, 0.45), body_mat if style == &"knight" else limb_mat, Vector3(0, -0.22, 0))
		var foot := _joint(StringName("foot_" + side), knee, Vector3(0, -0.45, 0))
		_part(foot, _boxm(Vector3(0.1, 0.07, 0.24)), _mat(&"boot", Color(0.14, 0.1, 0.07), 0.0, 0.8), Vector3(0, -0.02, 0.05))
	if style == &"kid":
		scale = Vector3.ONE * 0.64
	elif style == &"sentinel":
		scale = Vector3.ONE * 1.12
		# Its glaive.
		var staff := Node3D.new()
		staff.name = "Glaive"
		hand_r.add_child(staff)
		_part(staff, _cap(0.025, 2.0), limb_mat, Vector3(0, 0.0, 0), Vector3(PI * 0.5, 0, 0))
		_part(staff, _boxm(Vector3(0.04, 0.12, 0.5)), trim, Vector3(0, 0, 1.2))
		_part(staff, _boxm(Vector3(0.02, 0.06, 0.3)), glow_mat, Vector3(0, 0, 1.25))


## Poses: joint -> rotation (radians); "hips_y" the hips' height.
func _angles(p: StringName) -> Dictionary:
	match p:
		&"sit_slump":
			return {&"hips_y": 0.22, &"spine": Vector3(-0.32, 0, 0), &"chest": Vector3(-0.05, 0, 0.05),
				&"head": Vector3(0.45, 0.25, 0.1), &"thigh_l": Vector3(-1.45, 0.15, 0.0), &"thigh_r": Vector3(-1.3, -0.25, 0),
				&"shin_l": Vector3(0.25, 0, 0), &"shin_r": Vector3(0.6, 0, 0), &"shoulder_l": Vector3(-0.2, 0, 0.25),
				&"elbow_l": Vector3(-0.3, 0, 0), &"shoulder_r": Vector3(-0.35, 0, -0.1), &"elbow_r": Vector3(-0.7, 0, 0)}
		&"offer":
			return {&"hips_y": 0.22, &"spine": Vector3(-0.22, 0, 0), &"chest": Vector3(0.05, -0.2, 0),
				&"head": Vector3(0.15, 0.2, 0), &"thigh_l": Vector3(-1.45, 0.15, 0.0), &"thigh_r": Vector3(-1.3, -0.25, 0),
				&"shin_l": Vector3(0.25, 0, 0), &"shin_r": Vector3(0.6, 0, 0), &"shoulder_l": Vector3(-0.2, 0, 0.25),
				&"elbow_l": Vector3(-0.3, 0, 0), &"shoulder_r": Vector3(-1.25, 0.2, -0.25), &"elbow_r": Vector3(-0.35, 0, 0)}
		&"dead":
			return {&"hips_y": 0.2, &"spine": Vector3(-0.3, 0, 0.12), &"chest": Vector3(0.1, 0, 0.12),
				&"head": Vector3(0.75, 0.45, 0.3), &"thigh_l": Vector3(-1.45, 0.25, 0.0), &"thigh_r": Vector3(-1.35, -0.35, 0),
				&"shin_l": Vector3(0.15, 0, 0), &"shin_r": Vector3(0.35, 0, 0), &"shoulder_l": Vector3(0.0, 0, 0.12),
				&"elbow_l": Vector3(-0.15, 0, 0), &"shoulder_r": Vector3(-0.15, 0, -0.05), &"elbow_r": Vector3(-0.1, 0, 0)}
		&"kneel":
			return {&"hips_y": 0.52, &"spine": Vector3(0.25, 0, 0), &"head": Vector3(0.3, 0, 0),
				&"thigh_l": Vector3(-1.5, 0, 0), &"shin_l": Vector3(1.45, 0, 0), &"thigh_r": Vector3(0.15, 0, 0),
				&"shin_r": Vector3(1.55, 0, 0), &"foot_r": Vector3(0.6, 0, 0),
				&"shoulder_l": Vector3(-0.9, 0, 0.1), &"elbow_l": Vector3(-0.5, 0, 0),
				&"shoulder_r": Vector3(-1.0, 0, -0.1), &"elbow_r": Vector3(-0.4, 0, 0)}
		&"hold":
			return {&"hips_y": 0.52, &"spine": Vector3(0.3, 0, 0), &"head": Vector3(0.55, 0, 0),
				&"thigh_l": Vector3(-1.5, 0, 0), &"shin_l": Vector3(1.45, 0, 0), &"thigh_r": Vector3(0.15, 0, 0),
				&"shin_r": Vector3(1.55, 0, 0), &"foot_r": Vector3(0.6, 0, 0),
				&"shoulder_l": Vector3(-0.55, 0, 0.35), &"elbow_l": Vector3(-1.5, 0, 0),
				&"shoulder_r": Vector3(-0.55, 0, -0.35), &"elbow_r": Vector3(-1.5, 0, 0)}
		&"dormant":
			return {&"hips_y": 0.95, &"spine": Vector3(0.2, 0, 0), &"head": Vector3(0.6, 0, 0),
				&"shoulder_r": Vector3(-0.35, 0, 0), &"elbow_r": Vector3(-1.2, 0, 0), &"shoulder_l": Vector3(0.1, 0, 0.1)}
		&"guard":
			return {&"hips_y": 0.9, &"spine": Vector3(0.05, 0, 0), &"thigh_l": Vector3(-0.3, 0, 0), &"shin_l": Vector3(0.35, 0, 0),
				&"thigh_r": Vector3(0.2, 0, 0), &"shin_r": Vector3(0.3, 0, 0),
				&"shoulder_r": Vector3(-0.5, 0, 0.1), &"elbow_r": Vector3(-1.1, 0, 0), &"shoulder_l": Vector3(-0.6, 0, -0.2), &"elbow_l": Vector3(-1.0, 0, 0)}
		&"wind":
			return {&"hips_y": 0.92, &"spine": Vector3(-0.15, 0.4, 0), &"chest": Vector3(-0.1, 0.2, 0), &"head": Vector3(-0.1, -0.3, 0),
				&"thigh_l": Vector3(-0.4, 0, 0), &"shin_l": Vector3(0.4, 0, 0), &"thigh_r": Vector3(0.3, 0, 0), &"shin_r": Vector3(0.2, 0, 0),
				&"shoulder_r": Vector3(-2.7, 0, 0.3), &"elbow_r": Vector3(-0.5, 0, 0), &"shoulder_l": Vector3(-0.8, 0, -0.3), &"elbow_l": Vector3(-0.8, 0, 0)}
		&"strike":
			return {&"hips_y": 0.85, &"spine": Vector3(0.35, -0.3, 0), &"chest": Vector3(0.15, -0.2, 0), &"head": Vector3(0.0, 0.3, 0),
				&"thigh_l": Vector3(-0.7, 0, 0), &"shin_l": Vector3(0.6, 0, 0), &"thigh_r": Vector3(0.45, 0, 0), &"shin_r": Vector3(0.2, 0, 0),
				&"shoulder_r": Vector3(-1.0, 0, 0.1), &"elbow_r": Vector3(-0.1, 0, 0), &"shoulder_l": Vector3(-0.3, 0, -0.2), &"elbow_l": Vector3(-0.6, 0, 0)}
		&"reel":
			return {&"hips_y": 0.92, &"spine": Vector3(-0.45, 0.2, 0.1), &"chest": Vector3(-0.2, 0, 0), &"head": Vector3(-0.3, 0, 0),
				&"thigh_l": Vector3(0.2, 0, 0), &"thigh_r": Vector3(-0.2, 0, 0), &"shoulder_r": Vector3(-1.8, 0, 0.6),
				&"elbow_r": Vector3(-0.3, 0, 0), &"shoulder_l": Vector3(-0.5, 0, -0.6)}
		&"collapse":
			return {&"hips_y": 0.35, &"spine": Vector3(0.9, 0, 0.2), &"chest": Vector3(0.3, 0, 0), &"head": Vector3(0.7, 0, 0),
				&"thigh_l": Vector3(-1.5, 0, 0), &"shin_l": Vector3(1.5, 0, 0), &"thigh_r": Vector3(-1.2, 0, 0), &"shin_r": Vector3(1.6, 0, 0),
				&"shoulder_r": Vector3(-0.3, 0, 0.3), &"shoulder_l": Vector3(-0.2, 0, -0.3)}
	return {&"hips_y": 0.95}


func pose(p: StringName, rate := 6.0) -> void:
	_goal = _angles(p)
	_rate = rate


func snap(p: StringName) -> void:
	_goal = _angles(p)
	for key in _j:
		var j: Node3D = _j[key]
		j.rotation = _goal.get(key, Vector3.ZERO)
	(_j[&"hips"] as Node3D).position.y = float(_goal.get(&"hips_y", 0.95))


func _process(delta: float) -> void:
	if _goal.is_empty():
		return
	var k := 1.0 - exp(-_rate * delta)
	for key in _j:
		var j: Node3D = _j[key]
		j.rotation = j.rotation.lerp(_goal.get(key, Vector3.ZERO), k)
	var hips: Node3D = _j[&"hips"]
	hips.position.y = lerpf(hips.position.y, float(_goal.get(&"hips_y", 0.95)), k)


## The artifact: a hilt with no blade, a crystal in its pommel that never dims.
## STAND-IN (primitives). Its grip runs along local -Y from the origin (the hand).
static func make_hilt() -> Node3D:
	var h := Node3D.new()
	h.name = "Hilt"
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.16, 0.1, 0.07)
	leather.roughness = 0.8
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.7, 0.55, 0.28)
	brass.metallic = 0.85
	brass.roughness = 0.3
	var crystal := StandardMaterial3D.new()
	crystal.albedo_color = Color(0.4, 0.9, 1.0)
	crystal.emission_enabled = true
	crystal.emission = Color(0.3, 0.85, 1.0)
	crystal.emission_energy_multiplier = 4.0
	crystal.roughness = 0.1
	var grip := MeshInstance3D.new()
	var gc := CylinderMesh.new()
	gc.top_radius = 0.016
	gc.bottom_radius = 0.018
	gc.height = 0.17
	grip.mesh = gc
	grip.material_override = leather
	h.add_child(grip)
	for s: float in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.11, 0.022, 0.03)
		arm.mesh = b
		arm.material_override = brass
		arm.position = Vector3(0.055 * s, 0.095, 0)
		arm.rotation.z = 0.25 * s
		h.add_child(arm)
	var socket := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.022
	sc.bottom_radius = 0.02
	sc.height = 0.04
	socket.mesh = sc
	socket.material_override = brass
	socket.position.y = 0.11
	h.add_child(socket)
	var pommel := MeshInstance3D.new()
	var ps := SphereMesh.new()
	ps.radius = 0.024
	ps.height = 0.048
	pommel.mesh = ps
	pommel.material_override = brass
	pommel.position.y = -0.1
	h.add_child(pommel)
	var gem := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = 0.016
	gs.height = 0.05
	gs.radial_segments = 6
	gs.rings = 2
	gem.mesh = gs
	gem.material_override = crystal
	gem.position.y = -0.125
	h.add_child(gem)
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = Color(0.3, 0.85, 1.0)
	light.light_energy = 0.6
	light.omni_range = 1.4
	light.position.y = -0.12
	h.add_child(light)
	return h
