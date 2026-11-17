## 190. The timing-combat template replaces the combat (2026-11-16)

The user: "C:\DEV\godot\timing-combat. look at this project's handoff doc.
completely replace our combat system with this one". That project (its
HANDOFF.md) is a first-person melee template built on timing and trading
blows: Weapon scenes that own their poses and swings, a chain window, swept
hits, a guard whose parry is a timed press, lock-on and knockback.

Asked:
- **How far:** "Player + hit rules". Every player attack and the guard
  become the template's. Every enemy takes the player's blows and has its
  attacks parried by the new rules, and keeps its own AI and animations.
- **Which specials survive:** the dash, the sword's heavy swipe (Q) and wave
  slash (F), and the spear's stab and lunge. The axe's throw and berserk are
  dropped, and so are the spear's sweep and throw.

Backed up first as branch `backup/before-timing-combat` and tag
`v-before-timing-combat` (a18ab26).

Supersedes:
- the sword's clip strokes and their chaining (notes 164, 167, 174, 175);
- the guard's parry window and its cues as a tap (note 62 and 2026-10-17's
  cues);
- the spear's attacks (notes 167, 172) and the axe's (notes 84-91).

### The pieces (scripts/combat/, ported from the template)

- **`weapon.gd` (Weapon, @tool):** the swing state machine. WINDUP -> ACTIVE ->
  RECOVERY, each swing's length is `1 / hits_per_second` split by its shares,
  and only ACTIVE hits.
  - **The chain window:** measured in swings (0 = start, 1 = end). A press
    inside it during the swing is queued and starts the next swing the moment
    this one ends. A press after the end, with the window still open, starts it
    at once. A press before the window is ignored, and once the window closes
    the combo starts over.
  - **Hits:** the Hitbox's box is swept along the strike path, 24 samples per
    strike, so hits don't depend on frame rate. Each target is hit once a
    swing.
  - **Feel:** each swing carries its own camera motion (Swing `camera_windup` /
    `camera_strike`) and its lunge (`lunge_speed`).
  - **This game's additions:**
    - `combo_length`: only the first N swings chain; the rest are specials,
      started by `start_attack_at` and never chained.
    - `time_scale`: player.gd `attack_time_scale`, 1.25, multiplies every swing.
    - `wielder`: the player's body, left out of the sweep.
    - `sight_from` / `sight_mask`: the camera, and stone (2). A blow never lands
      through a wall; the blade itself passes through walls as before.
    - `hit_handler`: for a target with no `take_hit` (every enemy here).
    - `damage_scale`: the workbench's level.
    - `show_hitboxes`: the sandbox's "Show hitboxes".
- **`swing.gd` (Swing):** one attack. The template's fields, plus:
  - `length_multiplier` (a special is one long swing);
  - `move_multiplier` (the walk through it);
  - `hits` (false for the wave slash: the wave does the damage);
  - `stun_time` / `stagger_chance` (for this game's
    `apply_knockback(impulse, stun)`).
- **`guard.gd` (Guard):** the template GuardArm's rules without its arm. The
  knight's left arm (first_person_arms.gd) still shows the guard, as before.
  See "The guard" below.
- **`knockback.gd` (Knockback):** the player's slide off a blow. Slide distance
  is about knockback × taken / recovery (recovery 8). `from_direction` covers
  blows that aren't from a Weapon.
- **`lock_on.gd` (LockOn) and `lock_on_reticle.gd`:** see "Lock-on" below.

### The weapon scenes (scenes/weapons/)

Each weapon scene has Poses (Marker3Ds in head space, -Z ahead, the camera
0.11 m in front of the head), a Grip, the Model (an editor preview, freed at
runtime), the Hitbox, and the swings. Edit them in the editor: *Preview Pose*
and the PreviewCamera work as in the template. They were generated once by a
throwaway script, and the scenes are now the source.

