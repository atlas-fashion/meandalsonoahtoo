## 186. One leg of every arch was a black hole; darker level and torches; a soft flicker (2026-11-16)

Noah, after the remodel of notes 183 and 184: "fix the black holes in the walls
of the maze and missing portions of the arch in the prison rooms. Make the
overall level darker now that the stone texture is lighter. darken the
torchlight and make the flicker softer and easier on the eyes."

### The black holes and the arch's missing portions: one bug

**One leg of every arch drew black.** `tools/build_dungeon_kit.py`
`build_arch_like` lays the jambs (the legs' inner faces, through the arch's
thickness) on `Plane((s * half, 0, 0), (0, 0, 1), (0, 1, 0))` for both legs. A
`Plane` faces `u x v`, which is -x for both: right for the +x leg (into the
doorway), backwards for the -x leg, whose stones faced into their own leg and
were culled from the doorway. What showed was the dark backing: a black slab
1.3 m wide (the arch's thickness) and 3 m high, floor to springing, in one leg
of every `arch`, `arch_b` and `door_arch` -- every cell boundary in the maze,
every wooden door's arch, and the arches the prison's and the holding cells'
gates hang in, where the player stands right in the archway to open the gate.
- Fixed: u runs along `s` z (`Plane(..., (0, 0, s), ...)`), the cuts mirrored
  for the -x leg. Same stones, same count, same file size (2,940,036 bytes).
- **Measured** (throwaway headless harness, the area of the triangles in each
  jamb's plane by which way they face): before, the -x leg 0.00 m2 facing the
  doorway and 4.15 facing away (4.43 `arch_b`, 4.01 `door_arch`), the +x leg
  right; after, 4.14 / 4.15, 4.44 / 4.41 and 4.02 / 4.02 m2 facing the doorway
  and 0.00 away. The harness was written against the broken kit first and
  reported all three BAD.
- Seen in game, flat light, at a holding cell's gate: a black door-sized
  opening beside the gate before, coursed stone after.
- **Why note 183's void test passed**: it counts the magenta world showing
  through. A culled face shows the piece's own dark backing, which is black,
  not void. A hole test has to look at which way faces point as well.

**The walls with stones fallen out** (`wall_broken`, `wall_broken_b`, 64 walls
on the default seed) were the other black rectangles. `_pit` set the rubble
core 0.24 m back with a back at shade 0.12, and every torch hangs on a wall, so
its light rakes along the walls: the hole was all shadow. Now `pit_depth` 0.03:
the core stones stand 1.5-4.5 cm behind the wall's face (jitter +-0.012, was
-0.03..0.04), at shade 0.9 (was 0.55), the hole's sides 0.72 (0.42), its back
0.4 at 9 cm (0.12 at 46 cm). It reads as the facing fallen away and rough core
showing; a raking torch still lights it. An intermediate 7 cm was still black
under a raking test light. This supersedes note 183's "the hole lined, the
rubble core behind".

Both by rebuilding the kit (`blender -b --python tools/build_dungeon_kit.py`,
then `godot --headless --import --path .`).

### Darker (scripts/brick_level.gd `STONE_DARKEN`, scripts/maze.gd `module_torch_energy`)

- `STONE_DARKEN` 0.8 on the Blender kit's stone and floor albedo (`DK_ALBEDO`)
  and on the ForgeGUI stone (`FORGE_STONE_CAST`).
- `module_torch_energy` 1.1 -> 0.6. Rooms that scale it (the prison's x 1.6,
  the cells' `TORCH_SHARE`) follow.
- **Measured.** A throwaway windowed harness stood the player at 16 corridor
  cells (seeded) and 3 chest rooms, 4 headings each, every torch held steady,
  and took the screen's mean luminance (sRGB) -- the Tripo stone at its torch
  energy as the level Noah had tuned (`-- --tripo-kit`), the new stone as it
  was, and candidates set at run time (torch `base_energy` and the kit
  materials' albedo scaled), no rebuild per candidate:

  ```
                               corridors (64 views)     rooms (12)
                               mean     median          mean
  Tripo stone, torches 1.1     0.0179   0.0108          0.103   (before the remodel)
  new stone 1.0, torches 1.1   0.0621   0.0378          0.133   (what Noah saw)
  new stone 0.8, torches 0.9   0.0302   0.0158          0.098   (first pass)
  new stone 0.65, torches 0.85 0.0181   0.0065          0.083
  new stone 0.75, torches 0.65 0.0230   0.0103          0.071
  new stone 0.8, torches 0.6   0.0227   0.0121          0.070   (kept)
  ```

  The remodel had made the corridors 3 to 5 times brighter on screen. The
  first pass (0.8 / 0.9) was still 2-3 times the old level beside a torch.
  Darkening the stone further (0.65) took the places between torches under
  the old level (0.0015 against 0.0061 at one spot) while beside a torch it
  stayed twice as bright: ACES's toe crushes what is already dim. The new
  stone answers a torch more strongly than the Tripo stone did, so the lever
  is the torch, not the albedo. Kept: corridors at about the old level spot by
  spot, a little brighter beside a torch, rooms a third darker.
- The same run twice agrees per view to a few percent; a handful of views
  move more (effects in view), so compare medians and spot by spot.

### A soft flicker (scripts/torch.gd, scenes/chandelier.tscn)

| | before | now |
|---|---|---|
| `flicker_amount` | 0.62 | 0.4 |
| `flicker_speed` | 2.6 | 0.6 |
| `gutter_chance`, `gutter_depth` | 0.6, 0.6 | 0.12, 0.22 |
| `FLICKER_SMOOTH` | 0.03 s | 0.14 s |
| `GUTTER_IN`, `GUTTER_OUT` (new) | 0.12 s, 2.5 /s | 0.4 s, 0.7 /s |
| noise octaves | 3 | 2 |
| `sway`, `colour_swing` | 0.07, 0.35 | 0.04, 0.25 |

The chandelier's own overrides likewise (0.35, 0.5, 0.1, 0.25). Measured with
torch.gd's flicker math run headless for 24 torches x 60 s at 60 fps: the
light's change from one frame to the next fell from 6.4% of its brightness on
average (p99 19%, worst 30%) to 1.0% (p99 2.9%, worst 4.3%); it now swings
between 0.64 and 1.22 of its level (was 0.18 to 1.35), standard deviation 0.079
(0.17). A slow breathing glow, no stutter and no deep dips.

### Not measured
Frame time. Noah was playing another game on the PC throughout, so a benchmark
would have been wrong and would have slowed his game. Nothing here adds a
light, a pass or a triangle: the kit is the same size, one jamb per arch that
was culled is now drawn.

### Traps
- **A test run must not take the user's focus or play sound** (he said so
  mid-task): every windowed run went on a hidden desktop (`tools/hidden_run.ps1`,
  note 188) with `--audio-driver Dummy`. On a hidden desktop the game sees
  itself unfocused and the pause menu comes up over later shots: free the
  `PauseMenu` node in the harness.
- With the player's `_physics_process` off, the knight's body stays where it
  was and fills later shots; shoot from a spot away from the last one, or hide it.
- Looking for a hole by eye in lit screenshots found nothing in ~200 views:
  under torchlight an arch's black leg reads as shadow. Flat ambient light,
  and standing where the player stands (in the archway, at the gate), found it
  at once.
- Blender's bundled Python is the only Python on this PC, and a file edit
  through it must keep the file's line endings (`newline=''`).
