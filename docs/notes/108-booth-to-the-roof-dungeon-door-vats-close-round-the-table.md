## 108. The control room up to the roof, a dungeon-sized door; the vats close round the table (2026-10-25)

The user: "Make the control room as high as the ceiling of the surgery room.
Leave the floor where it is, and make the door the size of all the other ones.
Make the checkerboard pattern for the vats close to the table, and the open
space further away from it. That way they are harder to move around."

### The booth to the roof (`surgery_control.gd _build_booth`)

The floor stays at BOOTH_FLOOR 2.9. The walls go up to `_top` =
surgery.gd `booth_top()` = CEIL - 0.05 (8.55):
- **The leaded windows** stay a band BOOTH_H 2.3 tall at the bottom, on the
  hall side and at the far end.
- **Above them**, plank walls (`_planks`: a BoxMesh in the hall ceiling's
  planks, triplanar, and a collision box) go up to the roof.
- **Oak posts** run up both outer corners.
- **The plank roof** is at the top.

The hall's roof beams cross the top of it; they read as resting on its walls.

**The gantry was in the way.** Its runways run along the hall's ±X walls
(tops 6.75), and the bridge spans between them at 7.2, moving along Z. So:
- **`_choose_plan`** now counts an even turn (booth against a runway wall) as
  3 conflicts, so it takes an odd one -- booth against a ±Z wall -- unless the
  ways in leave nothing else. On an even turn `booth_top` falls back to just
  under the runways (6.07), and the door is cut down to fit.
- **`gantry_limits()`**: the booth's and landing's footprint plus a 0.7 m
  set-back gives a limit on the bridge's z (or, on an even turn, the
  trolley's x). The table clamps its gantry goal to `b_lo` / `b_hi` in
  `_drive`.

The cost: on the odd turns the claw can no longer get within about 3.7 m of
that one wall, anywhere along it. With the vats now all near the table, that
strip is open floor.

### The door (`_door_wall`, the leaf)

**The leaf.** "The size of all the other ones": the dungeon's wooden doors are
the brick kit's `door_leaf`, 1.94 m wide with a pointed head 4.2 m up
(module_level BRICK_LEAF_HALF / _TOP). The booth's door is now that same leaf
(BrickLevel.standalone("door_leaf")):
- scaled to DOOR_W 1.94 x DOOR_H 4.2 and thinned to LEAF_DEPTH 0.3;
- centred on the booth's door end, with module_level's `_leaf_backing_mesh`
  behind it;
- its blocker 1.94 x 4.2.

**No stone arch.** The kit's `door_arch` is 4.6 m wide and the booth's end is
2.98 m, so the arch is left out.

**The wall round it.** The door end is a CSG plank wall the booth's height,
with the leaf's outline cut out of it: straight sides to 3.05, then
tools/build_brick_kit.py's DOOR_LEAF_HEAD points to the apex. The CSG is solid
(layers 1 | 2).

Note 104's `boothdoorwall` piece and its boxes are gone. The kick shatters the
leaf as before; the crystal route's `_swing_door_open` swings it on its edge.

### The vats close round the table (`surgery.gd`)

Note 107's checkerboard is turned inside out:
- vats on the dark squares from TABLE_CLEAR 3.0 round the middle out to
  `_vat_outer()` -- VAT_OUTER 10.0, or 0.6 past the hatch if module_level put
  it further out, so a vat always stands over it;
- open floor beyond.

The nearest vats stand 3.35 m from the middle: a running jump off the table
lands on one. OPEN_RADIUS is gone.

### Measured (throwaway harness, headless; deleted)

14/14:
- plan turned 90; booth top 8.55, roof there, floor 2.9;
- door leaf 1.94 x 4.20 x 0.30; shut, it blocks; the wall beside it solid;
- chasing a player on the landing for 9 s, the gantry stayed within its limit
  (0.03 m of arrival overshoot inside a 0.7 m set-back);
- E at the door: kicked in, the surgeon out on the flags, the doorway open;
- 14 lattice vats from 3.35 to 9.60 m out (+2 across the ways in), none side
  by side (4.24 m), a vat over the hatch;
- a run and a jump off the table lands on the nearest vat (feet 1.82 m up).

Windowed: the dungeon door with its pointed head set in the booth's plank wall,
and the vats checkered round the table with the floor open beyond. The
booth's upper walls are dark from the hall -- its lamp lights only inside.

### Traps

- **The gantry spans the room at 6.2-7.2 m.** Anything taller standing against
  a wall has to keep it off (`gantry_limits`) or keep off its runways (the plan
  turn).
- The brick kit's door arch is 4.6 m wide: the leaf alone fits a narrower wall.
