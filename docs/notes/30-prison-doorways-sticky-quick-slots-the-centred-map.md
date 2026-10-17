## 30. Prison doorways, sticky quick slots, the centred map, pad inventory (2026-10-11)

- **The domed prison sealed its CORNER doorways.** A corner ring cell has no
  bay onto the court, and the cell walls either side of it shut it in: measured
  with a nav path + a walk on the player's own collision from outside every
  room entrance, 3 of 3 corner entrances into the prisons led nowhere (path
  ended 15 m from the hall). `dungeon_room._open_ring` now keeps every
  doorway's ring cell open AND, for a corner doorway, the bay beside it (no
  gate, no cell) with no wall between the two (`_open_pairs`, skipped by
  `_build_partitions`). After: 10 of 10 room entrances reach the centre.
  Test traps: the walk stops at the dais / generator in a room's middle (judge
  "within 2.6 m of the centre"), and the prison's wardens stand in the way --
  free them for a stone-only test.
- **Quick slots keep their item** (`inventory.assigned`, slot -> id): set
  whenever an item lands in a quick slot (`_mark`, run by `_changed`), kept
  when the last one is used (`take` / `remove`), cleared only by moving the
  stack out by hand (`move`, `quick_move`), putting another item in, or
  `unassign` (right-click on the emptied slot). `add` / `quick_move` send an
  item to the slot kept for it first, and no other item may take a kept slot
  (`_free_for`, also used by `room_for`). A run-dry slot draws its item with
  `ItemSlot.GHOST` tint and "0" (item_slot.gd, radial_menu.gd "(none left)");
  `ItemIcon.tint` is new. Saved as "quick_assigned" (`inventory.restore`).
- **The full map is moved, not pointed at**: the mouse stays CAPTURED; motion
  pans the map under a crosshair fixed at the panel's middle (= the screen's
  middle: the panel now has equal 48 px margins), the wheel / right stick zoom
  about it, left click / A marks the spot under it or opens the mark there
  (highlighted by corner brackets, `_hover_pin`). Left stick, d-pad and W/A/S/D
  pan (`_pad_map`, `PAD_PAN`). Only the mark editor frees the mouse; on a pad
  it is worked by focus (note box first, OSK). No pad cursor on the map.
  Mouse travel arrives in canvas pixels, so the map moves 1:1 on screen.
  A border panel ("rim") is drawn over the map picture -- it used to cover
  the panel's own frame.
- **The minimap is heading-up**: the crop is drawn `MINI_SPIN_PAD` 1.45x the
  frame inside a clip and rotated by -facing; the arrow stays up; marks are
  rotated about the player; an "N" rides the rim.
- **Pad inventory without a cursor** (inventory_screen.gd): d-pad / left stick
  (read from its own motion events, so W/A/S/D does not move it) step the
  highlight to the nearest slot in that direction by screen position
  (`_pad_step`), the stick repeating (0.32 s, then 0.13 s); A lifts and drops
  (`inventory.move`), B puts a lifted stack back or closes. The mouse keeps
  its pointer and hover. pad.gd's cursor is now unused by both screens.
- Measured in a harness (36/36): potions run dry -> slot empty, kept, greyed
  "0"; new potions back to it; other quick slots untouched; survives save/load;
  dragged out -> freed; map: mouse 1:1, wheel zoom holds the centre, click mark
  0.00 px under the cursor, editor frees and recaptures the mouse, cursor at
  the screen centre, stick pans, right stick zooms, A marks, B closes; minimap
  turned exactly a quarter with a quarter turn, arrow 0; inventory: Y opens with
  no pad cursor, d-pad and stick move the highlight, A lifts and drops.

