## 102. The surgery's vats, the hatch, the powering room and its crystal (2026-10-25)

The user: "Remove the bookshelves, the room should instead be filled with large
vats of pieces that the claw uses to make bionic soldiers. The player should be
able to push the vats around the room, but they should be heavy and
cumbersome. Redo the surgery room again. There should be a crystal powering the
whole room in a separate 'powering room' under the surgery room, only
accessible through a hatch that is under a specific movable vat. Remove the arm
that shoots the enforcer beam. When the player comes back up out of the
powering room after removing the crystal from the room, the surgeon should be
gone."

Asked and answered:
- The booth stays, but its kick-in cutscene goes. Pulling the crystal is the
  only way to stop the machine.
- Use the 49 credits left: two vats, the crystal and the hatch. The powering
  room is furnished with note 98's unused machine pieces.
- The vats stand in dense rows.
- No hint marks which vat stands over the hatch.

Note 98's rule stands: every model is a Higgsfield one.

### New Higgsfield pieces (tools/build_surgery_kit.py)

Four gpt_image_2_5 pictures (high, note 99's iron reference as
`image_references`) became four Tripo H3.1 models, now with `face_limit`. The
cost was 42 credits (49 down to 7).
- `vat_bones`: `long` 2.8 m, the valves included, so the tub is 2.29 across
  and 1.88 tall.
- `vat_gold`: `long` 2.5.
- `crystal`: 2.0 tall.
- `hatch`: `long` 1.35.

The raws came at 38-92 k triangles, so `--reduce` left them alone.

### The beam claw is gone

`scripts/surgery_beam_claw.gd` was deleted. In surgical_table.gd these went
with it:
- `beamer`, `BEAM_GIRDER_Z` and `BEAM_CLEAR`;
- the second girder on the bridge;
- the hi-Z limit in `_drive`;
- the beam wait before a slam.

player.gd's enforcer-beam slow (`_beam_speed_scale`) belongs to the enforcer
and stays.

The claw hovers lower now that the 3.9 m shelves are gone: `HOVER_Y` 5.6 -> 4.8
and `CARRY_Y` 5.9 -> 5.2. Its header now names the crystal as its power.
`power_off`'s default cause is `&"crystal"`.

### The vats (`scripts/surgery.gd` `_lay_vats`, `scripts/surgery_vat.gd`)

**The lattice.** It runs VAT_STEP 3 m apart, out to 12.05 m from the middle.
That is the dungeon's flagstone grid, so the hatch (cut where two flags meet,
below) lands on one of its points. Its offset is `_lattice_off`: one
coordinate a whole number of steps from the middle, the other half a step.
That gives 9 x 8 or 8 x 9 points.

**Kept clear** (`_kept_clear`):
- the middle, CLEAR_MIDDLE 3.1 either way;
- the intake under the booth;
- the pens;
- the rail (CLEAR_RAIL 1.2);
- each way in (CLEAR_DOOR 3.2).

**The rail.** It now runs along a row and down a column of the lattice
(`_rail_points(off)`), so it costs one row, not two. The plan's turn
(`_choose_plan`) also keeps the hatch off the rail.

**The carve.** The points are split as a maze's are: junctions (both indices
of one parity), the walls between them, and the pillars. Every junction is
open. A random spanning tree of walls is opened by Kruskal, using the room's
own generator, with the kept-clear walls joined first. VAT_LOOPS 15% of the
rest are opened too. `_join_up` then opens the shortest run of points to join
any pocket still cut off. The hatch is a wall between two junctions and is
never opened, so its vat can be shoved off either way. Every point left shut
gets a vat. With this seed that is 26 vats in rows, with aisles and
cross-gaps between.

The tubs are random bones or gold (45% gold) at a random turn. Up to VAT_LIGHTS
6 of the gold ones carry an amber `Oil` OmniLight, which is the hall's light
now that the dead-end candelabras are gone.

**Pushing** (surgery_vat.gd). Each vat is a floating CharacterBody3D with a
cylinder collision of RADIUS 1.15, lifted STAND_OFF 0.12 off the flags.
- **Who counts as pushing.** A player counts if their move_and_slide met it, or
  they are within RADIUS + TOUCH of it, and their stick points within
  SHOVE_DOT of it.
- **Breaking it loose.** Nothing moves for BREAKAWAY 0.55 s. Then it jolts loose
  (the model rocks back) and creeps in lurches: HEAVE 1.3 per second, the low
  ebb LURCH 35% of full speed. It accelerates at ACCEL 0.8 to PUSH_SPEED 0.8
  m/s.
- **Turning.** The direction follows the shove at only TURN 0.9 per second.
- **Stopping.** It brakes at BRAKE 5 once there has been no shove for GRACE_MS
  220.
- **Two pushers.** A second player shoving adds TEAM_BONUS 45% speed.
- **What stops it.** Walls, the table, other vats and the open hatch's curb
  stop it (mask `2 | 4 | STOP_LAYER`). A collision slides GRAZE 35% of what is
  left. A player in its way stops it (`_player_ahead`).
- **Dust and idling.** Dust kicks up at its foot while it scrapes. At rest with
  no one near, it does nothing.

The tray cart waits behind a vat shoved onto the rail.

Measured by holding "move_forward" into a vat: 0.000 m in the first 0.35 s,
1.35 m in 3.35 s, then 0.12 m more after letting go.

**Saving and resetting.** A save keeps every vat's place ("vats"). A world
reset with the machine still running sends them home. It leaves alone one
already shoved off an open hatch, and any vat whose home that one now stands
on.

### The hatch and the powering room (`scripts/surgery_power.gd`)

