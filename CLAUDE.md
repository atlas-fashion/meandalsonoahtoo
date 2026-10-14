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

`models/player_sword_meshy.glb` (the sword in use) is a build artifact from
`tools/build_meshy_sword.py`, fitted from the Meshy sources in
`models/source/meshy_sword/` (a `.gdignore` folder). Rebuild, never hand-edit;
see `tools/README.md`.

`models/kit/gate_door.glb` (the corridor doors) is a build artifact from
`tools/build_gate_door.py`, cut out of `module_gate.glb`. Rebuild, never
hand-edit; rebuild it whenever the gate module is rebuilt.

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

### Ten-change wave (2026-09-29): what was learned

- **A harness can silently change the user's graphics preset.** Something run
  during this wave rewrote `user://graphics.cfg` from Low (render scale 0.62, no
  SSAO or glow -- the settings every baseline here was taken at) to High at
  full scale, and the next benchmark read **18.2 fps against 65.5**, with every
  new feature looking guilty. A probe switching each one off saved ~5 ms in
  total; the real cause was 2.6x the pixels. **Check the benchmark's `scale`
  and `ssao/glow` header line against the baseline before believing a
  regression**, and never let a harness persist a preset.
- **A sky shader that reads `TIME` re-renders the radiance cubemap every
  frame**, visible or not: ~2.5 ms at EVERY station on the P620, corridors
  included. `scripts/sky_setup.gd` sets radiance 32 and
  `PROCESS_MODE_INCREMENTAL`; ambient is a flat colour and the stone is too
  rough to reflect, so nothing needs it. Measured after: 66.5 fps, worst p99
  23.33 ms, 737 MB (baseline 65.5 / 24.07 / 687).
- **The sky is procedural** (`shaders/sky_clouds.gdshader`, quarter-res pass).
  It is drawn at `SKY_ENERGY` 0.42 through ACES, whose toe crushes it: a zenith
  of 0.2 read as black, 0.78 as flat bright red. Tune it in the game shot.
  Without a perspective divide the cloud layers hung as vertical curtains near
  the horizon; a softened `xz / (y + 0.2)` deck fixes that.
- **Rock pillars are procedural** (`tools/build_rock_pillar.py`):
  `rock_column.glb` baked at its real 1.3 x 9 m and `rock_pillar.glb` at 1 m for
  pedestals and steps, each on its OWN UVs. Stretching the unit rock 9x drew its
  cracks into wood grain, and world triplanar on a non-tiling baked texture
  showed the UV islands as horizontal bands -- stacked drums, i.e. "bricks".
  Collision is a cylinder, because a box's corners stick out of round rock.
- **The courtyard sky lights hang directly over the rock** (inside the top of
  each boss column), and at energy 22 they blew the dark stone out to pale
  concrete and pink blotches whatever the albedo was. The rock is on its own
  visual layer (`ROCK_VISUAL_LAYER`) and the sky lights' cull mask leaves it out.
- **Windows are built from primitives**, not the Tripo grate: an emissive glow
  panel (radial gradient), a stone frame standing proud of the wall, iron bars
  and a red omni in the rock behind. Darkened, the grate read as a black square;
  undarkened, as a grey plate. Two traps hit on the way: the default emission
  operator ADDS the emission texture to the emission colour, so a white colour
  made the gradient pure white; and the shared stone materials set
  `vertex_color_use_as_albedo`, which renders a BoxMesh (no colours) black.
- **The glow panel must sit in FRONT of `WALL_FACE`.** It is measured at torch
  height and the Tripo stone at eye height stands up to ~10 cm nearer the
  corridor, so a panel placed behind the face was buried in stone.
- **`Graphics.set_preset()` SAVES by default**, and the benchmark's
  `--preset=` went through it -- that is how the settings file got rewritten.
  It now takes `persist := false` for runs that must not touch the player's
  settings; the benchmark passes it. Any harness that changes a preset must too.
- **`_apply_light` used to be one-way**: a cheap preset turned distance fade ON
  for always-on lights (the moon) and nothing turned it back off, so a
  Ultra -> Potato -> Ultra tour left the moon fading. It now restores the
  authored fade. (CLAUDE.md said "there is a test for this"; there was not.
  Measured with a throwaway harness: 236 lights, 0 differ after the round trip.)
- **The exploration map's pixel for a world point needs +0.5 cell**:
  `Built.to_world(pos)` is a cell's CENTRE, but cells are painted from their
  top-left corner. Without it the player marker (and the minimap's centring)
  sat 3 m up-left, on the wall. Measured: 0.00 px offset on 12 corridor cells;
  with the half cell removed, 11.3 px and 12 of 12 markers off the floor.
- **Clouds: gradient noise plus a domain warp**, not value noise. Overhead the
  deck is low-frequency, and thresholded value noise there made flat grey
  sheets with straight shard-like edges. `--bench --shot` now has a `sky`
  station that looks up from the boss court (via the player's `_look_pitch`,
  which it re-applies every frame, so setting `Head.rotation` does nothing).
- Final bench, P620 3440x1440, Low: spawn 16.11 (p99 19.54), boss centre 17.41
  (18.06), boss edge 22.08 (24.16), outer 8.51 (13.38), chest 20.89 (22.22).
  OVERALL 66.0 fps, worst p99 24.16 ms, 737 MB.
- **The boss room is sealed at its COURTYARD, not its outer doors**
  (`maze.gd _boss_court_gates`). A wall on collision layer 11, which only the
  boss's mask includes, keeps him in the court: measured, his centre stops at
  13.80 m from the room's centre, i.e. the 15 m court edge minus his 1.2 m
  radius, short of the arches at 15.2 m. Outer-door gates would then have left
  the whole arcade as a safe place to stand, so a portcullis
  (`scripts/portcullis.gd`, same `set_sealed` interface as `gate.gd`) fills each
  of the 20 court-facing arches instead. The bars GROW down from the crown:
  stored above it they would stand up through the arcade roof into the open
  sky. Arch sizes (3.6 m wide, crown 3.82 m, passage 2.3-2.8 m in from the
  arcade cell centre) were measured with rays against the exact collision.
  Trap: `Maze._process` re-applies the committed seal every frame, so a test
  that seals gates by hand sees them reopen at once; test through a real fight.
- **Skylights are a real hole in a module variant**, `module_straight_sky.glb`
  (`build_modules.py cut_skylight`, rebuild alone with
  `BUILD_ONLY=straight_sky`). One straight in three outside rooms uses it
  (`module_level._pick_skylights`); the dressing (stone liner, bars, a red
  spotlight pooling on the floor) is `place_skylights`. Trap: deleting faces
  with a VERTEX over the opening left the outer roof's big triangles -- they
  span the whole hole without a vertex in it -- covering most of the sky. The
  mesh is now bisected along the four edges first and faces are judged by
  their centre. Measured: 64.9 fps, worst p99 24.03 ms, 780.5 MB with 28 lit
  (was 66.0 / 24.16 / 737; the +43 MB is the variant's own texture set).
- **Torches were remade** (`scenes/torch.tscn`): iron wall plate, arm and ring
  holding a tilted wooden handle with a charred pitch head, a procedural flame
  card (`shaders/torch_flame.gdshader`, Y-locked billboard, additive, animated
  noise through an ember->orange->amber->core ramp) plus a soft halo card, and
  a few GPU embers gated on `Graphics.effects` and stopped out of range. All
  torches share one flame material; per-torch `seed` and the flicker
  `intensity` are INSTANCE uniforms driven by `torch.gd`. The light went from
  pale (1.0, 0.76, 0.50) to fire orange (1.0, 0.5, 0.2) and
  `module_torch_energy` 2.3 -> 2.8 to keep the corridors' brightness. First
  flame at 0.34 width with a steep taper read as a white candle jet; width and
  torn tongues are what make it read as a torch.
- **Pillar vines** (`tools/build_vines.py` -> `models/kit/vines_column.glb`,
  `vines_pedestal.glb`): stems traced by ray-casting onto the actual rock
  mesh at its drawn size, so they hug the lumps; leaves sway in
  `shaders/vine_leaf.gdshader` from vertex colours (R = stalk-to-tip weight,
  G = phase). First pass pointed blades straight out from the stone, which
  from the court showed them edge-on as slivers; they now hang with the
  broad face outward. Measured cost 1-2 ms in the rooms (boss edge 20.54 ->
  22.57 ms), so they have a knob: `Graphics.foliage` ("Pillar vines"), off on
  Potato. The pillar rock is darkened to 0.68 via `ROCK_DARKEN` in maze.gd.
- **Pillar vines were removed** at the user's request (2026-09-30), with their
  "Pillar vines" knob. `tools/build_vines.py`, `shaders/vine_leaf.gdshader` and
  `models/kit/vines_*.glb` are left on disk, unused. The darker pillar rock stays.
- **Windows are now two kinds, both with the red glow** (`place_windows`): a
  VIEW out of the maze -- the pane is `shaders/window_view.gdshader`, which
  ray-traces a yard behind the glass (dirt floor, rock ridge, red sky, three
  layers of `textures/window_plants.png` dead plants from
  `tools/build_dead_plants.py`) -- and a CAGE, an iron cage standing out of the
  frame with the Tripo skull (`models/skull_worn_ready.glb`, 898 tris), bones
  and stones, against the red glow panel. Rim walls always get views; of the
  rest, `WINDOW_VIEW_SHARE` are views. Two traps: the yard's floor has to sit
  well BELOW the window (it was 0.95 m under it and every ray at eye height hit
  the dirt, so the whole pane was one flat colour -- found by colouring each
  surface a debug colour), and a bright haze colour washes every layer into the
  sky. Measured: windows on vs off (16 of them, lights included) 57.8-58.6 vs
  61.9 fps; the old windows had the same lights, so most of that is the lights.
- **Windows are now all bone cages RECESSED into the wall** (2026-09-30; the
  view-out and protruding-cage versions were dropped). `build_modules.py
  cut_niche` builds `module_straight_niche.glb`: the straight with its +X wall
  face bisected and opened over 0.9 x 0.8 m at a 1.05 m sill into the hollow
  Tripo wall shell (face measured at 1.843 m). `module_level._pick_niches`
  puts one in 1 of 5 corridor straights, turning the piece half round (only
  that piece; the verifier allows exactly that) when the niche is wanted on
  the other wall, and `place_windows` lines it with stone, puts the red glow
  panel at the back, bars across the front, a random heap of bones, rocks and
  sometimes the Tripo skull on the floor, and the old window's red omni at the
  top of the niche. Torches skip the niche wall. Collision is the plain
  straight's, so nobody reaches inside. Measured 61.7 fps / worst p99 26.51 ms
  with 13 cages vs 61.9 / 26.21 with no windows at all; 825 MB (the variant
  brings its own texture set, +43 MB).
- **Bored archways get a clean lining** (`module_level._place_arch_liners`):
  the boolean's soffit was torn into floating shards with see-through gaps.
  Double-siding the materials fixed only the faces wound backwards (~5% of the
  test frame changed, the gaps stayed), so a jamb + round-head lining in the
  arch stone, 1.5 cm inside the cutter's surface (R 1.785, springing 2.02,
  2.25 -> 3.02 m out), is laid in every open side of cross/tee/corner/dead.
  One MultiMesh. Invented stone (synth/arch) is double-sided; Tripo stone
  stays one-sided (switching it too changed nothing measurable).
- **Bone cages hold loot now** (`scripts/bone_cage.gd`): light brick lining,
  the skull on a heap of gold coins and white jewels (MultiMeshes under a
  "Loot" node), the bars on a "Door" hinged at the left jamb. E (action
  `interact`) in front of a cage swings the door, scoops the loot into a sack
  that flies to the player, drops the skull to the floor and pays a random
  5-13 into `player.currency` (signal `currency_changed`), shown under the
  minimap by `explore_map.gd`. Trap: polling `Input.is_action_just_pressed` in
  `_process` missed presses landing between frames -- read the input EVENT.
  Measured: each new piece switched off saves <= 0.5 ms; the bench read
  58.2 fps / worst p99 27.71 ms, against a single 61.7 run earlier the same day.
- **Looting a cage is a short uncancellable scene** (`bone_cage.gd _play`), no
  sack: `player.begin_cutscene()` (no input, no movement, no damage or
  knockback) -> the player's own yaw and `_look_pitch` tween to face the cage
  -> the door swings -> every coin and jewel becomes its own glowing piece and
  flies on a curve, staggered over 0.9 s, to just in front of the view, with
  camera-facing gold/white ribbon trails (one ImmediateMesh rebuilt per frame)
  -> the view tweens back to exactly where it was -> `end_cutscene()` and pay.
  Measured: ~3 s, worst frame 23.6 ms without screenshots (the 900 ms "script"
  in shot overlays is the screenshot readback), view restored to 1e-4 rad.
  Trails at 3.5 cm wide read as white cones near the camera; 9 mm reads right.
- **E ("interact") opens everything now** -- chests (no more walk-up opening),
  the mimic (it shows the chests' exact prompt and springs on E, so nothing
  gives it away), bone cages and wooden doors. The prompt is one helper,
  `scripts/interact.gd` (class_name `Interact`; a new class_name needs a
  `--headless --import` before a plain run can resolve it).
- **Cages hold exactly what they pay**: `_fill_niche` rolls 5-13 with the build
  rng, stores it as the cage's `amount` meta and lays that many pieces (about a
  quarter jewels); `bone_cage.gd` pays the meta. The glow panel is gone from the
  back, so the brick shows there and the niche's red light does the glowing.
- **Wooden doors** (`place_doors` + `scripts/wood_door.gd`): double leaves of
  dark planks cut to the arch-lining profile, iron straps and ring pulls, in 1 of
  12 corridor-to-corridor bored archways (19 in this level). The blocker
  (layers 1+2: player, enemies, sight) starts disabled and arms on
  `Maze.level_built`, after the navmesh bake, so an opened door does not leave
  the corridor cut in the navmesh. Trap: the builder adds the leaves and blocker
  after the door enters the tree, so looking them up in `_ready` found nothing.

### Floating skulls, wooden doors (2026-09-30)

- **The cage skull model faces +X, not -Z.** Its rest yaw is -PI/2, and the
  look-at basis in `bone_cage.gd` is post-rotated by `Basis(UP, PI/2)`; the red
  eyes are placed on the +X face of its AABB. Aim anything at "the skull's
  front" through that, not `-basis.z`. It rises 0.2 m and tracks the camera
  only while the player is inside interact reach, and settles once looted.
- **Door wood is procedural** (`tools/build_wood_texture.py`, seed 5). Tripo
  was asked first: a textured model costs 20 credits and the balance was 10.
  The user prefers this weathered grey-brown version over a darker brown pass
  -- do not "fix" its colour; under the fire lights it already reads warm.
- **A door leaf is ONE mesh with real UVs** (`_door_leaf_mesh`), each plank
  mapped to one of the texture's four boards. Plank tops are sampled along the
  arch curve (`DOOR_TOP_STEPS`): cut flat they stair-stepped against the round
  arch, and on a single chord the outer board left an 18 cm notch, because the
  arch is nearly vertical at the jamb.
- **PowerShell `[IO.File]::WriteAllLines` writes CRLF**, after which any
  "`n"-anchored string replace silently matches nothing and a splice lands in
  the wrong place (one landed at the top of `module_level.gd`). Write with
  `WriteAllText` and normalise to LF.- **Cage eyes sit in the socket centres**: `EYE_RISE` -0.025, `EYE_SPREAD`
  0.235, `EYE_DEPTH` 0.13. At +0.06 / 0.21 they sat up under the brow at the
  inner corners and the skull read as cross-eyed. Judge them from a close-up
  camera with the cage door hidden; at gameplay distance the bars hide them.
- **Looted pieces end BELOW the view** (`OFFSCREEN_AHEAD`, `OFFSCREEN_MARGIN`
  x the frustum's half-height from `camera.fov`), and a finished piece's trail
  drains instead of blinking out. At the old target (0.8 m ahead, 0.42 m down)
  the player watched every coin shrink and vanish. Measured: 0 pieces removed
  on screen, nearest 127 px below the frame; with the margin broken to 0.5 the
  same check counted 35 on screen.- **Jump camera** (`player.gd`, groups "Landing bob" and "Jump takeoff"):
  takeoff dips the head 4.5 cm as the legs drive, then lifts it past rest,
  tipping the view up 1.6 deg and opening the FOV +2 deg over 0.38 s
  (`_jump_kick`, composed in `_update_head` / `_update_dash_view`). Landing was
  scaled against 14 m/s, so an ordinary 5 m/s jump landed at 25% -- a 1.2 cm
  dip nobody noticed; now 9 m/s reference, 11 cm / 3.2 deg at full, and it
  drops in over ~50 ms (`_landing_shape`) rather than in one frame. The
  landing pitch used to be ADDED, which tips the view UP (+rotation.x is up
  here); it now nods down as the export's comment always said. Measured on a
  real jump: takeoff -4.4 cm / +1.54 deg / +1.99 fov, landing -4.1 cm /
  -1.55 deg, settles to 1 mm and exactly the base FOV.
- **Every wooden door has a torch either side of its arch**, on the door
  cell's wall face (`_door_torch_spots`): 1.76 m from the cell centre at 2.05 m
  off the arch's centre line in cross/tee/corner, 1.46 m in a dead end,
  measured with rays. Side-wall placement was tried first and failed: only 9
  of 19 doors had a cell with both side walls solid, and 10 of those torches
  were inside stone near the straights' ends. `place_doors` now runs before
  `place_torches` and leaves `Built.doors`; door cells skip their random torch.
  Measured A/B (38 torches): 56.3 vs 57.5 fps, ~1 ms at spawn and boss edge.- **Inventory** (`scripts/inventory.gd`, class_name `Inventory`): 9 hotbar
  slots (keys 1-9, actions `hotbar_1`..`hotbar_9`) then a 27-slot bag; item
  kinds in `Inventory.ITEMS` (sword, health_potion, coins), icons drawn in code
  by `item_icon.gd`, one widget for every slot (`item_slot.gd`: drag/drop to
  move/merge/swap, shift-click bag<->hotbar, right-click split). The hotbar is
  built by `hud.gd` (bottom middle; the old consumables strip `$Slots` is hidden)
  and the full screen is `inventory_screen.gd` on "inventory" (C), created by the
  HUD. It is NOT a pause: the world runs, `player.ui_open` cuts look, attack and
  movement (`_move_input()`), Escape closes it before the pause menu sees it.
  `player.currency` is now a getter over the coins carried; `add_currency`,
  `add_consumable(type, n, notify) -> int` and `currency_changed` keep their old
  contracts for chests, drops, the mimic, cages and the minimap. Healing moved
  from 1 to "heal" (F): it drinks the potion in hand, else the first carried.
  The held slot decides the mouse: sword swings/slams; a potion is
  drunk; anything else does nothing. Respawn tops potions back up to
  `starting_counts` in the slot the player keeps them in. Consumables map to
  ids by `item_name.to_snake_case()`.
- **Sword out of view** (`player._update_sword`): the AnimationPlayer owns
  `Head/SwordPivot` and rewrites it every frame, so the duck is applied to the
  `Sword` MODEL as `P^-1 * D * P * rest`, rebuilt from rest each frame (layering
  onto the pivot would be overwritten or compound). Rays from the eye to three
  points down the blade on masks 2|256 (stone only -- enemies are on 1+3, so
  standing close to one never ducks it). The same motion puts the sword away
  when another slot is in hand. Measured: against a wall at 0.55 m it ducks to
  1.00 with 0 of 5 blade points on screen; 2 m back it returns to 0.00.
- **Doors hang at the arch MOUTH** (1.65 m from the junction centre, 1.38 in a
  dead end) and always swing INTO the junction. At 2.6 m the hinge line ran
  under the arch's vault (2.58 m high from 2.2 to 2.7 m out) and 3.8 m leaves
  could not open without going through stone. Test: points over every opened
  leaf, ray from the junction centre at the same height -- 0 behind stone; the
  control (one door moved back to 2.6 m) saw 11.
- **Four torches per door**: a pair on the junction face beside the arch and a
  pair beyond -- the far junction's face, or a straight's side walls 1.4 m from
  its centre. Straights' walls near their ends are NOT uniform (1.77 m on most,
  2.05 m on others, not a variant flag), so `wood_door._snap_torches` moves each
  onto the real stone by ray once collision exists (all 76 then 0.12 m off).
  Bench (Low, 3440x1440): 57.1 fps, worst p99 31.15 ms, vs 56.3 with two per
  door and 57.5 with none -- noise, except ~1 ms at the spawn, beside a door.
- **Harness trap: calling `_get_drag_data` outside a real drag** leaks its
  preview, which then draws on screen as a large disc; it cost a wrong fix
  (shrinking the torch halo, reverted). Screenshot from a run that does not do it.- **Doors are light-tight** (measured, not eyeballed): an unlit magenta panel
  behind each closed door, six views from each side, magenta pixels counted.
  Before: 22,009 over 72 shots. Three leaks: the 8 mm gaps left between planks,
  a 2 cm slot under the leaves, and -- the big one -- the arch's MOUTH, where the
  door now hangs, flares far wider than the arch (open to 3.77 m at 1.7 m off
  the centre line, against 2.56), so from the corridor side light came round the
  leaves. Fixed by planks edge to edge, leaves sunk 4 cm into the floor, and a
  static stone surround (`_door_frame_mesh`, arch material) just behind the
  leaves with a hole 7.5 cm smaller than them. After: 0 over all 19 doors x 12
  views; control with the doors OPEN: 37,387, so the test can see.
