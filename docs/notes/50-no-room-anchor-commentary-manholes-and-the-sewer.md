## 50. No room/anchor commentary; manholes and the sewer (2026-10-15)

- **Nothing is announced on entering a room or at an anchor.** The mine and the
  prison no longer announce on entry or alarm (`dungeon_room._raise_alarm` only
  alerts the enforcers), puzzle rooms do not announce their puzzle on sealing,
  and attuning / re-binding an anchor shows nothing. Result messages (a lock
  failing, the drills dying) stay.
- **Five manholes** (maze `manhole_count`), picked by
  `module_level._pick_manholes`: corridor straights only (not rooms, courts,
  halls, niche or skylight cells, nothing under the boss hall, >= 4 cells from
  the spawn), spread farthest-point. The hole is `MANHOLE_ALONG` 1.5 m along the
  corridor from the cell centre (`Built.manholes`: cell -> along, world).
  brick_level lays the kit's `floor_notch` tile (a flagstone with a half circle
  cut from its edge) for the two tiles round it, and NO bed: manhole.gd lays the
  bed in four pieces round the hole. Hiding carts, clutter and drips keep out of
  manhole cells.
- **The cover is Tripo's** (`manhole_cover`, geometry only, 10 credits), drawn in
  a dark rusted-iron material in the dungeon's browns, in an iron collar. E on
  it (crosshair on the collar): crouch, prise it up, drag it aside (~2.2 s).
  The floor collision runs whole under the hole, so an open hole has a
  `Blocker` cylinder (layer 1) or everyone would walk across thin air (measured:
  stopped 0.95 m from the centre). Covers stay open, saved as "manholes".
- **Climbing** (player.gd `begin_climb` / `climb_face` / `end_climb`,
  `climbing`): body collision off, physics early-out, the ladder's scene writes
  the position rung by rung (`manhole._climb`, `CLIMB_PACE` 0.62 s/m, a pull
  and a pause per 0.3 m rung, a sway per rung). DOWN: step over the hole,
  climb `DARK_STRETCH` 2.3 m while the HUD fades to black (`FADE_OUT` 1.1 s),
  wait for full black, cut to `LIGHT_STRETCH` 2.4 m above the sewer floor, and
  fade back in (`FADE_IN` 1.3 s) over that last stretch of ladder; step back off
  into the chamber. UP: the reverse; a cover still on is shoved off from below;
  out over the rim onto the flags beyond the ladder. ~4.4 s each way. Death
  mid-climb: `_respawn` clears `climbing`.
- **The sewer** (`scripts/sewer.gd`): 12 m down (`FLOOR_Y` -12), on the
  dungeon's own 6 m grid. Nodes = the 5 manhole cells; links = a minimum
  spanning tree + the one shortest extra link (a single loop), each an L along
  the grid; plus 3 short dead-end spurs. 165 cells against the maze's 1,112.
  Pipes: inner radius 2.2 m, axis 1.4 m up, flat walkway, a 0.8 x 0.35 m water
  channel with a dark glossy water strip (one merged mesh), round inlets in
  the walls, a ball at every bend/junction/end. A round chamber (r 3, 5 m high)
  at each manhole, centred `CHAMBER_SHIFT` 0.9 m back from the cell centre so
  the shaft rises at its wall and the ladder is against stone; its floor is
  whole (no channel under the ladder). Built as ONE CSG tree, baked
  (`bake_static_mesh` returns NULL until the CSG has been in the tree a frame:
  `_ready` awaits one), split into 24 m chunks (46), one trimesh collision on
  1|2|256. Brick is `tools/build_sewer_brick.py`, world triplanar. NOT under
  NavRegion: nothing walks down there, and the Remnant treats a player below
  y -4 as warded.
- **Light separation**: the dungeon floor is not a shadow caster, so the
  corridor torches and the moon lit the pipes 12 m below. The sewer draws on
  `sewer.VISUAL_LAYER` (1 << 15) and every other light leaves it out
  (maze `_wall_off_sewer`, run after the build AND each time the camera goes
  below -- the boss, mimic and chest lights are spawned later; measured 4 of
  them leaking before the second pass). Sewer torches (81, every 2nd straight,
  `_hang_torch` with `sewer` set) light only that layer and layer 1, and
  torch.gd `_rank` adds 1000 m to torches on the other level than the camera
  (split y -4), so the lit set is always the level you are on. The sewer's
  chunks, water and torches are hidden while the camera is above ground; the
  dungeon stays drawn below (the shafts look up into it).
- **Torch height in a pipe**: at 1.75 m up the flame sat in the curve of the
  vault and the pipe read black; at 1.0 m (wall 2.16 m out) it lights.
- **Its own map** (explore_map.gd `add_level`): a second level on the same grid,
  switched by height (`LEVEL_SPLIT_Y` -4) on the full map AND the minimap, with
  green walls and frames, "SEWERS" on the minimap and as the full map's title,
  ladders drawn as small squares (the one icon). Charted cells per level; a
  death forgets only the dungeon's (`snapshot` / `restore` always mean the
  dungeon); marks are per level ("level" on each). Saved as "map_levels".
- Tripo balance after this: 0.
- Measured (harness, 32/32 with the leak re-check): 5 manholes, 165 connected
  cells, floor under every cell, a capsule clear between every pair; cover
  lifted in 2.2 s, dragged 1.12 m; climb down 4.4 s, full black at y -2.4,
  black at the cut, 75 frames fading in between y -9.6 and -11.7, clear in the
  sewer, map on the sewer; climb up 4.5 s, out at y 0.00, 1.08 m from the hole,
  black at the cut, map back, sewer hidden; free to walk after; save lists the
  open cover and the sewer charting.
- Bench (RTX 3060, 3440x1440, editor closed), same layout with only the sewer
  build skipped: 69.5 fps / worst p99 29.17 / 1154 MB without, 68.6 / 34.22 /
  1157 with (a third run 65.4 / 30.26) -- noise; +20-40 draws.

