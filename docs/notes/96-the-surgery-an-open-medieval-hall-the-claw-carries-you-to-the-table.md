## 96. The surgery an open medieval hall; the claw carries you to the table (2026-10-21)

The user: "Remove the pillars, and make the room way more interesting and
medieval. The claw should follow you around and slam the ground trying to grab
you and put you on the table." Supersedes note 95's aisles, piers, pedestal-free
centre bay and the claw's thrust and rake; the kit, the glow and the table are
note 95's.

### No pillars: an open hall under a timber roof

The hall was morgue.gd's: brick cross vaults on every cell, resting on piers
at every inner vertex and pilasters along the walls. Taking the piers away
leaves the vaults floating, so the surgery's cells have no vault at all now.

- module_level.gd `_make_surgery_hall` records the surgery's whole block in
  `out.get_meta("open_roof")`; brick_level.gd `build` lays no vault and no lid
  (`cap`) over those cells (`roofed`). Walls, floors, skirts, doorway arches as
  before.
- surgery.gd no longer calls morgue.gd's `_build_piers` (no piers, no
  pilasters). `_raise_walls` carries the walls up in two more courses of the
  corridor's own brick wall piece (brick_level "wall", 3.5 m a course, faced as
  brick_level faces it: `Basis(UP, atan2(-d.x, -d.z))`) at y 3.5 and 7.0, on
  the same 13.9 m face, one MultiMesh; over each way in the course rests on an
  oak lintel. The walls' collision still stops at the old crown (5.7 m):
  nothing reaches higher.
- `_build_roof`: a plank ceiling at `CEIL` 8.6 m over the whole hall, six oak
  beams across it (`BEAM_Z`, 0.55 x 0.75), each end on a stone corbel, braced
  up from the wall, joists between, purlins across. It casts the moon's shadow.
- Torches on the wall face every 6 m where the pilasters stood, none within a
  doorway's half cell (`_find_doorways`, `_door_distance`). The levers stand on
  squat oak stands (`POST_HEIGHT` 2.2) where their piers were -- the first try
  ran the posts up to the beams and they read as pillars again.
- Lighting: the first pass had the roof and upper walls pitch black (nothing
  lit above ~5 m). The chandeliers now hang on chains from the beams (tops at
  6.2) with a gentler falloff (energy 3.0, range 12, attenuation 0.8), a dim
  warm `RoofFill` (0.9, range 13) hangs under the roof by the lamp, and the
  oak is lighter (albedo 0.62 / 0.5 / 0.4).

### More medieval (Higgsfield, models/surgery/)

Nine more pictures after the reference (gpt_image_2_5; the brazier hit the
rate limit and went through on resubmission) and Tripo H3.1 models, fitted by
tools/build_surgery_kit.py: an iron maiden (2.4 m), a torture rack (3.0 m), a
gibbet cage with its skeleton (2.7 m, hung from its top), a brazier (1.6 m), a
pillory (2.2 m), a wall tool rack of saws, cleavers and hooks (2.2 m), barrels
and sacks (2.0 m), a floor candelabra (2.1 m). The hearth was generated too
and **thrown away: Tripo filled its firebox in solid** -- a flat stone wall
where the fire should be. The hearth is built instead (`_build_hearth`): stone
jambs with capitals, a mantel, a stepped chimney breast up the wall, a sooted
firebox, an iron grate, logs and embers, `_flames` (billboard licks on a
CPUParticles3D, 26, additive, a radial teardrop texture made once), sparks
(with effects on), and a flickering light (`_add_fire`, `_work_fires`). The
tool rack and the pillory came out sideways in the previews and were turned
(-90 and 90 degrees).

Placed: wall slots now cycle study / apothecary / maiden / specimens / tools
(`_furnish`); the hearth takes its own slot; `_furnish_floor` stands two
braziers (with flames and light) and two candelabras (light) round the rail,
the rack and the pillory out in the hall, barrels by the walls, and hangs four
gibbet cages from the beams -- anything within 4 m of a way in is skipped.

### The claw: follow, slam, grab, carry, strap down (`surgical_table.gd`)

No piers, so no aisles: the arm runs from the ring's hub (`ROOT` y 6.75) out
under the roof (`BEND_Y` 6.3, `BEND_SHARE` 0.45 of the way) and down into the
wrist -- a crane's reach across the whole hall (`REACH` 12.6 from the middle).
The ring hangs from the middle beams (`RING_TOP` 7.5).

