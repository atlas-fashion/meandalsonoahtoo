## 177. Roots out of the masonry, twice as many; beetles, more rats; burial walls (2026-11-11)

The user, after note 176: the environment still does not please; the walls
should be different and unique, the roots part of the wall, more of them, the
dungeon crawling with life and interesting to explore. (Photoreal wall pieces
from the reference sheet wait on generation: the Tripo account had 0 credits,
and Higgsfield needs the user signed in in the built-in browser.)

- **Roots out of the stone** (`ruin_roots.burst_strands`, ruin_dressing
  `_wall_roots`): on every wall with 4+ roots, a quarter as many again (at
  least one) start MID-WALL (0.9-2.7 m), 0.09-0.16 m thick, their first two
  points pushed back into the brick (1.6 / 0.8 radii) and the first ring
  swollen 1.35x, so each swells out of the masonry; a shattered-brick decal
  (`textures/surgery_fx_crack.png`, 0.5-1.2 m, faded out past 30 m) where it
  breaks through (`_crack`). 608 on the fixed seed.
- **Twice the roots**: the overgrowth's walls 11-17 strands (variant 1 6-10),
  hanging 7-14 (14-24); tips alive in 85% / 95% of its cells, a second in 50 /
  60% of its straights; roots on 34% of every other district's cells (was
  13%), 4-8 strands, a living tip in 45% of those. 9,088 strands (was 4,140),
  89 living tips (50). The gold a little lower (`vein_energy` 1.4 -> 1.05), it
  covers so much more.
- **Hanging roots sway** (root_bark.gdshader `vertex`): vertex colour b marks a
  free-hanging strand (`Strand.sway`), moved up to 4.5 cm at its end, each on
  its own beat.
- **Beetles** (`scripts/vermin.gd`, one MultiMesh, at most 220 drawn): nests
  on every root wall (5-12) and by 60% of the seated dead (3-7): 366 nests. A
  nest is a wall; its beetles walk a field over it (v >= 0 up the brick on the
  wall's relief, v < 0 out over the floor), in bursts with stops, scattering at
  1.1 m/s from a player within 1.7 m. Only nests within 16 m of the camera
  move or draw.
- **Rats**: `rats_in_corridors` 24 -> 60, `rat_apart` 6 -> 4 m (they sleep
  beyond 25 m, rat.gd).
- **Burial walls in the ossuary** (`_loculi`): the morgue's catacomb facade
  (kit `wall_loculi`, the corridor brick with shrouded dead in three rows of
  niches) stood on 45% of the ossuary's free straight walls, candles at its
  foot; a 3.75 x 2.82 x 0.86 collider.
- Build: the ruins 2.8 -> 4.7 s (the roots).
