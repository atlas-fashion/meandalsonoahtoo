## 25. Wheels instead of the hotbar; controller; thrown into stone; the mine's calm (2026-10-10)

- **Thrown enemies meet the real stone** (enemy.gd `_thrown_move`): while a
  knockback or stagger carries a body, its mask gains layer 9 (the player's
  exact walls) for that move only. Its own boxes (layer 10) come from the grid
  and miss arcade piers and arch jambs, so shoves put skeletons into pillars.
  Measured: 40 bodies thrown hard at the nearest exact stone -- 0 inside it;
  control with the mask off: 19 of 40 inside.
- **The mine no longer alarms on entry.** Its wardens wander a patch of court
  in front of the face (`_watch_spots`) inside a room-sized aggro box and fight
  only on SIGHT. enemy.gd: a guard with a wander patch now strolls it while the
  player is outside its zone instead of walking home and standing (a leash
  first used here pinned them at their posts whenever the player was > 20 m
  off). Miners keep working until the last warden falls (`MINERS_TURN` 2.5 s
  later, all turn) or one is struck at its work: each working miner has a
  `MinerHit` StaticBody3D on the damageable layer (3) only, so swords, the
  spear and blasts reach it; struck, it becomes a real enemy that takes the
  blow. Measured 9/9 (wardens 2-5 m strolled in 10 s, sight -> engaged, cut on a
  working miner turns only it, 4 working -> 0 by 3.5 s after the last warden).
- **The hotbar is gone; two wheels replace it** (inventory.gd, radial_menu.gd).
  Slots 0-3 are the WEAPON wheel, 4-7 the QUICK ITEM wheel (up 1, right 2,
  down 3, left 4), 8-37 the bag (SIZE 38). `slot_accepts`: weapons only on the
  weapon wheel, consumables only on the quick wheel; `add` puts new weapons /
  potions straight onto their wheel, everything else in the bag. Old saves
  (39 slots) are re-added through `migrate`. `player.selected_slot` is the
  weapon-wheel slot in hand. Hold C (or R3) for weapons / R for quick items,
  aim with the mouse (travel accumulated and swallowed, so the view does not
  turn) or the right stick, release to equip / use; an empty slot or no aim
  does nothing. D-pad uses quick items 1-4 directly. Walking continues while a
  wheel is up; looking and attacking wait (`player.wheel_open`). Set up in the
  inventory (now V / Y): the character panel shows both wheels as diamonds.
  There is NO shield weapon (the user's list named one): the wheel holds the
  sword and spear, the rest empty, by the user's choice.
- **Controller** (project.godot): move left stick, look right stick (player
  `_pad_look`: squared response, `pad_look_speed` 3.4 rad/s x the sensitivity
  setting), RB light, RT medium (spin / dash), LT heavy, LB block/parry, R3
  weapon wheel, L3 ghost, d-pad quick items, A jump, X interact (not in the
  user's list), Y inventory, Select map, Start pause. Inventory on a pad: d-pad
  moves a cursor between slots by screen position, A lifts and A places, X
  sends a stack between bag and wheel, LB / RB change category, B / Y close.
  Pause / title menus focus a button for pad navigation. Attack icons switch
  their labels to RB / RT / LT when a pad was used last.
- **Traps**: this Godot's built-in `ui_accept` / `ui_cancel` have NO joypad
  buttons (d-pad and stick are in ui_up..ui_right) -- they are defined in
  project.godot with A / B added. A focused Button swallows "ui_cancel" before
  `_unhandled_input`, so the pause menu and title read it in `_input` (Escape
  stopped closing the pause menu once its Resume button had focus). Mouse
  travel arrives scaled by the window's stretch (half in a 2x window): the
  wheel's `DEAD_ZONE` is in canvas pixels. A Control made full-rect with
  `set_anchors_preset` alone stays zero-sized (the wheel drew round the
  top-left corner). Measured 26/26 + 7/7 driving real pad events
  (parse_input_event): both wheels by mouse and pad, d-pad drink, stick look,
  RB/RT/LT/LB, L3, A, Select, Start / B, Y, pad cursor, slot rules, migration.

