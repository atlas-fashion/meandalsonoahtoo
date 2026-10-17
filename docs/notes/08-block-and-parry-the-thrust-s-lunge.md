## 8. Block and parry; the thrust's lunge (2026-10-06)

- **Block = hold right click** (no Ctrl; Ctrl + right click is still the slam).
  The "slam" action's press starts it, its release (or `_check_block` finding
  the button up, the sword not in hand, a ghost, a cutscene...) ends it. Pose
  `block` (`_guard_pose`: hand at `GUARD_HAND`, blade up across the view to the
  upper left, flat to the front, up in `GUARD_UP` 0.1 s), `unblock` back to rest
  in `GUARD_DOWN`. Walking at `block_move_scale` 0.55; no cuts or thrusts while
  up. It can be raised out of a cut's recovery, never mid-stroke.
- **`take_damage(amount, blow, attacker = null)`** -> `_guard(blow)`: only blows
  from within `block_arc` 75 deg of the front count. Within `parry_window` 0.5 s
  of the guard going up: PARRY -- `parry_damage_taken` 0.25, the attacker gets
  `apply_knockback(away * parry_push 14, parry_stun 0.9)` (enemies keep that in
  `_knockback`, not `velocity`), a hit-stop `_slowmo(0.15, 0.09, 0.22)` and the
  purple `_guard_flash`. After the window: BLOCK -- `block_damage_taken` 0.5 and
  a small warm flash. Signal `guarded(parried, attacker)`. enemy.gd (skeletons,
  the boss) and mimic.gd now pass themselves as the attacker; bomb blasts pass
  none (blockable, nothing to throw back).
- `_guard_flash`: additive billboard ring + core (no depth test, so it shows over
  the guard), and with `Graphics.effects` CPU sparks and a short light. Played
  on the REAL clock so the hit-stop does not drag it. `_warm_guard_flash` draws a
  speck of each material 0.4 s after `_ready`.
- Harness trap (again): a screenshot's ~1 s stall lands in the NEXT frame's
  delta, and anything on the real clock (this flash, ignore-time-scale tweens)
  jumps straight to its end -- the first parry screenshot showed no flash at
  all. Shoot such effects before any other screenshot, or after one, wait.
- **Thrust**: `thrust_lunge` 5.5 -> 9.5 and given at `THRUST_DRAW` as the blade
  is driven (it used to be given at the start of the draw, where the damping
  bled it off before the blade moved); timeline DRAW 0.28 / HIT 0.40 / HOLD 0.52
  / END 0.95, and `_bite_end` is THRUST_END -- a thrust cannot be cut short to
  chain another. Measured: 1.26 m forward from standing.
- Measured in a harness: no guard 40 of 40; parry 10 of 40, attacker thrown at
  14 m/s, time scale 0.15 then back to 1, flash freed; block after the window
  20; from behind 40; left click does nothing while up; release -> unblock ->
  idle; a real skeleton's own blow on a held guard: 7 of its 14, credited to it.

