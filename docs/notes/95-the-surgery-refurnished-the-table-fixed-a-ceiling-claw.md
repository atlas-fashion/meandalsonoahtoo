## 95. The surgery refurnished after a reference; the table fixed, a ceiling claw (2026-10-21)

The user gave a reference picture of the surgery: a dark vaulted hall round a
heavy riveted iron table on a base of gears and pistons, amber indicator lamps,
an iron rail let into the floor round it, a great ring in the vault with
chains and jointed robot arms, apothecary shelves of bottles and candles,
candle chandeliers, glowing green specimen jars, anatomy charts, banners, a
wooden gallery with stairs, iron-bound chests, and a worktable with a skull and
an open book. They asked for the whole room recreated with Higgsfield, then:
"Make the table stationary in the middle of the room. Make the robot claw
really long and coming from the ceiling." Then: "Skip the flag" (no banners).
**Not built:** the wooden gallery and its stairs (architecture, not a prop;
the hall's piers and vaults are morgue.gd's).

### The kit (Higgsfield), `models/surgery/`, `tools/build_surgery_kit.py`

`gpt_image_2_5` (high) with the reference uploaded as an `image_references`
media, one isolated object per picture on a plain grey background, then Tripo
H3.1 image-to-3D for each: table (30k faces, detailed texture), ring, claw
(detailed), one arm segment (straight, the same at both ends so it stacks),
shelf, worktable, chandelier, specimen jar, chest; plus the anatomy chart as a
flat picture (`textures/surgery_chart.png`). Three of the eleven pictures were
rejected with `429 rate_limit_reached` on the first batch and went through on
resubmission: eleven pictures and nine standard 3D models in all.

The build script fits them (tools/README.md "The surgery's kit"): table 3.0 m
long (1.48 wide, 1.2 high, maps 2048), ring 3.4 m across, claw 1.7 m, segment
1.0 m (stretched in the game), shelf 3.0 m tall, worktable 2.0 m, chandelier
1.7 m (hung from its top), jar 2.1 m, chest 1.15 m; decimated to 5-12k
triangles each (the table kept whole); metallic 0.45-0.5 for the iron, 0-0.1
for wood. The shelf came out back to front (empty shelves facing the room) at
yaw +90 -- -90 is right; the `--preview` render is how that was caught.

**They glow with their own pictures.** surgical_table.gd `glow(piece,
energy)` duplicates each material with `emission_texture = albedo_texture`,
`EMISSION_OP_MULTIPLY`: the candle flames, amber lamps, green bottles and the
specimen fluid are the bright texels and the iron and wood the dark ones, so the
flames burn and the iron stays dark. Shelf 0.35, jar 1.1, worktable 0.3,
chandelier 1.4; the machine's own pieces (table 0.55, ring 0.45, claw and
segments 0.3) go with its power, down to 30% asleep or dead (`_power_glow`).

### The room (`scripts/surgery.gd`)

- `_furnish(slots)`: the wall slots the mechanisms leave, shuffled per seed,
  each a "study" (worktable along the wall, the chart over it at 2.55 m, a
  chest), "apothecary" (two shelves) or "specimens" (two jars, a chest between,
  one green light 0.7 / 3.6 m). Each piece solid as a box on layers 1|2
  (`_place`).
- `_hang_chandeliers()`: one from the crown of each corner bay (top 5.0 m),
  a warm OmniLight 2.8 / 10.5 m under it, no shadow. `_hang_wall_torches`
  keeps only the wall pilasters' 16 torches: morgue.gd's 16 on the inner piers
  are gone (the chandeliers and the ring's lamp light the middle). The first
  pass, with the chandeliers at 1.5 / 8.5 m, left the hall black.
- `_build_rail()`: the iron rail flush in the floor round the table (radius
  2.05), brass inlay, eight amber lamps, four plates.
- The pedestal is gone; the lamp is now in the ring's hub (`LAMP_HEIGHT` 4.05,
  beside the arm).
- **The clamp is at the end of an aisle** (wall slot `k` 0, the line through
  the middle clear of piers: left, right, back, then front), with the arms'
  mechanism beside it and the hoist's (legs) on the opposite wall. A clamp
  between pilasters could not be reached by the claw past the piers.
- The table's own navmesh (`_bake_table_nav`) is gone: it does not walk.
- `save_state` saves where the CLAW fell (`rest_point`) and its aisle
  (`rest_yaw`). Old saves held the walking table's position; if that is within
  2.5 m of the middle, the claw is laid out 4.2 m down the aisle.

### The machine (`scripts/surgical_table.gd`, rewritten)

The table stands still in the centre bay (its collision a 1.48 x 1.2 x 3.0
box, layers 1|4; the prisoner and cuffs as before). Above it the ring
(`RING_TOP` 4.8, scale 0.9) turns with the arm; from its hub (`ROOT` y 4.15)
hangs the arm -- as many stretched segment models as its length needs
(`SEG_LEN` 1.05, up to 16, `SEG_THICK` 2.7 = 0.35 m) -- and the claw with the
red lens at its wrist and an `EyeLight` (red, 4.5 m) that travels with it.

