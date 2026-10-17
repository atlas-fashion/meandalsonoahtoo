## 48. Wardens are ENFORCERS: the user's rigged model and baked animations (2026-10-15)

- **Renamed** everywhere: `scripts/enforcer.gd` (was warden.gd), group
  "enforcers", `is_enforcer()`, display "ENFORCER", maze `_spawn_enforcer` /
  `enforcers_with_packs` / `enforcer_aggro_range`, dungeon_room `_enforcers` /
  `enforcers_down` (an older save's "wardens_down" is still read), convoy
  `enforcer`, the HUD/room text. The BOSS is still THE WARDEN. The crier keeps
  the old bot's primitive head; its pieces live in crier.gd now (`_robot_*`).
- **The model** is the user's: `models/source/enforcer/ENFORCER_BAKED.blend`
  (a rusted Tripo mech on a 16-bone rig) -> `models/enforcer.glb` by
  `tools/build_enforcer.py`. ONLY the baked clips are exported (user's rule):
  WALK_BAKED (2.0 s), BEAM_BAKED (0.78 s), SWIPE_BAKED (1.25 s), from their NLA
  tracks; the file's unbaked "BEAM" (IK targets on a mesh) is dropped. (The
  first file sent had only WALK_BAKED; the user sent the right one.) The build
  adds bone-parented empties Godot imports as BoneAttachment3Ds -- EyeL/EyeR
  (HEAD, the two front-most bulges of the head ball), Muzzle (ARM_R, the
  cannon's mouth), Shield (ARM_L) -- renames the crystal's material
  "EnforcerCrystal", and samples the clips: the shield crosses the front fastest
  at frames 31-37 (blow at 32, `SWIPE_CONTACT`), the cannon is up and aimed from
  frame 37 (`BEAM_AIMED`). Drawn at `MODEL_SCALE` 0.59 (2.6 m), turned to face
  -Z; capsule r 0.6 h 2.5.
- **One mesh, one atlas** (`atlas()` in the build): delivered as 12 skinned
  meshes with 37 materials, 57 enforcers took the bench 70.1 -> 63.7 fps, worst
  p99 28 -> 40.7 ms, draws doubled in the rooms (each surface again in every
  torch's shadow pass, 12 skins each). Joined into one mesh and its colour
  baked (Cycles, DIFFUSE colour) into a 2K atlas on a smart-projected UV map
  (`enforcer_atlas.png` kept beside the source); the crystal keeps its own
  emissive material. After: 68.9 fps / 28.51 / 1155 MB (70.1 / 28.01 / 1117
  before the change) -- ~1 fps for 57 skinned 35k-triangle mechs.
- **Clips are driven by enforcer.gd** (`_animate`, `_play_clip`), named so
  enemy.gd's own state animations never match; enemy.gd still advances the
  player by hand (distance-based rate). Walk at speed / `WALK_GROUND_SPEED`
  0.82 m/s (a planted foot's speed, measured in Blender at the authored size x
  the scale), eased to a stop when standing (no idle clip); the beam's charge
  plays BEAM_BAKED up to the aim in CHARGE_TIME and holds it while firing; the
  swipe plays SWIPE_BAKED so the blow lands as the wind-up ends.
- **Cyan**: the crystal colour is read off its material (0.0, 0.91, 1.0). The
  state material (enemy.gd's `_material`, via an invisible proxy given as its
  `mesh`, since enemy.gd overrides its mesh's whole material) is put on the
  crystal surface; the eyes are emissive lenses at the EyeL/EyeR markers with
  their own copy at `EYE_GLOW` 0.35 of the glow -- on the same material the
  bloom ran the two eyes (0.11 m apart) into one ball, and halo cards made it
  worse (removed). Beam core/glow/light and the HUD's screen-edge beam glow are
  cyan.
- **Shield swipe knocks down** (`enforcer._try_connect` over enemy.gd's, the
  player's `guarded` signal read during the blow): unguarded ->
  `player.knock_down(dir, 7.5)`; blocked -> 10% and `apply_knockback` 4 (on
  their feet); parried -> nothing (the parry throws the enforcer). player.gd:
  `knock_down` throws the body back (+2.6 up), locks control through the slam
  recovery's `_slam_recover_until` for KNOCK_FALL 0.32 + KNOCK_UP 0.5 s with the
  slide bleeding off at KNOCK_FRICTION 9 (the recovery's own stop killed it in
  0.4 m), and `_knock_view` drops the view 1.28 m onto its back (+34 deg pitch,
  16 deg roll) and brings it up over the half second. Still hurtable.
- Measured (harness, 21/21): 57 enforcers, no "wardens" group; clips present;
  crystal colour read; eyes and crystal on the state colour; walks in on
  WALK_BAKED (rate 1.22); fires on BEAM_BAKED, cyan, 4.2 damage; unguarded swipe
  on SWIPE_BAKED: 22 damage, thrown 3.06 m, down and up in 0.82 s, view 1.28 m
  low; block 2.2 standing; parry 0. Harness trap: a guard held past the first
  swipe meets the next as a block -- judge the first only.

