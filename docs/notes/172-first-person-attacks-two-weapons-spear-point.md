## 172. Made for the eyes: the view turns with the body, a smoother attack camera, two weapon slots, the spear's point leads (2026-11-09)

The user:
- "All the animations look good in 3rd person, but the game is meant to be
  played in 1st person. Make it optimized for 1st person. If the player spins
  around, the camera should too very seamlessly."
- "Reduce the camera movement on the attacks a little bit. I like them but I
  want all the camera 'head' movement to be very smooth and extremely
  lifelike."
- "The player should have 2 weapon slots, not 4. For now, do away with the axe."
- "The spear should hit with the sharp edge of his spear when attacking all 3
  times. Right now the player is attacking with the blunt end for the first 2."

(The reverted commit 948a099 had used the number 172 for "the sword with
weight"; its note went with the revert. This is the new 172.)

### Why first person looked wrong

The captures turn the WHOLE knight. Measured, the head's turn since the stance
(headless harness over `PlayerMotion`):

| move | head turns |
|---|---|
| forehand `slash` | 95 degrees left, then back |
| backhand `chop` | 95 back the other way |
| heavy | 155 left, then the backhand back past the start |
| jabs (Punch_Combo_3) | 65-83 into each punch |
| lunge | 40 |
| sweep (Axe_Spin_Attack) | a full -360 |
| ult (Sword_Judgment) | a full -360, ending 27 past it |

The camera took only `Graphics.head_sway` (25%) of that, so from the eyes the
body wheeled away under a still view and the weapon swung out of sight behind
the head, then came back.

### The view turns with the body (player_motion.gd, coop_avatar.gd, player.gd)

- **The ride, baked per move** (`PlayerMotion._ride`, at `warm`): the head's
  turn about the vertical (`ride_yaw`, unwound, so a spin reads -360 rather
  than jumping at 180), what is left of it (`ride_nod`: pitch and roll) and its
  offset (`ride_offset`), sampled at `RIDE_HZ` 120 over the move's own clock and
  smoothed with a centred Gaussian (`RIDE_SMOOTH` 0.03 s, no lag). The capture
  is 30 fps, joined linearly; every frame of it was a kink in the view.
- **The turn is measured from the STANCE's head** (`_head_abs(&"stance", 0)`),
  not the move's first frame. The body blends in from the stance, and the sweep
  starts with its head already 35 degrees round, so measured from its own first
  frame the view ran 25-50 degrees behind the head all through the spin.
- **How much the view follows** (player.gd `view_follow`): all of a `spin` move
  (the sweep, the ult); otherwise Head sway x `ATTACK_CAMERA` (0.25 x 0.8 = 0.2
  by default) x the move's `turn` (0.4 for the jabs, which are a boxer's
  punches).
