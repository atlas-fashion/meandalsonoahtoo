## 87. The heavy axe: a delayed vertical chop for 60, a planted throw, 25% slower carrying it (2026-10-20)

The user: "The axe should have some attack delay, and a quick swipe down, it
should feel heavy to the player. It should deal 60 damage per hit. The swipe
should be fairly vertical, so the player cant sweep a bunch of enemies while
using it. The regular attack should be every .75 seconds. The mid attack
should stick for 2 seconds, and the player should stop moving .5 seconds
before throwing the axe to "wind up" the throw. The goal is to make the axe
feel very heavy and cumbersome, but very strong. The player should be .25%
slower when holding the axe." Read as 25% slower (".25%" would be
unnoticeable). **Supersedes note 85 entirely** (no alternating sides; 0.75 s;
2 s stick) and note 84's slash values and arc.

All in `scripts/axe.gd` unless named.

- **The chop:** one swing plane only, nearly vertical: `_swing(a)` turns the
  hand round `SWING_PIVOT` (0.14, -0.1, -0.3) at `SWING_HAND` 0.3 m in the
  plane of `e1` (0.12, 1, 0.3), straight up and a touch right, and `e2`
  straight ahead, from `SWING_FROM` -35 deg (raised behind the shoulder) to
  `SWING_TO` 150 deg (down past the crosshair). `slash_side` and `SLASH_ARC`
  are gone.
- **Delay:** `SLASH_WIND` 0.32 s raising it, then `SLASH_CUT` 0.1 s down (the
  blow lands at its end), `SLASH_BACK` 0.3 s recovery. One per `SLASH_EVERY`
  0.75 s (berserk halves both, as before).
- **One body per chop:** `_slash_strike` takes only the NEAREST damageable
  body in a lane `SLASH_HALF_WIDTH` 0.5 m either side of the crosshair (flat,
  measured from the eye), from -0.3 to `SLASH_REACH` 2.6 m ahead, line of
  sight checked. `SLASH_DAMAGE` 60, knockback 5 m/s for 0.3 s along the view,
  stagger chance `SLASH_STAGGER` 0.6.
- **Weight:** the view jolts as it lands (`player._swing_kick` 1.0 on a hit,
  0.6 on a miss; `player._shake` 0.3 / 0.15).
- **Throw:** `THROW_WINDUP` 0.5 s (was 0.22) with the player planted:
  `axe.is_winding_up()` (WINDUP pose, not yet released) joins
  `is_roaring()` in `player._axe_planted()`, which zeroes horizontal velocity
  in `_physics_process`. `THROW_DAMAGE` 60, `STICK_TIME` 2 s.
- **Carrying it:** `CARRY_SPEED` 0.75. `player._axe_speed()` (replaces
  `_berserk_speed`) multiplies walking pace, floor and air, by it while the
  axe is the held item and in hand -- not while it is thrown -- times the
  berserk factor (so berserk with the axe is 0.75 x 1.5 = 1.125 x normal).

**Measured** in a throwaway sandbox harness (headless, real physics), 13/13:
walking 3.19 m/s with the axe against 4.25 with the sword (x0.75), back to
x0.75 once the thrown axe was caught; one chop 60.0, landing 0.29-0.40 s after
the click; spammed 3 s, 4 chops 0.73-0.77 s apart; two skeletons shoulder to
shoulder, one cut; a skeleton 1 m to the side (29 deg, inside the old 65 deg
arc) not cut; walking forward then Q: 0.00 m/s until the axe left the hand
0.51 s later; the throw 60.0; left its target after 2.00 s; berserk chops
0.37-0.39 s apart. Re-broken (`CARRY_SPEED` 1.0, `THROW_WINDUP` 0.1,
`SLASH_HALF_WIDTH` 1.5) the matching checks failed. Screenshots (Xvfb,
compatibility) showed the axe raised high at the top right in the wind-up and
coming down through the crosshair. Clean `--quit-after` run: no errors.

**Traps.**
- A chop's knockback carries a skeleton out of the 2.6 m reach, so a harness
  spamming slashes at a free target counts one hit. Pin the target.
- Sandbox enemies with `enemies_passive` still wander: a target placed 8 m off
  had drifted 1.5 m sideways by the end of the 0.5 s wind-up plus a walk, and
  the throw (aimed at release, along the view) flew past. Real players re-aim;
  a harness has to pin the target until release.
- `SceneTree.physics_frame` is emitted before the nodes' `_physics_process`,
  so the first velocity read after a call is last frame's. Skip a frame.
