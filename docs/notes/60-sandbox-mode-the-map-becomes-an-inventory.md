## 60. Sandbox mode; the map becomes an inventory page (2026-10-17)

- **Sandbox** (the user: "mainly for testing"): a title button between Play and
  Settings, or `-- --sandbox` on the command line. `scripts/sandbox.gd`
  (autoload `Sandbox`): `active`, `enemies_passive`, `player_god`; `start()`
  runs SLOTLESS (`Saves.slot` -1, as `--skip-title`), so nothing is ever
  saved; `Saves.start` and `exit_to_title` call `Sandbox.reset()`.
- **The world** (maze.gd "The sandbox" section): the real level is built as
  always (every area is a teleport target) but EMPTY -- `_populate` returns
  after clearing unless `sandbox_population` (the menu's "Level's own
  enemies", `set_sandbox_population`, which also clears the decrepit respawn
  queue) -- the whole map charted (`explore_map.reveal_all`, the sewer too,
  before the anchor snapshot so a death keeps it), and a flat test plane
  (`scripts/sandbox_world.gd`): 160 m square at x = 1500 (well off the level's
  ~320 m), grid shader (1 m lines, 10 m in rust), 3 x 3 shadowless omnis 24 m
  up, its own NavigationRegion3D baked from its floor with the maze's navmesh
  settings (one navigation map). `_place_player` puts the player there at the
  start and after every death.
- **The menu** (`scripts/sandbox_menu.gd`, the ` key = new action
  `sandbox_menu`; Esc / B closes): a CanvasLayer (47) added LAST under the
  root (it reads its keys first, as the workbench screen does), freed with the
  maze. Not a pause: `player.ui_open` + a free mouse; closes on pause /
  cutscene / death. SPAWN: a count (1-10) and a button per kind
  (`sandbox_world.KINDS`: skeleton sword / pick, archer, enforcer, crier,
  decrepit, sewer lizard, the Remnant, mimic, the Warden), spawned in a row
  7 m in front of the player, facing them, each made as the maze makes it;
  they are children of the sandbox node, NOT the maze's population, so a
  death keeps them; Clear. SWITCHES: Enemies aggro, Player takes damage,
  Level's own enemies. WEAPON LEVELS: sword / spear / armor 1..UPGRADE_MAX,
  written straight into `player.weapon_levels` / `armor_level`. TELEPORT:
  `sandbox_world.destinations()` -- test plane, start cell, each chest room by
  kind, boss stair foot, workbench, morgue, boss hall (on its `floor_y`: the
  zone centre is in the air), great shard door, sewer ladder foot, every
  anchor; `teleport()` drops onto the floor below the target, out of hiding /
  a ladder / ghosting, with a 0.35 s fade.
- **Hooks**: passive -- enemy.gd counts the player as hidden (`player_hidden`:
  they lose interest and wander; a swing already started lands), crier.gd
  `_can_see`, stalker.gd `_warded`, mimic.gd holds still. God -- player.gd
  zeroes the damage in `take_damage` AFTER the guard (enemies still see blocks
  and parries), and `drain_health`, `beam_hit`, `kill_in_scene` do nothing.
- **Sewer dwellers on the plane**: decrepit.gd and sewer_lizard.gd were blind
  and invisible whenever the player was above y -4. Now `_other_level`: only
  when the player and IT are on different sides of the sewer roof -- the same
  in the real game, and they hunt on the plane.
- **The map is an inventory PAGE** (the ` key went to the sandbox):
  inventory_screen.gd has ITEMS | MAP tabs in its header (clickable);
  "toggle_map" is now **M** (Select on a pad, as before): closed it opens the
  screen on the Map page, on Items it switches to Map, on Map it closes (the
  old map key's toggle); Tab / Esc / B close from either page. The map
  (explore_map.gd `set_full_map_open(open, embedded)`) shows EMBEDDED: the
  inventory owns `ui_open` and the keys, the map's panel sits between the
  header and the footer (its hints move into the inventory's footer), the
  mouse is captured on the Map page (the map moves under its fixed cursor) and
  free on Items. A note being typed takes every key. The map no longer reads
  any open/close key itself; `set_full_map_open(open)` alone still works
  (tools/preview_map.gd). Opened with the player off the map (the plane) it
  shows the whole dungeon centred at zoom 1 instead of an empty panel.
- Measured (throwaway harness, deleted; headless, 60 fps): 60/60 -- slotless;
  starts on the plane; level empty; map 1112/1112 and the sewer charted; `
  opens / closes the menu; every kind spawns (20 alive after 1 s), Clear; on
  the plane a skeleton hunts 15 -> 5.7 m and a decrepit 15 -> 6.6 m (navmesh,
  above ground); passive, both kept off (15.1 / 20.9 m); god: 50 hit, drain,
  beam and the scene kill all took nothing, off again 100 -> 80; sword 7 =
  x1.48, spear 99 clamped to 10, armor 3; 18 destinations, every teleport on
  the floor within 0.3 m, the sewer's map level switched; M opens on Map, M
  closes, Tab on Items, M to Map, Esc closes, ui_open released each time; a
  death rose on the plane with a spawned enforcer kept and the level still
  empty; population on (246) and off (0). Normal `--skip-title` boot
  unchanged (population, no errors). Windowed screenshots checked: plane,
  menu, both inventory pages.
