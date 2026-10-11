# Working rules for this project

Godot 4.7.2, Forward+, Vulkan. Target hardware is a **Quadro P620 driving a
3440×1440 ultrawide** — weak fill rate, 2 GB VRAM, ~5 megapixels. Every decision
below follows from that.

## 1. Measure, then change, then measure again

**Never optimise on intuition, and never claim a speed-up without numbers.**

```
godot --path . --windowed -- --bench                   # current settings
godot --path . --windowed -- --bench --ablate          # cost of each switch
godot --path . --windowed -- --bench --size=3440x1440  # at the real resolution
godot --path . --windowed -- --bench --preset=potato
```

Rules that came out of getting this wrong:

- **Never benchmark with `--headless`.** The dummy renderer reports zero draw
  calls and the numbers are fiction.
- **Check for a vsync cap first.** The first run of this benchmark read a flat
  20.00 ms at every station; that was the refresh rate, not the game.
- Report **p99 / 1% low**, not just the average. Stutter is what players feel.
- When a change is supposed to make something faster, post the before *and*
  after at the same resolution. If it didn't help, say so and revert it.

## 2. What the measurements already established

Do not re-litigate these without new data:

- **This game is per-pixel bound, not geometry bound.** The worst spot in the
  level draws ~190 calls and under 100k triangles and still costs 25 ms.
- **Render scale is worth more than everything else combined** (−6.87 ms at 0.5,
  against an 11.42 ms baseline). Bloom −1.37, SSAO −1.19, torch shadows −0.80,
  textures −0.81, MSAA −0.43.
- **Cutting draw distance, mesh LOD or view range buys nothing here** (+0.11 ms,
  i.e. noise). Do not "optimise" by making the level see less — it costs the
  look and returns zero. Spend the budget on resolution and full-screen passes.
- CPU physics sits at 2–3 ms and has never been the constraint. Object pooling
  is not currently justified.

### Superseded by the organic kit level (2026-09-25)

The level is now the organic maze built from the Tripo kit in `models/kit/`
(`scripts/maze_graph.gd` → `scripts/organic_maze.gd`), not the square tile maze.
The tile maze survives behind `Maze.organic = false` as a fallback. Measured on
the P620 at 3440×1440:

```
spawn corridor     11.77 ms avg   p99 14.29    130 draws    96,983 prims
boss room centre   16.02 ms avg   p99 18.06    201 draws   147,873 prims
boss room edge     17.13 ms avg   p99 19.21    176 draws   138,193 prims
outer maze          6.57 ms avg   p99 10.42     63 draws    29,909 prims
OVERALL 89.5 fps   worst p99 19.21 ms   video memory 237.8 MB
```

- **Chunking the MultiMeshes bought nothing** (27.16 → 27.24 ms, noise). It is
  kept because it makes the draw-call counters honest and per-chunk occluders
  need it, but it is not a speed-up.
- **This level is still per-pixel bound.** Dropping the window from 3440×1440
  to 1720×720 takes the spawn station from 21.48 ms to 7.60 ms — a quarter of
  the pixels for a third of the frame. An earlier note here claimed the kit was
  geometry-bound, on the strength of a render-scale ablation run in
  `tools/preview_kit_level.gd`. That was wrong: the preview has no fog, no
  torches and no post-processing, so it measured the one configuration in which
  pixels are cheap. **Do not ablate lighting-sensitive costs in the preview.**
- **Omni light count is a per-pixel cost, not a CPU one.** Going from 347
  torches to 133 took the spawn station from 21.34 ms to 17.64 ms. Caching each
  torch's cull test to avoid a per-frame `global_position` read bought nothing
  (21.42 vs 21.34), and neither did switching torch shadows off — wall torches
  never cast shadows in the first place; the hand torch is the only shadow
  caster in the game. Lights cost where they overlap pixels, so the levers are
  their number and their range.
- **`--bench --ablate` is not usable on this level.** It runs the High preset,
  which the P620 cannot sustain here: every station pins at the 150 ms cap and
  its `cpu ms` column reports 579 ms against a 123 ms frame, which is not a
  per-frame figure. Ablate by changing one thing and re-running `--bench`.

