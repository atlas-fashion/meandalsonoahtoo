## 105. The booth lower, the kick and a lever you flip, a vat that really blocks the way in, the surgeon to fight (2026-10-25)

The user, after note 104:
- "Make the control room lower, so the player can actually jump onto the
  landing by the control room door. Make the cutscene start when the player
  interacts with the control room door."
- "The cutscene should be the player kicking the door down with such force,
  that it sends the surgeon out the window, and the surgeon lands on the
  ground. The player should then be able to interact with the lever, actually
  flip it, and the system powers down."
- "Give the arm a larger swing back before letting go of the mechanical piece
  that it throws at you."
- "there are no enemies for the claw to ferry."
- "the cutscene for the beginning of the surgery room needs to start when the
  player actually starts pushing the blocking vat. the blocking vat needs to
  actually block the player, so to get in the player has to push it to get
  in."
- "the player should have to fight the surgeon after the claw gets
  depowered. make infrastructure for that, and ill give you details later."

### The booth lower; E at the door (`surgery_control.gd`)

`BOOTH_FLOOR` 3.6 -> **2.9**. A vat's top is 1.97 and a jump rises 1.28 m
(`jump_velocity` 5, gravity 9.8), so from a vat shoved against the landing a
jump gets onto it. Measured: a running jump off a vat lands the player at
2.90. Everything in the booth hangs off BOOTH_FLOOR. The roof is now at 5.2,
and the intake under it has 2.45 m clear (the casket is 2.2).

The vat trigger and the scripted climb from note 104 are gone. Instead:
- **The door:** a Prompt "E Kick in" on the door (`Interact.chooser(_door,
  2.4, 1.6, 3.0, 0.15)`) while the machine runs.
- **The lever:** "E Pull the lever" (`chooser(_lever, ..., [_handle])`) once
  the door is in and the machine still runs.

### The kick (`_storm`)

1. Square up.
2. The kick (wood_door.gd's leg).
3. `_burst_door`: the debris is pushed in at 2.2 x, in 0.3 slow motion. The
   same moment `_fling_surgeon`: he goes out along the booth's length (+Z),
   which is the way the door flies.
4. He goes through the booth's FAR window (`_break_window`: `_end_pane`
   hidden, a spray of glass along his flight) and down onto the flags at
   `_landing_spot`, his "die" clip playing, dust and a shake.
5. He lies there (`lie_down`) and control comes back. The machine is still on.

`_landing_spot` is the first of seven spots outside that window clear of the
vats. One landed against a vat and could never get round it.

### The lever (`_build_lever`, `_pull_lever`)

It is note 98's kit `leverbox` with its `handle`, at LEVER_SCALE 0.85, against
the booth's back wall at the far end, facing in.
- E tweens the handle HANDLE_UP -0.35 -> HANDLE_DOWN 2.4 rad, with an
  overshoot.
- Sparks fly, `_throw_lever` darkens the console, and `power_off(&"control")`
  drops the claw.
- `surgery.gd _on_depowered(&"control")` -> `control.surgeon_rises()`: after
  2 s he gets up and the fight starts.

### The surgeon as a boss (`scripts/surgeon_boss.gd`)

**This is infrastructure:** his attacks and the fight's design are to come
from the user.

**His body.** A CharacterBody3D (capsule 0.38 x 1.85, layers 1 | 4) in groups
"boss" and "surgeon", with the Meshy model under it. `surgery_control.gd
_build_surgeon` makes it, and `_down_to_the_hall` reparents it into the hall's
frame when he leaves the booth. The model faces its +Z (its toes point that
way).

**States:**
- AT_WORK: at the console.
- FLUNG: the kick moving him.
- DOWN: lying in the hall.
- WAITING: on his feet in the hall. The fight starts as soon as a player is
  in the hall (`surgery.in_hall`).
- RISING: RISE_TIME 1.6 s, the "alert" clip.
- FIGHT: `engaged`. The HUD's boss bar shows (hud.gd `_engaged_champion`
  finds group "boss" with `engaged`, reading `display_name` "THE SURGEON",
  `health` and `max_health` MAX_HEALTH 600). He can be hurt (`take_damage`
  only in FIGHT; red sparks). `apply_knockback` gives a quarter push.
- DEAD: the "die" clip, collision off, `defeated`.

**His placeholder fight.** He faces the nearest player (TURN_RATE 5) and
walks at them at WALK_SPEED 1.6, stopping at STOP_AT 1.8 m. He has no attacks.
The level's navmesh does not know about the vats (they move), and he walked
into them and stood there. So he finds his own way:
- an AStarGrid2D over the hall floor (GRID_CELL 0.5);
- every vat (its radius plus his) and the table marked solid, re-planned every
  REPLAN 0.4 s;
- the hall's fixed things (booth posts, intake crates, frames) found once by
  physics shape queries, layer 2, not the vats or bodies (`_find_static`);
- a goal on a vat or the table moved to the nearest free cell.

Measured: 6.1 m from the player to 1.8 m (stopped) in under 12 s, round the
vats. Before the grid he got stuck behind vats and closed nothing.

