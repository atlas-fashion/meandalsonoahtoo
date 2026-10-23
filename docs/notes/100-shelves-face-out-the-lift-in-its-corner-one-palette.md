## 100. The shelves face out and stand taller, the lift in its corner, one palette, slower slams (2026-10-23)

The user: "Right now, the bookshelves are backs on both sides and too short, and
the lift that takes you to the control room doesnt fit the player very well,
so the player can see through the top of it when he's inside. Make all the
assets look seamless. Like they are supposed to be there. Make more time
between attacks from the claw." Builds on note 99.

### The shelves (`scripts/surgery.gd` `_build_maze`, the kit)

**Backs on both sides was a placement bug.** The kit's shelves face +Z (Tripo
returned them facing +X; `-90` turns them). `_build_maze` placed each of a
pair at `mid - facing * depth/2` -- *behind* the line, facing it -- so both
fronts met inside the wall and only the backs showed, from either side. Now
`mid + facing * depth/2`, `facing` in `[normal, -normal]`.

**Taller:** `fit` 2.9 x 0.42 x **3.9** (was 3.3; `SHELF_H` 3.9) in
tools/build_surgery_kit.py, budget 9000 each. 16000 was tried for smoother
crests and cost 4 M more primitives for nothing worth it; back to 9000.

**Joins:** where two walls meet at a corner, a T or a cross, the cases of one
run into the other's (each pair is 0.84 deep), so an oak post covers the join
(`_maze_post`: the kit's `beam` stood on end, `POST_W` 0.88 square, 3.45 tall
-- under the cases' carved crests, which carry on over it; its own collision).
Where a wall runs straight on, or ends, there is no post: the first pass put
one at every end and the maze became a forest of plain timber pillars.

**The claw over taller shelves** (`surgical_table.gd`): `HOVER_Y` 5.0 -> 5.6,
so the fingertips (CLAW_LEN 1.55 under the wrist) clear 3.9 m. Carrying a
player, the wrist at `CARRY_Y` 5.9 (was 4.6) and the body held `CARRY_GRIP`
0.45 of the claw down (was 0.75): **the carried body had always swept through
the shelves** -- measured, 48 frames of a 230-frame carry inside a shelf with
the old values, 0 with the new.

### The lift (`scripts/surgery_control.gd` `_run_lift`, the kit)

**Two faults, the first the real one.** (1) **The cage was standing on the
surgical table in the middle of the hall.** maze.gd moves the finished level
under the navmesh region after it is built; a `sync_to_physics`
AnimatableBody3D moved like that takes back the physics server's transform --
still the origin -- so the cage (local (-11.9, 0, -11.9)) came back at (0, 0, 0).
A player in it stood on the table top (1.2 m) with their eye 2.9 m over the
cage floor, through its 2.4 m roof. Note 99's harness only checked the cage's
height and passed. `_run_lift` now sets the full position every frame
(`_lift_centre()` + `_cage_y`) when it differs. (2) The `liftcage` model came
with its hanging chains and pulley, counted in its 2.4 m: the cage's roof sat at
~1.8 m. A 9th kit field `crop` (keep the bottom fraction of the height, before
fitting) -- 0.745 here, where a height profile of the raw shows the roof ends
and the chains begin. The cage's roof is now at 2.4 m.

Measured riding up: the eye 1.70-1.72 m over the cage floor all the way, at
least 0.52 m under the roof, the player in the cage; up at 3.6 the booth door
1.72 m away; the kick-in scene then runs through (door broken, surgeon dead,
the table switched off, state 8) and the player stays in the booth at 3.6.

### One palette (`surgical_table.gd` `grade`)

The kit's mean albedo ran from 0.08 (the chain) to 0.19 (the wrapped bundle) in
luminance and 0.12 to 0.70 in saturation -- grey stone next to orange rust next
to pale wood -- which is most of why pieces looked set down from different
sets. `grade(node)` pulls each material's mean colour (a 16 x 16 reduction of
its albedo texture) `GRADE_PULL` 0.65 of the way toward `GRADE_TARGET` (0.17,
0.135, 0.105: the kit's own mean, (0.176, 0.132, 0.098), a little
desaturated), per channel, through `albedo_color` (clamped 0.6 .. 1.7) -- the
texture's detail stays. Once per material (`_graded`), before any glow
duplicate is made. Called by surgery.gd `_kit` and `_mesh_of`, surgery_control.gd
`_piece`, `attach_prosthetic`, and the table's own `_shadows` and arm segments.

### More time between slams

`REAR_COOLDOWN` [2.6, 2.3, 2.0, 1.8, 1.6] -> **[5.0, 4.5, 4.0, 3.6, 3.2]** s
(from one slam ending to the next starting), the first slam 2.5 s after it
wakes (was 1.0), and 3.5 s after it lets someone go (`RELEASE_REST`, was 2.2).
Measured at level 0, dodging each slam: gaps 5.02, 5.02, 5.00, 4.98 s.

### Benchmark

RTX 3060, 3440x1440, editor closed. Note 99's version (stashed): surgery 40.3
fps, 1% low 30.0, p99 33.38 ms, 16.8 M prims. Now: 38.2 / 38.3 fps, 1% low
23.0 / 29.5, p99 43.53 / 33.94 ms, 18.5 / 17.9 M prims (two runs; the p99
swings that much between runs). About 1.3 ms of average frame for shelves 18 %
taller (more pixels, in a pixel-bound game) and the posts. Video memory 1327.4
MB, unchanged. Other stations unchanged.

### Traps

- **A `sync_to_physics` AnimatableBody3D loses a position set before the
  level is moved** (here, reparented for the navmesh bake). Set it again after,
  or every frame.
- A test that measures one coordinate of a moving thing passes while the thing
  is in the wrong place: check where it is, not just how high.
- A harness filtering colliders by "Maze" in the path matches everything: the
  level's root node is named Maze.
- Rebuilding a kit piece can rewrite its textures' `.import` (mipmaps off, new
  uid): `git checkout` them and reimport.
