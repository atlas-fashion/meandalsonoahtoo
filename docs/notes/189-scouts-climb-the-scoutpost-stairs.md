## 189. Scouts climb the scoutpost stairs (2026-11-16)

The user, on note 187's open question (enemies could not path up the stair, so
the upper floor was out of the scouts' reach): "let the scouts go upstairs".

### What was built
- **scoutpost.gd `_stair_link`**, called from `_build_compact`: a two-way
  `NavigationLink3D` ("StairLink") from 0.9 m before the stair's first step
  (`_stairs[0]["foot"]`) to 0.8 m past its head on the upper floor
  (`_stairs[0]["top"]`). The stair is 1.1 m wide and the navmesh's agents are
  0.5 m in radius, so the bake leaves nothing on it; the link joins the two
  floors' polygons (the map's link connection radius, 1 m by default), and
  whatever paths over it walks up the ramp's collision as the player does. Only
  the 2 x 2 posts have one (`_loft` and `_gallery` are not live).
- **The floor by the stair's foot kept clear** (`_dress_compact`,
  `STAIR_FOOT_CLEAR` 3.2, `_stair_foot`): a wall cell whose middle is nearer than
  that to the link's start gets no crates, barrels, candles, shackles or rubble
  (roots on the wall still grow). In the first run the link joined nothing below
  in posts 2 and 3 -- the path up ended on the ground floor 0.85 and 1.07 m off --
  and with that cell clear it joins in all 8. That run did not measure the
  link's ends, so that the props were the cause is inferred, not shown.
- **scout.gd**:
  - `OTHER_FLOOR` 1.5: more than that apart in height, `_chase` takes the path
    (`_path_dir`) at `HUNT_SPEED` and does not evade, flank or circle. `gap` is
    flat, so from under the player it read as close and the scout circled below.
  - `_on_link_reached` (the agent's `link_reached`): on a link it heads for the
    far end (`_link_exit`) until within 0.45 m flat and 0.8 m in height, or
    `LINK_COMMIT` 4.0 s, before it asks for a path again. Without it every scout
    stuck partway up or down: asked from the stair, which has no navmesh, the
    path began at the nearest floor, back at the link's start, and it turned
    round there.
- Other enemies that come into a post (note 182 `_fill_halls`) use the same
  navmesh, link included, but not the scout's `_on_link_reached`: by the first
  run they would stick on the stair. Not done; nothing but scouts was tested.

### Measured
Throwaway harness, windowed on a hidden desktop (tools/hidden_run.ps1), default
seed, `--no-enemies` (the posts' scouts still spawn; all but one freed). The scout
was kept hunting by setting `_seen_until` every tick, so sight is not what was
tested -- only the climb.
- Navmesh paths in all 8 posts: from the stair's foot to a spot across the upper
  floor ends up there (0-0.73 m off), and back down ends at the foot. The link's
  start is 0.45 m from the ground floor's navmesh (straight above it), its end
  0.30 m from the upper floor's.
- One scout, every post: on the ground floor with the player across the upper
  floor, up to within 3 m of them in 3.17-5.15 s, 1-3 moves started at them up
  there; on the upper floor with the player below, down in 2.58-5.60 s, 1-2 moves.
  From straight under the player (0 m apart flat), up to them in 3.63 and
  4.67 s (posts 0 and 2).
- **Re-break**: the first run, before `_on_link_reached` and the clear floor:
  every up and down failed (16 of 16, scouts stopped 0.24-2.13 m up the stair) and
  both "straight under" cases. In the passing run, with post 0's link switched
  off (`enabled = false`), the scout does not get up in 15 s.
- The log's only warning is the carve's old "rooms only fit 4 cells apart".

### Not done, not known
- Frame time not measured (the PC was in use).
- Whether a scout follows a player up who is out of its sight (it searches where
  it last saw them; `_begin_search` goes to the nearest navmesh point to that
  spot, which may now be upstairs).
- The props are now dealt on a different stream of the dressing's random numbers
  in each post (a cell skipped draws none), so the dressing differs from note
  187's screenshots; it was not looked at again.

### Traps
- A navigation link is not enough for a steering agent that re-asks for a path
  every `repath_interval`: from a spot with no navmesh under it the path starts
  at the nearest polygon, which on a stair is behind it. Commit to the link's
  exit (`link_reached`) or it turns round on the stair.
