## 154. Holding cells: many more, along the route, opened with E, a red beacon inside each; the starting cell one too (2026-11-03)

The user: "Make many more cells, but make more of them in strategic places along the
route through the maze. the player should be able to open said cells at any time. the
respawn beacons should be inside the cells with the proels, and they should be red to
start. The player should have to hold down the interact button to change the beacon
from red to gold. if the player takes damage while doing this, he stops doing it and
progress resets. The players starting cell should be this same kind of cell."

Supersedes note 153's release rule and placement, and note 8b / 32's anchors on the
brick kit (the tunnel-module fallback keeps its five anchors and the wooden spawn door).

### Readings chosen
- **A beacon in every cell**, not just the old five: "inside the cells with the proels"
  reads as each cell holding one, and it is what makes the route cells strategic. Open
  the gate, fight what comes out, then claim the beacon behind them.
- **The gate opens with a press of E** from either side (`holding_cell.gd`
  `_process` / `_unhandled_input`, `Interact.chooser` on the gate leaves, 3 m from the
  gate's middle). Letting a type out of containment no longer opens anything:
  `_open_holding_cells` and `all_let_out` are gone. Whatever is inside comes out loose,
  contained type or not.
- **An opened cell stays open and empty** through deaths (`stock` skips it) and in the
  save, since the player may rise inside it. The cells still shut are restocked on every
  death, as before.
- **Gold stays gold.** Every claimed beacon stays gold for good; the last one claimed or
  chosen is where the player rises (it blazes and carries the one light). A plain E on a
  gold one makes it the rising point again ("Rise here" / "Save progress", which also
  takes the map checkpoint as before).
- **The starting cell holds no proels** (the player wakes in it) but has its red beacon
  and the same gate; E opens it from inside. Its bed moved to the left wall to give the
  beacon the back (`jail_cell.gd` `beacon_at_back`).

### The beacon (respawn_anchor.gd)
- `RED` to start, `GOLD` once `claimed`. Prompt "Hold E   Claim the beacon".
- A press starts the hold (`_start_hold`); each frame it carries on only while the same
  player is near, looking at it, alive, out of a scene and holding E (`Coop.held`).
  `CLAIM_TIME` 3.0 s. Letting go, looking or walking away resets it to 0.
- **Damage**: `_on_holder_health` listens to the holder's `health_changed`; any drop
  cancels the hold and resets it. Still holding E after the hit does NOT carry on -- a
  fresh press starts again from 0. A hit fully blocked costs no health and does not
  cancel.
- While held the crystal and runes run red to gold, it spins faster and its light comes
  up in the same colour (so two lights at most: the active one and the one being held).
- The HUD shows the hold: `Interact.Prompt.progress` (0-1, or -1), drawn by `hud.gd`
  `_draw_interact_mark` as a gold arc round the crosshair, filling clockwise from the top.

### Placement (maze.gd `_place_holding_cells`)
- `holding_cell_count` 24 (was 10), plus the starting cell, which is `_holding_cells[0]`
  and `_start_cell`. Its tiles are NOT marked WALL: `_start_tile` reachability and the
  spawn-safe distances are measured from them.
- Order: (1) the free dead end nearest each of the user's five `anchor_marks` (where the
  anchors stood, fixed seed only); (2) dead ends within `holding_cell_route_reach` 6
  cells' walk of the **main route**, nearest first, `holding_cell_route_gap` 16 m apart;
  (3) the rest of the maze at `holding_cell_gap` 30 m.
- **The main route** (`_main_route`): one BFS from the starting cell; the corridor cells
  on the shortest walk to every room's centre (the containment blocks, surgery, morgue,
  chest rooms, the boss). 203 of 1,134 cells on seed 20260918. `_route_distance` walks
  out from it.
- **Few dead ends touch the route**: within 2 cells only 4 of 37 did, which is why the
  reach is 6. To find more, dead ends with a wall torch are now allowed when the torch's
  pilaster is on a SIDE wall (`s["pilaster"]` ±1); one on the back wall would stand in the
  beacon's plinth, so those stay out. In such a cell the prisoner on that side moves in
  and forward (`_spots`) and the cell's own torch goes on the other wall.
- Seed 20260918: 24 cells (5 at the marks, 14 by the route, 5 elsewhere), of 54 free dead
  ends, 20 of them by the route; 11 beside a wall torch; 17 of 24 within 6 cells of the
  route; no two under 16 m apart.
- The spawn's wooden door is no longer built on the brick kit (`module_level.place_doors`);
  the starting cell's gate hangs in the same arch.

### Saving
`save_state` version 2: `beacons` (claimed indices), `cells_open`, `anchor` (the active
one, as before). `restore_world` opens the cells first (before `_populate` stocks), then
the beacons. Saves from before: their `anchor` named other places, so it is ignored when
there is no `beacons` key; their `doors` indices are shifted down one, since the spawn's
wooden door was door 0.

### Measured
Throwaway windowed harness, seed 20260918, 34 checks, 0 failures: the start cell first and
empty; 25 cells, 25 beacons, all red and inside their cells; 2-3 different types, caged,
inside, all five types turn up; no prisoner within 0.4 m of anything solid (walls,
pilasters, plinth, layers 1|2|256|512); prisoners 0.9 m+ apart; every gate shut and solid;
the player starts in the start cell; held 1.4 s: hold 1.43, still red, the prompt carrying
0.48; a 5 damage hit stopped it and set it to 0; still holding 1 s more: still 0; let go
after 1 s: 0; held 3.3 s: gold and active; the start gate opened from inside; a maze cell's
gate opened from the corridor, its 3 prisoners loose and at the gate or out within 3 s;
only those two open; letting a type out opened nothing; save: beacons [0], cells_open
[0, 1], anchor 0, version 2; died: respawned 0.20 m from the gold beacon, the opened cell
still open and empty, the shut ones restocked, the beacon still gold.
**Re-broken**: the damage handler not cancelling -> 2 failures; the pilaster spots ignored
-> 5 prisoners touching a pilaster, 1 failure. Clean `--quit-after 1500`: 0 errors, 0
warnings, 14,065 of 14,065 tiles reachable.

Bench (RTX 3060, `--bench --size=3440x1440`, editor closed, same session):

```
                 before (note 153)          after
spawn corridor   84.8 fps  5.43M prims      89.3 fps  3.83M prims
boss centre     120.9      1.98M           111.5      2.13M
boss edge       128.2      0.64M           121.0      0.64M
outer maze       98.7      5.85M           106.6      4.28M
chest room       65.7      8.67M            67.7      7.37M
surgery          63.1      6.80M            71.6      4.71M
OVERALL 93.5 fps, p99 22.22, 1035 MB      94.6 fps, p99 16.67, 1051 MB
```

No cost that rises above the run-to-run spread (stations move both ways by up to 8 fps,
with the enemies in different places); +16 MB video memory.

### Traps
- `pass` is a GDScript keyword: a loop variable named `pass` is a parse error.
- `sed -i "${n}i..."` with `n` empty inserts the line before EVERY line of the file. It
  happened to maze.gd here; the inserted lines had no leading tab, which is what made them
  removable.
- A brick wall torch's pilaster sits on collision layers 2|256|512, not 1: a clearance
  test on layer 1 alone passed with prisoners standing in it.
- A test death waited on `_dead`, which flips late enough to read a player still where they
  died: wait on the `respawned` signal.
