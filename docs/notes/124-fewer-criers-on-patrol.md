## 124. Fewer criers; criers patrol the corridors and see ahead (2026-10-28)

The user: "There should be less criers, and criers should be patroling the
hallways. When they see a player, they should agro."

### Fewer (maze.gd)
- `flyer_share` 0.45 -> **0.25**.
- Seed 20260918 at the start (criers are the only corridor encounters there,
  note 120): **74-75 criers**, against 149 after note 123.
- With types out, criers are a quarter of the encounters.

### On patrol (crier.gd `_patrol`, `_plan_patrol`)
- Before, a crier with nobody in view hung where it was, bobbing.
- Now, until it sees someone (or once `memory` runs out after losing them), it
  flies the corridors:
  - at `patrol_speed` 3.2 m/s, at its hover height over each path point;
  - from one corridor point to another PATROL_MIN 12 to PATROL_MAX 40 m off,
    along the navmesh (`NavigationServer3D.map_get_path` from the floor
    below it);
  - pausing 0.6-2 s at each.
- A route through a shut wooden door is refused (patrol.gd `_through_door`),
  because it cannot open one and the navmesh runs through them.
- No headway in 2 s: a fresh route.
- The points come from maze.gd `_crier_route()`: the population's corridor
  points (`_patrol_points`, the spawn candidates) in world space, built once
  per population and shared. They are handed over in `_spawn_pack` for flyers,
  so trickle spawns (note 123) patrol too. A crier spawned with no route (the
  sandbox's) hovers as before.

### Seeing (crier.gd `_can_see`)
- It looked every way at once. On patrol it now sees ahead:
  - within `vision_cone_degrees` 150 of the way its lens faces (-Z, the way
    `_turn_to` points it);
  - or any way within VISION_NEAR 3 m.
- After that, the line of sight and range are as before: the sight layer, so
  never through a shut door, and `aggro_range`, which maze.gd sets to its
  `enemy_aggro_range` 18 m.
- Once it has seen the player (inside `memory` of the last sighting) it keeps
  them in view whichever way it turns.
- Seeing them, it drops its route and rushes the face as ever.

### Measured
Throwaway windowed harness, seed 20260918, 12 criers woken, the player passive
while watching:
- 74 criers at the start, every one with a route;
- over 20 s, 11 of 12 flew 26-60 m;
  - one made 4 m: still on its route, stalled against something;
- all 12 were 1.84-2.07 m over the floor below them;
- the player was put 8 m behind a patrolling crier (a clear line): not seen in
  1.2 s;
- 8 m ahead: seen, and on the face within 1.2 s.

**Re-broken** (`vision_cone_degrees` 360): "8 m behind ... not seen" failed.

A clean `--quit-after 1500` windowed run had no errors or warnings.

Bench (RTX 3060, `--bench`, default window, editor open), at the start:

```
                    note 123 after    now
overall fps         93.4              104.8
worst p99 (ms)      16.67             13.93
```

That is the fewer criers. Patrolling costs only a path query per leg.

### Trap
A harness that walks the player up to a crier must not use that crier again:
it goes off on the face and is freed.
