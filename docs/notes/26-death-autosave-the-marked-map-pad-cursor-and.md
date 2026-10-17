## 26. Death autosave, the marked map, pad cursor and keyboard, hiding carts (2026-10-10)

- **Keys**: inventory Tab, map ` (KEY_QUOTELEFT), quick wheel X. (The pad's X
  is still interact.)
- **A death autosaves**: player `_die` -> `Saves.request("death")`, written by
  the existing "when safe" rule -- after the respawn and the getting-up, so the
  slot holds the world as the death left it. Toast "Autosaved".
- **The map draws no icons** (junctions, rooms, gates, hiding places removed;
  walls, floor, centreline and the player's arrow stay). The full map is worked
  with a cursor: mouse freed and `player.ui_open` held while open; wheel /
  right stick zooms about the cursor (1-10x of the fit), drag pans, a click
  marks the map: an editor (note <= 48 chars, 8 colours, pin / cross / ring)
  opens; a click on a mark edits or deletes it. Marks are world x, z
  (`_pins`), drawn on the full map (note shown on hover) and the minimap, saved
  as "pins" in the slot, and NOT cleared by a death's map reset. The editor
  sits in the top half and the hints along the top, clear of the keyboard and
  the HUD. Inventory and map refuse to open over each other.
- **`Pad` autoload (scripts/pad.gd)**: `using_pad` (last device touched);
  `want_cursor(owner, on)` -- the inventory and the full map ask for it. While
  wanted and a pad is in use: a drawn arrow, left stick / d-pad moves it, A is
  the left mouse button. Its moves and clicks are sent as REAL mouse events
  (`parse_input_event`, device 77 so they are not taken for the real mouse,
  positions through `get_final_transform()` to window coordinates), so hover,
  click and drag-and-drop work in screens that know nothing of it; the OS
  pointer is hidden meanwhile. The inventory's old slot-stepping pad code is
  gone. The map pans when the cursor is pushed against its edge.
- **On-screen keyboard** (`Pad.attach_keyboard(line_edit)`; on the map note and
  the title's game name): pops up when the box takes focus with a pad in use.
  Focus-navigated keys (A types), B deletes, X space, Y shift, Start / Done
  finishes (emits text_submitted and moves focus on). Its CanvasLayer is put
  LAST under the root (`pad_keyboard_input.gd`), so it reads B before the
  screen behind it would close.
- **Hiding places are lidded carts** (hiding_spot.gd rewritten): the convoy
  barrow scaled up for a person to lie in (tray 2.0 x 1.0 m, rim 1.0 m, wheel
  past -X, handles past +X, 3.3 m overall), plank lid hinged along the back
  edge: open -1.42 rad to climb in / out, -0.3 when peeking, shut otherwise.
  No skeleton, usable from the start (`is_empty()` always true;
  `restore_emptied` is a no-op for old saves). The maze's no-spawn patch is now
  1.8 x 0.8 m along the wall. **Convoy carts have a lid too**, shut while
  hauled (the load sunk `LOAD_DROP` 0.18 under it), thrown open when looted.
- Measured 29/29: keys; map open/close, scroll zoom, click-to-mark (mark lands
  0.0 px from the click), edit, drag-pans-not-clicks, save / death / load of
  marks; pad cursor shows and moves, right stick zooms both ways, A opens the
  editor, the keyboard comes up, A types "qq", B deletes to "q" without
  closing the map, Start finishes; inventory cursor; 58 carts, hide (lid shut,
  sight ray blocked), peek (lid -0.30), out; convoy lid; a death wrote the
  slot only once the player was up (save dir pointed elsewhere).

