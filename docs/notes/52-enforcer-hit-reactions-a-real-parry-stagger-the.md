## 52. Enforcer hit reactions, a real parry stagger, the recoil looped, clean blends (2026-10-15)

- **The recoil loops while it fires** (`ANIM_RECOIL_CLIP` LOOP_PINGPONG at
  `RECOIL_RATE` 1.6): played once and held it was one 14 cm kick at the start of
  a 3.2 s beam -- "I couldn't tell if it was". Its first frame IS the aimed
  pose, so every pass starts and ends there. Measured: 0.16 m of muzzle travel,
  15 reversals in one beam.
- **`scripts/enforcer_react.gd`**, a SkeletonModifier3D under the enforcer's
  Skeleton3D: the hit reactions and the parry stagger as a layer OVER whatever
  clip plays. Keyframed in skeleton space (+Y up, +Z the mech's front, +X its
  left; channels torso / head / shoulders / arms as small rotation vectors in
  degrees, "hip" offset in leg lengths), authored for a blow from the front and
  turned at play time to face the attacker (`_start` yaw), so it always rocks
  AWAY; cubic keys, flat at both ends. Legs are not keyed: two-bone IK
  (`_solve_leg`) from the moved hips to the feet where the clip has them, so the
  feet stay planted while the hips drop and twist. Rig facts: TORSO is the root
  at hip height, the legs hang off it, FOOT_L/R sit under separate root bones
  (FOOT_*.001); deform bones are TORSO, HEAD, SHOULDER_*, ARM_*, THIGH_*,
  CALF_*, FOOT_*; ARM_*.001 are unweighted IK leftovers.
  - Three hits (`HITS`: chest rock-back, high twist, crushing dip), random,
    never twice running, half mirrored, scaled by damage (`HIT_FULL` 20); played
    from `take_damage` on every blow that lands.
  - `STAGGER` (2.1 s) on a parried swipe (`_on_player_guarded` -> `_parry_stagger`):
    thrown back on its heels, arms flung wide, knees buckling, staggering side to
    side, catching itself leaning forward, with a fading servo judder; the stun
    is `PARRY_STAGGER` 2.1 s (was the player's 0.9 for any enemy) and it stands
    meanwhile (the walk eased to a stop). Hits during it are not layered on.
  - `_flinch` is a no-op for the enforcer (enemy.gd's tipped the whole model
    over rigidly, feet and all), and so is the hit SQUASH in `_flash` (it scaled
    the model in one frame -- measured as the head jumping 6-10 cm a frame).
- **Crossfades are the layer's, not the AnimationPlayer's.** Godot's fade advances
  by delta x `speed_scale`: fading into a clip HELD at speed 0 never progressed,
  and at speed 1 it lurched over its first two frames (ARM_L 0.29, 0.38, then
  0.1). `_play_clip` now switches outright (`play(clip, 0)` + `seek(0)`) and
  first calls `crossfade(blend)`: the last pose shown is eased into the new clip
  on real time. Traps hit: a seek right after `play(clip, blend)` threw the
  engine's fade away (one-frame snap); and the layer switches itself OFF when
  idle (so far-off rigs are not updated every frame), so its stored pose can be
  stale -- `crossfade` uses it only if it was taken last frame (`_base_frame`),
  else reads the skeleton. The swipe's fade is 0.18 s (0.1 moved the legs
  0.46 m in four frames).
- Measured (harness, 19/19 twice): the layer runs with the rig otherwise still;
  a chest hit moves the head 8 cm AWAY from the attacker, and from behind the
  other way; the crush drops the hips 9 cm with the thigh's length exact under
  IK (0.4728 = 0.4728); every reaction alone ends exactly at rest (0.0000) with no
  frame over 1.1x its neighbours; picks cover all three, no repeats; recoil as
  above; a real right-click parry staggered it for 2.10 s with no attack; and
  across a recorded fight (walk, charge, fire, vent, swipe, parry, 8 hits) 0
  snaps at any transition. The detector caught the seek snap, the squash and
  the stale-pose snap before each was fixed. The walk clip's own foot plants
  (a dead stop after each swing, in the user's animation) are not counted.
- Bench (RTX 3060, 3440x1440, editor closed): 67.0 fps, worst p99 31.25 ms,
  1157 MB (66.9 / 35.70 before) -- noise.