- **The exploration map stops at shut doors** (`explore_map._door_shut`, keyed by
  cell boundary from `Built.doors`). The level's `open` mask treats a doorway as
  open, so the sightline used to map the corridor behind a closed door.
  `wood_door` emits `door_opened`, and the map recasts its sightlines at once.
  Tested on 5 doors from inside their cells: hidden 5/5 shut, shown 5/5 the
  frame after opening; control with the door check removed mapped straight
  through.- **The sword's TIP stays out of walls** (`player._sword_clearance`). The first
  duck tested the HELD pose at three points that stopped 0.9 m short of the
  2.65 m tip: 174 of 960 frames had the sword in stone, up to 1.67 m deep.
  Three faults, each found by measuring, each needed:
  1. Test the DUCKED pose, at points measured off the mesh (`_measure_sword`:
     tip, guard ends, five down the blade). Duck levels 0..1 are tried in
     tenths: `hard` = least clear at contact (applied instantly, a floor),
     `soft` = least with `sword_duck_margin` of air (eased toward).
  2. Run it from `RenderingServer.frame_pre_draw`, not `_process`: the player's
     `_process` ran before the AnimationPlayer moved the pivot, so mid-swing
     the duck was fitted to last frame's pose.
  3. The duck is NOT monotonic: easing down from 0.82 through 0.77 swung the
     guard into a side wall that both 0 and 1 cleared. The level actually drawn
     is tested itself (`_sword_clear_at`) and pushed further down if it clips.
  After: 0 of 960; boss court, six swings: max duck 0.000; cost 0.026 ms a frame
  in the open, 0.095 ms against a wall. Harness trap: measure at
  `frame_pre_draw` too -- measuring at the next `process_frame` reads the sword
  drawn last frame against a body physics has already moved 8 cm closer.- **Held potion** (`scripts/held_potion.gd`, model `models/potion_held.glb` from
  `tools/build_potion.py`): rises into the right hand when a potion slot is
  selected (the sword ducks away as before), tips to the mouth on a drink, and
  finishes that motion even when it was the last one. Held at half the
  modelled size, 0.21 m from the eye, so it stays inside the player's 0.4 m
  collision radius (measured 0.333 m at rest, 0.243 at the top of a drink) and
  needs no wall test. Green, not red, everywhere now (icon, ITEMS, the .tres).
  Colour traps: emission 2.6 through ACES read as pale mint, and a lit liquid
  under the orange hand torch read as lime -- it is nearly all emission with a
  little albedo. **No light**: a green omni in the flask cost ~1 ms a frame
  (19.6 vs 18.5) at either 1.4 or 0.8 m range and only tinted the glass neck,
  which a faint emission on the glass now does. Holding it: 18.5-18.8 ms
  against 18.1-18.4 with the sword (noise).- **The corridor doors are the Tripo gate** (2026-10-01): the pointed-arch
  double door with iron bands in the `gate` module (the cells the map marks
  green), cut out by `tools/build_gate_door.py` into `models/kit/gate_door.glb`
  ("LeafL", "LeafR", "GateFrame") at 1.15x. Located by rendering the module
  alone, then measured with ray grids: leaves in the plane x = -1.776 of the
  module's -X wall, moulding 0.18-0.24 m proud; the opening is two concentric
  two-centred arches (half-width 1.21, springing 2.0, radius 1.929 about centres
  0.719 either side, apex 3.79; moulding the same +0.43); seam at z -0.335.
  The plank doors stay in the code as the fallback.
  Traps hit, all found by measuring:
  - **A face's centre is not enough to crop a Tripo mesh**: a few huge
    triangles cross the whole module with their centre in the doorway; the
    first cut spanned 11 m. Every vertex must lie in the gate's slab.
  - The exported pieces carry material NAMES only (`export_image_format
    NONE`); `_gate_door_parts` gives them the module's own fixed materials,
    duplicated with `vertex_color_use_as_albedo` off (or they render black --
    the MultiMesh instance colour is what those materials expect) and both
    faces drawn. No second texture set.
  - The leaves are one-sided sheets with iron standing up to 0.35 m proud. The
    back is a mirrored copy of the BOARDS only, so it is 12 cm deep and the
    stone surround (pointed hole, `GATE_OVERLAP` under the leaves) can sit right
    behind it. The leaves meet with a ~2 cm gap that backed onto wall in the
    module: a batten behind the right leaf covers it. Light test: 43,272 px ->
    0 over 19 doors x 12 views; control with doors open 78-101k.
  - **Hinge in front of the boards** (`GATE_HINGE_FORWARD` 0.30): on the boards'
    line the straps' proud ends swung into the moulding (247 sampled vertices in
    stone), at 0.12 still 152. 0.30 clears everything (0 of 5,738); the open
    leaves then rest 0.3 m in from the jambs.
  - The gate is 2.78 m wide in a 3.57 m bored arch, so `Jambs` (layers 1+2,
    live from the start, so the navmesh bakes them) make the stone either side
    solid. Reachability still 100%.- **Benchmark with the Godot editor CLOSED.** With the editor open on this
  project (main.tscn, 1.9 GB working set) the game took ~1.4 s stalls several
  times a station -- p99 140 ms, the bench's cpu column 500-860 ms -- and an
  A/B with the whole maze and the player switched off still stalled, so it was
  not the game. Editor closed: 0 stalls, worst frame 23.7 ms. On a 2 GB card
  the editor's GPU resources plus the game's ~807 MB overcommit video memory.
  Gate doors measured that way: 61.0 fps, worst p99 25.76 ms (59.9 / 25.79
  before). Earlier "noise" between runs here may partly be this.- **Doors are kicked in** (`wood_door._kick`, debris `scripts/door_debris.gd`):
  E starts an uncancellable scene -- letterbox, `player.hands_busy` puts the
  sword/potion away, square up and step back (`WINDUP_DIST`, clamped by a ray),
  rush, the view dips to show a procedural leg (`_make_leg`, hinged at the hip
  on the BODY so pitching the view reveals it) driving out to the door, then
  0.3x slow motion + shake on impact, the leaves burst into pieces, and the
  pieces are watched until they settle (max 2.4 s). ~4 s in all; impact 0.86 s
  in. Tweens are `set_ignore_time_scale` so the slow motion only slows the
  world; `Engine.time_scale` is restored before control returns. `_open()` still
  exists for anything that wants a door simply swung open.
  Debris traps, both found by measuring where the pieces ended up:
  - **Clip triangles into chunks; do not sort them.** Tripo's leaves are big
    triangles, some the door's full height; sorted by centre, each "chunk"
    carried metre-long slivers and the burst was a fan of needles.
    `door_debris._clip` is Sutherland-Hodgman per grid cell.
  - **The collision box is the BOARD (8 cm), not the chunk's bounds**: those take
    in the iron bands and latch, 0.47 m deep, and every chunk stood up on end
    like a post (12-13 of 24 resting 1-2 m up). After: 30 of 30 on the floor.
  Pieces are on their own layer (13) colliding with floor, walls and each
  other, not with the player or enemies -- measured, the player walks straight
  through the rubble -- and freeze 6 s after the scene. 3x5 chunks a leaf with
  `Graphics.effects`, 2x2 and no dust without. Worst frame in the scene 24-31 ms.- **Kick tuning (2026-10-01)**: 2x3 pieces a leaf (12 a door; 1x3 without
  effects) -- a door splits into boards, it does not shatter. The scene no longer
  waits for the pieces to settle: leg down, view up and letterbox off together
  in `RETURN_TIME` 0.22 s after the slow motion, so control is back 0.58 s after
  the impact (scene 1.53 s, was ~4); the pieces finish falling in play.
  On impact `_shove` throws everything on the damageable layer (3) within
  `SHOVE_RADIUS` 3 m away from the door (`SHOVE_PUSH` 16, stun 0.6) and calls
  its `alert()` -- new on enemy.gd, the "noticed you" half of `take_damage`,
  which now uses it. Measured: an ordinary enemy behind the door thrown 4.4 m and
  hunting; one 6 m away untouched. Heavies (resistance 0.88) only stagger, by
  design. Trap: there is NO "enemies" group -- harnesses that "disabled the
  enemies" through it disabled nothing.- **Sword duck is smoothed** (`_update_sword`): one GOAL (rises at once to the
  least duck clearing `sword_duck_margin` 0.45 m and past any level that clips
  when drawn; comes down only after `sword_duck_hold` 0.25 s clear, at
  `sword_duck_out`), followed by a critically damped spring (`_smooth_damp`,
  0.045 s down out of view, 0.14 s back up; `SWORD_DUCK_URGENT` 0.02 s if the
  drawn sword would be in stone). Measured on 1,200 frames of wall approaches,
  slides and swings: direction reversals 22 -> 2, biggest one-frame jump
  0.90 -> 0.056, clipping 0 -> 0 (a plain spring with the 0.3 m margin clipped
  18 frames). Still fully up in an open corridor.
- **Doors break into 5 big pieces** (left leaf 1x2, right 1x3) that each crumble
  away 1-3 s later (`door_debris.crumble`): `shaders/debris_dissolve.gdshader`,
  the door's own textures eaten by noise with an ember rim, `dissolve` an
  INSTANCE uniform. Traps: the noise must be laid on the piece's OWN space with
  `repeat_enable` -- on the UVs (a texture atlas: a sliver per piece) or
  clamped, it read flat and every piece burned as one glowing slab. The first
  break stalled ~1 s (101 ms once Godot's shader cache had it): the dissolve and
  dust shaders compiling plus clipping the leaves in script. `warm_up` draws a
  speck of each and pre-cuts both leaves at `level_built`: worst frame in the
  scene now 33 ms. Kick faster: lands 0.55 s in (was 0.95), scene 1.03 s.
- Harness trap: bombers have no `alert()`; freezing only things with it left
  them running, and one blew up beside the invulnerable test player -- a bright
  disc mid-screen that looked like a rendering fault.- **The shockwave is gone** (2026-10-01): no right-mouse ability, no `shockwave`
  input action, no cooldown bar on the HUD, no ring mesh on the player. The
  slam (attack while airborne) and the dash are untouched. A copy of the old
  code survives only in work/checkpoints/2026-09-29-before-team-wave/.- **Ghost mode replaced the dash** (2026-10-01; `player._update_ghost`,
  `_ghost_lift`): HOLD "dodge" (Shift) to float `ghost_hover` 0.3 m up at
  `ghost_speed_scale` 2.5x walking with full steering, intangible to enemies
  (the old per-body phasing, window = `_ghosting`), taking `ghost_damage_taken`
  0.2 of hits instead of being immune. The bar drains over `ghost_duration` 4 s
  and refills over `ghost_refill` 5 s, starting the moment ghost ends; run dry,
  the key must be released before it starts again (`_ghost_locked`), or it
  flickers at the refill threshold. The dash's look is HELD while on:
  `_dash_view` pinned at 1 (and not decayed in `_process` while ghosting --
  decaying it there while physics re-set it made the FOV pulse), saturation 0,
  streaks, bank from the sideways part of the velocity. The dash's own
  damage/push, charges and invulnerability are gone; `is_dodging()`,
  `dodge_charge()`, `dodge_ready()` keep their names for the HUD.
  Measured: 10.63 m/s (walk 4.25), hover 0.30 m, bar 3.9 s / refill 5.0 s,
  a 50 hit takes 10, through an enemy that stops a walk dead.
- **The slam is on right click** ("slam" action) while airborne; left click in
  the air now swings. A dive paints its blast radius on the floor below
  (`SlamMarker`, additive ring shader, compiled at `_ready` by drawing it at
  zero strength); the impact flashes it, throws a dust ring, flashes firelight
  (those two only with `Graphics.effects`), shakes the camera hard
  (`_shake`, noise, squared decay over `slam_shake_time`) and drops the view
  into a crouch it rises out of over `slam_recover_time` 0.5 s, during which
  the player cannot move, jump, swing or ghost. Measured: movement back 0.57 s
  after impact (0.5 + acceleration), worst frame through dive and impact 22 ms.
- Harness traps: PROCESS_MODE_DISABLED takes a physics body OUT of the world
  (no collisions, no shape-query hits) -- keep a test enemy active and make the
  player invulnerable instead. And a screenshot stalls the next frame by up to
  a second; never time anything across one.
- **The sword is posed in code, not by clips** (2026-10-01). `player.gd`
  `_begin_pose` pauses the AnimationPlayer and `_update_pose` writes
  `Head/SwordPivot` from keyed poses (`_swing_pose`, `_slam_pose`), ending on the
  idle clip's frame 0 and handing back with `play(&"idle", 0.0)`. Poses are
  given as (hand position, blade direction, edge direction) in head space and
  solved against the blade's MEASURED axes (`_blade_frame`, from
  `_measure_sword`), so they survive a different sword asset. Left click
  alternates R->L (`slash`) and L->R (`chop`, the mirrored inputs -- mirror the
  inputs, not the transform, or the basis is improper). The `slash`/`chop` clips
  are now unused. The sword is 2.65 m from pivot to tip in this rig.
- **Hits are the blade's swept volume**: each physics tick in the cut window,
  hilt/tip last tick + now make a thin convex slab (`blade_hit_thickness`) that
  is queried on the hitbox mask, once per body per swing. It reads the DRAWN
  model, so a ducked sword does not cut through a wall. A body directly beside
  you at 2.6 m IS hit -- the wind-up passes through there; that is correct.
  Measured: behind 1.5 m and ahead 4.5 m never hit, everything the blade crosses
  hits once for exactly `attack_damage`.
- **The slam's strike is aimed in WORLD space every frame**: a head-space pose
  put the tip 0.1-0.3 m into the floor depending on crouch depth and pitch. Now
  0.03 m above the floor at any pitch. During it the duck ignores floor hits
  (`_ignores_floor`), or the sword ducked away from the ground it was striking.
- The tip trail is a camera-facing ribbon over the tip's recent positions on a
  GAME clock (`_trail_clock`), so slow motion does not shorten it. Its material
  must stay white; the old orange albedo multiplied the vertex colour.
- `hit_landed(target)` (sword and slam) drives the HUD's crosshair hit marker.
- **Enemy health bars** (`scripts/enemy_health_bar.gd`, one shared opaque
  billboard shader, values as instance uniforms): red snaps down, orange trail
  holds 0.45 s then drains, green on gain then red climbs. Attached from
  enemy/bomber/mimic `_ready`; hidden on a mimic until `awake`, on death, and
  past 28 m.
- Harness traps hit here: `await physics_frame` resumes BEFORE nodes' physics
  and parsed input flushes once per rendered frame, so "off within 2 physics
  frames of release" failed on timing, not on the game. And a floor ray on
  mask 1 lands on an enemy's head -- move it away before re-placing it, or it
  stacks on itself above the blade.
- Bench after (P620 3440x1440, Low): spawn 19.25, boss centre 17.71, boss edge
  22.58, outer 9.54, chest 22.03 ms; OVERALL 60.6 fps, worst p99 25.76 ms,
  809.5 MB.
- **The first remade swing did nothing in corridors** -- it was only ever tested
  in the boss court. The 2.65 m blade swept to 3 m either side of a 3.8 m
  corridor, the wall-duck hid the sword for 18-21 of every stroke's 24 frames,
  and hits read the hidden model: 0 damage. Three fixes, each measured:
  `_fit_swing` opens the arc only as far as the blade's whole path (wind-up,
  cut, recovery) stays `SWING_CLEAR` off the stone, from where the player
  stands AND from where the lunge will carry them (95 deg a side in the court,
  ~30 in a corridor); wind-up and recovery travel ROUND the arc (blending the
  orientations swung the tip 3 m up into the vault); and hits use the blade
  where the swing puts it (`sword_pivot * _sword_rest`), not the ducked model,
  with line of sight still checked (an enemy behind a side wall: 0 damage).
  Measured over 62 swings at 31 places in the level: 60 hit the enemy ahead;
  23 began with the sword already ducked by a wall within ~1 m (expected); of
  the other 39, 4 hid the sword for part of the stroke. Test swings in
  CORRIDORS, not only the open court.
- Harness trap (third time): a `--script` harness that fails to compile the
  game leaves the window open forever. An untyped `for side in [...]` value
  makes `:=` inference fail -- type it.
