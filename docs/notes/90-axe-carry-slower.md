## 90. A little slower carrying the axe (2026-10-20)

The user: "Make the player a little slower when using the axe."

`scripts/axe.gd` `CARRY_SPEED` 0.75 -> **0.65** (35% slower with the axe in
hand; supersedes note 87's 0.75). Read only by `player._axe_speed()`, so it
still applies only while the axe is held and in hand, and berserk still
multiplies it by `BERSERK_SPEED` 1.5 (0.65 x 1.5 = 0.975 x normal pace).

**Measured** in a throwaway sandbox harness (headless, real physics, holding
move_forward): 4.25 m/s with the sword, 2.76 m/s with the axe, ratio 0.650.
