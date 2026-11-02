## 151. The Proel builders' longer step, a spin out of the pound, never still, a heavy parry; queued sword strokes and jumps (2026-11-01)

Noah: "Make the proel builder's walking attack move a little further per step, and make the
transition between the walking attack and the spin smoother. The windup for the spin should be
quicker, but just as dramatic. The enemy shouldnt ever be completely still. The reaction to being
parried needs to be heavier and more realistic. Make input queues, like in the axe and spear attacks.
If the player swipes his sword or jumps twice in a row, make the next jump occur when he lands the
first one, and make the next sword swipe start when the first one concludes."

Supersedes note 149's `reel` and note 150's coil and "getting up". The clip list is now 21: `spin`
and `reel` are gone for `spin_w`, `spin_s`, `reel_wl`, `reel_wr`, `reel_sl`, `reel_sr`, `reel_o`.
Every clip built on `idle` moved a little with it (below). 18.0 MB, was 17.4.

### The step

`SLAM_V` / `SLAM_SPEED` / prosthetic.gd `move_speed` 0.9 -> 1.15 m/s, on the same 2 s stride: 1.15 m a
hammer. `SLAM_S` 0.6 -> 0.56, because the stance is what the leg has to reach: 0.6 left a foot 6.4 cm
short of its mark, 0.56 leaves 4.6. Measured in game: the body at 1.15 m/s, the planted foot at 0.00.

### Into the spin

Before, a landing switched to `spin` over a 0.4 s inertial blend from a bowed body with one hammer on
the floor to `spin`'s first frame, which was `idle`, feet and all. Now there is nothing to blend:

- **The spin only starts on a LEFT hammer** (`_land`, `side == 0`), so there is one starting pose, not
  two: on the right one the feet would have to pass through each other to reach the coil's stance.
  `SPIN_SHARE` was left at 0.75, so it comes about half as often per second in reach.
- `spin(walking)` is one clip each way, `spin_w` from `slam_walk`, `spin_s` from `slam_stand`, and it
  **is** the pound for its first frame: `pound_at(...)` carries on underneath, `mix`ed out joint by
  joint over `SPIN_IN` 0.75 s. `_start_spin` puts it on at however far past the landing the tick
  fell, with no blend.
- The feet step, they do not slide: the right, on its toes already, goes first (0.04-0.46 s), the left
  next (0.5-0.92 s), both to where they will stand **at the top of the coil** (`coiled`). In stride
  the body also runs out what is left of its walk, `eased_off` over `SPIN_CARRY` 0.5 s, 0.29 m
  (`SPIN_CARRIED`): `_blow_scale` is only for the walk at them, so `_slide` applies it past
  `SPIN_COILED`.
- Out of it: the last `SPIN_JOIN` 0.9 s of the clip is `mix`ed into `slam_in`, and `_run_on` puts on
  `slam_in` at that time, no blend. There was a stop between them before: both clips stood on
  `idle`'s frame at no speed.

Measured, fastest bone by the frame: walking 18.8, 15.0 (the hammer landing), 4.8, 2.7, the body
1.15 m/s through it; out of it 4.9, 4.7, 4.4. Feet 0.05 m/s at the switch.

### The wind-up

`SPIN_A` 1.9 -> 1.15 s, `SPIN_COIL` still 110 degrees (`SPIN_WINDUP` 2.2 -> 1.45, the clip 6.8 -> 6.05 s,
`SPIN_SWING` and `SPIN_RECOVER` as they were). The old coil's last 0.3 s was "all but still", on
purpose, and that was the stillest thing in the fight. What took its place:

- The left hammer is dragged across the front off the floor, the right comes down from its hoist and
  is drawn back. All of that is the pound and the coil mixed, nothing keyed.
- Coiling faster loads `Trail` harder: nothing changed there and the hammers lag and swing further.
- `strain` from 0.55 s: 5 cm lower, and `quake`, a 9 Hz tremble, arms and hammers a beat apart.
- The head stays on them to the top of the coil (`_tend_react`).
- `_thud`: dust and a small shake (`THUD_SHAKE`) as the coil's last foot comes down (`COIL_PLANT`).

### Never still

`--check` prints `[still]`: the longest stretch with the fastest joint under `STILL` 0.2 m/s, root and
turn counted. The dead aside, the worst is `idle`, 1.2 s, slowest 0.07 m/s, and it was under 0.1 m/s
all the time before, so `idle` was given real amplitude: 4 cm of weight going from foot to foot
(was 1.2), arms 4 degrees (1.2), hammers 5 on two harmonics (2), head 12 (6). A 48 s fight in the
sandbox, player standing: never under 0.2 m/s for longer than 0.08 s.

The other thing that stood still is that a clip that ended held its last frame until the state's
clock ran out: **a spin starts a tick or two into its clip, so its clip ends first**, 2 ticks of
statue. `_run_on` runs in `_physics_process` whatever the state and goes by the clip.

### The parry

