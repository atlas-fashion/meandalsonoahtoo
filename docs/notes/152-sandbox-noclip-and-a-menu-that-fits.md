## 152. Sandbox: noclip; a menu that fits the screen (2026-11-01)

The user, for the sandbox: a noclip toggle (free flight through walls), and the
sandbox menu ran off the screen.

- **Why it ran off**: project.godot stretches canvas_items over 1280 x 720, so
  the UI is **720 high however big the screen** (1720 x 720 at 3440 x 1440), and
  the GIVE ITEMS list had grown the middle column to 725 px on its own, before
  the panel's title and margins. The last buttons were off the bottom. A bigger
  screen would not have helped.
- **The menu** (`scripts/sandbox_menu.gd`): each column is in its own
  ScrollContainer (`_scrolled`, `follow_focus` so a pad's focus brings a button
  into view), the old list-only scroll in TELEPORT gone. `_fit` (on
  `size_changed` too) gives the columns the screen less `PANEL_CHROME` 140, at
  most `COLUMNS_MAX` 780. At 1720 x 720: panel 1144 x 699, 10 px from the top.
- **Noclip** (`Sandbox.noclip`, cleared by `reset()`; the menu's "Noclip (fly
  through walls)" under SWITCHES): player.gd `_update_noclip` at the very top of
  `_physics_process` takes `collision_mask` to 0 (kept in `_solid_mask`), `_fly`
  after the cutscene branches: full steering the way the view points
  (`_look_pitch`, not `head`, which carries the bob), Space / A straight up, Ctrl
  / B straight down (`ui_cancel`), Shift / the ghost button x3. `NOCLIP_SPEED` 14,
  `NOCLIP_ACCEL` 90. `move_and_slide` still runs, so `is_on_floor` goes false
  (the jump clip, no footsteps). Weapons swing and hit as usual.
- **Solid again for any scene and for a death**: both drop the body under
  gravity, and with mask 0 it falls through the floor. So `_update_noclip`'s want
  is `Sandbox.noclip and not in_cutscene and not _dead`, and it has to run before
  those branches return.
- **No sword dive while flying** (`_unhandled_input`): the dive is the only thing that ends
  it and it runs straight down until `slam_timeout`, through every floor.
- **Shift is not a ghost**: `_update_ghost` does not run while flying, so
  stopping sets `_ghost_locked` or a held boost would turn into one (note 113).
- **Switching off** (sandbox_menu.gd `_set_noclip` -> sandbox_world.gd
  `land_from_noclip`): in the open the body just drops where it is. Left in the
  rock or under a floor it would fall for ever, so it goes to the nearest navmesh
  point, snapped to the floor. "In the rock" is a ray from that navmesh point to
  the body with `_solid_mask`, or more than `NOCLIP_OPEN` 1.2 m off it sideways
  (past the plane's edge).
- **Trap: the navmesh rides 0.45-0.5 m above the stone.** The first test was
  `nav.y - at.y > 0.4` for "under a floor", which is true of anyone standing on
  one, so every switch-off at floor height teleported with a fade for nothing,
  and it hid that a body 1.2 m up inside a thin wall was not moved. Compare no
  height with the navmesh; ask whether it can see the body.
- **The navmesh has polygons on top of the level**: switched off 14 m over a
  corridor the body lands on the roof at y 5.7, standing. Noclip or a teleport
  gets it back; left as it is.
- Measured (throwaway harness, deleted; windowed at 3440 x 1440, real key
  events): 53/53. Panel inside the 1720 x 720 rect, also at 1280 x 1024 and
  1024 x 576 and back; all 50 controls come into view when focused; the wheel
  over a spin box scrolls the column (145 px) and leaves the level alone. Flying:
  13.0 m in the first second, level at pitch 0, 45 degrees up gave (9.2 up, 9.2
  along); Space +13.5, Ctrl -13.3, Shift 32.5 m in a second, no ghost; nothing
  moves with the menu open. On foot a wall 1.9 m off stopped them at 1.5 m
  (the control); flying the same line went 27 m on with 0 collisions. Off in
  the air on the plane: no sideways move, down to the floor. 10 spots in and
  beside walls at two places, plus under the floor and far outside the level
  (300, 1, 300): each ended standing on a floor and able to walk. A dive refused
  in the air, granted on foot (the control); a swing in flight ends; a scene and a
  death put the mask back, 257, and flight resumes after; `reset()` clears it.
  Screenshots checked (top, and scrolled to the last buttons). A clean
  `--quit-after` sandbox boot had no errors.
