## 115. The enforcer's feet stay planted: the body moves as the planted foot does (2026-10-27)

Asked for: the enforcers' speed through the world to match their walk's stride
so the feet stay planted, without touching the animations. Supersedes the walk
rate in note 48 (speed / `WALK_GROUND_SPEED` 0.82 at a steady glide).

**What the walk really is** (measured from WALK_BAKED's own tracks, FOOT_L /
FOOT_R in the body's space): a stomp. Each foot's stance has two lurches, each
a hold (the planted foot still, ~10 frames) then the planted foot sweeping back
faster and faster -- 0 to 4.3 m/s at rate 1 -- until it stops dead. The two
stances are uneven (0.90 m and 1.16 m at the drawn size). Mean over the 2 s
cycle: **1.03 m/s at rate 1** (the old 0.82 figure was off too). Both feet are
down twice a cycle (clip ~0.00-0.17 s and ~1.00-1.20 s).

So no steady body speed can plant those feet: gliding at 2.2 m/s with the walk
at x2.68, the planted foot slipped **1.15 m for every metre walked** (harness
below).

**What was built** (`scripts/enforcer.gd`, "THE GAIT" by the constants and the
gait section after `_hold`):
- `_build_gait()` (end of `_ready`) / `_read_gait()`: reads the walk's feet
  straight out of the Animation's tracks (`_bone_at`: position / rotation /
  scale tracks composed up the parents, rest where a bone has none; nothing is
  posed), turned into the body's space through every node between the
  skeleton and the body. Per 1/60 s sample: the lower foot across the sample is
  the planted one; `travel` accumulates how far it moved back (+Z, the body
  faces -Z; a planted foot creeping forward counts 0). `stand` marks samples
  where both feet are within `GAIT_STAND` 0.04 m of their lowest and the
  planted foot sweeps under `GAIT_HOLD` 0.1 m/s. Cached per Animation in the
  static `_gaits` (every enforcer shares the clip and the scale).
  `_gait_mean` = one cycle's travel / clip length.
- `_slide()` override: while `_gait_live()` (the walk clip on, no swipe, beam
  charge/fire, stun, stagger, death; on the floor) the body is moved, this
  tick, exactly as far as the planted foot swept over the span of clip the
  rig has just been stepped through (`_gait_travel(_walk_time() - span,
  span)`; `_walk_time` adds enemy.gd's animation-LOD debt), along the asked-for
  direction. Then `velocity` is put back to the asked-for speed, turned along
  whatever it met -- so all the steering (`_walk_to`, enemy.gd's states,
  patrol.gd, the escort code) keeps working on its own figures, untouched.
- `_animate()`: the walk plays at the asked-for speed (`velocity`, no longer
  `get_real_velocity()`, which is now the lurching step) over `_gait_mean`,
  clamped 0.4-3.2 as before. **Backwards** (negative `speed_scale`) when the way
  it goes is behind it (`GAIT_BACK` -0.3 cosine): the Role.BEAM back-off,
  which used to moonwalk. **Asked to stop**, it keeps its rate to the end of
  the step and stops at a `stand` sample (both feet down); under rate 0.3 it
  just stops. A clip with no readable feet falls back to the old eased rate.

**Measured** (throwaway harness, deleted: an enforcer on a plain floor made
to run via `_scared_until` / `_scared_to`; each physics tick the lower foot's
world displacement while it stays the lower one = slip):

```
                       before (glide)       after (gait)
run 2.2 m/s + stop     1.148 m slip per m   0.004 m per m   p95/frame 0.12 -> 0.0004 m
walk 1.3 m/s + stop    1.239 m per m        0.005 m per m (excluding the 180-degree turn's one frame)
backwards 1.6 m/s      (moonwalked)         0.004 m per m, rate -1.55
```
The run now stops 0.23 m from its goal (0.81 before) and always on both feet.
Speed through the world over a cycle is unchanged (move_speed 2.2, wander 1.3);
within a step it surges to ~7.5 m/s at 2.2 m/s and stands still in the holds --
that is what the user's walk animates, so that is what the body does. A smoother
gait would need a smoother walk clip.

**Traps:**
- **Read the span the clip has JUST run, not the one ahead.** enemy.gd steps
  the rig (`_advance_anim`) before the AI moves the body, so the pose shown this
  tick is already at the end of its span. Moving the body by the span ahead left
  it a tick behind its feet: 0.50 m of slip per metre walked with this stomp
  (the lurch's fast frames land on the hold's still ones).
- `get_real_velocity()` is the step's lurch now; anything wanting the speed the
  enforcer is *trying* to go reads `velocity` (restored after each slide).
- A SceneTree harness cannot `preload` enforcer.gd (it names `Graphics`); `load`
  it at run time. And `root` is SceneTree's own member -- name the node
  something else.
- Turning is still instant (`_face`), so a reversal swings the feet round in one
  frame; that is turning, not the gait.
