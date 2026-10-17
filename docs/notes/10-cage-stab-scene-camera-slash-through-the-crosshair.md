## 10. Cage stab, scene camera, slash through the crosshair (2026-10-07)

- **The sword is 2.08 m from guard to tip** (`player.blade_length()`), and the
  old stab stood the player 1.69 m from the skull: the blade ran dead through
  its centre but the TIP ended 1.54 m beyond it, inside the stone, and drawn on
  top of everything it simply covered the skull. Now `stab_at(target,
  through)` solves the hilt along the line from `STAB_SHOULDER` so the tip ends
  `through` (0.14) past the target, and the cage stands the player off by
  blade length + `STAB_REACH` 0.9 - 0.14 (`bone_cage._stab_stand`, clamped by
  a ray to the far wall). During the stab the sword's `z_clip_scale` goes to
  1.0 -- real depth, so the skull hides the buried tip -- and back to
  `sword_draw_depth` as it comes out (only the uniform changes; toggling
  `use_z_clip_scale` would compile a shader variant mid-scene). Measured: tip
  0.140 m past the centre, 0.000 m off line, eye 2.77 m from the skull.
- Stab timeline: cocked 0.30, held quivering to 0.40, driven in by 0.47
  (`stab_landed`: hit-stop, the skull pinned and shuddering, eyes x4), wrenched
  round by 0.66 (`stab_wrenched`: the skull bursts), out by 1.2.
- **Scene camera** (`player.scene_look_at(point, rate)`, `scene_frame(zoom_deg,
  roll_deg, rate)`): holds the view on a world point through the whole scene,
  walking included (`_scene_walk` no longer turns to the walk direction while a
  look is set), and pushes the FOV in / tilts the horizon, eased on the REAL
  clock. Cleared by `end_cutscene` and `_respawn`. The cage scene: letterbox
  (`wood_door.letterbox()` / `letterbox_out()`, now static), view on the skull
  (worst 3.7 deg off it after the first 0.9 s), push in 4 -> 9 -> 14 deg with a
  -3 deg tilt on the draw, 18 / +4 at impact, out as the coins fly.
- **The slash passes through the crosshair** (`_cut_pitch`): the blade is
  pitched so its line, from the guard's real place on the model, runs through
  the point `SWING_CROSS` 2.0 m down the view, on a high-to-low diagonal of
  `SWING_TILT` 0.42 rad that is zero exactly where the blade heads at that
  point. Measured on the pose function at 1 ms steps (rendered frames skip it:
  the cut sweeps ~0.4 rad a frame): 4.4 / 3.8 px from the centre; the old arc
  (pitch 0.1 -> -0.32) 124 / 121 px. Hits on a skeleton 1.2-2.4 m ahead, level
  and looking down: 15 of 16 (the miss: a level slash at 2.4 m, the tip's edge).- **Slash damage 32 -> 24** (`attack_damage`; the thrust stays 40). Measured: 24
  dealt to a skeleton 1.6 m ahead.
- **The white slash trail runs through the crosshair** (`_update_sweep_trail`).
  It traced the TIP, which passes 72-74 px off the crosshair (the blade crosses
  the view axis well short of its tip). It now traces `_trail_point()`: the
  point on the blade that actually crosses the axis, found once by running a cut
  through the pose function a millisecond at a time (a fixed distance worked
  out from `SWING_CROSS` passed 4 cm high: 16 px -- the cut crosses nearer,
  ~1.74 m). Samples are taken from `_swing_pose` every `TRAIL_STEP` 4 ms between
  frames (straight chords between frames cut inside the arc), and kept in the
  HEAD's frame like the sword: in world space the view kick and lunge carried the
  camera on after the blade had passed, and the streak sat 69-158 px off the
  crosshair, stair-stepped at each frame's join. Measured: 0.4 px on both
  strokes, level and looking down, on every frame while the crossing is on
  screen. The ribbon now gathers its vertices before `surface_begin`.- **Damage: cut 20, thrust 50** (`attack_damage`, `thrust_damage`; measured).
- **The thrust plants the player for a second** (`_thrust_planted()`): the
  hilt is drawn back over `THRUST_PULL` 0.3 s and held, coiled, to
  `THRUST_DRAW` 1.0 s; meanwhile ground movement decays to zero as in the slam
  recovery and jump is refused. Then the drive and the lunge: timeline HIT 1.12
  / HOLD 1.24 / END 1.67, `thrust_lunge` 9.5 -> 15. Measured with forward held:
  4.18 m/s walking before, 0.00 m/s from 0.25 s to the drive (0.28 m of drift
  while stopping), no jump; lunge 3.22 m from standing (was 1.26).- **Thrust wind-up is half a second** (2026-10-07): `THRUST_PULL` 0.22, `THRUST_DRAW`
  0.5, HIT 0.62, HOLD 0.74, END 1.17. Still planted (measured 0.00 m/s with
  forward held), drive at 0.517 s.
- **Lunge speed lines** (`shaders/lunge_lines.gdshader`, the HUD's `LungeLines`
  ColorRect built in code by `hud._build_lunge_lines`): white dashes racing
  outward along angular lanes, the middle kept clear for the crosshair, and a
  soft white rim; driven by `player.lunge_intensity()` (in over 60 ms, out over
  `lunge_effect_time` 0.45 s from the drive, GAME clock via `lunge_age()`), with
  the view opening out by `lunge_fov_kick` 7 deg (measured +5.9 peak). Gated on
  `Graphics.effects` and hidden at rest. The first lunge cost a 28.8 ms frame
  (the canvas shader compiling on first draw); the HUD now draws it once at
  strength 0 for 0.3 s at load: first lunge 17.9 ms, second 17.5, idle 17.1.- **Block 10%, parry 0% and half back** (2026-10-07): `block_damage_taken` 0.1,
  `parry_damage_taken` 0.0, and a parry now calls the attacker's
  `take_damage(blow * parry_reflect)` (0.5 of the blow it threw, AFTER the
  knockback so a killing blow does not shove a corpse) and emits `hit_landed`
  for the crosshair marker. A blow reduced to nothing returns before the damage
  marker. Measured: unguarded 40 -> 40; parry 40 -> 0 taken, attacker -20;
  block 40 -> 4; from behind while blocking 40; a real skeleton's 14-point blow
  parried: player untouched, skeleton -7. Harness trap: `_start_block()` alone
  does not hold a guard -- `_check_block` drops it next tick unless the button
  is really down; press the real right mouse button (`parse_input_event`).
