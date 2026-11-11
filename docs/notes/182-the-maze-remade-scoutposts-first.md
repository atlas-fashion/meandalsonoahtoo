## 182. The maze remade: wake gold, a scoutpost first, then a prison; the halls fill as the prisons open (2026-11-11)

The user: "Remake the maze. There are many flaws." Flaws:
- the cell bars invisible and uninteractable;
- the new props look bad and don't match the art style ("Wait until i give you
  tripo api credits");
- the smoke from breaking boxes too strong;
- the pots should break too, and dashing should break boxes and pots;
- "I never found any scoutposts".

The vision:
- spawn with the cell's beacon already gold, escape the cell, explore;
- a couple of criers and scouts before the first room;
- the first room a scoutpost, which must be cleared before the wheel opens the
  gate;
- then the first prison room, the first enforcer encounter;
- release the proels, and find them and little groups of enemies led by an
  enforcer, the halls busier with every prison opened;
- scoutposts more common than prisons, with helpful loot strewn around and a
  stylized chest that fits the art style.

Asked:
- **Which props to take out:** the corridor dressing only. The roots, the cell
  furniture and the scoutpost balcony stay.
- **"Pots":** the barrels.

Supersedes note 180's and 181's way of choosing the scoutposts (the last rooms
carved, the photo's hall the nearest in a straight line) and note 176's
corridor props.

### The rooms in the order they are found (module_level `_assign_room_roles`, `room_walks`)

- The morgue (furthest) and the surgery (nearest the boss) pick theirs first.
- Every other chest room is ranked by the walk from the spawn (`room_walks`, a
  bucket queue over the cells). Rooms stand on the corridors' own junctions, so
  the walk often has to go through one; stepping out of a room costs
  `ROOM_PASS` 60 cells more, so a room behind another ranks after it.
  - The first try never went through a room, and reached only 2 of 13.
- **Rank 0** is a scoutpost.
- **Rank 1** is a prison (a containment block, kind "chest").
- **The other `prisons` - 1 prisons** are spread evenly through the rest; the
  rest are scoutposts.
- Each room keeps its "walk_rank". maze.gd hands the contained types out by it
  (`_build_puzzle_rooms`), so the first prison met holds the proel swordsmen;
  `_place_scoutposts` orders by it, so `_scoutposts[0]` is the first room and
  the photo's own hall.
- `module_scoutpost_rooms` is 8 (was 6), `prisons` is 5 (one per contained
  type): 15 rooms with the morgue and the surgery. The carve now fits them 4
  cells apart (5 before), warning as before.
- Every seed's layout changed.

On the default seed, rooms by walk (cells):

```
scoutpost 32, prison 39, scoutpost 111, 196, prison 202, scoutpost 208, 227,
prison 228, scoutpost 239, 246, prison 261, scoutpost 279, prison 282
```

### Waking gold (maze.gd `_claim_start_beacon`)

A new game (no save, or a save from before the beacons) claims the starting
cell's beacon and makes it the active one, so the player rises there until
they claim another.

### The scoutposts (scoutpost.gd)

- **Its scouts are its guards.**
  - maze.gd `_spawn_scoutpost_scouts` hands each scout to its post
    (`add_guard`, `reset_guards` on every population). A cleared post gets none.
  - While any scout lives, the wheel's prompt reads "Kill the scouts first" and
    E does nothing.
  - With all of them dead the post is `cleared`, and the prompt reads "Hold E
    Turn the wheel" as before.
- **Cleared, it never shuts again** (`_armed` stays false).
- **The chest** (`_place_chest`, scripts/loot_chest.gd):
  - The stylized Tripo chest already in the project
    (`models/tripo_test_chest.glb`: banded wood under an iron-bound dome),
    1.15 m long, on chest.gd.
  - Its mesh is cut by triangle at 60% of its height into a body and a lid. The
    lid hinges at the back, so chest.gd's lid swing opens it.
  - Both faces are drawn (the Tripo model is one surface, and an open lid was
    seen from behind as hollow), with a floor of dark boards inside.
  - It goes against the wall across from the winch if it can, on the middle
    cell; never a way in, a corner or by the stair. Its spot is reserved before
    the dressing.
  - It holds 2 health potions and 15-30 coins. chest.gd now gives coins without
    a shard, with the same banner.
- **Saved:** `scoutposts_cleared` and `scoutpost_chests` (chest.gd `open_now`),
  beside note 181's `scoutpost_loot`.

### The population (maze.gd)

- **How full** (`population_share`): the corridors carry `early_population` 0.2
  of their full number (`enemies_per_corridor_cell` of every corridor cell) with
  no type let out, rising evenly to all of it with all five out.
  - On the default seed: 70 at the start, 126 wanted after the first prison.
- **Nothing out**: an encounter is a scout (`early_scout_share` 0.3) or a crier;
  nothing else (44 criers, 26 scouts).
  - Before, the skeleton rolls were counted and spawned nothing, and the
    trickle kept the start's number however many types were out.
- **Types out**: the old mix. A skeleton encounter is two to four, led by an
  enforcer at `pack_enforcer_share` 0.8 (0.45).
- **A prison opened** (`release_hand` → `_fill_halls`): the number goes up at
  once, and half the gap is spawned straight away out of sight. The trickle now
  rolls up to 4 encounters a tick when far short, which tops up the rest.
- **The first walk** (`_spawn_first_route`): while the first scoutpost is held
  and nothing is out, a crier, a scout, a crier and a scout are spread along the
  shortest walk from the cell to it (30-88% of the way). They keep to their
  stretch; they are not on patrol.
- **Enforcers**: no enforcer is in the corridors before the first prison. The
  prisons' own enforcers are the first met; collectors and the convoys come
  after a release, as before.

### The corridor props out (ruin_dressing.gd `props`, maze.gd `ruin_props` false)

- The districts are still cut, but dress only:
  - **Roots**: the overgrowth's all of its own, without its rubble; elsewhere a
    wall of roots now and then.
  - **Breakables**: a crate or two (6% of cells) or one to three barrels (5%).
- On the default seed: 3,667 root strands, 54 living tips, 36 crates, 61
  barrels, beetles, and no prop lights.
- The scoutposts still dress from ruin_dressing's functions (banners, candles,
  the fire basket, the cart); the user kept those.
