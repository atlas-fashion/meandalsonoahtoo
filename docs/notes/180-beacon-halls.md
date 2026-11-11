## 180. Beacon halls: the photo's root-choked hall, shut in until you wind the wheel (2026-11-11)

**Renamed in note 181**: the halls are the user's Scoutposts, `hall_room.gd` is
`scoutpost.gd`, `module_hall_rooms` is `module_scoutpost_rooms`; the box-built gallery
and its ladder were replaced by the Blender balcony and stair.

The user, with a photo of a great hall (massive roots down the left wall, timber
galleries, stone arches and pillars, barred arched doorways, caged lanterns on
chains, red banners, chains with big hooks, crates, barrels, a cart, a fire
basket, floor grates): "There should be many rooms like this, one identical to
the photo, and the rest similar, throughout the dungeon. The player should be
locked into these rooms until the player can hold down e to interact with a
wheel that lifts the dungeon doors. The beacons should be in here, and the cells
in the dungeon should be less frequent."

**Supersedes note 179's reading.** Note 179 took "rooms like this" to be the
cell photo of note 177 and built dead-end beacon rooms (`wheel_room.gd`). The
photo the user meant is this hall. `maze.gd` `beacon_room_count` is now 0 (the
code stays: `wheel_room.gd` `make_winch` builds the halls' winch); the beacons
moved to the halls; the holding cells stay 8 (note 179) and hold no beacon.

### The layout (module_level `_make_beacon_halls`, maze.gd `module_hall_rooms` 6)
- `module_hall_rooms` more rooms are asked of the carve (`chest_rooms` +6) and the
  LAST six carved become kind "hall", before the morgue and the surgery pick
  theirs, so those two and the five containment blocks are the same rooms
  (`_choose_rooms` places rooms in turn: extra ones come last). `hall_keep`
  stops a small map from eating a containment block. The corridors round the new
  rooms change: **every seed's layout changed** (as with note 120's room count).
  The carve now relaxes the room gap to 5 cells on the default seed (warning
  "rooms only fit 5 cells apart").
- Each hall is `_enclose_hall`'d like the morgue: a 5x5 block of vaulted cells,
  30 m square, the vaults running into each other, its ways in keeping their
  arches. place_doors hangs no door there (room cells), place_torches skips it,
  the ruins' districts leave it out (`_corridor`), nothing spawns in it from the
  corridors (`is_in_hall`, `_touches_room`).

### The hall (`scripts/hall_room.gd`, built by maze.gd `_place_halls` after the ruins)
Frame: the middle of the block, +Z towards its first way in. The first hall (the
one nearest the start) is `identical`: seen from that way in, the root wall and a
gallery on the left, a gallery along the back, the winch on the right, the fire
basket front right, the cart behind it, crates and barrels front left, grates
down the nave. The rest deal the same pieces out again (`_shuffle`).
- **Piers**: the morgue's pilasters along the walls; inside, the 2.2 m block
  that fills four vaults' meeting only from `SHAFT_TOP` 2.95 m up, standing on
  the corridors' junction pillar (0.9 m). The first shots with the morgue's full
  2.2 m piers were a forest of stone 1.9 m apart; slim, the floor reads as one
  hall. Under the boss hall's floor (`under_boss_hall`) a pier stays whole: the
  raised block would reach through it.
- **Light**: a torch on the two pilasters by each wall's middle (8), four caged
  lanterns (cell kit, `HoldingCell.make_lantern`, now static) on chains over the
  cells round the middle at `LANTERN_SHARE` 3.0 of a torch, the fire basket's
  coals and a 5.5 m light, candles. Lanterns and torches are torches: the
  nearest-N ranking (`Graphics.torch_lights`) bounds them.
