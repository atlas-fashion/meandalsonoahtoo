## 91. Berserk as fast as ghost mode (2026-10-20)

The user: "Berserk should make you as fast as ghost mode."

- `player._axe_speed()` now returns `lerpf(carry, ghost_speed_scale,
  axe.berserk_amount())`: while berserk the walking-pace multiplier is ghost
  mode's **2.5** outright, in place of the axe's `CARRY_SPEED` 0.65 -- the
  axe's weight does not apply in berserk. Supersedes note 84/87's
  `BERSERK_SPEED` 1.5 (the constant is gone from axe.gd). It still ramps in
  over the roar (the player is planted then) and out over berserk's last
  0.5 s. The other slows (swinging, blocking, drinking, wading, beams) still
  multiply it, as they do walking; ghost mode has none of those.
- **Acceleration too:** on the floor, `_physics_process`'s ground `damp` is
  multiplied by `lerpf(1, ghost_acceleration_scale, berserk_amount())`, so
  berserk reaches that pace as quickly as a ghost does (2 x 14 m/s2). Without
  it, coming out of the planted roar it took ~0.75 s to get up to speed and
  measured 10.15 m/s against the ghost's 10.59 over the first half second.

**Measured** in a throwaway sandbox harness (headless, real physics, holding
move_forward): ghost 10.59 m/s; axe in hand 2.76; berserk 10.63 (early and
late in it); after berserk 2.76 again. Clean `--quit-after 900 --
--skip-title` run: no errors.