**The hole.** module_level `_pick_surgery_hatch` picks it from the room's own
cell. It sits where two notched flags meet (MANHOLE_ALONG from a cell's
middle), SURGERY_HATCH_RING 5.9-9.1 m out, and at least 6 m from any way in.
It is recorded as the out's meta "surgery_hatch". brick_level lays the notched
tiles there as for a manhole, and the cell's bed is surgery_power.gd's, with
the hole left in it. The floor's collision runs whole under the hole: climbing
is scripted.

**The lid.** The hatch lid is hinged on the hole's +X side. E (once no vat is
within COVERED) plays a short scene: crouch, a heave on the ring, it sticks,
comes up past upright and falls open (LID_OPEN 1.85 rad). Open, it is solid,
and a curb on STOP_LAYER keeps vats off the hole.

**The climb.** It is manhole.gd's (`begin_climb`, the fades). The ladder is on
the hole's -Z side, the climber steps off the far rim, and the lid is out of
the way.

**The room.** Its frame is the hole, with +Z squared toward the hall's middle.
- **Where.** Floor at FLOOR_Y -3.9 and ceiling at CEIL_Y -1.25. That is above
  the sewer's split at -4, so the map, the torches and the sewer's haze treat
  it as the dungeon. The dungeon's floor slab ends at -1.2.
- **Size.** 7 x 8 m.
- **Shell.** The brick kit's flags and wall piece, the surgery's planks for the
  ceiling, two beams, and a 1 m shaft lined with the brick piece.
- **The ladder.** Note 98's `track` rail stood on end, its rings into the room
  as rungs.
- **The machine.** Two `galvanic` coil stacks, `pistons`, a glowing `column`, a
  `leverbox`, and the `flywheel` and a `gear` on the far wall, turning (FLY_SPIN
  2.4 rad/s).
- **The crystal.** It stands on a `gear` laid flat between two `clampmount`s,
  with `cable` runs up into the ceiling. It has a blue OmniLight. Candles stand
  by the ladder, and warm light comes down the shaft.

**The light layer.** Everything down here draws on POWER_LAYER (1 << 16).
`_wall_off`, like maze.gd's for the sewer, strips that layer from every other
light at setup, when the lid opens and on each climb down. The floor is no
shadow caster, so the hall's torches and the vats' oil would otherwise light
the room through the flags. The room is drawn only while a camera is within
30 m.

**The pull** (`_pull`, a scene). The player sets, grips, and the clamps fight:
six shudders, arcs off the jaws, the light stuttering. The crystal tears free
into their hands (inventory `power_crystal`, a Relic, so it gets the shard
icon). `_take_crystal` then:
- puts the crystal light out;
- runs the flywheel down over 3.5 s;
- puts out the glows;
- calls `table.power_off(&"crystal")`, so the claw falls in the hall;
- calls `control.power_cut()`.

Dust falls from the ceiling and the view shakes.

**Climbing back out** with the crystal gone: while the screen is black, the
script calls `control.leave()`.

### The control room (`scripts/surgery_control.gd`)

The lift, the kick, the stab scene, the master lever and their prompts are
gone. What stays:
- the booth, the glazing (note 101) and the surgeon at his console, playing
  "work";
- `power_cut(now)`: the console goes dark, the lamp gutters, and he turns
  ("alert") and stops;
- `leave()`: he is hidden and disabled, and the booth's door is left swung
  open on its edge.

### Saving

`save_state` now records "vats", "hatch", "crystal" and "gone" beside "down"
and "at". A save from before this note that has "down" (switched off by the
old lever) restores with the crystal out and the surgeon gone. The sandbox has
a "Surgery: powering room" teleport (`powering_room_point`).

### Measured (headless harness, driving the real game)

All 32 checks passed:
- 26 vats, one exactly over the hole, which reads as covered;
- the claw woke, hunted, slammed, caught, carried and strapped down, and the
  player struggled free;
- the vat shove above, and a world reset put the shoved vat back;
- the hatch vat moved off, so the hatch is uncovered and the lid opens;
- climbed down to the room's floor (y -3.90);
- pulled the crystal: the machine died and the inventory went 0 -> 1;
- the surgeon was still there while the player was below;
- climbed up: the surgeon was gone and control came back;
- the claw lies dead (state 9);
- the save holds down, crystal, gone, hatch and every vat.

**Benchmark.** It ran on this PC (1920x1080 window, not the RTX 3060 3440x1440
of notes 100-101): surgery 95-98 fps, p99 ~14 ms. With the vats left out it
was 100.5. Physics was 6.8-7.0 ms either way.

### Traps

- **A body pushed by the player must not collide with the player.** Pressed
  against it, every move_and_collide reported the player and bled off speed: it
  crept 0.18 m in 3 s. The player's own slide stops meeting the vat once it
  gives, so contact has to be by distance, with a grace period.
- **The lattice's first point was off by a step.**
  `-floor((REACH - off) / STEP) * STEP + off` is wrong for a half-step offset.
  It is `off - floor((REACH + off) / STEP) * STEP`. The bug left one side of the
  hall empty.
- **The kit's `track` lies along its X with its rings under it (-Y).** Stood on
  end, X goes up and -Y goes out from the wall.
- `Table.glow` on the crystal at 1.6 washed it white; 0.55 keeps it blue.
- **Unused now, kept in the repo:**
  - the six `shelf_*` pieces;
  - `liftcage` and `handrail`;
  - note 98's leftovers (`wallbay`, `jamb`, `corbel`, `lintel`, `frieze`,
    `leverbox`'s handle, the `clampjaw`, ...);
  - `shaders/surgery_cable.gdshader`.
