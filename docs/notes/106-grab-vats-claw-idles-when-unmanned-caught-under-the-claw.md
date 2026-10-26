## 106. Grabbing the vats; the claw idle once the booth is taken; caught under the claw, not in it (2026-10-25)

The user, after note 105:
- "once the player smashes the control room door, the arm should stop chasing
  the player."
- "The player shouldnt be able to open the vats. Instead the player should
  interact to grab a vat. he can pull or push it. the player should also be
  able to turn them very slowly. The player should not be allowed to block or
  attack while latched onto a vat."
- "Dont let the player be inside the claw when its closed, but rather under it.
  Right now the player is in the mesh when its closed."

### Grabbing a vat (`surgery_vat.gd`, `player.gd`)

**The lid prompt is gone.** Players cannot lift lids; the claw still does
(`set_lid`, FETCH).

**Grabbing.** The vat's prompt is "E Grab" (`Interact.chooser` on the tub). It
does not show to a player standing on it, one already on a vat, or one in the
air.

`grab(p)` records the player's bearing round the vat in its own frame
(`_holders`) and adds a collision exception between them, so the vat neither
shoves them nor counts as being in their way. Then player.gd `latch(vat)`:
- `latched_to = vat`;
- `hands_busy` -- the weapon is put away;
- no guard.

While latched:
- the player's `_physics_process` returns early, and the vat places them;
- the input handler swallows every action but mouse-look (no attack, thrust,
  slam);
- `_start_block` and `_note_block_press` refuse;
- the jump is never read, so there is none.

**The keys** (`_physics_process` reads each holder's `_move_input`):
- **Forward pushes** it away from them, **back pulls** it toward them, at
  PULL_SCALE 0.7 of the speed. Pulling first checks with `test_move` that the
  player has room behind them, and stops dead at a wall.
- Both go through note 102's heavy feel: BREAKAWAY 0.55 s before it gives,
  then lurches up to PUSH_SPEED 1.1, and a brake when the keys stop.
  Reversing it means stopping first.
- **Left/right turn it** (`_turn_by`) about its middle at TURN_SPEED 0.3 rad/s,
  with no breakaway. The player goes round with it (their bearing is in the
  vat's frame), unless that would walk them into something. Turning is how a
  push is aimed.
- Two holders heaving the same way add TEAM_BONUS.
- The holders are placed every tick at `radius + GRIP_GAP` (0.5) out on their
  bearing (`_place_holders`).

**Letting go.** E again `release`s. So does player.gd `unlatch()`, which runs
from `restrain` (the claw), `knock_down`, `begin_cutscene`, `hide_in` and
`_die`. `_check_holders` also drops anyone dead, in a scene, held, latched
elsewhere, or teleported away.

**Walking into a vat no longer moves it.** Note 102's bump-shove (`_shove`,
SHOVE_DOT, TOUCH, GRACE_MS) is gone, so grabbing is the only way.
`shove_started` now fires on a holder's first heave, so the entrance scene
starts when the player grabs the vat across the way in and pushes. The scene's
`begin_cutscene` takes their hands off it.

Measured:
- walking into the way-in vat for 1 s does nothing; "E Grab" shows; E
  latches;
- pushing starts the scene, which unlatches them;
- on an open vat: attack, jump and block all refused while latched;
- pushed 1.76 m in 3.5 s, the player 1.65 m from its middle
  (radius 1.15 + 0.5) the whole way;
- pulled 1.48 m in 3.5 s;
- turned 0.61 rad in 2 s, the player going round 0.60;
- E lets go;
- walking into it for 2.5 s moves it 0;
- knocked down while holding: let go.

### The claw idle once the door is kicked in (`surgical_table.gd`)

surgery_control.gd `_burst_door` calls `table.operator_gone()`, which:
- sets `unmanned`;
- drops whatever it carries (`_drop_all`) and lets go of a held player;
- goes back to HUNT.

`_hunt`, unmanned, keeps no target and hangs over the table (wrist at hover
less 0.4, fingers relaxed), still lit, until the lever powers it down. No
slams, fetches or ferries.

A save made after the kick but before the lever ("booth" true, "down" false)
used to come back with the door whole. Now `control.set_kicked_now()` restores
it: door and far pane gone, him lying in the hall (`lie_down`, "die" held at
its end), the claw unmanned.

Measured: after the kick, with the player out in the hall and every cooldown
cleared, 0 frames attacking in 8 s, and the trolley stayed over the table.
Re-broken (the unmanned branch off): 317 frames attacking, the trolley out
7 m.

### Caught under the claw, not inside it

**Before.** The slam dropped the claw to the floor round the player. Carrying,
it held them CARRY_GRIP 0.45 down its length, so their body, and the camera,
was inside the shut fingers.

**Catching from above.** In the DROP, `_player_under()` looks each frame for a
player within GRAB_RADIUS whose head the fingertips have reached (tip at or
under feet + HANG_UNDER 1.95, and still over feet + 0.5). The drop stops
there:
- `_len` is set so the tips sit exactly HANG_UNDER over their feet (one frame
  of the drop carried them 0.65 m past, and the player was then pushed under
  the floor);
- the fingers shut;
- `_impact(now, on_player)` gives sparks off the fingers, not a floor crack.

The catch, block and parry rules run as before. A miss still goes to the floor.

**Carrying.** The player hangs with their feet HANG_UNDER under the
fingertips, head and view just under the shut claw. CARRY_Y 5.2 -> 5.75, so
the feet clear the vats (5.75 - 1.55 - 1.95 = 2.25 over 1.97). CARRY_GRIP is
gone.

Measured: caught with the fingertips 1.95 m over their feet; the view at least
0.34 m under the fingertips through the carry; the feet never under the floor
(lowest 0.00). Without the early catch the feet went to -1.95.

### Measured (throwaway harness, headless, driving the real game; deleted)

23/23. Three runs in a row were clean. One earlier run failed "knocked down:
their hands come off it" once and never again; it was a harness
grab-positioning miss, not seen since.

Windowed screenshots through the player's eyes: latched (the vat filling the
view, the sword away) and carried (the hall below, no claw in the view).

### Traps

- **A held player moves with the vat:** a collision exception between them,
  or the vat's own body blocks every push. A pull needs the player's room
  behind them tested.
- **A fast drop overshoots a per-frame check:** set the stop height exactly
  rather than taking the frame it was seen.
