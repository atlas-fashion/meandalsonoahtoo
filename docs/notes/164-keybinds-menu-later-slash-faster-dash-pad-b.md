## 164. A keybinds menu, a later and fuller slash, a quicker dash, B to dash (2026-11-04)

The user asked for four things: "Make a keybinds menu, make the sword slashes
have a more elaborate, hyper realistic animation to where the sword hits a
little later than it does now. also make the dash cooldown 75% of what it is
now. bind B to dash on controller".

### The keybinds menu

- `scripts/keybinds.gd`, autoload `Keybinds` (registered after `Pad`). At startup
  it copies the project's own bindings for every action on the page (`ACTIONS`,
  20 of them: movement, jump, sprint, dash, the four attacks, interact,
  inventory, map, both wheels, the four quick slots) as the defaults, then lays
  `user://keybinds.cfg` over them.
- Each action has a **keyboard/mouse column** and a **controller column**
  (`column_of`: pad buttons and pad axes are the controller). `bind(action, e)`
  replaces that column's binding. If another action on the page already had
  that input, the two **swap**, so nothing ends up doubled and nothing that was
  bound loses its binding. `unbind` clears a column. `reset_all` restores
  the defaults.
- **Saved as strings, not Objects**: `key:<physical>:<location>`,
  `mouse:<button>`, `joy:<button>`, `axis:<axis>:<+1|-1>`. Only actions that
  differ from the defaults are written, so a later change to a default still
  reaches players who never touched that action. Trap: ConfigFile returns the
  saved list as a `PackedStringArray`, not an `Array`. The first loader checked
  `is Array` and silently loaded nothing.
- `bindable(e)` cleans a pressed input down to what a binding keeps:
  - the physical key, plus the side for Ctrl/Shift/Alt/Meta only;
  - the mouse button;
  - the pad button;
  - an axis pushed past 0.6, with its sign.
  It refuses **Escape** and **Start / Guide**, because those are how the player
  gets out of every menu. `pause` and the `ui_*` actions are not on the page,
  for the same reason.
- **Co-op**: `Coop.resplit()` (new) rebuilds the `p1_` / `p2_` copies from the
  new bindings whenever they change, so a rebinding takes effect mid-game for
  both players. Tested: `p1_attack` followed a rebinding to K.
- **Labels follow the bindings**: `Keybinds.label(action)` gives "LMB / RB"
  and `text(action, column)` gives one column.
  - The inventory's Controls rows (`inventory_screen.gd` `_stats_for`) now read
    them for sword, spear, axe, rat, robot rat and consumables.
  - The HUD attack tiles (`attack_icons.gd`, `KEY_ACTIONS` maps the attack lists'
    "LMB"/"Q"/"F" to attack/thrust/slam) show the current binding for the device
    in use.
  - The intro lessons' text is still hand-written.
- **The page**: `scripts/keybinds_panel.gd` (`KeybindsPanel`). It opens from
  **Settings → CONTROLS → Key bindings "Change..."** on both the pause menu and
  the title screen, and replaces the settings page while it is up
  (`SettingsPanel.show_keybinds`).
  - Pressing a binding starts listening. The next key, mouse button, pad button
    or trigger becomes that binding, and the hint says what was swapped.
  - Esc or Start leaves the binding unchanged, and so does waiting 6 s.
    Delete or Backspace clears it.
  - For 0.18 s after listening starts, input is ignored, so the click or A press
    that started it is not what gets bound.
  - "Reset all" restores the defaults.
  - Escape / B on the page, when not listening, steps back to the settings
    (`SettingsPanel._input`). It runs ahead of the menu's own handler because
    a child's `_input` runs before its parent's.
  - Trap: `settings_panel.gd` preloads the page script instead of naming the
    class. The global class cache is not rebuilt in a headless `-s` run, so
    `KeybindsPanel.new()` failed to parse there.
- Tested headless (event pushes through `root.push_input`):
  - bind, swap and pad bind;
  - the grace window ignores the starting press;
  - Escape cancels and B / `ui_cancel` steps back;
  - a save/load round trip, and a reset leaves an empty file.

