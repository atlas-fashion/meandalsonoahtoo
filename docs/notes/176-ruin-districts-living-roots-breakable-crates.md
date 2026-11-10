## 176. The maze in districts: gold-veined roots and their living tips, breakable crates, props of the ruins (2026-11-10)

The user (with a reference sheet of gothic dungeon ruin props: root-covered
pillars and arches, cages, chains, banners, candles, chests, crates,
skeletons, torture devices, crystals): add props like these to the
environment. All the roots on the pillars and walls streaked with a little
glowing gold; some root tips alive, whipping at the player going by; hitting
them makes the glow go away and they wilt and die. Crates break, as in a
soulslike, with a puff of dust. Then: "make the maze unique using those
props" -- each part of the maze its own.

### Districts (`scripts/ruin_dressing.gd`, built by maze.gd `_place_ruins`)

Brick kit only, after the clutter and before the navmesh bake (maze.gd
`_build_module_level`), so solid props are carved out of the navmesh (layer
512) and their floor marked WALL for spawning (`_mark_solid`, pulled out of
`_place_clutter`). `-- --no-ruins` builds the corridors without them.

- **Cut**: the corridor cells (no rooms, courts, the morgue hall) into about
  one district per `DISTRICT_CELLS` 70 cells, between 7 and 14 -- 13 on the
  fixed seed. Seeds farthest-point by steps from the spawn (only cells the
  spawn reaches: a cut-off passage once seeded a 5-cell district), then grown
  EVENLY -- the smallest district takes the next step. Plain simultaneous BFS
  gave the spawn's district 455 of 910 cells and a far one 5. Now 38-133.
- **Looks** (`Look`): OVERGROWN, STOREHOUSE, OSSUARY, QUESTION (the torture
  quarter), BANNERS, CRYSTAL, GAOL. The spawn's district is the gaol; the
  ossuary is anchored at the morgue, the question at the surgery; the rest by
  least-used look no touching district has, ties from the seed. A look's second
  district is its **variant 1**: overgrown 0 walls buried in roots / 1 a curtain
  hanging from the vaults and more tips alive; storehouse crates / barrels and
  carts; ossuary the seated dead among candles / coffins on end and candelabra;
  question maidens and racks / pillories, tool racks, more hooks; banners
  crimson and black / blue and green; crystal ice blue / violet (materials
  tinted, `_crystal_tint`); gaol hanging cages / chains, shackles, cage carts.
- **Density** falls toward a district's edge: `core` 0.5 at the edge to 1 three
  cells in (`_depth`, BFS from the edge cells). Roots turn up on 13% of other
  cells' walls (30% of those with a living tip), a crate on 5%.
- **Walls**: `_free_walls` -- closed, no torch, no iron cage wall, not used by
  the clutter (brick_level now records `clutter_walls`). Props reserve stretches
  of a wall (`_reserve`, `_spot`): ±2.3 m in a straight, ±1.25 m in a junction
  (its pillars stand in the corners). Roots use `_root_walls` (every closed wall
  but a cage's; a torch's wall keeps its middle 0.75 m either side clear for the
  pilaster: `band` in `wall_strands` / `_crawl`).
- Blocked: door cells, the spawn and the 8 round it, hiding carts' cells,
  manholes, holding cells, the gates.
- On the fixed seed: 4,140 root strands, 50 living tips, 105 crates (the 3
  clutter crates among them), 420 crystals in 72 clusters, 148 banners, 35
  seated dead, 113 candles, 238 bones, 44 maidens, 31 caskets, 56 chandeliers,
  33 gibbet cages, 89 hooks, 370 chain links, 183 small lights. Built in 2.7-2.9
  s (the level took ~25 s before).

### The roots (`scripts/ruin_roots.gd`, `shaders/root_bark.gdshader`, `root_common.gdshaderinc`)

- **Reliefs**: each kit piece's outer surface measured once from its own
  triangles (`_raster`): the wall's face over a 4 cm grid (`planar_relief`,
  +Z, 130 x 90 cells, 80 ms), the arch's two faces, the junction pillar's radius
  at every angle and height, widest of its four quarter turns (`pillar_relief`;
  brick_level stands each pillar at a random quarter turn). A strand's centreline
  is set into that surface by 40% of its radius, so it grips the brick. `outer`
  is max-filtered once per reach (`_dilate`) -- it was 49 lookups a point -- and
  the arch's opening edge is found once per row (`_opening_edge`; it scanned 80
  cells a point and was half of the overgrowth's build time).
- **Strands**: down the walls from the vault's springing (they start inside the
  stone above 3.0 m) in bundles of 1-3, wandering, kinking now and then, along
  the wall's foot when they reach the floor; branches and hair roots;
  round the junction pillars (spirals); over the arches' faces down one side of
  the ring; hanging from the vault (`_vault_at`: soffit 3.0 m at the wall to
  5.1 m at the crown), stopping over a head in the middle (2.35 m), lower by the
  walls.