**The hall decides the arm's path.** The centre bay is 6 m square with piers at
(+-3, +-3), the vault crown 5.1 m. The arm runs: hub -> over the bay's edge
(`GAP_NEAR` 1.7 m, 3.95 high) -> out past the piers' line into the aisle
(`GAP_FAR` 4.6 m, 3.55 high) -> down into the wrist along the claw's line, a
Catmull-Rom curve through those points (`_spline`), cut into equal segments.
A control point is only used if it brings the curve nearer the wrist, or the
folded arm doubles back on itself.

**Aisles.** `_aisle` is one of the four axes, chosen from the TARGET (the
player) with hysteresis (stays unless they are more than 45 + 9 degrees round,
so a player on a diagonal does not make it swing back and forth); `_theta`
eases to it at `TURN[level]`. To change aisle the claw is first drawn back
inside `BAY_SAFE` (2.3 m) -- the bay's inner square -- turns, then reaches out
again: it never sweeps through a pier. `_reachable(p)` rays from the aisle's
far point to `p` on sight's layer (2): a player round a pier cannot be struck
(the piers are cover), and the hover falls back to the aisle's line.

**Moves** (the `State` names kept, so surgery.gd and the saves did not change):
- GRAB: from anywhere within `GRAB_RANGE` 12.6 m of the middle and 2.2 m out.
  The wrist first drops to chest height + 0.7 (`_from`), then thrusts LEVEL
  along the aim, on past the player to `GRAB_REACH` 9.5 m unless stone stops
  it (`LUNGE_REACH` 13.4 from the middle) -- level, so it carries on into the
  clamp; aimed down from the vault it buried itself in the floor. 20 damage and
  a yank toward the table; parry cue, parry stun as before.
- SWEEP: within `SWEEP_RANGE` 2.8 m of the hovering claw: down beside the
  player at 1.85 m, then a rake sideways 2 x 2.8 m through them; stone across
  it stops it dead with sparks. 12 damage and a sideways knock.
- REAR (the slam): up over the player (`REAR_HIGH` 4.0), tracking, a hold, down
  into the floor: 24 damage in 2.4 m and a knockdown. Then STUCK for
  `REAR_STUCK` 1.9 s, exposed, before it tears free. Needs the hoist.
- The hover: `HOVER_SHORT` 3.4 m short of the player at 3.25 m, swaying, so it
  grabs at range and sweeps when they close in (at 2.6 it swept almost every
  time).

**Systems.** ARMS = grab and sweep, as before. "LEGS" is now the HOIST: cut,
the claw sags to the floor and is dragged at 1.1 m/s, its wrist cable exposed
(`_sagging`); jammed, for good. The power cable is wound round the wrist
(`CableHitbox`, 0.9 m box, layer 4 only while exposed); the claw's fingers
ring off blows (`ClawHitbox`). CORE and the relay unchanged.

### Measured

Every way to depower it, run for real in a throwaway harness (player held at a
spot, levers called, the cable hitbox struck): clamp (cut the arms, stand 1.3 m
before the open clamp, the grab is caught, three cuts), slam (stuck, three
cuts), jam (hoist cut then jammed: still sagging and exposed 12 s later, wrist
0.93 m), relay (arms, hoist, core: down, the claw on the floor), save (saved
depowered, restored to the same claw spot). All pass. Two failed first and
were real bugs: the clamp sat at 11.65 m, past a 10.5 m grab range; then the
arm stopped half turned, because the aisle was re-chosen every frame from the
hover point, which was itself projected onto the half-turned arm. One failure
was the test's own: it struck the cable before the next physics tick had
marked it exposed.

Benchmark, RTX 3060, 3440x1440, editor closed, the previous commit benched the
same session: surgery 42.7 fps / 23.41 ms avg, 1% low 34.4, p99 29.09 ms,
3,181 draws -> 45.3 and 44.7 fps / 22.07 and 22.37 ms, 1% low 38.0 / 36.6, p99
26.29 / 27.30 ms, ~2,500 draws (two runs) -- a little cheaper: sixteen fewer
torches outweigh four chandeliers and the kit. Overall 49.9 fps before, 50.2 and
48.9 after (noise: the other stations' numbers swing as much between runs).
Video memory 1210.2 -> 1233.7 MB (+23.5 MB, the kit's maps).

### Traps

- **`Vector3.slerp` between two nearly equal directions errors** ("The axis
  ... must be normalized", from `set_axis_angle`): it rotates about their cross
  product, normalised from almost nothing. The claw's direction is lerped and
  normalised instead (`_move_claw`).
- A temporary `instantiate()` to borrow a mesh (the segment) must be freed, or
  the game leaks render RIDs at exit.
- Never choose a heading from a point you derived from that heading (the
  aisle deadlock above).
- `find_children("Furniture")` finds one: siblings added with the same name are
  renamed `@Node3D@n`, not `Furniture2`.
- The vault has no collision (rays up from the floor hit nothing), so nothing
  stops the claw from entering it; its heights are constants measured off the
  hall (crown 5.1, arches over the gaps above 4.4).
