## 15. Faster stab, blood on the view, healing over time (2026-10-08)

- **Spear stab**: `STAB_EVERY` 0.28 -> 0.13, out in 0.035 s, home by 0.11.
  Measured: 10 stabs in 1.3 s (was 5 in 1.4 s), still 10 each.
- **Drinking heals EVENLY** (`player._update_drink`): `heal_amount` over
  `drink_time` (40 over 3 s), applied straight to health; the HUD's "Used ..."
  line is raised once for the total at the end (`_finish_drink`), not per frame.
  **Cut short** (`_interrupt_drink`) by any attack key with a WEAPON in hand
  (LMB / Q / F -> `_attack_key_spills_drink`, the attack then goes ahead) or a
  haft strike, and by any hit that actually hurts (in `take_damage` after
  guards and invulnerability). What has flowed in is kept, the flask (used as
  the drink began) is gone, the held flask lowers (`held_potion.stop()`), and
  `drink_interrupted(healed)` -> HUD toast "Drink cut short +N". LMB with the
  POTION in hand is the drink, not an attack. Cage-skull DRAIN does not cut it
  short (it is not a hit). Measured: +6.9/13.6/20.2/26.9/33.6 at 0.5 s steps
  (expected 6.7/13.3/20/26.7/33.3), +40 in full; LMB with the sword at 1 s:
  +13.6 kept, no more, swing happened, potion gone; a 10 hit at 1.5 s: heal
  kept, hit taken, no more; LMB with the potion in hand: still drinking.
- **Blood on the view** (`shaders/blood_screen.gdshader`, `hud._update_blood`):
  none above `BLOOD_FROM` 75% health, full at `BLOOD_FULL` 10%; splats from
  the edges (further at the corners, broken into lobes), droplets just ahead of
  them, a few drips from the top, and the rim darkening -- throbbing with a
  heartbeat below `BLOOD_HEART` 35%. `_wound` eases up fast (a hit splashes it
  in) and down slowly (washes away over a drink). Gameplay info: not gated on
  effects; warmed at load like the dread. DARK blood on purpose: the first pass
  at a 0.42 red read as a glowing red picture frame in this red-lit level, with
  speckles over the whole view at 60% health. Cost: 16.65 vs 16.67 ms
  (vsync-capped, RTX 3060) -- not measurable there; not benchmarked on the P620.
- **Blood made much fainter; low health greys the world** (2026-10-08). Blood
  now starts at `BLOOD_FROM` 50%, reaches at most a fifth of the screen height
  in, alpha 0.12-0.35, near-black colours, fewer droplets, drips only below
  ~25%. The main low-health signal is now `player._health_saturation()`: below
  `low_health_desaturate_from` 50% the environment's `adjustment_saturation`
  falls (smoothstep) to `low_health_saturation` 0.12 of the base at 0 health,
  through the same `_update_colour` that ghost mode uses (ghost still pins it
  to 0). No extra pass; the HUD keeps its colour. Measured (base 0.92): 100 /
  60 hp 0.92, 45 hp 0.90, 25 hp 0.52, 8 hp 0.17; ghost 0.00; back to 0.92 at
  full health.
- **Spear stab: 4 a second, evenly spaced under spam** (2026-10-08).
  `STAB_EVERY` 0.25 (out 0.06, home 0.21). A click that comes before the next
  jab is due is HELD (`_stab_queued`), not dropped, and fired on the physics
  step it falls due (`_physics_process`), timed on the spear's own step clock
  `_stab_clock`; the next is always scheduled from the step it fires on, so
  nothing comes sooner than 0.25 s. A held click is forgotten if the spear
  stops being free (guard up, drink, ghost, dash, throw, another slot).
  Measured with real mouse events: clicks every 20-90 ms -> 13 stabs exactly
  0.250 s apart, 4.00/s, all 13 landing for 10; uneven 180-330 ms clicks ->
  gaps 0.25-0.33, never under 0.25; a held click dropped when RMB went up.
  Re-broken (early clicks dropped, as before): gaps 0.25-0.33 under the same
  frantic clicking, 11 stabs -- the test sees it.