- **sword.tscn:**
  - **Swings:** Forehand (Right -> Left) and Backhand, the combo
    (`combo_length` 2); then Heavy (HeavyBack -> HeavyMid -> HeavyEnd) and Wave
    (Overhead -> WaveMid -> LowLeft).
  - **Timing:** 2 hits a second × 1.25, so a cut is 0.625 s. A cut lasted 0.625
    s before too (note 174's 0.50 pose s × 1.25).
  - **Damage:** a cut 20. The heavy swipe deals ×2.25 (45), with knockback
    ×1.6, a 0.6 m lunge, stagger always and stun 0.45; it lasts 2.4 cycles
    (1.5 s), held up for half its wind-up.
  - **Wave:** 3.2 cycles (2.0 s), `hits` false. Its wave is thrown as its
    strike begins (`_on_strike` -> `_fire_wave`), on the 20 s clock.
  - **Hit box:** from the guard, 1.75 m long (the old reach was 2.1 m from the
    hand), 0.4 m across, 0.3 m thick. Knockback 5.5.
  - **Rest:** where the knight's stance held the sword, measured.
  - Note 167's Higgsfield clips no longer play on any attack. The arm is put on
    the Weapon's grip by IK (below).
- **spear.tscn:**
  - **Swings:** JabA, JabB, Lunge. 2.85 hits a second × 1.25.
  - **Damage:** 10 a jab. The Lunge (1.6 cycles) is drawn back by
    LungeBack and driven through, ×1.6 (16), with a 1.1 m lunge and stagger 0.4.
  - The poses are spear.gd's old ones.
  - The hit box runs from 0.9 m up the haft for 1.35 m.
- **axe.tscn:**
  - **Swings:** one Chop (Raised -> Level -> Down, held at the top), 60
    damage, at 1.33 hits a second × 1.25.
  - The poses are axe.gd's `_swing` arc, turned so the haft runs down -Z.
  - No slot holds the axe (note 172), so in play nothing reaches it.

### The player (player.gd `_make_combat`, `_update_weapons`)

- **Where the weapons live:** the three Weapons are children of the Head at
  its origin, `weapons[id]`, and run at `process_priority` -10. Only the one in
  hand ticks (`_set_weapon_active`).
- **What the eye sees:**
  - The sword's pivot is put on the sword Weapon's grip every frame
    (`_pose_held_sword`, through `_grip_on_pivot`), unless a scene poses it
    (`_pose_kind`: the haft strike, the cage stab, the unbound slam).
  - spear.gd and axe.gd put their models on their Weapons' grips.
  - All three are drawn back by GUARD_DRAW as the guard goes up, as before.
- **The arm follows the weapon:** first_person_arms.gd now always leads with
  the weapon (`w` 0), so the right arm is IK'd onto the grip and the stance
  clip never carries the weapon. `body_motion()` is empty; the stance is
  still the body's.
- **The old clip player is stopped:** `anim` (idle/run/jump posed the pivot)
  no longer plays; `_update_locomotion` is a no-op.
- **The keys:**
  - **LMB:** `_weapon_attack` -> `request_attack`. Nothing swings with the
    guard up, and a click during a dash's burst swings as the dash ends.
  - **Q / F (sword):** `_start_special(&"Heavy" / &"Wave")`. A special starts
    only from idle. Pressed during a swing, it is held and started as the
    swing ends (`SPECIAL_BUFFER` 0.35 s past it).
  - **Middle click / L3:** lock on (a new `lock_on` action and keybind row).
- **Switching** waits for the swing to end (`_pending_slot`), as the
  template's does.
- **The camera:** each swing's camera motion × `weapon_motion_strength` 0.8,
  plus the kicks (hit 3/1.5/3°, block 1.5/0/1°, parry -1/0/-2°), go straight
  onto the head (`_weapon_view`). `aim_forward` takes the weapon's yaw out.
  The FOV punch (`_swing_kick`) comes with each strike, as before.
- **Movement:**
  - The walk is multiplied by the weapon's `move_multiplier` and by the
    guard's 0.6; the axe's `CARRY_SPEED` stays.
  - The knockback slide and the Weapon's `lunge_speed` (along `aim_forward`)
    are added for the move and taken off after (`_physics_process`), so the
    walk never feels them.
- **The player's blows on enemies:** `_hit_target` (the Weapon's
  `hit_handler`):
  - `take_damage(amount, away)`;
  - `knock` at the swing's `stagger_chance`, along the blade's way at the
    weapon's knockback, so the enemies keep their poise otherwise;
  - `strike` for a weak point;
  - `swat` passed over, as before.
- **Removed:**
  - the sword's clip strokes, the heavy and wave efforts (`_wave_effort`,
    `_heavy_effort`), the stab effort and strain, `_resolve_hits`;
  - the axe's throw, berserk and the HUD's berserk glow;
  - the spear's sweep, throw, tether and flight;
  - the exports for all of those (`attack_damage`, `heavy_*`, `parry_window`,
    `parry_reflect`, `block_arc`...).
  - The spear keeps `_blast_visual`, which rat_control.gd borrows for the rat
    bomb.

### The guard (guard.gd, player.gd `take_damage`)

- **An attack winds up while its cue is open.** Its cue opens when the enemy
  calls `parry_cue(self, listen)`, and stays open until its blow or `listen`
  seconds at most. A Weapon in the `weapons` group that is in WINDUP counts the
  same.
  - New: enemy.gd `_enter_windup` cues every player within 12 m from the start
    of the wind-up, for the wind-up and the strike plus 0.15 s. Every skeleton
    kind and the proels use it.
  - decrepit, enforcer, scout, the builder, the surgeon, the table, the roots
    and the sentinel cue as before.
- **Pressing the guard** cuts off the swing in progress, and marks every
  attack winding up at that moment.