- **The body is turned back by the rest** (`PlayerMotion.body_counter`,
  coop_avatar.gd `_apply_clip`): every bone of the clip, and the hips' offset,
  turned about the vertical by `follow x smoothed turn - raw turn`. So the
  knight's head always faces where the camera looks: a forehand turns the body
  and the view about 19 degrees together and the cut crosses in front of the
  eyes; the sweep and the ult turn both right round. Not the stance, not the
  upper-body parry (its hips are the stance's, so the turn would cancel).
- **What an attack throws or drives goes down the crosshair**, not the turned
  view: `player.aim_forward()` is the camera's forward with the attack's turn
  taken out. Used by the wave's launch, the heavy's lurch, the spear's stab box
  and its throw. Before this, the ult's wave went off 50 degrees to the side,
  mid-spin, and missed a target 2.4 m ahead.

### The attack camera: 20% less, and sprung (player.gd)

- `ATTACK_CAMERA` 0.8 of everything an attack does to the view: the head's
  nod and offset, the wave's and heavy's leans (`_wave_effort`,
  `_heavy_effort`), the stab's (`_stab_effort`, its push), the swing's punch
  (`attack_view_kick`, `attack_view_roll`).
- `RIDE_ROLL` 0.5 more off the head's roll: a head keeps the horizon nearly
  level.
- **One spring for all of it** (`_update_attack_view`, `_track`): a critically
  damped spring (`RIDE_SPRING` 26 rad/s), solved exactly over the step so it is
  stable at any frame rate. The ride's own speed is fed forward (worked out from
  the move's clock, `_ride_at` at t and t - 1/120), so smooth motion is followed
  with no lag; only what would have jumped -- a move cut into the next, a punch
  starting -- is eased, over about 2 / 26 s, never overshooting.
- A whole turn is no turn: before the spring, the state is unwound to the
  target's nearest turn, so the end of a spin hands back without unwinding.
- The head's composition: `_view_off` on the position, `_view_rot.x` / `.z`
  added to the look's pitch and roll, `_view_rot.y` premultiplied as a turn.
  The look itself is never smoothed.

### The spear's point leads (spear.gd, first_person_arms.gd)

Seen from the eyes before: through both jabs the spear lay along the punching
fist's grip line, and its bound BUTT was driven at the crosshair, the point
somewhere behind the camera. The lunge (Thrust_Slash) was point first.

- **Through the stab the spear leads** (`lead`, 0..1, `_update_lead`: up over
  `LEAD_IN` 0.06 s, held `LEAD_LINGER` 0.12 s past a thrust so a combo's gaps
  never hand back, down over `LEAD_OUT` 0.2 s). first_person_arms.gd multiplies
  the clip's arm weight by `1 - lead`, so the arm is IK'd onto the spear and the
  body's clip plays under it.
- **The thrusts** (`_thrust_pose`, head space): `READY_AT` low on the right,
  levelled at the crosshair; a jab snaps out (cubic ease-out) to `JAB_AT` by
  `STAB_OUT`, holds `JAB_HOLD` 0.035, draws back by `STAB_BACK`; jab_b on a
  slightly different line. The lunge draws back by the shoulder
  (`LUNGE_BACK_AT`), creeps a beat, then drives to `LUNGE_AT`, fastest as it
  bites at `LUNGE_OUT`, holds while the step carries, and comes home.
- **The haft slides through the fist** (first_person_arms.gd `_pose_right`):
  out of the arm's reach, only the part of the shortfall across the haft is
  taken back, so the spear runs on through the hand rather than the thrust
  coming back with the wrist. That is what lets a jab reach 0.78 m out.
- The lunge is `right_only` now: its capture's left fist floated in the middle
  of the view through the drive.
- Hits are as they were (a box down the aim): jab 10, lunge 16, sweep 22.

### Two weapon slots, no axe (inventory.gd, radial_menu.gd, ...)

- `Inventory.WEAPONS` 4 -> 2: slots 0-1 the weapon wheel (left, right), 2-5
  the quick wheel, 6-35 the bag (`SIZE` 36). An old 38-slot save goes through
  `migrate` (everything re-added where it now belongs), the sword in hand.
- **The wheel** (radial_menu.gd): the weapon wheel offers `WEAPON_DIRS` left
  and right. **A tap of C (or R3)** with no aiming swaps to the other weapon.
  Losing focus with the key down does not swap.
- Inventory screen: the weapons' diamond shows two slots, left and right; the
  slot keys read 1-2 for weapons and 1-4 for quick items (item_slot.gd).
- **The axe**: not in a new game's kit (`_reset_inventory`), taken out of any
  save that carries one (`restore_state`; the old `axe_given` hand-out gone),
  off the workbench (`UPGRADABLE`) and the sandbox's level spinners, and its
  four intro lessons cut (to_axe, chop, axe_throw, berserk; "Back to the sword"
  now waits for the spear to be home). axe.gd and its code paths are left in
  place, unreachable, for when it comes back.
- The robot rat rides the weapon wheel; with the sword and spear in both slots
  it goes to the bag, and has to be swapped onto the wheel in the inventory.

### A bug found on the way (sword_wave.gd)

`SwordWave.launch` hits whatever is already inside the wave in `_start`, and
player.gd set the wave's damage after `launch`, so a foe within reach of the
blade took the default 80 instead of 130. `launch` now takes the damage
(`hit`) and sets it before `_start`.

### Measured

Hits on a frozen enforcer, the player pinned (throwaway harness):

| | slash | chop | heavy | wave | jabs | lunge | sweep |
|---|---|---|---|---|---|---|---|
| 1.4 m | 20 | 20 | 45 | 80 (the bug above) | 10 | 26 (jab + lunge) | 22 |
| 1.9 m | 20 | 20 | 45 | 130 | 10 | 26 | 22 |
| 2.4 m | 20 | 20 | 45 | 0 before `aim_forward`, then 130 | 10 | 26 | 22 |

The camera against the knight's head bone through the sweep (heading of its
+Z): within 5-17 degrees of the stance's own offset through the spin, after
the stance-reference fix (25-50 before it).

Two weapon slots: a new game holds sword, spear, a potion on the quick wheel,
no axe; a tap of C swaps 0 -> 1 -> 0; an old save with the axe and a robot rat
on the wheel comes back with sword and spear in hand's slots, the potion on the
quick wheel, the robot rat in the bag, no axe.

Clean windowed runs with `--quit-after 1500`, with and without the intro: no
errors. No benchmark: the change adds two ride samples a frame and a bake of
a few milliseconds at load; nothing drawn changed.

### Traps

- **A move's own first frame is not where the body starts.** The body blends in
  from the stance; measure anything the camera follows from the stance.
- **Twist about the vertical is not the head's heading** when it pitches hard
  (the sweep looks 69 degrees down): they part by 20 degrees mid-spin. The
  twist is what the body's counter-turn needs, so both use it.
- **Anything that aims from the camera mid-attack** now aims along a turned
  view: use `aim_forward()`.
- `--check-only` on a script that names an autoload fails to compile in
  `--script` mode; the scripts were exercised at runtime instead.
