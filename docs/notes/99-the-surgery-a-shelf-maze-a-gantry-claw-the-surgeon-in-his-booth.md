## 99. The surgery redone: a maze of shelves, a gantry claw, the surgeon in his booth (2026-10-22)

The user: "base of claw should move on the X and Y axis across the whole room.
Make more realistic animations for the claw, and make it pause to drop much
later, so its hard to get away from the claw. The claw should have visual
effects when it hits the floor. The surgery room needs to be redone using
higgsfield. The walls should have no skulls, and the brick texture should be the
same as the dungeon walls. The room's architexture looks great though. Have it
make a bunch of different bookshelves, to make a maze of bookshelves in the
room, with the middle where the surgery table is being an open point." Then a
layout (intake: a freight lift up from the crypts, numbered trays among the
shelves of anatomical records; assembly: a rail carries each tray into the open
centre where the claw fits the gold prostheses; dispatch: finished soldiers
through a heavy gate into holding pens, failures down a shaft under the table),
and: "a new 'enemy' that is the surgeon. He should be in an elevated control
room. The task to get to the control room, kick the door down, kill the
surgeon, and power off the system. When you interact with the door of the
control room, the door breaking, killing of the surgeon, and turning off the
power should all be a cutscene."

Asked and answered: the old puzzle (levers, clamp, cut cable) goes -- the
control room is the only way to stop it; the surgeon operates the claw from his
console and does not fight; the way up is a freight lift.

Note 98's rule stands: every model is a Higgsfield one. Engine nodes (lights,
particles, decals, collision) are not assets.

### New Higgsfield pieces (models/surgery/, tools/build_surgery_kit.py)

gpt_image_2_5 pictures (high) -> Tripo H3.1 (9 credits each); the surgeon by
Meshy image-to-3D with rigging (38) plus two more clips by `meshy_rigging` (8
each); three effect pictures. About 300 credits, 352 -> 50.5. Two Tripo jobs
failed (shelf_trays, shelf_drawers; refunded) and went through resubmitted.

- walls: `wallframe` (an open, skull-free stone frame, `fit` 5.0 x 0.5 x 8.6),
  `lintel2` (5 x 0.7 x 1.1) and `frieze2` (5 x 0.5 x 3.9) over the ways in;
- the crane: `girder` (long 4.4, the bridge and the runways), `endtruck`
  (the trolley, long 3.0);
- the maze: six shelves, each `fit` 2.9 x 0.42 x 3.3 -- `shelf_ledgers`,
  `shelf_drawers`, `shelf_trays` (numbered trays), `shelf_scrolls`,
  `shelf_specimens`, `shelf_ruined`;
- the line: `floorrail` (long 3.0), `traycart` (2.2), `portcullis`
  (2.9 x 0.6 x 3.6), `penbars` (2.97 x 0.35 x 2.4), `shaftgrate` (long 3.6,
  top origin);
