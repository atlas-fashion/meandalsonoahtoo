extends "res://scripts/enforcer_react.gd"

## The decrepit enforcer's hit reactions (2026-10-15): the enforcer's layer
## (enforcer_react.gd -- keyed in skeleton space, turned to face the blow, legs
## held planted by IK) with this creature's own clips. It is a hunched, one-armed
## crawler whose arm is a great shield, and it reacts like something feral rather
## than a machine: sharp, jerky, recoiling and then dropping LOWER than before,
## with a shiver ("judder") through the head and the shield arm.
##
## Same conventions: rotation vectors in degrees (x pitch, minus tips the top
## back; y yaw, plus turns the front toward +X; z roll, plus leans the top
## toward -X), "hip" in leg lengths. There is no right arm on this rig.

## Struck in the face: the head snaps back, the hull jerks up and back, the
## shield is flung out wide -- then it ducks lower than it stood, hunched.
const HIT_SNAP := {
	"len": 0.58,
	"torso": [[0.0, Vector3.ZERO], [0.05, Vector3(-15, 0, 0)], [0.15, Vector3(-6, 0, 0)], [0.3, Vector3(6, 0, 0)], [0.44, Vector3(2, 0, 0)], [0.58, Vector3.ZERO]],
	"hip": [[0.0, Vector3.ZERO], [0.05, Vector3(0, 0.025, -0.07)], [0.24, Vector3(0, -0.045, 0.02)], [0.4, Vector3(0, -0.012, 0)], [0.58, Vector3.ZERO]],
	"head": [[0.0, Vector3.ZERO], [0.035, Vector3(-26, 0, 0)], [0.11, Vector3(-12, 7, 0)], [0.24, Vector3(11, -4, 0)], [0.38, Vector3(-3, 0, 0)], [0.58, Vector3.ZERO]],
	"sh_l": [[0.0, Vector3.ZERO], [0.06, Vector3(-10, 0, -14)], [0.24, Vector3(5, 0, 4)], [0.58, Vector3.ZERO]],
	"arm_l": [[0.0, Vector3.ZERO], [0.05, Vector3(-20, 0, -12)], [0.17, Vector3(9, 0, 6)], [0.33, Vector3(-3, 0, 0)], [0.58, Vector3.ZERO]],
	"judder": [[0.0, Vector3.ZERO], [0.06, Vector3(2.4, 0, 0)], [0.3, Vector3(0.8, 0, 0)], [0.5, Vector3.ZERO]],
}

## Clipped on the side: the hull wrenches round away from the blow and leans,
## the head whips round further and later, the shield swings right across the
## body as if to ward the next one off, and it snaps back past where it was.
const HIT_WRENCH := {
	"len": 0.72,
	"torso": [[0.0, Vector3.ZERO], [0.07, Vector3(-3, -26, 10)], [0.22, Vector3(2, 8, -3)], [0.4, Vector3(-1, -3, 1)], [0.72, Vector3.ZERO]],
	"hip": [[0.0, Vector3.ZERO], [0.08, Vector3(0.06, -0.03, 0.0)], [0.3, Vector3(-0.012, -0.005, 0.0)], [0.72, Vector3.ZERO]],
	"head": [[0.0, Vector3.ZERO], [0.05, Vector3(0, -10, 0)], [0.13, Vector3(-8, -34, 12)], [0.3, Vector3(3, 12, -4)], [0.48, Vector3(0, -3, 0)], [0.72, Vector3.ZERO]],
	"sh_l": [[0.0, Vector3.ZERO], [0.08, Vector3(-6, -10, 14)], [0.3, Vector3(2, 3, -4)], [0.72, Vector3.ZERO]],
	"arm_l": [[0.0, Vector3.ZERO], [0.1, Vector3(10, -18, 22)], [0.3, Vector3(-4, 6, -6)], [0.5, Vector3(1, -1, 1)], [0.72, Vector3.ZERO]],
	"judder": [[0.0, Vector3.ZERO], [0.08, Vector3(1.8, 0, 0)], [0.4, Vector3(0.5, 0, 0)], [0.6, Vector3.ZERO]],
}