- **Spin v2 (2026-10-08) -- SUPERSEDES the view-turning spin above.** The head
  no longer turns at all (`_spin_view_yaw` removed; `head.rotation.y` is only
  the haft camera's again). The BLADE sweeps the full circle instead:
  `_spin_pose` runs `_arc_pose` from `SWING_OPEN` round by -TAU (it takes any
  yaw; the hand follows), across the front, out of view behind, in again on the
  right. Level at `_spin_level()` = `_cut_pitch(0)` - `SPIN_DROP` 0.25: at eye
  height the circle and its trail are seen edge-on and the trail was a flat
  laser line along the horizon; at chest height it arcs across the lower view.
  The cut's white trail now runs for the spin too (`_update_sweep_trail`
  samples `_spin_pose` between frames, as it does `_swing_pose`).
  Knockback `spin_push` 11 / `spin_stun` 0.35 (a cut: 5.5 / 0.15); damage still
  `attack_damage`. Effort camera `_spin_effort()` -> (roll, pitch, drop, fov)
  composed in `_update_head` / `_update_dash_view`: wind-up leans back into the
  coil, dips and draws the FOV in (-3) with a building tremor; the drive leans
  into the turn (`spin_effort_roll` 6 deg), crouches (`spin_effort_drop`
  0.07 m), opens the FOV (`spin_effort_fov` +6) and trembles with the strain;
  release punches (`_swing_kick` 0.9) and shakes (`_shake` 0.2), then eases out.
  Measured: head yaw 0.00000 throughout, body yaw unchanged; front/right/
  behind/left hit once for 20; knockback 11.0 on all four vs a cut's 5.50;
  trail in all 36 ten-degree sectors round the player; roll 7.5 deg, drop
  0.14 m, FOV -2.3 / +6.0, back to exactly 75.000; worst frame 17.2 ms.
- **Spin v3 (2026-10-08, at the user's request) -- the VIEW spins again**,
  superseding v2's still head; v2's trail, double knockback and effort camera
  are kept. The head turns the full circle (`_spin_view_yaw` / `_spin_yaw_at`,
  coil `SPIN_COIL` 0.3 back first) and the blade is held at `SPIN_LEAD` -0.45
  leading it, at the lowered level pitch (`_spin_level`). Two things this needed:
  - **Trail in the BODY's frame during a spin.** In the head's frame a blade
    that turns with the head stands still and leaves no trail. Spin samples are
    `[point, time, true]` in the body's frame, the head's turn at each sample
    rebuilt from `_spin_yaw_at(at)`; `_update_sweep_trail` maps an entry by the
    body if it has the third element, else by the head.
  - **`_spin_view_yaw(delta)` looks a frame ahead.** `_update_head` runs before
    `_update_pose` advances the stroke by the same delta, so the head was a
    frame behind the blade and the streak ran on past it -- up to 0.71 m.
  Measured: head 6.28 rad and back to 0.00000, body yaw unchanged; four sides
  hit once for 20, knockback 11.0; trail in every sector on one circle (radius
  1.78-1.92 m, height spread 0.14 m); newest trail point 0.000 m from the blade
  (re-broken without the look-ahead: 0.713 m); FOV back to 75.000; worst frame
  17.1 ms.
- **Mouse look is ignored during the spin** (2026-10-08): `_unhandled_input`
  drops mouse motion while `_pose_kind == &"spin"` (not saved up), so the turn
  is always exactly one rotation and the body's yaw and pitch do not move.
  Measured with real mouse-motion events every frame (0 / +40 / -40 px, and
  15 px down): view turned 6.283 rad each time, body 0.0000, pitch 0.0000;
  mouse look normal before and after. Re-broken (guard off): 6.283 / 3.043 /
  9.523 rad. Harness traps: an injected event is handled the NEXT frame, so one
  injected in the spin's last frame lands after it; and measure the turn as
  body yaw + head yaw -- the camera's forward vector is skewed by the spin's
  lean and nod, and starting two frames in misses part of the coil.
- **Spin hands control back at the full turn; Q overrides a cut**
  (2026-10-08). `_spin_released()` (spin and `_pose_time >= SPIN_TURN` 0.62):
  from then the player has full control while the blade comes home -- mouse
  look (the drop in `_unhandled_input` stops), `_bite_end` is SPIN_TURN so a
  cut/spin/drink can start, `_start_block` lets the guard up, and
  `_attack_slows()` (used for walk speed and damping) is false. `_start_spin`
  no longer waits out a slash/chop: Q drops the cut where it is and the spin
  winds up from there, as the slam does; only a spin still turning refuses Q.
  Measured: mouse look, a spammed cut and a held guard each first took effect
  on the frame the turn completed (pose 0.617 -> 0.633 s; was 1.0); the turn
  still exactly 6.283 rad with the mouse moving; walk 4.25, 2.55 mid-turn,
  4.25 again before the blade was home; LMB then Q at 0.1 s into the stroke:
  chop -> spin, three enemies round the player all cut; Q at 0.3 s into a
  spin ignored.

