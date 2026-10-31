## 137. The sword skeleton's blows have weight: a long heave, a short swing, and a swing that does not stop (2026-10-30)

Noah loves the walk and run on the golem (note 136) and asked for the attacks to feel
heavy: a slow, effortful wind-up, a fast swing, then a slow recovery with follow-through
as the weight carries the hand on. Hit timing stays synced to the swing, and the
no-arm-twist work stays.

This supersedes the blows and the timers in notes 135 and 136. Their "the same timers"
is no longer true for the sword hand. Nothing else about the rig or the clips changed:
walk, run and the other 13 clips came out of the export byte for byte identical.

### Why they felt light

Timing, not poses. Measured on the old clips, tip speed in m/s:

```
           wind-up   swing   carried on past the window
slash_1    10.1      22.4    0.05 s, 0.30 m
slash_2     8.0      20.4    0.07 s, 0.43 m
slash_3    10.6      19.5    0.02 s, 0.06 m
heavy       3.7      14.8    0.07 s, 0.18 m
```

The arm went up at half the speed it came down, because 0.45 s is not long enough to lift
a 2 m arm slowly, and then it stopped dead at the end of the blow.

### The clock

`prosthetic.gd` `BLADE_WINDUP/SWING/RECOVER` and `HEAVY_WINDUP/SWING/RECOVER`, the same
numbers as `LIGHT` and `HEAVY` in `tools/anim_sword_skeleton.py`. Only the sword hand.

```
           wind-up        swing          recovery      whole clip
light      0.45 -> 0.90   0.32 -> 0.24   0.70 -> 1.00  1.47 -> 2.14 s
heavy      0.85 -> 1.25   0.42 -> 0.30   0.95 -> 1.45  2.22 -> 3.00 s
```

The swing is enemy.gd's ATTACK state and the blade can only hurt in it, so hit timing
stays on the swing by construction, as long as those two sets of numbers match.

The cooldowns did not change. `normal_cooldown` 1.6 runs from the start of the recovery,
so a light comes every 2.74 s against 2.37 s before: 13% fewer blows, and the same damage
a blow.

### The six beats

Set out above `slash_1` in the script, and each channel takes them late of the one under
it: **load** (it sags before it lifts), **haul** (the shoulder hikes with the effort), **hang**
(the arm all but stopped while the hips have already gone), **swing** (hips, chest, shoulder,
and the elbow stays shut until the arm has its speed), **carry**, **heave**.

- `arm` is now swing, out and roll; the **elbow has its own track**, so it can open late.
- The arm's blur went from 0.07 to 0.025. A tent that wide took the speed off the swing.
- The heavy's wind-up is **two pushes** with a hitch between them.
- `slash_2` rises past the blow until its own weight stops it, hangs, and is let down.
- `slash_3` misses the floor by a hand and runs on low past the forward foot.
- The carry drags the trailing foot: it starts moving before the window shuts, or the
  stretched leg leaves the foot behind.

**The carry was the hard part: the blade has to keep going the way it was going.** An arm
at `swing` 0 hangs along the spine, not straight down, so with the chest pitched 50 degrees it
points behind the body. The old `slash_1` ended with the arm pointing backwards at
(0.03, +0.79, -0.62), and just adding more of the same took the blade right round behind
it. So the follow-through keys were solved from world directions: pick where the upper arm
should point at each beat, then read off `swing` and `out` for the chest at that moment.
That is why `swing` goes back UP in the carry (75 to 115 in `slash_1`), and why the chest
turns less than it did. Keep this in mind for any new blow: **judge the end of a swing in
world space.**

The peak of the speed had to move too. Keys spaced evenly gave a peak at A+0.08 and nothing
left by the end of the window; holding the hips and elbow back moved it to A+0.15 to A+0.22.

### In the game

`sword_skeleton.gd`:

- `_measure_step`: 0.9 s is long enough for the player to have moved, so the step is
  measured again as the swing starts, from what is left of it.
- `TURN_SPRING_LOADED` 6.0: the model's heading spring in the wind-up and the recovery.
  With the blade up or still out, it comes round slowly. The swing keeps 20.