## 3. New content must honour the settings system

`scripts/graphics_settings.gd` (autoload `Graphics`) owns every quality knob.

- Anything that **costs frame time** gets a quality knob: one property on
  `Graphics`, one entry in each of the five `PRESETS`, one line in `SPEC` in
  `scripts/pause_menu.gd`. The menu builds its own widgets — there is no scene
  to edit.
- Read authored values through `set_meta` the first time a setting touches a
  node, and always scale from that original. Scaling from the current value
  compounds on every re-apply.
- New lights, meshes and effects must survive a preset round trip
  (Ultra → Potato → Ultra) unchanged. There is a test for this.
- Expensive things that only exist sometimes (bursts, transparency, extra
  lights) check `Graphics.effects` before spawning.
- Anything built at runtime by `maze.gd` is created after startup, so it needs
  `Graphics.apply_all()` to reach it — that already fires on `level_built`.

## 4. Verify by measuring behaviour, not by reading the diff

For any non-trivial change, write a **throwaway harness** that measures what the
thing actually does, run it headless, fix what it finds, then delete it and do a
clean `--quit-after` run with stderr visible. Examples that paid for themselves:
`tools/verify_skeleton_clips.py` caught two inverted axis signs that looked
perfectly fine in the source.

- A test that can pass vacuously is not a test. Re-break the thing and confirm
  the test notices.
- When a test fails, first ask whether the *test* is wrong. Several times here
  the code was right and the assertion was measuring the wrong quantity (a hook
  judged on forward reach; a jaw judged in world space while the head rotated).
- Godot/GDScript traps hit repeatedly: a freed object compares equal to `null`,
  so only `is_instance_valid()` detects one; a freed object cannot be passed to
  a typed parameter; `ColorRect` defaults to `MOUSE_FILTER_STOP` and parent
  filters do not propagate; autoload names do not resolve in `--script` mode.
- The `--script` rule is narrower than it looks: it is the **entry file** that
  cannot name an autoload. Anything that file goes on to `load()` — `player.gd`
  referencing `Graphics.effects`, say — compiles and runs fine once the tree is
  up. So a harness can exercise code that uses autoloads; it just cannot name
  them itself.
- **`MultiMesh.get_instance_transform()` returns identity under `--headless`.**
  The dummy renderer never stores the buffer, so it reads back `(0, 0, 0)` for
  every instance — no error, no warning. Two checks that "passed" this way were
  measuring nothing: a determinism test comparing identity to identity, and a
  floor-coverage test in which all 1,571 slabs appeared to sit at the origin.
  Anything that inspects MultiMesh instance data must run **windowed**. This is
  the same class of lie as the headless draw-call counter above.
- A count is not a measurement. `_build_floor()` returned the number of
  placements it *intended* while the mesh was null and nothing was added, so
  the build reported 1,571 floor slabs on an empty node. Return what was
  actually placed.
- Tripo pieces import with `metallic = 1.0` driving their packed ORM map, and
  their albedo is near-white. The albedo needs tinting down (`organic_stone_tint`)
  or the level blows out; the metallic scalar turned out to matter less than it
  looked, but stone should not claim to be metal regardless.

### Lighting on this level is baked per instance, not per texel

`scripts/organic_lighting.gd` bakes each panel's torchlight into its MultiMesh
instance colour and then takes the static geometry off the torches'
`light_cull_mask`, so 209 omni lights stop shading the walls, floor and ceiling
while still lighting everything dynamic. Measured A/B on identical geometry:
spawn corridor 15.18 → 13.20 ms, overall 64.3 → 67.9 fps. No shadows, no bounce.

**Do not reach for `LightmapGI` here.** It cannot light a `MultiMeshInstance3D`
at all, and a lightmap needs fixed geometry, so using one means freezing the
maze to one seed and flattening every chunk into unique meshes. That was built
and measured: **497 MB of video memory against 251 MB for the whole instanced
game**, a 382 MB scene file, and merely having that file in the project took
the editor down three times with `Vulkan device was lost`. `LightmapGI.bake()`
is also editor-only — it is not scriptable, only `set_light_data`,
`get_light_data` and `bake_quality` are. `tools/freeze_level.gd` still exists if
the hardware ever changes.

