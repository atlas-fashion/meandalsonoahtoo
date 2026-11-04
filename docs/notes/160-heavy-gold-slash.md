## 160. The sword's Q is a heavy slash that throws a slow gold wave (2026-11-03)

The user: "Replace the swords q ability with a heavier slash where the player has
a long wind up where he can't really move fast, the player should make the slash,
and the slash should shoot forward slowly, glowing gold. It should deal 80."
**The spin is gone** (supersedes the spin of note 15, its v2/v3 and the spin
lines of notes 24, 143 and 144; `SPIN_*`, `_spin_pose`, `_spin_yaw_at`,
`_spin_view_yaw`, `_spin_effort`, `spin_push`, `spin_stun`, `spin_stagger_chance`
and the trail's body-frame samples are deleted).

### What it does

- **Q with the sword** (`player.gd` `_start_heavy`, pose kind `&"heavy"`, in
  `ATTACK_POSES` so `attack_time_scale` 1.25 stretches it). Pose seconds, real =
  x1.25:
  - `HEAVY_RAISE` 0.32: blade hauled up over the right shoulder from wherever it
    was (`_heavy_arc(HEAVY_FROM_YAW 0.75, HEAVY_FROM_PITCH 0.9)`, hand lifted
    `HEAVY_LIFT` (0.02, 0.28, 0)). It stays in view, upper right.
  - to `HEAVY_WIND` 0.82: held, creeping back, a tremble that builds; the gold
    builds on the blade (`_blade_glow`, `_update_blade_glow`).
  - to `HEAVY_CUT` 0.95: the cut, high right to low left (to yaw -1.75, pitch
    -0.7) with a gold streak three times a cut's width (`HEAVY_TRAIL_COLOR`,
    `HEAVY_TRAIL_WIDTH`; the trail's third sample element now means "gold").
  - `HEAVY_FIRE` 0.885: the wave is thrown (`_fire_wave`), a punch of the view
    (`_swing_kick` 1.4, `_shake` 0.28) and a lurch of `HEAVY_LURCH` 2.2 m/s.
  - `HEAVY_HOLD` 1.02: control back (`_heavy_released`; a cut, the guard, another
    Q can start; `_bite_end` returns it). Home at `HEAVY_END` 1.36.
- **Slow through it**: `_attack_move_scale()` (both ground and air walking) is
  `heavy_move_scale` 0.15 of walking pace until `HEAVY_HOLD`, a cut's
  `attack_move_scale` otherwise. The look stays free (the spin locked it): the
  wave goes where they aim.
- **The blade never bites** (`_hit_window_open` false); the wave is the damage.
- **A blow taken before the wave is out cuts it off** (`_flinch`: `&"heavy"` and
  not `_wave_fired` -> `unblock`, as a cut). After the wave is out, it plays on.
- Camera effort `_heavy_effort()` (roll, pitch, drop, fov): leaning back to the
  right, the view drawn in by `heavy_effort_fov` 5 and trembling through the
  wind-up; thrown over to the left on the cut; eased out in the recovery.
- Exports: `heavy_damage` 80, `heavy_move_scale` 0.15, `wave_speed` 7,
  `wave_reach` 30, `wave_push` 9, `wave_stun` 0.5, `wave_stagger_chance` 1.0,
  `heavy_effort_roll/drop/fov`. Damage is `heavy_damage * weapon_damage_scale(&"sword")`,
  so the workbench upgrades raise it like the cut and slam.
- No cooldown beyond the stroke itself (the spin had none either).

### The wave (`scripts/sword_wave.gd`, `shaders/sword_wave.gdshader`)

- Launched by `SwordWave.launch` from the chest (`WAVE_HEIGHT` 1.05 m off the
  floor, `WAVE_AHEAD` 0.8 m ahead, pulled back if the player is against stone),
  **level** along the view's heading, rolled `WAVE_TILT` -0.45 to the cut's
  diagonal. Top-level node under the player's parent.
- Each physics tick: a ray down its middle against `geometry_mask` stops it at
  the first wall/door/vat (sparks burst, fades in `WALL_FADE` 0.22 s); a
  `BoxShape3D` the wave's width x height (`WIDTH` 3.0, `HEIGHT` 1.9, x
  `1 + SPREAD` 0.3 by the end of its reach) and the step's length is queried on
  `hitbox.collision_mask`; each body is hit once, only in line of sight of the
  wave, `swat()` bodies skipped, weak points `strike()`, otherwise
  `take_damage` + `knock` + `alert` + `hit_landed`. It passes through enemies.
- Look: a crescent ribbon built once (`arc_mesh`, 82 verts), bowed forward,
  thick in the middle and pointed at the tips; unshaded additive shader, hot
  white-gold front edge, gold tail, a flicker; `fog_disabled`; over 1.0 so glow
  blooms it. The blade's wind-up glow uses the same shader on two crossed quads
  under the sword model (`_make_blade_glow`, on the co-op viewmodel layer).
- `Graphics.effects` only: a gold `OmniLight3D` (range 5, no shadow) riding it,
  trailing sparks, the wall burst. The wave itself always spawns.

### Measured

Throwaway harness (sandbox, windowed, deleted):

```
wind-up walk max 0.64 m/s vs free 4.25          wave thrown 1.12 s after Q
wave speed 7.00 m/s, travelled 29.4 m, lived 4.23 s (reach 30)
three skeletons in line at 4/9/15 m: each lost exactly 80.0, once
one 5 m to the side: 0
flinch 0.3 s into the wind-up: pose cut off, no wave
in the maze, a wall 7.3 m off: wave stopped after 6.3 m
frame time, 3060 at 3440x1440, vsync off, 4 interleaved 2 s windows each:
  no wave  avg 12.22 ms  p99 13.58
  wave     avg 12.24 ms  p99 12.96
```

### Traps

- **The first wind-up pose was off screen.** Wound to yaw 1.45 with the hand
  drawn back 0.16 m, the hilt sat ~67 degrees right of centre and the whole
  sword left the view; screenshots showed nothing. Keep the wound blade in the
  upper right (yaw 0.75).
- **Sparks drew as metre-wide squares**: a `CPUParticles3D` with a 1 m
  `QuadMesh` and small `scale_amount` still drew 1 m quads (and the screen fell
  to 15 fps under the overdraw). Size the quad itself (0.045 m).
- **The blade glow at 0.045 of the blade's length was inside the blade** and
  invisible; it needs 0.1.
- Harness: enemies in the sandbox with `enemies_passive` still wander sideways
  off the wave's line -- freeze them (`set_physics_process(false)`), and a freed
  wave compares equal to `null` (section 4), so track it by a flag.
