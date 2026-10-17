# Working rules for this project

Godot 4.7.2, Forward+, Vulkan. Target hardware is a **Quadro P620 driving a
3440×1440 ultrawide** — weak fill rate, 2 GB VRAM, ~5 megapixels. Every decision
below follows from that.

## How this file and `docs/notes/` work together -- READ THIS FIRST

Sections 1-5 below are the standing rules. Everything else this project has
learned -- the history of every feature, its tuning values, its measurements
and the traps hit building it -- lives in **`docs/notes/`**, one file per
section, moved there verbatim from this file on 2026-10-17. Nothing was
summarised away; the notes are the full record.

**Before changing anything, find and read the notes for it. Do this yourself;
do not ask the user what the history is.**

1. Look up every file you will touch in **"Notes by source file"** below and
   read the notes listed for it.
2. **Also grep** `docs/notes/` for the feature, node, function and constant
   names involved (e.g. `grep -ril "parry" docs/notes`). Many notes name a
   function (`_spawn_decrepit`) or a feature ("the guard") without naming its
   file, so the file list alone is not complete.
3. Read the matching notes in full. **When notes disagree, the higher-numbered
   (newer) note wins**; several say outright that they supersede earlier ones.
   Section 6's subsections are older than section 7, and **sections 1-5 below
   are older than all the notes**: parts of sections 2 and 4 (lighting baked
   per instance, kit stone triplanar, torch shadows, the benchmark table)
   describe the organic level, which is now only a fallback -- see the
   Architecture map further down for what is live.

**Code comments cite "CLAUDE.md section N".** That now means
`docs/notes/NN-*.md` -- e.g. "section 33" is `docs/notes/33-torch-shadows.md`,
"section 6" is the `docs/notes/06.*` files (grep them for the cited topic), and
the second section 8 (respawn anchors) is `08b-respawn-anchors.md`. Sections
1-5 are still in this file.

**Recording new work** (do this as part of every feature, as before):
- Add a new file `docs/notes/NN-short-slug.md` with the next number (the
  latest is 59), headed `## NN. Title (YYYY-MM-DD)`, in the same style:
  what was built, where (file + function), the values, what was measured, and
  the traps.
- Add its row to the **section index** and its number to each file's line in
  **"Notes by source file"** (add lines for new files).
- Change sections 1-5 of this file only for a rule that applies project-wide.
  Correcting a fact in an older note: edit that note, or say in the new note
  which earlier one it supersedes.
- `docs/` holds a `.gdignore`, so Godot neither imports it nor rewrites it.

**Commit and push every change -- standing instruction from the user
(2026-10-17).** When a change is finished and verified, commit it (with its
note) and push it to `origin main` straight away, without asking. Commits go
directly on `main`, as the history does. The repo is shared, so:
- `git pull --rebase` before starting work and again before pushing.
- Stage your own files by name. Do not commit `.import` files that Godot
  rewrote by itself while the editor was open (e.g. only `detect_3d/compress_to`
  changing), or CLAUDE.md / notes files whose only change is spaces turned to
  tabs; `git checkout --` those instead. Do commit `.import` files that your
  change actually needs (new assets, deliberate import settings).
- If a push is rejected or a rebase conflicts, resolve it -- never force-push.

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

## Architecture map (checked against the code 2026-10-17)

**Boot.** `scenes/title.tscn` (`title_screen.gd`) -> `Saves.start(i)` ->
`scenes/main.tscn`: WorldEnvironment, MoonLight, **Maze** (`scenes/maze.tscn`,
`scripts/maze.gd`), Player (`player.gd`), HUD (`hud.gd`), Benchmark
(`tools/benchmark.gd`, idle without `--bench`), PauseMenu. `--bench` or
`--skip-title` skips the title. Autoloads: `Graphics`
(`graphics_settings.gd`), `Saves` (`save_system.gd`), `Pad` (`pad.gd`).

