## 68. Shield hitboxes on both enforcers; hit windows (2026-10-17)

The user: bone-anchored hitboxes for the shields of "both the enforcers" (the
enforcer and the decrepit), "1.5 times bigger than the shield mesh to ensure
good reach", "visible when the hit status is active", and hit markers with "a
start and an end rather than a fixed time". Supersedes the reach checks of
notes 59 / 61 (decrepit `_contact`, enforcer via enemy.gd `_try_connect`).

- **scripts/shield_hitbox.gd** (a BoneAttachment3D): rides ARM_L (both rigs
  carry the shield on it). Sized from the shield mesh itself: the vertices
  skinned >= 0.5 to the bone, taken into its rest space by the skin's bind
  pose, their AABB scaled 1.5x about its centre (cached per mesh + bone).
  Measured: decrepit 0.73 x 2.56 x 0.90 m (shield 0.48 x 1.71 x 0.60),
  enforcer 0.68 x 2.34 x 0.84 m. `overlaps(target)` is a box shape query in
  world units (a query shape cannot be scaled: the rig's scale goes into the
  size, the basis is orthonormalised) against the target's own layer, the
  collider checked. `set_live` shows a translucent red box with outlined edges
  while a window is open, if `Sandbox.show_hitboxes` (on by default, in a real
  game too; a sandbox menu switch).
- **Hit windows**: every blow is a [start, end] of clip seconds. While one is
  open the box is live and the blow lands the first tick it overlaps the
  player, once per window.
  - decrepit.gd: `*_HITS` = lists of windows (SWIPE [0.4833, 0.5833] f29-f35,
    JUMP [0.4833, 0.6], DROPKICK [0.9167, 1.0167] f55-f61, DASH [0.3, 0.35]),
    put on the move's clock in `_events` (`_hit_windows`; the dash's first
    START is its arrival). `_tick_windows` opens / lands; `_touches` = the box
    (+ a clear line, not through stone; the jump's ground strike without) --
    the DROPKICK kicks with its feet, so it keeps its reach check through its
    window and shows no box; `_land` = the outcome (guard, knock-down, combo,
    shove). The jump's sparks at its window's start. The lunge / leap aims the
    first window's START. `_contact` and `_tip_near` are gone.
  - enforcer.gd: `SWIPE_HITS` [[22/60, 26/60]] (the shield across the chest);
    `_try_connect` lands nothing now; `_swipe_windows` runs the windows on the
    swipe's own clock (`_now()` since its clip began x SWIPE_CONTACT /
    windup_time -- not the clip's position, which the anim LOD steps) and
    `_swipe_land` does the blow and the knock-down / shove. SWIPE_CONTACT
    stays only as the frame the clip is synced to the wind-up's end.
  - The box is shut when a move ends, on a parry knock-down, a stagger, the
    beam, and death.
- **tools/timing_preview**: "HIT n start" and "HIT n end" per window, each
  draggable; inserting "hit" adds a window [t, t + NEW_WINDOW 0.1]; deleting
  either marker removes the window (a move keeps at least one). The enforcer's
  swipe has its windows (insert "hit" there too) and a "wind-up ends here"
  marker for SWIPE_CONTACT. A cue's note is against its next window's START.
- Measured (throwaway harnesses, deleted; the real player in the sandbox, real
  time): timeline add / drag end / delete start / drag start, both enemies,
  compiled (7/7); the boxes on ARM_L at 1.5x; decrepit swipe 25 (+ the
  follow-up jump 50 on the downed player), jump 50, dash 15 from 10 m, the
  dropkick 35 by reach with no box drawn, enforcer swipe 22 -- all through the
  box; the player stepping 3 m aside 0.05 s before the swipe's window -> missed
  (0); Show hitboxes off -> never drawn while live. A windowed screenshot
  shows the box round the decrepit's shield mid-swipe. Harness traps: a
  window lands on its FIRST tick, so a dodge must come before it opens; and a
  swipe re-aims until 0.08 s before its window, so standing aside at the start
  is no dodge.
