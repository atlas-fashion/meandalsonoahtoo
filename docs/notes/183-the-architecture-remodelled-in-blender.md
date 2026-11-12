## 183. The architecture remodelled in Blender; scoutposts smaller, with an upstairs (2026-11-12)

The user: "remodel every piece of architecture in the dungeon using blender. Keep
the dark medieval looking old broken down feel ... many many different kinds of
broken stones, archways, gates, wooden architexture pieces, fantasy looking roots
... based on soulslike visuals ... very realistic and stylized, while being able
to run properly on my pc. There should be no gaps or weird unrealistic spots",
and then "scoutposts should be smaller than they are now, with an upstairs".

Supersedes, for the pieces it replaces, note 27's Tripo stone (the kit and its
code path stay: `-- --tripo-kit` runs the game on it for an A/B) and note 181's
balconies in the scoutposts (the big-hall code stays for a room of half 2).

### Readings chosen
- **"Every piece of architecture" is the stone the level is built from**: walls,
  arches, vaults, pillars and pilasters, floors, the dead ends' lunette, the
  door's stone arch, the big piers' face, and the corridor's timber and rubble.
  Rooms that stack those pieces (the surgery's walls, the morgue's and
  scoutposts' piers, the prisons' side walls) change with them.
- **Kept as they were**: what the user had made from his own photos or approved
  since (the cell kit's gates and furniture, the scoutposts' balcony kit, the
  roots and their gold, the crates and barrels), and the Tripo pieces the new
  kit has no piece for yet -- the prison's dome, frieze, generator and gates,
  the burial walls and slabs, the wooden door's leaf, the exits' door, carts,
  the manhole cover, `torch_mount`. Those are the next pass.
- **"Fantasy roots"** are note 176's: they measure the kit's own surfaces
  (`ruin_dressing.gd` reliefs of `wall`, `pillar`, `arch`), so they grow on the
  new stone unchanged.
- **Same sizes on purpose.** Every piece keeps the Tripo piece's name, frame and
  measures, so collision (boxes), doors, torches, cages, cells, skylights and
  manholes needed no change.

### The kit (tools/build_dungeon_kit.py -> models/dungeon/dungeon_kit.glb)
32 pieces, 63,577 triangles in all, 2.9 MB, no textures in the file.

**How a piece is made.** Every stone is its own shell -- a face on a grid, a
worn bevel round it going back into the joint -- laid on a SURFACE in that
surface's own metres (`Plane`, `Barrel`, `Intrados` soffit and ring, `Polar`,
`Drum`), in courses with broken joints (`courses`, `lay`). Each stone takes its
own patch of one tiling texture (turned, flipped, shifted), its own shade in
the vertex colour, stands a few millimetres proud of or behind its neighbours,
and has its corners chipped at random. Behind every stone a dark backing, at
ONE depth for the whole surface, closes the joint. `open=` marks an arris: the
bevel there is half a chamfer met by the other face's half, not darkened.

| piece | what | triangles |
|---|---|---|
| wall, wall_b, wall_c | three coursings, a base course 4.5 cm proud | 1,834-1,964 |
| wall_broken, wall_broken_b | stones fallen out: the rubble core behind, the hole lined | 2,272-2,288 |
| wall_cage + cage_door | a stone shelf on corbels, an iron cage on it; its grille the gate | 2,524 + 356 |
| wall_top | the lunette, coursed up under the barrel | 970 |
| pillar, pillar_torch | plinth, shaft, necking, capital; the torch in an iron ring on a bracket | 1,130 / 1,809 |
| arch, arch_b | jamb quoins, an impost, 15 (13) voussoirs and a keystone, spandrels both faces | 6,476 / 6,788 |
| door_arch | the wooden door's pointed arch: two halves meeting on a plumb joint | 3,976 |
| vault_straight, vault_b, vault_sky | a POINTED barrel (two arcs, 2.1 m rise on 1.9), an impost band, a ridge rib; the skylight's hole cut stone by stone | 2,214-2,580 |
| vault_corner, _tee, _cross | the barrels cut on the cell's diagonals, a moulded rib under every groin, a carved boss where they cross | 3,101-4,281 |
| floor, floor_b, floor_c, floor_notch | flagstones split from the tile; c with a flag broken and settled; the manhole's half ring of curb stones and shaft lip | 238-686 |
| pier_face | 2.2 x 7.9 m, banded where the vault springs | 1,918 |
| wood_support, wood_planks | shoring against a wall; a heap of boards | 950 / 568 |
| tie_beam | a tie beam on stone corbels, king post and struts under the vault, iron straps, a hook | 664 |
| portcullis_up | a portcullis hauled up into an arch: bars and spikes, nothing under 3.13 m | 2,160 |
| rubble_a, _b, _c | fallen stone (hulls of points) with dressed blocks among it | 382-746 |
| column_broken | a base, three drums, a ragged top, the next drum lying by it | 1,358 |

