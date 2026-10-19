extends Node3D

## A player as the OTHER player sees them, in co-op (2026-10-18): the game has
## no player body -- in first person you are a camera, a sword and a torch --
## so each player gets this stand-in, drawn only by the other half's camera
## (its own layer, split_screen.gd AVATAR): a hooded, cloaked figure built from
## primitives, in a colour of its own (player 1 rust red, player 2 steel blue),
## with what is in hand -- the sword, the spear -- and a lit torch in the
## other, and a name over the head.
##
## A child of the player, so it already turns with their yaw. It reads the
## player each frame: the hood follows where they look up or down, the cloak
## bobs and the arms swing with their pace, the sword arm cuts with their
## strokes and comes across to guard, the whole figure lies down when they
## die and is gone while they hide.

const CLOTH := [Color(0.42, 0.12, 0.08), Color(0.13, 0.22, 0.38)]
const NAMES := ["PLAYER 1", "PLAYER 2"]
const SHOULDER := Vector3(0.23, 1.36, 0.0)

var player: Node3D
var _body: Node3D
var _hood: Node3D
var _arm_r: Node3D
var _arm_l: Node3D
var _sword: Node3D
var _spear: Node3D
var _label: Label3D
var _phase := 0.0
var _lie := 0.0


func setup(p: Node3D, layer: int) -> void:
	player = p
	name = "CoopAvatar"
	var i: int = clampi(int(p.get("player_index")), 0, 1)
	var cloth := _mat(CLOTH[i], 0.95)
	var dark := _mat(Color(0.06, 0.05, 0.05), 0.9)
	var skin := _mat(Color(0.55, 0.42, 0.34), 0.8)
	var steel := _mat(Color(0.7, 0.72, 0.76), 0.35, 0.8)
	var wood := _mat(Color(0.35, 0.24, 0.14), 0.9)
	var flame := StandardMaterial3D.new()
	flame.albedo_color = Color(1.0, 0.6, 0.2)
	flame.emission_enabled = true
	flame.emission = Color(1.0, 0.5, 0.15)
	flame.emission_energy_multiplier = 3.0
	_body = Node3D.new()
	add_child(_body)
	# The cloak, the shoulders under it, the hood with a shadowed face.
	_part(_body, _cyl(0.17, 0.33, 1.15), Vector3(0.0, 0.58, 0.0), cloth)
	var chest := CapsuleMesh.new()
	chest.radius = 0.2
	chest.height = 0.62
	_part(_body, chest, Vector3(0.0, 1.2, 0.0), cloth)
	_hood = Node3D.new()
	_hood.position = Vector3(0.0, 1.5, 0.0)
	_body.add_child(_hood)
	var hood := SphereMesh.new()
	hood.radius = 0.17
	hood.height = 0.36
	_part(_hood, hood, Vector3(0.0, 0.08, 0.02), cloth)
	var face := SphereMesh.new()
	face.radius = 0.11
	face.height = 0.22
	_part(_hood, face, Vector3(0.0, 0.06, -0.09), dark)
	# Arms from the shoulders, a hand at each end.
	_arm_r = _arm(SHOULDER, cloth, skin)
	_arm_l = _arm(Vector3(-SHOULDER.x, SHOULDER.y, 0.0), cloth, skin)
	# In the right hand: the sword (a blade, guard and grip) or the spear.
	_sword = Node3D.new()
	_sword.position = Vector3(0.0, -0.6, -0.04)
	_arm_r.add_child(_sword)
	_part(_sword, _box(Vector3(0.05, 0.85, 0.012)), Vector3(0.0, -0.48, -0.0), steel).rotation.x = PI
	_part(_sword, _box(Vector3(0.2, 0.03, 0.04)), Vector3(0.0, -0.04, 0.0), wood)
	_part(_sword, _cyl(0.018, 0.018, 0.14), Vector3(0.0, 0.05, 0.0), wood)
	# Down and forward, so it shows from in front (pointing straight out it
	# was a sliver seen end on).
	_sword.rotation.x = -0.9
	_spear = Node3D.new()
	_spear.position = Vector3(0.0, -0.6, -0.04)
	_arm_r.add_child(_spear)
	_part(_spear, _cyl(0.018, 0.018, 2.0), Vector3(0.0, -0.4, 0.0), wood)
	var head := CylinderMesh.new()
	head.top_radius = 0.0
	head.bottom_radius = 0.045
	head.height = 0.22
	_part(_spear, head, Vector3(0.0, -1.5, 0.0), steel).rotation.x = PI
	_spear.rotation.x = -PI * 0.5
	# A torch in the left hand, alight.
	var torch := Node3D.new()
	torch.position = Vector3(0.0, -0.62, -0.05)
	_arm_l.add_child(torch)
	_part(torch, _cyl(0.025, 0.02, 0.4), Vector3(0.0, 0.12, 0.0), wood)
	var fire := SphereMesh.new()
	fire.radius = 0.05
	fire.height = 0.14
	_part(torch, fire, Vector3(0.0, 0.37, 0.0), flame).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label = Label3D.new()
	_label.text = NAMES[i]
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.font_size = 28
	_label.pixel_size = 0.004
	_label.modulate = CLOTH[i].lightened(0.45)
	_label.outline_size = 6
	_label.position = Vector3(0.0, 2.0, 0.0)
	add_child(_label)
	for g in find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).layers = layer


