## 187. A scoutpost's door stays open once wound; rising at its beacon shuts it again (2026-11-14)

The user: once the wheel is completed the door stays open; it closes again only
when the player respawns at that scoutpost's beacon, so they must reopen it.
And: verify the stairs in game by actually walking the player up them.

Supersedes the lock rules of notes 180-182 where they differ: note 180's "wound
up they stay up until everyone has left; then armed again", and note 182's
"cleared, it never shuts again" now has one exception (rising at its beacon).

### What changed (scoutpost.gd, maze.gd)
- **`wound`** (scoutpost.gd): set in `_unlock` when a hand was on the wheel as the
  gates reached the top -- not when a shut post with nobody alive inside opens
  itself (`EMPTY_OPEN`, note 180), so dying in a post and rising elsewhere does
  not count as winding it. A wound post is never armed again on walking in
  (`_armed = not (cleared or wound)`). Before, a post wound without being
  `cleared` (its guard list empty: the player was inside when the population
  was rolled, or no scouts were spawned) shut again on every visit.
- **`shut_in()`** (scoutpost.gd): clears `wound` and arms the post; the usual
  `_process` drop follows, the player being inside (0.35 s, then the 0.32 s
  crash, during the respawn's black). A post already locked stays locked.
  The wheel must be wound again; on a cleared post it turns at once (its scouts
  stay dead: `_spawn_scoutpost_scouts` gives a cleared post none, nor a post a
  player is standing in).
- **maze.gd `_shut_risen_in(player)`**, from `_on_player_respawned` after the
  player is placed (each co-op player too): every post the risen player is
  `_inside` gets `shut_in`. Rising inside a post can only be at its beacon (the
  beacon stands in the middle, the rise point 1.6 m in front of it).
- **Saved**: maze.gd `save_state` "scoutposts_wound" (indices, as
  "scoutposts_cleared"), `restore_world` sets `wound`. Loading a save is not a
  respawn: a wound post loaded into stays open.

### Measured
Throwaway windowed harness in the real level (default seed, `--no-enemies`, real
E and forward input; the post's scouts freed and its guard list emptied before
each wind, so `wound` alone was tested, not `cleared`), 0 failures:
- the first post open from outside; shut 1.2 s after walking in; held E winds it
  to 1.00 and sets `wound`;
- out and back in: stays open; walking about inside: stays open;
- **re-break**: `wound` set false by hand and walked in again: it shuts -- the
  test notices;
- died and risen at the start beacon: the post still open;
- its beacon claimed and made active, died: risen inside it (local
  (0, 0.17, 1.6)), `wound` false, shut 1.2 s later, stays shut with nobody
  winding; wound again (after the 0.38 s getting up) and open on coming back;
- `cleared` set, risen there again: shut, and the wheel winds at once;
- `save_state()` carries "scoutposts_wound": [0].
- **The stairs, all 8 posts**: holding forward from each stair's foot reaches
  the upper floor (2.12 m, then standing at 2.15) in 1.30 s, then walks
  8.5-8.8 m along it to its far end (the seventh post's upper floor is 5.2 m
  from the stair's head to its end, walked 3.9 m to within 0.6 m of it).
- Clean windowed `--quit-after 2400` run: no errors; the one warning is the
  carve's old "rooms only fit 4 cells apart".

### Traps
- `--no-enemies` does not stop the scoutposts' scouts: 3 were in the first post,
  and with them alive the wheel will not turn ("Kill the scouts first"), so the
  first harness run "failed" every wind. Free them, or they are guards.
- After a respawn the player gets up (`in_cutscene`, 0.4-0.9 s here): the wheel's
  prompt is hidden until then, and E held before it does nothing.

## 187, second part. Scoutposts of 2 x 2 cells, the upstairs over the whole room (2026-11-15)

The same message of the user's: "Make scoutposts smaller, and have the upstairs
span the whole room, with a hole for the stairs. Make sure the stairs are
accesable by the player; last time you made the stairs lead into a wall."

Supersedes note 183's "Scoutposts: 3 x 3 cells, an upper floor" (`_shrink_room`,
`_loft` and the big hall's code stay: `SCOUTPOST_TWO := false` in module_level.gd
puts the 3 x 3 back). What "into a wall" was: note 183's stair began against the
side wall, its first step touching it, so it could only be stepped onto from the
side -- and note 187's stair test above started the player ON the stair, so it
passed.

### What was built
- **module_level.gd `_shrink_room_two`** (`SCOUTPOST_TWO`): of the carve's 5 x 5
  block the room keeps its centre cell and the three of one quadrant
  (`room["even"]`, the quadrant needing the shortest passages), 12 m square, 9.8 m
  inside. Each old way in is led on by the shortest walk through the old block
  (`_stub_path`), kept as plain corridor; the rest is rock. `room["half"]` stays 1;
  `Built.room_world` is the corner the four cells share, `room_lo` / `room_hi` its
  cells (`_enclose_hall`, explore_map.gd `_reveal_room` and `_paint_room_floor`,
  maze.gd `is_in_scoutpost` read those). Nothing else that reads `room["half"]`
  sees a scoutpost (`chest_rooms()` is kind "chest" only).
- **scoutpost.gd `_build_compact`** (a room with `"even"`): one whole pier in the
  middle; a timber floor over all of the room at `FLOOR_Y` 2.4 (2.28 m clear
  under it), the kit's deck bays stretched onto a grid whose lines run along
  every opening's edge (`_upper_floor`, `_breaks`), a slab of collision under
  each; the stair up one wall, its first step `FOOT_CLEAR` 2.2 m from the side
  wall, the kit's stair scaled 2.4 / 2.15, the floor going on 3.8 m past its
  head; an opening over the stair (`STAIR_HOLE` 1.55 m out from the wall) railed
  along its side and across its foot; the beacon (3.3 m tall) in a railed well
  through the floor (`WELL_HALF` 1.25, at `BEACON_OFF` 2.55 from the middle both
  ways, on the side away from the stair), turned to face along the room
  (`beacon_yaw`, maze.gd `_add_beacon`) so the risen stand clear of the pier; a
  railing across every archway up there. Below: the winch cut down to go under
  the floor (`WINCH_UNDER` 0.85), stores, the fire basket, a grate, the scouts
  (`guard_spots`, maze.gd `_spawn_scoutpost_scouts`) in the three quarters the
  beacon is not in. Up there: the chest against a wall, crates, most of the loot.
- **Where the stair and the beacon go** (`_build_compact`, the first loop): the
  stair's wall, the way it rises and the beacon's side are chosen together by
  cost -- a way in under the stair 1000, one beside its head on the same wall 50,
  one opening onto the beacon's quarter 20, one onto the stair's foot 5.
- Torches: on the pilasters, over the floor on the stair's wall and the one
  across, under it on the other two at `LOW_TORCH_Y` 1.25.

### Measured
Throwaway harnesses, default seed, `--no-enemies`, the posts' scouts freed.
The walk and door test windowed on a hidden desktop (tools/hidden_run.ps1), the
navmesh maps headless.
- **Built**: 8 posts, each 4 hall cells and 9.8 m inside, 15 ways in between
  them. The maze is 1,120 cells (1,155 with the 3 x 3), all reached from the
  start, no opening onto nothing or onto a closed side.
- **A fault the first layout had, found by the walk**: the beacon went in
  whichever far quarter had the fewest ways in near it, and in 3 posts of 8 a
  doorway opened straight onto it. Its well's posts and the beacon close that
  quarter to the navmesh (the gaps are under the agents' 1 m), so the path from
  that doorway to the stair's foot was 130.4 m and 139.7 m, out and round the
  maze, and the walk from it ended 19-40 m short. With the cost above: every one
  of the 15 doorways 6.1-11.3 m from the foot by the navmesh, and all 15 walked.
- **The stairs, all 8 posts**: walked from 2 m inside each way in to 0.9 m
  before the first step (0.01-0.08 m short); from there, forward held, onto the
  upper floor in 2.00 s (standing at 2.40 m); on 2.6 m past the head; across the
  room up there (0.03-0.74 m short of a spot on the far side); back to the head
  and down the stair to the foot (at 0.00 m).
- **The door, first post**: open from outside; shut on walking in; the wheel
  wound under the upper floor to 1.00 (`wound`); open on coming back; risen at
  its beacon on the ground floor (local (-2.55, 0.17, -0.95)) and shut; free to
  move 0.82 s after 1.2 s of checks, walked 1.60 m; wound again. 0 failures,
  73 checks, and the same again on the finished code (after the torches were
  lowered). Its log's only errors are the 3 from the test's own path query to
  the upper floor (below); its one warning the carve's old "rooms only fit 4
  cells apart".
- **Seen**: screenshots from the eyes, 13 looked at in post 0 and 3 in post 2
  (the other 6 posts not looked at): the floor across the room under the vault,
  the pier through it, the well with the beacon in it, the stair's opening, the
  stair from the room, the winch under the floor.

### Not done, and what is not known
- **Enemies cannot follow upstairs.** The stair is 1.1 m wide and the navmesh's
  agents are 0.5 m in radius, so the bake leaves nothing on it; no
  NavigationLink3D exists anywhere in scripts/. A path from the foot to the
  upper floor ends on the ground floor in all 8 posts (0-9.5 m from under the
  goal), and in 3 of them the query logs the engine's "It's not expect to not
  find the most reachable polygons". By the code the same held for note 181's
  balconies and note 183's upstairs (the same stair); neither was run to check.
  With the floor over the whole room this is now a place to stand out of the
  scouts' reach. Left for the user to decide.
- **Frame time not measured**: other threads' Godot runs and the user's own game
  were on the GPU throughout. Each post now has 46-54 deck bays, each a
  MeshInstance3D of its own.
- **The void test of note 183 was not run again.** The screenshots (2 posts) show
  no hole.
- **The torches under the floor**: at 1.5 m the flame was in the boards. By the
  scene's measures (a 0.72 m flame quad at +0.37, the lowest beam at 2.11 m) at
  1.25 it ends about 0.13 m under them if the quad is centred there; in the one
  frame taken its tip still comes close. A caged lantern would suit a timber
  ceiling better.
- **The same engine error from `sewer_lizard.gd` `_wander`** in 2 runs of 7 (2
  lines each), none in the others. sewer_lizard.gd, sewer.gd and enemy.gd are
  unchanged; whether the new layout has a part in it is not known.
- **Not tried with a save made before this**: the corridors round each post
  changed with the room.

### Traps
- **A navmesh path's waypoints followed flat do not go down a stair**: the test's
  "back down" walked across the upper floor to above the goal and stopped there.
  Steer at the stair's head and then its foot.
- **The navmesh is baked from static colliders** (maze.tscn
  `geometry_parsed_geometry_type` 1), so the walk test runs `--headless` too.
- `_side_of` is a static of module_level.gd, not of its `Built`; a script error
  in a harness's coroutine stops it without quitting -- give it a watchdog timer.
- Under FOV 100 with the view pitched down, the well's corner newels at the
  frame's edges look like great leaning slabs. They are 0.22 m posts
  (tools/build_scoutpost_kit.py `build_post`).
