## 139. The sword skeletons are Proel swordsmen: out of a blow in stride, real turns, a living guard, red eyes, chains that hunt the kill (2026-10-31)

Noah: "Call them proels from now on. These are proel swordsmen." Their animations should
flow very smoothly and quickly from attacking to walking or running, they should have
animations for turning, the still idle after attacks should have more movement, the eyes
should be red and glow less to reduce bloom, and their attacks should be chained smartly,
with killing the player as the aim.

This changes note 138's "Not done" (a recovery can now be cut short) and its chain rolls.
The heavy blows, the links, the weights and the no-arm-twist work are untouched: every
blow and link came out of the export byte for byte identical.

### The name

Wherever a player sees it: `PROEL SWORDSMAN` over its health bar (prosthetic.gd
`display_name`), `Proel swordsman` in the sandbox, `CONTAINMENT: PROEL SWORDSMEN` and "The
proel swordsmen are loose in the maze." (dungeon_room.gd `HAND_NAMES`, which now holds each
type's whole name). Header comments, tools/README.md and CLAUDE.md say so too.

**The code keeps its old names on purpose:** `sword_skeleton.gd`, `models/sword_skeleton.glb`,
`tools/*_sword_skeleton.py`, `&"blade"`, `skeleton_blade`. `&"blade"` is in the saves
(`released_hands`), and every other skeleton type shares that code. Notes 135-138 are
history and still say sword skeleton. "Skeletons" as a word for all the types (the
inventory's "Dropped by", a settings hint) is left alone.

### Out of a blow, in stride (`out_*`)

`anim_sword_skeleton.py` `out_clip`, 18 clips: one per blow, `_s` or long, walk or run, and
`out_g_walk`/`out_g_run` from the guard. An `out` clip takes over from a blow and ends on
the first frame of the gait at the gait's speed, so both ends are swaps with no blend.

- **When:** `OUT_AT`, 0.32-0.38 s after a light's swing, 0.52 after the heavy's: the carry is
  spent and the right foot is down. `sword_skeleton.gd` has the same numbers: change both.
- **The body:** each channel crossfades from the blow, still running on its own clock, to the
  gait, also running, by a minimum-jerk weight. Both tracks are moving and the weight has no
  speed at either end, so nothing has to stop. No IK anywhere near the arm: it is lerped
  joint angles, so a roll is still a track, and the wrist does not turn.
- **The right foot** stays where it stands and rolls off by the gait's own `stance_foot`, as
  the body goes over it. **The root** is what that foot says it must be: from nothing to
  the gait's speed by the moment the foot leaves the floor.
- **The left foot** carries on whatever it was doing and lands on the gait's strike, phase 0.
  The foot the carry was dragging up becomes the first running step.
- `OUT_STRIDE` sets how long the first stride takes. slash_2's is 2.9 against 1.75 from the
  guard, because it leaves the blade high: at 1.75 the tip came down at 20.6 m/s, as fast as
  the swing itself, and all the weight went out of it.

**In the game:** `_tend_chain` asks `_should_leave` from `OUT_AT` on: gone past `CHAIN_REACH`,
or nobody to fight. `_leave` ends the RECOVER state and puts the clip on, with `_out` set; it
is root motion through `_blow`, so `_slide` drives it, in CHASE, and an attack can cut in.
`_tend_out` swaps to the gait a tick and a half before the end. Run when `engaged`, else walk.
Going later than `OUT_AT` it crossfades (`BLEND_OUT` 0.22) into the start of the clip. From
the guard, `_update_locomotion` starts `out_g_*` instead of `_switch`.

Swing's end to full run: 0.84-1.05 s from a light, 1.1 s from the heavy, against 1.3-1.85 s
of recovery, a 0.34 s blend and the acceleration before.

### Turning (`pivot_*`, `gpivot_*`)

The old turn was a spring at up to 6 rad/s under clips stepping at 1.75 rad/s, so it read as
a slide. Eight new clips, relaxed and on guard, left and right, 90 and 180 degrees (`b`).
`anim_sword_skeleton.py` `pivot`: the head goes first, then the chest, then the hips, the blade
dragged after them. The feet are planned on the floor (`step_foot`, an arc round the middle
of the body, so a 180 does not bring a foot through the other leg) and turned back by the
root each frame, so a planted foot stays planted. On guard they take 0.72 and 0.98 s.

**`root` x carries the turn, in radians.** The game lifts that track out with the step
(`_lift_roots`, `_yaws`), and in a pivot `_turn_model` sets the heading from it, scaled
0.7-1.15 to the turn it wants. It is not a rotation on `root` because the Spec's feet and
hips are all in the root's frame and the track is taken out of the game anyway.

`_update_locomotion` starts one under `PIVOT_SPEED` 1.4 m/s for more than `PIVOT_FROM` 0.95 rad,
the long one over `PIVOT_LONG` 2.3. The body waits (`_slide`), and attacks wait until 70% of
the way round. Out of a blow it blends longer (`BLEND_PIVOT_BLOW` 0.45): the blade is a long
way from the stance. Turned past `OUT_TURN` 1.2 rad from them, `_leave` gives way to a pivot.

Small turns keep `turn_l/r/gl/gr`, with the spring's speed capped at `TURN_MOST` 2.6 rad/s
while it stands, so their feet can keep up. On the move it leans into the turn (`_lean`, the
model's z, at most 0.16 rad), and with nobody to look at, the head looks where it is turning.

### The guard, alive (`idle_fight`)

6.6 s now, was 2.2. Blown from the blow: the chest heaves at 1.25 s and slows. The weight goes
from foot to foot, the blade sags and is hauled back a beat behind it, the claw works, the
head looks about, one foot shifts and is put back, then the other. `on` is 0 at both ends at
no speed, so a blow still lands on the guard itself: `[seam]` still reads 0.0000 m. Only
`fight_base` is the guard, and it did not change, which is why the blows did not.

### The eyes

`light_eyes` in build_sword_skeleton.py, which the anim script calls too, so changing them
needs no rebuild of the model: base (0.22, 0.012, 0.008), emission (1, 0.035, 0.018) at 0.8,
was orange at 1.7. The halo is the proel's own (`skeleton_eyes.gd` `attach_at` takes colour,
strength and size): alpha 0.2 at 0.04 m, was amber 0.55 at 0.06. The telegraph brightens them
1.5 times, was 2.6. The other skeletons keep their yellow eyes.

### Chains that hunt the kill

`CHAIN_NEXT` and the links are note 138's. What changed is how it picks. The chain used to be
rolled as the blow started; now it is weighed at `CHAIN_OUT`, with the result in front of it.

**Whether it goes on** (`_press_on`): always if they are open or a heavy would finish them.
Otherwise 0.75 after a hit, 0.5 after a block, 0.4 after a miss, +0.25 with them under
`LOW_HEALTH` 35%, and `CHAIN_TIRED` 0.7 of that for each blow already added. At most
`CHAIN_MOST` 2 added. If they have gone out of reach it does not go on: it goes after them.

**Which blow** (`_best_of`, `_worth`), also for the first blow of a chain:

- It would kill, through their armour and any guard (`_finishes`): +3.
- They are open (`_open`: knocked down, drinking, within `SWING_OPEN` 0.45 s of a swing): the more
  damage the better.
- Their guard is up and turned on it (`_guarded`): the heavy, the most that gets through.
- Going sideways over `SIDESTEP` 1.5 m/s: the flat cuts, not the overhead.
- Further off than the standoff: the longer step.
- The backhand gets +0.6 when the heavy is ready and wanted, since the heavy only follows it.
- Always a random 0-0.4, so a chain cannot be learned by heart.

`_pick_attack`: light if a light kills (the shorter wind-up), heavy if a heavy kills or they
are guarding. `_go_on` takes the heavy off its cooldown only to finish them. `_watch_player`
clears the light's cooldown when they are open and in reach, as the scout does, and `_rest` is
40% as long with them nearly dead.

### Measured

Throwaway windowed harnesses in the real sandbox, on the pose shown (a last-in-chain
modifier), deleted. Worst tip jolt across a switch, m/frame/frame:

```
slash_1 > out      0.028     heavy > out      0.033     out > run         0.041
slash_2 > out      0.036     slash_3 > out    0.028     blow > pivot      0.07-0.11
                                                        note 136's worst  0.062
```

The blow-to-pivot number was 0.26 before `BLEND_PIVOT_BLOW`. `[out]` in `--check`: 0.0000 m
at both ends. Speed gaps are under 0.25 m/s into the gait.

```
              length    tip peak m/s    blade to body
out_1_run     0.52 s    10.9            0.26
out_2_run     0.67 s    15.0            0.40
out_3_run     0.52 s     9.1            0.15
out_h_run     0.60 s    13.5            0.22
```

The upper arm's roll in an `out` peaks 3.6/f, under slash_1's 5.3/f. Wrist turn stays within 1 degree.

**Fights**, 40-60 s each, one proel, its health held up:

```
                 blows     kills     seconds to kill 100 health
standing still   17 hit    2         17.8, 18.8
sidestepping     10 of 15  2         18.1, 23.3
swinging at it   9 of 10   1         31.9 (its swings kept staggering the proel)
holding a guard  22 of 22 blocked, 8 of them heavies
```

A standing player took a hit every 2.1 s. Note 138's fight was 24 swings in 70 s, 2.9 s each.
That is a different harness, not a same-run A/B. The harness's held guard reads as a parry on
every blow unless `parry_window` is off, because re-raising it restarts the window.

**Also:** a stress run of hits, shoves and teleports through every state, then a kill: no errors.
Stood with nobody to fight, relaxed pivots played, 12 in 26 s. `_leave`'s late path ran 7 times.

**The export**: 31 clips in, 57 out. Compared track by track against the last build, `walk`, `run`,
`idle`, `relax`, `haul`, `idle_haul`, `turn_*`, `stagger_*`, `death_*`, every blow and every link are
byte for byte identical. Only `idle_fight` changed, and 26 clips are new. The GLB went from
18.30 to 20.40 MB.

**Clean run**: `--quit-after 1500 -- --skip-title --no-intro`, windowed: stderr empty.

No bench: nothing new is drawn, and the eyes draw less. Eye crop, old against new at 1.6 m,
same frame of light: lit pixels 6349 -> 3579, summed luminance 791948 -> 388787.

### Traps

- **A clip a tick from its end has no speed.** `_tend_out` stopped one tick early only by luck
  of rounding on some clips: on `out_g_run` the clip ended first, `_slide` read it as stopped
  and the body dropped from 4.6 to 0.5 m/s at the join.
- **`get_bone_global_pose` in `_process` reads the raw clip**, before the layer: crossfades read
  as jumps of 1.48 m. Measure on a last-in-chain modifier, as notes 135-138 did.
- **A far rig's clip may not run at all** (`anim_far_rate` 0 on low presets), and a body
  waiting on a pivot would wait for ever: `_shown_close`.
- **A foot's pitch at landing is a height.** The blows' `Blow.foot` jumps 0.018 m at landing,
  hidden by their speed. On a slow idle step that is a tick, so `step_foot` keeps the heel on the
  floor all the way (`sole`).
- A harness's player swinging at a proel kills it, and the harness ends. Hold its health up.
- A sheet shows a pivot's root x as a sideways drift. It is the turn, not a step.
- Blender's `.py` here is CRLF: a patch script has to match that.

### Not done

- The proel has no way to get round a raised guard: no strafe clip, so it chips with the heavy.
  The scout flanks (note 129).
- A run that reverses at speed is still the spring and the lean, not a plant-and-turn clip.
- `idle` to `walk` or `run` is the old blend. Only the guard got an `out`.
- The stagger's switch still reads 0.33 at the tip out of a swing, as it did. Not looked into.
- Sounds, as in note 137.
