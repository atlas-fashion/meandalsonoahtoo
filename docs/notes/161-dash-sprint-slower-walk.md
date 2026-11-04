## 161. Ghost mode replaced by a dash; Shift a sprint; a slower walk (2026-11-04)

The user: replace ghost mode with "a very polished dash", instant, a fairly long
animation that must finish before the next, 14 invulnerable frames so dodges
have to be timed, on Left Ctrl; Shift a sprint "not too much faster than
walking", the walk slowed so the sprint is the old walking pace, and the two
blending perfectly smoothly. Supersedes ghost mode everywhere (notes 6.19, 9,
91, 113's ghost parts; 143/145 "ghost stays free" now means the dash).

### Keys (project.godot)

- "dodge" is **Left Ctrl** (physical `KEY_CTRL`, `location` 1 = left; right Ctrl
  does nothing) and L3 on a pad, as before.
- New "sprint" action: **Shift** (held). No pad button is free, so on a pad the
  sprint is the left stick pushed past `pad_sprint_tilt` 0.92.
- Noclip (note 152): faster is now the sprint (Shift / full stick); Ctrl still
  flies down (no dash while flying).

### The dash (scripts/player.gd)

`_update_dash(delta, down)` runs each physics tick in play, before the body moves:
ages `_dash_age` (game seconds on the physics clock), ends the burst
(`_end_dash`) and starts one (`_start_dash`) on a fresh press.

- **Instant**: `_start_dash` sets the velocity on the first player tick after the
  press, at `dash_speed` 34 m/s, along the move input (flat, world), committed.
  It eases out squared over `dash_move_time` 0.24 s to `_dash_exit`: the pace it
  was walking at if a direction was held (it hands straight over to walking),
  0 from a stand -- **a step straight back** (no direction held) that plants.
  Level in the air (y held at 0 for the burst).
- **Distance**: from a stand 3.0 m back, dead stop. Walking forward, 4.86 m
  in 0.65 s against 2.15 m walking (+2.7 m).
- **The wait**: another dash only once the whole `dash_time` 0.65 s has run
  (`dodge_ready`). A press up to `dash_buffer` 0.12 s early is held and fires on
  the tick it may; a press earlier than that is dropped.
- **14 invulnerable frames**: `is_dash_invulnerable()` is `_dash_age + DASH_EPS <
  dash_iframes` (14 / 60 = 0.233 s), game time, so the same at any frame rate.
  Inside it `take_damage` returns before the guard (any blow, the Remnant's too,
  with no grace window after, `blows_dodged`++, `blow_dodged` signal),
  `knock_down` and `apply_knockback` return, and `beam_hit` takes nothing and no
  slow. After it, everything lands in full: ghost mode's 0.2 damage share is gone.
- During the burst (`_dashing`): passes through enemies (the old phasing,
  `_phase_window_open`), no attack, block, slam, heavy slash, spear or axe move,
  jump or rat deploy -- the same gates `_ghosting` had. A sword click in the burst
  is swung the moment it ends (`_dash_attack_queued`).
- Not started while drinking, swimming, slamming or getting up (`down`), in the
  heavy slash's wind-up or a scripted pose, `hands_busy`. A flinch does not stop
  it (the way out of the next blow, note 143).
- Only a press made in play (note 113, kept): `Coop.just_pressed` is an edge, so
  a key held through a menu, a scene, a pause or a respawn never fires; nor the
  first frame back (`_play_resumed`, was `_ghost_resumed`), nor Alt / Win + Ctrl
  (`_system_chord` no longer counts Ctrl). `_ghost_locked` and the focus-out
  notification are gone: an edge needs no lock.
- `_cancel_dash()` (scenes, hiding, slam, noclip, respawn) ends the burst and its
  frames; the wait runs on.
- The look, on the render clock (`_dash_vis`, so no 60 Hz stepping): the view
  opens out `dash_fov_kick` 9 deg and banks into a sideways dash, both decaying
  over `dash_effect_time` 0.45 s (was 0.32; no longer HELD as for the ghost);
  the head drops `dash_dip` 7.5 cm in 0.05 s and comes back up over the whole
  0.65 s (`dash_motion()`), tipping `dash_pitch_degrees` 1.6 with the dash's
  forward part; the weapon in hand is swept down `dash_weapon_dip` 0.14
  (`weapon_dip`, so the sword, spear and axe all take it); the world drains to
  `dash_saturation` 0.35 of its colour exactly while the frames last.
- HUD: the old ghost bar is the dash's wait (`dodge_charge` 0 -> 1 over 0.65 s,
  lit when ready). The inventory's meter is "Dash", its key rows "Dodge dash" and
  "Sprint". The intro's ghost lesson is "Dash  ·  2 times" (`dash_count`); the
  walk lesson mentions Shift.