**Three materials for all of it** (tools/dungeon_kit_textures.py, numpy only, no
bake): `dk_stone` 2048 for 2 m, `dk_wood` 1024 x 2048 with the grain along v,
`dk_iron` 1024 with metal in the ORM's blue. Every map tiles: the noise is
made in frequency space, the cell noise measures round the edges. Height first
(lumps, dressing marks, hewn facets, pick pits, spalls, cracks along a noise's
zero line); the normal is its slope, the occlusion its hollows; damp patches
are dark and glossy. brick_level.gd `dk_material` builds the three (plus
`floor`: the stone again at 0.78 of its roughness, the material damp.gd
switches specular on) and gives them to the surfaces by NAME.

### In the game (scripts/brick_level.gd)
- `_load_dungeon_kit`: the kit's pieces replace the Tripo kit's of the same name
  in `meshes()`; `is_dk(piece)`; `standalone()` hands a kit piece back as it is
  (its vertex colours are real). `torch_head()` for the pilaster's torch.
- **Variants** (`_variant`): a 4 x 4 cell chunk lays ONE of the two floors, one
  arch, one barrel and two of the three walls; the next chunk another set.
  `floor_c` one tile in 7 in every other chunk. `wall_broken` / `_b` on one
  plain corridor wall in 7 (never a room, a dead end or a cage wall), recorded
  as the Built's "broken_walls".
- **Clutter** (`place_clutter`): a heap of rubble under every broken wall;
  `column_broken` and rubble heaps on their own rolls; all boxed, all in the
  spots maze.gd marks solid. `_place_overhead`: `tie_beam` over one plain
  straight in 6 (never under a skylight or by a torch), `portcullis_up` in one
  arch in 9 off a plain straight (never a door's, a dead end's or a room's, and
  not arch after arch). Default seed: 26 + 24 + 5 rubble, 7 columns, 18 tie
  beams, 23 portcullises, 64 broken walls.
- **Shadows**: variants cast as the piece they are a variant of (`SHADOW_AS`),
  so the 2 x 2 cell shadow blocks are as many as before (2,916).

### Scoutposts: 3 x 3 cells, an upper floor
- **Shrunk in place** (module_level `_shrink_room`, `SCOUTPOST_HALF` 1): the
  carve still cuts a 5 x 5 block, so the rest of the maze is the maze it was.
  The room keeps the middle 3 x 3 (18 m square); of the ring round it only what
  leads from each old way in to the new hall is kept, as plain corridor --
  straight in, or from a corner along the wall and then in; the rest is rock.
  The room's "entrances" become the new hall's. The maze is 1,155 cells.
- **The upstairs** (scoutpost.gd `_loft`, a room of half 1): a timber floor
  `LOFT_DEPTH` 4.3 m deep at `DECK_Y` 2.15 along one wall with no way in (the
  back wall if it can, one whose corners have no way in beside them), from the
  side wall to the head of the stair -- 12.3 m where that corner has no way
  in -- built of
  the balcony kit's own pieces: its deck bays in two rows stretched to fit,
  posts and knee braces under the front, the railing along the front and across
  the stair's end, the same stair and ramp. Its front stops 15 cm short of the
  two stone piers.