### Kit stone is mapped WORLD TRIPLANAR, not by its own UVs

`organic_maze._tinted()` sets `uv1_triplanar`, `uv1_world_triplanar`,
`uv1_scale = 0.5`, `roughness = 0.92` and `normal_scale = 1.8` — the settings
`Mat_wall` in `scenes/maze.tscn` used before the kit existed, kept because they
were already tuned against this game's lighting.

The reason is that a generated asset's UVs are baked per asset, so every copy
shows the identical patch of stone and each join reads as a tile edge. Projected
in world space the texture is continuous across the whole level and the panels
stop announcing themselves. It also lets the GEOMETRY be flat: the detail comes
from the normal map, which is why the wall panel is 249 triangles and still
reads as carved stone. Prompt Tripo for a flat slab and let the texture work.

### Collision must sit BEHIND the wall face

A box centred on the wall contour reaches half its thickness into the corridor.
That shipped, as an 0.8 m invisible wall along every wall in the level, and the
test missed it because it sampled only corridor centrelines — which sit 2.2 m
from the boundary and never touched the intruding shell. **Sweep the whole
walkable region, not the centreline.** Two further causes, both worth knowing:
padding a box along its own length cuts the corner at a bend, and where rock is
thinner than the box, pushing it outward punches it through into the passage
beyond, so thickness has to be clamped to the rock actually probed along the
whole arc.

## 5. Generated assets

`models/ossuary_skeleton_rigged.glb` is a **build artifact** from
`tools/build_skeleton.py`. Never hand-edit it. See `tools/README.md` for the
rebuild command, the axis conventions and the traps.

`models/kit/module_*.glb` are build artifacts from `tools/build_modules.py`,
cut from the raw `models/kit/mod_*.glb` Tripo returned. Never hand-edit them;
rebuild and re-run `tools/verify_modules.py`.

## 6. The module level (2026-09-28)

The wall-panel kit is superseded. A cell is now ONE solid tunnel section that
carries its own floor, walls and vault, laid out on a 6 m grid
(`scripts/module_maze.gd` → `scripts/module_level.gd`). Panels were abandoned
because every defect they produced — stepping at bends, seams to the skybox,
collision that could not follow a curve, a texture restarting every 2 m — came
from tiling flat pieces along a curve. A solid section has no joins to go
wrong; the price is that the maze must live on a grid.

### What Tripo actually returns

**Ask for four specific shapes and you get four shapes, but not those four.**
Measured, not eyeballed: `mod_straight` was correct, `mod_corner` came back as
a four-way CROSS, `mod_tee` as a dead end, `mod_gate` as a dead end. Always
measure a generation's topology before building on it.

**Tripo builds interiors as doll's-house cutaways.** Four of the five pieces
had no roof at all — the ribbed vaults are decoration hanging under open sky,
not a surface. Every walkable column in cross, tee and corner saw sky. They
are capped by `add_lid()`, after decimation, because a two-triangle quad is
the first thing a collapse pass throws away.

**Missing shapes can be cut from the ones that arrived,** and that is cheaper
than more credits: a corner is a cross with two adjacent archways plugged, a T
with one, a dead end with three. The plug is a slab sliced off the donor's own
solid face, so it matches. Plugs are deliberately oversized to lap into the
floor, roof and walls, then `clip_to_cell()` trims the result back to exactly
one cell — without that, a plug juts through the neighbouring corridor's wall.

### Traps

- **A parity/voxel test cannot read these meshes.** Deciding solid-versus-air
  by counting surface crossings down a column failed twice: the overhanging
  roofs let a flood from the middle escape an archway and wrap around the
  OUTSIDE of the piece while still inside its bounding box, so every module
  read as having no walls; and once lidded, the single open sheet added one
  crossing to every column and inverted solid and air everywhere. Parity needs
  a closed surface and these are not closed surfaces. **Cast rays instead** —
  see `tools/verify_modules.py`, which also carries the controls that proved
  it (a bored block reads its opening at exactly 36% of the end face).
