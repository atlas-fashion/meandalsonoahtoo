## 123. Enemies spawn more often: a denser population, and a trickle that refills the corridors in play (2026-10-28)

The user: "Make enemies spawn more frequently." This came the same day as note
121's raise (0.25 -> 0.32). Read two ways at once:
- more enemies in each population;
- enemies turning up during play, not only when a death repopulates the world.

Travelling groups stay rare (note 120's `patrol_share`, one convoy at most).

### Density (maze.gd)
`enemies_per_corridor_cell` 0.32 -> **0.42**. Seed 20260918 at the start: 149
corridor criers (109-108 before).

### The trickle (maze.gd `_tick_spawns`, from `_process`)
- `_spawn_enemies`' per-encounter roll is factored into `_encounter` (flying
  roll, `_roll_pack_size`, the escort, note 120's progression skip, the
  hands). `_roll_encounter` wraps it and files every body spawned into
  `_corridor_enemies`.
- `_corridor_want` is set to what **actually came** at the population, not to
  `want`. `want` counts the skeleton rolls that progression skipped, and kept
  to that, the first version filled the gap with criers: 149 at the start,
  growing toward 382.
- Every `respawn_every` 8 s, with fewer of them alive than `_corridor_want`, it
  rolls one encounter at `_far_point(respawn_clear 35)`: a corridor point at
  least 35 m from every player and out of their sight. It tries up to 4 rolls
  per tick, so a roll of a type still contained does not leave the tick empty.
- Each released type is also kept at `loose_per_type` loose subjects, one per
  tick (`_hand_of` gives an enemy's type).
- `_populate` clears it all and restarts the clock. The sandbox with its
  population off gets none.

### Measured
Throwaway windowed harness, seed 20260918, `respawn_every` set to 0.5 for
speed:
- 149 at the start;
- 49 freed, then 20 new in 24 ticks;
- the nearest new one was 36 m from the player;
- every new one was a crier (no type out);
- after 38 s more: 149 of 149, never past the target.

**Re-broken** (`respawn_every` 9999): "the trickle refills" failed, 0 new.

A clean `--quit-after 1500` windowed run had no errors or warnings.

Bench (RTX 3060, `--bench`, default window, editor open and idle), at the
start of a game:

```
                        before            after
corridor enemies        109               150
overall fps             98.6              93.4
worst p99 (ms)          15.07 (chest room)  16.67 (chest room)
physics (ms)            2.8-5.7           3.1-6.2
```

The extra criers cost about 5 fps and 0.3-1.3 ms of physics.
