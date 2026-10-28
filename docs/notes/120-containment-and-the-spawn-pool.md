## 120. Containment blocks, a spawn pool that grows, the collector; the surgery last before the boss (2026-10-28)

The user: "The maze should start out with only crier encounters. The rooms
should be mandatory, and there should be a prison or 'containment' room for all
skeleton types. The enemy groups traveling should be rare. As you encounter
containment rooms and clear the wardens, you release the prisoners through a
back mechanical door of each cell rather than the front gate. Once you've
released that enemy type into the maze, you can find them spawned around. You
should also be able to find a more rare warden in the maze, attempting to
collect and transport the loose test subjects. All containment rooms should
look the same for now, just like the prison block." Then: "the claw room should
be the last room you encounter before the boss."

**Readings chosen.** "Wardens" are the enforcers posted in each block (the old
name, note 22). "Mandatory": every containment block holds one of the great
door's five shards, so all five must be opened to reach the boss. The skeleton
types are note 93's five: sword (blade), crossbow, hammer, shield, drill.
"Travelling groups" are the convoys and the packs on patrol.

### Rooms (maze.gd `_build_puzzle_rooms`)
- `module_chest_rooms` 5 -> **6**: the surgery takes one, the other five are
  containment blocks. **The room count feeds the generator, so every seed's
  layout changed** (seed 20260918: spawn (126, -6.75), morgue (9, 42), surgery
  (40, 37), 1,121 cells) -- and an old save rebuilds a different maze from its
  seed. Saves from before this are not compatible.
- `progression` (maze.gd, default on): the rooms are sorted by walk from the
  start (`_room_walks`) and the nearest five get `CONTAINED` in order --
  blade, crossbow, hammer, shield, drill -- each its shard
  (`Inventory.SHARDS[CONTAINED.find(hand)]`). Rooms beyond five (none on the
  default map) take the old roles with no shard (mimic via
  `_far_room_from_start(among, walks)`, mine, vacant); the shard door counts
  only rooms with a shard. **The mine and the mimic are therefore not built on
  the default map** (`mine_rooms` / `spawn_mimic` still apply to spare rooms;
  `progression = false` brings the old 2 prisons + mine + mimic back).
- Seed 20260918: sword (39, 13) 215 m walk, crossbow (27, 4) 329 m, hammer
  (7, 28) 425 m, shield (13, 13) 491 m, drill (32, 49) 509 m.

### The containment block (dungeon_room.gd, `hand`, `is_containment()`)
- The domed prison exactly (note 29/45), title "CONTAINMENT: <TYPE> HANDS".
  Five of the ~10 cells hold a prisoner; the prisoner is a **real skeleton of
  the type** (`maze.make_skeleton(hand)`; crossbow = archer.gd) put in on every
  world reset (`_cage_prisoner`, from `_respawn_prison`) with **enemy.gd
  `caged`**: after locomotion/animation and before any AI it zeroes `engaged`,
  moves only at `cage_walk`, and `alert` / `take_damage` / `apply_knockback`
  return at once -- blind, deaf, unhurt (a crier's call or a spear through the
  bars does nothing). Dormancy still applies (far blocks sleep).
- **The back door** (`_build_back_door`, every cell): a black unshaded panel
  (`_mat(&"void")`), two rust rails 4.75 m tall, a lintel, a riveted iron slab
  with three bands in front, a gear wheel left, a lamp right (one material per
  room, `_back_lamp_mat`, red -> GREEN). Built at `-BAY_DEEP + BACK_FACE`
  (0.16): at `-BAY_DEEP + 0.03` the black panel sat behind the brick's real
  face and the open door showed brick (screenshot). The chains moved out to
  x +-1.45. The level hangs torches on cells' back walls, one right over the
  door: `_torches_off_back_doors` slides any within 1.5 m of a door's middle
  along the wall to x +-2.0 and re-caches torch.gd `_fixed_position`.
