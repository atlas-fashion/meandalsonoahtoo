## 122. Containment exits that really lead into the maze; the prisoners walk out themselves; three collectors (2026-10-28)

The user: "There should be more than one collector warden. Also the containment
chamber exits should actually lead to the maze to increase realism. The
skeletons that are released should actually be released into the maze, but
more should be able to spawn randomly in addition."

Supersedes note 120's back door: there every cell had a door on a blind wall,
a black panel behind it, and a prisoner reaching it was slid into the wall and
freed while the maze spawned the same number elsewhere.

### The exits (module_level.gd `_make_back_exits`, option "back_exits")
- On when maze.gd has `progression` and `puzzle_rooms`. It runs after the
  morgue's and the surgery's picks and before any geometry, so the brick level,
  collision, the tile grid and the navmesh are all built for the passages.
- For every chest room still kind "chest", it looks at the ring cells along
  the sides. Corners are skipped, and so are the ways in and the cells beside
  them (the bays a corner way in passes through, dungeon_room `_open_ring`).
  It opens up to BACK_EXITS_WANTED 5 of them at the back:
  - first, wherever a corridor already runs right behind the wall;
  - then, through a passage dug in the rock to the nearest corridor
    (`_dig_path`: a breadth-first walk through cells not yet in the maze, at
    most BACK_EXIT_DIG 8 cells, inside the map's rim). The shortest passages go
    first, and each one is re-measured before digging, in case an earlier dig
    is in the way.
- A passage joins only a cell that `_joinable` accepts: no room, no court, no
  gate, not the player's starting cell, and not already open on that side.
  Dead ends may be joined.
- Every cell touched is classified again (`ModuleMaze._classify`).
- Recorded per room as "back_exits": [{cell, side, dug, join}], where join is
  the maze cell reached. They are NOT among its "entrances", so no wooden door
  goes on them, and the prison keeps those bays as cells.
- The dug cells and the join cells go into the out's meta "exit_passage".
  `place_doors` hangs no wooden door on an edge touching them: the first test
  had a prisoner stuck for good behind a shut one, because the navmesh runs
  through shut wooden doors.
- Seed 20260918 has 23 exits in all: 12 straight onto a corridor and 13 cells
  of dug passage. Per block: sword 5, crossbow 3, hammer 5, shield 5, drill 5.
  Before digging was added, the counts were 1, 6, 1, 0 and 4.
- The layout changed again. There are 1,134 cells (1,121 before). The spawn
  moved to (-29.25, 78): `_pick_spawn` weighs the walk to the rooms, and the
  passages shortened it. Which block holds which type moved with the walks:
  sword (7, 28), crossbow (32, 49), shield (27, 4), hammer (39, 13), drill
  (13, 13). Every one of the 14,065 open tiles is reachable from the spawn.

### The door in the passage (dungeon_room.gd)
- The prisoners go only in exit cells, at most PRISONERS 5. The bays carry
  "exit" (from `_prison_bays`), and the cells carry "exit" and "fake_exit".
  A block with no exits at all falls back to note 120's dark panel on every
  cell.
- An exit cell's door is note 120's rails, lintel, slab, gear and lamp, at
  -BAY_DEEP + BACK_FACE, with no black panel: the passage is real.
  - The gear and the lamp moved out to the bulkhead's face (z + 0.18 / 0.2).
  - The shut slab is solid (`back_body`, layers 1|2, 1.5 x 2.5 x 0.3 m). It is
    off while the navmesh bakes, armed in `_arm_doors` on level_built, and
    off again in `_lift_back_door`.
- **The bulkhead** (`_fit_bulkheads`, on level_built, once the collision is
  in the physics space).
  - The passage there is 3.1 m wide and the door 1.2 m, so stone showed either
    side of the door. Rays cast from the door's middle find the walls
    (1.55 m each side on this seed) and the roof.
  - The roof ray hits nothing, because the vault has no collision. It is capped
    at `built.height` + 0.2.
  - Plates go each side out to the walls, plus one over the door. They run
    0.15 m into the stone, in dark iron with two rusty ribs, and are solid to
    everyone and to sight.
- **The walk out** (`_walk_out`, `_walk_path`).
  - Each prisoner, still caged, follows a navmesh path from its cell to its
    join cell at WALK_OUT 1.6 m/s (was 1.3).
  - At the end it is uncaged and handed to maze.gd `turn_loose_subject`. That
    gives it normal aggro and a wander patch where it came out, and puts it in
    "loose_subjects".
  - Some passages make no headway: no progress in 3 s past the first
    waypoint, or 30 s gone in all. Then the prisoner is let go where it
    stands. `_vanish` remains only for the fallback panel.

### The spawn pool and the collectors (maze.gd)
- `release_hand(hand, count)`: the count only goes in the log now. Another
  `loose_per_type` (3) of the type turn up elsewhere at once, out of sight;
  these are the "more spawn randomly". Every later population adds packs and
  loose ones as in note 120.
- `collector_count` 1 -> 3.

### Measured
Throwaway windowed harness, seed 20260918, 0 failures:
- every block has 3-5 exits;
- every prisoner is in an exit cell;
- each exit has a door and a bulkhead, and no other cell has either;
- every shut door is solid, and the navmesh runs from each exit cell out to its
  join (23 of 23);
- shut, 15 of 15 rays cast down the passages (at the middle and 1 m to each
  side) stop.

After the sword block's crystal:
- 5 of 5 prisoners walked out and were loose in 11.1 s, each 0.32-0.63 m from
  its join cell when let go;
- exactly 3 more sword hands turned up elsewhere;
- the 5 lifted doors stop nothing;
- 3 collectors were out, and 3 again after a reset;
- the opened doors stay open after a reset.

The first run of the harness had 2 of 5 come out wrong. One was stuck behind a
wooden door in a dug passage. The other was a harness fault: it measured where
the prisoners were once all were out, by which time the early ones had
wandered. The fix was to measure each one as it is let go.

**Re-broken:** without `_fit_bulkheads`, "a bulkhead round each" failed in all
5 blocks and "closed across its width" failed (5 of 15 rays).

Screenshots show:
- from the corridor: the passage ends in a dark iron bulkhead with the slab in
  it;
- open, a sword skeleton walking out of the cell towards the camera.

A clean `--quit-after 1500` windowed run had no errors or warnings. Not
benched: this adds no lights, and the collectors only appear once a type is
out.

### Traps
- A ray up a brick corridor finds no roof: the vaults have no collision. Cap
  anything sized by an upward cast.
- Shut wooden doors stand in the navmesh (note 24's trap). Anything walked
  along a navmesh path must not have one on its route.
- `_pick_spawn` depends on how far the rooms are to walk, so any new opening
  near a room can move the start.