func _arm(at: Vector3, cloth: Material, skin: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = at
	_body.add_child(pivot)
	var sleeve := CapsuleMesh.new()
	sleeve.radius = 0.065
	sleeve.height = 0.62
	_part(pivot, sleeve, Vector3(0.0, -0.3, 0.0), cloth)
	var hand := SphereMesh.new()
	hand.radius = 0.05
	hand.height = 0.1
	_part(pivot, hand, Vector3(0.0, -0.62, 0.0), skin)
	return pivot


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var hidden: bool = player.call("is_hidden")
	visible = not hidden
	if hidden:
		return
	var dead: bool = player.get("_dead") == true
	var held: StringName = player.call("held_item")
	_sword.visible = held == &"sword"
	_spear.visible = held == &"spear"
	# Lying down when dead.
	_lie = move_toward(_lie, 1.0 if dead else 0.0, delta * 2.5)
	_body.rotation.x = -PI * 0.5 * _lie * _lie
	_body.position.y = 0.2 * _lie
	_label.visible = not dead
	# Pace: bob and swing with how fast they move.
	var v: Vector3 = player.get("velocity")
	var speed := Vector2(v.x, v.z).length()
	_phase += delta * (2.0 + speed * 2.2)
	var stride := clampf(speed / 4.25, 0.0, 1.5)
	_body.position.y += absf(sin(_phase)) * 0.04 * stride
	_hood.rotation.x = clampf(float(player.get("_look_pitch")), -1.0, 1.0) * 0.6
	var swing := sin(_phase) * 0.45 * stride
	_arm_l.rotation = Vector3(-0.5 - swing * 0.5, 0.0, 0.08)
	# The sword arm: forward with the blade out; cutting through a stroke;
	# across the body on guard.
	var arm := Vector3(-0.35 + swing, 0.0, -0.08)
	var kind: StringName = player.get("_pose_kind")
	var t: float = player.get("_pose_time")
	if player.get("_blocking") == true:
		arm = Vector3(-1.4, 0.7, -0.2)
	elif kind in [&"slash", &"chop", &"spin", &"slam", &"raise", &"stab", &"haft"] and t >= 0.0:
		var k := clampf(t / 0.35, 0.0, 1.0)
		arm = Vector3(-2.2 + 2.0 * k, 0.6 - 1.2 * k, -0.1)
	elif held == &"spear":
		arm = Vector3(-0.9, 0.0, 0.0)
	_arm_r.rotation = _arm_r.rotation.lerp(arm, 1.0 - exp(-18.0 * delta))


# --- Pieces -------------------------------------------------------------------------

func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 12
	c.rings = 1
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _part(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi
