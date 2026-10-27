## 116. The enforcer's walk a little smoother (2026-10-27)

The user, after note 115: "Make the enforcer walk slightly smoother." Note
115 had the body follow the planted foot exactly, so it surged to ~11 m/s at
the end of each lurch and stopped dead in one tick (the user's stomp walk).

**What was built** (`scripts/enforcer.gd` `_slide`, `GAIT_SMOOTH` 0.1): the
step each tick is the planted foot's speed averaged over a 0.1 s window of clip
centred on the span just shown (`_gait_travel(mid - w/2, w) / w`, times the
rate), instead of over that span alone. The cycle's mean is unchanged (a
window average of a periodic speed), so the walk covers the same ground; the
dead stop is spread over ~3 ticks at 2.2 m/s. `GAIT_SMOOTH = 0` is note 115
exactly.

**Measured** (throwaway harness, deleted: a 30 m run at 2.2 m/s on a plain
floor; slip = the lower foot's world motion while it stays the lower one;
speeds over the steady stretch):

```
window (clip s)   slip m per m   peak m/s   sd m/s   biggest drop a tick
0    (note 115)   0.004          11.08      2.74     11.06
0.05              0.039          10.53      2.64      7.82
0.08              0.119           9.36      2.45      4.95
0.10  (chosen)    0.171           8.65      2.33      3.91
0.15              0.308           7.15      2.02      2.63
0.20              0.436           5.95      1.73      1.95
(glide, before 115: 1.15 m slip per m)
```

**The first try, a blend, was worse:** mixing a share k of the walk's mean
speed into each tick's step (`lerp(foot, mean, k)`) slips k metres per metre
walked (0.20 at k=0.2, linear in k) and barely softens the stop (drop 8.85
m/s at k=0.2), because the slip lands in the holds, where the foot is still
and the drift shows most. The window puts the slip only at the moments the
foot is already sweeping fast, and takes the stop's edge off far more for the
same slip.

To go smoother, raise `GAIT_SMOOTH` (0.15 still keeps slip at a quarter of the
old glide's); to plant harder, lower it.
