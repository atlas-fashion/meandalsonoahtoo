## 12. The starting jail cell (2026-10-08)

- `scripts/jail_cell.gd` dresses the spawn dead end (`Built.spawn_door`) as a
  jail cell, built FRESH -- the old tile-maze jail code (`_build_jail_cells`,
  `_stock_jail_cells`, `cell_door.tscn`) is deliberately not used. Called from
  `maze._build_module_level` right after `place_doors`, before the bake. The
  gate door is untouched and still has to be kicked in.
- **A dead end is not square.** Measured with rays from its centre: back wall
  2.79 m, but two thick piers fill the back corners, so behind z = -1.2 (toward
  the back) the room is an alcove only 1.80 m either side; the full 2.79 m is
  only toward the door. A bed against the "2.79 m" side wall sat inside a pier.
  Layout now: plank bed with a straw pallet and a blanket across the alcove's
  back wall (head 0.15 m off the left pier), two shackles and chains on the back
  wall beside it with the last prisoner's skull, ribs and long bones under them,
  tally marks on the right pier, a slop bucket out in the wider front part,
  260 straw blades (MultiMesh) kept inside the real floor outline.
- Wall pieces (shackle plates, tally marks) snap onto the real stone by ray
  (mask 2|256) two physics frames after `_ready`: Tripo stone stands up to
  ~10 cm proud of the measured face.
- Plain-coloured props lit by the door's torches a metre or two away blew out
  to glowing orange; their albedos are deliberately dark (straw 0.29/0.22/0.10,
  bone 0.48, scratches 0.30).
- Measured: built in the spawn dead end, player starts inside it, 3/3 wall
  pieces snapped, bed and bucket collision clear of the stone (shape queries on
  layer 9 -- the first layout overlapped), nothing on the spawn spot, the door
  shut and E still kicks it in.- **Block pressed during an attack waits for it** (2026-10-08): `_start_block`
  now refuses for the WHOLE of a cut or thrust (it used to allow raising the
  guard out of a cut's recovery), and `_hold_guard` (every physics tick, after
  `_check_block`) raises it the moment nothing refuses any more if the button is
  still held -- the end of a cut, a thrust, a slam's recovery, a drink. Released
  before the end: no guard. A right click that only recaptured the mouse is
  `_guard_click_spent` until released, so it never turns into a block. Measured:
  held through a cut / pressed in its recovery / held through a thrust (the
  lunge still happened): guard up 0.016-0.017 s after the attack ended, never
  during it; tapped mid-cut: no guard; idle press: immediate, fresh parry window.
