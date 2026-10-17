## 28. Darker, Tripo carts / wood / doors, skull cages in the Tripo cage (2026-10-10)

- **Darker**: maze `module_torch_density` 1.0 -> 0.5, `module_ambient` 1.0 ->
  0.35, `module_torch_energy` 2.8 -> 2.2, and a brick door keeps one torch pair
  (its junction side) instead of two. Measured mean luminance at 12 fixed
  corridor spots: 0.0657 -> 0.0324 (-51%). Torches 643 -> 414 (128 at doors).
  Bench (RTX 3060, 3440x1440, enemies on): 91.1 fps, worst p99 19.56 ms,
  1002 MB (86.8 / 22.22 before).
- **New Tripo pieces** (text prompts, 40 credits each, 480 left), all in
  `brick_kit.glb` via `build_brick_kit.py`: `cart_body` + `cart_wheels` (a
  two-wheeled hand cart, exported at the convoy's size, wheels split off so
  they spin; axle at z 0.028, y 0.375) and `cart_lid` (the top boards of the
  crate Tripo returned for "a lid"); `wood_support` (snapped timber frame,
  2.4 m, against a wall), `wood_planks` (pile, 1.6 m), `wood_crate` (0.97 m).
- **Carts**: convoy.gd uses the kit cart at 1:1; hiding_spot.gd at
  `CART_SCALE` 1.368, so its numbers changed (tray 1.74 x 1.09, rim 1.3, base
  from -1.0 to +1.6) and the maze stands it `HIDE_FROM_CENTRE_BRICK` 1.05 off
  the corridor's middle (its wheels reach 0.82 m out). Both fall back to the
  primitive barrow without the kit.
- **Broken wood** (`brick_level.place_clutter`, from maze `_place_clutter`
  after the hiding carts, before the bake): straights only, not door cells, the
  spawn and its neighbours, hiding-cart cells, torch walls or cage walls; one
  roll per straight -- support 1 in 7, planks, crate. Support posts and the
  crate are solid (walls layer) and marked WALL in the grid; planks are not.
  ~24 supports, ~21 plank piles, ~14 crates.
- **Doors are the Tripo arched door**: `door_frame` + `door_leaf`, cut by
  `split_door` (the leaf ray-mapped from the front: 1.94 m wide, pointed head
  to 4.2 m, 0.16-1.0 m behind the stone face). `module_level._build_brick_door`
  hangs the node at the LEAF (`BRICK_DOOR_DEPTH` 2.38 + `BRICK_DOOR_LEAF` 0.58
  = on the boundary) so a kick from either side lands on it; one leaf
  ("LeafL"), jambs out to 1.8 m. The spawn stands 0.75 m forward of the dead
  end's middle to keep the door in reach.
- **Bone cages are the Tripo iron cage**: the niche cell's wall is `wall_cage`
  (no other cage walls any more), its gate cut free (`cage_door`, faces in front
  of y -0.46) and hung as bone_cage.gd's "Door"; the skull and loot sit inside
  the cage (0.77 x 0.78 x 0.35 m, `_brick_cage`, `_fill_niche(mid_override)`).
- Trap hit: the level is built before it is in the tree -- `global_position`
  on a fresh node errors and leaves it at the origin (all 33 cages were there).
- Trap (again): every new kit export brings new extracted textures as
  `compress/mode=0`; patch the `.jpg.import` files to 2 and re-import.
- Verified in a harness: cage aimed at + E paid 8, gate swung -1.80 rad; spawn
  door kicked open; hid in a cart and climbed out; convoys run with the new
  cart; all three wood pieces placed; clean run and title run silent.