- `ruin_props = true` brings note 176's districts back.

### Barrels (breakable_crate.gd `make_barrel`, `_barrel_layout`)

- **Built** from the crates' planks: sixteen staves bellied out (two boards
  each), two iron hoops (vertex colour on the plank material), a head of four
  boards let in under the rim. Two sizes (0.66 x 0.92, 0.56 x 0.78 m), a
  cylinder collider.
- **Broken** like a crate: a blow or a dash. The staves fly two to a piece, the
  hoops and the head whole.
- **In the scoutposts** they replace the Higgsfield "barrels" cluster, under the
  balconies and by the pile (`ruin_dressing.barrel_group`, `_barrels`).

### Lighter dust (breakable_crate.gd `_dust`)

The user said the dust was too strong. The puff is now about a third as heavy
(old values in brackets):
- 6 billboards (16);
- alpha 0.3 (0.7), 0.8 m (1.2), growing to 1.3x (1.7);
- 1.4 s (2.2), spreading at 0.4-1.3 m/s (0.8-2.4).

### The cell bars

Not reproduced, on the user's own saved settings (Ultra, view distance 1.25):
- Rendered from inside the starting cell, from outside two holding cells and
  inside a prison, every gate's leaves have their meshes and draw.
- E at the starting cell's gate shows the prompt and opens it.
- Every maze holding cell's prompt shows near its gate.

The kit (models/cell_kit.glb and its maps) is tracked with its `.import`
files. A checkout that runs the game before the editor has imported it would
build the gates with no mesh. Left as is, and reported to the user.

### Measured (throwaway harness, real level, default seed, headless; 0 failures)

- **Waking:** the start beacon is gold and the active one.
- **Room order:** the first room is a scoutpost and the second a prison with
  the proel swordsmen; scoutposts 8 against prisons 5.
- **At the start:** only criers and scouts in the corridors.
- **The first scoutpost:**
  - 3 scouts; walking in drops the gates;
  - at the wheel the prompt says "Kill the scouts first", and 1.5 s held left
    the lift at 0.00;
  - the scouts killed, it is cleared and the prompt says "Hold E   Turn the
    wheel"; 4.5 s held wound it to 1.00;
  - left and walked into again, it stays open.
- **The chest:** opens with E, coins 0 → 21.
- **Breakables:** 88 barrels in the maze. A blow breaks a barrel; a dash from
  3 m breaks a crate and a barrel.
- **The first release:** want 70 → 126, 98 about at once; 6 enforcer-led groups.
- **Saving:** the save holds the cleared post and the opened chest.

Seen (windowed): the photo's hall with its chest; the chest closed and open;
barrels and a crate; a barrel bursting with the faint dust; a corridor with
only roots.

A clean `--quit-after 2400` run: no errors.

### Traps

- **A walk that never passes a room** reached 2 of 13 rooms on this layout:
  rooms sit on the corridors' junctions.
- **Torches are ranked by the player's position**: screenshots taken far from
  the player are black. Move the (disabled) player with the camera.
- **The scoutposts' "seated dead" log "skin registered" errors headless**, as
  before (note 180).
