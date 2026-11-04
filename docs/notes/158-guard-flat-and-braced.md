## 158. The guard flat across the view, braced, stiff (2026-11-03)

The user: the guard's forearm more perpendicular to the camera view (horizontal
across the screen), stiffer (less wobble, overshoot, tremble), and
strong-looking, like driving an elbow into something.
Supersedes note 157's guard pose, springs, recoil and tremble; the parry pose
and the rules are unchanged.

### The pose (`first_person_arms.gd` constants)

The old guard rose diagonally away from the eye: elbow (-0.28, -0.30, -0.17) to
fist (0.04, -0.17, -0.27), 13 cm up and 10 cm deeper across its length. Now
elbow and wrist share one height and nearly one depth, so the forearm is a flat
bar square to the view, the upper arm thrust forward from the shoulder behind it:

```
              elbow                    wrist                    plate faces
guard     (-0.22, -0.14, -0.263)   (0.094, -0.14, -0.248)   (0.0, 0.35, -1)
shoulder brace  GUARD_SHOULDER (0.06, 0.03, -0.13)   (was (0.05, 0.02, -0.10))
```

The elbow sits 1.5 cm ahead of the fist -- the drive. The numbers are not
picked by eye: measured in the game, the left shoulder is at
(-0.256, -0.212, 0.113) head space before the brace, the upper arm 0.251 m and
the forearm 0.314 m (the knight at BODY_SCALE). The elbow is placed exactly the
upper arm's length from the braced shoulder and the wrist the forearm's length
from the elbow, so the two-bone IK (`_solve`, elbow spring as the pole) lands
the bones on the springs: the posed LeftForeArm bone read (-0.2195, -0.1384,
-0.2631) against the spring's (-0.22, -0.1384, -0.263). **Change the guard and
keep those two lengths**, or the IK puts the elbow somewhere else and the bar
tilts.

On screen (FOV 100, 3440x1440) the forearm crosses the lower half from a
hand's breadth left of centre to the fist just right of it, the upper arm and
pauldron sweeping in from the bottom-left; the drawn-back sword passes behind it.

### Stiffer

```
                  was            now
ELBOW_SPRING   34 / 0.62      44 / 0.92
WRIST_SPRING   27 / 0.55      36 / 0.88
BACK_SPRING    24 / 0.70      32 / 0.95
PARRY_SPRING   48 / 0.50      56 / 0.80
RECOIL_SPRING  14 / 0.50      26 / 0.85
BLOCK_KICK     (0.35,-0.7,2.0)  (0.15,-0.3,1.2)
PARRY_KICK     (-1.3,0.6,-1.2)  (-1.0,0.45,-1.0)
LOOK_LAG       0.12 m/rad     0.04
breath         5 mm           BREATH 2 mm
tremble        1.2 mm         none
SHUDDER        7 mm, fade 9   3 mm, fade 14
plate kick     block (0,2.2,1.0) -> (0,1.2,0.6); parry (-4,0,1.5) -> (-3,0,1.2)
```

The elbow still leads the wrist (stiffer), the drop is still 0.55 as stiff.

### Measured

Throwaway windowed harness (`_start_block`, the player's physics then off,
`guarded` emitted by hand; shots of the raise, guard, block and parry):

- Raise: 90% of the way at 0.31 s (0.33 before), overshoot **1.6 mm** (17.9 mm).
- A blocked blow's recoil, from the spring constants (harness frames ran at
  2-12 fps, too coarse to catch a 40 ms peak -- note 157's trap): peak ~20 mm at
  0.04 s, against ~84 mm at 0.09 s. A short hard jolt that drives straight back.

`--bench --size=3440x1440` (RTX 3060, High), same session: new 68.9 / 69.0 fps,
worst p99 22.22 / 22.43 ms; note 157's code put back 68.6 fps, p99 25.00 ms --
the same (only constants changed; the bench never raises the guard).
