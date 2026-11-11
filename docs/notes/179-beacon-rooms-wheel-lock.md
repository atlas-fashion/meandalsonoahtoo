## 179. Beacon rooms: shut in until you wind the wheel; the beacons there, fewer holding cells (2026-11-11)

**Superseded by note 180**: the photo meant was a great hall; the beacons and the
wheel lock moved to the beacon halls (`hall_room.gd`) and `beacon_room_count` is 0.

The user: "There should be many rooms like this, one identical to the photo, and
the rest similar, throughout the dungeon. The player should be locked into these
rooms until the player can hold down e to interact with a wheel that lifts the
dungeon doors. The beacons should be in here, and the cells in the dungeon should
be less frequent." The photo is note 177's (the cell with the caged lantern, the
bench under its chains, the shelf, and at the far end a riveted bronze door with
a big gear wheel between brass piston columns).

Supersedes note 154 on where the beacons stand and how many holding cells there
are.

### Readings chosen
- **"Rooms like this" are dead ends dressed as the photo**, placed where the
  holding cells were chosen (maze.gd `_place_holding_cells`: the user's beacon
  marks, then the main route, then the rest). The rooms take the first
  `beacon_room_count` 10 places, the holding cells the next
  `holding_cell_count` 8 (was 24).
- **The photo's gear door is the wheel**: the room's back wall carries it
  (`wheel_room.gd` `_build_wheel`: a riveted bronze door 1.75 x 2.6 m, two
  brass piston columns, a 1.24 m gear wheel with 20 teeth, three spokes, a hub
  and a handle), and turning it lifts the room's gate.
- **"The dungeon doors"** are the cell gate (the kit's rusted bars), hung
  raised in the room's arch -- its foot 2.3 m up (`LIFT`), its top just under
  the boss hall's floor -- and dropped like a portcullis.
- **"One identical to the photo"**: the first room (the one at the first beacon
  mark) keeps the photo's layout exactly -- bench and chains on the left, shelf
  on the right, the lantern over the middle. The others are mirrored at random
  and half of them hold a dead prisoner's remains.
- **The beacons**: one in every room, none in the holding cells; the starting
  cell keeps its own (it is where the game starts and the first place to rise).
  A room's beacon stands in the middle, 0.75 m towards the gate (`BEACON_SPOT`,
  `beacon_spot()`, read by maze.gd `_add_beacon`), so the winch has the back wall.

### The lock (`scripts/wheel_room.gd`, extends holding_cell.gd)
- Raised until a player is more than `TRIGGER_IN` 1.0 m inside the gate's line;
  `DROP_DELAY` 0.35 s later it crashes down in `DROP_TIME` 0.32 s (eased in),
  the blocker (layer 1: players and enemies) goes solid, a shake for everyone
  within 9 m and a puff of dust off the floor (effects on).
- Locked: "Hold E   Turn the wheel" in front of the wheel (2.4 m, looking at
  it). Held, the gate rises over `CRANK_TIME` 3.2 s and the wheel turns three
  times; let go and it sinks back at `SINK` 1.6 times that rate; a hit breaks
  the grip (any drop in health, as the beacon's hold). The HUD's arc shows how
  far up it is.
- Wound all the way, it stays up while anyone is still inside; once everyone
  has left it is armed again, so going back in shuts you in again. Rising at
  the room's beacon after a death shuts you in too.
- No prisoners (`stock` empty), no swinging (`swing_open` does nothing), not
  saved: a level built afresh has its gates raised.

### Measured
Throwaway windowed harness in the real level (seed 20260918, real input events):
10 rooms, 8 holding cells, 11 beacons (the rooms and the start); the gate hangs
raised before anyone goes in; walking in drops it (locked, lift 0); walking at
the dropped gate stops at z 2.02 (the gate is at 2.5); holding E 1.2 s winds it
to 0.38; letting go 0.8 s sinks it to 0; holding 4 s opens it, and it stays open
with the player still inside. 0 failures.

### Traps
- The first harness teleported the player onto the spot where the beacon now
  stands, and the plinth's collision threw them out of the room (z 5.05): the
  test, not the lock.