- Up there: the chest against the wall (`_place_chest`), a crate or two, three
  of the loot (the potion, coins, a small potion), rags over the rail, a torch
  at 3.7 m. Under it: the stores. The winch moves to another wall when it can;
  the heavy root wall is never the upstairs wall.
- Smaller room, less in it: 4 slim piers, a torch a wall (4), 2 lanterns (none
  over or across from the upstairs), the fire basket and the cart or the pile
  in the two corners away from it (`_dress_small_floor`), one grate.

### Measured
Throwaway windowed harnesses in the real level, default seed, 0 failures:
- **Walked**: 1,155 of 1,155 cells reached from the start; no opening onto
  nothing or onto a closed side.
- **Scoutposts**: 8, each half 1, 2 ways in both joined to the maze, 2 gates, an
  upper floor, a chest on it (y 2.15), a winch, 7-8 loot. In three of them,
  holding forward from the stair's foot reaches the deck in 1.4-1.9 s and walks
  8.1 m along it; standing in the middle drops the gates.
- **No void**: magenta behind the level, flat light, 36 cells x 12 views: 0
  void pixels. The same with a wall variant left out: 1,559,865 -- the test
  notices. (With the dark lid and skirts left out, 6,351, all at the surgery's
  doorway: the lid and skirts stay.) The first version of this test passed with
  every wall removed: the void comes out dim purple through the game's
  exposure, not (255, 0, 255).
- In Blender (`--preview`), the kit alone, assembled as the game lays it, shows
  no magenta from four views -- after the backing was put at one depth.

Frame time, 3440x1440, the user's saved settings, the editor open behind, new
and Tripo (`-- --tripo-kit`) alternated back to back (new / old / new):

```
station            fps new      fps old   gpu ms new     gpu ms old   triangles new / old
spawn corridor     70.4 / 71.9   68.2     10.65 / 10.69    11.32      2.7M / 5.8M
boss room centre   53.4 / 49.5   53.8     10.97 / 10.90    13.15      3.8M / 8.9M
outer maze         75.5 / 77.1   75.6      4.81 /  4.77     5.73      1.75M / 3.8M
chest room         41.1 / 42.9   38.3     20.73 / 20.71    23.23      6.6M / 14.1M
surgery            44.2 / 41.8   39.4     20.05 / 20.08    23.70      7.0M / 12.5M
ruins ossuary      66.2 / 60.9   62.4     11.85 / 11.35    12.20      0.9M / 4.3M
OVERALL            59.6 / 57.6   58.6     video memory 1,770 MB / 1,796 MB
```

The same in the corridors (they are CPU-bound), 2-3.5 ms less GPU time in the
rooms, half the triangles or fewer. Video memory barely moves: the Tripo kit's
21 texture sets still load for the pieces it keeps.

### Traps
- **Per-stone backing at each stone's own depth leaves hairlines of void** at
  glancing angles between neighbours set back differently. One depth (`bed`)
  for the whole surface.
- **A stone tucked wholly under something** (a spandrel stone under the arch's
  ring, a flag in the manhole) has every vertex moved onto the tucking curve,
  and its faces then span whatever it was tucked round: the manhole came out
  roofed over. Faces whose every vertex moved are dropped.
- **A straight-sided pointed head** has no single normal at its apex: built as
  ONE curve its ring stones fanned across each other. Two halves, each ending
  on a plumb joint (`Intrados(n0, n1)`).
- **Every variant is a MultiMesh per chunk, drawn twice.** With all variants in
  every chunk the ossuary drew 1,600 calls against 1,150 and ran 53 fps against
  63. And **the new floor variants cast shadows** until they were named in
  `NO_SHADOW`: 1,266 more shadow blocks in every torch's pass.
- `out.torch_cells` is empty while `BrickLevel.build` runs (torches are placed
  later): what must keep clear of a torch goes in `place_clutter`.
- A round drum laid as five patches is a pentagon: `grid` 0.1 and three patches.
- Blender: `bmesh.ops.convex_hull` returns the same vertex in "geom_interior"
  and "geom_unused"; `bmesh.ops.delete` refuses a list with repeats.
- The editor was open through all of this and the headless imports still ran.