- **Mesh** (`build_mesh`): one per cell, tubes by parallel transport, 4-7 sides
  by thickness, gnarled (swelling and knots along the length), pressed flat
  against their surface (`flat` 0.7: wide across it, shallow off it). Vertex
  colour r the bark's shade, g the strand's gold; UV round and along, UV2 along
  0..1 and a seed. No shadows, gone at 60 m.
- **Bark and gold** are all noise, no textures: fibres and cracked plates with a
  normal map from the height, moss, dark cracks; the gold thin streaks along the
  fibres, broken into strokes and patches, a slow pulse running down them
  (`vein_energy` 1.4), dimmed toward the silhouette (seen edge-on a tube crowded
  its streaks into a bright outline), and the whole root very faintly warm
  (0.02) so between torches it shows as a shape, not floating streaks. The
  mesh's `life` instance uniform is its gold.

### Living tips (`scripts/living_root.gd`, `shaders/root_tip.gdshader`)

- The end of a wall root grown to stop at 1.55-2.25 m with a blunt end; the tip
  continues it: one tapered tube (1.45 m ±15%) bent in the shader along a cubic
  Bezier whose three control points (instance uniforms) ride on damped springs
  in the script -- the end softer than the base, so it trails and cracks.
- Hangs writhing, curled out from the wall; a player in front of it within
  `notice` 2.8 m: it draws back up the wall over itself, shivering and glowing
  to 2.6x (`COIL_TIME` 0.5 s), opens a parry cue 0.17 s before the lash
  (`LISTEN` 0.3), lashes at their chest (reach 1.08x its length); the lash lands
  if the end passes within 0.5 m of their upright axis -- step out and it
  misses. 12 damage, through `take_damage(.., self)`, so a guard blocks it and a
  parry turns half back on it (which kills it). 1.5-2.6 s between lashes.
- A StaticBody3D on the damageable layer 4 only (nothing walks into it), a
  capsule following the curve's first 60%; its origin 0.9 m under and 0.35 m out
  from the base, because the player's line-of-sight test aims 0.9 m over a
  body's origin and that point must be clear of the wall.
