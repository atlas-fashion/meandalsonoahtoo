## 13. Prison cells in the corridors; yellow skeleton eyes (2026-10-08)

- **Cell rows** (`scripts/cell_row.gd`, placed by `maze._place_cell_rows` before
  the hiding places and the bake): `cell_row_count` 10 stone cell blocks, spread
  over the free side walls of corridor straights (not niche walls, torch walls,
  door cells, the spawn, under the boss hall). Each: 3 cells (1.15 m wide)
  between 0.5 m pillars under a lintel and capping slab, the front 1.17 m out
  from the measured wall face (`CELL_ROW_WALL` 1.90), everything that meets the
  wall reaching `BACK_IN` 0.3 m into it (the stone's face varies by ~15 cm along
  a straight). Each cell shut by iron BARS or (`cell_door_share` 0.45) a banded
  plank DOOR with a small barred window at 1.62-1.96 m; `cell_prisoner_share` 0.5
  hold a prisoner: the enemy skeleton model at `PRISONER_SCALE` 0.88 in its idle,
  facing out -- behind a door centred and square to the window. At 0.94 the
  window showed only his ribs. Decoration only: one collision box (1+2), grid
  tiles marked WALL. Hiding places keep out of straights with a row
  (`_cell_row_cells`): a coffin opposite a block would leave too narrow a passage.
  Measured: 10 rows, narrowest passage left 2.60 m, nav path along each straight
  past its row with no detour, reachability still 100%.
- **Yellow eyes on every skeleton** (`scripts/skeleton_eyes.gd`, `attach(root)`,
  from `enemy._ready`, and on the prisoners): two unshaded emissive balls with
  additive halos on a BoneAttachment3D on the `head` bone. The sockets are
  MEASURED once per mesh: the vertices skinned mainly to `head` are the skull
  (564 verts, mesh space = skeleton space on this model, face toward +Z, box
  0.22 x 0.29 x 0.31 m); sockets at 45% up, +-22% across, 3.5 cm in from the
  front, carried into bone space through the skin's bind pose. Hidden on death
  (`enemy._die`). The cage skulls keep their red eyes. The boss has none: its
  scene is a placeholder MeshInstance3D with no rig.- **The corridor cell rows were REMOVED** at the user's request (2026-10-08):
  `scripts/cell_row.gd` deleted, `maze._place_cell_rows` and the hiding places'
  `_cell_row_cells` exclusion gone. The note above describes code that no longer
  exists. The yellow skeleton eyes stay.

