## 177. The holding cells remodelled after the user's photo, in Blender with baked PBR (2026-11-05, landed 2026-11-11)

The user: "Make the prison room cells look like this photo. Use blender", then "I
want it photorealistic too", "use this image, not the description" and "The cells in
the maze and the starting cell should have no door at the back." The photo: a narrow vaulted
cell of dark wet stone blocks lit by one caged brass lantern hanging from the
ceiling; at the far end a riveted bronze door with a big gear wheel behind radial
straps between brass piston columns; heavy rusted chains and shackles on the left
wall over a stone bench with a frayed burlap cloth; a stone shelf on the right with
a metal bowl and cup; square flagstones, a drain grate, straw; rusty bars in front.

Supersedes note 153's and 154's dressing of the cells (the starting cell's plank bed,
the torus shackles, the corridor torch on a side wall, the prison's Tripo gate on
these cells). Placement, prisoners, beacons, gates opening and saving are unchanged.

### Readings chosen
- **The vault, the walls and the flagstones are the brick kit's own** dead end,
  already a barrel vault of brick (`brick_level.gd`); they were left alone. The kit
  dresses the cell inside them.
- **No door at the back**, so the photo's bronze gear door became the **gate's lock**:
  a riveted bronze case on the left leaf with a gear wheel behind six radial straps
  and a small brass gear, and on the right leaf a brass piston throwing the bolt.
  Under eye height (centre 1.08 m), as the old lock plate hid prisoners on the middle
  line at eye height (note 153). The beacon keeps the back wall to itself.
- **The lantern is the cell's light**, replacing the cell's torch on a side wall: the
  torch scene with its mount freed and its flame shrunk to a candle's, inside the
  lantern, so torch.gd keeps the flicker, the nearest-N ranking, the shadow and the
  view culling. Same energy as before (3.0 of a corridor torch; the starting cell
  2.2, was 0.6 on its wall, too dark in the middle).
- **The starting cell gets the same kit**: the bench in place of the plank bed, and it
  keeps the last prisoner's bones and the slop bucket.

### The kit (tools/build_cell_kit.py -> models/cell_kit.glb)
Modelled in Python in Blender from nothing, every piece in Godot's frame and turned
into Blender's per piece. One material for all, its maps baked in Cycles into one
atlas (albedo 4096, normal 4096, ORM 2048), from procedural trees per kind: rust
(iron showing at edges, rust in crevices and by noise, rough and barely metal where
rusted), bronze and brass (polished edges, verdigris in the crevices), wet stone
(dark, glossy 0.28-0.7 roughness, cracks along a voronoi), burlap (a woven pattern on
the cloth's own UVs, stains), pewter, straw, wax, pit black.

| piece | what | triangles |
|---|---|---|
| gate_l / gate_r | hinge and meeting stiles, an elliptical head rail, three pairs of flat rails, 9 square bars a leaf, rivets, hinge knuckles; the lock | 4,898 / 3,540 |
| lantern (+ glass) | dark iron: hook, cone cap, a cage of 6 bars and 2 hoops, a candle cup and stub | 1,448 |
| lantern_chain | 0.5 m of chain, repeated up to the vault by a ray at runtime | 1,200 |
| wall_chains | a heavy chain from 2.75 m to a big ring, and lower a short chain to a pair of open manacles, on riveted eye plates | 3,388 |
| bench | a chipped stone slab on a solid block (1.2 x 0.5, top 0.48) and its burlap, frayed by noise with a hole | 9,256 |
| shelf | a thick stone shelf (top 1.2 m) on one broad corbel, a dented pewter bowl, a tall banded tin cup | 2,348 |
| drain | a stone frame, a black pit, an iron grate | 1,344 |
| straw_tuft | 90 bent blades, both faces | 1,080 |

About 28.5k triangles a cell, against the old torus chains alone: 29 links of a default
`TorusMesh` at 4,096 each, 119k a cell.

### Placement (scripts/holding_cell.gd `_kit_dress`, `_hang_lantern`, `_hang_chain`)
- The bench (solid, as in the photo, not on legs) and the chains on the left wall at `BENCH_Z` -0.9, or the right when a
  wall torch's pilaster has the left; the shelf on the other wall at the same z,
  clear of a pilaster (|z| < 0.45). Wall pieces hang under a holder `SNAP_HEIGHT`
  1.2 m up the wall, snapped onto the real stone by jail_cell's `_snap_to_walls`
  (a ray along the floor line grazed it). Bench and shelf have box collision on layer
  1, children of their holders so they move with the snap.
- The drain at z 0.55; 7 straw tufts (MultiMesh) under the bench, in the corners and
  about, over the old 260 blades.
- The lantern's hook at y 2.95, z 1.0 (towards the gate, so it lights the prisoners'
  fronts); `_hang_chain` casts up on 2|256 and stacks chain runs to the vault.
- The lantern and the gate cast no shadow (the light is inside the cage; the gate's
  shadow hid the prisoners, note 153); bench, shelf and chains cast for it.

### Measured
Throwaway windowed harness, seed 20260918, its own Camera3D:
- 25 cells built (24 and the start), every one dressed; 57 prisoners, none within
  0.4 m of the bench's or the shelf's collision (layers 1|2|256|512);
- the gate leaves fill the arch as the Tripo pair did, the lock clear of the
  prisoners on the middle line (screenshots through the bars at 3.8 m);
- the lantern's chain reaches the vault in every cell.

Frame time at 3440x1440 (RTX 3060, the editor open), standing outside the bars and
inside by the gate of the starting cell and three maze cells, 3 s each, old cells
(HEAD's holding_cell.gd) against new, interleaved old / new / old / new:

```
old  80.0 fps  p99 16.22 ms      new  79.7 fps  p99 16.47 ms
old  80.7 fps  p99 15.96 ms      new  79.8 fps  p99 15.76 ms
final (VRAM-compressed maps, retuned to the photo): 80.0 fps, p99 16.16 ms
```

Within the run-to-run spread: no cost. The kit is about 28.5k triangles a cell
against 119k for the old torus chains; the atlas is three maps, VRAM compressed.

### Traps
- **The cloth solver let the burlap fall straight through the bench headless**, with
  collision modifiers on the bench and a wall (`collision.use` set, the view layer
  updated, frames stepped one by one): 2.3 m under the floor every run, and the
  export still "succeeded" with the cloth in the bench object. It is now draped by a
  formula (flat on the top, rolled over the front edge on a 3 cm radius, hanging in
  folds) and the build checks nothing of it is near the floor.
- **Even texel density gave the gate's bars 70% of the atlas**, leaving the bench and
  shelf a few hundred pixels: smooth, flat stone. `UV_SHARE` scales each piece's islands
  before packing (bars 0.55, bench and shelf 1.5).
- **The glTF textures import lossless** (`compress/mode=0`): three 4096/2048 maps at
  about 200 MB of video memory. Their `.import` files are set to VRAM compressed, the
  normal map as a normal map.
- **Pointiness reads every edge of a thin bar as worn**: the edge wear (iron showing,
  less rust) covered the bars whole and they read as polished brass under the lantern.
  The rust kind now takes only a little of it.
- A metal's diffuse colour bakes black: colour, roughness and metal are baked as
  emission.
- `ShaderNodeBsdfPrincipled` is the Python id (not `...PrincipledBSDF`).
- `find_child("HoldingCell*")` finds the `HoldingCells` container first, at the
  origin: a camera placed from it looks at the level from outside (black).
- The harness: another thread's half-written player.gd failed to parse, and the
  player's first-person arms follow whatever camera is current; screenshots use their
  own Camera3D with the player and its arms hidden.
