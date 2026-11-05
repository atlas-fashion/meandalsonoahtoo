## 167. Higgsfield attack clips, the spear's combo and sweep, faster proels (2026-11-05)

The user asked for several things:
- Higgsfield animations for all of the player's attacks and the parry;
- the sword swipe slightly later than before, the heavy later still, and a very
  elaborate ult;
- every animation smooth into every other, and swipes alternating sides;
- spear clicks: two short jabs, then a third that comes a hair later, moves the
  player forward and does a little more damage, then a hair's wait before the
  jabs start again;
- spear Q: a delayed swipe like the scout's, which knocks enemies down;
- faster proel swordsmen;
- the player model doing the same animations as the first-person view.

Then: "all animations should be hyperrealistic, utilizing dynamic speed for
emphasis and weight", and "don't use the model that higgsfield made though, use
the one already in the game". Only the bones' MOTION comes from Higgsfield. Every
mesh it returned is thrown away, and the clips play on `models/player_knight.glb`
(note 166).

### The clips (Higgsfield 3D Rigging = Meshy's action library)

How they were made:
- `models/source/knight/knight_meshy.glb` was uploaded (`media_upload`) and rigged
  with `animation_action_id` set: one clip per job, 8 credits each.
- 11 jobs, 88 credits; 174 credits left.
- The rig is Meshy's own 24 bones, the same names as the knight's (note 155).
- `tools/strip_anim_clip.py` (Blender 5.2) cuts each 8 MB result down to its
  skeleton, its clip and one skinned triangle, about 40 KB, into
  `models/anims/<name>.glb`:
  - The triangle is needed: without a skinned mesh, Godot imports the bones as
    Node3Ds.
  - The scene runs at 30 fps for import and export, Meshy's rate. At the default
    24 the clip was resampled.

| game clip | Higgsfield action | used for |
|---|---|---|
| sword_swipes | Left_Slash (97) | forehand (0-1.1 s), then the backhand from where it ends (1.08-2.45 s) |
| sword_heavy | Charged_Slash (242) | Q: a long gathering sweep to the left, then an explosive backhand |
| sword_ult | Sword_Judgment (102) | F: crouch, leap, airborne cut, deep landing, flourish, last sweep |
| sword_parry | Sword_Parry_Backward (148) | the recoil off a parried blow |
| spear_jabs | Punch_Combo_3 (203) | the two short jabs |
| spear_lunge | Thrust_Slash (240) | the third: drawn back, then driven through with a step |
| spear_sweep | Axe_Spin_Attack (238) | Q: wound high, swept low from left to right |

Also generated and not used: Right_Hand_Sword_Slash (219, one cut that spins),
Triple_Combo_Attack (105), Weapon_Combo_2 (241) and Sword_Parry (147, a static
hold). Left_Slash won the swipes because its forehand ends exactly where its
backhand begins, so a chained pair meets frame for frame and the sides always
alternate.

### `scripts/player_motion.gd` (`PlayerMotion`)

- **Baked**: each clip's forward kinematics at 60 Hz, in knight space. For every
  bone it stores its turn from rest; it also stores the right fist and shoulder
  relative to the eye, and the head's height. 3-7 ms a clip, all 36 ms of it
  done at load (`warm`, from player.gd `_ready`).
- **MOVES**: each move is a stretch of a clip on the game's clock, through
  `knots` [pose s, clip s]. A monotone cubic runs through them (Fritsch-Carlson,
  `_warp`), so the clip never runs backward and its speed never jumps. That
  carries the dynamic speed:
  - a slow gather;
  - a hang at the top;
  - the cut at 2.5-3x the capture;
  - the follow-through bleeding off.

  Each move blends in from whatever pose came before (`in`) and out to rest
  (`out` → `end`).
