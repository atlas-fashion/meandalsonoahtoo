## 94. The surgery: the surgical table, depowered not killed (2026-10-21)

The user: "a new room in the maze ... where the old dead prisoners are supposed
to be turned bionic. The thing that does this is a robotic table. The table
should act like a boss, but you should not be able to kill it. You have to
depower it." Four phases (it wakes; three cables into three wall mechanisms;
switches that briefly disable a system each, while it keeps hunting; lure the
restraint arm into a wall clamp and cut the power cable under its chassis),
plus: clues physical (no text, no glowing markers), danger escalating as
systems are disabled, more than one solution, a wrong switch that teaches
rather than resets, and the room telling what happened to the last prisoners.

**Higgsfield contributed nothing.** The user asked for it, but the connector
can only list past generations and credits -- it cannot generate -- and the
cloud network refuses its CDN (403), so not even old images could be pulled
in. Every mesh here is procedural (boxes, cylinders, tori merged per material),
like the morgue's furniture. If the user makes art on the Higgsfield site, the
files go into the project by hand.

### Where it is

- **`scripts/module_level.gd`**: option `"surgery"` (default false; maze.gd
  passes `surgery_enabled`). `_make_surgery_hall(out, enclose)` takes the chest
  room that maximises min(distance to the start, distance to the morgue),
  kind "surgery"; the morgue's enclosure code moved into `_enclose_hall()`,
  which both now call (court off, hall on, `_classify`). It costs a chest room,
  so maze.gd asks for `module_chest_rooms + morgue + surgery` rooms and five
  chest rooms remain. **Existing saves' layouts change**: the extra room shifts
  the generator, so a saved seed builds a different maze than it did before.
- **`scripts/maze.gd`**: `surgery_enabled`, `_pick_surgery()`, builds
  `surgery.gd build_room()` after the morgue, `is_in_surgery(tile)` (kept out of
  enemy spawns and `_touches_room`), `surgery_centre()`, `surgery()`;
  `save_state` / `restore_world` carry `data["surgery"]`; the end of
  `_populate()` calls its `on_world_reset()` (so a death puts a live table back
  to sleep, a depowered one stays dead).
- **`scripts/sandbox_world.gd`**: a "Surgery" teleport next to the Morgue one.
- **`scripts/surgery.gd`** extends morgue.gd (piers, pilasters, torches,
  `_limit_view`). Local frame: +Z toward the first doorway. Built by `_dress()`:
  - three **wall mechanisms** in wall slots (`_wall_slots`: non-corner,
    non-doorway): ARMS = two pistons and a gear (back wall preferred for the
    core, left for the arms, right for the legs); LEGS = a flywheel with an iron
    bar on a hook beside it; CORE = a dark glass column with a lit rod and one
    OmniLight (range 4.5).
  - the **clamp** on the arms' wall next to them (two toothed jaws, mouth at
    (0, 1.35, 0.95) local). It sits on the arms' relay: cutting the arms springs
    it open and it stays open (latched) until something is caught.
  - the **pedestal** (top 0.46 m, layers 2|256) and an old surgical **lamp**
    (SpotLight 2.4 at 4.25 m) on the table's circuit -- it dies with it.
  - three **levers** on piers (-9,0,3), (9,0,-3), (3,0,-9); which system each
    cuts is **shuffled per seed**, so it must be found out every game.
  - the **story** (`_build_story`): in the four (+-6, +-6) cells, shuffled --
    two pairs of steel slabs with strapped prisoners half-fitted with
    prostheses, a broken table on its side, a toppled rack of limbs; nine tools
    dropped round the pedestal; eight torn restraints; corpses in the corners.
    These are also the cover.
  - **cables** (`_build_cables`, `_update_cables`, `_animate_cable`): one
    MultiMesh of 30 short sections per cable, `shaders/surgery_cable.gdshader`
    reading INSTANCE_CUSTOM (r = glow, gba = colour). Routed every 0.25 s along
    the level's navmesh from the table's plug to the port, hugging the floor and
    climbing the wall at the end. Arms cable twitches when the arms move, legs
    cable shivers while it crawls, core cable carries the core's heartbeat
    pulse. A straight two-point path is normal where nothing is in the way.
  - the table's own **navmesh** (`_bake_table_nav`): a private NavigationServer
    map, agent radius 1.0, height 1.5, cell 0.25, obstacles = piers and cover
    boxes. 172 polygons. Freed in `_exit_tree`.
