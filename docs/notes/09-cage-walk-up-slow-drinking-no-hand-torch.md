## 9. Cage walk-up, slow drinking, no hand torch, new keys (2026-10-06)

- **Keys**: ghost mode ("dodge") is LEFT CTRL (physical KEY_CTRL, location
  left) in project.godot; the thrust is SHIFT + left click and the slam SHIFT +
  right click (`shift_pressed` read off the event, as Ctrl was); plain right
  click is still the block. Ctrl + left click is now just a cut. No cut,
  thrust, slam or block while ghosting.
- **Ghost entry cost**: `ghost_entry_cost` 0.1 of the bar is taken the moment a
  ghost starts, then it drains as before, so tapping it is not free speed.
  Measured: 1.00 -> 0.883 on entry; five quick taps -> 0.458.
- **Drinking** (`use_consumable`): a drink takes `drink_time` 3.0 s. The flask
  is used up as it starts, the heal lands at the end (`_update_drink`, game
  clock), and meanwhile the player walks at `drink_move_scale` 0.25 and cannot
  attack, block, slam, ghost or haft-strike; the sword is put away and the
  flask held to the lips (`held_potion.drink(duration)`: up in 0.35 s, sipping,
  down at the end). HUD: "Drinking" countdown bar above the hotbar
  (`hud._build_drink_bar`, `player.drink_remaining()`). Death cancels it.
  Measured: 3.02 s; 1 s of walking 3.64 m plain vs 1.05 m drinking.
  Harness trap: the first walk test ran into the spawn's door and "passed" at
  0.04 m -- measure movement on open floor, against a plain walk.
- **The hand torch is gone** (`Head/TorchHand` and its six resources removed
  from player.tscn). It was the only shadow-casting light in the game, so the
  "torch shadows" setting now has nothing to act on, and corridors are lit by
  the wall torches alone.
- **Cage scene walks the player over** (`bone_cage._play`):
  `begin_cutscene(true)` -- a scene in the world, so blows still land
  (`take_damage` checks `_cutscene_hurts`) -- then `player.scene_walk_to(spot)`
  (`STAND_OFF` 1.3 m out from the cage, walking pace, turning to face the way,
  ends on arrival / timeout / no headway, signal `scene_walk_finished`), a short
  turn to square up, door, stab, loot, level the view, control back facing the
  cage. Dying partway (`_still_going`) drops the scene and leaves the cage to
  try again; `_die` ends a scene walk and `_respawn` clears `in_cutscene`.
  Measured: walked from 2 m off to one side, struck from 0.10 m off the spot,
  a 10-point blow landed mid-scene, paid; death mid-scene -> cage not busy,
  not looted, player back in control.
- **Keys again (2026-10-07)**: ghost ("dodge") is SPACE (held), jump is F,
  drinking ("heal") is R, the map ("toggle_map") is TAB. Thrust / slam stay
  Shift + left / right click; block is right click. The map toggles in
  `_input` (before the GUI) and marks Tab handled, so it does not also move
  focus between controls. Verified by pressing the real keys in a harness.
- **And again (2026-10-07)**: ghost ("dodge") is RIGHT MOUSE (held), block is a
  new "block" action on SPACE (held; parry = Space just before the blow). Shift
  + right click is still the slam: right click with Shift down never STARTS a
  ghost. `_action_held(action)` asks the keyboard and mouse directly (keys and
  mouse buttons) instead of the latched action state; `_dodge_held` and
  `_check_block` use it. Jump F, drink R, map Tab, thrust Shift + left click.


