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

