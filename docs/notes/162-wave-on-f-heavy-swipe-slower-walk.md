## 162. The gold wave is the sword's F (130, the slam's 20 s); Q a delayed heavy swipe; the walk 2.5 (2026-11-04)

The user: "Slow down walking even more, but leave the sprint speed the same. there
should be a very noticable difference in speed. make the swords current "q"
ability the ult (f), and make it deal 130 damage. I will use the slam later for
another weapon. Keep the slams cooldown on this ability. Make a heavy delayed
swipe the "q" ability for the sword." Supersedes note 160's key (Q), damage (80)
and "no cooldown"; note 161's walk (3.3).

### The wave slash on F (scripts/player.gd)

- Note 160's stroke, unchanged in look and timing, renamed for its new place:
  pose kind `&"wave"` (was `&"heavy"`), `_start_wave`, `_wave_pose`, `_wave_arc`,
  `_wave_effort`, `WAVE_RAISE` ... `WAVE_END`, `WAVE_TRAIL_*`, `WAVE_LURCH`,
  exports `wave_damage`, `wave_move_scale`, `wave_effort_*` (were `heavy_*` /
  `HEAVY_*`). The blade glow node is `WaveGlow`.
- F ("slam" action) with the sword starts it. **`wave_damage` 130**
  (x `weapon_damage_scale(&"sword")`, so the workbench raises it).
- **The slam's cooldown and clock**: `slam_cooldown` 20 s on `_slam_ready_at`.
  `_start_wave` refuses while the clock runs; `_fire_wave` sets it, so a wind-up
  cut off by a blow before the wave is out costs nothing. `slam_charge()`, the
  inventory's meter (now "Wave", gold) and the F icon all read that clock.
- F overrides a cut or a heavy swipe's wind-up, as Q used to over a cut.

### The slam, kept unbound

`_start_slam`, `_land_slam`, the marker, ring, pose and every `slam_*` export are
untouched. The sword's F only reaches it with **`sword_slam` = true** (export,
default false); `attack_cooldowns` then shows the slam icon on F again. For the
weapon it goes to later: call `_start_slam` from that weapon's F with the same
gates as the `sword_slam` branch in `_unhandled_input`.

### The heavy swipe on Q

Pose kind `&"heavy"` (`_start_heavy`, `_heavy_pose`, `_heavy_effort`,
`_heavy_lunge`), in `ATTACK_POSES`, so x1.25 `attack_time_scale`. Pose seconds:

- to `HEAVY_RAISE` 0.16: carried round the arc to cocked back over the right
  shoulder (yaw `HEAVY_FROM_YAW` 1.05, pitch 0.32, hand `HEAVY_LIFT`
  (0.06, 0.13, 0.08)); it stays in the right of the view (screenshot checked).
- to `HEAVY_WIND` 0.47: **the delay** -- held, creeping 0.12 rad further back
  with a slight tremble. The player walks at `heavy_move_scale` 0.35.
- `HEAVY_WIND` -> `HEAVY_CUT` 0.6: flat right to left to yaw `HEAVY_TO_YAW` -1.95
  (wider than a cut's 1.66), the pitch eased onto `_cut_pitch` by the middle, so
  it passes through the crosshair 2 m out like a plain cut. At `HEAVY_WIND` a
  lurch of `heavy_lunge` 5.5 m/s along the view, `_swing_kick` 1.3, `_shake` 0.12.
- Bites from `HEAVY_BITE` 0.475 to `HEAVY_HOLD` 0.68 through `_resolve_hits`, for
  `heavy_damage` 45 (cut 20) with `heavy_push` 9, `heavy_stun` 0.45 and
  `heavy_stagger_chance` 1.0. A white streak `HEAVY_TRAIL_WIDTH` 1.8 a cut's width
  (the trail sample's third element: true = the wave's gold, false = this).
- Home by `HEAVY_END` 0.95. Camera: a smaller copy of the wave's lean and crouch.
- **Committed** until `HEAVY_HOLD`, like the wave: `_committed()` (wave or heavy
  before its `_bite_end()`) gates the guard, the dash, another Q and the queued
  cut, replacing `_wave_released`/`_heavy_released`. A blow taken before
  `HEAVY_WIND` cuts it off (`_flinch`, to `unblock`).
- Icon: the blade cocked back and a doubled wide arc (attack_icons.gd `&"heavy"`;
  the gold crescent is now `&"wave"`). Intro lessons: "Heavy swipe" (Q) and
  "Wave slash" (F, `_setup` clears `_slam_ready_at` so it never waits on an
  earlier wave). Inventory: "Heavy swipe 45", "Wave slash 130, a wave", "Wave
  cooldown 20 s"; controls rows likewise.

### Walk and sprint

`move_speed` 3.3 -> **2.5**, `sprint_speed` 4.25 unchanged: the sprint is 70%
faster (was 29%). `scene_walk_to` keeps 3.3 (`SCENE_WALK_SPEED`), the pace its
scenes and 4 s timeouts were made at.

### Measured

Throwaway windowed harness in the sandbox (deleted):

```
walk 2.500 m/s   sprint 4.249 m/s (Shift key event)   back to walk 2.501
heavy swipe, target 2 m ahead: hit 0.68 s after Q, 45.0 damage; walk in the wind-up 0.88 m/s (0.35 x 2.5)
a blow 0.2 s into the wind-up: pose cut off, 0 damage (45 when the blow did not flinch: not vacuous)
F: pose 'wave', no slam; target 5 m ahead lost 130.0; clock 18.6 s left 2.5 s on
icons: [wave 18.6 F] [heavy 0 Q] [slash 0 LMB]
F again at once: nothing; F with the clock cleared: a wave
```

Clean `--quit-after` windowed runs from the title and into the maze: no errors.
Frame time: the swipe draws nothing new (the cut's own trail, wider), so no
benchmark; the wave is note 160's (+0.02 ms).

### Traps

- `_action_held` reads physical keys, so a harness that `action_press`es
  "sprint" never sprints; send an `InputEventKey` with `physical_keycode`.
- `take_damage` only flinches with an `attacker`, and not in `Sandbox.player_god`.
