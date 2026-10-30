## 131. The intro outside the dungeon: the knight's hilt, Vardia, every control taught, kidnapped into the cell; lizards always drop the small heal (2026-10-30)

The user:
- "Make the lizards drop the little heals every single time you kill one."
- "Make an intro outside the dungeon. this should teach the player all about
  the movement, and how to do everything they need to do. It should be placed
  in a hill area thats heavilly forrested. The backstory (cutscene) is that the
  player got the artifact (weapon handle) long ago as a kid from a dying
  knight, and the kid has tried to research this weapon handle that is crystal
  powered his whole life. all he could find about the artifact is the fact that
  it traces back to an ancient civilization called Vardia, and found some
  coordinates to where it was. The player should gain control when he arrives
  at the place where the civilization was. He should search the area while
  learning all controls. Once the player knows all the controls, he should get
  kidnapped unexpectedly and wake up in the dungeon cell like it is now."

### Stand-ins, and why

Note 98's rule is no assets made in code. None could be generated here: the
Higgsfield connector offers only 7 read-only tools (no generation), the account
has 7 credits, and `TRIPO_API_KEY` is not set. Asked, the user chose **stand-ins
now**, to be swapped for Higgsfield models later.

**Made in code (swap these):** the terrain mesh, every plant and its textures
(`intro_flora.gd`), the knight, the boy, the sentinel and the hilt
(`intro_figure.gd`), the training posts (`intro_post.gd`), the study's furniture.

**Already generated, reused:** the ruins are the brick kit's arch, walls, pillars
and slabs, the morgue slab (the altar) and the cart; the Tripo kit's columns,
rocks and fallen blocks; the old organic level's ground and rock textures.

### Lizards (`enemy.gd`, `sewer_lizard.gd`)

enemy.gd `sure_drops`: dropped on every death, before the rolls. The lizard's is
`small_health_potion`; its `drop_odds` keeps `bone_fragment` 0.3.

### How it is wired

- maze.gd, at `level_built`: `INTRO.wanted(save)` -> `INTRO.begin(self)` instead
  of `wake_up` and the "new game" save.
- `wanted`: a new game in a slot. Never for a save or the sandbox, so never for
  harnesses (slot -1). `-- --intro` forces it, `-- --no-intro` leaves it out.
- `intro.gd` is added BESIDE the maze, because the maze is hidden: `maze.visible`
  off, its minimap (`_minimap_root`) off, the moon's energy 0. The explore map
  stays alive (the map lesson needs it). Enemies are asleep by distance anyway.
- `maze.intro_running` blocks saving (save_system.gd `_safe`). Quitting mid-intro
  leaves the slot empty, so it starts again.
- The Environment is changed in place, `ENV_KEYS` kept and restored, as the
  sewer's haze does: player.gd holds a reference to it for its colour effects.
- The world sits at `ORIGIN` (-2400, 0, 0), above the sewer's `SPLIT_Y`, and is
  freed at the end.

### The story (`intro.gd _story`, about 95 s)

Hold jump 1 s to skip (`SKIP_HOLD`); control comes 3.2 s after the skip.

1. "Many years ago". Night on the forest road: a burning cart, the knight
   against a tree, the boy kneeling. The hilt passes from hand to hand; he dies.
2. The study: candle, books, the hilt on the desk, the map with "VARDIA ?" and
   the coordinates.
3. "Thirty years later". The hill at dusk; the last of the path walked in the
   player's own eyes (`scene_walk_to`), then "VARDIA / The coordinates end here."

### The world (`intro_world.gd`)

- 360 m terrain on a 2 m grid: the height is worked out once into `_grid`
  (181 x 181). The first version called the full height function about a million
  times; `height()` now reads the grid.
- 3,073 trees, 1,878 ferns, 699 bushes, 1,408 grass tufts, in MultiMeshes by 40 m
  chunk with visibility ranges. Built in about 0.5 s, under the black.
- Foliage is alpha-cut cards with bent normals (`intro_foliage.gdshader`).
- The player is held inside `BOUND_R` 50 m round the ruins; the ring has a gap for
  the walk up, and `close_path()` shuts it on arrival.
- The looks are `profile()` / `set_lights()`: dusk, night, study.

### The lessons (`intro_lessons.gd`)

24, each watched for in the player's real state, with keyboard and pad wording:
look, walk, jump the trunk, read the stone, pack, map, sword (cut, spin, slam),
weapon wheel, spear (stab, dash, throw), axe (chop, throw, berserk), back to the
sword, ghost, block, parry, bring the sentinel down, drink, the altar.

- Co-op: a lesson moves on when every player has done it.
- **The sentinel** (`intro_sentinel.gd`) wakes for the block lesson. Its blow is
  telegraphed (WIND 1.05 s, parry cue 0.42 s before), a parry throws it reeling,
  it cannot be hurt until the "fell" lesson (`mortal`), and it pulls its blows so
  nobody can die here (a death would run the dungeon's respawn).
- The drink lesson sets health to 60% if it is over 70%, so there is something
  to drink for.

### Taken (`intro.gd _taken`, `_finish`, 22 s from the altar)

The altar lights up; blue eyes in the trees behind; the burlap sack from note 128;
a struggle; "That's the one"; a white flash and black; "Below. With the others."

`_finish` restores everything, puts them on the cell spot, resets the pack and
health to a new game's (the lesson's potions do not count), and calls `wake_up`.
Then `Saves.request("new game")`, as before.

### Measured (throwaway windowed harnesses, deleted)

- **Lizards:** 200 of 200 `_grant_drop` calls gave a small potion, with 29 bone
  fragments (expected about 30).
- **All 24 lessons** passed in one play-through driven by pad events.
- **The ending,** tested separately: the intro gone 22.0 s after the altar, the
  maze visible, `intro_running` false, 0.30 m from the cell spot, waking; depth
  fog back, 100 / 100 health, 3 potions; control back afterward.
- About 200 fps at the ruins in the default window.

### NOT tested

- **The whole game in one sitting:** the full play-through was killed by its time
  limit at the altar, so the ending was run alone, jumping to the altar lesson.
- **Co-op** was never run.
- **A real new game from the title** (`Saves.slot` >= 0): every run used `--intro`
  with slot -1, so the "new game" save after the wake did not run. It was a black
  screen; see note 132.
- **Keyboard and mouse:** the harness played on pad events; the look lesson
  was driven by rotating the player.
- **The two wheels' menus:** the harness used `select_slot` and `use_consumable`,
  so only the lessons' detection of the result was tested.
- **The night, study and vista shots after the last retune.** The arrival was
  looked at afterward; the soft-dot fix for the blocky fire was not.
- **`--bench`:** the bench never enters the intro, and nothing measured it at
  3440x1440.

### Not done

- Skipping the tutorial: only the story can be skipped.
- Sounds and a voice: the lines are subtitles.
- Generated models for everything listed as stand-ins.
- The hilt in the player's hand: it exists only in the cutscene, and nothing yet
  connects it to the sword they start with.

### Traps

- **`:=` cannot infer a type from `[...][i]`.** Give it one.
- **`const Interact := preload(...)` shadows the global class.** Just use it.
- **An additive material draws its colour whole, whatever its alpha.** The soft
  dot has to fade in RGB too.
- **Made-up joypad axes reset each frame**, buttons do not: a harness has to
  re-send a held stick every physics frame.
- **A random scatter can land in a lesson's way.** A fallen block stopped the run
  at the trunk, so the entry, posts, sentinel and stone are now kept clear.
- **The first frames after the level builds stall on shaders:** a wall-clock wait
  says nothing about how far a coroutine has got.
