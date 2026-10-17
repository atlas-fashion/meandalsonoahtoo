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
