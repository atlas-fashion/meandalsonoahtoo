## 157. No torch; the left arm blocks and parries (2026-11-03)

The user: "Remove the torch, and make a hyper realistic blocking animation where
the player uses his left arm to block and parry."
Supersedes note 156's "No left arm".

### The torch is gone

- `scripts/hand_torch.gd` deleted (it shed no light, note 24: only its flame
  showed in the bottom-left corner). player.gd `_ready` no longer makes it.
- The co-op body (`coop_avatar.gd`) lost its torch prop and the flame material;
  its left arm now swings with the stride and comes up on guard (upper arm out
  and forward, forearm across the face), and its sword arm stays forward on
  guard instead of crossing the body.

### The guard is the left arm (`first_person_arms.gd` `_update_guard`)

The rules are unchanged -- `_start_block`, `_guard`, `parry_window`, parry cues
(note 62), `_on_guarded` -- only what is seen moved. The right hand's weapon is
no longer the guard: the sword, spear and axe guard poses are now just their
rest drawn back and down (`player.gd` `GUARD_DRAW` (0.1, -0.11, 0.12) head
space; spear.gd / axe.gd `_guard_pose` add it to `_rest()`). The old
`GUARD_HAND / DIR / EDGE` and the spear's `GUARD_CENTRE / ALONG / HAFT_MIDDLE`
are gone, and the weapons no longer take `_guard_kick`.

A second copy of the arms mesh, the left arm (the right folded to a point), at
full size. Nothing keyed: three damped springs in head space -- the elbow, the
wrist, and the direction the back of the gauntlet (the vambrace's plate) faces
-- chase the pose of the moment, sub-stepped at 4 ms. The bones come from the
same IK as the right arm (`_solve`, split out of `_pose` with `_place` and
`_shoulder`), with the elbow spring as the pole.

Poses (head space, metres; eye at the origin):

```
              elbow                 wrist                  plate faces
down      (-0.30, -0.60,  0.04)  (-0.20, -0.82, -0.10)  (-0.4, -0.2, -1)   under the view, hidden
guard     (-0.28, -0.30, -0.17)  ( 0.04, -0.17, -0.27)  ( 0.0,  0.3, -1)   forearm across the lower half
parry     (-0.30, -0.30, -0.20)  (-0.26,  0.00, -0.30)  (-1.0,  0.1, -0.5) forearm upright, out to the left
```

- Springs (rad/s, damping ratio): elbow 34 / 0.62, wrist 27 / 0.55 -- the
  elbow leads the fist up, both overshoot a touch and settle -- plate 24 / 0.7,
  the parry's wrist 48 / 0.5. Going down every spring is 0.55 as stiff: the
  arm drops, heavy.
- Up, the shoulder comes forward and in behind the forearm (`GUARD_SHOULDER`
  (0.05, 0.02, -0.10), scaled by how far up the wrist is), as a body braces.
- Held: it breathes (1.9 rad/s, 5 mm) and trembles (about 1 mm), and a turn of
  the head leaves it behind (`LOOK_LAG` 0.12 m a radian, sprung back).
- A blocked blow (`player.guarded` false): a kick into a separate, softer
  recoil spring (14 / 0.5) -- `BLOCK_KICK` (0.35, -0.7, 2.0) m/s, the fist
  driven back at the face and down, the elbow 60% of it -- back over about a
  third of a second; the plate knocked up; a 7 mm shudder through the plate
  dying at 9/s.
- A parry (`guarded` true): `PARRY_BEAT` 0.16 s at the parry pose on the stiff
  spring plus `PARRY_KICK` (-1.3, 0.6, -1.2) out wide, then `PARRY_HOLD` 0.18 s
  more before it may go down; the plate thrown outward. A tapped, cued parry
  with no guard held still brings the arm up for the beat. The parry's
  hit-stop (`_slowmo`) slows the springs with everything else.
- Hidden when down and still (and no recoil left).

### Measured

Harness (throwaway, windowed, block held by turning the player's physics off so
`_check_block` could not drop it): the posed wrist bone matched the spring's
wrist to under 1 mm at every step; up within 2 frames of `_start_block`; the
recoil visible the frame after a blocked hit; the parry beat at the upright pose;
down and hidden a second after release; a tap parry raising it from down.

`--bench --size=3440x1440` (RTX 3060, High): 70.2 fps overall, worst p99
22.61 ms, against 70.4 / 23.25 at note 156 -- noise. The bench never raises the
guard; up, it is one more 8k-triangle skinned mesh.

### Traps

- `_check_block` reads the real mouse button (`_action_held` walks the
  InputMap events), so `Input.action_press` does not hold a guard in a harness;
  `_start_block` then turning the player's physics off does.
- Harness frames ran at 13-30 fps; a spring kick read one or two frames late
  had already swung back, so "the recoil moved 1 mm" was the clock, not the
  spring. Read it the frame after.
