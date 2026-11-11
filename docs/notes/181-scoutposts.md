## 181. Scoutposts: scouts, loot, a balcony up a stair built in Blender (2026-11-11)

The user, of note 180's beacon halls: "The player should be able to find health
potions here scattered around, along with other loot. There should be a number
of scouts in these. Call these Scoutposts", "Use blender for models", "You should
make a little balcony in them, with stairs".

### Renamed
- `scripts/hall_room.gd` -> `scripts/scoutpost.gd` (nodes `Scoutpost%d_%d`, log
  `[scoutposts]`); maze.gd `module_scoutpost_rooms` (6), `_scoutposts`,
  `_scoutpost_rooms`, `_place_scoutposts`, `is_in_scoutpost`; room kind
  "scoutpost"; module_level `_make_scoutposts`, options "scoutposts" /
  "scoutpost_keep"; the bench station "scoutpost". The cells keep their `hall`
  flag (it is the enclosed-hall flag the morgue and the surgery share).

### Scouts (maze.gd `_spawn_scoutpost_scouts`, `_spawn_post_scout`)
`scoutpost_scouts` 3 scouts in each scoutpost nobody is standing in, at three of
the four spots 4.8 m round the beacon, with NO patrol (a patrolled scout roams
the corridors): enemy.gd's own wandering keeps each within `scoutpost_wander`
9 m of where it stood up. Replaces note 180's one rolled corridor encounter.
Measured: 3 scouts in each of the 6 after the build, still 3 inside the photo's
after 6 s.

### Loot (`scoutpost.gd` `_scatter_loot`, `LOOT`)
Per scoutpost: a health potion and a pile of coins up on a balcony, a small
potion on the photo's table (else the floor), another small potion, two more
coin piles (4-12) and a gold crystal on the floor 2.9 m out from the walls
(never a way in, the winch, a corner or under a stair), a robot rat one time in
four. item_drop.gd with "lying" (as the containment rooms' coins, note 126; it
rests on the deck: item_drop's LAND_MASK has 256). What is taken is saved:
maze.gd `save_state` "scoutpost_loot" (an array per scoutpost), `take_loot` on
restore.

### The balcony (`scoutpost.gd` `_gallery`, `models/scoutpost_kit.glb`)
Built in Blender by **`tools/build_scoutpost_kit.py`** (rebuild, never hand-edit;
`blender -b --python tools/build_scoutpost_kit.py`, then a Godot `--import`):
five pieces, 7,872 triangles, one baked atlas (albedo and normal 4096, ORM
2048), reusing build_cell_kit.py's geometry helpers, iron and stone (its `main()`
is now behind `if __name__ == "__main__"` so it imports):
- `deck_bay` (3.0 m: six planks with gaps, three joists, front beam, ledger,
  bolts and nails), `post` / `post_end` (a hewn post on a stone pad, knee braces,
  an iron band), `rail_bay`, `stair` (twelve risers over 3.4 m, closed strings,
  handrail on newels).
- Hewn timbers: a chamfered section swept along a path a little out of true; each
  vertex carries its timber's axis ("axis" attribute) so the procedural wood's
  grain, checks and streaks run along every piece whichever way it lies; worn
  pale arrises, grime in the joints, dust on what faces up.
- The textures' imports set to VRAM compressed, the normal map as a normal map
  (as cell_kit's): the first import came out lossless.

In the hall: deck bays end to end, stretched to fit (`BAY` 3.0), posts at the
joins (`post_end` mirrored at the far end), a railing along the front and across
the far end, the stair against the wall past the near end (`STAIR_Z` 0.3 out,
clear of the pilasters), rising to `DECK_Y` 2.15. The stair goes at an end whose
corner has no way in; if both have one, the deck shortens so the stair's foot
stays `STAIR_CLEAR` 10.3 m from the middle. Collision: the deck, the posts, the
railings, and a wedge (ConvexPolygonShape3D) under the treads -- 32 degrees,
walked straight up. No props in the cells the stair stands in (`_stair_cells`).
The old box-built gallery and its ladder are gone; the table and stool are still
boxes of the morgue's wood.

### Measured
Throwaway windowed harness (default seed, real input): every scoutpost has 7
loot and a balcony; holding forward from each stair's foot climbs to 2.15 m in
3.2 s; along each balcony 5 s of forward covers 13.4-16.4 m of 15.6-18.6 to its
far end (one slower: the living root tips on its wall lash, and a lash flinches,
note 145); walking onto a drop takes it. `--bench` (1280x720, High, the same
busy PC as note 180's run, every station ~5% slower): scoutpost 67.7 fps, 1% low
58.9, gpu 9.27 ms (note 180: 70.5 / 9.17); video memory +49 MB (the kit's atlas).

### Traps
- The scouts are in the group "scouts", not "enemies".
- `len` is a GDScript built-in: a local named so shadows it.
