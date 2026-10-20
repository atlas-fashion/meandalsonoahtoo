## 85. The axe: alternating slashes every 0.5 s, 1 s in its mark (2026-10-20)

The user, after trying note 84's axe: "Make the axe slash mirror alternating
from side to side, and make the slash hit every .5 seconds. Make the axe stay
in the enemy for 1 second before returning." Supersedes those three values in
note 84.

- **Alternating:** `axe.slash_side` flips on every `_fire_slash`: 1 is the
  forehand (up right to down left), -1 its mirror (up left to down right).
  `_swing(a)` mirrors the swing plane's diagonal `e1` and `SWING_PIVOT` in X
  by it, and builds the pose from the mirrored radial and tangent, so the
  basis stays a rotation (mirroring a Basis directly would flip its
  handedness and the head's normals). The slash's sideways shove follows the
  side (`player.global_basis.x * 0.5 * slash_side`). The arc test is
  symmetric, so what is hit does not depend on the side.
- **`SLASH_EVERY` 0.75 -> 0.5 s** (berserk 0.25). `SLASH_BACK` 0.3 -> 0.22, so
  a whole cut (0.12 + 0.14 + 0.22 = 0.48 s) ends before the next is due; a
  click on the beat still cuts the recovery short, as before.
- **`STICK_TIME` 2 -> 1 s.** Killing it, or its death while the axe is in it,
  still sends the axe straight back.

Measured in a throwaway sandbox harness (headless), 6/6: spammed for 2.6 s,
slashes 0.50 s apart with sides 1, -1, 1, -1, 1; the mid-cut hand at x +0.33
forehand / -0.33 backhand at the same height; a throw stayed 1.00 s; berserk
slashes 0.25-0.26 s apart. Clean `--quit-after` run: no errors.
