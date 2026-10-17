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

