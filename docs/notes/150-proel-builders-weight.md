## 150. The Proel builders' blows have weight: a long hoist, a short drive, three spins the hammers drag (2026-11-01)

Noah: "The animation speed of the proel builders is fine, there just is too little weight to the
impact of their hits. make sure the descent of the impact is faster than the windup rather than a
linear motion throughout the whole attack. especially the spin, there should be a windup and then
a few quick spins. think about the momentum of the heavy hammers dragging the rest of the body
along with them".

So the clocks stayed and the time inside them moved: `SLAM_T` 2.0 s, a hammer a second, the landings
at the same moments, `spin` 6.8 s. Only `slam_walk`, `slam_stand`, `slam_in` and `spin` changed: the
other 12 clips are byte for byte the same (each accessor compared with the last commit's GLB).

### The pound

| | before | now |
| --- | --- | --- |
| drive | 0.40 s | 0.30 s (`ARM_DRIVE_AT` 0.85) |
| head at most, on the way down | 19.8 m/s | 29.9 m/s |
| arriving at the floor | 14.7 m/s | 24.5 m/s |
| hoist, from the floor to the top | 1.2-1.6 s | 1.3-1.6 s, 7.7 m/s at most |
| hammer held on the floor | 0.10 s | 0.18 s, let go by 0.34 s (`ARM_STUCK`, `ARM_FREE`) |
| body after the landing | waited | goes on down 8 degrees and 3 cm, 0.11 s |

- **A first pass of 0.24 s came in at 36.8 m/s**: 0.6 m a frame, a jump, not a blow. Read `[pace]`.
  The head goes over the top before it comes down: 2.2 m above the floor at 0.2 s out and still 2.17 m
  at 0.1 s out, so the whole fall is the last 6 frames and the 0.2 s before that is the over-arm.
- The hoist ends in a hang (`ARM_TOP_AT` 0.78 to `ARM_DRIVE_AT`) creeping back to `ARM_CREST`, and
  the body rears to 0 degrees and 1.15 m as it does (`BOW_TOP` 0.69), then drops first, by 0.01 s.
- `swap_side`: the torso's turn was a sine over the whole second. Now 28% of it goes through the
  hoist and 72% with the drive, so the shoulder comes over in the blow.
- **The hammer stops and the body does not.** That needs the arm to give, and the arms are joint
  angles, so `pin` solves swing, out and elbow (Gauss-Newton, 5 steps, one numeric Jacobian a
  step) to hold the head where it landed. In `slam_walk` that spot goes back at `SLAM_V`, so
  the body walks past a hammer that stays put, where it used to skate with the body.
- `shudder`: 0.1 s decay, 0.2 s period: the spine, the head a beat late, the other arm on its way up
  (7 degrees), and the head of the hammer rocking on its corner.
- `BOW_KEYS` has a key before zero, never read, only to leave the body moving at the landing:
  `track` is flat at its first key.
- The game's cue, listen and live are untouched: they count back from the landing, which did not
  move. `live` opens 0.3 s out, exactly as the drive starts.
- `down` in `pound` jumped at `BOW_TOP` (0.55 x (1 - BOW_TOP) in one frame, a 2 degree pop in the
  lean). It reads the bow now.

### The spin

| | before | now |
| --- | --- | --- |
| coil | 1.3 s, 75 degrees | 1.9 s, 110 degrees, the last 0.3 s all but still |
| to full speed | 1.25 s | 0.5 s |
| turns | 2 | 3 (`SPIN_TURN` 1080) |
| top speed | 6.5 rad/s | 10.7, 12.1 at the fastest of the lurch: 2 turns a second |
| running out | 1.9 s | 1.1 s, 9 degrees past the end and back (`SPIN_BACK`) |
| getting up | 1.8 s | 2.0 s |
| `SPIN_WINDUP`, `SWING`, `RECOVER` | 1.85, 2.65, 2.3 | 2.2, 2.15, 2.45 |

`Trail` is what the ask was about. The hips' turn is still laid out (`Turn`), but the chest and the
hammers are integrated from it, every 2 ms, as two weights on springs, the hammers pulling back on
the chest (`PULL` 0.9). Nothing about the lag is keyed: left behind by the first shove (chest -24,
hammers -51 degrees behind it), swinging through to +21 and +32, and when the hips stop, overrunning
by 39 and hauling the chest 19 past them, then back the other way, -19, and settling. Flat out the
chest and arms ride ahead of the hips (15 and 10 degrees) and the head comes last.

- **Swinging an arm that is out sideways does nothing**: `arm_l[0]` is about X and the arm lies along
  X, which is why the old `lag` hardly showed. `Spec.yaw_l`, `yaw_r` turn the whole arm round the
  chest. 0 for every other clip. The lag goes through a tanh at 42 degrees.
- `Turn` is integrated with the angle in it (`SPIN_LURCH` 0.14), so it goes faster down the low
  side of a circle tilted 11 degrees (`SPIN_TILT`), low in front, high behind; the top speed is
  found by iterating to the whole turn. `ang` reads the tilt off in the body's frame, so it stays fixed
  on the floor. The hammers ride 0.65-2.2 m.
- The left arm rides out further and the hips lean 0.13 m away from it: the left is the heavier throw.
- **Feet**: stepping every 130 degrees at this speed would be a step in 0.08 s. `Foot` is someone
  throwing the hammer: the left steps in under the body and spins on its ball (`swivel` 1), hopping
  forward once a turn while the right is down; the right pushes off, is carried round in the air
  (in the body's frame, between stances), and stamps once a turn (`SPIN_STAMP`, 104 degrees on
  the floor). Then slower, wider steps to where idle stands. **The last stance must start
  within about 40 degrees of the end**: the first version put the right foot down 175 degrees out,
  and the foot went backwards under the knee.
- It still ends 0.018 m off `idle`, and walks 1.5 m. `SPIN_LIVE` opens 0.3 s after the release.

`--check` now prints `[pace]` for each hammer, the spin's foot stances, how near the feet come
and how far ahead of the hips the chest and hammers are. `--sheet <dir> clips <frames>` takes a
frame count and wraps at 10.

### Measured

Windowed harness in the sandbox, the player standing still, health held, deleted after.

- 40 s: three spins, hammers landing on 0.82 / 0.12 s of the clip as before. A spin from a gap of 2.70
  hit for 40 at 3.30 s, 1.1 s after going live. A hammer: 30 at 0.05-0.08 s before it lands.
- **Two of the three spins missed, and that is not new**: both came straight after a hammer had
  knocked the player flying, under 0.1 s earlier, so the gap the spin measured was 1.7 m and they landed
  about 3.6 m off.
- Parry through each cue for 38 s: `reel` every time, 1.2 taken from the shocks through a guard.
- `reel_from` at 3.02 s into the spin: the body took the model's heading (-94), up in 1.7 s, pounding.
- 38 frames of the spin from a side camera in the game agree with the sheets from Blender.
- No errors. Baked data only, so no change to frame time expected; **not measured**: Rainbow Six and
  Roblox were running again, as in note 149.

### Traps

- **`--check` output hides a hammer's real path.** `up` measured to the highest point called the
  over-arm part of the hoist. `[pace]` counts the hoist to `ARM_DRIVE_AT`.
- `Turn.when` is bisection, and past the end the turn is no longer monotonic: its upper bound stops
  at 75% of the run-out. Ask it for no more than about 1070.
- One frame still lands 3 cm into the floor: frame 7 is 0.003 s before the landing, on the drive,
  not pinned. So did the old clip.

### Not done

- Sounds, still. The pound and the stamp most of all.
- A hammer shaking the view (`SHOCK_SHAKE`) and the dust are as note 149. If the hit still wants more,
  they are the next thing to turn up, not the clip.
