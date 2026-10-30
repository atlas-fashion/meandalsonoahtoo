# Working rules for this project

Godot 4.7.2, Forward+, Vulkan. Target hardware is a **Quadro P620 driving a
3440×1440 ultrawide** — weak fill rate, 2 GB VRAM, ~5 megapixels. Every decision
below follows from that.

**Since 2026-10-06 the user's PC runs an RTX 3060 on that same 3440×1440
screen.** There the frame is torch shadow passes and, near the boss and the
surgery, CPU (enemy physics) -- not pixels. Note 112 has the 3060 baseline and
the retuned presets; measure against those, not the P620 tables below.

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
  latest is 131), headed `## NN. Title (YYYY-MM-DD)`, in the same style:
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
`scripts/maze.gd`), Player (`player.gd`), Player2, HUD (`hud.gd`), HUD2, Benchmark
(`tools/benchmark.gd`, idle without `--bench`), PauseMenu, SplitScreen
(`split_screen.gd`). Player2, HUD2 and SplitScreen take themselves away
outside CO-OP (note 79; `-- --coop`; with `--coop-monitors` player 2 plays
on another monitor, note 80). `--bench` or `--skip-title` skips the title. Autoloads: `Coop` (`coop.gd`: the players, whose input an event is,
polled input per player), `Graphics` (`graphics_settings.gd`), `Saves`
(`save_system.gd`), `Pad` (`pad.gd`), `Sandbox` (`sandbox.gd`).

