## 97. The maze as it was; the surgery in the room nearest the boss (2026-10-21)

The user: "Revert the maze to the format that I had before you made the surgery
room. Make the existing room closest to the boss room in that format the
surgery room, rather than making a new maze layout." Supersedes note 94's
choice of room (the chest room furthest from both the start and the morgue).

**What had changed the layout.** Note 94 asked module_level for one more chest
room (`chest_rooms`: `module_chest_rooms + morgue + surgery`). Room count feeds
the generator, so every seed laid out a different maze: on seed 20260918 the
spawn moved from (-150, 5.25) to (126, -6.75), the morgue from (39, 13) to
(9, 42), an extra room appeared at (7, 28), 1,112 cells became 1,121.

**Now.** maze.gd asks for `module_chest_rooms + morgue` again -- no room for the
surgery -- and module_level `_make_surgery_hall` turns one of the existing
chest rooms (those left after the morgue's pick) into the surgery: the one
nearest the boss room, straight line centre to centre. So there is one chest
room fewer (4, not 5): one fewer puzzle room, and the great door's sockets
(counted from the rooms built) one fewer with it.

**Measured** (a throwaway harness printing every room's kind and centre, the
spawn, and a hash of every cell's openings and room index, seed 20260918): the
commit before the surgery (01ff157, its maze.gd / module_level.gd /
brick_level.gd checked out for the run) gave 1,112 cells, hash 2982778077,
spawn (-150, 0.2, 5.25); now -- identical, the same seven rooms in the same
places, the chest room at (40, 37) (106.8 m from the boss, the nearest; the
others 110.3-142.6 m) now kind "surgery". The current code before this change
gave hash 894167556 -- the comparison catches a different layout. The surgery
builds in its new room (two ways in: one on the front wall's middle, one at a
corner of the back wall; lintels and torches follow them), and a clean run is
clean.
