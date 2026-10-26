## 104. The surgery: an entrance scene and bars, vat lids, real soldiers in the pens, the claw's three moves, the way up to the booth (2026-10-25)

The user (all in one request, building on notes 102-103):
- "Put the door back on the control room, and make the control room to where
  the player can push a vat over to it, jump on the vat, and start a cutscene
  where the player kicks the door down, throw the surgeon out of the control
  room down to the surgery room, and power off the system from the control
  room. The player has to start by jumping on the middle table, then to the
  vats. That should be another way to beat this room."
- "When the player walks up to the door of the surgery room, a cutscene should
  start where the player pushes a vat out of the way of the entrance (so the
  player knows vats are pushable), walks into the room as the claw is working
  on making a soldier, it dropping the soldier into the finished area,
  noticing the player, and raising bars at the entrances, blocking the player
  from escaping. Then, right as the claw starts targeting the player, give the
  player control back."
- "Give the vats removable lids."
- "Give the claw 3 moves": the grab; a piece out of a vat thrown at the player
  (30 and knocked down, blockable for less, parriable away off the player's
  front -- into the claw, it is knocked back and limp 4 s); a finished soldier
  grabbed and thrown over the wall, acting as a normal enemy.
- "The skeletons that are finished being built by the claw should not be
  props, they should be real enemies."

Nothing new from Higgsfield (7 credits left, a Tripo model is 9). Every new
thing uses an existing kit piece:
- the lids are the `hatch` plate;
- the thrown piece is the `prosthetic` arm;
- the bars are the pens' spiked `penbars`;
- the landing is the `platform`, with a `beam` post.

### The door

The booth's door had not gone anywhere: note 102 left it shut, and only the
crystal path's `leave()` swings it open. A probe found its mesh visible at the
door wall's gap. What was missing was a way to reach it, and that is what this
note adds.

### Lids (`surgery_vat.gd`)

`fit_lid()` (surgery.gd `_vat` calls it once `kind` is set) lays the `hatch`
plate, LID_SIZE 2.3 m across, over the rim. RIM is 1.89 for bones and 1.83 for
gold, measured off the models.

`set_lid(on, instant)` tweens it (LID_TIME 0.55 s) up off the rim, over, and
down onto its edge, leaning against the tub's side, or back. It is parented to
the vat, so it moves with it.

The player's prompt (`Interact.chooser` on the tub) reads "E Lift the lid" or
"E Put the lid on". It does not show from on top of the vat. A world reset
puts the lids back on (`go_home`), and the save keeps them ("lids").

### Standing on vats; the scripted shove

- `_on_top(n)`: a player standing on a vat never shoves it and never counts as
  being in its way.
- `scripted_push(to, time)`: the entrance scene's shove. It lurches and scrapes
  like a real one.

### Real soldiers in the pens (`surgery.gd`)

The prop soldiers (`_soldier`) are gone. `_build_dispatch` records their six
spots (`_pen_spots`, plan frame), and `stock_pens()` puts a real skeleton on
each:
- `prosthetic.make(enemy.tscn, hand)`, hands from PEN_HANDS (blade, hammer,
  drill, blade, shield, hammer);
- rooted and blind the way maze.gd's jail cells hold theirs (`wanders` false,
  `aggro_range` 0.5), still dozing when far away.

`stock_pens()` runs from `on_world_reset`, which maze.gd `_populate` calls on
the first build too. A death frees the pens and every thrown soldier and fills
the pens again.

The table's API (all on surgery.gd):
- `pen_soldier_for(at)`;
- `soldier_taken`;
- `turn_loose(e)`: maze.gd `_turn_loose`'s settings (aggro 70, no vision cone
  or line of sight, awake, seen);
- `loose_count`;
- `pen_drop_point`.

### The claw's moves (`surgical_table.gd`)

New states go after the old ones, so saved numbers stand: LIMP 12, FETCH 13,
FERRY 14, WORK 15.

**Choosing a move.** In HUNT, at its turn (`_next_rear`), it rolls once
(`_rolled_for`): SPECIAL_CHANCE 0.5. If the roll says yes, or the player is
more than 3 x SLAM_OVER out from under it, and `_next_special` has come
(SPECIAL_EVERY [9, 8, 7, 6.5, 6] s by level; 7 s after it wakes),
`_start_special` begins a FERRY or a FETCH. It picks a FERRY 45% of the time
when both are possible, and FERRY needs a pen soldier and fewer than LOOSE_MAX
2 thrown soldiers up. Otherwise it slams as before. After a move:
`_next_rear` = now + 0.6 x REAR_COOLDOWN, and `_next_special` is pushed on.