- **Any blow kills it**: thrown off by the blow, its glow flares and goes out
  (2.2/s), it greys, shrivels to 60% and hangs limp down the wall (`wilt` over
  1.8 s), gold motes and bark chips (effects on). When the last tip grown from
  a cell's root mesh dies, that mesh's gold fades out over 2.8 s (`life`, the
  mesh's "alive" count). Asleep beyond 18 m.
- **Measured in the real level** (throwaway harness, real input events): stood
  1.5 m out from a tip, it lashed (1000 -> 988); one sword swing killed it;
  glow 0.0 and wilt 1.0 after 2.5 s; its mesh's count 1 -> 0. Pictured from the
  eye: at rest, lashing (an orange tendril at the face), and dead (the whole
  cell's roots dark).

### Breakable crates (`scripts/breakable_crate.gd`)

- Built from boxes: four posts, sides of boards between them with rails and a
  diagonal brace on two, a lid with two battens; each box on one plank of
  `textures/surgery_planks.png` along its grain, so the debris is the crate's own
  boards. Four sizes (0.58-1.12 m), three tints, one mesh whole plus 14 chunk
  meshes (posts, half sides, half lids), cached per size.
- **One blow breaks it** (sword, spear, a thrown spear's blast) and so does
  dashing into one (`watch`, a player's `_dashing` within 0.6 m of its box,
  run by ruin_dressing's `_physics_process`). The 14 chunks fly off as rigid
  bodies along the blow (layer 0, mask floor 1 and walls 256), and after 3.2 s
  are laid down as plain meshes where they lie and stay; a lit dust puff
  (`surgery_fx_dust.png`, 16 billboards, 6 without effects) and 22 tumbling
  splinters. 22% coins (3-9), 6% a small health potion. A crate stacked on it
  drops into its place.
- **Trap: a sword cut passes over a crate.** The first test swung at a crate and
  missed every time: the blade sweeps at chest height. Blows find a taller
  volume of its own (`HitVolume`, 1.75 m, layer 4 only); the crate itself is
  solid on 256 | 512 and NOT on 2 (the player's line of sight is tested on 2:
  a crate stacked above would hide the one under it).
- The clutter's crate (brick_level `place_clutter`) is now one of these: its
  place goes out in `clutter_crates`; the RNG calls there are unchanged, so the
  layout is the same.
- Measured: a swing broke one, 14 pieces laid down; a dash broke another.
- Not saved: a level built afresh has its crates whole (and its tips alive).
  A broken crate leaves its hole in the navmesh (it was carved at the bake).

### The props (`ruin_dressing.gd`)

- The Higgsfield kit made for the surgery (notes 95-98, `models/surgery/`),
  graded and glowing as there (surgical_table `grade` / `glow`): maiden, rack,
  pillory, tool rack, brazier (an ember disc and a light), gibbet cages, hooks,
  chains, cuffs, bundles, casket, candelabra, chandelier, crystal, barrels,
  hand cart, cage cart, rug, lectern. Each stands against its wall facing out
  (the models face +Z), with a box collider on 256 | 512.
- Made here: the seated dead (the rigged ossuary skeleton posed slumped by
  world turns of its bones, `_turn` / `_aim`, baked once per pose with
  `bake_mesh_from_current_skeleton_pose` and shared, 3 poses); skull piles;
  loose bones (one mesh each); candles (the stubs of a group one mesh, each
  flame the torch's flame shader on a small card); banners (`ruin_banner.gdshader`:
  wool with a faded gold border and one of three devices, the hem torn and
  holed by alpha, sagging and stirring; rod and brackets one mesh); rubble.
- Hanging things keep over a head: gibbet cages scaled 0.72-0.8 with their foot
  at 2.35 m or higher; bundles on hooks come down to 0.7 m, so they have a
  0.4 m collider; the seated dead's legs a 0.65 x 0.5 x 0.9 one.
- **Lights**: candles, coals, candelabra, chandeliers, crystals, at most one per
  group; unshadowed, so short (2.0-2.4 m; a chandelier 3.6 m from a junction's
  middle at 3.4 m up) -- far enough from any other corridor's floor that they
  do not light through the stone; no mist; fading out at 22 m; flickered by
  the dressing's own `_process`. Only with `Graphics.effects`.

### Settings (section 3)

- **`Graphics.ruin_shadows`** ("Prop shadows"): the big props (maidens, racks,
  pillories, tool racks, braziers, caskets, carts, barrels, lecterns, the seated
  dead) in the torches' shadow passes. Ultra on; High, Medium, Low, Potato off.
  Applied on `Graphics.changed` (`_apply_graphics`), the low-LOD shadow copies
  (brick_level `shadow_lods`) shown or hidden with it. Banners and candelabra
  never cast (measured: shadows were most of the props' cost).
- The props' lights follow `effects`. Round trip holds: the lights' meta from
  `_apply_light`, the casters re-set from the knob every time.

### Measured (RTX 3060, 3440x1440, the user's settings: Ultra, msaa 2, 16 torches)

`--bench --ab=code` with a temporary hook that hid the ruins on `ab_on`
(removed after), interleaved, two runs agreeing. New benchmark stations
`ruins overgrown`, `ruins crystal`, `ruins ossuary` (tools/benchmark.gd, from
`samples`). Ruins shown / hidden, avg ms (gpu ms):

```
spawn corridor     20.14 / 19.73  (18.79 / 18.51)
boss room centre   17.86 / 16.98  (13.65 / 13.46)
outer maze         18.39 / 17.59  (11.85 / 11.75)
chest room         24.94 / 24.45  (22.48 / 22.12)
surgery            21.18 / 20.15  (18.86 / 18.29)
ruins overgrown    14.47 / 14.00  (10.95 / 10.43)
ruins crystal      15.10 / 14.70  (10.85 / 10.65)
ruins ossuary      17.50 / 16.97  (14.03 / 14.05)
```

0.4-1.0 ms a frame, GPU 0.0-0.6 ms; the rest is the render thread culling some
thousands more instances (it costs in the boss hall too, over the corridors).
`--ab=ruin_shadows=false`: 0.2-1.1 ms of it was the props' shadows (chest room
gpu 22.24 -> 21.46), hence the knob off below Ultra. Merging the bones', candle
stubs', rubble's and banner rods' meshes and thinning the crystal clusters
(0.8 -> 0.55 of walls) did not move the numbers (within noise).

### Traps

- **`Theme` is a native class**: an enum of that name is a parse error. `Look`.
- **Typed arrays from a ternary** (`var a: Array[float] = [..] if c else [..]`)
  fail at runtime: build them with `append`.
- **The player reads attacks from events**: `Input.action_press("attack")`
  swings nothing; a harness must `Input.parse_input_event` an
  `InputEventAction` (dash and move are polled, so `action_press` works there).
- **Teleporting the player to y 0.05** put them in the floor and the game put
  them back: screenshot after screenshot showed the same corridor. Stand them
  at 1.0-1.2 m (as `_floor_under` does). Also wait out the first seconds after
  the build (the wake-up in the cell).
- A name clash under one parent renames a node (`@MeshInstance3D@12`): count
  debris by meta (`crate_debris`), not by name.
- In the dark between torches the roots read only by their gold; hence the
  faint overall warmth, and the props' own small lights per district.
