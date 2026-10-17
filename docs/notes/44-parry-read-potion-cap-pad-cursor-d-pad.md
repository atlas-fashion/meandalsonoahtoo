## 44. Parry read, potion cap, pad cursor, d-pad wheel, map pins, safe respawns (2026-10-14)

- **Crier parry reads as a parry**: `player._on_guarded` puts the guard flash
  in the MIDDLE of the view (1.15 m down the camera's -Z) when the attacker's
  `guard_flash_centre()` is true -- a crier on the face; it used to go 1.3 m
  above the attacker's origin, i.e. off the top of the screen. A parried
  explosion (the crier hears the player's `guarded` signal inside its own
  `take_damage` call) throws the pieces off the face with no fireball; an
  unparried one keeps the fireball. Fuse `face_fuse` 1.8 -> 1.0 s.
- **Potions: one stack, at most 20** (`Inventory.ITEMS` "single";
  `is_single`): `room_for` counts only the one stack's room, `add` never starts
  a second stack, `split` will not make one. Everything else stacks as before.
- **Pad cursor is the LEFT STICK only** (pad.gd): read from the stick's own
  motion events (`_stick`) -- `Input.get_joy_axis` only sees what a joypad
  driver reports, so injected events moved nothing -- and those events must NOT
  be marked handled by a screen: input reaches the tree last child first, and
  the autoload Pad (first under root) heard nothing while the inventory
  swallowed them. `want_cursor(owner, on, click)`: the inventory asks with
  `click` false -- the cursor's hover IS the highlight (kept when it drifts off
  a slot on a pad), and A lifts/drops it as before; the d-pad still steps.
- **D-pad holds the quick wheel** (radial_menu.gd `_held`): a direction opens it
  on that slot; another direction moves the choice; releasing the held
  direction uses it; B before that cancels. player.gd no longer uses quick
  items straight off the d-pad.
- **Map**: left click / A drops a PIN (`quick` true: no editor, never on the
  minimap, saved with the marks; left click on a pin lifts it); right click / X
  opens the mark editor (new mark, or edits whatever is under the cursor).
  Middle drag pans in the free-pointer path.
- **Nothing spawns in sight** (maze.gd `_seen_by_player`, `_note_spawn_eye` at
  the top of `_populate`, after the player has been placed): corridor spawn
  tiles (and convoy starts) are skipped when any of SPAWN_SIGHT_POINTS -- the
  tile's centre and the corners of a pack's 1.3 m scatter, at 1.0 and 2.4 m --
  has a clear line (sight layer) from the eye within 70 m. Checking the centre
  at 1.2 m alone left two hovering criers in sight round a pier. The Remnant
  (>= 100 m off) skips the test. Cost: +70-160 ms per repopulation, behind the
  death fade.
- Measured: 23/23 (potions 25 -> 20 in one stack, room 12 at 8, no split,
  bones 150 in 2 stacks; fuse 1.02 s; unguarded fireball and 50, parried 0 and
  no fireball, flash at the view's centre; Y opens, d-pad steps, stick moves
  the cursor 227 px, its slot is the highlight, B closes; d-pad holds the wheel
  with nothing used, release drinks, B cancels; left click pins, right click on
  it edits, left click lifts, right click on open map opens the editor) and,
  with the full population from 6 corridor spots: 0 enemies in sight, 312
  tiles in sight skipped.

