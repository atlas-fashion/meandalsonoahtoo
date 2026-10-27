## 111. The surgeon's claw taken and kept; hold E to move a vat, no turning while pushing; the claw's motion made fluid (2026-10-26)

The user:
- "When the surgeon is killed, there should be a cutscene where the the player
  takes the claw from the surgeon and the player should keep it in their
  inventory."
- "The player should have to hold "e" to move vats around. The player shouldnt
  be able to turn when pushing a vat."
- "Make the claw's animations more fluid."

### The claw taken off him (`surgery_control.gd`, `surgeon_boss.gd`)

surgery.gd `_on_surgeon_defeated` (bars down, as before) now also calls
`control.claw_scene_when_ready()`. After 1.8 s, as soon as a player is up,
free and in the hall (`_claw_taker`: the nearest, not dead, not in a scene,
no menu open), `_take_his_claw(p)` plays. Everyone is in the cutscene,
letterboxed.

1. **The walk.** `_claw_stand` picks where they kneel: CLAW_STAND 1.15 m from
   the claw, out of 16 bearings, the one nearest them that is:
   - in the hall;
   - 0.75 m clear of every joint of his body (`boss._j`);
   - clear of every vat (radius + 0.5), the line to the claw too.

   If none is clear, the near side.
2. **Down on a knee**: `scene_lean` (0, -0.62, -0.2), zoom 8, looking at the claw.
3. **Five wrenches**:
   - his rig jolts (surgeon_boss.gd `jolt`: a decaying shake on top of `_animate`'s eased rig position, `_rig_at`);
   - sparks off the socket;
   - the view rocks.
4. **Torn free.** `unmount_claw()` hands the node over with its world transform
   in `transform` (no longer posed by him) and it is re-parented to the surgery.
   A burst of sparks and a shake for everyone.
5. **Lifted into view** (1.1 s): from where it lay to `_held_pose`, which is in
   camera space:
   - its hub at CLAW_HELD_AT (0.24, -0.36, -0.72);
   - scale CLAW_HELD_SCALE 0.32;
   - its fingers (its -Y) pointing along CLAW_HELD_POINT (-0.32, 0.42, -1), up and across toward the middle.

   The view comes level (`scene_look_at` a point 4 m ahead at 1.2 m).
6. **Tried once** (1.4 s): the fingers open and shut (`_flex_claw`, the same
   bone axes as the table's FINGER_AT), and its eye light flares.
7. **Put away** (0.45 s): lowered out of view and freed. Then:
   - `claw_kept = true`;
   - `add_item(&"surgeon_claw")`;
   - the toast "Surgeon's Claw";
   - control back.

The scene lasts about 7 s from his death to control back (headless, 6.6 s).

**The item** (inventory.gd): "surgeon_claw", "Surgeon's Claw", a Relic, stack
1, with its own icon (item_icon.gd `_claw`: an iron hub with a red eye, three
jointed fingers with brass knuckles).

**Saved.** surgery.gd `save_state` writes "claw_kept". `restore_boss(dead, at,
kept)`:
- kept: `drop_claw_now` takes it off his body (the inventory, restored after
  the world, has it);
- dead but not kept (saved between his death and the end of the scene): the
  scene plays 2.5 s after the load.

### Hold E for a vat (`surgery_vat.gd`, `player.gd`)

- **E pressed grabs, E let go lets go.** `_check_holders` drops any holder for
  whom `Coop.held(n, &"interact")` is false. The "E again" release in
  `_unhandled_input` is gone. The prompt reads "Hold E   Grab" (GRAB_TEXT) and
  is hidden while held.
- **No turning while pushing:**
  - player.gd: mouse look (`_unhandled_input`) and stick look (`_pad_look`) keep
    only the pitch while `latched_to` is set.
  - surgery_vat.gd: a holder's sideways keys count toward turning only when
    they are not heaving, and the vat turns only when no one is
    (`pushers == 0`). Left and right still turn it, slowly, standing (the only
    way to aim a push).

### The claw's motion (`surgical_table.gd`, the "Fluid motion" block)

Three things made it move in steps:

1. **The hoist** ran at a constant speed that started and stopped dead
   (`move_toward`). `_hoist_step` now drives it as `_drive` drives the gantry:
   - up to `_hoist`, accelerating at max(HOIST_ACCEL_MIN 6, `_hoist` x
     HOIST_KICK 4) -- top speed in a quarter second;
   - braking on the sqrt curve to arrive;
   - coming in faster than it can stop from (a slower drive taking over from a
     fast one), braking just hard enough (v^2 / 2d) to stop on the goal.

   A length set outright since the last tick (the drop, a catch, a save) zeroes
   its speed (`_len_was`). The parry's knock (`_hoist` 18) still throws it up
   in about KNOCK_TIME.
2. **It was drawn at the last tick**, so at more frames than ticks it stood
   still a frame and then jumped. `_snap_prev` keeps the tick's start;
   `_pose_arm` draws `_b`, `_o`, `_len` between the two by
   `Engine.get_physics_interpolation_fraction()`. Two things go with it as
   drawn so they do not lag the claw:
   - the cargo (`_hold_cargo(w, axis)`);
   - a carried player, whose own view glides with it.

   `_settle()` (sleep, a save) clears the history.
3. **The fingers** lurched toward each goal (an exponential lerp, full speed on
   frame one). `_finger_step` is a critically damped spring (closed-form smooth
   damp, stable at any frame time), stiffness `_open_rate` x FINGER_SPRING 1.6.

The shake before the drop eases in and out (`_shake_amt`, 6 a second), and so
does the wrist's turn speed when it starts or stops working on someone
(`_spin_rate`).

### Measured (throwaway harness, deleted)

Headless, `--fixed-fps 144`.

Vats 10/10:
- latched with E held, no prompt;
- pushed 1.16 m with forward + right + stick-right held: the vat turned 0.000
  and the view 0.000;
- standing, right turns it 0.30 rad;
- E let go: unlatched, hands free;
- off the vat the stick turns the view again;
- a grab without E held drops at once.

Re-broken (old turning and toggle back), 5 of those fail: the vat turned 0.75,
the view 2.60.

Smoothness (24 s of the claw hunting a player moved round the hall, 3,456
frames over 1,440 ticks):
- **Judder** (mean change in per-frame travel / mean travel): 0.017-0.042 as
  drawn now, against 2.000 for the tick's wrist, which is what the old code
  drew.
- **The hoist's largest speed change in one tick**, outside the slam: 0.70 m/s
  hunting. The STRAP state reaches 1.52, because its goal is a 9 rad/s
  sinusoid. Re-broken (`move_toward` back): 5.98.

The claw scene 12/12, three runs:
- dead 1.8-2.1 s before the scene starts;
- the claw held in view;
- `claw_kept`;
- off his back;
- one in the inventory;
- control back;
- saved;
- no second scene.

Restore 5/5 each way:
- not kept: the scene plays on load and gives it;
- kept: off his body, no scene.

Windowed:
- **Frame time:** 41 ms median through the scene, with the other thread's
  uncommitted fog work in the tree.
- **Screenshot:** the claw held up over his body, lit, fingers reaching across
  the view.

A clean `--quit-after 900` run (`--skip-title`) has no errors from this work.
The sewer lizard's nav-corridor errors are older.

### Traps

- **The first screenshots showed only vat iron.** In the test he had died
  standing against a vat (the spot `leave()` gives him), and kneeling "on the
  side they came from" put the player's face in the tub. Hence `_claw_stand`.
- **Screenshot runs lie about timing.** Saving a 3440x1440 PNG every 0.6 s
  stalled each frame for about a second. The scene runs on real-time tweens,
  but the camera eases per frame (clamped to 0.1 s), so the view barely moved.
  Take one shot at the moment wanted.
- **A harness entry file cannot preload a script that names an autoload.**
  Preloading surgical_table.gd for its enum compiled it in the harness's
  context (`Sandbox` unresolved), and the table broke with it. Use the literal.

### Not done

- What the claw does in the inventory: it is kept, as asked; it has no use yet.
- A sound for the wrench and the tear.
