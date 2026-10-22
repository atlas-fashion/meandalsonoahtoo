## 98. The surgery rebuilt: elaborate walls, a study, testing areas, a shipping line -- every piece from Higgsfield (2026-10-22)

The user: "The room's architecture should be redone. Make it more elaborate
with the walls and stuff. There should be a corner of the room thats like a
study corner, with bookshelves and stuff. There should be scientific testing
areas, and there should be infrastructure for test subjects that are made to
be shipped out after the machine works on them. Use higgsfield for whatever you
need. I want no original assets or models that were made directly in claude."

**The rule this sets:** nothing in the surgery is built from primitives any
more. Everything note 96 still made in code -- roof beams, planks, corbels,
lintels, the hearth, the floor rail, the lever posts and handles, the three
wall mechanisms and their gears and flywheel, the clamp, the cables, the cuffs,
the chains, the prisoners' drill bits, the slabs, the broken table, the limb
rack, the tools, the torn restraints -- was replaced by a Higgsfield model or
dropped. surgical_table.gd's `_merge` / `_boxm` / `_cylm` / `_sphm` /
`_torusm` / `_mat` helpers are deleted. What stays generated-but-flat: the
plank ceiling (`textures/surgery_planks.png`, on a plane), the anatomy chart
(note 95) and the flame (`textures/surgery_flame.png`, billboard licks). Lights,
particles and collision boxes are engine nodes, not assets. The level's own
brick walls and floor round the hall are the brick kit's (note 27), untouched.

### The kit (models/surgery/, tools/build_surgery_kit.py)

44 gpt_image_2_5 pictures (high; the user's reference image as
`image_references`, one isolated object on grey) -> 42 Tripo H3.1 models (9
credits each, the pictures 1.5; 447 credits in all, 799 -> 352). One rate limit (the
monorail track) went through on resubmission. All fitted by the build script:

- architecture: `wallbay` (a gothic bay, blind tracery, skull string course;
  `fit` 5.0 x 0.55 x 8.6), `jamb` (clustered pilaster, 1.0 x 0.8 x 8.6),
  `lintel` (skull lintel, 5.0 x 0.7 x 1.1), `frieze` (tracery and skulls,
  5.0 x 0.55 x 3.9), `beam` (4.66 m section), `brace`, `corbel` (a grotesque);
- study: `bookcase`, `desk` (with chair), `lectern`, `globe` (armillary),
  `rug`, `books`;
- testing: `labbench`, `galvanic` (Leyden jars and coils), `testchair`,
  `still`, `slab`, `prosthetic` (the mechanical arm fitted to the subjects);
- shipping: `casket` (upright, numbered, tagged), `cagecart`, `crates`,
  `handcart`, `track` (monorail), `hook` (trolley and chain), `bundle` (a
  wrapped subject);
