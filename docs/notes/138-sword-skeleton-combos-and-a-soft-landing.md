## 138. The sword skeleton's combos, and a blow that comes to rest (2026-10-31)

Noah likes the animations from note 137 and asked for two things: now and then it should
chain 2-3 attacks, each swing's recovery flowing into the next wind-up, and the return from
an attack to idle, the one thing he did not like, should be seamless. Walk, run, the heavy
feel, hit timing and no arm twist all stay.

This changes note 137's recovery times (below). Everything else in it still holds.

### Why the return showed

Not the blend. The clip stopped the blade itself. Measured in a real fight:

```
                tip m/s, before the clip ends     (the swing is about 21)
                0.2 s      0.05 s
slash_1         4.6        6.1
slash_2         10.2       3.0
slash_3         5.2        3.4
heavy           3.1        0.8
```

The recovery's keys drive the arm home in the last 0.34 s, 90 degrees of it, and its track
is flat at the last key, so it arrives at speed and stops in a few frames. `slash_2` also
ended with its left foot 0.2 m off the stance, which skated home under the idle. Foot and
pose checks at a clip's end could not see the first of those: the last frame was in the
right place, and it got there too hard.

### The soft landing

`anim_sword_skeleton.py` `Blow.clock`: from `settle` the clip's clock slows at a steady rate
to nothing at the end, and every channel reads its keys through it. No key moved, so the
swing and the carry are untouched, and all the joints come to rest together.

```
           keyed     settles from     recovery now    was
light      1.0 s     0.7 s            1.3 s           1.0
heavy      1.45 s    1.05 s           1.85 s          1.45
```

`BLADE_RECOVER` and `HEAVY_RECOVER` in prosthetic.gd are those numbers. `normal_cooldown`
1.6 still runs from the start of the recovery, so a light still comes every 2.74 s: the time
comes out of standing in guard. The blurs narrow with the clock (`pace`), or the last pose
stops a centimetre short of the guard by what they average in.

- `_b()` now reads idle_fight's real first frame, breath included, instead of the guard's
  round numbers. A blow ends exactly on it: `[seam]` in `--check` reads 0.0000 m.
- `slash_2`'s left foot shuffles back as the right comes up. Its right foot goes 0.08 s sooner
  to make room. `slash_1` and `slash_3`'s stepping foot land on the stance's own x.

**Three other ways out of a blow, in `sword_skeleton.gd`:**

- `relax` (1.4 s): the guard and the idle stand a stride apart. Going to `idle` from the guard
  it steps there, the hips first and the blade let down last. `_update_locomotion`.
- `turn_gl`, `turn_gr`: turning with nobody moving played `turn_l`, whose arm is the idle's,
  so the blade dropped and came back up whenever it turned to follow someone. These are the
  same steps from the fighting stance with the guard held, and start at `TURN_FROM_GUARD`,
  where both feet are nearest the stance.
- `_switch` starts a walk or run on the right foot out of a blow too, and reads
  `assigned_animation`, since a blow's clip can run out a tick before the state does.

Two small lurches: the heading spring's stiffness eases (`_turn_k`) instead of jumping 6 to 11
as a blow ends, and the head's look comes up over the last 60% of the recovery instead of
all at once after it.

### The combos

A **link** is a clip from one blow, at `LINK_OUT` (0.62 s after its swing) to the next blow,
`LINK_IN` before its swing. The game swaps clips at those moments with no crossfade: they are
the same pose at the same speed.

- The links are 0.75 s. Five, chosen by where the blade ends up: `slash_1` ends low on its left
  where the backhand starts, the backhand ends high on its right where the others start.

```
slash_1 -> slash_2          slash_2 -> slash_1, slash_3, heavy          slash_3 -> slash_2
```

- A link does not depend on either blow's step. By `LINK_OUT` every light has both feet back
  in the stance, in its own root's frame, and at `LINK_IN` every blow is still in it. So one link
  serves the `_s` and long clips, and the next blow's step is picked at the join, from where
  the player is by then (`_join`). Into the heavy the link takes its step back itself.
- `splice`: each channel stays on the old blow's own track as long as it can, then runs a
  quintic to the new one, matching place and speed at both ends. `HANDOVER` sets when, so
  the hips go first and the elbow last, and the arm keeps the speed it came in with. That
  is what keeps the weight in it. Quintic in the joint angles, so the arm's roll is still a
  track, and `--check` still reads it.
- Hit to hit in a chain is 1.83 s, against 2.74 s for single blows.

In the game (`sword_skeleton.gd`): `_start_blow` rolls `CHAIN_SHARE` 0.4 for a second blow, and
`CHAIN_THIRD` 0.4 for a third. `_tend_chain` reaches `CHAIN_OUT` in the recovery and `_go_on`
picks the next and calls enemy.gd's own `_enter_windup`, so the telegraph, the ATTACK window
and the sweep are all the ordinary ones, and `_windup_for` says what is left of the link and
the wind-up. Further than `CHAIN_REACH` 2.6 m, or stunned, or no longer engaged, it lets the
blow finish its recovery. A stagger or death goes through `_play_state_anim` / `_fold_up` and
clears the chain. The heavy only ever ends one, and only when it is off cooldown.
After a chain it is blown: both blows wait `CHAIN_REST` 0.7 s longer for each blow added.