**`maze.gd` `_ready()` builds the whole level:** seed (`maze_seed`, or the
save's) -> level builder -> `_build_gates`, `_place_player`,
`_connect_player`, `_attach_explore_map` -> navmesh bake ->
`Graphics.apply_all` -> `_seal_cells`, `restore_world(save)`, `_populate()`,
`restore_player(save)` -> `is_built = true`, emits **`level_built`**.
`_populate()` spawns: boss, jail-cell stock, enemies, convoys, stalker,
decrepits, sewer lizards, chests.

**The live level path** is `maze.gd` `modules = true` ->
`_build_module_level()`:
- Layout: `maze_graph.gd` (organic graph) sampled onto a grid by
  `module_maze.gd` (`module_organic_shape = true`). The graph is deliberately
  NOT stored in `_graph` (setting it switches maze.gd to the organic rules).
- Geometry: `module_level.gd` `build()`; with `ModuleLevel.brick = true` (the
  default) the stone is the **brick kit**, `brick_level.gd`. `-- --modules`
  swaps back to the old Tripo tunnel modules for A/B.
- Then: doors (`wood_door.gd`), torches (`torch.gd`), windows (`bone_cage.gd`
  cages), room lights, skylights, `jail_cell.gd`, `boss_hall.gd`, zone gates
  (`zone_gate.gd`), anchors (`respawn_anchor.gd`), hiding spots
  (`hiding_spot.gd`), clutter, damp (`damp.gd`), `morgue.gd`, chest rooms
  (`dungeon_room.gd`: prison / mine / vacant), the great door
  (`shard_door.gd`), the sewer (`sewer.gd`, `manhole.gd`).

**Fallback / legacy paths** (reached only when `modules = false`):
`organic = true` -> `_build_organic_level()` (`organic_maze.gd`,
`organic_dressing.gd`, `organic_lighting.gd`, `wall_contour.gd`,
`kit_placer.gd`, `maze_phases.gd`); both off -> the original tile maze. Older
notes (sections 2, 4, 6) describe these paths; check which path a note is
about before applying it.

**Not loaded by anything:** `scripts/puzzle_room.gd` (replaced by
`dungeon_room.gd`; only comments mention it), `circular_maze.gd` and
`maze_difficulty.gd` (only `tools/*_circular_maze.gd`), `beanstalk.gd`. The
five 0-byte `.gd` files at the repo root (`bomber`, `bone_cage`, `chest`,
`mimic`, `wood_door`) are empty stubs; the real scripts are in `scripts/`.

**Systems** (all `scripts/`):
- Player & combat: `player.gd` (movement, sword, block/parry `_start_block`
  `_guard` `_on_guarded`, spear dash/stab `stab_at`, `take_damage`, `_die`,
  `_respawn`, `hide_in`), `spear.gd`, `hand_torch.gd`, `held_potion.gd`,
  `door_debris.gd` (kicked doors), `interact.gd` (shared E prompt).
- Enemies: `enemy.gd` (skeleton; base class; also the boss via
  `scenes/boss.tscn` + `weak_point.gd`), `archer.gd` + `arrow.gd`, `crier.gd`
  (flying heads, once "bombers"), `enforcer.gd` + `enforcer_react.gd` (once
  "warden bots"), `decrepit.gd` + `decrepit_react.gd` (moves: note 59), `sewer_lizard.gd` +
  `goo.gd`, `stalker.gd` ("the Remnant" / "the Shade"), `mimic.gd`,
  `convoy.gd`; helpers `patrol.gd`, `skeleton_eyes.gd`, `skeleton_sword.gd`,
  `enemy_health_bar.gd`, `death_burst.gd`, `item_drop.gd`. Clip changes on the
  enforcer and decrepit rigs are inertialized by `enforcer_react.gd`
  `crossfade` (note 59) -- use it for any new clip switch.
- World: `chest.gd`, `gate.gd`, `portcullis.gd`, `workbench.gd`,
  `screen_fade.gd`, `sky_setup.gd` (sky, moon).
- UI: `hud.gd`, `attack_icons.gd`, `inventory.gd` (data),
  `inventory_screen.gd`, `item_slot.gd`, `item_icon.gd`,
  `consumable_type.gd`, `radial_menu.gd` (item wheels), `explore_map.gd`
  (map, incl. sewer level), `pause_menu.gd` (owns settings `SPEC`),
  `settings_panel.gd`, `title_screen.gd`, `pad.gd` +
  `pad_keyboard_input.gd` (controller, on-screen keyboard).
- Saving: `save_system.gd` (4 slots, `request()` / `save_now()`, autosave);
  maze.gd supplies `save_state()`, `restore_world()`, `restore_player()`.

**Running.** On the `tflfr` Windows machine the Godot binary is
`C:\Users\tflfr\Desktop\Godot_v4.7.2-stable_win64.exe` (examples here say
`godot`). Game args go after `--` (`OS.get_cmdline_user_args()`):
`tools/benchmark.gd` reads `--bench --ablate --shot --swing --no-trail
--preset=<name> --size=WxH --nocull --flat`; `maze.gd` reads `--no-enemies`
and `--modules`; `brick_level.gd` reads `--brick-skip=a,b`. Harnesses are
`extends SceneTree` scripts run with `--script res://tools/<x>.gd` (see
section 4 for the headless traps). Asset build pipelines (Blender headless,
then `godot --headless --import --path .`) are documented in
`tools/README.md`; read it before touching any generated model.

## Section index (`docs/notes/`)

| § | Date | Topic | File |
|---|---|---|---|
| 6.00 | 2026-09-28 | The module level (intro) | [docs/notes/06.00-module-level.md](docs/notes/06.00-module-level.md) |
| 6.01 | 2026-09-28 | What Tripo actually returns | [docs/notes/06.01-what-tripo-actually-returns.md](docs/notes/06.01-what-tripo-actually-returns.md) |
| 6.02 | 2026-09-28 | Traps | [docs/notes/06.02-traps.md](docs/notes/06.02-traps.md) |
| 6.03 | 2026-09-28 | Measured | [docs/notes/06.03-measured.md](docs/notes/06.03-measured.md) |
| 6.04 | 2026-09-28 | The boss hall is a scaled cross | [docs/notes/06.04-the-boss-hall-is-a-scaled-cross.md](docs/notes/06.04-the-boss-hall-is-a-scaled-cross.md) |
| 6.05 | 2026-09-29 | Full-resolution modules, and what they cost | [docs/notes/06.05-full-resolution-modules-and-what-they-cost.md](docs/notes/06.05-full-resolution-modules-and-what-they-cost.md) |
| 6.06 | 2026-09-28 | Collision: exact for the player, boxes for everyone else | [docs/notes/06.06-collision-exact-for-the-player-boxes-for-everyone.md](docs/notes/06.06-collision-exact-for-the-player-boxes-for-everyone.md) |
| 6.07 | 2026-09-28 | Rooms are cloisters | [docs/notes/06.07-rooms-are-cloisters.md](docs/notes/06.07-rooms-are-cloisters.md) |
| 6.08 | 2026-09-28 | The preview must carry the game's GRADE, or it lies about brightness | [docs/notes/06.08-the-preview-must-carry-the-game-s-grade.md](docs/notes/06.08-the-preview-must-carry-the-game-s-grade.md) |
| 6.09 | 2026-09-28 | A visibility range is measured from the node's ORIGIN | [docs/notes/06.09-a-visibility-range-is-measured-from-the-node.md](docs/notes/06.09-a-visibility-range-is-measured-from-the-node.md) |
| 6.10 | 2026-09-28 | Rim walls need rock behind them | [docs/notes/06.10-rim-walls-need-rock-behind-them.md](docs/notes/06.10-rim-walls-need-rock-behind-them.md) |
| 6.11 | 2026-09-28 | Judge the level from the GAME, not from a preview | [docs/notes/06.11-judge-the-level-from-the-game-not-from.md](docs/notes/06.11-judge-the-level-from-the-game-not-from.md) |
| 6.12 | 2026-09-28 | The junction archways had to be bored out | [docs/notes/06.12-the-junction-archways-had-to-be-bored-out.md](docs/notes/06.12-the-junction-archways-had-to-be-bored-out.md) |
| 6.13 | 2026-09-28 | Every module must be the SAME height, with its floor at zero | [docs/notes/06.13-every-module-must-be-the-same-height-with.md](docs/notes/06.13-every-module-must-be-the-same-height-with.md) |
| 6.14 | 2026-09-28 | Two kinds of render, for two different questions | [docs/notes/06.14-two-kinds-of-render-for-two-different-questions.md](docs/notes/06.14-two-kinds-of-render-for-two-different-questions.md) |
| 6.15 | 2026-09-28 | Dressing: floors, ambient, torches, windows | [docs/notes/06.15-dressing-floors-ambient-torches-windows.md](docs/notes/06.15-dressing-floors-ambient-torches-windows.md) |
| 6.16 | 2026-09-28 | The layout is the organic map, drawn onto the grid | [docs/notes/06.16-the-layout-is-the-organic-map-drawn-onto.md](docs/notes/06.16-the-layout-is-the-organic-map-drawn-onto.md) |
| 6.17 | 2026-09-28 | The tile grid must stay in phase with the cell grid | [docs/notes/06.17-the-tile-grid-must-stay-in-phase-with.md](docs/notes/06.17-the-tile-grid-must-stay-in-phase-with.md) |
| 6.18 | 2026-09-29 | Ten-change wave (2026-09-29): what was learned | [docs/notes/06.18-ten-change-wave-what-was-learned.md](docs/notes/06.18-ten-change-wave-what-was-learned.md) |
| 6.19 | 2026-09-30 | Floating skulls, wooden doors | [docs/notes/06.19-floating-skulls-wooden-doors.md](docs/notes/06.19-floating-skulls-wooden-doors.md) |
| 7 | 2026-10-06 | The boss hall | [docs/notes/07-the-boss-hall.md](docs/notes/07-the-boss-hall.md) |
| 8 | 2026-10-06 | Block and parry; the thrust's lunge | [docs/notes/08-block-and-parry-the-thrust-s-lunge.md](docs/notes/08-block-and-parry-the-thrust-s-lunge.md) |
| 9 | 2026-10-06 | Cage walk-up, slow drinking, no hand torch, new keys | [docs/notes/09-cage-walk-up-slow-drinking-no-hand-torch.md](docs/notes/09-cage-walk-up-slow-drinking-no-hand-torch.md) |
| 8 (second) | 2026-10-07 | Respawn anchors | [docs/notes/08b-respawn-anchors.md](docs/notes/08b-respawn-anchors.md) |
| 10 | 2026-10-07 | Cage stab, scene camera, slash through the crosshair | [docs/notes/10-cage-stab-scene-camera-slash-through-the-crosshair.md](docs/notes/10-cage-stab-scene-camera-slash-through-the-crosshair.md) |
| 11 | 2026-10-08 | The Shade and the hiding places | [docs/notes/11-the-shade-and-the-hiding-places.md](docs/notes/11-the-shade-and-the-hiding-places.md) |
| 12 | 2026-10-08 | The starting jail cell | [docs/notes/12-the-starting-jail-cell.md](docs/notes/12-the-starting-jail-cell.md) |
| 13 | 2026-10-08 | Prison cells in the corridors; yellow skeleton eyes | [docs/notes/13-prison-cells-in-the-corridors-yellow-skeleton-eyes.md](docs/notes/13-prison-cells-in-the-corridors-yellow-skeleton-eyes.md) |
| 14 | 2026-10-08 | The spear | [docs/notes/14-the-spear.md](docs/notes/14-the-spear.md) |
| 15 | 2026-10-08 | Faster stab, blood on the view, healing over time | [docs/notes/15-faster-stab-blood-on-the-view-healing-over.md](docs/notes/15-faster-stab-blood-on-the-view-healing-over.md) |
| 16 | 2026-10-08 | The Remnant | [docs/notes/16-the-remnant.md](docs/notes/16-the-remnant.md) |
| 17 | 2026-10-08 | The morgue, the royal sarcophagus, and getting up after death | [docs/notes/17-the-morgue-the-royal-sarcophagus-and-getting-up.md](docs/notes/17-the-morgue-the-royal-sarcophagus-and-getting-up.md) |
| 18 | 2026-10-08 | Puzzle rooms, shards and the great door | [docs/notes/18-puzzle-rooms-shards-and-the-great-door.md](docs/notes/18-puzzle-rooms-shards-and-the-great-door.md) |
| 19 | 2026-10-09 | Title screen, settings, saving | [docs/notes/19-title-screen-settings-saving.md](docs/notes/19-title-screen-settings-saving.md) |
| 20 | 2026-10-09 | The skeleton archer | [docs/notes/20-the-skeleton-archer.md](docs/notes/20-the-skeleton-archer.md) |
| 21 | 2026-10-09 | A bigger maze with rooms far apart | [docs/notes/21-a-bigger-maze-with-rooms-far-apart.md](docs/notes/21-a-bigger-maze-with-rooms-far-apart.md) |
| 22 | 2026-10-09 | Warden bots and the chest rooms | [docs/notes/22-warden-bots-and-the-chest-rooms.md](docs/notes/22-warden-bots-and-the-chest-rooms.md) |
| 23 | 2026-10-09 | Haul convoys | [docs/notes/23-haul-convoys.md](docs/notes/23-haul-convoys.md) |
| 24 | 2026-10-10 | Stagger, skeleton swords, patrols, the hand torch, the crystal mine | [docs/notes/24-stagger-skeleton-swords-patrols-the-hand-torch-the.md](docs/notes/24-stagger-skeleton-swords-patrols-the-hand-torch-the.md) |
| 25 | 2026-10-10 | Wheels instead of the hotbar; controller; thrown into stone; the mine's calm | [docs/notes/25-wheels-instead-of-the-hotbar-controller-thrown-into.md](docs/notes/25-wheels-instead-of-the-hotbar-controller-thrown-into.md) |
| 26 | 2026-10-10 | Death autosave, the marked map, pad cursor and keyboard, hiding carts | [docs/notes/26-death-autosave-the-marked-map-pad-cursor-and.md](docs/notes/26-death-autosave-the-marked-map-pad-cursor-and.md) |
| 27 | 2026-10-10 | The brick kit: the corridors rebuilt from the user's photos | [docs/notes/27-the-brick-kit-the-corridors-rebuilt-from-the.md](docs/notes/27-the-brick-kit-the-corridors-rebuilt-from-the.md) |
| 28 | 2026-10-10 | Darker, Tripo carts / wood / doors, skull cages in the Tripo cage | [docs/notes/28-darker-tripo-carts-wood-doors-skull-cages-in.md](docs/notes/28-darker-tripo-carts-wood-doors-skull-cages-in.md) |
| 29 | 2026-10-10 | Darker still, the Tripo torch everywhere, 5-piece doors, the domed prison | [docs/notes/29-darker-still-the-tripo-torch-everywhere-5-piece.md](docs/notes/29-darker-still-the-tripo-torch-everywhere-5-piece.md) |
| 30 | 2026-10-11 | Prison doorways, sticky quick slots, the centred map, pad inventory | [docs/notes/30-prison-doorways-sticky-quick-slots-the-centred-map.md](docs/notes/30-prison-doorways-sticky-quick-slots-the-centred-map.md) |
| 31 | 2026-10-11 | Prison ceiling and gates remade by Tripo, doors, respawn inventory | [docs/notes/31-prison-ceiling-and-gates-remade-by-tripo-doors.md](docs/notes/31-prison-ceiling-and-gates-remade-by-tripo-doors.md) |
| 32 | 2026-10-11 | Anchors save progress; the workbench | [docs/notes/32-anchors-save-progress-the-workbench.md](docs/notes/32-anchors-save-progress-the-workbench.md) |
| 33 | 2026-10-12 | Torch shadows | [docs/notes/33-torch-shadows.md](docs/notes/33-torch-shadows.md) |
| 34 | 2026-10-12 | Darker, physical falloff, a real base light | [docs/notes/34-darker-physical-falloff-a-real-base-light.md](docs/notes/34-darker-physical-falloff-a-real-base-light.md) |
| 35 | 2026-10-12 | No torchlight through walls; carts are searched, then hidden in | [docs/notes/35-no-torchlight-through-walls-carts-are-searched-then.md](docs/notes/35-no-torchlight-through-walls-carts-are-searched-then.md) |
| 36 | 2026-10-12 | A kicked door leaves its arch | [docs/notes/36-a-kicked-door-leaves-its-arch.md](docs/notes/36-a-kicked-door-leaves-its-arch.md) |
| 37 | 2026-10-12 | The kicked arch lined; searching a cart is a scene | [docs/notes/37-the-kicked-arch-lined-searching-a-cart-is.md](docs/notes/37-the-kicked-arch-lined-searching-a-cart-is.md) |
| 38 | 2026-10-14 | Night and the red moon | [docs/notes/38-night-and-the-red-moon.md](docs/notes/38-night-and-the-red-moon.md) |
| 39 | 2026-10-14 | Damp floors and drips | [docs/notes/39-damp-floors-and-drips.md](docs/notes/39-damp-floors-and-drips.md) |
| 40 | 2026-10-14 | The floor retextured damp by Tripo | [docs/notes/40-the-floor-retextured-damp-by-tripo.md](docs/notes/40-the-floor-retextured-damp-by-tripo.md) |
| 41 | 2026-10-14 | Wet floor by Tripo, puddle decals gone, steadier torch flicker | [docs/notes/41-wet-floor-by-tripo-puddle-decals-gone-steadier.md](docs/notes/41-wet-floor-by-tripo-puddle-decals-gone-steadier.md) |
| 42 | 2026-10-14 | Parry the bombers; the door's own Tripo arch; doors in 23 pieces | [docs/notes/42-parry-the-bombers-the-door-s-own-tripo.md](docs/notes/42-parry-the-bombers-the-door-s-own-tripo.md) |
| 43 | 2026-10-14 | The criers | [docs/notes/43-the-criers.md](docs/notes/43-the-criers.md) |
| 44 | 2026-10-14 | Parry read, potion cap, pad cursor, d-pad wheel, map pins, safe respawns | [docs/notes/44-parry-read-potion-cap-pad-cursor-d-pad.md](docs/notes/44-parry-read-potion-cap-pad-cursor-d-pad.md) |
| 45 | 2026-10-14 | The prison's frieze, generator and energy beams; no chest in the cells | [docs/notes/45-the-prison-s-frieze-generator-and-energy-beams.md](docs/notes/45-the-prison-s-frieze-generator-and-energy-beams.md) |
| 46 | 2026-10-15 | FOV slider, solo criers, crier block 25%, a white-purple moon, less red | [docs/notes/46-fov-slider-solo-criers-crier-block-25-a.md](docs/notes/46-fov-slider-solo-criers-crier-block-25-a.md) |
| 47 | 2026-10-15 | The morgue rebuilt: an enclosed vaulted hall with Tripo burial walls and slabs | [docs/notes/47-the-morgue-rebuilt-an-enclosed-vaulted-hall-with.md](docs/notes/47-the-morgue-rebuilt-an-enclosed-vaulted-hall-with.md) |
| 48 | 2026-10-15 | Wardens are ENFORCERS: the user's rigged model and baked animations | [docs/notes/48-wardens-are-enforcers-the-user-s-rigged-model.md](docs/notes/48-wardens-are-enforcers-the-user-s-rigged-model.md) |
| 49 | 2026-10-15 | Enforcers take turns; a harder throw; dimmer glow, ring eyes; the beam pose settled | [docs/notes/49-enforcers-take-turns-a-harder-throw-dimmer-glow.md](docs/notes/49-enforcers-take-turns-a-harder-throw-dimmer-glow.md) |
| 50 | 2026-10-15 | No room/anchor commentary; manholes and the sewer | [docs/notes/50-no-room-anchor-commentary-manholes-and-the-sewer.md](docs/notes/50-no-room-anchor-commentary-manholes-and-the-sewer.md) |
| 51 | 2026-10-15 | The enforcer's second delivery; manholes open from above only; walk-over pickup | [docs/notes/51-the-enforcer-s-second-delivery-manholes-open-from.md](docs/notes/51-the-enforcer-s-second-delivery-manholes-open-from.md) |
| 52 | 2026-10-15 | Enforcer hit reactions, a real parry stagger, the recoil looped, clean blends | [docs/notes/52-enforcer-hit-reactions-a-real-parry-stagger-the.md](docs/notes/52-enforcer-hit-reactions-a-real-parry-stagger-the.md) |
| 53 | 2026-10-15 | Enforcer eye rings traced from the lenses | [docs/notes/53-enforcer-eye-rings-traced-from-the-lenses.md](docs/notes/53-enforcer-eye-rings-traced-from-the-lenses.md) |
| 54 | 2026-10-15 | The sewer remade with Higgsfield | [docs/notes/54-the-sewer-remade-with-higgsfield.md](docs/notes/54-the-sewer-remade-with-higgsfield.md) |
| 55 | 2026-10-15 | The sewer remade again: one stone, mold and sludge, moss light | [docs/notes/55-the-sewer-remade-again-one-stone-mold-and.md](docs/notes/55-the-sewer-remade-again-one-stone-mold-and.md) |
| 56 | 2026-10-15 | The decrepit enforcer, in the sewer | [docs/notes/56-the-decrepit-enforcer-in-the-sewer.md](docs/notes/56-the-decrepit-enforcer-in-the-sewer.md) |
| 57 | 2026-10-16 | The decrepit's X eyes, chest crystal and fits; the channel grated over | [docs/notes/57-the-decrepit-s-x-eyes-chest-crystal-and.md](docs/notes/57-the-decrepit-s-x-eyes-chest-crystal-and.md) |
| 58 | 2026-10-16 | Three decrepits, the sewer lizard, a proud grating, walkable manholes | [docs/notes/58-three-decrepits-the-sewer-lizard-a-proud-grating.md](docs/notes/58-three-decrepits-the-sewer-lizard-a-proud-grating.md) |
| 59 | 2026-10-17 | The decrepit's new moves; every clip change seamless | [docs/notes/59-the-decrepit-s-new-moves-and-seamless-blending.md](docs/notes/59-the-decrepit-s-new-moves-and-seamless-blending.md) |

## Notes by source file

Which notes name each file (section numbers; `8b` = the second section 8).
Not exhaustive -- also grep `docs/notes/` as described above.

- `scenes/cell_door.tscn`: 12
- `scenes/crier.tscn`: 43
- `scenes/enemy.tscn`: 20, 22
- `scenes/hud.tscn`: 24
- `scenes/main.tscn`: 6.19, 19
- `scenes/player.tscn`: 9
- `scenes/title.tscn`: 19
- `scenes/torch.tscn`: 6.15, 6.18, 7, 19, 24, 27, 46
- `scripts/archer.gd`: 20
- `scripts/arrow.gd`: 20
- `scripts/attack_icons.gd`: 24
- `scripts/bone_cage.gd`: 6.18, 6.19, 28
- `scripts/boss_hall.gd`: 7
- `scripts/brick_level.gd`: 27
- `scripts/chest.gd`: 18
- `scripts/convoy.gd`: 23, 28
- `scripts/crier.gd`: 43, 48
- `scripts/damp.gd`: 39, 40, 41
- `scripts/decrepit.gd`: 56, 57, 59
- `scripts/decrepit_react.gd`: 56, 59
- `scripts/door_debris.gd`: 6.19
- `scripts/dungeon_room.gd`: 22, 24
- `scripts/enemy.gd`: 6.19, 8, 11, 20, 22, 23, 24, 25, 48, 52, 56
- `scripts/enemy_health_bar.gd`: 6.19
- `scripts/enforcer.gd`: 48, 51, 53, 59
- `scripts/enforcer_react.gd`: 52, 56, 59
- `scripts/explore_map.gd`: 6.18, 50
- `scripts/gate.gd`: 6.18
- `scripts/goo.gd`: 58
- `scripts/hand_torch.gd`: 24, 29
- `scripts/held_potion.gd`: 6.19
- `scripts/hiding_spot.gd`: 11, 26, 28, 35
- `scripts/hud.gd`: 6.19, 24
- `scripts/interact.gd`: 6.18
- `scripts/inventory.gd`: 6.19, 25
- `scripts/inventory_screen.gd`: 6.19, 30
- `scripts/item_drop.gd`: 6.19, 16, 51
- `scripts/item_icon.gd`: 6.19
- `scripts/item_slot.gd`: 6.19, 30
- `scripts/jail_cell.gd`: 12
- `scripts/manhole.gd`: 50, 51
- `scripts/maze.gd`: 6.18, 8b, 19, 22, 44, 56, 58
- `scripts/maze_graph.gd`: 6.16
- `scripts/mimic.gd`: 8
- `scripts/module_level.gd`: 6.00, 6.12, 6.19, 8b
- `scripts/module_maze.gd`: 6.00, 6.07, 8b, 27
- `scripts/morgue.gd`: 17
- `scripts/pad.gd`: 26, 30, 44
- `scripts/pad_keyboard_input.gd`: 26
- `scripts/patrol.gd`: 24
- `scripts/pause_menu.gd`: 19
- `scripts/player.gd`: 6.19, 17, 32, 44, 48, 50
- `scripts/portcullis.gd`: 6.18
- `scripts/puzzle_room.gd`: 18, 22
- `scripts/radial_menu.gd`: 25, 30, 44
- `scripts/respawn_anchor.gd`: 8b, 32
- `scripts/save_system.gd`: 19
- `scripts/settings_panel.gd`: 19, 46
- `scripts/sewer.gd`: 50, 55, 56, 57
- `scripts/sewer_lizard.gd`: 58
- `scripts/shard_door.gd`: 18
- `scripts/skeleton_eyes.gd`: 13
- `scripts/skeleton_sword.gd`: 24
- `scripts/sky_setup.gd`: 6.18
- `scripts/spear.gd`: 14
- `scripts/stalker.gd`: 11, 16, 22
- `scripts/title_screen.gd`: 19
- `scripts/torch.gd`: 6.18, 16, 24, 29, 35, 41, 50
- `scripts/wood_door.gd`: 6.18
- `scripts/workbench.gd`: 32
- `shaders/blood_screen.gdshader`: 15
- `shaders/debris_dissolve.gdshader`: 6.19
- `shaders/dread.gdshader`: 11, 16
- `shaders/energy_beam.gdshader`: 45
- `shaders/ghost.gdshader`: 11
- `shaders/lunge_lines.gdshader`: 10
- `shaders/sewer_stone.gdshader`: 55
- `shaders/sewer_water.gdshader`: 55
- `shaders/sky_clouds.gdshader`: 6.18, 38
- `shaders/spear_blast.gdshader`: 14
- `shaders/torch_flame.gdshader`: 6.18, 19
- `shaders/vine_leaf.gdshader`: 6.18
- `shaders/water_drip.gdshader`: 39
- `tools/benchmark.gd`: 6.11, 33
- `tools/build_brick_kit.py`: 27, 28
- `tools/build_decrepit.py`: 56, 57, 59
- `tools/build_enforcer.py`: 48, 51, 53
- `tools/build_gate_door.py`: 6.19
- `tools/build_modules.py`: 6.05, 6.18
- `tools/build_potion.py`: 6.19
- `tools/build_rock_pillar.py`: 6.18
- `tools/build_sewer_kit.py`: 54, 55
- `tools/build_vines.py`: 6.18
- `tools/build_wood_texture.py`: 6.19
- `tools/grade_texture.py`: 6.05
- `tools/preview_module_level.gd`: 6.11, 6.14
- `tools/tripo.ps1`: 7
- `tools/tripo_image.ps1`: 41, 45, 47
- `tools/tripo_texture.ps1`: 40, 41
- `tools/verify_collision.py`: 6.06
- `tools/verify_module_level.gd`: 6.06
- `tools/verify_modules.py`: 6.02
