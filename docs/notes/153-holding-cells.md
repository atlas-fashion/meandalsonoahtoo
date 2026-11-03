## 153. Holding cells: jail cells in the maze with 2 or 3 proels of different types (2026-11-02)

The user: "Make random jail cells in the maze that contain 2 or 3 random proels of
different types. All of the current skeletons are going to turn into proels once i
give you the permanent models."

**Readings chosen.** "Proels" here means every skeleton type, so the pool is all
five of `CONTAINED`: with only the two finished proels a cell of three different
types could not exist, and the user's second sentence says the rest are proels in
waiting. A new type added to `CONTAINED` turns up in the cells with no other change.
"Contained or released" was left to me: they are contained the way a block's
prisoners are, and released the way a block's are, see below.

### Where (maze.gd `_place_holding_cells`, right after `_place_anchors`)
- `holding_cell_count` 10 cells, `holding_cell_gap` 30 m apart and from the spawn,
  picked by a shuffle on their own rng (`_active_seed ^ 0x6a61696c`), so no other
  spawn stream moved and **the layout did not change**: old saves still fit.
- From dead ends. `_plain_dead_ends` was lifted out of `_place_anchors`, unchanged.
  Dropped on top of that: an anchor's dead end, one opening on a room or a court, a
  dug exit passage (note 122), and one with a wall torch. Seed 20260918 has 35 left.
- Every tile of the cell goes WALL on the grid. `_patrol_points`, the spawners, wander
  areas and `_far_point` all read the grid, so no goal lies behind the bars. The grid's
  reachability is printed earlier, so this raises no fragmentation warning.

### The cell (scripts/holding_cell.gd, `extends jail_cell.gd`)
- The prison's gate pair (`jail_gate_l/_r`) in the dead end's arch at z 2.5. It fits the
  arch exactly, being made for the same brick-kit arch.
- The starting cell's straw and shackles, no bed or bucket.
- A blocker on layer 1 only (bars do not stop sight), off for the navmesh bake and armed
  in `maze._seal_cells`, as the prison's. So the floor inside is on the navmesh.
- Roster: `_cell_roster`, 2 or 3 distinct types, kept in `hands`.
- Prisoners: `make_skeleton(hand)`, `caged` (note 120): blind, deaf, unhurt. `stock()`
  puts them back on every population, facing the bars.

### Released when every type in the cell is out
`release_hand` -> `_open_holding_cells`: a cell opens once ALL its types are in
`released_hands`. Any one type would have let out types still contained, which breaks
"once you've released that type you can find them". The leaves swing out 1.5 rad, and
0.4 s later the prisoners are uncaged and handed to `turn_loose_subject`. No walker is
needed: they are on the navmesh and on patrol from there. Dormant ones go when a player
comes near.
- **Nothing is saved.** Open follows from `released_hands`: `stock` opens a cell whose
  types are all out, at once and empty.
- `progression = false`: `released_hands` stays empty, so cells stay shut. It reads
  that array, not `is_released`, which answers true for everything then.

### Measured
Throwaway windowed harness, seed 20260918, 0 failures:
- 10 cells; 2-3 types each, all different; all five types turn up; 23 prisoners, each
  the right type, caged, inside; cells 30 m or more apart; none on an anchor; no patrol
  point inside any cell; every tile WALL;
- every gate stops a ray on layer 1 and not on the sight layer;
- a prisoner hit for 50 and alerted: unhurt, not engaged;
- a reload (types already out at `_populate`): that cell open, empty, gate swung, blocker
  off, the others stocked;
- types released one by one: a cell opened exactly when its last type went, 10 of 10;
- all out, then a world reset: all open and empty.

Standing 7 m out as the last type went (player kept alive, no deaths): 3 of 3 uncaged,
the swordsman at z 5.5 and the drill at z 6.7 within 2 s (the gate is at 2.5), the
crossbow staying back inside to shoot, as it should. **Re-broken** (no `arm`, no grid
marking, `release_hand` not telling the cells): 46 failures. Clean `--quit-after 1500`
run: 0 errors, 0 warnings, 14,065 of 14,065 tiles reachable.

Bench (RTX 3060, `--bench --size=3440x1440`, editor open, same conditions both ways):

```
                 no cells                 cells
spawn corridor   67.4 fps  9.00M prims    67.4 fps  9.06M prims
boss centre      81.0      7.17M          81.4      7.02M
boss edge        91.5      5.23M          89.2      5.29M
outer maze       91.7      7.88M          89.1      7.86M
chest room       56.1     12.83M          54.4     12.97M
surgery          57.1     10.90M          56.3     11.07M
OVERALL 74.1 fps, p99 19.67, 1022 MB      72.9 fps, p99 22.40, 1035 MB
```

Prims are flat. Before the cap below they were 500-600k up at every station and overall
71.9. The 1.2 fps left is near the run-to-run spread (the no-cells build read 73.9 and
74.1). Physics read about 0.9 ms up in the bench, but with nobody near, 23 prisoners
all asleep, switching their physics off changed nothing (3.19 on, 3.24 off, 2.95 on).

### Traps
- **The prisoners were invisible from the corridor**, though there all along. Three
  causes, fixed in turn: the leaves' shadow cut the player's hand torch to nothing (no
  shadow on these leaves; the prison's still cast); a corridor torch is too weak for such
  dark models through bars (`TORCH_SHARE` 3.0, at `TORCH_Z` 1.25 so it falls on their
  fronts, where the starting cell's 0.6 at z 0.5 left them black against it); and the
  gate has a solid lock plate at eye height, which hid anyone on the middle line (the
  `SPOTS` keep clear of it). Look through the bars from where the player stands: from
  inside the cell it all looked fine.
- A `TorusMesh` left at its defaults is 4,096 triangles. One chain of 17 links is
  nothing in the starting cell and 1.3M across ten cells, with nothing culling them.
  `_draw_to(self, DRAWN_TO)` caps everything in a cell at 55 m, past the fog; prisoners
  too. It leaves alone what has a limit of its own (a sword, a health bar), and a freed
  prisoner goes back to none.
- A harness that stands a player among released enemies gets them killed, and the
  repopulation frees everything it was watching. It read as "0 of 2 came out". Keep the
  player alive, and print what you are counting before trusting a zero.
- A torch fades in over 0.4 s from the ranking (torch.gd). Read a light right after a
  teleport and it says energy 0, invisible; wait real seconds, not frames.