**FETCH (`_fetch`).** The vat (`_vat_to_fetch`) is a gold one 4-14 m from the
player and nearest the claw; a bones vat only if no gold one will do; never one
a player stands on. The steps:
1. Over it, fingertips 1.3 m above the rim.
2. If the lid is on: down onto it, fingers shut, the lid lifted off
   (`set_lid(false)`), up. It is left off.
3. Into the tub; a piece taken (`_take_piece`: the kit's arm at PIECE.SCALE in
   the fingers); sparks.
4. Drawn back 0.9 m away from the player, shaking 0.55 s.
5. Thrown (`_throw_piece`) at where the player will be 0.55 s on (chest
   height), with a swing kick.

**The piece (`scripts/surgery_piece.gd`).** It is the arm at SCALE 2.4,
glowing a little in its own gold, with oil drops trailing. It flies a
ballistic arc (GRAVITY 14) that lands on its aim in 0.075 s per metre, 0.55 to
1.15 s. The player and the claw are tested as capsules, as arrow.gd does; stone,
the vats and the floor stop it, and it clatters down and lies there 6 s.

What happens when it reaches a player depends on their guard:
- **Unguarded:** 30 damage (`take_damage(DAMAGE, dir, proxy)`) and
  `knock_down(dir, 7)`.
- **Blocked:** the Proxy's `block_damage_share` 0.3 lets 9 through. They stay
  on their feet, and it clangs off and drops.
- **Parried** (the ordinary rule: the guard up within `parry_window` of it
  landing; no cue): no damage, the player's purple flash at the piece, and it
  flies off at PARRY_SPEED 24, straight for 1.2 s, then falls. Its direction
  is where the player is looking (the camera's forward), so looking up at the
  claw sends it there. ASSIST draws it the rest of the way onto the claw if
  the claw is within 22 degrees of that line.
- **Into the claw** (the capsule from wrist to fingertips, radius 0.85):
  `struck_by_piece` lets go of anything held and knocks the claw limp along
  the piece's flight for LIMP_PIECE 4.0 s (`_knocked(now, limp_for, push)`;
  `_limp` now runs `_limp_for`). The parrier gets `hit_landed`.

**FERRY (`_ferry`).** The steps:
1. Over the soldier, fingertips at CLEAR_TIP 3 m, over the pen bars (2.4 m).
2. Down onto its shoulders; fingers shut; `_take_cargo`. The soldier's
   processing goes off and its collision is set aside.
3. Up to the carry height.
4. Across, to THROW_SHORT 3.5 m short of the player, over clear floor
   (`_clear_floor`: no vat within 2.75 m, turning round the player in 45-degree
   steps until clear; the first test had one land on a vat top, stranded).
5. Swung and let go (`_let_cargo_go(true)`): processing and collision back,
   velocity and `apply_knockback` toward the player (THROW_SOLDIER 6 m/s),
   and `turn_loose`. From then on it is an ordinary enemy.

`_hold_cargo` hangs the body CARGO_HANG 1.65 m under the fingers every tick.
`_drop_all` lets go of everything held when the claw is knocked limp, switched
off, or reset.

### The entrance scene (`surgery.gd _intro`)

A vat stands across each way in (`_block_entrances`: RADIUS + 0.6 inside,
added to `vats`, so the save keeps it). The scene starts the first time a
player is within INTRO_REACH 5 m of a way in from outside with the claw asleep
(`_check_intro`); `intro_done` is saved. Everyone is put in the cutscene and
the letterbox comes down. Then:
1. The claw is at WORK (`begin_work`, `hold` keeping it from waking): over the
   prisoner on the table, picking at it, sparks.
2. The player walks up to the vat and leans in. It is shoved (`scripted_push`,
   2.4 s) 1 m in and 2.4 m to whichever side has more room (`_room_to`), with
   the player behind it. Then they walk in past it, looking at the claw.
3. `ferry_prisoner(pen_drop_point())`: FERRY with the prisoner prop as cargo,
   set down (not thrown) just over the middle pen's bars. `ferried(at)`: the
   prop is hidden and a real soldier stands in its place (`_pen_soldier`).
4. `notice()`: HUNT, an eye flare and a jolt, the first slam 2.5 s off.
5. The view turns to the way in: `raise_bars()`.
6. Back to the claw; then the letterbox goes and control returns. The claw is
   already hunting.

Measured headless: 13.0 s, the bars at 11.4 s.

### The bars

`_build_bars`: the pens' spiked `penbars`, 3.2 m wide and BARS_H 3.7 m tall, in
each way in, sunk BARS_DOWN 3.9 m and
hidden, its collision off. `raise_bars` brings it up in BARS_TIME 0.9 s
(TRANS_BACK) with dust and a shake, and sets its collision.

