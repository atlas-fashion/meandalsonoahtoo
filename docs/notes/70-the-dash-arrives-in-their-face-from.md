## 70. The dash arrives in their face, and only from 7 m (2026-10-17)

The user: "the dash isn't putting him close enough for the player. and it
should have a higher threshold, right now it dashes when you're barely away
from him". Supersedes note 67's DASH_MIN = CLOSE_RANGE and the slide's aim.

- **Where it ends**: the slide used to aim the shield's TIP at the player
  (DASH_TIP 1.9 m ahead of the body), so the body pulled up ~2 m short. Now
  `DASH_ARRIVE` 1.3: the slide puts its BODY that far from the player's (in
  their face; the shield's box over them). `_dash_step`'s gap is measured to
  it; DASH_TIP stays only as a measurement of the clip.
- **When it dashes**: `DASH_MIN` 7 m (was CLOSE_RANGE 3.8). Between close range
  and 7 m it crawls in, or now and then (45% a roll, 4-9 m, off cooldown)
  leaps; from 7 m out the dash still comes first whenever it is ready.
- Measured (throwaway harness, deleted; the sandbox, real time, the AI
  choosing): held 5 m off for 6 s -> no dash (jump, dropkick, jump, dropkick --
  the leap rolls); from 12 m -> dashed first at 12 m, arrived 1.30 m from the
  player, 15 landed; the player stepping 2 m aside mid-slide -> 1.47 m, 15.