### B dashes on a pad

`project.godot` `dodge`: joy button 1 (B) instead of 7 (L3). On a pad, sprint
is the stick pushed all the way, and clicking L3 while sprinting dashed by
accident. B was only `ui_cancel`, and the dash ignores presses while a menu is
open, so it doesn't clash. Noclip's "Ctrl / B straight down" already matched. The dash also ignores B while a
wheel is up (`_dash_pressed` checks `wheel_open`), because B is what closes the wheel
(`radial_menu.gd`).
The intro lesson, the inventory rows and the player.gd comments now say B.

### The dash: 75% of the wait

`dash_time` 0.65 → **0.4875 s** (player.gd export). It is both the wait before
the next dash (`dodge_ready`) and the length of the dip-and-rise of the view
(`dash_motion`), so the body motion is shorter too. The motion itself
(`dash_move_time` 0.24) and the iframes (14/60 s) are unchanged.

### The slash

All times are pose seconds (×1.25 for real seconds, `attack_time_scale`).
`_swing_pose` in player.gd now runs in five phases.

| phase | until | what the blade does |
|---|---|---|
| gather | `SWING_GATHER` 0.08 | eased in and out (smoothstep) round the arc to `SWING_PULL` 0.22 rad past the start of the arc; pitched up `SWING_CHAMBER` 0.2; the hand up, back and out to the wind-up side (`SWING_CHAMBER_HAND`) |
| load | `SWING_WIND` 0.125 | a creep of `SWING_CREEP` 0.07 rad further back, the hand drawn in tighter |
| cut | `SWING_HOLD` 0.31 | one smootherstep from the loaded yaw to `SWING_OVER` 0.24 rad past the end of the arc (fastest across the middle, through the crosshair around 0.22). The chamber pitch drains by 45% of the cut, then it drops `SWING_DIG` -0.14 through the target. The hand drives forward `SWING_REACH` mid-cut and is drawn across and down at the end (`_cut_hand`). The wrist rolls the edge `SWING_ROLL` 0.5 rad over the last 45% (`_arc_pose`'s new `roll`, about the blade's own line) |
| settle | `SWING_SETTLE` 0.37 | a `SWING_RECOIL` 0.06 rad rebound off the end |
| home | `SWING_END` 0.54 | round the arc to rest, with the wrist turned so the edge arrives as it rests (`_roll_onto_rest`) |

- **It bites later**: the hit window is SWING_WIND..SWING_HOLD, so it opens at
  0.125 pose = 0.156 s real, against 0.07 = 0.0875 s before (+69 ms). Measured
  in a live attack: the window opened on the 0.150 s physics tick.
- **The view kick and the lunge come with the cut, not the click**
  (`_strike_cut`, fired from `_update_pose` once `_pose_time` passes SWING_WIND;
  `_cut_struck` flag). During the gather and load the body is still. Measured:
  the kick at 0.150 s, same as the window.
- The queued-combo boundary (`_bite_end`) and the HUD tile are still SWING_HOLD,
  now 0.31 (was 0.27). A full stroke is 0.54 pose (0.675 s), up from 0.42.
- `_trail_point` samples the cut over SWING_WIND..SWING_HOLD (`SWING_CUT` is
  gone). The trail turns on 0.01 before the cut.
- **Measured** (tip speed, 1 ms steps, real seconds):
  - cut peak 92-94 m/s;
  - gather 75 (forehand) and 106 (backhand from rest);
  - load 5, settle 7, home 44-60.
- Trap: the forehand's edge at the rest aim was nearly half a turn from the
  rest pose's edge. The home blend's slerp flipped across in one frame (a
  100-250 m/s spike at t≈0.50). `_roll_onto_rest` turns the arc's edge onto
  the rest edge the short way, so the slerp only has a small residual left.
- Rendered (slowed 20x, frames at fixed pose times) and compared with the old
  stroke. The arm mesh tearing mid-cut (the IK'd knight arms, note 156) is in
  the old stroke too; this change did not cause it.