- **Godot does not import new assets in `--script` mode.** A run will report
  the file missing via `ResourceLoader.exists()`. Run
  `godot --headless --import --path .` first.
- A `--script` run that fails to load leaves the window open forever rather
  than quitting, which looks exactly like a hang.
- **Desaturating the stone texture does nothing you can see**, because every
  light in this game is a fire. Neutral albedo under a 1.0/0.72/0.42 torch is
  still brown. Grey needs the albedo leaned cool (`STONE_CAST`) as well.
- The roughness scalar MULTIPLIES the packed ORM map. Tripo's map is glossy,
  so `roughness = 0.95` alone leaves wet-looking highlights; the texture has
  to be dropped for the scalar to mean anything.
- Each grafted module carries TWO texture sets, because the plug brings the
  donor's material with it. Six maps per piece at 1K.

### Measured

Modules are 6.00 × 6.00 × 5.10 m, ~6k triangles each. Archways are 3.80 m wide
on a straight but only 1.60 m at the cross-derived junctions; collision jambs
are sized from those measurements, so **re-measure if the modules are rebuilt
at another scale**. A 16×16 maze is 256 cells in 61 draw calls. Collision is
boxes derived from the grid, not the mesh — a trimesh body per cell would be
about a million triangles to describe a grid of rectangles.

Measured on the P620 at 3440×1440, 17×17 cells with the 3×3 hall:

```
spawn corridor     13.80 ms avg   p99 20.64    115 draws   298,139 prims
boss room centre   17.47 ms avg   p99 18.82    166 draws   510,607 prims
boss room edge     19.12 ms avg   p99 20.96    168 draws   509,761 prims
outer maze         17.97 ms avg   p99 22.22    151 draws   443,850 prims
OVERALL 59.4 fps   worst p99 22.22 ms   video memory 332.8 MB
```

Against the panel kit it replaces (60.2 fps, p99 22.22 ms, 252 MB) that is the
same frame time for **three to five times the primitives** — more confirmation
that this game is per-pixel bound. The cost is +81 MB of video memory. Do not
"optimise" the triangle budget without measuring: it is not what is slow.

### The boss hall is a scaled cross

Nothing in the kit makes an open room and there were no credits left to
generate one, but the cross already is a vaulted chamber with an archway per
side — just corridor-sized. Scaled 3× horizontally and 1.7× vertically it is
an 18 m × 8.7 m hall in the same stone, for one draw call. Its nine cells are
reserved before the carve (`arena_half`) and it joins the maze only at the
middle of each side, because that is where its archways are — a corridor
arriving anywhere else would run into blank wall.

- **The hall needs its own torches.** It has no cells, so the per-cell torch
  loop never visits it, and it shipped as a pitch-black 18 m room.
- **Four, not eight.** Eight cost **2.9 ms** at the boss station (57.4 → 49.2
  fps); four in the corners light the same room for nothing measurable (57.5
  fps). Once the count is settled, ENERGY is the free lever — brightening
  four lights changes nothing about how many pixels they touch.
- The corridor ceiling cannot run across the map as one slab: the hall is
  taller, so a slab at corridor height cuts through it at chest height. It is
  laid as four panels around the hall's footprint plus a higher lid.

### Full-resolution modules, and what they cost (2026-09-29)

**Decimating the Tripo modules is what made the stone read as triangles.**
Their detail lives in a tangent-space normal map authored for the ORIGINAL
mesh; at 6k triangles (from ~14k) the vertex normals under it changed and the
shading broke along the new big triangles. On top of that the glTF importer
stores Tripo's normals as custom split normals, which went stale after the
booleans and scaling. `build_modules.py` now keeps full resolution (13-18k),
clears the custom normals and re-smooths by angle, and ships 2K textures.

