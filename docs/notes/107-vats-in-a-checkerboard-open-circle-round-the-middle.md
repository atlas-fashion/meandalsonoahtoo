## 107. The vats in a checkerboard, a wide open circle round the middle (2026-10-25)

The user: "arange the vats in a checkerboard pattern in the center of the floor,
and have a wide circle area around the middle that is open with no vats. The
hatch should be under one of them."

### How it reads (`surgery.gd _lay_vats`)

The vats stay on note 102's lattice: 3 m apart on the dungeon's flagstone
grid, through the hatch, out to VAT_REACH. Note 102 carved a maze in it (a
Kruskal spanning tree, VAT_LOOPS, `_join_up`); now the vats stand on every
point whose two indices add up to the hatch point's parity -- the dark squares
of a checkerboard.

**What that gives.**
- No two vats stand side by side.
- They meet only at their corners, 4.24 m apart across the diagonal, leaving
  1.9 m gaps.
- The open floor runs between them corner to corner, all of it connected.

**The open circle.** No vat within OPEN_RADIUS 6.0 of the middle. That
replaces note 102's CLEAR_MIDDLE square, which survives only as where the rail
ends. Once the vats' own size is counted, the clearing round the table is
about 10 m across.

**The hatch.** Its point is always a dark square, so a vat always stands over
it. With no vat beside it, it can be shoved off any way. It is exempt from the
circle and the other kept-clear zones; module_level puts it 5.9-9.1 m out
(SURGERY_HATCH_RING).

**Still kept clear** (`_kept_clear`): the intake under the booth, the pens, the
rail, the ways in. The two vats across the ways in (note 105) are as they were.

`_join_up`, `_floor` and VAT_LOOPS are gone.

### Measured (throwaway harness, headless; deleted)

8/8, the default seed (the hatch 7.5 m out, the plan unturned):
- 24 vats on the lattice and 2 across the ways in;
- the nearest pair 4.24 m apart, 26 diagonal pairs;
- the nearest vat 6.18 m from the middle;
- a vat exactly over the hatch (0.00 m), the hatch reading as covered;
- all 1800 walkable 0.5 m floor cells (a capsule the player's size, the pens
  left out) reachable from the middle, and both ways in.

The only cut-off floor was behind the pens' bars, where it should be.

Windowed: from overhead, the vats on alternate squares round the clear middle;
from a corner, the table alone in a wide clearing, vats checkered round it.

### Note for the booth route (notes 104-106)

The nearest vats now stand 6+ m from the middle: too far to jump to from the
table (1.2 m) without first grabbing one and pushing it up to it.