`reel_body` in the anim script; `reel_wl` / `wr` / `sl` / `sr` by hammer and by in stride or standing,
each from the pose its hammer meets a guard in (`REEL_EARLY` 0.07 s before landing, what note 150
measured), and `reel_o` from flat out in the spin. `REEL` 1.7 -> 2.2 s, `REEL_BACK` 0.75 -> 1.0 m, so a
parry buys half a second more than it did.

| s | |
| --- | --- |
| 0 | the arm is thrown back in 0.09 s, the trunk has not heard yet (0.22 s), the head a beat after that |
| 0-0.4 | the arm folds, the hammer going on over the shoulder (2.5 m up), dragging that shoulder and the chest round 32 degrees and back 30; the toes come up off the front foot |
| 0.14-0.92 | the feet come late: the rear one, then the front one the long way past it |
| 0.6-1.0 | the hammer comes back down on its own weight, faster and faster, past the leg; the other arm has dropped already |
| 1.02 | the hammer on the floor beside it (`REEL_THUD`: dust, a shake) and the body after it, bowed 48 degrees, hips at 0.93 m |
| 1.2-1.75 | shoulders heaving, the last two steps to get under itself |
| 1.5-2.2 | up, into `slam_in` at `REEL_JOIN` 0.7 s |

- `stop_dead` (enforcer_react.gd): the inertial layer normally keeps the speed a rig had. That is
  the opposite of a hammer meeting a guard. After `crossfade` it drops the speed, so the offset
  starts from rest.
- `reel_o`: `root` x carries the turn on, `eased_off` over 0.4 s then 18 degrees back. `_yaw_scale` is
  the speed the spin was at over `SPIN_TOP_RATE`, so a parry at the end of the run-out does not throw
  it round 120 degrees. It used to stop dead in a tick.
- `_reel_clip` reads `live` before anything clears it.

### The queues (player.gd)

- **Sword.** `_attack_queued`, set where `_start_attack` used to drop the click: while the stroke still
  bites. `_take_queued_attack`, from `_update_pose`, begins it the tick the blade stops biting, which
  is `_bite_end()`, the earliest a click could start one anyway: not the end of the whole pose, or a
  click made early would come later than one made late. A spin's turn holds one too.
- Forgotten, as the spear's is, if the sword is put away, a flinch or anything else ends the stroke,
  block is held, or the spin or slam goes over it.
- **Jump.** `_jump_queued`: pressed with no floor, no coyote time and no water. Spent the first tick
  there is a floor. Read before the early returns, so a press in a dash or a dive counts; a dive's
  landing then forgets it (`down`), as do a knock-down, ghost mode, a menu, a scene, a ladder, a vat.
- No time limit on either, as the axe and spear have none, and one is held however many presses.

Measured: two clicks 0.12 apart, strokes at 0.016 and 0.349 s; three in 0.2 s, still two; a second in
the recovery at 0.4, at once, as before; spam-clicking, 0.35 s apart, even; flinch, weapon away and a
spin over it each forget it, no stroke; a click in a spin begins at 0.782 s, its turn ending at 0.775.
Jumping: pressed in the air, the next jump 0.017 s after landing; one press never jumps twice; two
in the air give one; knocked down, none.

### Measured, in the game

Throwaway harnesses, headless for the queues and windowed for the fight (`override.cfg` with
`window/size/no_focus=true`, deleted after, since Rainbow Six and Roblox were up). A real parry by
setting `_block_pressed_at` in the cue, player pinned where they stood. **Frame time not measured**,
for the same reason as notes 149 and 150. Baked data and small per-tick reads, so none is expected.

### Traps

- **`_now()` is not the clip's clock through a parry.** The hit-stop slows the clip and not the stun, so
  the stun ran out 0.1 s early, `_tend_pound_clip` saw a clip that was not a pound and switched to
  `slam_in` from its start: a 0.9 m pop, then a standstill. It was found only by a real parry;
  `reel_from` called by hand has no hit-stop. The reel ends with its clip now (`_end_reel`).
- **`_end_spin` set the body's heading and left the model's offset to the next `_turn_model`**, which a
  parry comes after: for a frame the model's turn was counted twice.
- A headless physics tick is not a frame. The inertial layer's first frame reads wrong there; measure
  switches at `RenderingServer.frame_pre_draw`, windowed.
- Multi-line heredocs through the Bash tool fail on this PC; write the script with Write.
- `proel_builder.gd` has CRLF endings: a script that patches it needs to allow for that.

### Not done

- `slam_in` ends on `slam_stand`'s frame, so into `slam_walk` the legs blend (`BLEND_POUND`, new: there
  was no blend at all). One foot still jumps 26 cm in the first frame of that, and walk to stand 15 cm.
  Where that goes in the inertial layer was not found.
- `slam_in` brings the left hammer down to the floor with no blow, dust or cue, as it always did.
- `reel_o` still pops about a metre at the hammers if parried late in the run-out, where the arms are
  far from flat out. Over `BLEND_HIT`, and a hit-stop is covering it.
- Sounds, still.