### Measured

Throwaway windowed harnesses in the real sandbox, one golem, on the pose shown by a last-in-chain
modifier, deleted. **The return, blow to idle_fight:**

```
                tip m/s before the end        worst speed lost      foot moved in
                0.2 s         0.05 s          in a frame, m/f       the 0.5 s after
slash_1         4.6 -> 1.3    6.1 -> 0.06     0.048 -> 0.009        0.03 -> 0.02
slash_2         10.2 -> 1.0   3.0 -> 0.05     0.029 -> 0.008        0.07 -> 0.016
slash_3         5.2 -> 0.6    3.4 -> 0.04     0.023 -> 0.005        0.03 -> 0.02
heavy           3.1 -> 0.17   0.8 -> 0.02     0.007 -> 0.002        0.007 -> 0.007
```

Worst jolt across the switch, of the tip, head, claw and feet: 0.048 -> 0.013 m/frame/frame. Into `relax`: 0.003, with
the feet stepping.

**Chains:**

```
                     out          in           speed gap out/in    tip peak    upper arm spin
link_1_2             0.0000 m     0.0000 m     0.000 / 0.000 m/s   4.7 m/s     2/f, 23 degrees
link_2_1             0.0000       0.0000       0.023 / 0.001       10.3        2.1/f, 54
link_2_3             0.0000       0.0000       0.023 / 0.001       10.3        2.3/f, 54
link_2_h             0.0000       0.0000       0.022 / 0.011       10.1        1.8/f, 42
link_3_2             0.0000       0.0000       0.000 / 0.000       6.7         2.2/f, 52
```

Those are `--check`'s `[link]` and `[roll]`, the same for `_s`. The wrists do not turn. The swaps in
the real fight read jolts of 0.004-0.019 m/frame/frame, under the clips' own.

**Fights**, the player's health held up:

- Standing still, 70 s: 24 of 24 swings landed, in 4 chains and the rest single, at A+0.10 to A+0.18.
  The window opened at clip time 0.90-0.92, or 1.25-1.27 on the heavy.
- Stepping 0.9 m back as each blow ended, 60 s: 17 of 20. Every single blow landed. All three
  misses were a chain's follow-up: the long step at the join leaves it 1.5 m off someone at 2.2 m,
  so backing off is how you dodge a chain. Left that way on purpose: it commits, and it swings.
- Out of `CHAIN_REACH` at `CHAIN_OUT`, 60 s: no links played, 19 of 19.
- Turned to face someone at the side, 50 s: 17 of 17, `link_2_h` among them.
- Stunned in a link twice, killed in a third: no errors, and it fought on after the stuns.

**The export**: 23 clips in, 31 out. Compared track by track against the last build, `idle`,
`idle_fight`, `walk`, `run`, `haul`, `idle_haul`, `turn_l`, `turn_r`, `stagger_*` and `death_*` are
byte for byte identical. The eight blows changed; `[pace]`, `[reach]` and `[roll]` read as in note
137 up to the settle, the keys being the same. The GLB went from 17.39 to 18.30 MB.

**Clean run**: `--quit-after 1500 -- --skip-title --no-intro`, windowed: stderr empty.

No bench: nothing here changes what is drawn.

### Traps

- **`crossfade` holds a moving pose for a frame.** `_begin_offsets` takes the offset from last
  frame's pose to this frame's clip, so with two clips in step the offset is one frame's
  movement, at no speed of its own, and the rig stands still for a frame and then catches up.
  Tip jolt 0.096 with a crossfade on the swap, 0.019 without. It is small on an ordinary switch,
  but it is why a swap between matching clips must not call it. It also reads `_rot_before` as
  standing still when the new clip starts near 0.
- **A clip can end in the right place and still look wrong.** Check the speed coming in,
  not just the last frame: `[seam]` prints the tip's speed at 0.4 to 0.05 s out.
- **In a harness, a golem past `anim_full_distance` jumps its clip by a few frames**, and reads as
  a jolt of 0.7. It is animation LOD, not a seam: print the clip times beside the number.
- **A walk away straight after a blow never reaches `relax`:** blow, one tick of `idle_fight`,
  then walk, because it picks a clip by speed. `relax` only shows when it stands.
- A harness that frees its own golem has to quit by itself, or it runs to the timeout.

### Not done

- The blow's recovery still cannot be cut short when the player walks away. That is the weight.
- A player who hides or scares it mid-recovery cuts the recovery off into a walk, an ordinary
  0.34 s blend. It looked fine and was left.
- The `crossfade` trap above, in `_begin_offsets`. Fixing it would touch the enforcer and
  decrepit, so it was left out of this.
- Sounds, as in note 137.