**When the fight comes.**
- **The booth route:** the lever -> he rises.
- **The crystal route:** `power_cut` (alert, in the booth). Then `leave()`,
  run while the player climbs out with the screen black, now brings him down
  into the hall (`wait_at(_boss_spot())`, the door swung open) instead of
  hiding him (note 102). He is WAITING, and the fight starts as the player
  comes up.

**The bars and the fight.**
- The bars now stay up when the machine dies (`_on_depowered` no longer
  lowers them).
- `fight_started` -> `_want_bars` (raised once the doorways are clear).
- `defeated` -> `lower_bars`. The room is done.

**Saves and resets.**
- **World reset** with the machine off (`on_world_reset` ->
  `control.reset_boss`): he is whole and WAITING at his spot and the bars are
  down, until a player comes back in. If the crystal was pulled and they died
  before climbing out, he comes down then (`leave`).
- **Save:** "surgeon_dead" [x, y, z, yaw] (room frame) when he is dead.
- **Restore:** off by the booth -> `set_thrown_now` (door and far pane gone,
  lever down, him waiting). Off by the crystal -> `set_taken_now`, then
  `leave()`. Then `_restore_surgeon` -> `restore_boss(true, at)` if dead.

### The vat across the way in really blocks it (`surgery.gd`, `surgery_vat.gd`)

**Why it failed before.** Measured with raycasts: the way in is a corridor
3.38 m wide that opens at the wall face into the hall's 6 m arch. Note 104's
vat stood inside the hall, where there is room on both sides, so the player
simply walked round it.

**Where it stands now.** In the corridor's mouth, ENTRY_OUT 1.2 m outside the
wall face, at ENTRY_GROW 1.26 x size: radius 1.45, model and lid scaled to
match. The vat now has a `grow` (set before it enters the tree), `radius`
and `height`; `_sway` keeps the model's scale.

A capsule the player's size (r 0.4) fits nowhere across it. A normal-sized vat
would also block there (0.54 m gaps against a 0.8 m player); the size is margin
and weight.

Entry vats are `entry` and the claw never fetches from them.

**The scene starts on the shove.** The vat emits `shove_started(player)` when
a shove begins (`_pusher`). `_on_entry_shoved(p, k)` starts the scene with the
claw asleep and the scene not yet played; the old distance trigger
(`_check_intro`) is gone. The scene shoves the vat in two legs (`scripted_push`
1.5 s each), the player behind it, then has them walk in past it:
1. Straight in out of the corridor, to 0.6 m inside.
2. On to 1.9 m in and 1.8 m to whichever side is freer.

Measured: standing at the vat starts nothing; walking into it starts the scene
on the first shove. The scene takes 12.9 s, ending with the vat 1.9 m into the
hall, the bars up, and the player inside with control back.

### The pens were empty in the sandbox

maze.gd `_populate` (which calls `surgery.on_world_reset`, where `stock_pens`
ran) returns early in the sandbox. `_process` now stocks the pens once the
maze `is_built` (`_stocked`). Measured: 6 in both the game and the sandbox
(the sandbox had 0).

### The bigger wind-up (`surgical_table.gd` FETCH step 3)

Over FETCH_WIND 0.85 s:
- the trolley is hauled FETCH_HAUL 1.6 m back from the player;
- the arm is swung back FETCH_SWING 1.15 on its hinge (the wrist out from
  under the trolley, `_o` driven directly);
- it shakes as it reaches the top.

Then it whips through (FETCH_WHIP 0.22 s) toward them and lets go half way.
Measured: swung back 1.04 m, let go 0.95 s into it (was 0.9 m of trolley and
no swing, 0.55 s).

### Measured (throwaway harness, headless, driving the real game; deleted)

31/31, twice:
- six in the pens; no gap past the entry vat;
- the scene starts on the shove, not on approach;
- the wind-up;
- the jump onto the landing;
- the prompt and E at the door; the door broken, him on the flags, the far
  pane gone, control back with the machine on;
- the lever prompt; the handle flipped 2.75 rad; the machine down; the bars
  still up;
- the fight on 3.2 s later with the boss bar up;
- he reaches the player round the vats; he can be hurt;
- a world reset: whole, waiting, bars down; back in, the fight again with the
  bars up;
- dead: the bars down; saved "booth" and "surgeon_dead".

Re-broken (BOOTH_FLOOR 3.6) the jump fails, as it should.

Windowed screenshots (another game held the GPU again):
- the vat filling the corridor mouth;
- the lower booth;
- the door from the landing;
- the lever up and pulled;
- "THE SURGEON 600 / 600" over him in the hall.

### Not done -- for the user's details

- His fight: attacks, phases, how he is hurt or staggered, what he drops.
- Clips: a walk, his attacks, a hit, getting up. The model has only "work",
  "alert" and "die", so for now he slides upright when he walks.
- His health (600) is a placeholder.

### Traps

- **The level's navmesh does not have the vats** (they move). Anything that
  has to walk round them needs its own way (the surgeon's grid), or it walks
  into them.
- **The sandbox never calls `on_world_reset`:** room setup that hangs on it
  never runs there.
- **The surgery's ways in are corridors 3.4 m wide** opening into a 6 m arch
  at the wall face: something meant to block one has to stand in the corridor.
- **A new script's `.uid`:** `godot --headless --path . --import` writes it
  (note 92's missing uid).
