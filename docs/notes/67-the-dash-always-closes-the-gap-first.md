## 67. The dash always closes the gap first (2026-10-17)

The user: "edit his AI to always prioritize closing distance with the dash".
Supersedes note 61's 35%-a-roll dash.

- decrepit.gd `_chase`, out of CLOSE_RANGE: the DASH whenever it is off
  cooldown (DASH_COOLDOWN 2.2 s), in DASH_MIN..DASH_MAX and the floor between is
  clear -- every tick, no roll. Only while it cools down does it roll (every
  0.35 s, 45%) for a leap, jump or dropkick, at LEAP_MIN..MAX 4-9 m. Close in
  (CLOSE_RANGE 3.8) is unchanged: any of the four moves (note 61).
- `DASH_MIN` is now CLOSE_RANGE (was 4.5): no band between close range and the
  dash where it only crawls. (CLOSE_RANGE's block moved above the dash's
  constants, which now use it.)
- A blocked blow shoves the player ~5 m (note 66): the dash is its answer.
- Measured (throwaway harness, deleted; the sandbox, real time, the player
  untouchable and sent 9 m off whenever it got within 3 m between moves, 30 s):
  dash@10.0 jump@7.0 (dash cooling) dash@8.9 dropkick@7.1 (cooling) dash@9.0
  jump@9.0 (cooling) dropkick@7.1 (cooling) dash@9.1 -- with the dash ready,
  4 of 4 gap-closers were dashes; leaps only while it cooled down.