- **Body** (`body_pose`): coop_avatar.gd `_apply_motion` lays it over the walking
  pose, blended in and out with the move.
  - It retargets in knight space: each bone takes the clip's turn from ITS rest,
    so neither rig's bone axes matter.
  - The legs and hips' travel give way to the stride while walking.
  - The parry plays on the upper body over the guard.
  - `_skel.reset_bone_poses()` each frame, or the neck and shoulders kept the
    clip's last turn.
- **First person** (`fp_sword`): the sword's pivot is where the capture's fist is
  relative to the eye. The eye and the 9 cm shoulder drop match
  first_person_arms.gd's, and the arm's shoulder is carried by the torso's twist
  (`fp_shoulder_shift` → `_shoulder`'s `extra`), so the fist is always in reach.
  The whole arm sits `FP_LOWER` 12 cm lower through a move.
- **The grip** (`BLADE_REST`): out along the arm and up, half way between, with
  the edge forward. It was read off the capture's own prop sword in Higgsfield's
  preview GIFs:
  - straight up in the wind-up;
  - across the front pointing left at the cut;
  - out to the left as it follows through;
  - the heavy's backhand ending pointing right.

  Straight out of the thumb (+Z) pointed the blade down the view through every
  cut.

### The sword (player.gd)

All times are pose seconds, ×1.25 for real ones.

| | bites | real time to the hit | was |
|---|---|---|---|
| forehand `slash` | 0.18-0.29 | 0.225 s | 0.156 s (note 164) |
| backhand `chop` | 0.15-0.26 (from the forehand's end) | | |
| heavy (Q) | 0.62-0.76 (`HEAVY_BITE`, `HEAVY_HOLD`) | 0.78 s | 0.59 s |
| ult (F) | wave at `WAVE_FIRE` 0.64, committed to 0.76, home by 2.35 | | |

- **Heavy**: the cut lands 0.78 s after Q (0.59 in note 162), length 1.15.
- **Ult**:
  - The wave is thrown at `WAVE_FIRE` 0.64, in the air.
  - The move is committed to 0.76, home by 2.35. After WAVE_HOLD the flourish
    can be cut into.
  - The view rides the leap and the landing: `_motion_rise`, 0.8 of the head's
    rise for the ult and 0.35 for the other moves.
- **Aim** (`_aim_fix`): the captures cut high. The backhand's tip crossed in front
  3 m up, and the heavy's at 2-2.6 m, over a proel's head.
  - Each move's stroke is turned about the eye so the blade's sweet spot
    (`CUT_SPOT` 0.6 along it) crosses the crosshair's line at `CUT_ELEVATION`
    -7°. Worked out once per move: slash +22°, chop -50° (the clamp), heavy -24°.
  - The turn is in full through the bite and eased in over the wind-up and out
    over the recovery (`_aim_weight`), so every move still starts and ends as
    captured and chains without a jolt.
- **Blends** (`_arc_blend`): a straight blend from the forehand's follow-through
  (high left) to rest (low right) ran the arm under the eye, so blends bow out
  and down (`BLEND_ARC`).
- **Parry** (`_parried_pose`, `_parry_t`): the clip's fist motion since its stance,
  turned about the grip, laid over the guard. Only `PARRY_TURN` 0.55 and
  `PARRY_SHIFT` 0.4 of it: the full capture snaps the fist back 0.5 m and 60°,
  and over the drawn-back guard that put the hilt in the face.
- The old posed strokes are gone (`_swing_pose`, `_heavy_pose`, `_wave_pose`,
  `_arc_pose`, `_cut_pitch` and their constants). The trail samples
  `_motion_pose`.

**Measured.** A headless harness: a frozen enemy at 1.4, 1.9 and 2.4 m, and the
player pinned in place.

| | 1.4 m | 1.9 m | 2.4 m |
|---|---|---|---|
| old: slash, chop, heavy | hit | hit | all three missed |
| new: slash | hit at 0.267 s | hit | hit |
| new: chop | hit at 0.233 s | hit | hit |
| new: heavy | hit at 0.867 s | hit | hit (missed on one earlier run, at the edge) |

The wave hit for 130.

### The spear (spear.gd)

**LMB: jab, jab, lunge.** `COMBO` [&"jab_a", &"jab_b", &"lunge"].
- Jabs are `STAB_EVERY` 0.25 apart, `STAB_DAMAGE` 10 each.
- The lunge comes `LUNGE_AFTER` 0.33 after the second jab. It bites at
  `LUNGE_OUT` 0.2 for `LUNGE_DAMAGE` 16 with `LUNGE_REACH` 3.2, and carries the
  player `LUNGE_STEP` 1.1 m (`player.begin_spear_dash`, the old dash's carry,
  which stone stops).
- `LUNGE_REST` 0.58 passes before the next jab.
- Held clicks fire on the beat. A combo left `COMBO_FORGET` past its beat starts
  over.
- Measured, holding the button: hits at 0.117, 0.417, 1.000 (16), 1.567, 1.883,
  2.467 s. The player moved 1.92 m over two lunges.

**Q: the sweep** (was the dash). The scout's delayed swipe:
- `SWEEP_STRIKE` 0.55 pose, which is 0.69 s real (the scout's is 0.6).
- Everything in a box in front gets `SWEEP_DAMAGE` 22 and is knocked down: the
  box reaches `SWEEP_REACH` 3.0 out, `SWEEP_WIDTH` 3.6 across and `SWEEP_HIGH`
  1.3 up.
- `SWEEP_COOLDOWN` 2.4. The player is planted at `heavy_move_scale` through it. A
  blow in the wind-up cuts it off.
- **Knocked down** (`_knock_down`):
  - `knock_down_from(away)` where an enemy has a fall of its own: decrepit.gd
    goes over on its back, as a parry throws it; sword_skeleton.gd (the proels)
    does `reel_from(away, true)`, the thrown clip.
  - Everything else is thrown `SWEEP_PUSH` and stunned `SWEEP_DOWN` 1.4 s.
- Measured: hit at 0.717 s for 22, stunned 1.38 s.
- HUD: a `&"sweep"` glyph (attack_icons.gd). The inventory stats and the intro
  lesson ("Spear sweep") are updated.

**First person.**
- The jabs and lunge are the clip's fist motion since its stance, driven down the
  crosshair. `JAB_DRIVE` 1.9 with the sideways drift halved; `LUNGE_DRIVE` 0.7.
- The SWEEP is posed instead (`_sweep_pose`) on the clip's timeline and with the
  body's directions: wound up high on the left, a hang, swept low left to right.
  The capture is a whole-body spin, and from inside the head its fist rose a
  metre and the forearm turned end over end. The first-person shoulder stays put
  for it.
- The body plays all three clips as captured.

### The proel swordsmen

- `BLOW_TEMPO` (prosthetic.gd) and `TEMPO` (tools/anim_sword_skeleton.py) go from
  1.725 to 2.24 (×1.3).
- Re-baked with `blender -b models/source/sword_skeleton/sword_skeleton.blend -P
  tools/anim_sword_skeleton.py` (21 s).
- `[reach]`: every blow lands inside its window (lights at A+0.06-0.08 of 0.11,
  heavies at A+0.09 of 0.13).

### Traps

- **A frame change is not a turn.** The fist's basis is absolute, so to head space
  it is `K2H * h.basis`. Conjugating it (`K2H * h * K2H⁻¹`) pointed the blade back
  at the viewer.
- **Placing the fist by the eye alone put it out of the arm's reach.** The
  capture's shoulder moves with the torso's twist, and the first-person arm's did
  not, so the IK slid the shoulder into the camera. Carry the shoulder.
- **Test harness: an enemy spawned on the player shoves it.** The player ended
  up 1.8 m up on the enemy's head, and every swing "missed".
  - Settle the player first.
  - Freeze the enemy (`set_physics_process(false)`).
  - Pin the player each tick.
  - With the enemy half in the floor, the old code missed too.
- `rm` of a glob under a path set by `cd` is refused by the safety check; use
  `${VAR:?}` paths.
