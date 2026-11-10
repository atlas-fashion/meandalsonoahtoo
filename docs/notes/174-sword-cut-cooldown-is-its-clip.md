## 174. A sword cut's cooldown is its whole clip (2026-11-09)

The user's goal: realistic, immersive, satisfying combat. Asked for: the regular sword attack's
cooldown lasts exactly as long as its animation, so a new attack cannot start before the current
one finishes.

### What it was

`_start_attack` let a new cut begin once the one in progress stopped biting, `_bite_end()`:
`SLASH_BITE.y` 0.40 pose s for the forehand, `CHOP_BITE.y` 0.31 for the backhand -- about half way
through clips that run 0.75 and 0.66 (PlayerMotion MOVES `end`). Everything after the bite (the
follow-through and the blend home) was cut off by the next stroke, and the body snapped from the
cut's pose to the stance in one frame (the old move's weight 1 -> the new one's `weight_in(0)` 0).
Note 151's queue held an early click to that same point.

### What it is

- `player.gd` `_stroke_end()`: over a `slash` or `chop`, `PlayerMotion.length(kind)` -- the clip's
  own end; over the heavy swipe or the wave, `_bite_end()` as before (they keep their own committed
  windows, and an LMB may still cut into their recovery once they have followed through).
- `_start_attack` and `_take_queued_attack` use it, so a click during a cut is held (note 151) and
  begins on the tick the cut ends. Each stroke now plays out whole, its follow-through blended home
  into the stance, and the next blends in from there -- no snap.
- The HUD's LMB tile (`attack_cooldowns`) counts down to `_stroke_end()` and its full length is the
  forehand's clip, 0.75 x `attack_time_scale` = 0.94 s (was SWING_HOLD 0.50 s).
- Left alone: Q (heavy) and F (the wave) may still override a cut in progress, as note 162 designed;
  `_bite_end()` still gates the guard, the dash, drinking and `_committed()`.

Real time (x `attack_time_scale` 1.25): forehand 0.9375 s, backhand 0.825 s; a held-down combo runs
a stroke every 0.83-0.95 s (it was every 0.39-0.50 s).

### Measured

Throwaway harness, headless (main.tscn, `--no-enemies --no-intro`), clicks fed to `_start_attack`
on the physics tick, each stroke's start and the pose second it was replaced at logged:

```
single click                 slash@0.017, ended at pose 0.747 (0.967 s)
spam every 0.05 s for 2 s    chop@0.017  slash@0.850  chop@1.800  slash@2.633
                             each ended at pose 0.653 / 0.747, the next starting that same tick
two clicks 0.12 apart        chop@0.017  slash@0.850
click at 0.5 s (recovery)    chop@0.017  slash@0.850 (held, not dropped)
click at 1.0 s (after end)   chop@0.017  slash@1.017 (at once)
```

The pose second at which each stroke gave way is what tells this from the old rule (it read 0.31 /
0.40 there). Clean `--quit-after 600` run: nothing on stderr. Frame time not measured: one float
compare a tick.

### Traps

- `_bite_end()` has other callers that must keep the bite (the guard, dash, drink, `_committed`):
  the new rule is a separate function, not a change to `_bite_end`.