- Enforcers down -> E on the crystal (`_cut_power`, unchanged: red crystal +
  the shard). For containment it calls **`maze.release_hand(hand, n)` at once**
  (n = caged prisoners; a death before the doors are up still lets the type
  out), and 1 s later `_open_back_doors`: the front gates **stay shut**
  (`_arm_doors` keeps them armed; `_power_off_now` leaves them), each slab
  jolts 6 cm then slides `BACK_LIFT` 2.25 m up over 1.6 s with its gear
  turning (about its own axle: `rest * Basis(UP, a)` -- setting `rotation.y`
  threw away the gear's tilt), 0.15 s apart, and each prisoner, still caged,
  is walked (`_run_walkers`, `WALK_OUT` 1.3 m/s) to 0.6 m off its door, then
  `_vanish`: physics off, collision off, slid 1.8 m on into the dark over 1.1 s
  and freed. Announce "THE BACK DOORS GRIND OPEN / The <type> hands are loose
  in the maze." A loaded save: doors up, lamps green, cells empty.
- `drop_point(from)`: the corridor cell outside the block's nearest way in.

### The spawn pool (maze.gd, end of file)
- `released_hands` (saved as "released", restored in `restore_world` before
  `_populate`). `_spawn_enemies`: a skeleton roll comes with chance
  `released / 5`; one that does not come is **counted as placed** so the criers
  keep their density -- at the start they are the only corridor encounters
  (seed 20260918: 48-49 criers, 0 skeletons, 0 convoys). A pack that comes is
  `_pack_hands(count)`: crossbows at the back (`archer_share`) if out, a shield
  at the head (`shield_share`) if out and it has someone to guard, the rest
  sword/hammer/drill among those out (`_melee_hand` when exactly sword+hammer).
  `_spawn_pack(..., hands)` uses the list; empty keeps the old rolls.
- `loose_per_type` 3 lone wanderers of each released type every population
  (group "loose_subjects"), plus the n that walked out at release time
  (`_spawn_loose`, at `_far_point`: a corridor point >= 30 m from every player
  and out of sight).
- **Travelling groups rare**: `patrol_share` 0.2 of skeleton packs patrol
  (every one did); the rest keep their stretch (roam by `wander_share`, the
  enforcer by its escort). `convoy_count` 4 -> 1, and none until the sword
  hands (its crew) are out.

### The collector (scripts/collector.gd)
- `collector_count` 1 lone enforcer, spawned >= 45 m off once any type is out
  (`_spawn_collectors`, again every population). It is the enforcer's `patrol`
  (it implements `step`), so it fights like any enforcer when it sees a player
  and falls back to collecting after. Every 0.5 s: the nearest loose subject
  within 90 m (not engaged) -> navmesh path, replanned every 1.5 s; within
  2.2 m it is **shackled**: out of the group, its `patrol` = the collector, a
  chain (unit cylinder, local-scaled -- `Basis.scaled` would stretch world Y)
  from the enforcer's hand to its neck, following its trail 1.7 m apart. With
  CARRY 2 led (or none left in reach) it walks them to `collector_drop` and,
  within 3 m, hands them in (freed). Nobody to fetch: it roams 14-45 m legs.
  The enforcer killed: the led are loose again.

### The surgery last, then the boss
- surgery_vat.gd `bolted` (count of blocks shut): its prompt reads "Bolted to
  the floor   N containment blocks still shut" and `grab` refuses. surgery.gd
  `set_entrances_bolted(left)` on the ways in's vats (0 once `intro_done`), fed
  by maze `update_surgery_bolts()` (end of `_populate`, and every release).
- shard_door.gd `_use` asks `maze.surgery_done()` (surgery.gd `is_done`: the
  surgeon dead, or his claw kept) and otherwise toasts "The door will not
  answer. Something still works in the surgery."

### Measured
Throwaway windowed harness (seed 20260918, `Sandbox.enemies_passive`, the
Remnant off), 0 failures: start 48 criers / 0 skeletons / 0 convoys / no
collector; 5 blocks, 5 distinct types, 5 caged of 5 held cells each, all the
right type, a back door in 10 of 10 cells, 3 enforcers each; a caged prisoner
hit for 50 and alerted: 100 -> 100 hp, moved 0.00 m; surgery vats bolted [5, 5],
great door refusing. Sword block opened: type released, 5 loose sword hands,
10 of 10 doors up > 2 m, every prisoner gone, 10 of 10 front gates still solid,
bolts [4, 4], one collector. Collector (dormancy off for the test, two subjects
put 5-12 m off): shackled 2 in 29.6 s, chain drawn, led 9 m in 6 s with both
within 7 m, handed both in 7.5 s after being put 12 m from the drop. After a
reset: 34 skeletons, all sword, 3 loose, 1 collector, 1 convoy, the opened
block empty, the others caged again. All five opened: bolts [0, 0]; reset: 135
skeletons of all five types (shield 19, crossbow 37, sword 33, hammer 26,
drill 20), 7 patrols of 51 packs, 15 loose; save "released" lists all five;
`claw_kept` -> the door answers. **Re-broken** (`progression = false`): "no
corridor skeletons" fails (140), "no convoys" fails, "five blocks" fails (0).
Screenshots: slab shut with red lamp; open with green lamp on black; a shield
skeleton walking to its door; the torch moved off the door.

Bench (RTX 3060, `--bench`, 1280x720 window, editor closed), at the start of a
game: before 74.0 fps, worst p99 23.54 ms, 655.9 MB, 245 enemies; after 101.8
fps, worst p99 14.58 ms, 613.6 MB, 49 enemies (physics 2.4-4.2 ms against
4.2-8.6). The layouts differ (room count), and this is the start: with every
type out the corridor population is back near the old one (135 skeletons +
their enforcers) plus 15 loose and the collector -- not benched.

### Traps
- A Dictionary used as a Dictionary KEY changes hash when it is mutated: a
  harness keyed per-cell values by the cell dict and the lookup failed after
  the cell gained "lifted". Index by position instead.
- Setting `dormant_range = 0` does not wake an enemy already asleep (`_dormant`
  stays true and enforcer.gd returns before moving). Clear `_dormant` too.
- An enforcer never walks while dormant (> 45 m from every player), so the
  collector only works where a player is near -- as every enemy does.
- The sewer lizards' "not expect to not find the most reachable polygons" nav
  error shows on some runs (path asked before the sewer navmesh is baked);
  it predates this.
