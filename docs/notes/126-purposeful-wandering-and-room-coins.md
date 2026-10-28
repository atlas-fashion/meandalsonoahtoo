## 126. Enemies keep to their area and stop to do something; coins lying in the containment rooms, with golden flames (2026-10-28)

The user:
- "Enemies should not be able to open doors. They should wander around in
  their respective areas, as if they have a brain and are doing something."
- "You should be able to find coins lying around in containment rooms. Coins
  should have a small golden animated trail shooting up from them, kinda like
  fire, so the player can see them."

### Doors
Nothing opens a wooden door but the player. That was already so; note 125's
patrols refuse routes through shut ones, or walk up to the door and turn back.

### Their own area (patrol.gd, crier.gd)
- A patrol's `home` is where its first member stood at `setup`. A crier's
  `_patrol_home` is where it first patrolled.
- A goal is refused if it is more than HOME_RADIUS 45 m from home. A patrol
  that has been carried further off (a chase) may only take goals nearer home.

### Stops (patrol.gd `_begin_stop`, `_do_stop`)
At the end of each leg the leader stops for STOP_MIN 2 to STOP_MAX 6 s, doing
one of these, rolled each time:
- **LOOK** about: body and head swinging +-0.9 rad, slowly.
- **STUDY** the nearest wall: 8 rays at chest height, mask 2, 3 m; it turns
  square to the closest hit and stands. With no wall in reach, it looks about
  instead.
- **LISTEN**: it turns to face back down its own trail and stands.

The column catches up and stands behind. Criers hang 1.5-4.5 s at a stop
(0.6-2 before) and look about. Their vision cone (note 124) sweeps with them.

### Coins (dungeon_room.gd `_place_coins`; item_drop.gd)
- Each containment block lays COIN_PILES 5 stacks of COIN_MIN 3 to COIN_MAX 9
  coins on its court, at build:
  - 2.6 m to `_span` - 1.6 m from the middle (clear of the generator);
  - at least 2.5 m apart.
- They are item_drop.gd drops of `coins` with the meta "lying": no pop, they
  just settle. They are children of the room, so a death does not put them
  back.
- One picked up (freed while queued, `_on_coins_gone`) is saved in the room's
  "coins_taken" and freed again on load.
- **The flame** (item_drop.gd `_coin_flame`, on every coins drop, so an
  enemy's dropped coins have it too):
  - a CPUParticles3D of FLAME_COUNT 18, in world space, so it streams behind
    a pile flying to the player;
  - born in a 3.5 cm sphere on the stack, rising at 0.45-0.75 m/s with a little
    lift and a wandering sideways sway, living 0.75 s;
  - drawn as soft round billboards (0.07 x 0.11 m, additive, unshaded, no fog),
    growing then shrinking, and going from white-gold through gold and orange
    to nothing;
  - drawn within FLAME_SEEN 32 m;
  - with `Graphics.effects` off: 9 particles, 0.5 s.
- **Far drops rest.** More than FAR 34 m from every player, a resting drop
  turns its flame off and skips its glint and its look for a taker. This is
  checked twice a second.

### Measured
Throwaway windowed harness, seed 20260918.

Coins:
- 25 piles in 5 blocks, all resting on the floor (a ray down meets the floor
  within 0.15 m), each with its flame emitting;
- one taken: 0 -> 3 coins, listed as taken and saved as taken;
- screenshots: small gold wisps rising off each pile, visible across the court.

Patrols, with every type out and 60 patrol leaders woken for 60 s:
- none strayed more than 57 m from home (furthest 39 m);
- 53 of 60 stopped at least once;
- all three kinds of stop were seen, and 28 of the lookers turned their heads;
- they stood about 10% of the time.

**The first bench found the coins' cost.** Without the far-rest, the 25
lying drops all ran every frame: 96.6 / 95.5 fps against 101.7 for the
commit before. With it:

```
                    before (125)      after
overall fps         101.7             100.5
worst p99 (ms)      14.58             16.93 (the chest room station)
chest room gpu ms   8.08              8.56
```

The chest room station is in a containment block, with its five flames in
view. They cost about 0.5 ms of GPU there.

A clean `--quit-after 1500` windowed run had no errors or warnings.
