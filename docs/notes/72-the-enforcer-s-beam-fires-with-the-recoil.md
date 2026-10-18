## 72. The enforcer's beam fires with the recoil; the arms aim it; seamless blends (2026-10-17)

The user: apply the decrepit's blending to the (surface) enforcer; "the beam
animation and recoil animation should work together and the beam should only
start during the recoil animation"; "once beaming, both arms should adjust
vertical rotation to face the player, since the beam comes out at an angle";
"remove any dynamic shaking of the beam arm for now"; and the swipe's arm
"clipping through the body".

- **Beam timing** (enforcer.gd): the charge plays BEAM_BAKED up to its settled
  pose with NO beam (the thin aiming line is gone). Firing plays
  BEAM_RECOIL_BAKED ONCE at rate 1 and holds its last frame (`_freeze_at`,
  HOLD_EARLY) -- no more ping-pong (RECOIL_RATE removed: that was the "shaking").
  The beam comes on with the kick, `RECOIL_BEAM` 8/60 s (frame 9) into the
  fire, on the fire's own clock (`_fire_t0`, `_beam_live`), opening from a
  third of its width over BEAM_FLARE_IN 0.08 s; BEAM_TIME runs from then. The
  timing preview shows it as a draggable "BEAM ON: the kick" marker on
  BEAM_RECOIL_BAKED (frames).
- **The arms aim** (enforcer_react.gd `aim_at` / `set_barrel` / `_aim`): in
  the firing pose the barrel points 12-15 deg DOWN and ~5 deg to the side
  (measured), and the beam went from the muzzle straight at the player. Now,
  from the fire's start, both shoulders (the cannon rests on the shield arm)
  are pitched together about +X around a pivot midway between them until the
  barrel's elevation is the beam's; eased in/out over AIM_EASE 0.15 s, at most
  AIM_MAX 0.7 rad; letting go eases out the LAST angle (recomputing from the
  walk's hanging arm asked for a 40 deg turn up -- a snap). The barrel is the
  line from ARM_R's joint to the Muzzle marker (the marker's own axis is NOT
  the barrel: it points 74 deg down). Yaw: the body turns by the barrel's side
  angle (`barrel_world`, read off the clip pose every frame; `_barrel_facing`,
  eased at BARREL_YAW_RATE). Measured: barrel vs beam 0.1 deg worst (the clip
  alone: 7.6 deg at 10 m, 2.2 at 5 m, 22.7 with the player 3 m up, 7.5
  strafing).
- **Blending as the decrepit's** (note 59): the walk is re-entered at the phase
  nearest the pose shown (`_match_phase`, decrepit.gd's), its rate eased at
  WALK_RATE_EASE 7/s from a standstill, and an engaged enforcer keeps the layer
  tracking (`keep_tracking = engaged`, switched back on if it had gone idle --
  setting the flag alone did not wake it).
- **A blend bug, both rigs** (enforcer_react.gd `crossfade`): the switch's
  start frame was the frame the pose last CHANGED; a rig standing still had
  changed seconds earlier, its fade counted as already over, and the switch
  snapped (walk -> beam: the shield arm 0.3 m in one frame, every time). Now
  the frame it was last SHOWN (`_base_frame`).
- Measured (throwaway harness, deleted: sandbox, real time, the shown pose read
  in `skeleton_updated` -- a script reading bone poses afterwards gets the RAW
  clip, the modifier's changes are not kept -- resampled at 60 Hz): the worst
  bone acceleration in the 6 frames after each switch against the clips' own
  99th percentile: walk->charge 0.22x (was 1.6x, the snap), charge->recoil
  0.11x, recoil->walk 0.09x, walk->swipe 0.21x, swipe->walk 0.22x. Decrepit,
  same run: 0.02-0.10x, the dropkick's own whip 0.35x.
- **Imports at 60 fps** (models/enforcer.glb.import, decrepit.glb.import):
  `animation/fps` was 30, so Godot resampled the 60 fps clips at half rate and
  interpolated across the gaps (SWIPE_1_BAKED's ARM_L 105 deg between two kept
  keys, the dropkick 126). Now 60.
- **The swipe's arm through the body is in the clip** (left to the user, who
  is fixing it in Blender): SWIPE_1_BAKED's baked IK FLIPS the shield arm --
  f13 -> f14 the elbow swings 148 deg round the shoulder-shield line in one
  frame (SHOULDER_L 135 deg, ARM_L 95 deg) while the shield itself moves
  normally, and again over the strike f22-25 (SHOULDER_L 98 deg at f23). Seen
  frame by frame in Blender it is invisible; the game plays the clip at x0.58
  and interpolates between frames, sweeping the arm through the torso. The
  enforcer's IK constraints change the baked pose by 5 mm at most.
