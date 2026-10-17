## 18. Puzzle rooms, shards and the great door (2026-10-08)

- **Every chest room is a puzzle room** (`scripts/puzzle_room.gd`, built by
  `maze._build_puzzle_rooms` after the morgue, before the bake; `puzzle_rooms`
  export). Entering (1.8 m inside the gate line) seals the room's gates
  (`_gates[i + 1]`, driven in `maze._process` from each room's `sealed`) and
  announces the puzzle's name and hint; solving sinks them, brings the dimmed
  sky light back up and raises a plinth out of the floor in a light column with
  the room's chest on it. The chest (`chest.gd` `shard`, `coins`) holds the
  room's shard (`Inventory.SHARDS`, kind "Relic", bag first, Treasure tab).
  No pedestals, guards or `_spawn_chests` chests in this mode.
- **Four puzzles, dealt like a deck** (every one before any repeats):
  `platforms` THE STAIR OF KEYS -- 4 colour levers each raise 2-3 of 4
  platforms one step (0.85 m), bands of colour on each platform per lever;
  the planner (`_plan_platforms`) guarantees exactly ONE lever combination
  makes the stair 1-2-3-4 up to the keystone at 5; standing on it solves.
  `prism` -- 3 levers XOR R/G/B beams into a crystal (rows independent over
  GF(2), rings on each post show its beams); hold the Eye's colour 1 s,
  three rounds. `chorus` -- 6 coloured stones sing a sequence (3, 4, 5 notes),
  strike them back; a wrong note drains 10 (never below 25%) and it replays.
  `veil` -- 4 glyph dials; which glyph each wants is written on corner stelae
  visible ONLY in ghost mode. Shapes, not colours, because ghost mode drains
  the colour from the view.
- **A sealed room is a ward**: `stalker._warded` treats the player as hidden,
  so the Remnant cannot trap and kill them in a room they cannot leave.
- **Death**: an unsolved room resets and unseals (`on_world_reset`, called by
  maze AFTER `_populate`); a solved room stays solved, an unopened chest stays.
- **The mimic** is the room far from the start both ways (walk and straight
  line, each scaled by the largest; `_far_room_from_start`) -- the first pick
  by walk alone was 367 tiles' walk but 36 m from the start. It rises in place
  of the chest (`wake_floor` -1.3, opened from the floor), `register_mimic`
  hands it to the old seal-until-dead logic, it drops the shard on death (onto
  the floor if the pack is full), and a death brings an unkilled one back.
- **The shard door** (`scripts/shard_door.gd`, `maze._build_shard_door`): two
  8 m stone-and-gold leaves in the boss hall's arch, hinged on its HALL face
  (the portcullis hangs mid-arch in front of them), one colour-ringed socket
  per room. E sets every carried shard (out of the pack first, so a death
  cannot copy one); with all five the shards blaze, the seal burns away and the
  leaves swing into the hall (letterboxed scene, ~10 s), then `OpenLeaves`
  collision. With none it says how many are set.
- **Traps hit**: the level's arch stone (`_synth_arch_material`) is lit by its
  MultiMesh instance colours; on plain meshes it renders BLACK under any light
  -- the puzzle stone is its own normal-mapped grey with a faint emission
  standing in for ambient. `CylinderMesh.radial_segments` will not go below 4,
  so a "triangle" came out a diamond (the square turned 45 deg): the triangle
  glyph is built by hand (`_triangle_mesh`). Sky dimmed to 0.35 left only the
  glowing parts visible; it is 0.55 plus a room-coloured light (`RoomLight`).
- Measured in a harness (90/90): 5 rooms, all 4 kinds; each sealed on entry
  with its gates up, solved through real E presses on levers/stones/dials, the
  platform stair CLIMBED with the movement and jump keys onto the keystone,
  gates down, plinth at 0.60, shard in the pack; death in an unsolved room
  unsealed and reset it; mimic sprang, sealed its room, open again on death,
  shard given; Remnant lost a player in a sealed room (control: kept hunting
  outside); door refused with no shards, opened with five, control returned,
  walked 5 m into the hall. Clean run: 0 enemies in rooms. Not benchmarked on
  the P620 (one extra omni and ~40-60 small meshes per room).
- **The five dealt puzzles (2026-10-09)**: `puzzle_room.DEALT` = platforms, drowning,
  weighing, mirrors, bells -- one per room. prism / chorus / veil are still in
  the file (`KINDS`) but no longer dealt.
  - **Stair of Keys, harder**: 7 levers (red, blue, green, gold, violet, cyan,
    white), 5 platforms, keystone at level 6 (5.1 m). Every lever moves 2-3
    platforms; the planner keeps only layouts where exactly ONE of the 128
    lever sets makes the stair, and that set is 3-4 levers. Plans in ~0.5 ms.
  - **Drowning Court**: sealed at the COURT's 12 arches by stone sluices (the
    seal waits until the player is 1.2 m inside the court, or they would be
    shut out in the arcade). Water rises a stage every 9 s (stages 0/1.3/2.4/
    3.5 m); the player floats in it (`player.water_depth`, group "water",
    `SWIM_FLOAT` 0.95, jump works from the water, `swim_speed_scale`). Stone
    tops 0.02/1.45/2.55/3.65: each reachable AND above water at exactly one
    stage. Step on them in the Eye's order; a wrong one surges the water +1;
    the drain wheel lets 2 stages out; chest-deep water drains 3 hp/s down to
    25%. Traps: two water tweens overlapping (a drain still running under a
    surge) kept dragging the level back -- one tween at a time now; bobbing off
    a stone and back on counted as a wrong stone -- re-standing on the stone
    just counted is ignored; floating depth is 0.95, so the cold threshold is
    0.8, not 1.0. The water's grazing red sheen must stay faint (0.07): seen from
    a hand above it, nearly all of it is grazing.
  - **Weighing Room**: 2 shrouded bodies (5), 3 skulls (2), 4 bone bundles (1)
    dealt into three distinct targets (gold ingots on each scale's right pan).
    E lifts (held before the camera, `hands_busy`, `player.carry_speed_scale`
    0.55 for a body), E on a scale's left pan places / takes back, E at nothing
    sets it down. All three level and nothing carried -> solved. Beam: a
    positive angle drops the load's pan (the first version tipped backwards).
  - **Mirror Corridor**: 5x5 grid (3 m) at chest height; a red lantern and a
    coloured eye at two of eight edge ports. A DFS lays a path with >= 3 turns
    (mirrors) and one pane of the eye's colour; decoys: a wrong-colour pane,
    three mirrors, three pillars; mirrors scrambled. Beam meshes are POOLED:
    freeing them the frame they were made left `Graphics._apply_to_node` a
    deferred call on a dead node (an error per segment per turn).
  - **Bell Parry**: three gallows, blades swung by energy (never gain/lose
    height), periods 3.0/2.5/2.1 s. A blade meeting the player calls
    `take_damage(12, dir, blade)` with a `Blade` attacker (no-op knockback and
    damage) and bounces back; the player's `guarded(parried, attacker)` decides
    it. Three parries running rings the bell; a block or a hit resets the count.
  - Measured in a harness, 57/57 + 10/10 on resets: the stair climbed with real
    jumps; the drowning court sealed only inside, sluices solid, water rose by
    itself, dry jump short of the first column, every stone reached by
    swimming and jumping at its own stage, drain wheel by E, solved, drained,
    vault up; weighing lift/place/take/drop by E and solved; mirrors turned by
    E and solved; every bell rung by real right-click parries (unguarded: hurt;
    guard held: block only); a death in each new room resets it.