- the booth and lift: `platform` (5.94 x 2.97 x 0.45, top origin, metallic
  0.15 -- at 0.5 it rendered as a smeared glossy sheet), `boothwindow` (5.94 x
  0.25 x 2.5), `boothdoorwall` (2.97 x 0.25 x 2.5), `door` (1.05 x 0.12 x 2.1),
  `console` (long 2.2), `handrail` (3.0), `liftcage` (`fit` 2.6 x 2.6 x 2.4,
  yaw 0 -- open side on the model's +X);
- `textures/surgery_fx_dust.png` (512), `surgery_fx_crack.png` (1024),
  `surgery_fx_chip.png` (256).

`GLASS` / `split_glass()` in the kit script: for `boothwindow`, the faces
inside the window rectangle (normalised x -0.43..0.43, z 0.33..0.93) facing
front or back are split into an object "Glass" (2207 faces), which
surgery_control.gd `_glaze`s see-through. **New kit textures import with
compress/mode=0**: patch them to 2 and reimport, as before. Godot then rewrites
the older surgery imports too (`detect_3d/compress_to=0`, normal maps flagged,
roughness from the normal) -- commit those, or every machine churns them.

**These Tripo returns came at 1.3-1.4M triangles, ~46 MB each** (note 98's
were 1-7k): 23 of them would have added 1 GB to the repo for pieces built to
12000 at most. `--reduce` (`reduce_raw`, `RAW_MAX` 100000) welds and decimates
each raw in place, maps untouched (image names kept, so the built textures keep
their file names): 1060 MB -> 173 MB. The kit was rebuilt from the reduced raws
and looks the same in game. Run it on any new raw before committing.

The surgeon (`tools/build_surgeon.py`): three Meshy GLBs of the same model and
rig -- `raw_surgeon.glb` ("Checkout_Gesture", his work at the console),
`raw_surgeon_alert.glb` ("Alert_Quick_Turn_Right"), `raw_surgeon_die.glb`
("Fall_Dead_from_Abdominal_Injury"). Their actions go onto the first armature
as NLA tracks "work", "alert", "die" and export with
`export_animation_mode='NLA_TRACKS'`; Meshy's stray Icosphere is dropped,
maps 1024, metallic 0.1. 2.4 MB.

### The hall (`scripts/surgery.gd`)

- **Brick like the dungeon's.** The brick kit's "wall" texture is an atlas, not
  tileable, so the hall is not retextured: `_raise_walls` stacks the level's own
  brick wall pieces (`BrickLevel.standalone("wall")`) in courses at y 3.5 and
  7.0 up to the ceiling, and `_build_walls` puts an open `wallframe` per cell in
  front (`BAY_DEPTH` 0.5) so the brick shows through. No jambs, no corbels, no
  skulls; `lintel2` + `frieze2` over the ways in.
- `_build_roof` (planks and a beam MultiMesh), `_build_runways` (girder
  MultiMesh along x = +-(inner - `RUNWAY_IN` 0.5), tops at 6.75, braces).
- **The plan frame.** Everything of the layout lives under `_plan`, a Node3D
  turned k x 90 degrees so the lift corner is plan (-X, -Z); `_choose_plan`
  picks the k whose layout clears the room's real ways in.
- **The maze** (`_carve_maze`, `_build_maze`): 9 x 9 cells of ~2.98 m.
  Kruskal's spanning tree plus 13 % extra openings (`LOOPS`) for loops, so the
  claw can't corner you in every dead end. Each wall is two shelves back to
  back (`SHELF_DEPTH` 0.42, `SHELF_H` 3.3, a random one of the six), one
  collision box per wall. Kinds: lift (0,0); intake (0,1), (0,2); the centre
  3..5 x 3..5 left open; the pens (8, 3..5). Forced open: the intake, (0,1)-(1,1)
  (nothing tall under the booth), the rail row 2 from i 0 to 4 then into (4,3),
  the centre, the aisle (5,4)-(6,4)-(7,4). Forced shut: (0,0)-(1,0).
  `cell_at(i, j)` is public.
- `_build_intake`, `_build_rail` (floorrail from the lift to the centre, a
  `traycart` running it on a loop, `_run_cart`), `_build_dispatch` (the pens
  behind penbars, the portcullis at (7,4)-(8,4), finished soldiers --
  skeletons with the gold prosthetics -- caskets, a red PenLight),
  `_build_centre` (the disposal shaft's grate under the table), `_furnish_dead_ends`
  (a desk, lectern, globe, books, a jar or a chest in dead ends), `_spawn_table`, the control
  room, `_light_hall`, `_limit_view`.
- Save `{"down", "at"}`; restore calls `control.set_finished()`, reset
  `control.reset()`.

### The claw on a gantry (`scripts/surgical_table.gd`)

The ring-and-rail arm is gone: an overhead travelling crane. The **bridge**
(a girder at `BRIDGE_Y` 7.2) runs along Z on the two runways; the **trolley**
(endtruck, top `TROLLEY_TOP` 6.95, scale 0.5) runs along X on the bridge; the
arm hangs from it at `ROOT_Y` 6.25 and telescopes (`_len`). The whole room is
in reach.

- `_drive`: per-axis arrive steering -- the trolley along X at 5 -> 7.4 m/s
  (by level), accel 9; the bridge along Z at 4 -> 6, accel 6 -- so it
  overshoots and settles like something heavy, rather than gliding.
- `_swing`: a damped spring pendulum (`SWING_RATE` 3.4, `SWING_DAMP` 0.32)
  driven by the base's acceleration (`SWING_GAIN` 0.075): the claw lags when
  it starts, swings past when it stops. `_swing_lock` stiffens it for the slam.
- `_hunt` hovers the wrist at `HOVER_Y` 5.0 over `_aim_point` (the player led
  by `LEAD` 0.25 s).
- **The slam, late.** WIND 0.35 s (rises 0.7) -> TRACK (0.5 s, down to 0.3 by
  level; still following) -> LOCK (0.16 -> 0.12 s, the parry cue) -> DROP 0.17 s
  eased in -> stuck (`REAR_STUCK` 1.3, `PARRY_STUCK` 3.0) -> `PULL_TIME` 0.5.
  Measured: locked 0.86 s into the slam, landed 1.19 s.
- **Impact** (`_impact_fx`): a crack `Decal` under it (`_crack` /
  `_drop_decal`; at most `DECAL_MAX` 6, each fades after `DECAL_LIFE` 9 s), a
  ring of dust (`_dust_burst`, the dust texture), stone chips (`_chips`),
  sparks, a flash OmniLight, camera shake; all scaled by `strength`.
  `_emit(parent, p, at, life)` starts and frees a one-shot CPUParticles3D.
- Kept: carry to the table and strap (CARRY/STRAP), struggling free,
  `power_off(cause)`, `set_dead_now`, `rest_point`, static `glow()`. Gone: the
  clamp, the cut, the cable hitbox and feed. `_intruder` takes players at
  y -1 .. 5.5 and ignores one in a cutscene.
- States unchanged: REAR 5, DEAD 9, CARRY 10, STRAP 11.

### The control room and the scene (`scripts/surgery_control.gd`)

`setup(surgery, table, inner, cell)`, built under `_plan`:

- **The booth** over cells (0,1)-(0,2): the platform floor at `BOOTH_FLOOR`
  3.6 on oak posts; the glazed window wall facing the hall (+X), a narrower one
  at the far end, the door wall toward the lift with the door at `DOOR_X` 0.6
  (`DOOR_W` 1.0); walls `BOOTH_H` 2.3; a plank roof at 5.9 (under the runway
  at 6.75); the console at x1 - 0.85 turned -PI/2, its lamps glowing
  (`Table.glow`); a warm lamp behind him, so he is a shape at the window from
  the hall.
- **The lift** at cell (0,0): four oak posts, an AnimatableBody3D cage
  (`liftcage` turned -PI/2 so its open side faces the booth door), chains;
  `LIFT_TIME` 4.5 s up or down. Prompts "Ride the lift" (in the cage) and "Call
  the lift" (by distance -- a Prompt has no mesh, so `looked_at` can't find it).
- **The surgeon** at x0 + 1.25, facing the console and the window, playing
  "work" on a loop. Clips are found by name (`_clip`).
- **"Kick in"** on the door runs `_storm(p)`, all of it a cutscene
  (`begin_cutscene` .. `end_cutscene`, letterboxed): square up -> the kick
  (wood_door.gd's leg) -> `_burst_door` (door_debris.gd shatter, crumble, dust)
  at 0.3 time scale while he plays "alert" -> walk in -> `stab_at` his chest
  (await `Signal(p, &"stab_landed")` / `stab_wrenched`) -> `_kill_surgeon`
  ("die") -> walk to the lever -> `_throw_lever` (sparks, `table.power_off
  (&"control")`, the console goes dark, the lamp flickers) -> look out at the
  claw dropping dead -> control back.
- `set_finished()` (a save with it done: door gone, surgeon dead, dark),
  `reset()`.

### Measured (headless harness, driving the real game)

Paths on the navmesh from both ways in to the middle and to the lift; awake
and hunting, the gantry 4.13 m in 1 s; slam locked 0.86 s, landed 1.19 s; one
crack decal; carried, strapped, struggled free; rode the lift to 3.6; door
burst, surgeon killed, machine off, control back, claw dead (state 9), saved
down. 0 failures.

### Traps

- Height stack: runway top 6.75, bridge 7.2, booth roof 5.9, cage 2.4 tall
  (3.6 + 2.4 = 6.0), beams' undersides 7.85, ceiling 8.6. Raise the booth or
  the cage and they hit the runway.
- A const named `Control` shadows the native class -- hence `ControlRoom`.
  morgue.gd already has `SKELETON`; a subclass can't redeclare it.
- Awaiting a signal through a variable typed `Node3D`: `await Signal(p,
  &"name")`, not `p.name`.
- Tripo faces +X: check every raw model from two sides before setting its yaw.
- Unused now, kept in the repo: the note 98 pieces this pass dropped (wallbay,
  jamb, corbel, lintel, frieze, the levers, clamp, cable, gears, flywheel, ...)
  and `shaders/surgery_cable.gdshader`.