## A heavy blow: the knees give and the hips drop, the hull pitches forward,
## the head drops and the shield is slammed down to catch it, then it heaves
## itself back up, rising a touch high before it sinks back into its crouch.
const HIT_BUCKLE := {
	"len": 0.82,
	"torso": [[0.0, Vector3.ZERO], [0.08, Vector3(13, 0, -5)], [0.3, Vector3(9, 0, -2)], [0.5, Vector3(-3, 0, 1)], [0.82, Vector3.ZERO]],
	"hip": [[0.0, Vector3.ZERO], [0.08, Vector3(0, -0.13, 0.02)], [0.3, Vector3(0, -0.1, 0.0)], [0.48, Vector3(0, 0.025, 0.0)], [0.64, Vector3(0, -0.006, 0.0)], [0.82, Vector3.ZERO]],
	"head": [[0.0, Vector3.ZERO], [0.06, Vector3(6, 0, 0)], [0.14, Vector3(19, 0, -6)], [0.36, Vector3(-6, 0, 2)], [0.56, Vector3(2, 0, 0)], [0.82, Vector3.ZERO]],
	"sh_l": [[0.0, Vector3.ZERO], [0.1, Vector3(8, 0, 10)], [0.36, Vector3(-3, 0, -3)], [0.82, Vector3.ZERO]],
	"arm_l": [[0.0, Vector3.ZERO], [0.1, Vector3(15, 0, 6)], [0.3, Vector3(10, 0, 3)], [0.5, Vector3(-4, 0, -1)], [0.82, Vector3.ZERO]],
	"judder": [[0.0, Vector3.ZERO], [0.12, Vector3(1.6, 0, 0)], [0.45, Vector3(0.4, 0, 0)], [0.7, Vector3.ZERO]],
}

## Parried and thrown on its back (decrepit.gd topples the whole body; this is
## the limbs over it, timed to its KNOCK_* phases): the head is thrown back and
## the shield flung up as it goes over, both jar on landing, it lies twitching,
## then the head comes up first and the shield is driven down to heave it up.
const KNOCKED := {
	"len": 1.95,
	"torso": [[0.0, Vector3.ZERO], [0.12, Vector3(-8, 0, 4)], [0.4, Vector3(-4, 0, 2)], [0.48, Vector3(3, 0, 0)],
		[1.0, Vector3(1, 3, -2)], [1.35, Vector3(0, 0, 0)], [1.55, Vector3(12, 0, 0)], [1.8, Vector3(-3, 0, 0)], [1.95, Vector3.ZERO]],
	"head": [[0.0, Vector3.ZERO], [0.1, Vector3(-30, 0, 0)], [0.36, Vector3(-16, 10, 0)], [0.47, Vector3(10, 0, 0)],
		[0.85, Vector3(4, -9, 4)], [1.15, Vector3(6, 7, -3)], [1.4, Vector3(-4, 0, 0)], [1.5, Vector3(24, 0, 0)],
		[1.75, Vector3(-8, 0, 0)], [1.95, Vector3.ZERO]],
	"sh_l": [[0.0, Vector3.ZERO], [0.12, Vector3(-18, 0, -20)], [0.42, Vector3(-6, 0, -12)], [0.5, Vector3(6, 0, -4)],
		[1.35, Vector3(4, 0, -6)], [1.52, Vector3(14, 0, 8)], [1.8, Vector3(-3, 0, 0)], [1.95, Vector3.ZERO]],
	"arm_l": [[0.0, Vector3.ZERO], [0.12, Vector3(-40, 0, -25)], [0.36, Vector3(-12, 0, -30)], [0.47, Vector3(22, 0, -10)],
		[0.8, Vector3(16, 0, -6)], [1.1, Vector3(20, 0, -9)], [1.38, Vector3(14, 0, -4)], [1.55, Vector3(32, 0, 12)],
		[1.8, Vector3(-6, 0, 0)], [1.95, Vector3.ZERO]],
	# Shaking on the ground: the jar of landing, then twitches as it lies.
	"judder": [[0.0, Vector3.ZERO], [0.42, Vector3(4.0, 0, 0)], [0.6, Vector3(0.6, 0, 0)], [0.95, Vector3(2.8, 0, 0)],
		[1.15, Vector3(0.4, 0, 0)], [1.3, Vector3(2.0, 0, 0)], [1.5, Vector3.ZERO]],
}

## Feral: a quick involuntary twitch of the head and the shield, played now and
## then while it hunts (decrepit.gd), never over a hit.
const TWITCH := {
	"len": 0.34,
	"head": [[0.0, Vector3.ZERO], [0.04, Vector3(-9, 16, 5)], [0.12, Vector3(3, -4, -1)], [0.34, Vector3.ZERO]],
	"sh_l": [[0.0, Vector3.ZERO], [0.05, Vector3(-3, 0, -5)], [0.34, Vector3.ZERO]],
	"judder": [[0.0, Vector3.ZERO], [0.05, Vector3(2.5, 0, 0)], [0.25, Vector3.ZERO]],
}


func _init() -> void:
	super()
	hits = [HIT_SNAP, HIT_WRENCH, HIT_BUCKLE]
	stagger_clip = KNOCKED


func twitch(from_world: Vector3) -> void:
	if busy():
		return
	_start(TWITCH, from_world, 1.0 if randf() < 0.5 else -1.0, randf_range(0.6, 1.1))