### Measured

`--check` has three new lines: `[pace]`, `[reach]` (when the blade, elbow to point, reaches
someone 1.3 m past the end of the step, against the window) and `[clear]` (blade to body).
`[check]` also prints how far a foot is off its mark. `--sheet` shows a blow's beats, not
even steps.

```
           wind-up   swing   carried on    lands   tip jolt     edge off the cut
slash_1    6.3       21.1    0.18 s 0.99 m A+0.15  0.215->0.151 mean 29 -> 15
slash_2    4.5       22.8    0.18 s 2.35 m A+0.17  0.141->0.239 mean 45 -> 50
slash_3    6.8       25.3    0.23 s 1.49 m A+0.15  0.115->0.218 mean  9 -> 10
heavy      2.5       14.8    0.20 s 1.05 m A+0.18  0.068->0.111 mean 31 -> 18
```

The swing against the wind-up went from about 2 to 1 up to between 3.3 and 6 to 1. By `[reach]`,
the old `slash_2` at its full step landed at A+0.80, past the end of its window, so it would
have missed someone at the full standoff. It lands in the swing now. Its edge is still the
worst of the four, as in note 136.

**The arms did not twist.** The code that makes the forearm a pure hinge did not change.

```
           upper arm spin    peak (was)     wrist turn
slash_1    -70..+11          5.3/f (5.8)    0
slash_2    0..+80            3.3/f (3.5)    0
slash_3    -55..+3           2.3/f (3.3)    0
heavy      -52..+46          4.1/f (1.6)    1-2
```

The heavy's peak is higher because it swings in 0.30 s, not 0.42. It is still under the lights.

**Fights**, windowed, in the real sandbox, one golem, reading the player's health on the
pose shown:

- Standing still, 70 s: 26 of 26 landed.
- Teleported 5.5 m away every 6 s, 70 s: 23 of 23.
- Teleported 2.25 m ahead just as a blow came up, 100 s, which is what gets the long-step
  clips: 38 of 38, the long ones landing at A+0.13 to A+0.23.

The first two ran before the last tweak (the lights' step moved in 0.04 s earlier, because the
long ones were landing at A+0.22; `slash_2`'s swing eased). Only the third ran on the clips as
committed.

All in the ATTACK window. The harness flagged 2 as outside it: `_run_attack` lands the blow and
then `_enter_recover` runs in the same tick, so a hit on the window's last tick reads as RECOVER.
`heavy` itself, long step, did not come up in any of these: 33 `heavy_s` did. `--check` says it
lands at A+0.18.

**The export**: 23 clips in, 23 out. Compared track by track against the last build,
`idle`, `idle_fight`, `walk`, `run`, `haul`, `idle_haul`, `turn_*`, `stagger_*` and `death_*`
are identical. The eight blow clips changed.

**Clean run**: `--quit-after 1500 -- --skip-title --no-intro`, windowed: stderr empty.

No bench: nothing here changes what is drawn, only the keys in eight clips.

### Traps

- **A harness that teleports the player to force a long step needs the blow's cooldown
  nearly out**, or the golem walks in first and picks the `_s` clip. Almost every blow in a
  real fight is `_s`: it walks up to `STOP_AT`, then swings. The long clips are for someone
  backing off.
- **`[reach]` only means something from A on.** The guard pose holds the blade out where
  the player stands, and the sweep tests distance, not motion: a blade near them at the start
  of the window lands at once.
- **`.gdignore` does not cover `tools/__pycache__`.** Blender writes it when the anim script
  imports `build_sword_skeleton`. Delete it; do not commit it.

### Not done

- `slash_1`'s trailing foot still comes 0.2 m off its mark at the full step, as it did (0.197).
  Moving the foot sooner took it to 0.18, and moving the step earlier put it back.
- Against someone standing still it creeps in: `STEP_MIN` makes each blow a small step, and
  after a few it is pressed up against them at 0.75 m. Note 135's number; left alone, but it
  shows more now that a blow is a big, slow thing.
- `slash_2`'s edge, as in note 136.
- Sounds. A heavy blade wants a grunt on the heave and a scrape on the carry.