- **SUPERSEDED (2026-10-01, at the user's request): the sword no longer reacts
  to walls at all.** The wall duck (`_sword_clearance`, `_sword_clear_at`, the
  goal/hold/margin spring, `_sword_points`) and the swing-arc fitting
  (`_fit_swing`) are gone; every stroke uses the full `SWING_OPEN` arc. The
  sword is instead DRAWN IN FRONT of everything: `_draw_sword_on_top` gives each
  surface a material copy with `use_z_clip_scale` (`sword_draw_depth` 0.12),
  Godot 4.5+'s viewmodel option -- same size on screen, depth compressed toward
  the camera, no extra pass or viewport. Keep the scale above ~0.08: the
  nearest sword points are ~0.6 m from the eye and the camera's near plane is
  0.05. The only duck left is putting it away (another item in hand, or
  `hands_busy`). Hits still use the swung blade with the line-of-sight check,
  so nothing is cut through stone. Measured: 0.40 m from a door, idle and
  mid-swing, duck 0.00 and the sword drawn over the door; corridor strokes both
  land; bench 60.2 fps / worst p99 25.79 ms (60.6 / 25.76 before), 809 MB.
  The "Sword out of view" / "TIP stays out of walls" / "Sword duck is smoothed"
  notes above describe the removed system.
- **Bombers are struck with the haft, not cut** (2026-10-03). Swords and the
  slam pass through them (`player._resolve_hits` and the slam skip anything with
  `swat()`; `bomber.take_damage` is a no-op; no health bar). Within
  `swat_reach` 2.6 m of the eyes, with line of sight, a bomber shows
  "E   Strike"; E calls `player.haft_strike(bomber)` -> pose `haft` (0.32 s,
  contact at 0.11): the sword is drawn whatever is held, REVERSED -- blade back
  over the right shoulder, away from the target -- and placed by its POMMEL
  (`_blade_pommel`, the mesh's lowest vertex; `_pommel_at`), driven 1 m out
  along the line to the bomber. Placing it by the pivot missed: the pivot is not
  the pommel. On contact `bomber.swat(dir)` puts the fuse out, knocks it away
  (clamped by a ray so it never flies through stone), spins and pops it; no
  blast, `died` still emitted. Works on a lit bomber riding the player. Measured
  in a harness: 16/16 -- both strokes and the slam leave a bomber untouched with
  no hit marker, prompt at 1.8 m not 4.5, struck and gone with no damage, lit one
  never goes off, the potion comes back after. On screen the pommel lands on the
  bomber's column (x within 1 px); the hit's view punch lifts the view ~90 px.
- **A haft-struck bomber SHATTERS** (`bomber._shatter`), replacing the
  knock-away. Its sphere is cut once per mesh (`_pieces`, static cache) into 10
  chunks -- each triangle to the nearest of 10 directions, each group closed
  into a solid with an inner face at `SHARD_DEPTH` 0.55 and walls on its open
  edges -- that burst out the way it was struck plus outward, tumble, bounce
  off stone (a ray per piece per frame; mask 2), cool white -> orange and
  shrink away by 0.9 s. Measured: 10 pieces, 0 ended through the wall or under
  the floor, all freed. **The first shatter cost a 79 ms frame**: the
  double-sided variant of the bomber material compiling on first draw.
  `_warm_up` (first bomber, deferred from `_ready`) pre-cuts the pieces and
  draws one speck of a piece in that material in front of the camera: worst
  frame then 26.9 ms.
- **Heavy attack is Ctrl + right click** (2026-10-03); a plain right click does
  nothing. The "slam" action still binds the right button alone -- an action
  matches a mouse button whatever modifiers are held -- so `ctrl_pressed` is
  checked on the event (either Ctrl key). In the air it dives as before; on the
  ground (`_slam_grounded`) the player is planted, the sword goes overhead
  (pose `raise`) and after `slam_ground_windup` 0.22 s -- on the raise's own
  GAME-time clock, so slow motion slows it too -- `_land_slam` brings it down
  onto the floor with the full blast. `slam_recover_time` is 1.0 s (was 0.5):
  that long locked down, crouched and rising. Measured: no rise at all on the
  ground, impact 0.22 s after the click, blast hit an enemy 2.2 m away, 0.000 m
  of movement for the first 0.85 s with forward held, 0.95 m by 1.35 s.
  Harness trap: the slam (150) kills a 100-health test enemy -- check
  `is_instance_valid` before moving it again, or the script errors and the
  window stays open forever.
- **No interact text in the world any more** (2026-10-03). `Interact.prompt()`
  returns an invisible `Interact.Prompt` (Node3D with `text`, group
  `interact_prompt`); callers still set `visible`/`text` as before. The HUD turns
  the crosshair into a ring with four corner brackets while `Interact.focus()`
  finds one up: gold for open, orange-red for "Strike" (bombers), grey for
  "Full". Wooden doors test reach HORIZONTALLY, so a door's cursor is up at any
  height above it -- a harness that floats the player away to clear prompts does
  not clear that one. The player spawns 2.2 m from a door, so the cursor is
  legitimately up at spawn.
- **Thrust** (Ctrl + left click, sword): pose `thrust` -- hilt drawn to the hip
  (`THRUST_DRAWN`), driven out (`THRUST_STRUCK`) with the blade aimed at
  `THRUST_AIM` just under the crosshair. 40 damage (cut 32). NO cooldown (it had
  one, 3/4 of the slam's, removed at the user's request 2026-10-03, with its HUD
  bar); its cost is that it is SLOWER than a cut: bites 0.18-0.40 s, ends 0.66
  (slash: 0.07-0.27, ends 0.42), so spammed it is ~100 dps against the cut's ~118. The swing's swept slab is a LINE for a stab
  (the blade moves along itself), so the thrust's hit volume is a box of
  `thrust_hit_radius` round the blade. `_stroke_damage` carries the stroke's
  damage. Measured:
  40 dealt, 0 sword vertices cut by the near plane inside the view.
- **Haft-strike camera**: on E the view (HEAD yaw/pitch only, never the body or
  `_look_pitch`) turns `haft_aim_share` of the way onto the bomber (capped
  `haft_aim_max`), and the jab is re-aimed every frame up to contact
  (`_aim_haft`) because the head is moving. On contact: `Engine.time_scale`
  0.18 held 0.16 s then eased back over 0.45 s (tween ignores time scale and
  runs through pause; skipped if something else already slowed time), FOV -14
  deg and 5 deg dutch tilt, all settling on the WALL clock (`_update_cine`).
  `_respawn` calls `_end_slowmo`. Measured: contact 0.12 s, x0.18, fov -16.9,
  turn 12 deg, everything exactly restored by 1.0-1.4 s, aim untouched.
- **Inventory hover + descriptions**: hovered slot lights (`ItemSlot.hovered`),
  and a 300 px panel right of the slots shows icon, name, kind
  (`Inventory.ITEMS[...]["kind"]`), `desc`, and live numbers read off the player
  (`inventory_screen._stats_for`). The engine tooltip is gone.
- Harness traps: a screenshot stalls ~1 s, so a "wait 500 ms" loop can exit
  before a pose has advanced past the frame it shot -- loop on the STATE, not
  the clock.
- **Crosshair is a white ring and dot** (2026-10-03): the scene's four cross
  ticks are hidden; `hud.gd` draws the ring (`crosshair_radius` 9) round the
  scene's dot, and while a prompt is up four white corner brackets close in
  round it. No colour coding any more (the gold/orange/grey interact tints were
  removed at the user's request: every crosshair is white). Hit-marker ticks
  start at 12 px, outside the ring.
- **Doors kick only when AIMED at** (`wood_door._aimed_at`): within `reach`
  horizontally AND the view ray crosses the blocker box's plane inside its
  rectangle within `AIM_RANGE` 3.6 m. Geometric, not a ray cast, so the jambs
  and moulding cannot catch it and it works before the blocker is armed.
  Measured: usable looking at it from 1.8 m; not usable turned 90/180 deg,
  looking at the ceiling or floor, or from 3.3 m; E only kicks when aimed.
- **Everything needs the crosshair ON it** (2026-10-03): chests, the mimic,
  bone cages and bombers as well as doors. `Interact.looked_at(node, reach,
  margin, parts)` casts the view ray against the box round the node's VISIBLE
  meshes (measured once, cached as meta `aim_box`, in the node's own space so
  it moves with it). The mimic passes `[$Body, $LidPivot]`: its LandingMarker
  and ImpactRing are effect meshes that made its box 8.9 m wide. A LIT bomber
  (`fusing`, latched on the shoulders) is exempt, or it could never be struck.
  Measured: each usable aimed at, not usable turned 100 deg or looking over it.
  Harness trap: a bomber placed within `trigger_range` of the player lights and
  latches, and then counts as exempt -- use a fresh one for the negative test.
- **Bone cage scene: the skull is stabbed first** (`bone_cage._stab_skull`):
  after the door swings, `player.stab_at(world_point)` -- pose `stab`, the sword
  drawn whatever is held, hauled back by the shoulder (`STAB_COCKED`), driven in
  on a cubic ease (contact 0.30 s), held with a quarter twist, withdrawn by
  0.95 s; `stab_landed` fires on contact with a hit-stop (`_slowmo(0.08, 0.1,
  0.3)`, the haft's slow motion now generalised), shake and punch. The skull
  then breaks into 12 chunks (`_skull_pieces`: recentred on its AABB, cut with
  the bomber's static `_solid_piece`), a red flash and bone dust, and the loot
  flies `AFTER_STAB` 0.45 real s later. First break stalled 58 ms (cutting in
  script + the double-sided material compiling); `_warm_up` pre-cuts and draws a
  speck at load: 31 ms (the scene's normal frame). Stab lands 1.3 s after E.
- **Inventory screen rebuilt after a reference the user supplied** (dark
  souls-like): header with a crest and spaced serif title (SystemFont: Palatino
  Linotype -> Book Antiqua -> Georgia -> Times), three framed panels with gold
  corner brackets -- the bag (5 x 6, so `Inventory.BAG` is now 30) with
  category tabs (All / Weapons / Consumables / Treasure; Q / E or click; other
  kinds DIM in place rather than reflowing, so drag positions hold), an item
  card (name, kind, big icon on a faint seal, description, two stat columns from
  `_stats_for`, an italic `quote` from ITEMS), and a character panel (a drawn
  silhouette, the item in hand, the hotbar as "Quick Items", coins, potions and
  health / ghost / slam bars) -- then a key strip. The reference's other tabs
  (Equipment, Stats, Journal) are NOT shown: those screens do not exist. It is
  laid out for the 1280 x 720 stretch canvas; the backdrop is 0.95 opaque
  because at 0.86 the HUD showed through. E is swallowed while it is open.
  `ItemIcon.paint(canvas, id, rect, tint)` draws an icon onto anything;
  `ItemSlot.make_ornate(size, font)` gives the screen's slot look (the HUD
  hotbar keeps the plain one).
- **The player starts shut in** (2026-10-03): `module_level._pick_spawn` takes
  the DEAD END furthest from the boss whose one exit opens onto a corridor
  (falling back to the old furthest-through-corridor rule, `_furthest_corridor`,
  which also leaves every cell's walking depth as meta "spawn_depth").
  `Built.spawn_door` records it and `place_doors` ALWAYS hangs a door across
  that exit, in the dead end itself, so the gate's front (+Z, the iron side)
  faces the player. `maze._place_player` stands the player at the exact spawn
  (not snapped to the 1.2 m tile grid -- snapped, the door was 2.58 m away and
  out of its 2.4 m reach) facing it (`Built.spawn_yaw`), on respawn too.
  `SPAWN_BACK` 0.7 + the dead end's 1.38 m door depth = door 2.08 m ahead.
  This deliberately overrides the older "never spawn in a dead end" note.
- **Cage skulls drain** (`bone_cage`, group "Stare"): the skull wakes for anyone
  in front of its cage within `watch_reach` 3.4 m (no aim needed; using the cage
  still needs the crosshair), and once fully turned on them drains
  `drain_per_second` 2.5 through `player.drain_health(amount, floor)` -- not a
  hit: no invulnerability window, marker or knockback, nothing in a cutscene,
  and never below `drain_floor` 25% of max health. Eyes pulse while it drains.
  Measured: 7.5 in 3 s, stops at 25.00, nothing out of reach.
- **The rally is gone**: hitting no longer wins health back. Exports, the bank,
  `rally_from_damage` and `_drain_rally` removed; the HUD's yellow RallyBar is
  kept in the scene but hidden.
- **Item drops** (`scripts/item_drop.gd`; `spawn(parent, at, id, count)`):
  skeletons (enemy.gd, the boss too) roll `drop_rolls_min..max` (1-2) times on
  death over `drop_odds` (bone_fragment 0.6, health_potion 0.3, skeleton_skull
  0.05, nothing the rest); measured over 20,000 rolls within 1%. The old
  straight-into-the-inventory potion drop (`drop_chance`/`drop_table`, and the
  boss's `drop_chance = 1.0` override) is gone. A drop pops up and out, falls
  with a ray per frame on mask 2, bounces, settles lying ON the floor (5 mm,
  re-measured after it lies down) with an additive glint that proximity-fades
  into the floor (without that the halo was cut by a hard line). E with the
  crosshair on it (`Interact.looked_at`, margin 0.22) flies it to the player
  like the cage loot -- curve, trail, out the bottom of the view -- and
  `player.add_item` adds it on arrival (consumables and coins through their own
  paths; others emit `item_gained`, toasted by the HUD). `Inventory.room_for`
  is checked first: no room shows "Full" and it stays. Visuals: the potion and
  cage skull models, sized down; a bone is built from primitives.
  New items `bone_fragment` (Material) and `skeleton_skull` (Trophy) with
  icons, and a fifth inventory tab, Materials. Kinds in `Inventory.BAG_FIRST`
  go to the bag before the hotbar, so loot does not take the number keys.
- **Drain wisps** (`bone_cage._update_wisps`): while a skull is actually taking
  health (not once `drain_floor` stops it) black smoke wisps leave it every
  ~0.11 s (max 10), snake to the player's chest on a wavering curve (pinned at
  both ends) over 0.8-1.25 s and their tails run in after them. One
  camera-facing ImmediateMesh per cage, two surfaces: alpha-blended near-black
  smoke soft across its width (gradient texture on V), and an additive dull-red
  core thread at a third of the width -- pure black alone read as nothing more
  than faint bands on the dark stone; with the wobble at 0.12-0.3 m they also
  overlapped the skull, since they travel almost straight at the camera, so it
  is 0.25-0.5 m. Materials are passed per surface to `surface_begin`
  (`material_override` would cover both).
- **ImmediateMesh trap**: `surface_begin` followed by no vertices (every
  segment of a trail degenerate) errors "No vertices were added" and leaves the
  mesh stuck mid-surface, so the next `surface_begin` errors too. Every ribbon
  here (wisps, cage loot trails, item-drop trails) now gathers its vertices
  first and only begins a surface when there are some.

## 7. The boss hall (2026-10-06)

The boss room is no longer the 7x7 cloister on the corridors' level. It is a
grand stair from ONE doorway up to a throne hall above the corridor roofs.

- **One doorway** (`module_maze._one_boss_entrance`, after `_finalise_rooms`):
  the entrance with the most maze behind it is kept, the rest walled up; any
  part of the maze that was only reachable THROUGH the room gets a corridor dug
  round it (`_dig_round`, BFS that never enters a room) or, if it is a 1-2 cell
  stub, is dropped. The whole block is then `court`, so no arcade modules,
  collision, torches or doors are built in it -- every placer already skips
  court cells. Reachability still 100%.
- **The plan** (`module_level.plan_boss_hall`, BEFORE skylights are picked):
  everything in the stair's frame (u across, v in from the doorway, y up).
  Stair 8 m wide, 2 x 18 steps of 0.194 on 0.42 m with a 3 m landing, to
  `HALL_FLOOR_Y` 7.0 (corridor roofs 5.1). The hall is the largest of
  40x48 .. 26x30 that stays inside the map and off every chest room's COURT
  (+2 m); chest ARCADES are roofed, so it may stand over them. Skylights are
  never picked under it (`under_boss_hall`). First version kept clear of the
  whole chest BLOCK +1.5 cells and found no room anywhere (fell back to 26x30).
- **The build** (`scripts/boss_hall.gd`, from maze `_build_module_level` under
  NavRegion so the navmesh bakes it): stair walls and facade, solid steps,
  RAMPS under them half a tread back from the noses (the capsule cannot climb
  19 cm steps; the navmesh needs a slope), a 1.4 m floor slab, 14 m walls with
  an 8 m arch, columns, a dais with ramp, placeholder throne, carpet, banners,
  braziers (a torch.tscn with the bracket hidden and the fire scaled up) and
  torches. Open to the sky; its sky lights are `HALL_SKY_ENERGY` 10 -- the
  courts' 22 blew the carpet and paving out to flat scarlet.
  Collision: floor/stairs/dais 1+2, walls/columns 2+9+10, throne 9 ONLY (the
  player cannot walk into it, the boss can sit in it), boss wall 11 across the
  arch inside the hall.
- **Gameplay**: `maze._boss_hall_gate` puts one portcullis (8 x 8 m, 15 bars)
  in the arch as `_gates[0]`; `_boss_court_gates` is only used without a hall.
  The boss spawns at `boss_spot` on the dais facing the doorway; his zone is the
  hall interior via the new `enemy.aggro_box_origin` (null = spawn point) and
  a non-zero `aggro_box_extents.y` now also limits height -- without it a
  player in a corridor UNDER the hall was "inside" the zone. `boss_throne_seat()`
  returns the "ThroneSeat" marker (-Z toward the doorway) for the boss work.
  `_close_boss_block_grid` marks the block's tiles WALL except the stair.
  The four old boss rock columns are not built with a hall.
- **Tripo**: the placeholders ("Throne", "Dais", "Columns", "Braziers",
  "Banners") are meant to be replaced by generated models; the API account had
  no credit (the web studio's 200 credits are a separate wallet). Swapping a
  mesh must not move the collision, the ramps, the seat or the boss spot.
- Measured in a harness: one doorway; walked up the stair on the real controls
  into the hall in 6.5 s (y 7.00); boss asleep with the player in a corridor
  under the hall, awake and the portcullis down once in it; nav path throne ->
  entrance ends 0.30 m from the goal. Bench (RTX 3060, 3440x1440, preset 1,
  scale 1.0, SSAO/glow on): spawn 7.32 ms, boss centre 8.72 (p99 11.11), boss
  edge 9.22, outer 3.38, chest 8.61; OVERALL 154.4 fps, 1176 MB. (Not
  comparable with the P620/Low figures above.)
- `tools/tripo.ps1` now reads the User-scope key FIRST: after `setx`, every
  running process still had the old key in its environment and kept billing
  the old account.

## 8. Block and parry; the thrust's lunge (2026-10-06)

- **Block = hold right click** (no Ctrl; Ctrl + right click is still the slam).
  The "slam" action's press starts it, its release (or `_check_block` finding
  the button up, the sword not in hand, a ghost, a cutscene...) ends it. Pose
  `block` (`_guard_pose`: hand at `GUARD_HAND`, blade up across the view to the
  upper left, flat to the front, up in `GUARD_UP` 0.1 s), `unblock` back to rest
  in `GUARD_DOWN`. Walking at `block_move_scale` 0.55; no cuts or thrusts while
  up. It can be raised out of a cut's recovery, never mid-stroke.
- **`take_damage(amount, blow, attacker = null)`** -> `_guard(blow)`: only blows
  from within `block_arc` 75 deg of the front count. Within `parry_window` 0.5 s
  of the guard going up: PARRY -- `parry_damage_taken` 0.25, the attacker gets
  `apply_knockback(away * parry_push 14, parry_stun 0.9)` (enemies keep that in
  `_knockback`, not `velocity`), a hit-stop `_slowmo(0.15, 0.09, 0.22)` and the
  purple `_guard_flash`. After the window: BLOCK -- `block_damage_taken` 0.5 and
  a small warm flash. Signal `guarded(parried, attacker)`. enemy.gd (skeletons,
  the boss) and mimic.gd now pass themselves as the attacker; bomb blasts pass
  none (blockable, nothing to throw back).
- `_guard_flash`: additive billboard ring + core (no depth test, so it shows over
  the guard), and with `Graphics.effects` CPU sparks and a short light. Played
  on the REAL clock so the hit-stop does not drag it. `_warm_guard_flash` draws a
  speck of each material 0.4 s after `_ready`.
- Harness trap (again): a screenshot's ~1 s stall lands in the NEXT frame's
  delta, and anything on the real clock (this flash, ignore-time-scale tweens)
  jumps straight to its end -- the first parry screenshot showed no flash at
  all. Shoot such effects before any other screenshot, or after one, wait.
- **Thrust**: `thrust_lunge` 5.5 -> 9.5 and given at `THRUST_DRAW` as the blade
  is driven (it used to be given at the start of the draw, where the damping
  bled it off before the blade moved); timeline DRAW 0.28 / HIT 0.40 / HOLD 0.52
  / END 0.95, and `_bite_end` is THRUST_END -- a thrust cannot be cut short to
  chain another. Measured: 1.26 m forward from standing.
- Measured in a harness: no guard 40 of 40; parry 10 of 40, attacker thrown at
  14 m/s, time scale 0.15 then back to 1, flash freed; block after the window
  20; from behind 40; left click does nothing while up; release -> unblock ->
  idle; a real skeleton's own blow on a held guard: 7 of its 14, credited to it.

## 9. Cage walk-up, slow drinking, no hand torch, new keys (2026-10-06)

- **Keys**: ghost mode ("dodge") is LEFT CTRL (physical KEY_CTRL, location
  left) in project.godot; the thrust is SHIFT + left click and the slam SHIFT +
  right click (`shift_pressed` read off the event, as Ctrl was); plain right
  click is still the block. Ctrl + left click is now just a cut. No cut,
  thrust, slam or block while ghosting.
- **Ghost entry cost**: `ghost_entry_cost` 0.1 of the bar is taken the moment a
  ghost starts, then it drains as before, so tapping it is not free speed.
  Measured: 1.00 -> 0.883 on entry; five quick taps -> 0.458.
- **Drinking** (`use_consumable`): a drink takes `drink_time` 3.0 s. The flask
  is used up as it starts, the heal lands at the end (`_update_drink`, game
  clock), and meanwhile the player walks at `drink_move_scale` 0.25 and cannot
  attack, block, slam, ghost or haft-strike; the sword is put away and the
  flask held to the lips (`held_potion.drink(duration)`: up in 0.35 s, sipping,
  down at the end). HUD: "Drinking" countdown bar above the hotbar
  (`hud._build_drink_bar`, `player.drink_remaining()`). Death cancels it.
  Measured: 3.02 s; 1 s of walking 3.64 m plain vs 1.05 m drinking.
  Harness trap: the first walk test ran into the spawn's door and "passed" at
  0.04 m -- measure movement on open floor, against a plain walk.
- **The hand torch is gone** (`Head/TorchHand` and its six resources removed
  from player.tscn). It was the only shadow-casting light in the game, so the
  "torch shadows" setting now has nothing to act on, and corridors are lit by
  the wall torches alone.
- **Cage scene walks the player over** (`bone_cage._play`):
  `begin_cutscene(true)` -- a scene in the world, so blows still land
  (`take_damage` checks `_cutscene_hurts`) -- then `player.scene_walk_to(spot)`
  (`STAND_OFF` 1.3 m out from the cage, walking pace, turning to face the way,
  ends on arrival / timeout / no headway, signal `scene_walk_finished`), a short
  turn to square up, door, stab, loot, level the view, control back facing the
  cage. Dying partway (`_still_going`) drops the scene and leaves the cage to
  try again; `_die` ends a scene walk and `_respawn` clears `in_cutscene`.
  Measured: walked from 2 m off to one side, struck from 0.10 m off the spot,
  a 10-point blow landed mid-scene, paid; death mid-scene -> cage not busy,
  not looted, player back in control.
- **Keys again (2026-10-07)**: ghost ("dodge") is SPACE (held), jump is F,
  drinking ("heal") is R, the map ("toggle_map") is TAB. Thrust / slam stay
  Shift + left / right click; block is right click. The map toggles in
  `_input` (before the GUI) and marks Tab handled, so it does not also move
  focus between controls. Verified by pressing the real keys in a harness.
- **And again (2026-10-07)**: ghost ("dodge") is RIGHT MOUSE (held), block is a
  new "block" action on SPACE (held; parry = Space just before the blow). Shift
  + right click is still the slam: right click with Shift down never STARTS a
  ghost. `_action_held(action)` asks the keyboard and mouse directly (keys and
  mouse buttons) instead of the latched action state; `_dodge_held` and
  `_check_block` use it. Jump F, drink R, map Tab, thrust Shift + left click.


## 8. Respawn anchors (2026-10-07)

- **Anchors** (`scripts/respawn_anchor.gd`, placed by `maze._place_anchors`):
  plinth, four-sided obelisk with a carved rune line, floating crystal. E with
  the crosshair on it (`Interact.looked_at`, 2.4 m horizontal reach) attunes
  it; `maze._on_anchor_attuned` darkens every other one, so exactly one is
  active, and it stays active until another is attuned. Only the active one
  carries a light (teal omni, distance-faded). `anchor_count` 5, in DEAD ENDS
  (alcoves never block a corridor): one is always the dead end nearest the
  boss by walking depth (`spawn_depth` meta), the rest greedy farthest-point
  from the start and each other. Excluded: the spawn dead end, door cells,
  rooms, courts, anything under the boss hall. The obelisk stands
  `ANCHOR_BACK` 1.2 m back from the cell centre; the player rises 1.6 m in
  front of it facing out (`spawn_point`, `spawn_yaw`). Collision layers 1+2,
  built before the navmesh bake; its grid tiles are marked WALL so nothing
  spawns in the plinth.
- **Respawn**: `_place_player` uses the active anchor when there is one (the
  start, behind its door, otherwise).
- **Death penalty**: `_map_snapshot` is `ExploreMap.snapshot()` taken at level
  start and again on every attune; `_on_player_respawned` calls
  `restore()`, so everything charted since the checkpoint is forgotten.
- **Bars rise on death**: `_populate` now clears `_boss_committed` and
  `_mimic_committed`. Before, it unsealed the gates and the next `_process`
  re-sealed them at once round the fresh, unengaged champion, so after dying
  in a boss or mimic fight the room could never be entered again.
- `module_level.gd` / `module_maze.gd` have NO class_name: maze.gd and the
  anchor `load()` them. Naming `ModuleMaze` in maze.gd is a parse error.
- Measured in a harness: 5 placed, every rise point on floor, nav-reachable
  from the start, 8 rays from each plinth clear of stone; E while looking away
  does nothing; attune A -> active; 2 new cells charted, die -> rose 0.18 m
  from A's point, 0 of 2 new cells kept, 3 of 3 old kept; attune B -> A dark,
  1 active, rose at B; boss engaged -> sealed, after death up (and still up
  30 frames later); same for the mimic's 5 gates; control (commitment kept)
  re-seals.
- **Keys (2026-10-07, third pass)**: swing LMB; block/parry hold RIGHT CLICK
  ("block"); ghost ("dodge") hold SHIFT; slam F ("slam", a dive in the air,
  the overhead blow on the ground); thrust Q (new "thrust" action); jump
  SPACE; drink R; map Tab; interact E; inventory C. No Shift/Ctrl + click
  combos remain, so the ghost no longer has to refuse to start with Shift down.
  Verified by pressing the real keys in a harness (14/14). Trap: an air dive
  from a low jump lands within 3 frames, so check that it STARTED
  (`_slam_started_at`, `_slam_grounded`), not that `_slamming` is still on.
## 10. Cage stab, scene camera, slash through the crosshair (2026-10-07)

- **The sword is 2.08 m from guard to tip** (`player.blade_length()`), and the
  old stab stood the player 1.69 m from the skull: the blade ran dead through
  its centre but the TIP ended 1.54 m beyond it, inside the stone, and drawn on
  top of everything it simply covered the skull. Now `stab_at(target,
  through)` solves the hilt along the line from `STAB_SHOULDER` so the tip ends
  `through` (0.14) past the target, and the cage stands the player off by
  blade length + `STAB_REACH` 0.9 - 0.14 (`bone_cage._stab_stand`, clamped by
  a ray to the far wall). During the stab the sword's `z_clip_scale` goes to
  1.0 -- real depth, so the skull hides the buried tip -- and back to
  `sword_draw_depth` as it comes out (only the uniform changes; toggling
  `use_z_clip_scale` would compile a shader variant mid-scene). Measured: tip
  0.140 m past the centre, 0.000 m off line, eye 2.77 m from the skull.
- Stab timeline: cocked 0.30, held quivering to 0.40, driven in by 0.47
  (`stab_landed`: hit-stop, the skull pinned and shuddering, eyes x4), wrenched
  round by 0.66 (`stab_wrenched`: the skull bursts), out by 1.2.
- **Scene camera** (`player.scene_look_at(point, rate)`, `scene_frame(zoom_deg,
  roll_deg, rate)`): holds the view on a world point through the whole scene,
  walking included (`_scene_walk` no longer turns to the walk direction while a
  look is set), and pushes the FOV in / tilts the horizon, eased on the REAL
  clock. Cleared by `end_cutscene` and `_respawn`. The cage scene: letterbox
  (`wood_door.letterbox()` / `letterbox_out()`, now static), view on the skull
  (worst 3.7 deg off it after the first 0.9 s), push in 4 -> 9 -> 14 deg with a
  -3 deg tilt on the draw, 18 / +4 at impact, out as the coins fly.
- **The slash passes through the crosshair** (`_cut_pitch`): the blade is
  pitched so its line, from the guard's real place on the model, runs through
  the point `SWING_CROSS` 2.0 m down the view, on a high-to-low diagonal of
  `SWING_TILT` 0.42 rad that is zero exactly where the blade heads at that
  point. Measured on the pose function at 1 ms steps (rendered frames skip it:
  the cut sweeps ~0.4 rad a frame): 4.4 / 3.8 px from the centre; the old arc
  (pitch 0.1 -> -0.32) 124 / 121 px. Hits on a skeleton 1.2-2.4 m ahead, level
  and looking down: 15 of 16 (the miss: a level slash at 2.4 m, the tip's edge).- **Slash damage 32 -> 24** (`attack_damage`; the thrust stays 40). Measured: 24
  dealt to a skeleton 1.6 m ahead.
- **The white slash trail runs through the crosshair** (`_update_sweep_trail`).
  It traced the TIP, which passes 72-74 px off the crosshair (the blade crosses
  the view axis well short of its tip). It now traces `_trail_point()`: the
  point on the blade that actually crosses the axis, found once by running a cut
  through the pose function a millisecond at a time (a fixed distance worked
  out from `SWING_CROSS` passed 4 cm high: 16 px -- the cut crosses nearer,
  ~1.74 m). Samples are taken from `_swing_pose` every `TRAIL_STEP` 4 ms between
  frames (straight chords between frames cut inside the arc), and kept in the
  HEAD's frame like the sword: in world space the view kick and lunge carried the
  camera on after the blade had passed, and the streak sat 69-158 px off the
  crosshair, stair-stepped at each frame's join. Measured: 0.4 px on both
  strokes, level and looking down, on every frame while the crossing is on
  screen. The ribbon now gathers its vertices before `surface_begin`.- **Damage: cut 20, thrust 50** (`attack_damage`, `thrust_damage`; measured).
- **The thrust plants the player for a second** (`_thrust_planted()`): the
  hilt is drawn back over `THRUST_PULL` 0.3 s and held, coiled, to
  `THRUST_DRAW` 1.0 s; meanwhile ground movement decays to zero as in the slam
  recovery and jump is refused. Then the drive and the lunge: timeline HIT 1.12
  / HOLD 1.24 / END 1.67, `thrust_lunge` 9.5 -> 15. Measured with forward held:
  4.18 m/s walking before, 0.00 m/s from 0.25 s to the drive (0.28 m of drift
  while stopping), no jump; lunge 3.22 m from standing (was 1.26).- **Thrust wind-up is half a second** (2026-10-07): `THRUST_PULL` 0.22, `THRUST_DRAW`
  0.5, HIT 0.62, HOLD 0.74, END 1.17. Still planted (measured 0.00 m/s with
  forward held), drive at 0.517 s.
- **Lunge speed lines** (`shaders/lunge_lines.gdshader`, the HUD's `LungeLines`
  ColorRect built in code by `hud._build_lunge_lines`): white dashes racing
  outward along angular lanes, the middle kept clear for the crosshair, and a
  soft white rim; driven by `player.lunge_intensity()` (in over 60 ms, out over
  `lunge_effect_time` 0.45 s from the drive, GAME clock via `lunge_age()`), with
  the view opening out by `lunge_fov_kick` 7 deg (measured +5.9 peak). Gated on
  `Graphics.effects` and hidden at rest. The first lunge cost a 28.8 ms frame
  (the canvas shader compiling on first draw); the HUD now draws it once at
  strength 0 for 0.3 s at load: first lunge 17.9 ms, second 17.5, idle 17.1.- **Block 10%, parry 0% and half back** (2026-10-07): `block_damage_taken` 0.1,
  `parry_damage_taken` 0.0, and a parry now calls the attacker's
  `take_damage(blow * parry_reflect)` (0.5 of the blow it threw, AFTER the
  knockback so a killing blow does not shove a corpse) and emits `hit_landed`
  for the crosshair marker. A blow reduced to nothing returns before the damage
  marker. Measured: unguarded 40 -> 40; parry 40 -> 0 taken, attacker -20;
  block 40 -> 4; from behind while blocking 40; a real skeleton's 14-point blow
  parried: player untouched, skeleton -7. Harness trap: `_start_block()` alone
  does not hold a guard -- `_check_block` drops it next tick unless the button
  is really down; press the real right mouse button (`parse_input_event`).
## 11. The Shade and the hiding places (2026-10-08)

- **The Shade** (`scripts/stalker.gd`, built in code, spawned by
  `maze._spawn_stalker` in `_populate` so a death resets it >= `stalker_min_distance`
  50 m from the player; group "stalker"). The skeleton model at 1.75x (~3.3 m)
  with `shaders/ghost.gdshader` (unshaded, translucent, both sides drawn, fresnel
  rim, upward wisps, a ragged fade at the bottom; instance uniforms `base_y`,
  `anger`, `flash`) plus a fluttering open-cylinder shroud, a glow on the head
  bone and (with `Graphics.effects`) a cold distance-faded omni. Moves by hand
  along the navmesh with `collision_mask = 0` -- nothing stops it, doors
  included -- floating `hover` over the path's height; layers 1+3, so it blocks
  the player and is hit by the sword and slam.
  States WANDER/PAUSE (corridor tiles from `_spawn_candidates`, 12-45 m hops),
  HUNT, SEARCH, WINDUP/STRIKE/RECOVER. Sees 26 m in a 140 deg cone, 4.5 m all
  round, with line of sight on layer 2. Hunting it always knows where the player
  is and follows at `hunt_speed_ratio` 1.07 x their `move_speed` (measured
  4.55 vs 4.25 m/s) until they hide; then it goes to where it lost them, searches
  `search_time` 7 s after arriving and goes back to wandering. Struck or kicked
  (`alert`) it hunts. Strike: within 3 m, 0.8 s wind-up, 55 damage + throw,
  UNBLOCKABLE (`player.take_damage` skips the guard for an attacker with
  `unblockable`). No knockback. `max_health` 5000 x `damage_taken_scale` 0.2: a
  20-point cut does 4 -- meant to be killed LATER; those two are the knobs.
  `death_drops` / `death_coins` are a PLACEHOLDER reward (a skull, 150 coins).
- **Hiding places** (`scripts/hiding_spot.gd`, `maze._place_hiding_spots`, 18,
  farthest-point spread over the free side walls of corridor straights -- not
  niche walls, torch walls, door cells, the spawn or under the boss hall), built
  before the bake (layers 1+2, grid tiles WALL). A louvred wardrobe in the door
  wood (`HIDE_FROM_CENTRE` 1.40 from a straight's centre). E aimed at it: walk
  up, doors open, `player.hide_in()`; E again: `leave_hiding()` in front.
  Hidden (`player.is_hidden()`): body collision off, held still, hands empty,
  look clamped to +-0.95 rad yaw / +-0.6 pitch out of the doors, `take_damage`
  and `drain_health` ignored, unseen by the Shade, `enemy._can_see` and
  `Interact.looked_at` (so no other prompt fires from inside). The door leaves
  are hidden while occupied; the HUD's `HideSlats` overlay is the doors.
- **The warning** (`shaders/dread.gdshader`, `hud._update_dread`, NOT gated on
  effects -- it is gameplay): frost in a band at the screen's BORDER (a circle
  from the centre swallowed an ultrawide's sides first), thicker from 34 m to
  7 m, deeper toward the Shade's bearing, pulsing on a heartbeat (52 -> 150 bpm,
  +20 hunted); hunted, the very edge darkens and "IT HUNTS YOU" shows. Trap:
  `fract(sin(dot(...)))` hashing loses precision on the GPU and read as squares;
  it uses Dave Hoskins' arithmetic hash. All new canvas shaders are drawn once at
  load (`opacity` 0, meta "warming") so the first use does not compile.
- Measured in a harness (23/23): 18 placed, 0 stone hits in front of any back,
  narrowest passage left 2.85 m, all reachable; spawned 132 m off, wandered
  11-15 m in 8 s; saw the player down a corridor and hunted, dread up, label
  up; steady chase 4.55 m/s; E hid in 184 ms, it lost them, slats up, a 50 hit
  did nothing, it came within 1.0 m and gave up after ~9 s without finding
  them; E out 0.05 m from the front with collision back; its blow did 55
  through a held guard; a 20 cut did 4; dread off far away. NOT yet benchmarked
  (the wardrobes are ~9 draws each; the Shade one transparent skinned mesh).- **Hiding places are sarcophagi now** (2026-10-08; the louvred wardrobe is
  gone). `hiding_spot.gd`: a hollow stone coffin (2.3 x 1.05 x 0.95 m, arch
  stone at half the arches' texture scale -- at theirs it read as a woven
  check) lying along the wall at `HIDE_FROM_CENTRE` 1.22, with a carved lid
  that carries its own collision. States SEALED -> (E "Open": walk up, the lid
  grinds along the rim, one end open) GUARDED: a real skeleton from the maze's
  `enemy_scene`, adopted through `maze.adopt_enemy` (so a reset frees it), rises
  out of the open end and climbs over the rim with its physics held off and its
  rig stepped by the coffin, then is let loose and alerted -> killed: EMPTY for
  good, toast, and `explore_map.mark_hiding_place` -> (E "Hide") OCCUPIED: the
  player lies inside, eye just over the front rim, the lid drawn back over and
  propped `LID_GAP` 0.13 m -- the real gap IS the view out (the HUD overlay is
  only a vignette now, `slat_amount` 0). If the guard is freed without dying
  (the player died and the world reset), the coffin reseals and is guarded
  again. Map: pale bar along the wall, `COL_HIDE`, drawn only where charted,
  kept apart from the charted cells so a death does not forget it; legend
  "hiding place". Measured (22/22): 18 placed, 0 stone in front of a back,
  narrowest passage 2.52 m, all reachable; Open raised the skeleton in 717 ms
  and it stood 0.65 m from the front and hunted; no Hide prompt while it stood;
  killing it emptied the coffin and the map pixel read COL_HIDE; hidden, a ray
  out of the gap was clear, the lid 0.10 m over the eye, the rim below it; the
  Shade did not find them; out again; a reset resealed a guarded coffin and left
  the emptied one empty.- **Peeking** (2026-10-08): hidden in a sarcophagus the player now lies with the
  lid SHUT and eyes below the rim (`EYE_LOW` HEIGHT - 0.13) -- nothing to see but
  the inside of the coffin. Holding "jump" (Space) peeks: `player._update_peek`
  (run at the top of `_physics_process`, before the hidden early-out) eases
  `peek_amount()` 0 -> 1 over `peek_ease_time` 0.2 s, and the coffin
  (`_follow_peek`) lifts the lid to `_lid_propped()` and the body to `EYE_HIGH`
  with it. The peek bar works like the ghost bar: drains over `peek_duration`
  3 s, refills over `peek_refill` 4 s whenever not peeking (out of hiding too,
  and while held-and-locked), and run dry the key must be let go
  (`_peek_locked`). HUD: `PeekBar`, centred under the crosshair, ghost-bar
  colours, shown only while hidden.
- **Hiding makes enemies give up** (`enemy.gd`, so skeletons and the boss --
  NOT bombers, the orange flyers, which never ask; the mimic only fights in its
  sealed room, which has no hiding places). A guard goes home; anything else that
  was engaged walks away (`_begin_retreat` / `_run_retreat`): to its home or its
  furthest wander spot if 9 m clear, else to a navmesh point 11-20 m off found
  with `map_get_closest_point`, tried in the direction it already stands from
  the player first (a sentry adopts it as its new post), along the navmesh at
  `retreat_speed_scale` 0.5. `map_get_random_point` over the whole map almost
  never landed in that ring: the first version walked "away" to a home 4 m off.
  Seeing the player again calls it off. Bombers still blow up on the coffin;
  a hidden player takes no damage from it.
- Measured (17/17): shut, a forward ray hits stone; Space -> peek 1.0 in 0.4 s,
  the view out clear; bar 0.61 after ~1 s, dry and locked at ~3 s, +0.25 in 1 s
  after release, peeks again; bar hidden out of hiding. A skeleton engaged,
  still engaged with the player in the open (control), gave up once hidden and
  walked 4.6 -> 9.1 m (another run 2.4 -> 11.6) from the coffin; a bomber
  arriving after hiding flew in and blew itself up; the hidden player unhurt.
  Harness trap (again): a freed bomber compares equal to null, so an
  `if bomber != null` check silently skipped the bomber test.
## 12. The starting jail cell (2026-10-08)

- `scripts/jail_cell.gd` dresses the spawn dead end (`Built.spawn_door`) as a
  jail cell, built FRESH -- the old tile-maze jail code (`_build_jail_cells`,
  `_stock_jail_cells`, `cell_door.tscn`) is deliberately not used. Called from
  `maze._build_module_level` right after `place_doors`, before the bake. The
  gate door is untouched and still has to be kicked in.
- **A dead end is not square.** Measured with rays from its centre: back wall
  2.79 m, but two thick piers fill the back corners, so behind z = -1.2 (toward
  the back) the room is an alcove only 1.80 m either side; the full 2.79 m is
  only toward the door. A bed against the "2.79 m" side wall sat inside a pier.
  Layout now: plank bed with a straw pallet and a blanket across the alcove's
  back wall (head 0.15 m off the left pier), two shackles and chains on the back
  wall beside it with the last prisoner's skull, ribs and long bones under them,
  tally marks on the right pier, a slop bucket out in the wider front part,
  260 straw blades (MultiMesh) kept inside the real floor outline.
- Wall pieces (shackle plates, tally marks) snap onto the real stone by ray
  (mask 2|256) two physics frames after `_ready`: Tripo stone stands up to
  ~10 cm proud of the measured face.
- Plain-coloured props lit by the door's torches a metre or two away blew out
  to glowing orange; their albedos are deliberately dark (straw 0.29/0.22/0.10,
  bone 0.48, scratches 0.30).
- Measured: built in the spawn dead end, player starts inside it, 3/3 wall
  pieces snapped, bed and bucket collision clear of the stone (shape queries on
  layer 9 -- the first layout overlapped), nothing on the spawn spot, the door
  shut and E still kicks it in.- **Block pressed during an attack waits for it** (2026-10-08): `_start_block`
  now refuses for the WHOLE of a cut or thrust (it used to allow raising the
  guard out of a cut's recovery), and `_hold_guard` (every physics tick, after
  `_check_block`) raises it the moment nothing refuses any more if the button is
  still held -- the end of a cut, a thrust, a slam's recovery, a drink. Released
  before the end: no guard. A right click that only recaptured the mouse is
  `_guard_click_spent` until released, so it never turns into a block. Measured:
  held through a cut / pressed in its recovery / held through a thrust (the
  lunge still happened): guard up 0.016-0.017 s after the attack ended, never
  during it; tapped mid-cut: no guard; idle press: immediate, fresh parry window.
## 13. Prison cells in the corridors; yellow skeleton eyes (2026-10-08)

- **Cell rows** (`scripts/cell_row.gd`, placed by `maze._place_cell_rows` before
  the hiding places and the bake): `cell_row_count` 10 stone cell blocks, spread
  over the free side walls of corridor straights (not niche walls, torch walls,
  door cells, the spawn, under the boss hall). Each: 3 cells (1.15 m wide)
  between 0.5 m pillars under a lintel and capping slab, the front 1.17 m out
  from the measured wall face (`CELL_ROW_WALL` 1.90), everything that meets the
  wall reaching `BACK_IN` 0.3 m into it (the stone's face varies by ~15 cm along
  a straight). Each cell shut by iron BARS or (`cell_door_share` 0.45) a banded
  plank DOOR with a small barred window at 1.62-1.96 m; `cell_prisoner_share` 0.5
  hold a prisoner: the enemy skeleton model at `PRISONER_SCALE` 0.88 in its idle,
  facing out -- behind a door centred and square to the window. At 0.94 the
  window showed only his ribs. Decoration only: one collision box (1+2), grid
  tiles marked WALL. Hiding places keep out of straights with a row
  (`_cell_row_cells`): a coffin opposite a block would leave too narrow a passage.
  Measured: 10 rows, narrowest passage left 2.60 m, nav path along each straight
  past its row with no detour, reachability still 100%.
- **Yellow eyes on every skeleton** (`scripts/skeleton_eyes.gd`, `attach(root)`,
  from `enemy._ready`, and on the prisoners): two unshaded emissive balls with
  additive halos on a BoneAttachment3D on the `head` bone. The sockets are
  MEASURED once per mesh: the vertices skinned mainly to `head` are the skull
  (564 verts, mesh space = skeleton space on this model, face toward +Z, box
  0.22 x 0.29 x 0.31 m); sockets at 45% up, +-22% across, 3.5 cm in from the
  front, carried into bone space through the skin's bind pose. Hidden on death
  (`enemy._die`). The cage skulls keep their red eyes. The boss has none: its
  scene is a placeholder MeshInstance3D with no rig.- **The corridor cell rows were REMOVED** at the user's request (2026-10-08):
  `scripts/cell_row.gd` deleted, `maze._place_cell_rows` and the hiding places'
  `_cell_row_cells` exclusion gone. The note above describes code that no longer
  exists. The yellow skeleton eyes stay.

## 14. The spear (2026-10-08)

- **Second weapon, hotbar slot 3 at the start** (`scripts/spear.gd`, a Node3D
  under `Head` made in `player._ready`; `Inventory.ITEMS[&"spear"]`, icon
  `ItemIcon._spear`, stats in `inventory_screen._stats_for`). It does its own
  fighting; `player._unhandled_input` routes LMB / Q / F to `spear.stab()` /
  `dash()` / `throw()` while it is in hand and `_spear_free()`.
- **Stab (LMB)**: 10 damage, one per `STAB_EVERY` 0.28 s however fast it is
  clicked; a box `STAB_REACH` 2.7 m x 0.45 down the camera on the hitbox mask,
  first body only, line of sight checked, bombers skipped (they take the haft).
- **Dash (Q)**: `player.begin_spear_dash` drives the body at 17 m/s for 0.32 s
  (no steering); a 0.9 m sphere ahead hits everything once for 25 and shoves it
  aside. Cooldown 1.4 s. Trap: the dash ended at full speed and the normal
  movement code coasted it ANOTHER 6 m (11.3 m total) -- the exit now clamps
  horizontal speed to `move_speed`. Measured 6.3 m.
- **Throw (F)**: 0.24 s wind-up, then a top-level "ThrownSpear" flies 46 m/s by
  ray (stone, layer 9, hitbox mask) up to 42 m, EXPLODES where it stops
  (`BLAST_DAMAGE` 60 falling to half at `BLAST_RADIUS` 4.5, push 15, LOS from
  the blast, bombers `swat`ted, `alert()`), sticks 0.3 s, then is pulled back
  butt first along a glowing tether and caught (~1.4 s round trip at 10 m).
  Nothing works while it is away. The player takes no blast damage.
  Thrown point-blank at a wall it bursts at the wall, not beyond it.
- Fireball is `shaders/spear_blast.gdshader` (facing-weighted noise, `fade`
  instance uniform): a plain additive sphere read as a solid faceted dome.
  Warmed up at load: worst frame through the first throw 27.7 ms.
- Traps: hiding the spear Node3D while it was away hid its top_level TETHER
  child too -- hide `_model`, not the node. Fully metallic iron rendered black
  in these halls (nothing to reflect): metallic 0.4. The rest pose aims the
  blade right of and below the crosshair; pointed AT it, the blade sat behind
  the reticle 2 m out and the spear read as a dark stick.
- `respawn` calls `spear.reset()` (back in the hand, projectile freed).
- Measured in a harness, 19/19: slot 3; F throw -> 55.8 on the struck enemy,
  46.9 at 2.5 m, 0 at 9 m; stab/dash refused while away; LMB 10; spammed
  5 stabs in 1.4 s; nothing at 3.8 m; Q 6.3 m, second Q on cooldown 0 m; dash
  25 to each of two in line; bomber beside the blast popped (control: a blast
  14 m off left one untouched); reset.

- **Every weapon blocks** (2026-10-08). `_start_block` takes anything
  `Inventory.is_weapon` (kind "Weapon"), not only the sword; `_check_block`
  drops the guard if the item in hand changes (`_block_item`), and
  `_hold_guard` raises it again at once with the new one if RMB is still held.
  The sword keeps its pivot pose; the spear reads `player.guard_amount()` and
  blends to `spear._guard_pose()` (haft level across the body, its middle in
  front of the face, blade off left) -- a PLACEHOLDER. The plan (user): every
  weapon is a hologram projected by a crystal in the haft, and a SHIELD pops out
  of the haft on block; models and animations are in progress. Hooks for it:
  signal `guard_changed(raised)` (also on death/respawn), `guard_amount()` (eased
  0..1 over `GUARD_UP` / `GUARD_DOWN`), `guarded(parried, attacker)` and
  `_guard_kick` for the knock. The spear guard waits for a stab/dash/wind-up
  and for a thrown spear to be caught (`spear.busy()`); nothing else of the
  spear works while guarding (`_spear_free`). Measured with the real RMB
  (11/11): spear parry 0 taken / 20 back, block 4 of 40; stab, dash and throw
  refused while up (re-broken: the dash went through, 6 m and 25 damage); guard
  up after the stab, not during; none while thrown, up on the catch; spear ->
  sword with RMB held: down, up with the sword, which still blocks 4 of 40;
  potion in hand: no guard.

- **The sword's Q is a SPIN now; the thrust is gone** (2026-10-08). `_start_spin`
  -> pose `spin` (`_spin_pose`, timeline SPIN_WIND 0.2 / SPIN_TURN 0.62 /
  SPIN_END 1.0; the slash ends at 0.42): blade wound out right while the view
  coils `SPIN_COIL` against the turn, then the HEAD turns one full circle left
  (`_spin_view_yaw`, added to `head.rotation.y`; the body's yaw -- the aim --
  is never touched, and a whole turn ends exactly where it began) with the
  blade held at `SPIN_LEAD` leading it, so in the world it sweeps the whole
  circle. Hits are the cut's: the same swept-blade slab in `_resolve_hits`,
  `attack_damage`, `attack_push`, `attack_stun`, once per body; bites from
  SPIN_WIND to SPIN_TURN; committed (`_bite_end` = SPIN_END), Q mid-spin does
  nothing. No trail (it is drawn in the head's frame, where a spinning blade
  stands still). The thrust's exports, constants, pose, planting and its hit
  box are deleted; `_hilt_at` now always takes an aim (the cage stab uses it).
  The lunge speed lines stay for the spear's dash ("Lunge look" group).
- **Spear throw: 100 damage, 10 s cooldown** (`BLAST_DAMAGE`, `THROW_COOLDOWN`
  from the release; reset on respawn). Full damage within 1 m of the impact (a
  struck body's centre is ~0.9 m from where the spear hit it), half at the
  4.5 m edge. The cooldown shows on the spear's hotbar slot
  (`ItemSlot.set_cooldown`: a dark shade draining downward + seconds left,
  driven by `hud._update_slot_cooldowns` from `spear.throw_charge()`).
- Measured (all pass): spin hit enemies front, right, behind and left once
  each for 20, knockback 5.50 outward on all four = a cut's 5.50; 5 m off
  untouched; view turned 6.28 rad and ended at 0.0000 with the body's yaw
  unchanged; a second spin after it hits again; worst frame 17.2 ms (idle and
  a hand turn: 17.2 / 16.9). Throw: struck enemy 100.0; F again 1.9 s later
  refused; slot showed 9; clears at 10 s and throws again.
- **Harness trap**: a "50 ms first frame" of every attack was the harness --
  the timer started before a press helper that waits two frames, so the first
  sample spanned three vsyncs (3 x 16.7). Start the clock AFTER the press.

## 15. Faster stab, blood on the view, healing over time (2026-10-08)

- **Spear stab**: `STAB_EVERY` 0.28 -> 0.13, out in 0.035 s, home by 0.11.
  Measured: 10 stabs in 1.3 s (was 5 in 1.4 s), still 10 each.
- **Drinking heals EVENLY** (`player._update_drink`): `heal_amount` over
  `drink_time` (40 over 3 s), applied straight to health; the HUD's "Used ..."
  line is raised once for the total at the end (`_finish_drink`), not per frame.
  **Cut short** (`_interrupt_drink`) by any attack key with a WEAPON in hand
  (LMB / Q / F -> `_attack_key_spills_drink`, the attack then goes ahead) or a
  haft strike, and by any hit that actually hurts (in `take_damage` after
  guards and invulnerability). What has flowed in is kept, the flask (used as
  the drink began) is gone, the held flask lowers (`held_potion.stop()`), and
  `drink_interrupted(healed)` -> HUD toast "Drink cut short +N". LMB with the
  POTION in hand is the drink, not an attack. Cage-skull DRAIN does not cut it
  short (it is not a hit). Measured: +6.9/13.6/20.2/26.9/33.6 at 0.5 s steps
  (expected 6.7/13.3/20/26.7/33.3), +40 in full; LMB with the sword at 1 s:
  +13.6 kept, no more, swing happened, potion gone; a 10 hit at 1.5 s: heal
  kept, hit taken, no more; LMB with the potion in hand: still drinking.
- **Blood on the view** (`shaders/blood_screen.gdshader`, `hud._update_blood`):
  none above `BLOOD_FROM` 75% health, full at `BLOOD_FULL` 10%; splats from
  the edges (further at the corners, broken into lobes), droplets just ahead of
  them, a few drips from the top, and the rim darkening -- throbbing with a
  heartbeat below `BLOOD_HEART` 35%. `_wound` eases up fast (a hit splashes it
  in) and down slowly (washes away over a drink). Gameplay info: not gated on
  effects; warmed at load like the dread. DARK blood on purpose: the first pass
  at a 0.42 red read as a glowing red picture frame in this red-lit level, with
  speckles over the whole view at 60% health. Cost: 16.65 vs 16.67 ms
  (vsync-capped, RTX 3060) -- not measurable there; not benchmarked on the P620.
- **Blood made much fainter; low health greys the world** (2026-10-08). Blood
  now starts at `BLOOD_FROM` 50%, reaches at most a fifth of the screen height
  in, alpha 0.12-0.35, near-black colours, fewer droplets, drips only below
  ~25%. The main low-health signal is now `player._health_saturation()`: below
  `low_health_desaturate_from` 50% the environment's `adjustment_saturation`
  falls (smoothstep) to `low_health_saturation` 0.12 of the base at 0 health,
  through the same `_update_colour` that ghost mode uses (ghost still pins it
  to 0). No extra pass; the HUD keeps its colour. Measured (base 0.92): 100 /
  60 hp 0.92, 45 hp 0.90, 25 hp 0.52, 8 hp 0.17; ghost 0.00; back to 0.92 at
  full health.
- **Spear stab: 4 a second, evenly spaced under spam** (2026-10-08).
  `STAB_EVERY` 0.25 (out 0.06, home 0.21). A click that comes before the next
  jab is due is HELD (`_stab_queued`), not dropped, and fired on the physics
  step it falls due (`_physics_process`), timed on the spear's own step clock
  `_stab_clock`; the next is always scheduled from the step it fires on, so
  nothing comes sooner than 0.25 s. A held click is forgotten if the spear
  stops being free (guard up, drink, ghost, dash, throw, another slot).
  Measured with real mouse events: clicks every 20-90 ms -> 13 stabs exactly
  0.250 s apart, 4.00/s, all 13 landing for 10; uneven 180-330 ms clicks ->
  gaps 0.25-0.33, never under 0.25; a held click dropped when RMB went up.
  Re-broken (early clicks dropped, as before): gaps 0.25-0.33 under the same
  frantic clicking, 11 stabs -- the test sees it.
- **Spin v2 (2026-10-08) -- SUPERSEDES the view-turning spin above.** The head
  no longer turns at all (`_spin_view_yaw` removed; `head.rotation.y` is only
  the haft camera's again). The BLADE sweeps the full circle instead:
  `_spin_pose` runs `_arc_pose` from `SWING_OPEN` round by -TAU (it takes any
  yaw; the hand follows), across the front, out of view behind, in again on the
  right. Level at `_spin_level()` = `_cut_pitch(0)` - `SPIN_DROP` 0.25: at eye
  height the circle and its trail are seen edge-on and the trail was a flat
  laser line along the horizon; at chest height it arcs across the lower view.
  The cut's white trail now runs for the spin too (`_update_sweep_trail`
  samples `_spin_pose` between frames, as it does `_swing_pose`).
  Knockback `spin_push` 11 / `spin_stun` 0.35 (a cut: 5.5 / 0.15); damage still
  `attack_damage`. Effort camera `_spin_effort()` -> (roll, pitch, drop, fov)
  composed in `_update_head` / `_update_dash_view`: wind-up leans back into the
  coil, dips and draws the FOV in (-3) with a building tremor; the drive leans
  into the turn (`spin_effort_roll` 6 deg), crouches (`spin_effort_drop`
  0.07 m), opens the FOV (`spin_effort_fov` +6) and trembles with the strain;
  release punches (`_swing_kick` 0.9) and shakes (`_shake` 0.2), then eases out.
  Measured: head yaw 0.00000 throughout, body yaw unchanged; front/right/
  behind/left hit once for 20; knockback 11.0 on all four vs a cut's 5.50;
  trail in all 36 ten-degree sectors round the player; roll 7.5 deg, drop
  0.14 m, FOV -2.3 / +6.0, back to exactly 75.000; worst frame 17.2 ms.
- **Spin v3 (2026-10-08, at the user's request) -- the VIEW spins again**,
  superseding v2's still head; v2's trail, double knockback and effort camera
  are kept. The head turns the full circle (`_spin_view_yaw` / `_spin_yaw_at`,
  coil `SPIN_COIL` 0.3 back first) and the blade is held at `SPIN_LEAD` -0.45
  leading it, at the lowered level pitch (`_spin_level`). Two things this needed:
  - **Trail in the BODY's frame during a spin.** In the head's frame a blade
    that turns with the head stands still and leaves no trail. Spin samples are
    `[point, time, true]` in the body's frame, the head's turn at each sample
    rebuilt from `_spin_yaw_at(at)`; `_update_sweep_trail` maps an entry by the
    body if it has the third element, else by the head.
  - **`_spin_view_yaw(delta)` looks a frame ahead.** `_update_head` runs before
    `_update_pose` advances the stroke by the same delta, so the head was a
    frame behind the blade and the streak ran on past it -- up to 0.71 m.
  Measured: head 6.28 rad and back to 0.00000, body yaw unchanged; four sides
  hit once for 20, knockback 11.0; trail in every sector on one circle (radius
  1.78-1.92 m, height spread 0.14 m); newest trail point 0.000 m from the blade
  (re-broken without the look-ahead: 0.713 m); FOV back to 75.000; worst frame
  17.1 ms.
- **Mouse look is ignored during the spin** (2026-10-08): `_unhandled_input`
  drops mouse motion while `_pose_kind == &"spin"` (not saved up), so the turn
  is always exactly one rotation and the body's yaw and pitch do not move.
  Measured with real mouse-motion events every frame (0 / +40 / -40 px, and
  15 px down): view turned 6.283 rad each time, body 0.0000, pitch 0.0000;
  mouse look normal before and after. Re-broken (guard off): 6.283 / 3.043 /
  9.523 rad. Harness traps: an injected event is handled the NEXT frame, so one
  injected in the spin's last frame lands after it; and measure the turn as
  body yaw + head yaw -- the camera's forward vector is skewed by the spin's
  lean and nod, and starting two frames in misses part of the coil.
- **Spin hands control back at the full turn; Q overrides a cut**
  (2026-10-08). `_spin_released()` (spin and `_pose_time >= SPIN_TURN` 0.62):
  from then the player has full control while the blade comes home -- mouse
  look (the drop in `_unhandled_input` stops), `_bite_end` is SPIN_TURN so a
  cut/spin/drink can start, `_start_block` lets the guard up, and
  `_attack_slows()` (used for walk speed and damping) is false. `_start_spin`
  no longer waits out a slash/chop: Q drops the cut where it is and the spin
  winds up from there, as the slam does; only a spin still turning refuses Q.
  Measured: mouse look, a spammed cut and a held guard each first took effect
  on the frame the turn completed (pose 0.617 -> 0.633 s; was 1.0); the turn
  still exactly 6.283 rad with the mouse moving; walk 4.25, 2.55 mid-turn,
  4.25 again before the blade was home; LMB then Q at 0.1 s into the stroke:
  chop -> spin, three enemies round the player all cut; Q at 0.3 s into a
  spin ignored.

## 16. The Remnant (2026-10-08)

- **The big ghost is "the Remnant"** (was the Shade): `display_name` "THE
  REMNANT", node "Remnant", comments renamed. Still `scripts/stalker.gd` and
  group "stalker" in code.
- **No overlay warning any more.** The frost/heartbeat rect and "IT HUNTS YOU"
  label are gone from the HUD (`shaders/dread.gdshader` is now unused). Instead
  (`hud._update_dread`, gameplay info, not gated on effects):
  - **Torches go ice blue when it is very close**: `torch.gd` static `chill`
    (0 fire, 1 ice) = 1 - smoothstep(`CHILL_NEAR` 6, `CHILL_FAR` 18 m), eased
    over ~1 s. Every torch IN RANGE (they already skip work out of range)
    lerps its light from its own colour (`_fire_colour`, read once) to
    `ICE_LIGHT`, and the flame shader mixes an `_ice` ramp by the `chill`
    instance uniform (flame and halo). Only touched when chill changes.
  - **While it HUNTS: an icy grade** -- a 1D colour-correction LUT
    (GradientTexture1D) on the scene's environment, red held down and blue
    lifted (mid grey -> 0.34/0.47/0.60, shadows lifted blue), blended by the
    eased hunt amount (`HUNT_IN` 1.5 s, `HUNT_OUT` 3 s) and set to null at 0.
    The first curve (mid grey -> 0.25/0.42/0.60) took this red-lit level
    nearly to black. Measured mean luminance: normal 10.8, hunted 13.3 (blue
    21.3 vs red 13.9), torches chilled 16.5.
  - **And the camera** (`player.set_remnant_hunt`): a fine noise tremble
    (`remnant_shake` 5 mm, `remnant_shake_roll` 0.45 deg) and the FOV drawn in
    `remnant_fov_in` 2.5 deg, breathing +-0.8 over 5 s. Measured: FOV
    -3.30..-1.70 deg, frame-to-frame head motion 10.7x calm.
- **Trap fixed in passing**: `_update_dash_view` returned early (resetting the
  FOV) unless a dash/swing/jump/zoom/lunge was active, so a FOV term added
  only in its composition line never showed. The spin's FOV effort was exposed
  to the same gap; both are now in the early-out test.
- **One blow kills** (`stalker.one_shot` true): the strike deals
  max(`strike_damage`, 10x the player's max health), so even ghost mode's 0.2
  dies. Turn it off when the player has upgrades to face it.
- Measured (12/12): far -> 9 torches fire, no grade, FOV exact; 4.5 m (not
  hunting) -> 9 of 9 torches blue, still no grade; hunting -> grade, FOV,
  tremble; gone -> every torch back to exactly its own colour, grade null, FOV
  75.000; one blow killed at full health, and in ghost mode.
- **Torches cool earlier** (2026-10-08): `CHILL_FAR` 18 -> 32 m, `CHILL_NEAR`
  6 -> 10 m, so the blue is a warning in time to act. Measured chill: 40 m 0.00,
  30 m 0.02, 24 m 0.30, 18 m 0.70, 12 m 0.98, 9 m 1.00.
- **Item drops never fall through or into anything** (2026-10-08,
  `item_drop.gd`). Measured first with a stress harness: ~560 drops released at
  random REACHABLE navmesh points (body height; the navmesh also covers the tops
  of the wall boxes -- islands nobody reaches -- so unfiltered random points are
  bogus), one in four also from 0.35 m inside the nearest wall, 4 over every
  coffin and anchor, the throne seat and the jail cell, and one onto every
  coffin lid, which is then slid open. Judged: never settled; under a floor
  (straight up is a surface's underside); floating (nothing under it); inside
  (point overlap with a static shape -- a ray from inside a box never sees the
  box -- or back faces in 2+ directions). Before: 26 of 687 bad -- 21 left
  floating where coffin lids had been, 5 inside the boss hall's wall or the
  throne (layer 9 only, which drops ignored). Fixes:
  - lands on `LAND_MASK` 1|2|256 (layer-1-only props like the jail bed, the
    layer-9 throne), passing through characters and loose bodies
    (`_world_ray` re-casts excluding them); back faces ignored -- landing on
    one meant resting on a ledge INSIDE a wall's shell;
  - re-checks its support every `SUPPORT_CHECK` 0.25 s while resting, falls
    again if it has gone;
  - released inside solid (`_is_buried`), it steps out toward the player (who
    is always in the open) on its FIRST FRAME -- `spawn` adds it to the tree
    before setting its position, so `_ready` sees the origin;
  - if it comes to rest buried anyway (a lid sliding round it), out and down
    again, up to 3 times;
  - last resort: `LOST_DROP` 4 m below where it was dropped, or falling
    `LOST_TIME` 4 s, it is put on the ground under its drop point.
  After: 0 of 2,061 over three runs.
- **The Remnant hunts faster**: `hunt_speed_ratio` 1.07 -> 1.35. Measured 5.74
  m/s against a 4.25 walk: walking away loses ~1.5 m/s, a full ghost burst
  (2.5x for 4 s, 5 s refill) still opens ~20 m, so escaping means using ghost.

## 17. The morgue, the royal sarcophagus, and getting up after death (2026-10-08)

- **The morgue** (`scripts/morgue.gd`, built by `maze._build_module_level` under
  the nav region before the bake): the carve is asked for one extra chest room
  and `maze._pick_morgue` turns the one FURTHEST from the start into kind
  "morgue" (5 chest rooms kept; `morgue_enabled`). `chest_rooms()` filters on
  kind, so it gets no chest, mimic, pedestals, gates or guards;
  `is_in_morgue` keeps ordinary spawns out; map draws a bone-white cross
  (`COL_MORGUE`). The local frame faces the first entrance: royal sarcophagus on
  a dais at the back facing the way in, 10 standing wooden coffins against the
  court's piers (closed / ajar / open / open with a broken body standing in it /
  lid fallen flat), 3 stone slabs (two with bodies), 8 bodies on the floor
  clear of the aisle. Coffins are procedural anthropoid prisms (`_prism`,
  `_tri` winds every triangle clockwise-from-its-normal, Godot's front).
  Collision boxes 1+2.
- **The dead**: the enemy skeleton model at 0.94, laid on its back (quarter
  turn about X; the flip makes it face -Z), dropped by its rest bounds onto the
  floor, every joint knocked out of true (`_sprawl`), 80% missing 1-3 of head /
  arms / forearms / thighs / shins -- `set_bone_pose_scale` 0.001 collapses the
  mesh into the joint -- with the lost bone or skull lying near. NOTHING GLOWS:
  the model's material has emission ON (the enemies tint it by state); bodies
  get a shared copy with emission off and dulled albedo (`_make_dead`).
  Measured: 12 bodies, 0 emissive surfaces, 0 lights.
- **The royal sarcophagus**: 3.9 m, sized to the Remnant (model x1.75), dark
  stone with old-gold edges, a gold sword down the lid, crest and crown; the
  Remnant's own crowned body stands inside. Material traps: `stone_plain_albedo`
  averages 30/255, so any tint of it rendered solid black -- the stone uses only
  its normal map; and bright gold (1.0/0.74/0.3) read as neon under the court's
  red sky light -- 0.6/0.44/0.17.
- **E on it ("Open") is a scene the player does not survive** (`_open_royal`):
  walk up (letterbox, hands away), lid grinds a hand's breadth, the room goes ice
  blue in 0.4 s (`hud.ice_override` forces the torches' chill and the ice grade;
  the room's own lights tween to ice), the Remnant appears 3.4 m BEHIND
  (`stalker.scripted_appear`: AI off, flash, fades up), the view turns to it,
  it rears (`scripted_windup`) and slams (`scripted_slam`), the view is crushed
  into the floor (`player.scene_crush`) and cut to black (`hud.fade_black`), then
  `player.kill_in_scene()`. The respawn resets the room (`_on_respawned`) and
  `_populate` spawns a fresh Remnant. If the Remnant has been banished the lid
  just opens. Measured timeline: creak 0.9 s, ice 1.5, appears 1.95, turned
  2.73, black 4.15, dead 4.23. Traps: in PAUSE/SEARCH `stalker._hold` plays the
  idle loop every frame, which overwrote the windup and slam -- scripted state
  is STRIKE; the health bar hides for a `scripted` host.
- **The Remnant guards it**: corridor spots within 34 m of the morgue are in its
  wander list `remnant_morgue_bias` (4) times over.
- **Every death fades to black; every respawn gets up** (player.gd): `_die`
  fades `hud.fade_black` (a CanvasLayer at layer 90, over the HUD and the
  letterbox) over 0.75 of `respawn_delay`; `_respawn` -> `_begin_wake`: black
  fades out over `WAKE_FADE` 1.3 s, saturation starts at 0 (set directly --
  eased, the view came up in colour) and returns over `WAKE_COLOUR` 2.8 s
  (`_wake_colour` in `_update_colour`), the camera lies on its side 1.32 m low
  (roll 72), pushes up onto a knee looking down, then stands with a sway
  (`_wake_view`), weapons away until 1.3 s, control at `WAKE_CONTROL` 1.9 s.
  Measured: saturation 0.00 at respawn, eye 1.35 m low, full colour/standing/
  control by ~1.7 s after; an ordinary death reached full black.
- Not benchmarked on the P620 (12 more skinned meshes in the morgue, no new
  lights); vsync-capped 60 fps on the RTX 3060 in the room.
- **The Remnant starts very far away and wanders at random** (2026-10-08,
  superseding the morgue bias above): `maze._spawn_stalker` picks a random spot
  among the furthest `stalker_far_share` (10%) of the corridor from the player,
  never nearer than `stalker_min_distance` 100 m, at level start and after
  every death; the morgue wander bias is removed (`wander_spots` is the plain
  corridor list, `_pick_wander` random hops 12-45 m). The pick uses its OWN
  `RandomNumberGenerator.randomize()`d: the maze's `_rng` is seeded to repeat
  layouts and the global RNG is reseeded on every reset -- with either, the
  Remnant came back on the very same spot after every death. Measured over a
  start and 3 deaths: 151 / 159 / 156 / 146 m away (furthest corridor 162 m;
  94-100% of the corridor nearer), four different spots; wandered ~20 m in 12 s.
  Harness trap: the respawn's wake is a scene (no damage), so killing the player
  0.4 s after a respawn silently did nothing.
- **Map legend wraps** (`explore_map._build_full_map`): an HFlowContainer across
  the panel's width, growing upward, instead of a fixed 640 px row whose last
  entry ran off the panel once "morgue" was added.
- `screenshots/` (with `.gdignore`) holds map_complete.png / minimap_complete.png,
  taken with every cell revealed via `ExploreMap.restore()`.

## 18. Puzzle rooms, shards and the great door (2026-10-08)

- **Every chest room is a puzzle room** (`scripts/puzzle_room.gd`, built by
  `maze._build_puzzle_rooms` after the morgue, before the bake; `puzzle_rooms`
  export). Entering (1.8 m inside the gate line) seals the room's gates
  (`_gates[i + 1]`, driven in `maze._process` from each room's `sealed`) and
  announces the puzzle's name and hint; solving sinks them, brings the dimmed
  sky light back up and raises a plinth out of the floor in a light column with
  the room's chest on it. The chest (`chest.gd` `shard`, `coins`) holds the
  room's shard (`Inventory.SHARDS`, kind "Relic", bag first, Treasure tab).
  No pedestals, guards or `_spawn_chests` chests in this mode.
- **Four puzzles, dealt like a deck** (every one before any repeats):
  `platforms` THE STAIR OF KEYS -- 4 colour levers each raise 2-3 of 4
  platforms one step (0.85 m), bands of colour on each platform per lever;
  the planner (`_plan_platforms`) guarantees exactly ONE lever combination
  makes the stair 1-2-3-4 up to the keystone at 5; standing on it solves.
  `prism` -- 3 levers XOR R/G/B beams into a crystal (rows independent over
  GF(2), rings on each post show its beams); hold the Eye's colour 1 s,
  three rounds. `chorus` -- 6 coloured stones sing a sequence (3, 4, 5 notes),
  strike them back; a wrong note drains 10 (never below 25%) and it replays.
  `veil` -- 4 glyph dials; which glyph each wants is written on corner stelae
  visible ONLY in ghost mode. Shapes, not colours, because ghost mode drains
  the colour from the view.
- **A sealed room is a ward**: `stalker._warded` treats the player as hidden,
  so the Remnant cannot trap and kill them in a room they cannot leave.
- **Death**: an unsolved room resets and unseals (`on_world_reset`, called by
  maze AFTER `_populate`); a solved room stays solved, an unopened chest stays.
- **The mimic** is the room far from the start both ways (walk and straight
  line, each scaled by the largest; `_far_room_from_start`) -- the first pick
  by walk alone was 367 tiles' walk but 36 m from the start. It rises in place
  of the chest (`wake_floor` -1.3, opened from the floor), `register_mimic`
  hands it to the old seal-until-dead logic, it drops the shard on death (onto
  the floor if the pack is full), and a death brings an unkilled one back.
- **The shard door** (`scripts/shard_door.gd`, `maze._build_shard_door`): two
  8 m stone-and-gold leaves in the boss hall's arch, hinged on its HALL face
  (the portcullis hangs mid-arch in front of them), one colour-ringed socket
  per room. E sets every carried shard (out of the pack first, so a death
  cannot copy one); with all five the shards blaze, the seal burns away and the
  leaves swing into the hall (letterboxed scene, ~10 s), then `OpenLeaves`
  collision. With none it says how many are set.
- **Traps hit**: the level's arch stone (`_synth_arch_material`) is lit by its
  MultiMesh instance colours; on plain meshes it renders BLACK under any light
  -- the puzzle stone is its own normal-mapped grey with a faint emission
  standing in for ambient. `CylinderMesh.radial_segments` will not go below 4,
  so a "triangle" came out a diamond (the square turned 45 deg): the triangle
  glyph is built by hand (`_triangle_mesh`). Sky dimmed to 0.35 left only the
  glowing parts visible; it is 0.55 plus a room-coloured light (`RoomLight`).
- Measured in a harness (90/90): 5 rooms, all 4 kinds; each sealed on entry
  with its gates up, solved through real E presses on levers/stones/dials, the
  platform stair CLIMBED with the movement and jump keys onto the keystone,
  gates down, plinth at 0.60, shard in the pack; death in an unsolved room
  unsealed and reset it; mimic sprang, sealed its room, open again on death,
  shard given; Remnant lost a player in a sealed room (control: kept hunting
  outside); door refused with no shards, opened with five, control returned,
  walked 5 m into the hall. Clean run: 0 enemies in rooms. Not benchmarked on
  the P620 (one extra omni and ~40-60 small meshes per room).
- **The five dealt puzzles (2026-10-09)**: `puzzle_room.DEALT` = platforms, drowning,
  weighing, mirrors, bells -- one per room. prism / chorus / veil are still in
  the file (`KINDS`) but no longer dealt.
  - **Stair of Keys, harder**: 7 levers (red, blue, green, gold, violet, cyan,
    white), 5 platforms, keystone at level 6 (5.1 m). Every lever moves 2-3
    platforms; the planner keeps only layouts where exactly ONE of the 128
    lever sets makes the stair, and that set is 3-4 levers. Plans in ~0.5 ms.
  - **Drowning Court**: sealed at the COURT's 12 arches by stone sluices (the
    seal waits until the player is 1.2 m inside the court, or they would be
    shut out in the arcade). Water rises a stage every 9 s (stages 0/1.3/2.4/
    3.5 m); the player floats in it (`player.water_depth`, group "water",
    `SWIM_FLOAT` 0.95, jump works from the water, `swim_speed_scale`). Stone
    tops 0.02/1.45/2.55/3.65: each reachable AND above water at exactly one
    stage. Step on them in the Eye's order; a wrong one surges the water +1;
    the drain wheel lets 2 stages out; chest-deep water drains 3 hp/s down to
    25%. Traps: two water tweens overlapping (a drain still running under a
    surge) kept dragging the level back -- one tween at a time now; bobbing off
    a stone and back on counted as a wrong stone -- re-standing on the stone
    just counted is ignored; floating depth is 0.95, so the cold threshold is
    0.8, not 1.0. The water's grazing red sheen must stay faint (0.07): seen from
    a hand above it, nearly all of it is grazing.
  - **Weighing Room**: 2 shrouded bodies (5), 3 skulls (2), 4 bone bundles (1)
    dealt into three distinct targets (gold ingots on each scale's right pan).
    E lifts (held before the camera, `hands_busy`, `player.carry_speed_scale`
    0.55 for a body), E on a scale's left pan places / takes back, E at nothing
    sets it down. All three level and nothing carried -> solved. Beam: a
    positive angle drops the load's pan (the first version tipped backwards).
  - **Mirror Corridor**: 5x5 grid (3 m) at chest height; a red lantern and a
    coloured eye at two of eight edge ports. A DFS lays a path with >= 3 turns
    (mirrors) and one pane of the eye's colour; decoys: a wrong-colour pane,
    three mirrors, three pillars; mirrors scrambled. Beam meshes are POOLED:
    freeing them the frame they were made left `Graphics._apply_to_node` a
    deferred call on a dead node (an error per segment per turn).
  - **Bell Parry**: three gallows, blades swung by energy (never gain/lose
    height), periods 3.0/2.5/2.1 s. A blade meeting the player calls
    `take_damage(12, dir, blade)` with a `Blade` attacker (no-op knockback and
    damage) and bounces back; the player's `guarded(parried, attacker)` decides
    it. Three parries running rings the bell; a block or a hit resets the count.
  - Measured in a harness, 57/57 + 10/10 on resets: the stair climbed with real
    jumps; the drowning court sealed only inside, sluices solid, water rose by
    itself, dry jump short of the first column, every stone reached by
    swimming and jumping at its own stage, drain wheel by E, solved, drained,
    vault up; weighing lift/place/take/drop by E and solved; mirrors turned by
    E and solved; every bell rung by real right-click parries (unguarded: hurt;
    guard held: block only); a death in each new room resets it.

## 19. Title screen, settings, saving (2026-10-09)

- **The main scene is `scenes/title.tscn`** (`scripts/title_screen.gd`): Play (the
  four save slots), Settings, Quit. **`-- --bench` and `-- --skip-title` go
  straight into the level with no slot** (nothing is ever saved then), so the
  benchmark commands in section 1 still work unchanged. Harnesses that load
  `scenes/main.tscn` directly are also slotless. The title text is the project
  name (`application/config/name`).
- **`scripts/settings_panel.gd`** (class `SettingsPanel`) is the one settings page,
  shown by the title and the pause menu: CONTROLS (mouse sensitivity) and the
  graphics SPEC that used to live in pause_menu.gd. New graphics knobs go in its
  SPEC now. Sensitivity is `Graphics.mouse_sensitivity` (0.1-3.0, a multiplier
  on `player.mouse_sensitivity`, via `player._look_scale()`), saved in
  graphics.cfg under [controls], and in no preset: moving it never flips to Custom.
- **Pause menu**: Resume, Save game, Settings, Exit to title (saves first), Quit
  to desktop (saves first).
- **Saves autoload** (`scripts/save_system.gd`): 4 slots in user://saves
  (`store_var`, written to a .tmp and swapped in). Autosaves every 60 s of
  unpaused play and on `Saves.request(reason)`: anchor attuned, puzzle solved,
  shard won (chest opened / mimic killed), shards set in the door, boss killed,
  and once at the start of a new game so the slot shows. A save waits until it
  is safe: never in a cutscene, dead, hidden or waking (a shard in flight to the
  door is in neither the pack nor the door).
- **What is saved** (maze.gd `save_state`): the seed (the level is rebuilt from
  it), the player (`player.save_state`: position, yaw, pitch, health, every
  inventory slot, the slot in hand), the active anchor, the map and its
  checkpoint snapshot, kicked doors, looted cages, emptied coffins (by their
  order in the tree, which the seed fixes; unnamed nodes get run-dependent
  names, so paths cannot be used), each puzzle room's solved/looted, the shard
  door, and `boss_defeated`. **The boss now stays dead** once killed (he used
  to respawn on every death). Not saved: enemies (repopulated, as after a
  death), item drops lying on the floor, cooldowns.
- **Loading**: `restore_world` runs BEFORE `_populate` (so a dead boss is never
  spawned and a kicked door never arms), `restore_player` AFTER it (because
  `_populate` forgets the mimic, which a solved room puts back). A solved room
  is restored to its finished look (levers set / load on the scales / mirrors
  aligned / bells rung, plinth up, the chest open or the reward waiting).
- Harness trap: point `Saves.save_dir` somewhere else (and put back any setting
  you touch), or a test run writes into the player's own slots.
- Measured in a harness (31/31): title up; a slot started a new game and was
  written at once; autosave on the clock; a requested save held through a
  scene and written after it; Save game from the pause menu; Exit to title; the
  slot card's summary; loaded the same seed, the player 0.00 m from where they
  saved, same facing, health, coins and shard, the anchor, door 5 kicked (door 4
  still shut), cage 2 looted (cage 1 not), coffin 3 empty (coffin 2 not), the
  solved room with its plinth up, the door's sockets, the boss still dead, the
  map; sensitivity doubled the look and was written to graphics.cfg; delete.
- **Saving revised (2026-10-09, at the user's request)** -- supersedes the event
  saves above: the ONLY automatic save is the one every 60 s of play; the rest
  are by hand (pause menu Save game, or "Save and leave"). The `Saves.request`
  calls at anchors, puzzles, shards, the door and the boss are gone; the one
  `request` left writes a NEW game's slot once the player is up, so the named
  slot exists. Exit to title / Quit to desktop no longer save by themselves:
  they ask (Save and leave / Leave without saving / Cancel) and say how long ago
  the last save was (`Saves.since_saved`).
- **New games are named** on the title (LineEdit, `Saves.NAME_MAX` 24, trimmed,
  empty -> "Game N"); `Saves.game_name`, kept in the slot's meta.
- **A slot card shows only the game's name, the zone and when it was saved** --
  deliberately no shards, puzzles or play time (play time is still stored).
- **Zones**: maze.gd `zone` (this level is 1), `ZONE_NAMES` {1: "Zone 1"}
  (placeholder), `zones_cleared` (a zone's boss killed; saved), `zones_open()`
  (1 and every zone after a cleared one). Nothing reads `zones_open` yet: the
  zones after 1 are not built -- the user will start them when zone 1 is done.
- **A new game starts with the player getting up** off the cell floor
  (`player.wake_up()` = the respawn's wake), only when started from a slot; a
  loaded game and slotless runs (benchmark, harnesses, --skip-title) start
  standing. Harness trap: the first frames of a fresh level are slow, so the
  wake takes longer in real seconds than WAKE_END -- wait on `is_waking()`.
- Measured (20/20): an empty slot asks for a name; the game started with the
  player getting up, no control and nothing written meanwhile; the slot written
  once up with the trimmed name and "Zone 1" and no progress fields; no save at
  an anchor, a solved room, a shard or the boss; the boss's death cleared zone 1
  and opened zone 2; autosave on the clock; Exit to title asked and, left
  without saving, wrote nothing; a loaded game did not get up again and kept
  zone 1 cleared.
- **Into the game through black (2026-10-09)**: choosing a slot shows
  "DESCENDING..." for `LOADING_HOLD` 0.7 s, then the title fades to black over
  `LOADING_FADE` 1.0 s; the HUD's blackout starts at full black whenever there
  is a slot, so the level builds behind black. A new game's player gets up out
  of it (`wake_up` -> `_begin_wake(true)`), a loaded game fades in
  (`hud.fade_black_when_steady`). **Both wait for the frames to settle first**
  (3 frames in a row under 0.1 s, or 3 s): the level's first frame is a long
  stall, and it swallowed the whole 1.3 s fade -- black to clear in ONE frame,
  a cut. Measured: before, [1.0, 0.0] in one step; after, the get-up lifts at
  most 0.035 a frame over ~75 frames, a load 0.017 over ~59. The wake's own
  clock is also capped at 0.05 s a frame so a later stall cannot skip it.
- **Torch flame tips fade out** (2026-10-09, `shaders/torch_flame.gdshader`): the
  tongues used to reach the top of the 0.72 m flame card still bright and stop
  in a straight line there. Heat now burns out between `burnout` (0.58-0.78 of
  the card, moved by slow noise so the cut-off is never level) and 0.96, so the
  tip thins and cools through the ember reds to nothing. The flame reads ~10%
  shorter; the card (torch.tscn Mesh_flame) can be made taller if that is missed.

## 20. The skeleton archer (2026-10-09)

- **`scripts/archer.gd`** extends enemy.gd. The maze puts it on an `enemy.tscn`
  instance BEFORE it enters the tree (`set_script`), at the back of a skeleton
  pack of 2+ with chance `archer_share` 0.5 (7 in the test level) -- never
  alone, so it has fellows to hide behind. Its numbers are in `_init` (a script
  swap drops the scene's overrides): 60 health, move 3.3 (slower than the
  player's 4.25), vision 140 deg, punch 8 when touched.
- **enemy.gd hooks**: every skeleton joins group "skeletons"; the chase calls
  `_chase(...)` (default false) after the wander/out-of-reach handling, so a
  kind can hunt its own way and fall back to the swing by returning false.
- **Shooting**: draws for 0.85 s (the bow comes up, string back, arrowhead
  brightens), looses when it has a clear line through stone (allies do not
  block), next shot 3-4.5 s after. **Distance**: backs off below 8 m along the
  navmesh (5 headings, best one further away), comes on beyond 17 m or with no
  line; slower than the player and stopped by corners, so it is caught.
  **Cover**: with a non-archer skeleton within 12 m it goes to stand 1.6 m
  behind it on the far side from the player, and only draws once settled there
  (or 1.5 s overdue) -- drawing mid-way left it standing in the open.
- **Arrows** (`scripts/arrow.gd`): 26 m/s, straight. The player and the archer
  are tested as capsules (`Geometry3D.get_closest_points_between_segments`), not
  by layer -- the player shares layer 1 with every skeleton. The hit is
  `take_damage(15, travel, proxy)`, so the guard applies: blocked, it falls
  aside (1.5 through); **parried, it homes back on its archer at 30 m/s and
  hits for the FULL 15** -- the player's own half-reflect lands on the `Proxy`,
  which takes nothing (and sits 1.3 m below the arrow, because the guard flash
  is placed 1.3 m above an attacker's origin). Stone stops it; it sticks 6 s.
- **The aim pose is code** (the rig has no bow clips): `_point_bone` turns a
  bone's +Y onto a direction with `set_bone_global_pose`, blended by `_aim`;
  left arm along the shot, right elbow out and back, hand to the jaw. The bow
  is procedural (arc of boxes, string spans, nocked arrow) placed at hand.L.
- Measured (harness, real right-click parry): 7 archers spawned; arrows 3.05-
  4.3 s apart, every hit 15; held off at 13.9 m; a parried arrow took exactly
  15 off its archer; a held guard let 1.5 through; backed from 4 to 9 m from a
  player standing still; chased with the keys, caught (0.8 m); with a fellow
  between, it stood 2.3 m behind it at 0.97 alignment. Posed bones measured:
  hand.L 0.70 m out along the shot, hand.R beside the jaw.

## 21. A bigger maze with rooms far apart (2026-10-09)

- **The map is ~3x the corridor**: `module_extent` 92 -> 150, `module_grid` 33 ->
  53, `module_dead_ends` 44 (was `organic_dead_ends` 16, still used by the
  organic mode). Measured over 80 seeds: ~1,090 cells (887 corridor, was ~283).
- **Rooms are spread out** (`module_maze._choose_rooms`): each chest room goes
  to a junction far from every room already placed -- chosen at random among
  those scoring within `SPREAD_SLACK` 0.5 of the furthest -- with at least
  `module_room_gap` 7 cells between blocks (relaxed a cell at a time if the map
  cannot fit them). Pure farthest-point (0.8) put every room on the rim, a
  pattern a player can learn; 0.5 puts ~2 of 6 inside. Rooms used to sit on the
  graph's chambers one cell apart: closest pair 2-11 cells' walk.
- **At most `module_room_entrances` 2 doorways per chest room**
  (`_limit_entrances`, also used for the boss's one): corridors that ran
  THROUGH a room (up to 9 doorways before) are walled off and dug round it.
  Trap: close doorways and drop stubs in one pass, dig in a SECOND -- interleaved,
  a corridor dug for one doorway ran through the stub behind the next, and
  dropping that stub stranded what it had just rejoined (2 seeds in 30).
- **The start is far from every room** (`module_level._pick_spawn`): the dead
  end maximising min(walking cells to the nearest room, 3x the straight-line
  cells), boss depth breaking ties. Walking alone once put it 4 cells through
  the rock from a puzzle room. Measured over 40 seeds: >= 26 cells' walk and
  >= 8 cells straight from any room (was as close as 2 cells' walk).
- Result over 80 seeds: closest two rooms >= 12 cells' walk (mean 18.6), every
  seed 100% connected, every chest room <= 2 doorways.
- **Enemies follow the corridor**: `enemies_per_corridor_cell` 0.25 (72 over the
  old 283 cells) -> ~220-230. Spawn candidates now also skip tiles TOUCHING a
  room (`_touches_room`): a pack scatters 1.3 m, and from a doorway that put 2
  of 229 inside a puzzle room. Anchors (5) are still a fixed count.
- **Hiding places follow the corridor too**: `hiding_spots_per_corridor_cell`
  0.064 (18 over 283) -> ~58. The spread (farthest-point) keeps each spot's
  nearest-chosen distance and updates it per pick (spots x count, not x count^2).
  Measured: nearest pair 22-24 m apart (51 m with 18); from a corridor cell to
  the nearest, mean 13.0 m / worst 32.8 m (was 26.1 / 54.4); all reachable;
  same-session bench 122.2 -> 119.9 fps, worst p99 12.50 both, load +0.1 s.
- **Harness trap: Godot's path search gives up on long routes.**
  `NavigationPathQueryParameters3D.path_search_max_polygons` defaults to 4096;
  across this map a path of ~350 points stops 7-44 m short and reads as
  "unreachable" (8 of 58 hiding places). Set it to 0 (unlimited) in a test.
  Also wait for the navigation map to sync after `level_built`: queried at
  once, every path came back empty and every target read as unreachable.
- **Respawn waits for steady frames** (`_respawn` -> `_begin_wake(true)`): the
  reset respawns every enemy in one frame (~480 ms here, 171 ms on the old
  map), and that frame jumped the get-up fade 36% at once; held, the largest
  one-frame step is 1.3%.
- Measured, RTX 3060, editor closed: load to `level_built` 9.2 -> 14.4 s;
  bench 3440x1440 (preset 1, scale 1.0) OLD 132.7 fps / worst p99 12.12 ms /
  1369 MB, NEW 123.3 / 12.20 / 1390 MB, physics 1.8-3.0 -> 3.4-4.3 ms (the
  enemies). Stations land in different spots per layout, so per-station rows
  are not like for like. Not benchmarked on the P620.

## 22. Warden bots and the chest rooms (2026-10-09)

- **The puzzle rooms are no longer built.** `maze._build_puzzle_rooms` now builds
  `scripts/dungeon_room.gd` (group "chest_room"; maze.gd still keeps them in
  `_puzzles` and saves them under "puzzles"). `puzzle_room.gd` is left on disk,
  unused. Kinds: `prison_rooms` (2) PRISON BLOCKS, chosen by the seed and never
  the mimic's room; the rest `vacant` -- a dais with the chest (or the mimic) --
  until the user picks designs for them. Nothing seals any more: `sealed` is
  always false, `is_warding` never true (stalker.gd reads group "chest_room").
  The rooms' `on_world_reset` is now called from the END of `_populate` (after
  the corridor intruder count), so the first build gets it too.
- **The prison block**: two rows of four barred cells across the court (FRONT
  4.4 m from the centre, cells 2.5 x 2.7 x 2.9 m), a generator in the aisle on a
  red crystal (red omni, pistons, flywheel), brass conduits, a red lock lamp
  over every door, three warden bots posted in the aisle facing the cells
  (`POSTS`: x, z, row watched), guard-boxed to the room (`aggro_box_*`). Five
  cells hold a prisoner (the skeleton model playing idle, eyes attached), one
  is the LOCKER with the room's shard chest (`chest.locked` until the power is
  cut) and crates, the rest bones. Entering (1.8 m inside the block) alarms the
  wardens. All destroyed -> `wardens_down` -> E on the crystal: it flies to the
  player (`red_crystal` item), the generator gutters out, the doors swing OUT
  into the aisle (hinge +X along the door; a turn of a about Y takes +X to
  (cos a, 0, -sin a), so back row -1.75, front row +1.75 -- the first sign was
  wrong and the test proved it), door collision off, each decor prisoner is
  swapped for a real enemy (`maze.adopt_enemy`) that comes out alerted, and the
  chest unlocks. Bars are layer 1 only (they do not block sight); the doors'
  collision is armed on `level_built`, after the bake, so cells stay in the
  navmesh. Deaths: wardens come back unless all were destroyed; a cut
  generator stays cut; prisoners let out and not yet killed are back in their
  open cells. Save: kind, looted, wardens_down, powered_off, prisoners_down,
  freed_alive (cell indices).
- **Warden bots** (`scripts/warden.gd`, extends enemy.gd, group "wardens";
  display "WARDEN BOT" -- the boss is THE WARDEN, these are his machines). Put
  on an enemy.tscn instance like the archer; `_enter_tree` throws the skeleton
  away and builds a crude robot from primitives merged per rigid part (static
  mesh cache, one surface per material: hips, thighs, shins, torso barrel with a
  caged gold crystal, box head with a gold lens, a beam arm ending in a crystal,
  a club arm), animated in code (stride, bob, head, arm aim, club swing). The
  chest crystal is the first mesh, so enemy.gd's state material IS the crystal
  material; every crystal shares it. 240 health, 2.7 m/s, knockback resistance
  0.85, club 22, capsule r 0.55 h 2.25. Drops `gold_crystal` (0.6) or a potion.
- **The beam**: clear line through stone (2|256; its fellows do not block) and
  within 20 m -> CHARGE 0.65 s (thin aiming line, crystals flare) -> FIRE up to
  3.2 s, swinging after the player at 0.95 rad/s, the player tested as a capsule
  -> `player.beam_hit(5, delta, dir)`: 5 a second paid by the tick, no
  invulnerability window, slowed to `beam_slow` 0.45 (0.725 behind a raised
  guard, which takes `block_damage_taken` 0.1 of it; ghosts 0.2), spills a
  drink, damage marker every 0.5 s; HUD gold edge glow (`hud._update_beam_glow`,
  `player.beam_amount()`). VENT 1.6 s. Between beams it holds its ground inside
  12 m (it does not walk into melee; it clubs if you come to it). The drawn beam
  stops 0.8 m short of a player it is on and has no flare there, and the tubes
  taper with no caps: drawn to the chest it filled the bottom of the view as a
  gold wedge ending in a flat disc.
- **One with every skeleton pack** (`maze._spawn_pack` -> `_spawn_warden`,
  `wardens_with_packs`, aggro 22): beside its escort (the pack's first) on the
  side furthest from the rest; it does NOT collide with its pack
  (`add_collision_exception_with`) -- two sentries side by side walled it in
  7.6 m from its escort -- and steps aside to `PACK_ROOM` 1.2 m when awake.
  Idle it follows its escort along the navmesh when further than 3.6 m.
- Measured (35/35): 44-50 pack wardens, every corridor skeleton within 4 m of
  one at spawn, nearest pack-mate 0.78 m at spawn / >1.8 m awake; escorts moved
  ~8 m along their corridors, every warden back within 3.6-4.0 m in 8 s; beam
  first fires 0.73 s after spotting, exactly 5.00/s while firing, fires again
  after venting; walking under it 1.91 m/s (4.25 free); guarded 0.50/s; stone
  stops it; prison: 8 cells / 5 prisoners / 1 locker, doors solid after the
  bake, alarm wakes all three, no crystal until they fall, E takes it, 8 of 8
  doors out into the aisle (control with the sign flipped: 0 of 8), no door
  collision left, 5 prisoners out and 4+ walked clear in 4 s, chest unlocked;
  death after the power cut: 4 loose back, no wardens; death with wardens
  standing: all 3 back; a saved state restored into the other prison. Bench
  (RTX 3060, 3440x1440): 121.2 fps, worst p99 12.50 ms, 1381 MB (same-session
  before: 122.2 / 12.50).
- **Harness traps**: the Remnant kills in one blow whatever the health; over a
  long test it finds the player, the world resets and every enemy under test is
  freed ("previously freed" errors mid-test). Set `stalker_enabled = false`
  before adding the scene. And place a measuring spot relative to where the
  enemy IS -- a warden that had been hunting stood 2 m from a spot computed off
  its post, so it clubbed instead of beaming and the beam "never fired".

## 23. Haul convoys (2026-10-09)

- **`scripts/convoy.gd`**, spawned by `maze._spawn_convoys` on every repopulate
  (in `_spawned`, so a death sends fresh ones out): a wheelbarrow cart of gold
  coins and red and gold crystals moved round the corridors by three skeletons
  -- one PUSHES at the handles, one PULLS a rope in front, one STEADIES the load
  at the side -- with a warden bot walking behind. Lore: refinery to
  consolidator; neither exists yet.
- **The road never nears a dead end** (`network`): the corridor graph without
  rooms, courts or shut doors (`Built.doors` edges), every cell with fewer than
  two ways on peeled off until none is left (the 2-core), then only the LARGEST
  connected piece kept -- rooms and doors split the loops, and a convoy started
  on a 6-cell loop had nowhere to go. 79-168 loop cells per seed of ~900
  corridor cells. `convoy_count` 4 but one per `convoy_loop_cells` 40 of loop.
  Legs are BFS paths of 8-26 cells (3+ if hemmed in), never back the way it
  came, joined on 14 m before the road ends (Chaikin-smoothed cell centres,
  arc-length lookups, cell lengths cached per smoothing -- searched per cell
  per tick they cost ~1 ms a frame). It may stand 2-4 s at a leg's end.
- **Convoys never meet**: each CLAIMS its road from behind its warden to the
  road's end (`claimed`); legs are planned off other convoys' claims, and with
  none clear the convoy waits at the end of its road and retries every 0.5 s
  (taking a claimed leg anyway sent two head on). A cart or warden on its road
  just ahead holds it (guard, 5 Hz). Starts >= `convoy_start_clear` 45 m from
  the player and each other, on unclaimed road, or not at all.
- **The crew are real skeletons with `enemy.hauled_by`**: enemy.gd skips its AI
  and physics for them (`_haul_anim`: walk/idle at `haul_speed`, then
  `convoy.pose_hauler` points the arms). The cart is steered like a barrow:
  axis from the pusher's road point to the wheel's (placed by its centre, the
  handles swung 0.5-0.8 m off the pusher's hands on bends; now 0.15 m). The
  steadier keeps to whichever side is clear (`_slot_clear`: road rays 4.5 m
  ahead and body-radius rays at its spot now and 3.2 m on), crossing IN FRONT
  of the wheel, or drops in line behind the pusher -- coffins stand 0.7 m into a
  corridor and it walked through them. Its checks run only within 40 m of the
  player. The cart is an AnimatableBody (layer 1; crew and warden excepted).
- **The warden** escorts a marker 4.6 m behind the cart. Asleep (enemy
  dormancy) it is carried on the marker -- otherwise 55 m behind in a minute;
  awake it stops colliding with any enemy it bumps (a sentry pack held it 14 m
  back) and is put back on its mark if > 8 m off and out of the player's sight.
- **Set upon** (`_set_upon`, 5 Hz): a crewman hurt, alerted (a kicked door) or
  gone, the warden engaged, the player within 4 m of any of them, or seen within
  16 m in the puller's 140-degree cone with a clear line -> `_let_go`: the crew
  are released (`hauled_by` null, home where they stand) and alerted, the
  warden too; the cart stays. E on it (`Interact.looked_at`) takes 20-40 coins,
  1-2 red and 1-3 gold crystals; the load disappears. `broke_because` says why.
- **Cost**: the cart is five meshes shared by every cart (body, wheel, coins
  MultiMesh, red and gold crystals; ~28 pieces was ~30 draws a cart) with a
  50 m visibility range, and a convoy > 60 m from the player moves at 10 Hz.
  A/B/A (RTX 3060, 3440x1440, editor closed): 118.2 / 116.7 fps with, 119.7
  without; worst p99 13.50 / 11.80 vs 12.08 (noise).
- Measured over six seeds: every convoy moved 50-61 m a minute, 0 of 480 cart
  samples off the loops, no dead-end cell on any route, crew clear of stone
  with the player near, carts never closer than 7 m (once the claims were in;
  before: 0.4 m), pusher's hands 0.15 m from the grips, warden within 8.2 m;
  seen from in front -> dropped in 0.02-0.2 s, a player 14 m behind unnoticed,
  a crewman hit -> dropped, all three crew and the warden then hunting; looted;
  a death -> a fresh set out. Harness traps: a blow lands inside the player's
  invulnerability window when other enemies are hitting them -- kill with
  `kill_in_scene`; and the steadier's checks are skipped far from the player, so
  test them with a stand-in "player" near (30 m above) each cart.


## 24. Stagger, skeleton swords, patrols, the hand torch, the crystal mine (2026-10-10)

- **Stagger is a roll per hit** (`player.knock(body, impulse, stun, chance)`;
  stun floored at `stagger_min_time` 0.45). A stagger shoves the enemy and
  cancels its attack (`enemy._staggered`: wind-up / swing / recovery dropped,
  `_on_staggered` -- the archer loses its draw; the warden's beam already drops
  when stunned) and it lurches away from the blow (`_flinch`, a tween on
  `visual.rotation`). A blow that does NOT stagger hurts but neither moves nor
  interrupts. Chances: sword cut `slash_stagger_chance` 0.4, spin and slam 1.0;
  spear stab `STAB_STAGGER` 0.1, dash and the thrown spear's blast (its heavy)
  1.0. Poise-bearers (the boss) keep their hyper-armour. Measured: 120 real
  cuts -> 38%, 200 real stabs -> 7-11%; chance 1 mid-wind-up -> back to CHASE,
  no blow, winds up again; chance 0 -> the blow lands.
- **Spear stab effort**: walking at `spear_stab_move_scale` 0.45 while a stab
  is out (4.25 -> 1.91 m/s measured), and `_stab_effort` -- push 7 cm forward,
  dip, nod, shoulders rolling to alternate sides (`spear.stab_side`), FOV drawn
  in 2.6 deg (72.4 measured) and a strain tremor that builds while it is spammed
  (`_stab_strain`). Composed in `_update_head` / `_update_dash_view` (the FOV
  early-out includes `_stab_fov`).
- **Skeletons carry swords** (`scripts/skeleton_sword.gd`; enemy.gd `armed`,
  `weapon`), and the SWORD is what hurts: the blade swept from last tick to this
  one vs the player's capsule, once per attack (`_sword_connect`). The right arm
  is posed in code over the clip (two-bone reach + hand along the blade, blended
  by phase): cut = high on its side down across, charge = overhead chop, lunge =
  thrust, spin = arm out. A cut steps in (`_attack_step`, up to 4 m/s, to a
  0.45 m gap). Archers, wardens and prison prisoners are unarmed (old reach
  test); miners carry a PICK. Traps: posing must run only on ticks the rig was
  advanced (`_anim_stepped`) or the blend compounds; `_play_state_anim`'s
  `seek(0, true)` re-poses the whole rig from the new clip, so it re-runs the
  arm (one glitch frame per cut before); the sword is a CHILD of the body,
  re-placed only on rig steps (it followed the hand to 2 cm). Measured: stood in
  front 14/14 per blow, only during ATTACK; stepped back as it cut 0/4; behind
  it as the cut starts 0/3 (control, the old reach test: 3/3).
- **Scenes use the weapon in hand** (`player._scene_weapon`, `scene_reach()`,
  `spear_scene_pose()`): the cage stab and the bomber haft strike pose the spear
  instead of drawing the sword when the spear is held (driven through the skull
  tip 0.138 m past; the BUTT into the bomber). The spear's TIP_REACH 2.07 vs the
  sword's 2.08 keeps the cage stand-off. **Cage scene hands back control the
  frame the skull bursts**; the coins fly after and are paid on arrival.
- **Packs patrol** (`scripts/patrol.gd`, maze `patrols`): every corridor
  skeleton pack walks in a column -- leader on navmesh legs of 14-40 m between
  corridor points, followers on its trail, the warden at the back -- and fights
  as ever when it sees the player. Traps, all measured: a follower's goal on a
  short trail was the leader itself and the pack leant on each other and stood
  still (4 of 49 patrols) -> extrapolate behind the heading; a follower in front
  of its leader in a corridor jammed both -> members pass through each other
  while both march, solid again in a fight; routes through shut wooden doors
  (the navmesh runs through them; group "wood_doors") are refused. Result: 49 of
  49 leaders and 178 of 178 members moved > 12 m in 30 s, moving 94% of
  samples, 0 off the navmesh. `archer_share` 0.85 (+ `second_archer_share`
  0.45 in packs of 4+): 89% of 2+ packs measured.
  **Shipped with the freed-object trap** (section 4): killing a patrol's leader
  passed the freed body to `_alive(m: Node3D)` -- a script error every tick,
  seen in play, missed because no harness killed a patrolling enemy. `members`
  and `_leader` are untyped now and `_prune` drops the dead. Test: 43 members
  of 12 patrols killed leader-first while marching, then a death and respawn:
  0 errors; control with the typed parameter put back: 180.
- **Hand torch** (`scripts/hand_torch.gd`, under the camera): `torch.tscn`
  without its bracket, light or embers, at SCALE 0.1 / DEPTH 0.17 placed from
  the frustum each frame (`CORNER` -0.975, -0.86) -- the flame's tongues and the
  head at the far bottom-left, left of the HUD bars. On screen the flame is
  ~0.47 x SCALE / DEPTH of the view height (0.3 filled 83%). Traps: torch.gd
  turns embers back on with the effects knob, and paused they froze into one
  big glowing block -- free them before it enters the tree. No light: per-pixel
  cost over the whole screen, and it would change the corridors' look.
- **The crystal mine** (`dungeon_room.gd` kind "mine", maze `mine_rooms` 1, never
  the mimic's room): a faceted rock face (`_rock_mesh`, flat-shaded noise
  sphere, `rock` material; smooth-shaded it read as orange clay) with gold/red
  crystal seams, 3 electric drills (spinning bits, sparks with effects, brass
  cables to the generator), 4 miners at the face + 2 at an ore heap by a cart on
  rails (decor skeletons swinging picks on `attack_1/2`, ball and chain), 2
  wardens. The generator runs on the room's SHARD (its colour). Entering raises
  the alarm and every miner is let loose with its pick; with wardens AND miners
  down, E takes the shard (no chest here) and the drills spin down. Deaths:
  wardens back unless all destroyed; killed miners stay dead, the rest back at
  work. Saved: `miners_dead`. Measured 16/16 (harness trap: the room's block is
  15 m from its centre, so "4 m outside the court" is inside the alarm).
- Bench (RTX 3060, 3440x1440, editor closed): 102.5-103.1 fps, worst p99
  15.7 ms, 1386 MB; with `patrols` off 107.3 / 13.8 (earlier today, before this
  wave: ~118-121). The patrols cost ~4 fps, mostly physics at the chest-room
  station; the rest of the drop is CPU (cpu ms ~ frame ms) and was not pinned
  down -- the swords measured as nothing. Not benchmarked on the P620.
- **HUD: health under the hotbar, attack icons on the left** (hud.gd
  `_layout_health`, laid out in code so hud.tscn is untouched): the health bar
  is the hotbar's width (570) centred under it, numbers on the bar, the ghost
  bar under that; the hotbar is raised to `HOTBAR_BOTTOM` -62 (the held-item
  label and drink bar follow it). The orange slam bar is hidden. A ROW at the
  bottom, `GAP` 18 px left of the hotbar / health bar, its foot level with the
  health bar's (placed at the user's request after a left column, then a
  bottom-left column): `scripts/attack_icons.gd` (an HBoxContainer), three
  rounded tiles for the weapon in
  hand -- heavy (F), mid (Q), regular (LMB) -- with drawn glyphs and the
  hotbar's cooldown look (shade draining down, whole seconds on cooldowns of
  1 s+, a rim flash when one comes back). Data: `player.attack_cooldowns()` /
  `spear.attack_cooldowns()` as [kind, seconds left, of how long, key], -1 =
  unusable (the spear in flight). The sword's cut and spin have no cooldown of
  their own: their tiles show the stroke in progress (to `_bite_end` /
  SPIN_TURN) and the slam recovery. Measured: swapping to the sword and back,
  the throw counted 0.92 s down over 0.93 s; the slam kept counting while the
  spear was out; hidden with the potion in hand. Trap: a Label reparented with
  `set_anchors_preset` keeps its old offsets (sat left of centre) -- use
  `set_anchors_and_offsets_preset`. The hand torch's `CORNER` went to -1.15
  once the health bar no longer hid that corner.

## 25. Wheels instead of the hotbar; controller; thrown into stone; the mine's calm (2026-10-10)

- **Thrown enemies meet the real stone** (enemy.gd `_thrown_move`): while a
  knockback or stagger carries a body, its mask gains layer 9 (the player's
  exact walls) for that move only. Its own boxes (layer 10) come from the grid
  and miss arcade piers and arch jambs, so shoves put skeletons into pillars.
  Measured: 40 bodies thrown hard at the nearest exact stone -- 0 inside it;
  control with the mask off: 19 of 40 inside.
- **The mine no longer alarms on entry.** Its wardens wander a patch of court
  in front of the face (`_watch_spots`) inside a room-sized aggro box and fight
  only on SIGHT. enemy.gd: a guard with a wander patch now strolls it while the
  player is outside its zone instead of walking home and standing (a leash
  first used here pinned them at their posts whenever the player was > 20 m
  off). Miners keep working until the last warden falls (`MINERS_TURN` 2.5 s
  later, all turn) or one is struck at its work: each working miner has a
  `MinerHit` StaticBody3D on the damageable layer (3) only, so swords, the
  spear and blasts reach it; struck, it becomes a real enemy that takes the
  blow. Measured 9/9 (wardens 2-5 m strolled in 10 s, sight -> engaged, cut on a
  working miner turns only it, 4 working -> 0 by 3.5 s after the last warden).
- **The hotbar is gone; two wheels replace it** (inventory.gd, radial_menu.gd).
  Slots 0-3 are the WEAPON wheel, 4-7 the QUICK ITEM wheel (up 1, right 2,
  down 3, left 4), 8-37 the bag (SIZE 38). `slot_accepts`: weapons only on the
  weapon wheel, consumables only on the quick wheel; `add` puts new weapons /
  potions straight onto their wheel, everything else in the bag. Old saves
  (39 slots) are re-added through `migrate`. `player.selected_slot` is the
  weapon-wheel slot in hand. Hold C (or R3) for weapons / R for quick items,
  aim with the mouse (travel accumulated and swallowed, so the view does not
  turn) or the right stick, release to equip / use; an empty slot or no aim
  does nothing. D-pad uses quick items 1-4 directly. Walking continues while a
  wheel is up; looking and attacking wait (`player.wheel_open`). Set up in the
  inventory (now V / Y): the character panel shows both wheels as diamonds.
  There is NO shield weapon (the user's list named one): the wheel holds the
  sword and spear, the rest empty, by the user's choice.
- **Controller** (project.godot): move left stick, look right stick (player
  `_pad_look`: squared response, `pad_look_speed` 3.4 rad/s x the sensitivity
  setting), RB light, RT medium (spin / dash), LT heavy, LB block/parry, R3
  weapon wheel, L3 ghost, d-pad quick items, A jump, X interact (not in the
  user's list), Y inventory, Select map, Start pause. Inventory on a pad: d-pad
  moves a cursor between slots by screen position, A lifts and A places, X
  sends a stack between bag and wheel, LB / RB change category, B / Y close.
  Pause / title menus focus a button for pad navigation. Attack icons switch
  their labels to RB / RT / LT when a pad was used last.
- **Traps**: this Godot's built-in `ui_accept` / `ui_cancel` have NO joypad
  buttons (d-pad and stick are in ui_up..ui_right) -- they are defined in
  project.godot with A / B added. A focused Button swallows "ui_cancel" before
  `_unhandled_input`, so the pause menu and title read it in `_input` (Escape
  stopped closing the pause menu once its Resume button had focus). Mouse
  travel arrives scaled by the window's stretch (half in a 2x window): the
  wheel's `DEAD_ZONE` is in canvas pixels. A Control made full-rect with
  `set_anchors_preset` alone stays zero-sized (the wheel drew round the
  top-left corner). Measured 26/26 + 7/7 driving real pad events
  (parse_input_event): both wheels by mouse and pad, d-pad drink, stick look,
  RB/RT/LT/LB, L3, A, Select, Start / B, Y, pad cursor, slot rules, migration.

## 26. Death autosave, the marked map, pad cursor and keyboard, hiding carts (2026-10-10)

- **Keys**: inventory Tab, map ` (KEY_QUOTELEFT), quick wheel X. (The pad's X
  is still interact.)
- **A death autosaves**: player `_die` -> `Saves.request("death")`, written by
  the existing "when safe" rule -- after the respawn and the getting-up, so the
  slot holds the world as the death left it. Toast "Autosaved".
- **The map draws no icons** (junctions, rooms, gates, hiding places removed;
  walls, floor, centreline and the player's arrow stay). The full map is worked
  with a cursor: mouse freed and `player.ui_open` held while open; wheel /
  right stick zooms about the cursor (1-10x of the fit), drag pans, a click
  marks the map: an editor (note <= 48 chars, 8 colours, pin / cross / ring)
  opens; a click on a mark edits or deletes it. Marks are world x, z
  (`_pins`), drawn on the full map (note shown on hover) and the minimap, saved
  as "pins" in the slot, and NOT cleared by a death's map reset. The editor
  sits in the top half and the hints along the top, clear of the keyboard and
  the HUD. Inventory and map refuse to open over each other.
- **`Pad` autoload (scripts/pad.gd)**: `using_pad` (last device touched);
  `want_cursor(owner, on)` -- the inventory and the full map ask for it. While
  wanted and a pad is in use: a drawn arrow, left stick / d-pad moves it, A is
  the left mouse button. Its moves and clicks are sent as REAL mouse events
  (`parse_input_event`, device 77 so they are not taken for the real mouse,
  positions through `get_final_transform()` to window coordinates), so hover,
  click and drag-and-drop work in screens that know nothing of it; the OS
  pointer is hidden meanwhile. The inventory's old slot-stepping pad code is
  gone. The map pans when the cursor is pushed against its edge.
- **On-screen keyboard** (`Pad.attach_keyboard(line_edit)`; on the map note and
  the title's game name): pops up when the box takes focus with a pad in use.
  Focus-navigated keys (A types), B deletes, X space, Y shift, Start / Done
  finishes (emits text_submitted and moves focus on). Its CanvasLayer is put
  LAST under the root (`pad_keyboard_input.gd`), so it reads B before the
  screen behind it would close.
- **Hiding places are lidded carts** (hiding_spot.gd rewritten): the convoy
  barrow scaled up for a person to lie in (tray 2.0 x 1.0 m, rim 1.0 m, wheel
  past -X, handles past +X, 3.3 m overall), plank lid hinged along the back
  edge: open -1.42 rad to climb in / out, -0.3 when peeking, shut otherwise.
  No skeleton, usable from the start (`is_empty()` always true;
  `restore_emptied` is a no-op for old saves). The maze's no-spawn patch is now
  1.8 x 0.8 m along the wall. **Convoy carts have a lid too**, shut while
  hauled (the load sunk `LOAD_DROP` 0.18 under it), thrown open when looted.
- Measured 29/29: keys; map open/close, scroll zoom, click-to-mark (mark lands
  0.0 px from the click), edit, drag-pans-not-clicks, save / death / load of
  marks; pad cursor shows and moves, right stick zooms both ways, A opens the
  editor, the keyboard comes up, A types "qq", B deletes to "q" without
  closing the map, Start finishes; inventory cursor; 58 carts, hide (lid shut,
  sight ray blocked), peek (lid -0.30), out; convoy lid; a death wrote the
  slot only once the player was up (save dir pointed elsewhere).

## 27. The brick kit: the corridors rebuilt from the user's photos (2026-10-10)

- **Same layout, new stone.** `module_maze.gd` still decides the cells;
  `scripts/brick_level.gd` (switched on by `module_level.brick`, set from maze
  `brick_kit`, default true; `-- --modules` builds the old Tripo tunnels for an
  A/B) assembles each cell from `models/brick/brick_kit.glb` (build:
  `tools/build_brick_kit.py`, see tools/README.md). The eight pieces were
  generated by Tripo from the user's reference photos (`models/source/
  brick_kit_refs/`): wall, wall with iron cage, pillar, pillar with torch,
  pointed arch, arched door, barrel vault, flagstone slab. 320 credits; 680 left.
- **A cell**: brick walls 3.8 m apart (`WALL_FACE` 1.9, 3.5 m high, 1 m thick);
  a barrel vault springing at 3.0 m to an inner crown at 5.1 m, cut into an L
  (corner), T (tee) and groin (cross) with a carved RIB over every groin line;
  a pointed arch (opening 3.38 m, soffit ~4.6 m, 1.2 m deep) centred on every
  open boundary -- it hides both cells' wall ends and vault ends; a pillar in
  each corner of a junction (0.9 m, at +-2.0); four 3 m flagstones on a dark
  bed; a dark lid (6.4-6.6 m) and dark "skirts" on every closed side, floor to
  lid. Dead ends carry a lunette panel over the end wall; exits (`gate`) carry
  the arched door piece. One wall in 9 is the iron-cage wall
  (`Built` meta "cage_walls"; torches and hiding carts avoid it).
- **Seamless, measured**: magenta void, flat light, 70 corridor cells x 18
  views. First build 698,135 magenta samples (cracks along the cut groins and
  a crescent beside every arch); ribs over the groins -> 259,708; vaults run
  INTO the arches (VAULT_HALF 3.03, they ended at 2.5) -> 89,499; the lid's
  skirts (the Tripo vault has a few real holes in it) -> 36, worst view 4.
  Trap: courts and skylights are MEANT to show sky -- lid them in the probe or
  it counts them.
- **Everything that measured the old modules was moved onto the new numbers**:
  torches are the kit's torch pillar standing as a pilaster with torch.tscn's
  flame/light on its carved torch (`module_level._pilaster_torch`; bracket,
  handle and head hidden); doors hang at the arch's junction mouth
  (`BRICK_DOOR_DEPTH` 2.38) with their torches on the junction pillars' inner
  faces; the spawn stands 0.2 m forward of the dead end's centre (door 2.18 m
  ahead, in reach); niches cut through `wall_niche` at the wall face 1.9;
  skylights' shaft runs 4.95-6.6 m (the vault is 1.3 m thick at the crown);
  the jail cell's walls are 1.9 out with its alcove 1.5 wide (no tally marks:
  they float over the deep mortar); anchors 1.1 m back.
- Collision is boxes (walls, arch legs, pillars, pilasters) on layers 2|256|512
  -- the player's exact layer and the enemies' simple layer are now the same
  shapes, since the pieces are flat panels. Measured: walked into a side wall
  and stopped 1.50 m out (face 1.9, capsule 0.4); navmesh paths reached 40 of
  40 corridor cells; reachability 100%; the spawn door kicks open.
- **Trap: a headless first import leaves textures uncompressed.** The kit's
  extracted maps came in as `compress/mode=0`; set to 2: video memory 1318 ->
  1020 MB (old kit 1391).
- **Cost (RTX 3060, 3440x1440, editor closed)**: with enemies 86.8 fps, worst
  p99 22.22 ms, 1038 MB (old modules, same session: 95.7 / 18.95 / 1411);
  without enemies (`-- --no-enemies`, new) 102.4 vs 121.6. It is GPU: measured
  render time 11.1 vs 9.2 ms at the same eight spots, CPU render time equal.
  `-- --brick-skip=piece,...` (new) leaves pieces out: walls -1.6 ms, pillars
  -1.1, vaults -0.6, floor -0.5, arches -0.35, lid/skirts/bed nothing. Thinning
  the pillars 3500 -> 1500 tris bought 0.3 ms; one collision body per chunk
  instead of one for the map bought nothing. Not yet found what makes the
  brick pieces dearer per pixel than the old modules; not benchmarked on a P620.
- Not rebuilt in brick: the boss hall, the morgue's and chest rooms' own
  props, the courts' paving (flagstones now) aside. The old `models/kit`
  modules and their code path are kept for `-- --modules`.
- **Anchors are placed by hand for the fixed seed** (2026-10-10): maze
  `anchor_marks` (world x, z, in the user's order) for `ANCHOR_MARKS_SEED`
  20260918 -- the level's `maze_seed`, so every game -- each take the nearest
  free dead end (the old spread-out placement is the fallback for any other
  seed). Measured snaps: 7.1, 1.0, 6.6, 14.5, 1.0 m. The anchor nearest the
  boss is no longer guaranteed. `screenshots/map_route.png` is the map with the
  room route and anchors, drawn from the save's seed.

## 28. Darker, Tripo carts / wood / doors, skull cages in the Tripo cage (2026-10-10)

- **Darker**: maze `module_torch_density` 1.0 -> 0.5, `module_ambient` 1.0 ->
  0.35, `module_torch_energy` 2.8 -> 2.2, and a brick door keeps one torch pair
  (its junction side) instead of two. Measured mean luminance at 12 fixed
  corridor spots: 0.0657 -> 0.0324 (-51%). Torches 643 -> 414 (128 at doors).
  Bench (RTX 3060, 3440x1440, enemies on): 91.1 fps, worst p99 19.56 ms,
  1002 MB (86.8 / 22.22 before).
- **New Tripo pieces** (text prompts, 40 credits each, 480 left), all in
  `brick_kit.glb` via `build_brick_kit.py`: `cart_body` + `cart_wheels` (a
  two-wheeled hand cart, exported at the convoy's size, wheels split off so
  they spin; axle at z 0.028, y 0.375) and `cart_lid` (the top boards of the
  crate Tripo returned for "a lid"); `wood_support` (snapped timber frame,
  2.4 m, against a wall), `wood_planks` (pile, 1.6 m), `wood_crate` (0.97 m).
- **Carts**: convoy.gd uses the kit cart at 1:1; hiding_spot.gd at
  `CART_SCALE` 1.368, so its numbers changed (tray 1.74 x 1.09, rim 1.3, base
  from -1.0 to +1.6) and the maze stands it `HIDE_FROM_CENTRE_BRICK` 1.05 off
  the corridor's middle (its wheels reach 0.82 m out). Both fall back to the
  primitive barrow without the kit.
- **Broken wood** (`brick_level.place_clutter`, from maze `_place_clutter`
  after the hiding carts, before the bake): straights only, not door cells, the
  spawn and its neighbours, hiding-cart cells, torch walls or cage walls; one
  roll per straight -- support 1 in 7, planks, crate. Support posts and the
  crate are solid (walls layer) and marked WALL in the grid; planks are not.
  ~24 supports, ~21 plank piles, ~14 crates.
- **Doors are the Tripo arched door**: `door_frame` + `door_leaf`, cut by
  `split_door` (the leaf ray-mapped from the front: 1.94 m wide, pointed head
  to 4.2 m, 0.16-1.0 m behind the stone face). `module_level._build_brick_door`
  hangs the node at the LEAF (`BRICK_DOOR_DEPTH` 2.38 + `BRICK_DOOR_LEAF` 0.58
  = on the boundary) so a kick from either side lands on it; one leaf
  ("LeafL"), jambs out to 1.8 m. The spawn stands 0.75 m forward of the dead
  end's middle to keep the door in reach.
- **Bone cages are the Tripo iron cage**: the niche cell's wall is `wall_cage`
  (no other cage walls any more), its gate cut free (`cage_door`, faces in front
  of y -0.46) and hung as bone_cage.gd's "Door"; the skull and loot sit inside
  the cage (0.77 x 0.78 x 0.35 m, `_brick_cage`, `_fill_niche(mid_override)`).
- Trap hit: the level is built before it is in the tree -- `global_position`
  on a fresh node errors and leaves it at the origin (all 33 cages were there).
- Trap (again): every new kit export brings new extracted textures as
  `compress/mode=0`; patch the `.jpg.import` files to 2 and re-import.
- Verified in a harness: cage aimed at + E paid 8, gate swung -1.80 rad; spawn
  door kicked open; hid in a cart and climbed out; convoys run with the new
  cart; all three wood pieces placed; clean run and title run silent.

## 29. Darker still, the Tripo torch everywhere, 5-piece doors, the domed prison (2026-10-10)

- **No torches at doors** (brick kit: `place_torches` skips `out.doors`).
  **Darker**: `module_torch_density` 0.4, `module_ambient` 0.12,
  `module_torch_energy` 1.7, court `SKY_LIGHT_ENERGY` 12 (was 22), `SKY_ENERGY`
  0.3. Torches 414 -> 208. Mean luminance at 12 corridor spots 0.0324 -> 0.0170
  (0.0657 two passes ago). Bench (RTX 3060, 3440x1440): 91.9 fps, worst p99
  18.75 ms, 1015 MB.
- **Every torch wears the Tripo torch** ("torch_mount", cut from the torch
  pillar by `cut_torch_mount` -- ring, handle and wrapped head, 1.44 m, ray-mapped:
  the pillar's face on that side is 0.31 m from its centre, not 0.45). torch.gd
  `kit_mount` (default true) hides Plate/Arm/Ring/Handle/Head and moves Flame,
  Halo, Embers and Light out to the kit torch's head. Off for the torch pillar
  (it has its own carved torch) and the boss hall's braziers. hand_torch.gd reads
  the moved flame position. Never put the old procedural body back.
- **Doors break into 5 uneven pieces**: `door_debris.pieces_for(mesh, cols,
  rows, slant, merge_top)` -- cut lines each tilted up to `slant`, the top row
  one piece; brick doors use 2 x 3, slant 0.55, merged top (wood_door
  `_split_for`, keyed on the leaf mesh's name "Boards"). Measured: 5 pieces.
- **The prison is a domed hall** (`dungeon_room._build_domed_prison`, brick kit
  only; the old block is `_build_block_prison`). The cells ARE the arcade: every
  arch round the court (one per non-corner ring cell, `_prison_bays`) is shut by
  a two-leaf Tripo jail gate ("jail_gate_l/_r", cut from the gate of Tripo's
  "prison cell" -- which came back as a little roofed hut -- and stretched to the
  brick arch's 3.36 x 4.55 m opening), and walls ("wall" + "wall_top") across
  every ring-to-ring arch split the arcade into cells; the doorway bays stay open.
  A brick band over the arches to `DOME_BASE` 8.35, a dark ring closing the
  corners, the Tripo dome ("prison_dome": came back on its side, stood up and
  normalised to radius 1 in `build_dome`) at `DOME_RADIUS` 8.5 with its oculus
  open; a red spot and a faint additive shaft fall through it onto the generator;
  four ember lights under the dome; a Tripo torch on every arch; four gibbet
  cages with skeletons on 14 m chains. The court's sky lights are removed
  (`_drop_sky_lights`). Cells carry "door" + "door2" and "open"/"open2"
  (relative swing); `_open_cells` / `_power_off_now` swing both. 11 cells per
  room here; 5 prisoners, 1 locker (the chest), the rest bones.
- Measured in a harness: 2 prison rooms, 11 cells each; cutting the power opened
  11 of 11 gates and let out 5 prisoners; a door kicked into 5 pieces.
- **Trap fixed**: `Graphics._apply_to_node` is called deferred and was TYPED, so
  any light or mesh freed before it ran (the prison removing the court's sky
  lights) errored "Cannot convert argument 1 from Object to Object". It is
  untyped now and skips freed nodes.
- Tripo: dome, cell bay (unused: a solid wall), cell (gate source) -- 120
  credits; ~360 left.
- **Lighting, second pass (2026-10-10, "way too dark... more torches, way less
  bright, increase the firelight effect")**: `module_torch_density` 1.1 (469
  torches), `module_torch_energy` 1.3, `module_ambient` 0.3, `TORCH_RANGE` 20 /
  `TORCH_ATTENUATION` 0.4 (wide soft overlapping pools). torch.gd firelight:
  `flicker_amount` 0.62, gutters more often and deeper, the light SWAYS with the
  flame (`sway` 7 cm, noise), its colour runs hot (HOT) as it flares and ember
  red (EMBER) as it gutters (`colour_swing` 0.35), halo 1.6x. Measured: mean
  luminance 0.0321 (2 of 12 spots near-black; 0.0147 with energy 0.85 and range
  15 -- doubling the count while halving energy left it DARKER). Cost: 79.9 fps,
  worst p99 23.64 ms (91.9 / 18.75 before); chest room 14.9 -> 19.8 ms. Lights
  are per-pixel: count and range are the levers if this must come back down.

## 30. Prison doorways, sticky quick slots, the centred map, pad inventory (2026-10-11)

- **The domed prison sealed its CORNER doorways.** A corner ring cell has no
  bay onto the court, and the cell walls either side of it shut it in: measured
  with a nav path + a walk on the player's own collision from outside every
  room entrance, 3 of 3 corner entrances into the prisons led nowhere (path
  ended 15 m from the hall). `dungeon_room._open_ring` now keeps every
  doorway's ring cell open AND, for a corner doorway, the bay beside it (no
  gate, no cell) with no wall between the two (`_open_pairs`, skipped by
  `_build_partitions`). After: 10 of 10 room entrances reach the centre.
  Test traps: the walk stops at the dais / generator in a room's middle (judge
  "within 2.6 m of the centre"), and the prison's wardens stand in the way --
  free them for a stone-only test.
- **Quick slots keep their item** (`inventory.assigned`, slot -> id): set
  whenever an item lands in a quick slot (`_mark`, run by `_changed`), kept
  when the last one is used (`take` / `remove`), cleared only by moving the
  stack out by hand (`move`, `quick_move`), putting another item in, or
  `unassign` (right-click on the emptied slot). `add` / `quick_move` send an
  item to the slot kept for it first, and no other item may take a kept slot
  (`_free_for`, also used by `room_for`). A run-dry slot draws its item with
  `ItemSlot.GHOST` tint and "0" (item_slot.gd, radial_menu.gd "(none left)");
  `ItemIcon.tint` is new. Saved as "quick_assigned" (`inventory.restore`).
- **The full map is moved, not pointed at**: the mouse stays CAPTURED; motion
  pans the map under a crosshair fixed at the panel's middle (= the screen's
  middle: the panel now has equal 48 px margins), the wheel / right stick zoom
  about it, left click / A marks the spot under it or opens the mark there
  (highlighted by corner brackets, `_hover_pin`). Left stick, d-pad and W/A/S/D
  pan (`_pad_map`, `PAD_PAN`). Only the mark editor frees the mouse; on a pad
  it is worked by focus (note box first, OSK). No pad cursor on the map.
  Mouse travel arrives in canvas pixels, so the map moves 1:1 on screen.
  A border panel ("rim") is drawn over the map picture -- it used to cover
  the panel's own frame.
- **The minimap is heading-up**: the crop is drawn `MINI_SPIN_PAD` 1.45x the
  frame inside a clip and rotated by -facing; the arrow stays up; marks are
  rotated about the player; an "N" rides the rim.
- **Pad inventory without a cursor** (inventory_screen.gd): d-pad / left stick
  (read from its own motion events, so W/A/S/D does not move it) step the
  highlight to the nearest slot in that direction by screen position
  (`_pad_step`), the stick repeating (0.32 s, then 0.13 s); A lifts and drops
  (`inventory.move`), B puts a lifted stack back or closes. The mouse keeps
  its pointer and hover. pad.gd's cursor is now unused by both screens.
- Measured in a harness (36/36): potions run dry -> slot empty, kept, greyed
  "0"; new potions back to it; other quick slots untouched; survives save/load;
  dragged out -> freed; map: mouse 1:1, wheel zoom holds the centre, click mark
  0.00 px under the cursor, editor frees and recaptures the mouse, cursor at
  the screen centre, stick pans, right stick zooms, A marks, B closes; minimap
  turned exactly a quarter with a quarter turn, arrow 0; inventory: Y opens with
  no pad cursor, d-pad and stick move the highlight, A lifts and drops.

## 31. Prison ceiling and gates remade by Tripo, doors, respawn inventory (2026-10-11)

- **The prison's first dome was lopsided** (its collar half a radius off its
  base, the upper shell one-sided -- Tripo built a partial piece) and open at
  the top, its corners closed by a flat ring in `stone_plain_albedo`, which is
  so dark it renders black on plain meshes. Replaced by a second Tripo dome
  ("prison_dome2": symmetrical, closed, ribbed -- but an EXTERIOR on a solid
  base disc). `build_brick_kit.build_dome_inside` cuts the disc away and
  reverses every face so the brick and ribs line the inside; exported as
  "prison_dome" (radius 1, base z 0). The hall sizes it to the room's CORNERS
  (`inner * sqrt 2 + 0.3`, squashed `DOME_RISE` 0.62): it springs from just
  outside the band, so every view up meets wall or dome. The ring, the
  oculus beam and shaft, and the gibbets are gone; ember lights moved up.
  Band segments overlap (`cell_size + 0.7`) -- end to end they left slots.
- **Cell gates are a second Tripo pass** ("jail_gate": a flat pointed-arch
  gate full of bars, cross bands, lock plate), fitted to the brick arch's
  probed opening (3.32 m to 3.3 m, apex 4.8) at 3.28 x 4.74 x 0.2 and split
  into two leaves on their hinges (`GATE_HALF` 1.64). The first pass (cut from
  Tripo's "prison cell" hut) was sparse and broken.
- A third generation, "prison_vault" (a square rib vault), came back as a
  cross of iron rods -- unused. Tripo balance 350.
- **Doors**: 7 uneven pieces (3 x 3, merged top, slant 0.5); thrown at
  `LAUNCH_MIN..MAX` 10-15 m/s away from the player (was 4-7.5), up 1.2-3.4.
  Measured: each piece's furthest reach from the door 5.7-12.3 m (the old
  launch: under 1 m by the same moment). The brick door's stone frame was
  hollow inside once its leaf was cut out of it, so `wood_door._drop_frame`
  hides it and disables its jambs when the door breaks (and on load),
  leaving the corridor's own complete arch.
- **Respawn keeps the inventory as it was at death** -- `_respawn` no longer
  calls `_reset_inventory` (which topped potions back up); it only runs for a
  new game. Measured: 1 potion and 4 bone fragments at death -> identical slots
  after the respawn.

## 32. Anchors save progress; the workbench (2026-10-11)

- **Any anchor can be attuned again, the active one included** (respawn_anchor.gd):
  the active one's prompt reads "E   Save progress" and E re-snapshots the map
  through the same `maze._on_anchor_attuned` (announced "PROGRESS BOUND").
  The player always rises at the one attuned LAST.
- **Upgrades live on the player** (player.gd): `weapon_levels` (id -> level,
  default 1, `UPGRADABLE` sword and spear), `armor_level`, `UPGRADE_MAX` 10.
  `weapon_damage_scale(id)` = 1 + `UPGRADE_DAMAGE` 0.08 per level above 1 --
  applied to the cut / spin (`_stroke_damage`), the slam, and the spear's stab,
  dash and throw blast (`spear._scale()`). `damage_negation()` =
  `ARMOR_STEP` 0.04 per level above 1, applied in `take_damage` after guards
  and ghost, and in `beam_hit`. `upgrade_cost(level)` = round(3 x 1.5^(level-1))
  gold crystals: 3, 5, 7, 10, 15, 23, 34... `upgrade(what)` pays and returns
  false when it cannot. Saved as "weapon_levels" / "armor_level". The
  inventory's item card shows Level and the scaled damage.
- **The workbench** (`scripts/workbench.gd`, procedural -- no Tripo, by the
  user's choice): plank bench with iron straps and a shelf, an anvil on a stone
  block, a grinding wheel (spins up on each upgrade), hammer and tongs, a tray
  of glowing gold crystals; one collision box (1+2), built in
  `dungeon_room._build_mine` before the bake, front right of the court facing
  its middle, clear of the wardens' patch. E aimed at it opens a screen: one
  row per upgradable weapon CARRIED plus Armor -- level, effect now -> next,
  cost, Upgrade (disabled when short or mastered); pad works it by focus.
  `ui_open` and a freed mouse while up. The screen is a CanvasLayer added LAST
  under the root (inner class `Screen`), so it reads Escape / Tab / E before
  the pause menu and the inventory: Escape closes it WITHOUT pausing.
- Stone colour trap again: light grey stone blew out to flat pink under the
  court's red sky light, 0.13 went to black silhouettes; 0.24 with the plain
  stone normal map, triplanar, reads as stone.
- Measured in a harness (34/34): re-attune A -> 2 newly charted cells in the
  snapshot, kept through a death while 2 uncharted-since were forgotten
  (control); B then A -> rose at A; bench prompt when aimed, E opens, rows
  sword/spear/armor, nothing affordable with 0 crystals, Escape closes without
  pausing, costs 3/5/7/10, 20 crystals bought sword 2, 3, spear 2, armor 2, 3
  for exactly 3+5+3+3+5, armor 4 refused with 1 left; a 50 hit at armor 3 took
  46.00; a real sword cut at level 3 dealt 23.20 (20 x 1.16); spear scale 1.08;
  levels survive save_state / restore_state.

## 33. Torch shadows (2026-10-12)

- **Nothing cast shadows before this**: every torch light had `shadow_enabled`
  false and every brick chunk `cast_shadow` OFF (the settings menu still said
  the hand torch -- removed in section 9 -- was the only caster). Now every
  torch hung by `module_level._hang_torch` casts (meta `torch_shadow`), and the
  corridor pieces cast except `brick_level.NO_SHADOW` (floor, bed, cap, skirt:
  lit only from above or outside the corridor). Doors (frame + leaf), hiding
  carts, convoy carts, anchors (not the crystal), the workbench and skeleton
  swords cast too; skinned enemies always did. Torch mounts and the pilaster
  pillar do NOT (they would shade their own light).
- **The knobs** (`Graphics`): `shadows` 0/1/2 (off / hard / soft) as before,
  now acting on the torches; hard = `SHADOW_DUAL_PARABOLOID` (2 passes), soft =
  `SHADOW_CUBE` (6). New `shadow_distance` (Ultra 14, High 12, Medium 10, Low 8,
  Potato 0; menu "Torch shadow distance"), applied as each torch's
  `distance_fade_shadow` -- past it a torch lights but does not cast. And the
  CAP: the positional atlas's quadrants are its slots, and a light with no slot
  casts nothing, the slots going to the lights covering most of the screen.
  `_apply_viewport` gives soft 2 quadrants of 4 (8 torches), hard 1 (4), the
  rest disabled. Atlas sizes raised: Low and Medium 2048, High 4096. A key
  missing from an older graphics.cfg now takes the saved preset's value
  (`load_settings`), not the script default.
- **The level had been lit THROUGH its walls.** Torches reach 20 m at
  attenuation 0.4 and lit the next corridor through the stone; with shadows on
  everything, mean luminance fell 2-3x in corridors and 30x in the spawn's jail
  cell, which had no torch of its own (it has one now, at 0.6 energy, on its
  left wall). Measured per station (same shots, `--bench --shot`): energy 2.4
  restored rooms but left stretches with no torch in sight black; ambient 0.3
  -> 0.45 changed nothing visible (ACES); density 1.5 lit every stretch but,
  once capped, ran 1.5-3x the old brightness at 59 fps. Kept: density 1.1,
  `module_torch_energy` 1.3 -> 1.4 -- every station back within ~20% of before.
  Torches beyond the cap still light through walls, as before.
- **Cost** (RTX 3060, 3440x1440, Ultra, editor closed): before 83.1 fps / worst
  p99 22.22 ms / 1016 MB. Uncapped, 24 m: 40.9 fps, chest room 18.9 (51M prims:
  six passes over every chunk in 20 m, per torch; render CPU 17 -> 44 ms).
  Flame sway forcing a redraw every frame was NOT it (42.5 with sway 0). 12 m:
  50.8; capped at 8: 59.4; dual paraboloid instead of cube: 61.8 (kept cube on
  soft); the 1.5 density alone without shadows: 65.9. Final (1.1, 8 slots,
  14 m, cube): **73.1 fps, worst p99 25.00 ms, 1060 MB**; chest room (domed
  prison, a torch on every arch) 44.9 vs 53.3. Not benchmarked on the P620.
- Measured in a harness (11/11): Ultra loaded with no shadow_distance in the
  file -> 14 (re-broken without the preset fallback: 8, caught); 502 torches all
  casting, cube, 14 m; atlas 4+4 slots; 940 brick chunks cast, none of floor /
  bed / cap / skirt; jail torch; Potato none cast; High 12 m; Low dual
  paraboloid, 4 slots, 8 m; Ultra -> Potato -> High -> Low -> Ultra: 0 of 661
  lights differ; graphics.cfg untouched.
- `tools/benchmark.gd`'s header now reports "torch shadows N torches to X m".

## 34. Darker, physical falloff, a real base light (2026-10-12)

- **There was no base light.** With every torch switched off, the ambient
  (`module_ambient` 0.3 x `AMBIENT_ENERGY` 7) measured 0.0005 mean luminance --
  black -- and 3.0 read 0.045: ACES's toe eats low ambient whole. That is why
  every earlier "raise the ambient" test changed nothing visible. Measured
  sweep, torches off: 0.8 -> 0.004-0.006, 1.2 -> 0.010-0.014, 1.6 -> 0.016-
  0.022. **1.1 is "barely see"**: slabs and brick courses just readable, black
  a few metres off.
- **Ambient colour near-neutral** (0.17, 0.175, 0.19): the old (0.16, 0.175,
  0.225) made the dark read blue, and mixed with the orange fire turned the
  wall beside a torch magenta.
- **Torches darker and physical**: `TORCH_ATTENUATION` 0.4 -> 1.0,
  `TORCH_RANGE` 20 -> 14 m, `module_torch_energy` 1.4 -> 1.3. Beside a torch
  about half the old brightness, between torches down to the base light. At
  1.0 a torch adds little past ~12 m (14 vs 20 m: 10-25% less between
  torches), and it also cuts what an unshadowed torch leaks through a wall.
- Tested live with a harness that applied energy / attenuation / range /
  ambient to every torch and the environment at runtime and shot 3 spots
  beside a torch, 3 between (6-12 m from any light) and the 3 darkest
  straights (the densest map has none past ~12 m) -- no rebuild per config.
  Trap: "nearest light" includes the red skylight spots and cage lights; a
  "near" spot that read 0.025 with every torch off was lit by those.
- Bench (RTX 3060, 3440x1440, Ultra, editor closed): **79.4 fps, worst p99
  22.81 ms, 1060 MB** (73.1 / 25.00 before this; 83.1 / 22.22 before torch
  shadows). The shorter range paid for the shadows' cost.
- The boss hall is as dark as it was (lit mostly by its sky lights); not
  retuned.

## 35. No torchlight through walls; carts are searched, then hidden in (2026-10-12)

- **Only shadowed torches give light** (`torch.gd` `_rank`, static, run every
  `RANK_PERIOD` 4 frames by whichever torch processes first): every torch hung
  by `_hang_torch` (meta "torch_shadow") is ranked by distance from the camera
  and only the nearest `Graphics.torch_lights` give light (Ultra 16, High 12,
  Medium 10, Low 8, Potato 6; settings "Lit torches", replacing section 33's
  shadow distance); every one of them casts. The rest keep flame and halo and
  give none (`light.visible = false`). A torch fades over `LIT_FADE` 4 m at the
  edge of the set (eased, `LIT_EASE`), and at most `SHADOW_SLOTS` 24 are ever lit
  -- the atlas is now 4 + 4 + 16 slots -- because a lit torch with no slot casts
  nothing and lights through the wall again. After a jump (respawn) the old set
  is still fading as the new one fades in: the furthest fading ones go out at
  once to stay within 24. Torches no longer have a Godot distance fade
  (`Graphics._apply_light`): it could switch a shadow off before its light.
  Potato has no shadows at all, so there torches DO light through walls.
- Measured (harness): walking 40 stretches of the level, at most 24 lit, every
  lit torch casting on every frame; 4 spots with a torch 3-10 m behind stone and
  none in sight, that torch boosted 20x: shadowed 0.009 / 0.007 / 0.014 (the
  base light), its shadow switched off 0.040 / 0.028 / 0.068 -- the control
  sees the leak. (A 4th spot read the same both ways: the torch was round the
  corner ahead, lighting the floor through the opening -- legitimate.) Bench
  (RTX 3060, 3440x1440, Ultra): 72.3 fps, worst p99 27.78 ms, chest room 41.6
  (79.4 / 22.81 when 8 cast and the rest leaked).
- **Hiding carts** (`hiding_spot.gd`) start SHUT. E "Search": walk up, the lid
  swings open, `_roll`: health potion 0.15, coins 0.19 (3-7), bone fragments
  0.19 (1-3), else nothing ("Empty" toast); the find rises out of the tray and
  flies to the player (`ItemDrop.give`: a drop spawned already taken; coins now
  have their own stack-of-coins drop visual). No room: the rest pops out onto
  the floor. The lid stays open; only a searched cart offers "Hide". Hidden, the
  lid rests at `LID_SLIT` -0.08 rad and the eye sits 4 cm under the rim in the
  middle of the tray: the slit along the front is the view out. Saved as
  "carts" (searched indices; the old "coffins" list named every cart and is
  ignored). Measured over 20,000 rolls: empty 0.47, coins 0.20, bones 0.19,
  potion 0.15, coins always 3-7.
- **The lid was see-through from inside**: the kit lid (a Tripo crate's top
  boards) is one-sided, so from below it was not drawn and a hidden player saw
  the corridor and the torches straight through it. `_both_sides` gives the lid
  two-sided copies of its materials.
- **Peeking is removed** (the slit replaces it): player `_update_peek`,
  `peek_amount`, the peek bar's exports, and the HUD's PeekBar are gone. The
  section 11 notes on peeking describe removed code.

## 36. A kicked door leaves its arch (2026-10-12)

- `wood_door._drop_frame` is gone: a kick (and a load of a kicked door) used to
  hide the brick door's stone frame ("GateFrame") and drop its jambs' collision,
  so the arch vanished with the door. Now only the wooden leaf breaks; the frame
  and jambs stay (the navmesh was always baked with the jambs, so nothing
  changes for pathing).
- The frame had been hidden because, with the leaf cut out of it, its stone was
  hollow: from the far side the opening's inner faces were missing (a black
  hole). `module_level._build_brick_door` gives the frame two-sided copies of
  its materials (`_frame_both_sides`), and the reveal reads as stone from both
  sides.
- Measured in a harness: after a kick, frame visible, jambs on layers 1+2, leaf
  gone; walked through on the real W key from 2.5 m before the door to 7.5 m
  past it; shots from both sides and both angles show the arch whole.

## 37. The kicked arch lined; searching a cart is a scene (2026-10-12)

- **The brick door frame is a shell** (measured with rays against its mesh):
  its opening has a reveal only on a lip at the front (z -0.05 to -0.3) and one
  at the back (-0.95 to -1.1); between them, where the Tripo door sat, a slot
  runs back to walls 1.75 m out and a ceiling at 4.96 m. With the door kicked
  out that was a hollow you saw into and, at angles, through. No Tripo needed:
  `module_level._door_reveal_mesh` extrudes the opening's measured outline
  (`DOOR_REVEAL`, half-width by height, pointed head to 4.32) across the slot
  (`DOOR_REVEAL_Z`, lapping each lip), as "GateFrame/Reveal", hidden until the
  door breaks (`wood_door._show_reveal`, on the kick and on load). Re-measured
  with the lining: 0.96 m at the jambs and 4.32 at the apex all the way through.
  Traps: wound the wrong way the lining showed its back face and rendered black
  even double-sided (the normal pointed out); and the arch material
  (stone_plain) read as flat plaster beside the frame's blocks -- it uses
  stone_grey (grey blocks, dark mortar), triplanar in the frame's own space.
- **Searching a cart** (`hiding_spot._search`, ~2.7 s once at the cart, was
  ~1.4): letterbox, weapon put away (`hands_busy`), step up to `SEARCH_STAND`
  0.55 m, crouch and reach -- two forearms with hands (primitives, placed each
  frame from shoulder points under the eye to the lid's front edge, hands
  levelled into the cart so the fingers hook under the edge) -- the lid sticks
  (lifts 0.11 rad, drops back, the arms tremble), gives with a jolt (`_shake`),
  and is heaved over (0.8 s) while the view rises and leans in over the rim
  (`player.scene_lean`, new: an eased head offset for scenes, cleared by
  `end_cutscene` and the respawn) and looks down into the tray; the hands let
  go once the lid is past upright. The find lies in the tray for the peek
  (`ItemDrop.give(..., wait)`) and flies to the player as control returns.
  Measured: the Tripo cart's tray floor is at 0.78 m (`KIT_TRAY_FLOOR`; the old
  `TRAY_FLOOR` 0.52 put the find under the boards). Death mid-scene: no hands,
  no letterbox, no lean left, weapon back, the cart left unsearched.
- **The drawn hands were removed** (2026-10-12, at the user's request): no
  forearms or hands in the cart search; the reach is a plain 0.4 s beat of the
  view leaning in. Everything else in the scene is unchanged (measured 2.6 s,
  finds delivered, no extra meshes on the cart).

## 38. Night and the red moon (2026-10-14)

- **The red sky and its fake lights are gone.** The courts, the boss hall and
  the floors under the skylights are lit by the scene's "MoonLight"
  DirectionalLight3D, set up by `maze._setup_moon` (it was a faint, shadowless
  blue light at 0.07 that lit every corridor through its roof): `MOON_COLOUR`
  (1.0, 0.16, 0.09), `moon_energy` 2.4, `MOON_ELEVATION` 72 / `MOON_AZIMUTH` 45,
  PSSM 4 splits to `MOON_SHADOW_DISTANCE` 95 m (chunks are culled at 70 m +
  half a block; past the shadow distance it would light everything it faces).
  `place_room_lights` now places nothing (returns the empty holder the prison
  and puzzle code still look in; `faked := true` for the old omnis), the
  skylight spotlights are off (`SKYLIGHT_SPOTS`), the boss hall's sky lights
  and the rock fills are gone.
- **High, because of the skylights**: the shaft is 1.65 m deep through a 1.0 x
  2.4 m opening. At 62 deg the light landed on the corridor wall; at 72 it
  makes a barred pool on the floor (the grate and liner now cast).
- **Everything open to the sky must cast**: the prison dome, band, partitions
  and gates, the boss hall's walls (`boss_hall._add_mesh` had shadows OFF, so
  the hall let the moon through its walls), the morgue's dead and coffins, the
  shard door, the portcullis and the mine's props now cast. The corridor lid
  and skirts cast too -- the Tripo vault has small holes -- on their own visual
  layer `BrickLevel.MOON_ONLY_LAYER`, which every torch leaves out of its
  `shadow_caster_mask` and cull mask. Skylight cells used to have NO lid; they
  get a frame of lid round the shaft (a stray spot of moon came through the
  vault's holes beside the pool).
- **The boss hall's stone was too dark to light**: its textures average ~0.12
  albedo against the flagstones' 0.41 (energy-10 sky lights hid that). Paving
  0.72 -> 1.25, walls x1.65 on the colour (~3x linear).
- **Graphics**: the moon is on only with shadows (`_apply_light`, meta "moon");
  Hard uses 2 splits, Soft 4. On Potato (no shadows) it is OFF -- it would
  light every corridor -- so the courts have only the base light there.
- **The sky** (`shaders/sky_clouds.gdshader`): night colours, the moon's disc
  drawn at `LIGHT0_DIRECTION` (`moon_size` 0.06 rad, mottled, limb darkened,
  `moon_intensity` 7 -- at 16-28 ACES burnt its core to peach), a red haze and
  corona, clouds near it catching its light, sparse twinkling stars. Disc and
  stars are drawn in the full-res pass behind the clouds: the quarter-res pass
  writes cloud coverage to ALPHA (`_compute_full(dir, out cover)`; Godot
  shaders have no mutable globals).
- Measured (harness, torch flicker frozen so moon-on/off differ only by the
  moon): 8 corridor spots, worst +0.0002 luminance (none); every skylight's
  floor pool shows the bars; courts 1.1-4x brighter; the boss hall lit with
  column shadows. Harness traps: after a teleport the nearest torches fade in
  over ~0.4 s -- wait 90 frames before comparing shots; a player with
  collision_mask 0 falls through the floor while you wait; and the boss hits a
  test player down to low health, which desaturates every shot.
- Bench (RTX 3060, 3440x1440, Ultra, editor closed): **65.1 fps, worst p99
  33.33 ms, 1106 MB** (72.3 / 27.78 before). The moon's 4 cascades redraw the
  level's geometry; the prison (dome now casting) is the worst, 28.7 ms.