Cost, measured: primitives in view 3-5x (880k-1.2M), video memory 338 -> 687 MB.
The frame is still per-pixel bound -- at 1720x720 every station ran about 3x
faster (spawn 16.4 -> 5.6 ms) -- so the triangles are not where the time went.

**Invented surfaces** (bored archway reveals, lids, floor slabs) are tagged
`synth_stone` in Blender -- the boolean's `material_mode = TRANSFER` carries the
cutter's material onto the faces it creates -- and get a world-triplanar graded
copy of the old brick (`tools/grade_texture.py`). Triplanar costs ~1 ms at the
spawn station (16.4 -> 15.4 with it off); kept, because the alternative is grey
smears. Ungraded, the old brick is tan with green vines and every archway
looked like a different building.

Also fixed in passing: `add_floor` used to recalculate normals across the WHOLE
Tripo mesh, which on a non-manifold mesh can flip wall faces. Scope any
`recalc_face_normals` to the faces you just made.

### Collision: exact for the player, boxes for everyone else

Wall collision used to be boxes at the CELL BOUNDARY while the visible stone is
well inside the cell (1.90 m from centre on a straight, boundary at 3.0), so
the player could walk over a metre into solid-looking stone. Now each module
exports a walls-only trimesh (`module_*_col.glb`, floors stripped, 7,000 tris,
shared per kind) and the player collides with that.

**Enemies must not.** Measured: with the trimesh for every body, physics at the
boss room's edge went from 1.4 ms to 5-13 ms and a boss caught on ragged stone
put a **104 ms** hitch into the frame. So the walls exist twice:

```
floor slab        layers 1+2   everyone stands on it
exact trimesh     layers 2+9   the player (mask 257); 2 = blocks sight
simple boxes      layer 10     enemies, boss, bomber, mimic (mask 513); navmesh
```

The navmesh bakes from mask 513 (floor + boxes), which keeps the bake fast.
Layer 2 is this project's sight layer (`sight_blocking_mask`, `geometry_mask`):
the first module collision was on layer 1 only, and **every enemy could see and
aggro through every wall in the level**. `verify_module_level.gd` now checks
passages and sealing separately for the player, the enemies and sight, because
a default-mask ray hits every layer and hides a gap in any one of them.

`tools/verify_collision.py` compares each collision mesh against its render
mesh. **Measure surface-to-surface, not distance along a ray.** A ray grazing a
pier's side face hits the pier at 1.4 m or skims to the back wall at 2.8 m on a
few centimetres of edge position; the first version reported that as metre-
scale errors in both directions at once and nearly sent the budget up for
nothing. With `find_nearest` the real disagreement is under 3 cm. At 2,500
triangles it was genuinely wrong in recesses (a 1.28 m invisible surface inside
a plugged arch); 7,000 fixed that.

### Rooms are cloisters

A room is a square block of cells in which every cell opens onto every
neighbour inside the block (`module_maze.gd`). The ring falls out as T-pieces
and corners -- a roofed arcade -- and the inside cells are `court`: no module,
no roof, paved, open to the sky. Boss room 7x7 (30 m courtyard), chest rooms
5x5 (18 m). Corridors that ran into a room's footprint become its doorways.

- **Do not set `_graph` in module mode.** `boss_tile`, `is_in_boss_room`,
  `is_in_treasure_room` and `_build_gates` all switch to the organic level's
  round-chamber rules when it is set, and pointed the chest test and the gates
  at rooms that did not exist. `_module_rooms()` feeds the square-room rules.
- **Courtyards need their own light.** Every torch hangs inside the arcade, so
  the court and the arcade's court-facing side were black silhouettes against
  the sky. A flat-lit shot proved the geometry intact; the fix was sky-coloured
  lights over each court at energy **22** (5.5 lit only the floor under them --
  they are ~10 m from the walls, a torch is ~2 m) and the sky drawn at 0.42.
- **Room lighting density was measured**: arcade torch every 2 cells -> boss edge
  24.0 ms, chest 22.7; every 4 -> 21.1 / 20.2 but the firelight was gone. Set to 3.
