## 88. The axe a little heavier; the chop's white streak (2026-10-20)

The user: "Make the axe feel a little heavier, and also give the slash down an
effect like the swords slash effect: the little white line." Builds on note 87
(its values stand unless named here). All in `scripts/axe.gd`.

**Heavier** -- the cadence (`SLASH_EVERY` 0.75 s, 60 damage) is unchanged; the
weight is in the feel:
- `SLASH_WIND` 0.32 -> **0.36 s**, and the last `WIND_HANG` **22%** of it is
  spent hanging at the top (`_pose_transform` WIND: hauled up over the first
  78%, then held) before the drop.
- **Hit-stop:** a chop that lands holds the swing where it met the body for
  `HIT_STOP` **0.07 s** (`_hold_until`; `_process` stops advancing `_pose_t`;
  halved under berserk with everything else).
- **The view is dragged down after the blow:** `_slash_strike` sets the
  player's landing dip (`_land_kick` 1, `_land_strength`
  `CHOP_DIP_HIT` **0.5** / `CHOP_DIP_MISS` **0.28**; a deeper dip already
  running is kept). At 0.5 that is ~5.5 cm down and 1.6 deg of pitch, over
  `landing_kick_time` 0.32 s, on top of note 87's kick and shake.

**The streak** (`_update_trail`): the sword's slash trail (player.gd
`_update_sweep_trail`) rebuilt for the chop -- an `ImmediateMesh` ribbon
`AxeTrail` (top level, the player's `SweepTrail` material borrowed, a matching
fallback `_mat(&"trail")`), through the middle of the edge (`TRAIL_AT`), kept
in the HEAD's frame so the kick and dip do not leave it behind. Sampled from
the swing itself every `TRAIL_STEP` 0.04 of the cut's progress (`_cut_angle`,
shared with the pose) -- 185 deg in 0.1 s is a third of the arc a frame, and
frame-to-frame chords would cut inside it. Width `TRAIL_WIDTH` 1.6 x the
sword's; life, alpha and the on/off switch are the player's
`sweep_trail_life` / `_alpha` / `_enabled`, and like the sword's it is off
without `Graphics.effects`. Cleared in `reset()`.

**Measured** in a throwaway sandbox harness (headless, real physics), 15/15:
a miss -- no hold, dip 0.28, trail up to 32 samples, on screen, gone 1 s
later; a pinned skeleton -- 60 damage, swing held 0.067 s, dip 0.50, trail
shown, the blow 0.417 s after the click (was 0.29-0.40); effects off -- no
trail. The streak's screen path (1280 x 1280 view) comes down from above the
top right to the bottom, passing ~70-90 px right of the crosshair: the axe's
own line, since its swing plane pivots by the right shoulder (`SWING_PIVOT`
x 0.14), unlike the sword's, which is fitted through the crosshair. Clean
`--quit-after 900 -- --skip-title` run: no errors.

**Trap.** In a `--script` harness the autoloads are not in the tree during
`_initialize`: `Sandbox.start()` there fails on `get_tree()`. Await a
couple of process frames first.