When they rise or fall:
- **Up:** the claw woken without the scene (a world reset, the sandbox
  teleport; `woke` -> `_on_woke`) sets `_want_bars`, and the bars rise once no
  one stands within 1.3 m of a way in.
- **Down:** when the machine dies (`depowered`, either route), and at once on
  a world reset or on loading a save with it off.

### The way up to the booth (`surgery_control.gd`)

A vat is too tall to jump onto from the floor. The table (1.2 m) is not:
measured, a run and a jump lands a player on it (feet 1.20 m up). From the
table they can reach the vats, and the vats from one another. A vat shoved
into the corner by the booth is the step up.

**The landing** (`_build_landing`): the `platform` scaled to a cell (0.5 x)
over the hall's corner cell (0, 0), where the lift's cage stopped in note 99,
at BOOTH_FLOOR 3.6. It has collision and an oak `beam` post under its outer
corner.

**The trigger.** In `_process`, a player standing on a vat (`_vat_under`: 1.5
to 2.4 m above its foot, within its radius, on the floor) whose middle is
within CLIMB_NEAR 2.2 m of the landing's or the booth's footprint starts
`_storm`. Nothing happens if the machine is already off.

**The scene** (note 99's kick, from git d97e51a):
1. Hauled up over the landing's edge onto it.
2. A step back, squared to the door, the kick (wood_door.gd's leg). The door
   bursts in (door_debris.gd shatter, crumble, dust) in 0.3 slow motion, and
   he turns ("alert").
3. In beside him.
4. A heave (`scene_lean`). `_throw_surgeon`: over the console, through the
   hall window (`_break_window`: the pane hidden, a spray of glass), and down
   to the flags 2.4 m out (`_landing_spot`), his "die" clip playing, dust
   where he lands.
5. To the console: `_throw_lever`. The console dies and `table.power_off
   (&"control")`.
6. Out through the broken window, the claw falls.
7. Control back, the player standing in the booth.

Measured: 9.2 s; the surgeon at floor height; the table off; the bars down;
the player at 3.6.

**Saving and the crystal route.** The save adds "booth" (`set_thrown_now`:
door and pane gone, him lying in the hall, the console dark) and "intro".
`leave()` and `power_cut()` leave a thrown surgeon alone, so the crystal route
still works afterwards.

### Measured (throwaway harness, headless, driving the real game; deleted)

34/34 passed, and twice more after the last changes:
- Six real rooted pen skeletons. All 28 vats lidded, two of them across the
  ways in. A lid off (leaning at 1.10 m) and back on.
- The entrance scene starts from 3.6 m outside and ends in 13.0 s:
  - the vat shoved 2.6 m;
  - WORK, then FERRY;
  - seven in the pens;
  - the bars up and solid;
  - control back, the claw hunting, the player inside.
- FETCH, unguarded: the lid off, a piece thrown, exactly 30 damage, knocked
  down.
- FETCH, blocked: 9 damage, on their feet.
- FETCH, parried while looking 1.6 m to one side of the claw: no damage. The
  assist takes the piece into the claw, which is limp 4.25 s of game time
  (the 0.25 s knock plus 4).
- FERRY: lifted to 2.6 m, thrown loose (loose 1, processing back, aggro 70),
  landing on the floor 1.9 m from the player.
- Jumped onto the table: feet 1.20 m up.
- On a vat placed beside the landing: the booth scene runs (as above). Saved
  "booth", "intro" and every lid.

Re-broken, the harness fails as it should: no `fit_lid` fails the lid checks,
and ASSIST 0 fails the parry-into-the-claw checks. The windowed screenshots
show the lids (on, and off leaning), the vat in the way in, the booth's
landing, the claw over an open gold vat, the bars, the piece in the air, a
soldier in the claw, and the booth after.

Not measured: frame time. The pens' seven skeletons are ordinary enemies
(they doze when far, `dormant_range`); no benchmark was run, because another
game was holding the GPU.

### Traps

- **A harness that names nodes to find them misses Godot's renames:** a
  second "SurgeryPiece" under the same parent became "@Node3D@18006". Find by
  script.
- **A block raised as a throw leaves the claw is a parry if the flight is
  under `parry_window` (0.5 s).** Raise it during the aim to test a block.
- **A harness's guard needs the block action held** (note 103), the parry's
  too.
- A subclass of morgue.gd cannot have a `_bars` (morgue's letterbox) or a
  `WOOD_DOOR`; it already has `WoodDoor`.
- The kit's `portcullis` is a solid riveted plate: in a way in it read as a
  door, not bars (so the `penbars`). The level's cells are 6 m; the ways in
  are about 3.2 m.