- **`scripts/surgical_table.gd`** (CharacterBody3D, `State` DORMANT, WAKING,
  HUNT, GRAB, SWEEP, REAR, CLAMPED, STALL, DYING, DEAD):
  - **Wakes** when a standing player is inside the room (respects
    `Sandbox.enemies_passive`): 3 s -- sensor head turns to them, restraints
    snap open and the strapped prisoner is thrown off, six legs unfold, it rises
    from 0.84 to 1.08 m and hunts.
  - **Moves**: GRAB (the telescoping restraint arm, four sections and a
    shackle; range 2.4-5.2 m, reach 7.5 m, aim tracks until 0.28 s before the
    lunge, 20 dmg and a yank; `parry_cue` to every player; a parry snaps the
    arm back and stuns it 0.9 s), SWEEP (pincers, 2.9 m, 12 dmg), REAR (rises and slams, 3.1 m radius,
    24 dmg, cooldown 8 -> 5 s). Reach ray uses mask 2 only (on the default mask
    it hit the player it was reaching for).
  - **Escalation**: `level` 0..4 rises the first time each system is cut, each
    time it tears free of the clamp. SPEED 1.6 -> 3.5, TURN 1.4 -> 2.9, grab
    wind-up 1.15 -> 0.7, cut time 7.5 -> 4.5 s, clamp hold 7.5 -> 4.8 s.
  - **It cannot be killed**: `take_damage` on steel only clangs and sparks. The
    power cable under its belly is a separate hitbox (inner `CableHitbox`, on
    layer 4 only while exposed) and takes CABLE_CUTS = 3 blows. Exposed while
    it rears (rise and hold), while it is clamped, and while it drags itself
    with the legs cut or jammed (lift 0.5, nose down).
  - **Systems** (`cut(system)`): arms off aborts a grab/sweep; legs off aborts
    a rear and it drags at 0.55 m/s; core off STALLS it 1.9 s, dark, then the
    arms' and legs' cables flare and feed it back -- the wrong-switch clue that
    the other two power the core.
  - **Clamped** (`room.clamp_try_catch(shoulder, tip)` -- the arm need only run
    through the jaws, segment distance <= 1.15): hauled to the wall, belly up.
    Strain builds only while its legs are powered; at the hold time it tears
    free, the clamp is wrecked open again, level + 1.
  - **Depowered** (`_shutdown(cause)`): DYING 3.2 s, crashes to 0.36 m, legs
    splay, core and lens fade to 0, the lamp dies, the hum stops (an
    AudioStreamGenerator at 22050 Hz -- the only machine sound in the dungeon),
    two gold crystals and 40 coins drop. Saved as `{"down", "at", "yaw",
    "jammed"}`; reloads dead where it fell.

### The solutions

1. **Clamp** (the intended one): find the arms lever, then bait a grab with the
   clamp behind you; caught, run under and cut the belly cable three times
   before it tears free.
2. **Sever while it rears**: its belly shows on every rear-up; three hits.
3. **Jam the legs**: cut the legs, put the bar through the stopped flywheel;
   it drags itself forever after with its belly showing.
4. **The relay**: arms and legs both cut, then the core -- nothing left to feed
   it back, and it shuts down.

### Measured

A throwaway harness (54 checks, deleted) drove it headless: wake and prisoner
thrown, stands 1.07 m, reaches striking range from five spots, grabs, sweeps
and rears land (284 health taken over the run), the belly exposed on a rear,
steel shrugs off blows, every lever does what it says and angers it, the clamp
catches in one try and strain rises only with the legs on, three cuts kill
power, light reads 0.000, lamp off, hum stopped, two drops, saved and reloaded
dead, reset leaves it dead, the relay shutdown works, a jam keeps the legs dead
and the belly exposed. 0 failures. Rendered windowed under xvfb (OpenGL, so
the grade is not the game's) to check the table, mechanisms, clamp, lever and
the dead pose read right.

**Not benchmarked on the P620**: the cloud machine has no GPU. Cost is three
MultiMeshes, one OmniLight (the core column) and one SpotLight (the lamp), all
reached by `Graphics._apply_light` like every other light; sparks check
`Graphics.effects`. Run `--bench` with the sandbox teleport to it before
trusting it at 3440x1440.

### Traps

- **A `--script` harness must not preload surgical_table.gd**: it names
  `Sandbox`, the preload fails with "Identifier not found" and poisons the
  cached script for the game too. `load()` it after the tree is up.
- **Use `global_rotation`, not `rotation`, inside a rotated room**: the table
  turned away from the player until every yaw read was global.
- **A floating-mode body's shape must clear the floor's bumps**: the brick floor
  is uneven; the cylinder sat at its height and caught. Raised 0.3 m.
- **Nav agent radius and height must be multiples of the cell** or the bake
  warns and rounds; and an agent radius of 1.25 eroded the aisles between the
  3.8 m-apart piers into islands. RADIUS 0.95, agent 1.0. Take the path's end
  as the target when the player is off the mesh, never beeline.
- **Cables kept under the room node**, not `top_level`: a visibility range is
  measured from the node's origin (note 6.09), and the world origin is far away.
- `"Too many instances using shader instance variables"` and "Dual paraboloid
  shadow mode not supported" flood the OpenGL/xvfb log: those are the torches'
  instance uniforms and the hand torch's shadow under the Compatibility
  renderer, not this room.

**Benchmarked (2026-10-21, on the user's PC -- now an RTX 3060, not the P620;
3440x1440, current settings):** `tools/benchmark.gd` has a `surgery` station
(placed from the room's floor, half its court out from the table: a ray from
above would land on the hall's roof). surgery 45.4 fps avg, 1% low 37.4,
p99 26.73 ms, 3,220 draws -- in line with the chest room (25.84) and below the
worst station (boss room edge 31.06). Overall 52.0 fps, 1205.6 MB.
