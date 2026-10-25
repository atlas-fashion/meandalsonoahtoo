## 103. The claw opens and shakes before it drops; a block is caught, a parry knocks it limp; the vats a bit faster (2026-10-25)

The user: "the claw should open its claw and shake lightly before dropping to
catch the player. If the player is blocking, the claw should still get the
player. The player should be able to parry the claw, with the nice purple
visual feedback and the claw should get knocked up, go limp for 2 seconds,
and continue chasing the player. the player should be able to move the vats a
bit faster." Builds on notes 99 and 102.

### The fingers (`surgical_table.gd` `_rig_claw`, `_pose_fingers`)

claw.glb is one 8753-vertex mesh, so it had no fingers to move. A height
histogram of its vertices shows three fingers at bearings 30, 150 and 270
degrees (atan2(z, x) in the model), apart below y -1.1 and joined in the hub
above -0.8. `_rig_claw` skins the mesh at load time, once, shared by every
copy:
- a Skeleton3D with a "hub" bone and three finger bones, each finger's rest
  at its knuckle (KNUCKLE_Y -0.85, KNUCKLE_R 0.14 out along its bearing);
- each vertex goes to the hub and to the finger whose bearing is nearest. The
  finger's weight rises smoothly from 0 at FINGER_FROM -0.72 to 1 at
  FINGER_TO -0.98, so the bend spreads over the knuckle instead of creasing;
- the new ArrayMesh keeps the surface's material, so `grade` and `glow` still
  find it.

`_pose_fingers(open, shake)` swings each finger about its knuckle's tangent:
out above 0 (FINGER_OPEN 0.75 rad), in below 0 (FINGER_SHUT -0.3). `_open`
eases toward `_open_goal` at `_open_rate`.

What the fingers do in each state:
- asleep: a little shut;
- hunting: relaxed;
- waking: they open and close as the arm pays out;
- the slam: opening as it draws up, wide during the shake, snapping shut (rate
  30) as it lands, dug in while stuck;
- carrying: shut;
- strapping: picking at the player;
- limp and dying: hanging half open, splaying as it swings.

The screenshots show no tearing at the knuckles.

### The slam (`_slam`)

WIND 0.35 s (opening) -> TRACK -> **SHAKE 0.3 s** -> LOCK -> DROP 0.17 s.
- **SHAKE** is new. The claw is open wide and still following the player. It
  shakes lightly: the whole claw trembles 0.025 rad and wobbles 1.8 cm, and
  each finger trembles 0.07 rad on its own.
- **The parry cue** moved here from LOCK, listening SHAKE + LOCK + DROP (about
  0.6 s). A block pressed any time from the shake starting to the landing
  parries.
- **TRACK** is 0.15 s shorter ([0.35 .. 0.15] by level), so the slam takes
  only 0.15 s longer overall. Level 0 lands at 1.33 s (1.19 before).
- **LOCK** keeps shaking, and its old stronger shudder is gone.

### Block and parry (`_impact`, `_strike`, `_knocked`, `_limp`)

- **A block is caught.** `_impact` no longer spares a guarded player from the
  grab. The block still takes its 90% off the 12 damage and still saves an
  outer player from being knocked down.
- **Any guard meets it.** `_strike` now gives the blow as travelling back
  along the player's own facing. Before, it was the flat line from the wrist,
  which is near zero when the claw lands right on them and fell back to the
  table's own -Z. That made the front-arc check random, so a parry could
  fail for no visible reason.
- **The purple flash.** It is the player's own (`_on_guarded`: flash, sparks,
  light, hit-stop). Because the attacker passed is the TABLE, in the middle of
  the hall, `guard_flash_centre()` returns true during the strike so the flash
  goes in the middle of the view. Without it, the flash would have pointed
  toward the table.
- **The parry's echoes.** The player's echoes of a parry (`take_damage` of
  half the blow, `apply_knockback`) are ignored while `_striking`. Before, the
  echoed damage made the table ring and threw sparks at the table, far from
  the claw.
- **Parried → `_knocked`.** A burst of the player's `parry_color` sparks comes
  off the fingers, the fingers fly open, and the swing gets a KNOCK_SWING 4.0
  kick away from the player(s). Then State **LIMP** (12, a new last value of
  the enum, so the saved numbers stand):
  - KNOCK_TIME 0.25 s hauled up at 18 m/s, KNOCK_RISE 1.2 m over where it
    hovers. 4.4 m up from the floor was measured;
  - then LIMP_TIME 2.0 s slack: the drives coast to a stop, the arm sags 0.4 m
    under its hover, the swing's damping drops to 0.3 of normal, and the
    power gutters (0.2-0.35, flickering), dimming its eye light and the glow;
  - then the fingers jerk shut, it is back in HUNT and chasing at once, with
    the next slam after the usual REAR_COOLDOWN.
- `PARRY_STUCK` (a parried claw stuck 3 s in the floor) is gone.

### The vats (`surgery_vat.gd`)

PUSH_SPEED and ACCEL 0.8 -> 1.1. BREAKAWAY (0.55 s before it gives), the
lurches, the turning and the brake are unchanged. Measured holding
move_forward into a vat:
- 0.000 m in the first 0.35 s;
- **1.85 m in 3.35 s** (1.35 m before);
- 0.20 m more after letting go.

### Measured (throwaway harness, headless, driving the real game; deleted)

23/23 passed:
- the claw rigged with 4 bones;
- the vat numbers above;
- it wakes and hunts;
- unguarded: the shake starts 0.70 s in with the fingers 0.75 rad open, the
  player is caught, and the fingers are at -0.30 on them;
- the guard up (block held) before the cue: one block registered, caught all
  the same;
- block pressed 0.15 s into the shake: one parry, LIMP, not caught;
- knocked up 4.37 m, then 2.24 s of game time in LIMP (0.25 + 2.0);
- back to HUNT, over the player within 1.5 s, and it slams again.

Re-broken (a guarded player spared again; SHAKE_TIME 0) gave 8 failures, as it
should. Windowed screenshots: the claw shaking open and glowing, shut while
holding, and dark and swung aside while limp.

### Traps

- **A windowed run while another game holds the GPU runs at ~1 fps.**
  Physics then can't keep up and game time runs ~9x slower than the wall
  clock. The table's slam phases count game time (`_t`), but its parry cues
  and cooldowns, and the player's block press, count the wall clock
  (`_now()`), so timing tests fail for no real reason. Run timing tests
  headless, and check `nvidia-smi` when a windowed run is slow.
- **A harness's block must hold the action.** `_check_block` drops the guard
  when `block` isn't held (`Input.action_press(&"block")`). A parry needs only
  the press (`_note_block_press`).
