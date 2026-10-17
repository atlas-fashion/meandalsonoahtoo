## 7. The boss hall (2026-10-06)

The boss room is no longer the 7x7 cloister on the corridors' level. It is a
grand stair from ONE doorway up to a throne hall above the corridor roofs.

- **One doorway** (`module_maze._one_boss_entrance`, after `_finalise_rooms`):
  the entrance with the most maze behind it is kept, the rest walled up; any
  part of the maze that was only reachable THROUGH the room gets a corridor dug
  round it (`_dig_round`, BFS that never enters a room) or, if it is a 1-2 cell
  stub, is dropped. The whole block is then `court`, so no arcade modules,
  collision, torches or doors are built in it -- every placer already skips
  court cells. Reachability still 100%.
- **The plan** (`module_level.plan_boss_hall`, BEFORE skylights are picked):
  everything in the stair's frame (u across, v in from the doorway, y up).
  Stair 8 m wide, 2 x 18 steps of 0.194 on 0.42 m with a 3 m landing, to
  `HALL_FLOOR_Y` 7.0 (corridor roofs 5.1). The hall is the largest of
  40x48 .. 26x30 that stays inside the map and off every chest room's COURT
  (+2 m); chest ARCADES are roofed, so it may stand over them. Skylights are
  never picked under it (`under_boss_hall`). First version kept clear of the
  whole chest BLOCK +1.5 cells and found no room anywhere (fell back to 26x30).
- **The build** (`scripts/boss_hall.gd`, from maze `_build_module_level` under
  NavRegion so the navmesh bakes it): stair walls and facade, solid steps,
  RAMPS under them half a tread back from the noses (the capsule cannot climb
  19 cm steps; the navmesh needs a slope), a 1.4 m floor slab, 14 m walls with
  an 8 m arch, columns, a dais with ramp, placeholder throne, carpet, banners,
  braziers (a torch.tscn with the bracket hidden and the fire scaled up) and
  torches. Open to the sky; its sky lights are `HALL_SKY_ENERGY` 10 -- the
  courts' 22 blew the carpet and paving out to flat scarlet.
  Collision: floor/stairs/dais 1+2, walls/columns 2+9+10, throne 9 ONLY (the
  player cannot walk into it, the boss can sit in it), boss wall 11 across the
  arch inside the hall.
- **Gameplay**: `maze._boss_hall_gate` puts one portcullis (8 x 8 m, 15 bars)
  in the arch as `_gates[0]`; `_boss_court_gates` is only used without a hall.
  The boss spawns at `boss_spot` on the dais facing the doorway; his zone is the
  hall interior via the new `enemy.aggro_box_origin` (null = spawn point) and
  a non-zero `aggro_box_extents.y` now also limits height -- without it a
  player in a corridor UNDER the hall was "inside" the zone. `boss_throne_seat()`
  returns the "ThroneSeat" marker (-Z toward the doorway) for the boss work.
  `_close_boss_block_grid` marks the block's tiles WALL except the stair.
  The four old boss rock columns are not built with a hall.
- **Tripo**: the placeholders ("Throne", "Dais", "Columns", "Braziers",
  "Banners") are meant to be replaced by generated models; the API account had
  no credit (the web studio's 200 credits are a separate wallet). Swapping a
  mesh must not move the collision, the ramps, the seat or the boss spot.
- Measured in a harness: one doorway; walked up the stair on the real controls
  into the hall in 6.5 s (y 7.00); boss asleep with the player in a corridor
  under the hall, awake and the portcullis down once in it; nav path throne ->
  entrance ends 0.30 m from the goal. Bench (RTX 3060, 3440x1440, preset 1,
  scale 1.0, SSAO/glow on): spawn 7.32 ms, boss centre 8.72 (p99 11.11), boss
  edge 9.22, outer 3.38, chest 8.61; OVERALL 154.4 fps, 1176 MB. (Not
  comparable with the P620/Low figures above.)
- `tools/tripo.ps1` now reads the User-scope key FIRST: after `setx`, every
  running process still had the old key in its environment and kept billing
  the old account.