- HUNT: it FOLLOWS the nearest player, the wrist `HOVER_Y` 4.1 over them and
  `HOVER_BACK` 1.2 back toward the table, at `SPEED` 4.2-7.0 m/s by anger.
- Over them (within `SLAM_OVER` 2.0) and off cooldown (`REAR_COOLDOWN`
  3.4-2.0 s): the SLAM (State.REAR). Up over them tracking (`REAR_RISE` 0.55),
  a hold with the spot fixed (`REAR_HOLD` 0.6-0.4 s; the parry cue fires) --
  step aside then -- and down (`REAR_SLAM` 0.13).
- Where it lands (`_impact`): the clamp first (`clamp_try_catch_at`: open and
  within `CATCH` 1.8 m of its mouth -> CLAMPED). A player within `GRAB_RADIUS`
  1.3 takes 12 and is GRABBED -- unless they parry (the claw bites into the
  floor and is stuck `PARRY_STUCK` 3.2 s) or block (knocked down instead).
  Everyone within 2.6 m is knocked down. Missed: stuck `REAR_STUCK` 1.8 s, the
  wrist's cable exposed, then torn free.
- CARRY: the player is held (player.gd `restrain`), lifted to `CARRY_Y` 4.4 and
  carried at 5.5 m/s to over the table, dangling (their view swinging,
  `restrain_view`). `CARRY_BREAK` 8 struggles and they drop free.
- STRAP: laid on the slab, the cuffs shut, the view put down on its back
  looking up at the claw (`restrain_view` (1.25, 72, sway)), which works at them
  -- `OPERATE_DAMAGE` 6-10 every 0.9 s, sparks -- until `STRAP_BREAK` 12-20
  struggles burst the cuffs (thrown off the side, `THROW` 6.5), a partner cuts
  the ARMS (the claw lets go), the core is cut (it lets go and stalls), or they
  die. A "Struggle! / Mash attack / jump to break free" banner (hud.gd
  `announce`) when seized: a prompt's text is never shown, only the crosshair
  brackets.
- Sagging (hoist cut or jammed): dragged along the floor after them, lashing
  (8, every 1.4 s within 1.6 m), the cable exposed.
- After letting go it holds off `RELEASE_REST` 2.2 s.

**player.gd** gains a HELD mode: `restrain(by)` (a hurting cutscene: no input,
no movement, blows land), `release(push)`, `is_restrained()`, `struggles`
(attack, jump, interact or block pressed while held; a small shake), and
`restrain_view` (added to the view like `_knock_view`). While held the mouse and
the pad still look about; `_physics_process` returns early (the holder places
them every frame); `_die` clears it.

### Measured

Every behaviour run for real in a throwaway harness (player held at a spot,
health topped up): grab (slammed, caught, carried, strapped, 18 damage in 2.5 s
of operating, struggled free, back to HUNT), carry (struggled free mid-air),
clamp (arms cut, standing 0.6 m before the open clamp, stepping 2.8 m aside
during the hold: caught, three cuts, depowered), slam (stepping aside: stuck and
exposed, three cuts, depowered), jam, relay, save -- all pass. Pictures from the
player's own eyes while carried and strapped.

Benchmark, RTX 3060, 3440x1440, editor closed, two runs: surgery 45.1 / 46.1
fps (22.16 / 21.68 ms avg), 1% low 29.3 / 33.7, p99 34.11 / 29.67 ms, ~2,170
draws -- against note 95's 45.3 / 44.7 fps, 1% low 38.0 / 36.6, p99 26.29 /
27.30. The average is the same; the tail is noisier (the bench player now wakes
a claw that hunts and grabs them; other stations' p99 swing as much between
runs: boss room centre 32.82 / 28.73). Overall 49.6 / 51.9 fps against 50.2 /
48.9. Video memory 1233.7 -> 1254.3 MB (+20.6 MB, the new pieces' maps).

### Traps

- Removing piers means removing VAULTS: the brick level hangs every cell's
  vault on its corners. Mark the cells (`open_roof`), do not delete pieces
  after the build.
- The upper courses use `BrickLevel.standalone("wall")`, which drops the
  corridor walls' vertex colours: same stone, not the same jitter.
- "Not expect to not find the most reachable polygons" navigation errors in a
  clean run come from the sewer lizard's and decrepit's wandering (their
  backtraces), not this hall; they were seen in note 95's runs too.