### Sprint and walk

- `move_speed` 4.25 -> **3.3** (walking), `sprint_speed` **4.25** (the old walk).
  `_pace()` = lerp(walk, sprint, `_sprint_k`); `_sprint_k` follows Shift (with a
  direction held) on a critically damped spring (`_update_sprint`,
  `sprint_blend_time` 0.3), so the pace leaves and arrives with no corner and
  turns back the same way part-way. The view opens `sprint_fov_kick` 2.5 deg.
- Everything that read `move_speed` as "walking pace" in player.gd reads
  `_pace()`: ground, air, swimming, the spear dash's exit. The scripted scene
  walk keeps `move_speed`.
- Berserk keeps its absolute pace, `berserk_speed` 10.625 m/s (= ghost mode's
  2.5 x the old 4.25, note 91), walking or sprinting; `berserk_acceleration_scale`
  2.0 is the old `ghost_acceleration_scale`.
- The Remnant (stalker.gd `_hunt_speed`) runs at 1.35 x `sprint_speed`, so its
  5.74 m/s is unchanged. Back-to-back dashes outrun it (about 8 m/s).

### Measured

Throwaway windowed harness in the sandbox, real key events (deleted):

```
walk 3.300 m/s     sprint 4.249 m/s     back to walk 3.301
walk -> sprint 90% in 0.60 s; largest change a tick 0.039 m/s, of that 0.0094
  (every 6th tick: 3.30 3.44 3.67 3.86 4.01 4.10 4.16 4.20 4.22 4.23)
dash: on the player's first tick after the press, at 34.00 m/s
  speed by tick 34.0 29.4 25.2 21.3 17.7 14.5 11.6 9.0 6.7 4.8 3.2 1.9 0.9 0.3 0
backstep 3.01 m, dot with straight back 1.000; W held: forward, 4.86 m in 0.65 s
a press 0.3 s in: nothing; a press 0.55 s in: the next dash 39 ticks (0.65 s) on
take_damage every tick of a dash: 14 negated from its first, 0 of the next 25 (x2)
knock_down in the frames: still standing; just after a dash: down
right Ctrl, Alt + Ctrl, Ctrl held through a menu: no dash; a fresh press: dash
a click in the burst: no swing in it, a swing as it ends
```

Clean `--quit-after` windowed runs into the maze and into the intro: no errors.
Frame time: nothing drawn is added (no nodes, lights or passes), so no benchmark.

### Traps

- **The 15th frame.** 14 physics deltas of 1/60 summed can land a hair under
  14/60; compared without `DASH_EPS` the window was 14 or 15 frames from run to
  run, and the 0.65 s wait likewise.
- `physics_frame` fires before the nodes' `_physics_process`, so a harness that
  awaits it reads the player one tick behind -- "the dash began 1 signal after
  the press" is the player's very next tick.
- From a stand, easing out to the walking pace slid on 0.4 m after the burst
  (3.9 m) with nothing held; a backstep has to ease out to 0.
