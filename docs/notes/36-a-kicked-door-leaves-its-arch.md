## 36. A kicked door leaves its arch (2026-10-12)

- `wood_door._drop_frame` is gone: a kick (and a load of a kicked door) used to
  hide the brick door's stone frame ("GateFrame") and drop its jambs' collision,
  so the arch vanished with the door. Now only the wooden leaf breaks; the frame
  and jambs stay (the navmesh was always baked with the jambs, so nothing
  changes for pathing).
- The frame had been hidden because, with the leaf cut out of it, its stone was
  hollow: from the far side the opening's inner faces were missing (a black
  hole). `module_level._build_brick_door` gives the frame two-sided copies of
  its materials (`_frame_both_sides`), and the reveal reads as stone from both
  sides.
- Measured in a harness: after a kick, frame visible, jambs on layers 1+2, leaf
  gone; walked through on the real W key from 2.5 m before the door to 7.5 m
  past it; shots from both sides and both angles show the arch whole.