- **When a blow lands:**
  - **PARRIED:** the guard is still up and this attack's cue was marked. No
    damage, no shove (`parry_knockback_multiplier` 0). The attacker reels or is
    thrown back (`parry_push` 14, `parry_stun` 0.9), with the purple flash and
    the hit-stop.
  - **BLOCKED:** the guard is up any other way. 30% gets through
    (`block_damage_multiplier`; an attacker's `block_damage_share` still wins),
    and the shove ×0.5.
  - **HIT:** the guard is down. The swing is cut off, the shove is full
    (`blow_knockback` 3 m/s, or the attacker's own), plus the hit kick and
    note 143's flinch.
- **Changed from before:**
  - A guard held up before the wind-up never parries; the press is what is
    timed.
  - The press must still be held when the blow lands. Before, a tap inside the
    window counted.
  - The guard ignores direction (`block_arc` is gone).
  - A parry deals nothing back (`parry_reflect` 0.5 is gone).
  - A block lets 30% through (it was 10%).
  - Uncued blows (arrows, a crier's blast, the mimic) can only be blocked.
- `block_damage_taken` remains as a read-only property (the guard's 0.3), for
  sword_skeleton.gd and the inventory card.

### Lock-on (lock_on.gd)

- **Picking a target:** middle click or L3 locks the enemy nearest the middle
  of the view, within 20 m and 60°, with no stone in the way. Targets come from
  the enemy groups (`skeletons` covers every enemy.gd kind), plus
  `lock_on_targets`, which criers, mimics and the intro's sentinel now join.
- **Turning:** the body's yaw and `_look_pitch` smooth-damp onto it
  (0.22 s, 300°/s).
- **Switching:** a mouse flick (80 px) or the stick moves to the next target in
  view.
- **Letting go:** on a second press; on death, a scene, hiding or a ladder;
  beyond 25 m; or after 1 s out of sight.
- **The reticle** is a gold diamond on the player's own CanvasLayer.

### Elsewhere

- **intro_lessons.gd:**
  - The "Spear sweep" and "Throw the spear" lessons became one "Spear lunge"
    lesson (`current_move() == &"lunge"`).
  - A "Lock on" lesson comes after the sentinel wakes (in the block lesson).
  - The parry lesson now says to press as the glaive winds up and hold.
  - The heavy and wave lessons read `current_move()`.
- **inventory_screen.gd:** the sword, spear and axe cards read the Weapons
  (`player.swing_damage`) and list lock-on.
- **attack_icons:** the sword shows wave, heavy and slash; the spear stab; the
  axe axe_slash. Cooldowns come from the weapon's time left, or 0 once its
  chain window is open.

### Measured (throwaway harnesses, headless; all passed)

**Bare world:**
- A cut lasts 0.625 s and deals 20.
- Two chained presses hit twice, 0.614 s apart.
- A press 0.05 s into a swing is ignored.
- The heavy swipe deals 45 and staggers; the wave slash fires once and
  starts its 20 s clock, and a second waits.
- The guard cuts off a swing, and nothing swings while it is up.
- **Pressed in the wind-up and held:** parried, no damage, the attacker thrown
  back.
- **Guard already up before the wind-up:** blocked, 9 of 30 through.
- **Pressed after the wind-up closed:** blocked.
- **Unguarded:** a full hit, the swing cut off, and the player slid 0.35 m.
- **Lock-on:** takes the enemy in view and faces it within 0.0° after 1.2 s.
  A second press lets go.
- **The spear:** jab, jab, lunge; the lunge carried the player 0.98 m.
- **Switching:** a switch mid-swing waits, and is taken when the swing ends.

**The real level (default seed):**
- A scout's wind-ups opened cues; pressed in them, it was parried 2 of 2
  times, health 100 -> 100.
- Four cuts took a scout from 160 to 100 health, locked on.

**Elsewhere:**
- Every script in `scripts/` and `scripts/combat/` compiles.
- A `--quit-after 2400 -- --skip-title` run: no errors.
- **Seen (windowed, bare world):** the sword in the knight's gauntlet, the arm
  following through the forehand, backhand and heavy swipe; the wave's gold
  arc leaving as its strike begins; the spear's jabs and lunge.

Not measured: frame time. The sweep is about 24 shape queries per strike
while a swing is active; the old code ran one convex query per physics tick.

### Traps

- **The heavy swipe whiffed behind the player.** HeavyBack (yaw -105°) to
  HeavyEnd (+85°) is 190°, and the slerp took the short way round. HeavyMid
  makes it go through the front. Any swing whose poses are more than 180°
  apart needs a middle pose.
- **A harness can't compile `sword_wave.gd`** (it names `Graphics`), so
  headless harnesses print "Nonexistent function 'material'" from the blade
  glow. The game, and windowed runs, are fine.
- **`_action_held` reads the physical keys,** so a harness pressing the guard
  with `Input.action_press` has it dropped by `_check_block` the next tick. Use
  `player.guard.press()` directly.
- **Out of reach, the fist stops short** (first_person_arms.gd). The sword
  comes back with the hand and the spear slides through the fist, but the hit
  box is the Weapon's own pose, not where the arm left the model.