- **Enemy spawning**: open courtyards are all floor against one-tile corridors,
  so they swamped the candidate list -- 47 of 92 enemies spawned in rooms.
  Rooms are now excluded from corridor spawns. The 4 guards per chest room from
  `_spawn_room_packs` are deliberate and stay; the build reports the count.
- **Zone doors lived in `_spawned`**, which `_populate` frees on its first run,
  straight after the build -- they were destroyed before anyone could reach
  them. They are in `_zone_gates` now.

Measured on the P620 at 3440x1440:

```
spawn corridor     16.33 ms   p99 19.66    214 draws     879,644 prims
boss room centre   17.36 ms   p99 18.06    270 draws   1,008,464 prims
boss room edge     22.37 ms   p99 24.07    304 draws   1,178,794 prims
outer maze          8.69 ms   p99 13.89    134 draws     464,158 prims
chest room         20.47 ms   p99 21.67    293 draws   1,194,600 prims
OVERALL 65.5 fps   worst p99 24.07 ms   video memory 686.8 MB   physics <= 1.9 ms
```

Benchmark stations now sit in the rooms the level actually built; the old
fixed coordinates had dropped two of them onto the roof. Not comparable with
the 137 fps run above: the rooms moved the spawn to a different spot.

### The preview must carry the game's GRADE, or it lies about brightness

The scene's environment tonemaps with **ACES at white 4.0** and then applies a
colour adjustment (brightness 0.95, contrast 1.12, saturation 0.92). A preview
that builds a fresh `Environment` gets LINEAR tonemapping and no adjustment,
and ACES crushes midtones hard. The same geometry under the same lights looked
atmospheric in preview and nearly black in game, and that discrepancy signed
off three separate rounds of lighting work before it was caught.

`configure_environment` now sets the grade too, so the preview cannot flatter
the level. Raising ambient behind a wrong grade is not a fix: a test at
ambient 9.0 produced a pixel-identical frame while sky contribution was still
1.0, and even after that the numbers needed were far higher than the preview
suggested. Current values are tuned against the GAME: stone tint 1.0,
ambient 7.0, torch energy 10.0.

### A visibility range is measured from the node's ORIGIN

Chunks were positioned at the corner cell of a 24 m block, so a whole block
was culled while most of it was still inside the range and directly in front
of the player. In game that read as large slabs of wall simply missing. The
chunk node now sits at the block's CENTRE and its range carries an extra half
diagonal. Confirmed by disabling culling and watching the walls fill in.

### Rim walls need rock behind them

Tripo stone has a ragged foot and the modules are generated meshes, not sealed
boxes, so there are small gaps where a wall meets the floor. Inside the maze
that is harmless -- the neighbour's stone is right behind. On the RIM there is
nothing behind, and the same gaps show the void. That is what "large missing
segments at the bottom of the walls" was, and it is why every per-module test
passed, every corridor shot looked perfect, and only shots facing the edge of
the map showed it. `_place_backing` puts a slab of dark rock behind every
exposed face.

### Judge the level from the GAME, not from a preview

`tools/preview_module_level.gd` builds its own scene and lights it itself. It
showed readable, atmospheric corridors while the actual game was so dark the
player could see nothing but their own sword. **Screenshot the real thing**:

```
godot --path . --windowed --resolution 1600x900 -- --bench --shot
```

`tools/benchmark.gd` teleports to the player and writes `user://gameplay.png`.
This is the third time a preview has produced a confident wrong conclusion
about this game's lighting; the previous two are recorded above.

Two real faults hid behind that:

- **`ambient_light_sky_contribution` was 1.0** on the scene's environment, so
  ambient came entirely from the sky and `ambient_light_color` did nothing at
  all. The symptom is not "too dark" but "brightness has no effect" -- a test
  at ambient 9.0 produced a pixel-identical frame. `configure_environment`
  now forces it to 0.
- **The player spawned in a dead end**, because the spawn is the cell
  furthest from the boss and that is always a leaf. `_spawn_score` now
  penalises leaves by more than a couple of cells of distance.

### The junction archways had to be bored out