- the machine: `leverbox`, `handle`, `pistons`, `gear`, `flywheel`, `bar`,
  `column` (the core's glass), `clampmount`, `clampjaw`, `cable`, `chain`,
  `cuff`, `railring`, `grate`, `hearthjamb`, `mantel`.

The build script gained `"fit"` (each axis scaled to an exact size -- the
architecture has to meet its neighbours), an origin `"back"` (the clamp jaw's
hinge), and an optional 8th field `(rx, ry)` to stand a piece Tripo laid down
(the cable, 90 about X). **Most Tripo returns face +X** (thin along X): a
two-view render (from +X and from -Y) of every raw model settled each one's yaw
before building -- almost all -90.

### The hall (`scripts/surgery.gd`)

- `_build_walls`: on every ring cell's outer side a `wallbay` stretched to the
  span between pilasters (corner cells run on to the corner), or over a way in
  the `lintel` (underside 3.7) with the `frieze` above (4.8); a `jamb` pilaster
  every 6 m, and one set diagonally across each corner with no way in beside
  it. They stand in front of the brick (`BAY_DEPTH` 0.55, `JAMB_DEPTH` 0.8);
  their collision takes the first 3.2 m.
- `_build_roof`: the plank texture on a plane at `CEIL` 8.6 (world
  triplanar), the six beams as one MultiMesh of `beam` sections (alternate ones
  turned end for end), a `corbel` and a `brace` under each end.
- Torches on the pilasters' faces (none within 2 m of a way in), chandeliers on
  `chain` runs (`_chain`) from the beams.
- The hearth: two `hearthjamb`, the `mantel` and hood on them, the `grate` of
  burning logs, flames and a flickering light. (Note 96's built hearth is gone;
  the first generated hearth -- firebox filled in solid -- is still not used.)

**The four corners (`_zones`)**, chosen from the ways in: SHIPPING the corner
nearest one, the STUDY the furthest, LAB and TRIALS the other two by the seed.
A corner takes the wall slots on its own side of its two walls' middles; any
slot left over gets an apothecary shelf pair.

- `_study`: three bookcases on each of its bays, two more in the corner, the
  rug with the desk on it facing the table, the lectern and grimoire, the
  armillary sphere, piles of books, a chest, a candelabra.
- `_lab`: a lab bench and two specimen jars on each bay (green light), the
  anatomy chart over the first, the still in the corner, a bench as an island,
  the worktable, a chest, a candelabra.
- `_trials`: the galvanic machine and the tool rack on one bay, the iron maiden
  and a tool rack on the other, the testing chair facing the table, two slabs
  with subjects fitted with the `prosthetic` arm, the rack, the pillory, two
  gibbets from the beams, the older dead in the corner.
- `_shipping`: four caskets along each bay, the cage cart, crates, the hand
  cart, barrels, and the monorail along the beam over the corner -- three
  `track` sections, five `hook`s, four with a wrapped `bundle`, swaying
  (`_work_fires`).
- Two braziers by the rail on the lab and trials sides.

**The machine's fittings:** the levers are `leverbox` posts with a `handle`
(pivot at 1.42 m); the arms' mechanism the `pistons` panel with the `gear`
turning in its socket; the hoist's the `flywheel` with the `bar` beside it
(jammed: `_bar_jammed`); the core's the `column`, its glass glowing with the
core through its own materials (`_glow_own`); the clamp the `clampmount` with
two `clampjaw`s (mouth 1.6 m out from the bay); the floor rail the `railring`;
the cables the `cable` section in the MultiMesh, its picture as the sheath
(`surgery_cable.gdshader` `sheath_tex`). On the table (surgical_table.gd): the
`cuff`s on the restraint hinges, the `prosthetic` on the prisoner
(`attach_prosthetic`), no lens, bulbs, portholes or plugs (the table model's
own lamps glow with the core), and no visible wrist cable -- while it is in
reach the claw itself pulses cold and reddens with each cut (`_claw_mats`).

### Measured

A throwaway harness ran every route: grab (slammed, carried, strapped,
operated on, struggled free), carry (struggled free mid-air), clamp, slam, jam,
relay, save -- all pass. A reachability check (navmesh paths from each way in
to the table and every lever, ending at the goal) **failed** on the first
build: the cage cart stood across the shipping corner's way in and, with the
crates and caskets, walled it off -- paths stopped at (10, -10). `_floor` and
`_subject_slab` now leave out anything within `LANE` 1.4 m (plus its own half
size) of the line from a way in to the middle (`_in_lane`), printing what it
left out (on seed 20260918: the crates by the corner and the barrels); the cage
cart and hand cart were moved clear. Then all paths pass. (The check needs
~120 frames after `level_built` before the navigation map answers.)

Benchmark, RTX 3060, 3440x1440, editor closed, two runs: surgery 44.2 / 43.7
fps (22.61 / 22.87 ms avg), 1% low 31.9 / 30.2, p99 31.35 / 33.16 ms, ~1,800
draws -- against note 96's 45.1 / 46.1 fps, p99 34.11 / 29.67, ~2,170 draws:
the average a little lower, the tail in the same band, fewer draws. Overall
58.0 / 58.4 fps (the maze is note 97's layout now, so the other stations are
not comparable with note 96's). Video memory 1254.3 -> 1315.2 MB (+61 MB, the
new pieces' maps).

### Traps

- A navigation map answers nothing for the first frames after the level is
  built (empty paths): a reachability test that does not wait passes or fails
  for the wrong reason.
- Once in five clean runs: "1 resources still in use at exit"; not reproduced
  in five more (two of them `--verbose`). Unexplained.
- Tripo's flat pieces face +X; a single front render cannot tell a piece
  facing +X from one facing -X -- render it from two sides.