- **Timber galleries** (`_gallery`) on 1-2 fully closed walls (2 wanted on the
  photo's): seven posts with knee braces, front beam, ledger, joists, six planks
  at `DECK_Y` 2.15, `DECK_DEPTH` 1.75 out, a railing with balusters, a ladder,
  crates and barrels up on the deck, rags (plain, `ruin_banner.gdshader`'s new
  `plain` instance uniform) and red banners over the rail. Short by 3 m at a
  corner whose other wall has a way in. All the wood is ONE mesh (`_timber`,
  `_strut` into a SurfaceTool, the morgue's dark wood), casting under
  `Graphics.ruin_shadows` (it joins the ruins' `_casters`). A plank table, stool,
  unlit lantern and lit candles under the photo hall's left gallery (`_table`).
- **Roots** through ruin_dressing.gd (`hall_begin` / `hall_end`): one wall heavy
  (14-20 strands a cell, a living tip in most cells, hanging roots), the rest at
  0.55 odds with 4-9, roots over the archways, and `floor_strand` roots crawling
  3.5-6 m out across the flags from the heavy wall's foot, half sunk.
- **Props** through ruin_dressing.gd: banners, candles, shackles and the seated
  dead, crates (breakable), barrels, rubble; on the floor the fire basket
  (`brazier`), a pile of crates and barrels, the handcart at 1.3, hooks and
  chains from the vault (`_hooks`, `_chain`); two big grates (the cell kit's
  drain scaled to 1.4 m); fallen blocks at a few pilasters, never in a way in
  or before the winch. ruin_dressing `_wall_span` is 1.7 in a hall (clear of the
  pilasters).

### The lock
- The cell kit's barred gate in every way in, `GATE_Z` 2.5 out of its ring cell,
  hung raised `LIFT` 2.3 (as note 179's), blocker off (built before the navmesh).
- A living player more than `TRIGGER_IN` 1 m in from the walls: after 0.35 s
  every gate crashes down in 0.32 s, solid, dust off each (effects), a shake for
  those inside.
- The winch (`WheelRoom.make_winch`: the photo's bronze gear door) on the middle
  of a wall with no way in; "Hold E   Turn the wheel" within 2.4 m looking at
  it. Held, every gate rises together over `CRANK_TIME` 3.6 s; let go and they
  sink back 1.6 times as fast; a hit breaks the grip.
- Wound up they stay up until everyone has left; then armed again. With nobody
  alive inside a shut hall winds itself open after `EMPTY_OPEN` 1.5 s (a death
  elsewhere must not leave a hall shut for good). Rising at its beacon shuts you
  in again. Not saved.
- The beacon (maze.gd `_add_beacon`, `beacon_spot` the middle). Beacon indices
  in saves moved with the layout anyway.
- **Guards**: `_spawn_hall_guards` rolls one corridor encounter (criers and
  scouts until types are let out) in each hall nobody is in, beside the beacon.

### Measured
Throwaway windowed harness in the real level (default seed, real input events,
`--no-enemies`), 0 failures: 6 halls each with a beacon; gates raised at the
start; not shut from beyond the gate; shut 1.2 s after stepping in, every gate
down and solid; walking at a dropped gate stops at z 14.02 (gate 14.5); the
prompt at the wheel; holding 1.2 s winds to 0.33, letting go sinks to 0, holding
on opens it and it stays open with the player inside; shut again on coming back;
left with nobody inside, open again.

`--bench` (1280x720 window, High): beacon hall 70.5 fps avg, 1% low 61.6, p99
16.23 ms, gpu 9.17 ms, 964 draws -- against the chest room's 46.0 / gpu 10.63 and
the surgery's 50.1 / 12.10 on the same run. Not an A/B (the layout itself
changed, so there is no "before" level to compare); GPU drifts with the PC's
background load (memory).

### Traps
- The harness first stood the player at "the first gate", which was a gate on
  a side wall, so "inside" was in the corridor beyond it: three false failures.
  Gates are in wall order, not way-in order.
- Placing the camera on a floor spot that holds a prop (the fire basket) throws
  the player out of it: pick view spots clear of the props.
- The headless run's "skin registered with a valid skeleton" errors are the
  seated dead under the dummy renderer, not the halls (none windowed).