Tripo's cross -- which every corner, T and dead end is cut from -- has 1.60 m
openings in a 6 m room 5.1 m tall, against 3.80 m on the straight. At standing
eye height that does not read as a corridor: it reads as a small chamber with
holes low in the walls, which is exactly how it was reported. They are now
bored to ~3.5 m by `widen_passages()` with a round-headed arch cutter, no
credits spent. Two traps, both of which produced silently wrong meshes rather
than errors:

- **A boolean cutter must be a single closed manifold.** Stacking a box and a
  cylinder as two overlapping shells made the exact solver grow every
  module's bounding box to the cutter's length and leave two modules with no
  opening at all. The cutter is now one extruded arch profile.
- **Widen BEFORE sealing, never after.** Sealing joins the plug on as a
  second overlapping shell and the clip leaves open boundaries, so the mesh
  is neither manifold nor free of self-intersections and the solver produces
  nonsense on it. The unsealed cross cut perfectly, which is what gave it
  away.

**`ARCH_WIDTH` in `module_level.gd` must track the meshes.** It sizes the jamb
collision, so stale figures wall up the middle of every widened archway with
invisible geometry while the visible stone says it is a passage.

Measured after widening, with 197 torches: **113.3 fps, worst p99 13.79 ms,
338 MB** -- essentially unchanged from the 1.60 m version despite far longer
sight lines and 60% more lights.

### Every module must be the SAME height, with its floor at zero

`fit_cell` makes a module HEIGHT tall from the bottom of its BOUNDING BOX,
which is the underside of the floor, not the surface the player walks on.
Those differ per piece -- 0.28 m on the straight, nothing on the ones cut
from the cross, because the arch cutter had bored their floors away. Two
separate faults came out of that, and neither showed up in any per-module
test:

- **A 29 cm step at every straight-to-junction seam**, with *nothing at all
  below the floor plane* to hide it. The floor patch was a single quad, and
  a plane has no underside, so the line of sight went straight out of the
  level: measured, every module was open on all four sides below its floor.
  Those are the "rectangular holes at the bottom of the walls". The patch is
  now a BOX, and the player -- who stands on a collision slab whose top is
  y = 0 -- is no longer knee deep in the floor of every straight.
- **A horizontal slot around the top of every cell.** Dropping the floor to
  zero left the ceiling below the fixed height the lid is placed at, so the
  lid floated. Slots line up from cell to cell, so from inside the maze you
  looked out through the ceiling and saw the sky.

`stretch_to_full_height` scales Z so that once the floor is at zero the
ceiling is exactly HEIGHT, for every piece. Do not remove it.

**Sequential booleans degrade the mesh.** Cutting four archways one after
another silently stopped cutting part way through -- the tee came out with
one opening instead of three, no error anywhere. `use_hole_tolerant = True`
plus a weld between cuts fixes it, and the result is clipped to the cell
unconditionally because the solver sometimes leaves a cutter behind as loose
geometry.

### Two kinds of render, for two different questions

A dark atmospheric shot and a hole-hunting shot are opposite jobs and one
image cannot do both: in the intended lighting a hole is just one more black
patch. `preview_module_level.gd --flat` floods the level with white ambient,
kills the fog and leaves the background magenta, so anything open to the void
blazes out. That is what finally located the wall-base holes after every
aggregate test had passed.

### Dressing: floors, ambient, torches, windows

- **The "gaps in the stone" were not Tripo's fault.** Modules are scaled so
  their BOUNDING BOX is one cell, and the box is set by the overhanging roof,
  so the floor slab stopped short: 100% coverage in the middle of a cell,
  **42–67% in a ring at the edge**. Every join had a slot in it. Fixed by
  `add_floor()` laying a full-cell slab under the module's own floor, at the
  low decile of its real surface height so it never pokes through. Two
  triangles. Scaling the piece up instead would push the roof into the
  neighbour and trade a floor hole for a ceiling one.
- **Ambient is a floor on visibility, not a light.** Too low and the level is
  unplayable between torches; too high and the stone flattens. It stays cool
  so it reads as gloom, and it costs nothing.