**Co-op rule for new code** (note 79): there may be TWO players. Never
`get_first_node_in_group("player")` for "the player" -- use `Coop.nearest`,
`Coop.user_for` (an interactable's user), `Coop.all()`; check
`Coop.owns(player, event)` in a player's input handlers, poll with
`Coop.held` / `Coop.vector`, free or capture the mouse with `Coop.set_mouse`,
put a player's full-screen panel under `Coop.ui_root(player)`, give an
`Interact` call the player (`looked_at(..., by)`, `pressed(event, by)`,
`prompt.player`).

**`maze.gd` `_ready()` builds the whole level:** seed (`maze_seed`, or the
save's) -> level builder -> `_build_gates`, `_place_player`,
`_connect_player`, `_attach_explore_map` -> navmesh bake ->
`Graphics.apply_all` -> `_seal_cells`, `restore_world(save)`, `_populate()`,
`restore_player(save)` -> `is_built = true`, emits **`level_built`**.
`_populate()` spawns: boss, jail-cell stock, enemies, convoys, stalker,
decrepits, sewer lizards, rats (own `_rat_rng`), chests. Corridor skeletons only of the
types let out of containment (`released_hands`, note 120): at the start, only criers
and scouts (a lone scout is `scout_share` of the encounters, note 127).

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
  (`hiding_spot.gd`), clutter, damp (`damp.gd`), `morgue.gd`, the surgery (`surgery.gd` + `surgical_table.gd` + `surgery_vat.gd` + `surgery_power.gd` + `surgery_control.gd` + `surgery_piece.gd` + `surgeon_boss.gd`, notes 94-105; the chest room nearest the boss; every piece a Higgsfield model; rows of pushable vats, the claw on its gantry, the surgeon's booth, and under the floor -- through a hatch under one vat -- the powering room whose crystal switches it off), chest rooms
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
- Player & combat: `axe.gd` (the third weapon: slash, a throw that stays in
  its mark, berserk; note 84), `player.gd` (movement, sword, block/parry `_start_block`
  `_guard` `_on_guarded`, parry cues `parry_cue` (note 62), spear dash/stab `stab_at`, `take_damage`, `_die`,
  `_respawn`, `hide_in`, held by the surgery's claw `restrain` / `release` (note 96)), `spear.gd`, `hand_torch.gd`, `held_potion.gd`,
  `door_debris.gd` (kicked doors), `interact.gd` (shared E prompt).
- Enemies: `prosthetic.gd` (the skeleton types -- drill, sword, hammer, shield
  hands; `skeleton_shield.gd`; note 93), `enemy.gd` (skeleton; base class; also the boss via
  `scenes/boss.tscn` + `weak_point.gd`), `archer.gd` (the crossbow hand) + `arrow.gd`, `crier.gd`
  (flying heads, once "bombers"), `enforcer.gd` + `enforcer_react.gd` (once
  "warden bots"), `decrepit.gd` + `decrepit_react.gd` (moves: notes 59, 61, 65-71), `sewer_lizard.gd` +
  `goo.gd`, `stalker.gd` ("the Remnant" / "the Shade"), `mimic.gd`,
  `convoy.gd`, `collector.gd` (rounds up loose skeletons, note 120), `scout.gd` (the spearman
  robot that roams hunting the player; its body, rig and every animation are
  procedural in `scout_body.gd`: planted-foot gait, IK, springs, mantle cloth;
  note 127); helpers `patrol.gd`, `skeleton_eyes.gd`, `skeleton_sword.gd`,
  `enemy_health_bar.gd`, `death_burst.gd`, `item_drop.gd`, `shield_hitbox.gd`
  (bone hitboxes: both enforcers' shields, the decrepit's left foot; hit windows; notes 68-69). Clip changes on the
  enforcer and decrepit rigs are inertialized by `enforcer_react.gd`
  `crossfade` (note 59) -- use it for any new clip switch. The enforcer's beam
  timing and arm aim (`aim_at`): note 72. Every enemy clip plays at 1x on its
  move's own clock (hit windows, parry cues, an end), never synced to
  enemy.gd's wind-up timer (note 74). Rigs with 60 fps clips import at
  `animation/fps=60` (at 30 Godot resamples and swings limbs across the gaps).
- Before the dungeon: `intro.gd` (note 131: a new game starts on the forested hill of Vardia; story, 24 lessons, kidnapped into the cell; `-- --intro` / `-- --no-intro`), with `intro_world.gd`, `intro_lessons.gd`, `intro_sentinel.gd`, and the stand-ins `intro_flora.gd`, `intro_figure.gd`, `intro_post.gd`.
- After the surgeon: `boss_abduction.gd` (note 128: bagged, carried to the
  boss hall, a scout hooks the sack off; `_long_scene` is where the long
  cutscene goes; then the fight), started by maze.gd `take_to_the_boss`.
- World: `chest.gd`, `gate.gd`, `portcullis.gd`, `workbench.gd`,
  `screen_fade.gd`, `sky_setup.gd` (sky, moon).
- UI: `hud.gd`, `attack_icons.gd`, `inventory.gd` (data),
  `inventory_screen.gd`, `item_slot.gd`, `item_icon.gd`,
  `consumable_type.gd`, `radial_menu.gd` (item wheels), `explore_map.gd`
  (minimap; the full map is the inventory's MAP page, M -- note 60), `pause_menu.gd` (owns settings `SPEC`),
  `settings_panel.gd`, `title_screen.gd`, `pad.gd` +
  `pad_keyboard_input.gd` (controller, on-screen keyboard).
- Sandbox (test mode, never saves): `sandbox.gd` (autoload `Sandbox`),
  `sandbox_world.gd` (test plane, spawning, teleports), `sandbox_menu.gd` (` key).
- Rats (notes 77, 78): `rat.gd` (the harmless rat -- the user's Tripo rat,
  `rat_look.gd` + models/rat.glb from tools/build_rat.py; grabbed with E into
  the hand by its tail, thrown it scares -- enemy.gd / crier.gd `scare`),
  `rat_model.gd` (the robot rat's procedural look; its glow is the enforcer's
  crystal colour), `rat_control.gd` (`player.rats`: a live rat held by the
  tail and thrown, the robot rat in hand, set down, driven
  through its eyes with `player.remote_view`, detonated), `robot_rat.gd` (its
  body and camera). Items of kind "Utility" ride the wheel their ITEMS
  "wheel" names (inventory.gd `wheel_of`).
- Saving: `save_system.gd` (4 slots, `request()` / `save_now()`, autosave);
  maze.gd supplies `save_state()`, `restore_world()`, `restore_player()`.

**Running.** On the `tflfr` Windows machine the Godot binary is
`C:\Users\tflfr\Desktop\Godot_v4.7.2-stable_win64.exe` (examples here say
`godot`). Game args go after `--` (`OS.get_cmdline_user_args()`): `title_screen.gd` reads `--sandbox` (straight into
the sandbox, note 60);
`tools/benchmark.gd` reads `--bench --ablate --at= --only= --set= --shot --swing --no-trail
--preset=<name> --size=WxH --nocull --flat`; `maze.gd` reads `--no-enemies`
and `--modules`; `brick_level.gd` reads `--brick-skip=a,b`. Harnesses are
`extends SceneTree` scripts run with `--script res://tools/<x>.gd` (see
section 4 for the headless traps). Asset build pipelines (Blender headless,
then `godot --headless --import --path .`) are documented in
`tools/README.md`; read it before touching any generated model. The enforcers'
attack timings are markers on their clips in `tools/timing_preview/*.tscn`, and
dragging one rewrites its constant (notes 63-64) -- bind any new timing there too.

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
| 60 | 2026-10-17 | Sandbox mode; the map becomes an inventory page | [docs/notes/60-sandbox-mode-the-map-becomes-an-inventory.md](docs/notes/60-sandbox-mode-the-map-becomes-an-inventory.md) |
| 61 | 2026-10-17 | The decrepit's dash slides in; every move close in | [docs/notes/61-the-decrepit-s-dash-slides-every-move-close.md](docs/notes/61-the-decrepit-s-dash-slides-every-move-close.md) |
| 62 | 2026-10-17 | Parry cues: the attack listens for block | [docs/notes/62-parry-cues-the-attack-listens-for-block.md](docs/notes/62-parry-cues-the-attack-listens-for-block.md) |
| 63 | 2026-10-17 | Timing preview: every enemy's timings on the animation timeline | [docs/notes/63-timing-preview-every-enemy-s-timings-on.md](docs/notes/63-timing-preview-every-enemy-s-timings-on.md) |
| 64 | 2026-10-17 | Drag a timing marker to change the timing; the enforcers only | [docs/notes/64-drag-a-timing-marker-to-change-the.md](docs/notes/64-drag-a-timing-marker-to-change-the.md) |
| 65 | 2026-10-17 | Every clip its own parry marker; the dash's slide is a fixed length | [docs/notes/65-every-clip-its-own-parry-marker-the.md](docs/notes/65-every-clip-its-own-parry-marker-the.md) |
| 66 | 2026-10-17 | Several hits and parry cues per move; add them on the timeline | [docs/notes/66-several-hits-and-parry-cues-per-move.md](docs/notes/66-several-hits-and-parry-cues-per-move.md) |
| 67 | 2026-10-17 | The dash always closes the gap first | [docs/notes/67-the-dash-always-closes-the-gap-first.md](docs/notes/67-the-dash-always-closes-the-gap-first.md) |
| 68 | 2026-10-17 | Shield hitboxes on both enforcers; hit windows | [docs/notes/68-shield-hitboxes-on-both-enforcers-hit-windows.md](docs/notes/68-shield-hitboxes-on-both-enforcers-hit-windows.md) |
| 69 | 2026-10-17 | The dropkick's left-foot hitbox | [docs/notes/69-the-dropkick-s-left-foot-hitbox.md](docs/notes/69-the-dropkick-s-left-foot-hitbox.md) |
| 70 | 2026-10-17 | The dash arrives in their face, and only from 7 m | [docs/notes/70-the-dash-arrives-in-their-face-from.md](docs/notes/70-the-dash-arrives-in-their-face-from.md) |
| 71 | 2026-10-17 | No dash at close range | [docs/notes/71-no-dash-at-close-range.md](docs/notes/71-no-dash-at-close-range.md) |
| 72 | 2026-10-17 | The enforcer's beam fires with the recoil; the arms aim it; seamless blends | [docs/notes/72-the-enforcer-s-beam-fires-with-the-recoil.md](docs/notes/72-the-enforcer-s-beam-fires-with-the-recoil.md) |
| 73 | 2026-10-17 | The enforcer's swipe, re-baked by the user | [docs/notes/73-the-enforcer-s-swipe-re-baked-by-the-user.md](docs/notes/73-the-enforcer-s-swipe-re-baked-by-the-user.md) |
| 74 | 2026-10-17 | Every enforcer clip at 1x: the swipe a move of its own | [docs/notes/74-every-enforcer-clip-at-1x-the-swipe-a-move.md](docs/notes/74-every-enforcer-clip-at-1x-the-swipe-a-move.md) |
| 75 | 2026-10-17 | The enforcer's swipe loop: swipe 2 dashes; beams broken off | [docs/notes/75-the-enforcer-s-swipe-loop.md](docs/notes/75-the-enforcer-s-swipe-loop.md) |
| 76 | 2026-10-17 | The title theme | [docs/notes/76-the-title-theme.md](docs/notes/76-the-title-theme.md) |
| 77 | 2026-10-18 | Rats: utility items, live rats thrown, the robot rat | [docs/notes/77-rats-utility-items-and-the-robot-rat.md](docs/notes/77-rats-utility-items-and-the-robot-rat.md) |
| 78 | 2026-10-18 | The Tripo rat, animated, and held by the tail | [docs/notes/78-the-tripo-rat-animated-and-held-by-the-tail.md](docs/notes/78-the-tripo-rat-animated-and-held-by-the-tail.md) |
| 79 | 2026-10-18 | Local co-op split-screen | [docs/notes/79-local-co-op-split-screen.md](docs/notes/79-local-co-op-split-screen.md) |
| 80 | 2026-10-18 | Co-op: what its frame time costs, the torch share, two monitors | [docs/notes/80-co-op-cost-cuts-and-two-monitors.md](docs/notes/80-co-op-cost-cuts-and-two-monitors.md) |
| 81 | 2026-10-20 | The decrepit: more time between attacks | [docs/notes/81-decrepit-more-time-between-attacks.md](docs/notes/81-decrepit-more-time-between-attacks.md) |
| 82 | 2026-10-19 | Co-op: each player on the other's map; player 1's HUD no longer squashed | [docs/notes/82-co-op-partner-on-the-map-and-player-1-s-canvas.md](docs/notes/82-co-op-partner-on-the-map-and-player-1-s-canvas.md) |
| 83 | 2026-10-20 | Robot rats stack to 10 | [docs/notes/83-robot-rats-stack-to-10.md](docs/notes/83-robot-rats-stack-to-10.md) |
| 84 | 2026-10-20 | The axe: slash, a throw that stays in its mark, berserk | [docs/notes/84-the-axe.md](docs/notes/84-the-axe.md) |
| 85 | 2026-10-20 | The axe: alternating slashes every 0.5 s, 1 s in its mark | [docs/notes/85-axe-alternating-faster-slash.md](docs/notes/85-axe-alternating-faster-slash.md) |
| 86 | 2026-10-20 | The axe: no crash when what it is stuck in is freed | [docs/notes/86-axe-freed-target-crash.md](docs/notes/86-axe-freed-target-crash.md) |
| 87 | 2026-10-20 | The heavy axe: a delayed vertical chop for 60, a planted throw, 25% slower carrying it | [docs/notes/87-heavy-axe.md](docs/notes/87-heavy-axe.md) |
| 88 | 2026-10-20 | The axe a little heavier; the chop's white streak | [docs/notes/88-axe-heavier-and-its-streak.md](docs/notes/88-axe-heavier-and-its-streak.md) |
| 89 | 2026-10-20 | Berserk heals 7 a second | [docs/notes/89-berserk-heals.md](docs/notes/89-berserk-heals.md) |
| 90 | 2026-10-20 | A little slower carrying the axe | [docs/notes/90-axe-carry-slower.md](docs/notes/90-axe-carry-slower.md) |
| 91 | 2026-10-20 | Berserk as fast as ghost mode | [docs/notes/91-berserk-at-ghost-speed.md](docs/notes/91-berserk-at-ghost-speed.md) |
| 92 | 2026-10-20 | No sticking to corners: move_and_slide plus a slip round arch legs and pillars | [docs/notes/92-no-sticking-to-corners.md](docs/notes/92-no-sticking-to-corners.md) |
| 93 | 2026-10-20 | Skeleton types: drill, sword, hammer, shield and crossbow hands | [docs/notes/93-skeleton-prosthesis-types.md](docs/notes/93-skeleton-prosthesis-types.md) |
| 94 | 2026-10-21 | The surgery: the surgical table, depowered not killed | [docs/notes/94-the-surgery-and-the-surgical-table.md](docs/notes/94-the-surgery-and-the-surgical-table.md) |
| 95 | 2026-10-21 | The surgery refurnished after a reference (Higgsfield); the table fixed, a ceiling claw | [docs/notes/95-the-surgery-refurnished-the-table-fixed-a-ceiling-claw.md](docs/notes/95-the-surgery-refurnished-the-table-fixed-a-ceiling-claw.md) |
| 96 | 2026-10-21 | The surgery an open medieval hall (no pillars, a timber roof); the claw carries you to the table | [docs/notes/96-the-surgery-an-open-medieval-hall-the-claw-carries-you-to-the-table.md](docs/notes/96-the-surgery-an-open-medieval-hall-the-claw-carries-you-to-the-table.md) |
| 97 | 2026-10-21 | The maze as it was before the surgery; the surgery in the chest room nearest the boss | [docs/notes/97-the-maze-as-it-was-the-surgery-in-the-room-nearest-the-boss.md](docs/notes/97-the-maze-as-it-was-the-surgery-in-the-room-nearest-the-boss.md) |
| 98 | 2026-10-22 | The surgery rebuilt: elaborate walls, a study, testing areas, a shipping line -- every piece from Higgsfield | [docs/notes/98-the-surgery-rebuilt-every-piece-from-higgsfield.md](docs/notes/98-the-surgery-rebuilt-every-piece-from-higgsfield.md) |
| 99 | 2026-10-22 | The surgery redone: a maze of shelves, a gantry claw that slams late, the surgeon in his booth (a cutscene ends it) | [docs/notes/99-the-surgery-a-shelf-maze-a-gantry-claw-the-surgeon-in-his-booth.md](docs/notes/99-the-surgery-a-shelf-maze-a-gantry-claw-the-surgeon-in-his-booth.md) |
| 100 | 2026-10-23 | The shelves face out and stand taller, the lift in its corner (it was on the table), one palette, slower slams | [docs/notes/100-shelves-face-out-the-lift-in-its-corner-one-palette.md](docs/notes/100-shelves-face-out-the-lift-in-its-corner-one-palette.md) |
| 101 | 2026-10-23 | The surgery's torches on the colonettes, leaded glass in the booth, a second claw that beams (and stops before the slam) | [docs/notes/101-torches-on-the-colonettes-leaded-glass-the-beam-claw.md](docs/notes/101-torches-on-the-colonettes-leaded-glass-the-beam-claw.md) |
| 102 | 2026-10-25 | The surgery's shelves turned to rows of pushable vats; its power a crystal in a room under the floor, through a hatch under one vat; the beam claw gone; the surgeon gone once it is pulled | [docs/notes/102-vats-a-hatch-the-powering-room-and-its-crystal.md](docs/notes/102-vats-a-hatch-the-powering-room-and-its-crystal.md) |
| 103 | 2026-10-25 | The claw opens and shakes before it drops; a block is caught, a parry knocks it limp 2 s; the vats a bit faster | [docs/notes/103-the-claw-opens-shakes-and-can-be-parried-limp.md](docs/notes/103-the-claw-opens-shakes-and-can-be-parried-limp.md) |
| 104 | 2026-10-25 | The surgery: an entrance scene and bars; vat lids; real soldiers in the pens; the claw throws pieces and soldiers; the way up to the booth over the table and the vats | [docs/notes/104-entrance-scene-bars-lids-pen-soldiers-claw-moves-booth-route.md](docs/notes/104-entrance-scene-bars-lids-pen-soldiers-claw-moves-booth-route.md) |
| 105 | 2026-10-25 | The booth lower, E at its door, the kick flings the surgeon out of the window, a lever you flip; the way in really blocked, its scene on the shove; pens in the sandbox; a bigger wind-up; the surgeon a boss (infrastructure) | [docs/notes/105-booth-lower-kick-lever-blocking-vat-surgeon-boss.md](docs/notes/105-booth-lower-kick-lever-blocking-vat-surgeon-boss.md) |
| 106 | 2026-10-25 | Vats grabbed (E): pushed, pulled, turned slowly, no fighting meanwhile; the claw idle once the booth door is in; caught under the claw, not inside it | [docs/notes/106-grab-vats-claw-idles-when-unmanned-caught-under-the-claw.md](docs/notes/106-grab-vats-claw-idles-when-unmanned-caught-under-the-claw.md) |
| 107 | 2026-10-25 | The surgery's vats in a checkerboard round a wide open circle, a vat always over the hatch | [docs/notes/107-vats-in-a-checkerboard-open-circle-round-the-middle.md](docs/notes/107-vats-in-a-checkerboard-open-circle-round-the-middle.md) |
| 108 | 2026-10-25 | The control room up to the roof (the gantry kept off it), its door the dungeon doors' size; the vats checkered close round the table, the floor open beyond | [docs/notes/108-booth-to-the-roof-dungeon-door-vats-close-round-the-table.md](docs/notes/108-booth-to-the-roof-dungeon-door-vats-close-round-the-table.md) |
| 109 | 2026-10-25 | The claw home over the table when it dies; the surgeon takes it onto his back (an ambush at the hatch, or after the lever) and speaks; a stand-in body with iron limbs and a needle; his dash, spin and slam | [docs/notes/109-surgeon-takes-the-claw-two-openings-stand-in-body-three-moves.md](docs/notes/109-surgeon-takes-the-claw-two-openings-stand-in-body-three-moves.md) |
| 110 | 2026-10-25 | The surgeon deals his moves in turn, the needle dash first -- hopping back when too close, the needle blazing and leaving a streak; the booth route's scene waits until they are down out of the booth; the claw bigger (x1.3) and carrying higher | [docs/notes/110-the-needle-dash-seen-booth-scene-waits-bigger-claw.md](docs/notes/110-the-needle-dash-seen-booth-scene-waits-bigger-claw.md) |
| 111 | 2026-10-26 | The surgeon's claw taken off him and kept (a scene, the inventory's Surgeon's Claw); hold E to move a vat, no turning while pushing; the claw's motion fluid (eased hoist, drawn between ticks, sprung fingers) | [docs/notes/111-take-the-surgeons-claw-hold-e-vats-fluid-claw.md](docs/notes/111-take-the-surgeons-claw-hold-e-vats-fluid-claw.md) |
| 112 | 2026-10-26 | Realistic fog that limits the view (depth fog total at 60 m, a volumetric mist only shadowed lights light, nothing drawn past the fog); the presets retuned for the RTX 3060 at 3440x1440; `--ablate` from the settings in effect, a gpu ms column | [docs/notes/112-fog-and-the-3060.md](docs/notes/112-fog-and-the-3060.md) |
| 113 | 2026-10-27 | Ghost mode only on a fresh press: not when Shift was already down as a menu, scene, pause, respawn or focus loss ended, nor in a Ctrl/Alt/Win chord; pad bindings read from the pad, not the latched action | [docs/notes/113-ghost-only-on-a-fresh-press.md](docs/notes/113-ghost-only-on-a-fresh-press.md) |
| 114 | 2026-10-27 | No moonlight through the roofs: one-sided roofs (the surgery's ceiling, the prison's inside-out dome) never cast for the moon; a shadows-only box over each (`BrickLevel.moon_shade`) | [docs/notes/114-no-moonlight-through-roofs.md](docs/notes/114-no-moonlight-through-roofs.md) |
| 115 | 2026-10-27 | The enforcer's feet stay planted: each tick the body moves as far as the walk's planted foot sweeps (read from the clip's tracks); the walk backwards when backing off; a stop finishes the step | [docs/notes/115-enforcer-feet-planted-the-gait.md](docs/notes/115-enforcer-feet-planted-the-gait.md) |
| 116 | 2026-10-27 | The enforcer's walk a little smoother: each tick's step is the planted foot's speed averaged over 0.1 s of clip (`GAIT_SMOOTH`), the dead stop spread over a few ticks for a little slip | [docs/notes/116-enforcer-walk-smoother.md](docs/notes/116-enforcer-walk-smoother.md) |
| 117 | 2026-10-27 | Sandbox: T / pad Y on the map teleports to the pin under the cursor or the spot (rock goes to the nearest open cell; the floor and navmesh found there); "Heal to full" and "5 health potions" in the menu | [docs/notes/117-sandbox-map-teleport-and-heals.md](docs/notes/117-sandbox-map-teleport-and-heals.md) |
| 118 | 2026-10-27 | The surgery: the pen soldiers face the hall (they faced their pens' back wall); the black slits between the raised brick pieces backed with a second skin of the same brick (`BackingBrick`, no shadows) | [docs/notes/118-surgery-soldiers-face-the-hall-no-black-gaps.md](docs/notes/118-surgery-soldiers-face-the-hall-no-black-gaps.md) |
| 119 | 2026-10-28 | The surgery's soldiers and surgeon face the player moving and fighting: they wrote a world heading into a local `rotation.y` under the turned surgery (soldiers under a top-level `Soldiers` node; the surgeon's `_face_yaw` sets `global_rotation`) | [docs/notes/119-surgery-enemies-turn-in-world-yaw.md](docs/notes/119-surgery-enemies-turn-in-world-yaw.md) |
| 120 | 2026-10-28 | Containment: the maze starts with only criers; one prison-look containment block per skeleton type (caged prisoners, mechanical back doors they walk out through once its enforcers are down and the crystal is out); each type let out joins the spawn pool; patrols and convoys rare; the collector (a lone enforcer chaining loose subjects); the surgery bolted until every block is open, the great door until the surgeon is dead | [docs/notes/120-containment-and-the-spawn-pool.md](docs/notes/120-containment-and-the-spawn-pool.md) |
| 121 | 2026-10-27 | A damp sewer: thick wet air while below, a drifting ground mist on the water (a world-space fog volume per cell), the moss glowing in it, drips off the crowns, wet walls; enemies more often and mostly alone (1 / 2 / 3 at 66 / 24 / 10%, an enforcer only in some twos and threes); the floor's black joints now dark wet earth | [docs/notes/121-damp-sewer-mist-solo-spawns-dirt-floor-joints.md](docs/notes/121-damp-sewer-mist-solo-spawns-dirt-floor-joints.md) |
| 122 | 2026-10-28 | Containment exits really lead into the maze: each block's cells opened at the back onto a corridor, or a passage dug to one (`module_level._make_back_exits`); an iron bulkhead round each back door; the prisoners walk out along it and stay loose where they come out, 3 more of the type elsewhere; 3 collectors | [docs/notes/122-containment-exits-into-the-maze.md](docs/notes/122-containment-exits-into-the-maze.md) |
| 123 | 2026-10-28 | Enemies spawn more often: 0.42 per corridor cell (was 0.32); a trickle (`_tick_spawns`) rolls one more encounter every 8 s, 35 m off and out of sight, while fewer are alive than came at the population; loose subjects kept up the same way | [docs/notes/123-more-spawns-and-the-trickle.md](docs/notes/123-more-spawns-and-the-trickle.md) |
| 124 | 2026-10-28 | Fewer criers (`flyer_share` 0.25, was 0.45); criers patrol the corridors (`crier._patrol`: navmesh legs between corridor points at 3.2 m/s, no shut doors) and on patrol see ahead (150 degree cone, 3 m all round), rushing the face once they see the player | [docs/notes/124-fewer-criers-on-patrol.md](docs/notes/124-fewer-criers-on-patrol.md) |
| 125 | 2026-10-28 | Every corridor enemy patrols (`patrol_share` 1.0; lone skeletons and packs without an enforcer never got a patrol before; loose subjects too); patrol.gd picks goals in reach from shared buckets, takes part-way routes (up to a shut door), backs off when stuck and avoids that way, followers steer by the navmesh; criers likewise. Standing still 62% -> 8% of the time | [docs/notes/125-every-enemy-patrols-smartly.md](docs/notes/125-every-enemy-patrols-smartly.md) |
| 126 | 2026-10-28 | Enemies keep to their area (45 m of where their patrol began) and stop 2-6 s at each leg's end to look about, study the nearest wall, or listen back the way they came; criers look about at their stops; nothing but the player opens doors. Coins lying in the containment rooms (5 piles a block, saved when taken), every coin drop with a small golden flame rising off it; far drops rest | [docs/notes/126-purposeful-wandering-and-room-coins.md](docs/notes/126-purposeful-wandering-and-room-coins.md) |
| 127 | 2026-10-28 | The scout: a spearman robot in rusted riveted plate with a ragged mantle and blue goggle eyes, built from primitives into one skinned mesh and animated procedurally (feet planted by a stepping gait, two-bone IK, the spear leading the arms, damped springs, a verlet mantle); roams alone on patrol, hunts on sight, circles, tri-stab / knockdown swipe / spear dash, searches where it lost them; 110 health | [docs/notes/127-the-scout.md](docs/notes/127-the-scout.md) |
| 128 | 2026-10-29 | Bagged and carried to the boss: once the surgeon is dead and his claw kept, a sack over the head, carried to the throne hall, a scripted scout hooks it off with its spear; `_long_scene` (boss_abduction.gd) is the placeholder for the long cutscene; then the fight. The great door wants no shards (E opens it once the surgery is done) | [docs/notes/128-bagged-and-carried-to-the-boss.md](docs/notes/128-bagged-and-carried-to-the-boss.md) |
| 129 | 2026-10-29 | The scout tuned: 160 health (enforcer 240), hunts at 5.5 m/s, every move at TEMPO 1.25 (the swipe's sweep at 1x), shorter pauses; the tri-stab drives each stab onto them (1-3 m, opened from 3.4 m); two-move chains now and then (never three); it punishes openings, steps out of swings, circles a raised guard to the side, dashes at someone backing off | [docs/notes/129-scout-tuning.md](docs/notes/129-scout-tuning.md) |
| 130 | 2026-10-29 | The small health potion: 20 health (half) in 1.5 s (half; `ConsumableType.drink_scale`), a smaller flask on the floor, in the hand and as an icon; the sewer lizards drop it (0.3 a roll) instead of the full one | [docs/notes/130-small-health-potion.md](docs/notes/130-small-health-potion.md) |
| 131 | 2026-10-30 | The intro outside the dungeon (stand-ins until Higgsfield can generate): the knight's hilt, the study, the forested hill of Vardia; 24 lessons teach every control; the sentinel; kidnapped at the altar, waking in the cell. Lizards always drop the small heal | [docs/notes/131-intro-vardia-lessons-kidnapped-lizards-always-heal.md](docs/notes/131-intro-vardia-lessons-kidnapped-lizards-always-heal.md) |

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
- `scripts/archer.gd`: 20, 77, 92, 93
- `scripts/arrow.gd`: 20, 79, 93
- `scripts/attack_icons.gd`: 24, 77, 79, 84
- `scripts/axe.gd`: 84, 85, 86, 87, 88, 89, 90, 91
- `scripts/boss_abduction.gd`: 128
- `scripts/bone_cage.gd`: 6.18, 6.19, 28, 79
- `scripts/boss_hall.gd`: 7
- `scripts/brick_level.gd`: 27, 96, 102, 114, 121
- `scripts/chest.gd`: 18, 79
- `scripts/consumable_type.gd`: 130
- `scripts/coop.gd`: 79, 80
- `scripts/corner_slip.gd`: 92
- `scripts/coop_avatar.gd`: 79
- `scripts/collector.gd`: 120, 122, 125
- `scripts/convoy.gd`: 23, 28, 79, 93, 120
- `scripts/crier.gd`: 43, 48, 60, 77, 79, 124, 125, 126
- `scripts/damp.gd`: 39, 40, 41
- `scripts/decrepit.gd`: 56, 57, 59, 60, 61, 62, 64, 65, 66, 67, 68, 69, 70, 71, 77, 81, 92
- `scripts/decrepit_react.gd`: 56, 59
- `scripts/door_debris.gd`: 6.19
- `scripts/dungeon_room.gd`: 22, 24, 79, 93, 114, 120, 122, 126
- `scripts/enemy.gd`: 6.19, 8, 11, 20, 22, 23, 24, 25, 48, 52, 56, 60, 77, 79, 92, 93, 120, 131
- `scripts/enemy_health_bar.gd`: 6.19
- `scripts/enforcer.gd`: 48, 51, 53, 59, 64, 68, 72, 73, 74, 75, 92, 115, 116
- `scripts/enforcer_react.gd`: 52, 56, 59, 72
- `scripts/explore_map.gd`: 6.18, 50, 60, 79, 82, 117
- `scripts/gate.gd`: 6.18
- `scripts/goo.gd`: 58, 79
- `scripts/graphics_settings.gd`: 79, 80, 112, 121
- `scripts/hand_torch.gd`: 24, 29
- `scripts/held_potion.gd`: 6.19, 130
- `scripts/hiding_spot.gd`: 11, 26, 28, 35, 79
- `scripts/hud.gd`: 6.19, 24, 79, 84
- `scripts/interact.gd`: 6.18, 79
- `scripts/intro.gd`, `scripts/intro_figure.gd`, `scripts/intro_flora.gd`, `scripts/intro_lessons.gd`, `scripts/intro_post.gd`, `scripts/intro_sentinel.gd`, `scripts/intro_world.gd`: 131
- `scripts/inventory.gd`: 6.19, 25, 77, 83, 84, 102, 111, 130
- `scripts/inventory_screen.gd`: 6.19, 30, 60, 77, 78, 79, 84, 117, 130
- `scripts/item_drop.gd`: 6.19, 16, 51, 79, 126, 130
- `scripts/item_icon.gd`: 6.19, 77, 84, 111, 130
- `scripts/item_slot.gd`: 6.19, 30
- `scripts/jail_cell.gd`: 12
- `scripts/manhole.gd`: 50, 51, 79, 121
- `scripts/maze.gd`: 6.18, 8b, 19, 22, 44, 56, 58, 60, 77, 79, 93, 94, 97, 112, 120, 121, 122, 123, 124, 125, 127, 128, 131
- `scripts/maze_graph.gd`: 6.16
- `scripts/mimic.gd`: 8, 60, 79
- `scripts/module_level.gd`: 6.00, 6.12, 6.19, 8b, 94, 96, 97, 102, 112, 122
- `scripts/module_maze.gd`: 6.00, 6.07, 8b, 27
- `scripts/morgue.gd`: 17, 79, 94
- `scripts/pad.gd`: 26, 30, 44, 79, 80
- `scripts/pad_keyboard_input.gd`: 26
- `scripts/patrol.gd`: 24, 125, 126, 127
- `scripts/pause_menu.gd`: 19
- `scripts/player.gd`: 6.19, 17, 32, 44, 48, 50, 60, 62, 75, 77, 78, 79, 84, 87, 91, 92, 96, 106, 111, 113, 130
- `scripts/portcullis.gd`: 6.18
- `scripts/prosthetic.gd`: 93
- `scripts/puzzle_room.gd`: 18, 22, 79
- `scripts/radial_menu.gd`: 25, 30, 44, 77, 79
- `scripts/rat.gd`: 77, 78, 79
- `scripts/rat_control.gd`: 77, 78, 79
- `scripts/rat_look.gd`: 78
- `scripts/rat_model.gd`: 77
- `scripts/respawn_anchor.gd`: 8b, 32, 79
- `scripts/robot_rat.gd`: 77
- `scripts/save_system.gd`: 19, 60, 79, 131
- `scripts/sandbox.gd`: 60, 68
- `scripts/sandbox_menu.gd`: 60, 68, 77, 84, 117, 130
- `scripts/sandbox_world.gd`: 60, 77, 79, 93, 94, 102, 117, 127
- `scripts/scout.gd`: 127, 128, 129
- `scripts/scout_body.gd`: 127, 128, 129
- `scripts/settings_panel.gd`: 19, 46, 80, 112
- `scripts/sewer.gd`: 50, 55, 56, 57, 79, 112, 121
- `scripts/split_screen.gd`: 79, 80, 82
- `scripts/sewer_lizard.gd`: 58, 60, 92, 130, 131
- `scripts/shard_door.gd`: 18, 79, 120, 128
- `scripts/shield_hitbox.gd`: 68, 69
- `scripts/skeleton_eyes.gd`: 13
- `scripts/skeleton_sword.gd`: 24, 93
- `scripts/skeleton_shield.gd`: 93
- `scripts/sky_setup.gd`: 6.18
- `scripts/spear.gd`: 14, 78, 79
- `scripts/surgery.gd`: 94, 95, 96, 98, 99, 100, 101, 102, 104, 105, 106, 107, 108, 111, 114, 118, 119, 120, 128
- `scripts/surgery_beam_claw.gd`: 101 (deleted in 102)
- `scripts/surgery_power.gd`: 102, 109, 121
- `scripts/surgery_vat.gd`: 102, 103, 104, 105, 106, 111, 120
- `scripts/surgery_piece.gd`: 104, 110
- `scripts/subtitles.gd`: 109
- `scripts/surgeon_boss.gd`: 105, 109, 110, 111, 119
- `scripts/surgery_control.gd`: 99, 100, 101, 102, 104, 105, 106, 108, 109, 110, 111, 128
- `scripts/surgical_table.gd`: 94, 95, 96, 98, 99, 100, 101, 102, 103, 104, 105, 106, 108, 109, 110, 111
- `scripts/stalker.gd`: 11, 16, 22, 60, 79
- `scripts/title_screen.gd`: 19, 60, 76, 79, 80
- `scripts/torch.gd`: 6.18, 16, 24, 29, 35, 41, 50, 79, 80
- `scripts/wood_door.gd`: 6.18, 79
- `scripts/workbench.gd`: 32, 77, 79
- `shaders/berserk_ground.gdshader`: 84
- `shaders/blood_screen.gdshader`: 15
- `shaders/burlap_bag.gdshader`: 128
- `shaders/debris_dissolve.gdshader`: 6.19
- `shaders/dread.gdshader`: 11, 16
- `shaders/energy_beam.gdshader`: 45
- `shaders/floor_dirt.gdshader`: 121
- `shaders/ghost.gdshader`: 11
- `shaders/intro_foliage.gdshader`, `shaders/intro_terrain.gdshader`: 131
- `shaders/lunge_lines.gdshader`: 10
- `shaders/sewer_mist.gdshader`: 121
- `shaders/sewer_stone.gdshader`: 55, 121
- `shaders/sewer_water.gdshader`: 55
- `shaders/surgery_cable.gdshader`: 94, 98
- `shaders/surgery_glass.gdshader`: 101
- `shaders/sky_clouds.gdshader`: 6.18, 38
- `shaders/spear_blast.gdshader`: 14
- `shaders/torch_flame.gdshader`: 6.18, 19
- `shaders/vine_leaf.gdshader`: 6.18
- `shaders/water_drip.gdshader`: 39, 121
- `tools/benchmark.gd`: 6.11, 33, 112
- `tools/build_brick_kit.py`: 27, 28
- `tools/timing_preview/timing_preview.gd`: 63, 64, 65, 66, 68, 69, 72, 74, 75
- `tools/build_decrepit.py`: 56, 57, 59, 66
- `tools/build_enforcer.py`: 48, 51, 53, 73, 75
- `tools/build_gate_door.py`: 6.19
- `tools/build_modules.py`: 6.05, 6.18
- `tools/build_potion.py`: 6.19
- `tools/build_rat.py`: 78
- `tools/build_rock_pillar.py`: 6.18
- `tools/build_sewer_kit.py`: 54, 55
- `tools/build_surgery_kit.py`: 95, 96, 98, 99, 100, 102
- `tools/build_surgeon.py`: 99
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
