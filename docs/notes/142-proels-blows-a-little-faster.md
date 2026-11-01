## 142. The proels' blows a little faster: one tempo over every blow and link (2026-10-31)

Noah: "Speed up the proels attacks a little."

Read as the whole blow, keeping the weight of note 137: a slow heave, a fast swing, a slow
recovery. That weight is the proportions, so everything takes one number, `TEMPO` 1.15 in
`tools/anim_sword_skeleton.py`, `BLOW_TEMPO` in `prosthetic.gd`. Change both. Supersedes the times
in notes 137 and 138. Their keys and their beats still hold: the keys did not move.

```
           wind-up        swing          recovery       whole clip     cooldown
light      0.90 -> 0.78   0.24 -> 0.21   1.30 -> 1.13   2.44 -> 2.12   1.60 -> 1.39
heavy      1.25 -> 1.09   0.30 -> 0.26   1.85 -> 1.61   3.40 -> 2.96   4.50 -> 3.91
```

### How

`LIGHT`, `HEAVY`, `LINK`, `LINK_OUT` and `LINK_IN` stay as they are keyed. `blow_clip(bl, tempo)`
runs the clock `tempo` times as fast, and the blows and links pass `TEMPO`, with their lengths over
it. So the blurs, the foot's landing and the settle all scale with the keys. `reel`, `relax`, the
gaits, pivots, strafes, staggers and deaths pass nothing and stay byte for byte the same. `OUT_AT` and
what `--check` and `--sheet` read are clip time, over `TEMPO`. In the game `BLADE_*`, `HEAVY_*`,
`LINK_TIME`, `CHAIN_OUT`, `CHAIN_IN` and `OUT_AT` are the old numbers over `BLOW_TEMPO`.

Baked, not played at 1.15. An `out` clip ends at the gait's own speed, so it must stay at 1x, and a
blow played faster would meet it at the wrong speed. `out_clip` reads the blow's clip function, so
the blow runs on faster inside it and the clip still ends in stride. 32 `out_*` clips changed
for that, the same lengths as before. `out_g_*` did not.

The cooldowns are over `BLOW_TEMPO` too, or the time saved would only go to standing in guard.

### Measured

`--check`, old -> new:

```
           tip peak m/s   swing mean   lands at        worst jolt       upper arm peak
slash_1    29.7 -> 34.0   21.1 -> 23.1  A+0.15 -> 0.13  0.151 -> 0.198   5.3/f -> 6.1/f
slash_2    37.7 -> 43.1   22.8 -> 24.5  A+0.17 -> 0.15  0.239 -> 0.315   3.3/f -> 3.8/f
slash_3    38.2 -> 43.8   25.3 -> 27.5  A+0.15 -> 0.13  0.218 -> 0.286   2.3/f -> 2.6/f
heavy      24.6 -> 28.6   14.8 -> 17.1  A+0.18 -> 0.16  0.111 -> 0.146   4.1/f -> 4.6/f
```

The jolts went up by 1.32, which is 1.15 squared: the same path in less time. Every blow still lands
inside its window, `[seam]` reads 0.0000 m with the tip stopped, and `[link]` 0.0000 m in and out at
speed gaps of 0.03 m/s or less. `[out]` reads 0.0000 m at both ends; the speed gap out of the blow rose most on
`out_2_run_high`, 1.03 -> 1.22 m/s, under the 1.33 of `out_3_run_low`, which did not move. Blade to body at the closest went from 0.041 to 0.054 m. Foot off its
mark and wrist turn did not change: the poses are the same.

**The export**: 92 clips in, 92 out. Compared accessor by accessor against the last build, 47 are byte
for byte identical, `walk`, `run` and `reel` among them. 45 changed: 8 blows, 5 links and 32 `out_*`.
Meshes, skin, nodes, materials and images the same. The GLB went from 23.10 to 22.89 MB.

**Fight**, a throwaway windowed harness, deleted: one proel, a standing player, 70 s each.

```
                                    before        after
swings                              27            28
all landed, in the ATTACK window    27 of 27      28 of 28
clip time as the window opens       0.90-0.92     0.78-0.79
heavy, same                         1.26          1.10
time in the window, light           0.25 s        0.22 s
hit to hit at its quickest          1.82 s        1.58 s
hit to hit, mean                    2.45 s        2.40 s
heavies among them                  2             5
```

The quickest gap, inside a chain, is 13% shorter. **The mean hardly moves in a fight this size**: it is
one run each, the second had more heavies, and most of the gap between exchanges is the circling of
note 140 (`CIRCLE_MOST`, `_wants_blow`), which this did not touch. What a player sees is each blow
coming sooner and each chain coming faster.

**Clean run**: `--quit-after 1500 -- --skip-title --no-intro`, windowed: stderr empty. No `--bench`:
nothing new is drawn.

### Traps

- **A swap happens in clip time, and a clip's length is rounded to whole frames.** `LINK_TIME` is 0.652 s
  and the link's clip 0.650 s. `_tend_chain` joins 1.5 ticks early, so it never reaches the end. The
  blows round the same way they always did (146.4 -> 146 frames then, 127.3 -> 127 now).
- A blow's constants are expressions now, so `BLADE_WINDUP` prints 0.78260869565217.

### Not done

- `CHAIN_REST`, the circling times and `TURN_GAP` are as they were. To make proels press harder overall,
  those are the numbers, not this one.
- The chance to dodge is that much shorter: the wind-up is 0.12 s less on a light blow.