- **Use `scenes/torch.tscn`, not bare `OmniLight3D`.** It already models a
  bracket and flame and already flickers on seeded noise — and its lights
  distance-fade, which is worth **more than 4 ms**: swapping bare omnis for
  it took the level from 59.4 to 72.0 fps. Torch positions come from
  `WALL_FACE`, measured per module, because the wall is 1.90 m from the
  centre on a straight and 2.79 m on the plugged ones; a fixed standoff
  buries the torch in stone in one and floats it in the next.
- **Barred windows are lit from BEHIND the grate**, out in the rock. These
  lights cast no shadows so stone does not stop them, and back-lighting is
  what makes the bars read as dark ironwork against the glow. Emission on the
  panel does not work at any level — it saturates the whole thing to flat red
  and takes the bars with it.

### The layout is the organic map, drawn onto the grid

`module_organic_shape` samples `scripts/maze_graph.gd` -- the generator that
makes the sprawling disc with a round arena, chambers, dead ends and long
cross-map links -- onto the cell grid. Its bowed corridors cannot be built
from rigid square sections, so the curves are lost; the footprint, topology
and feel are not.

**Draw the corridor POLYLINES onto the grid; do not sample the distance
field.** The first attempt opened any cell the network passed within half a
cell of, and produced a solid disc of floor with a few islands of rock in it
— nothing like a maze. Corridors are 4.4 m and cells are 6 m, so a distance
test loose enough not to drop cells is loose enough to swallow the rock
between neighbouring corridors. Following centrelines keeps corridors one
cell wide at any grid coarseness; consecutive samples on a curve can be a
knight's move apart, so they are joined with an L rather than assumed
adjacent.

**Prune islands BEFORE driving the hall's corridors, not after.** Rasterising
a curved network always strands a few pockets. Pruning last can delete a cell
an archway points at.

**Do not close an opening that points into the arena.** Its nine cells are
deliberately absent from `cells`, so a blanket "close anything pointing at a
cell I do not have" walls up all four hall mouths right after opening them.
That cost an hour: the hall rasterised as a sealed island of exactly 181
tiles in the middle of the map. When the grid reports fragmentation, the
build now prints each island's size and location, which named the cause
immediately.

Measured, 33x33 cells, 405 cells placed, at 3440x1440:

```
spawn corridor      6.83 ms avg   p99  9.26     86 draws   133,188 prims
boss room centre   11.05 ms avg   p99 11.76    144 draws   365,073 prims
boss room edge     12.22 ms avg   p99 13.33    154 draws   389,853 prims
outer maze          6.53 ms avg   p99 10.42     73 draws    96,613 prims
OVERALL 118.0 fps   worst p99 13.33 ms   video memory 337.4 MB
```

**The organic layout is much FASTER than the square grid maze** it replaced
(70.8 fps, p99 18.06 ms) despite having more cells, because one-cell-wide
winding corridors cut sight lines and very little is ever in view at once.
More evidence the constraint is pixels, not geometry.

### The tile grid must stay in phase with the cell grid

Gameplay — chests, enemies, spawns, the boss test — all index `grid`, so the
module layout is rasterised into it. The cell size must be an **odd whole
number of tiles** and both counts must be **odd** (17 cells × 5 tiles = 85),
or cell centres fall between tile centres, the one-tile doorways land on
stone, and the maze rasterises into islands. `_build_module_level` checks
this rather than trusting it, and the build prints reachability every time.

The grid is a PROXY; the geometry is the truth. Its walkable core and doorway
channels are deliberately narrower than the real openings — claiming floor
where there is stone puts an enemy inside a wall, while claiming stone where
there is floor only wastes a little space. The arena needs its archways
painted in explicitly, or its floor is an island ringed by "wall" and nothing
can walk in.

Traps hit here: `grid` is `Array[PackedByteArray]`, so a plain `Array` from
the rasteriser is **refused at runtime** and leaves the grid empty — use
`assign`. Torch count rides on the existing `light_detail` knob and is read at
build time, because `Graphics.apply_all()` cannot retro-fit a torch that was
never spawned.
