## 59. The decrepit's new moves; every clip change seamless (2026-10-17)

Supersedes note 56's shield slam (STABS_BAKED is gone) and its move timings.

- **New clips** (`models/source/enforcer/PUTRID_ENFORCER_BAKED.blend`, the user's
  second delivery; only `_BAKED` clips used, the user's rule): CRAWL_BAKED (same
  as before), SWIPE_BAKED (45 f), JUMP_BAKED (75 f, was 105), DROPKICK_BAKED
  (103 f), DASH_BAKED (21 f). CRAWL and DASH came as `*_BAKED.001` -- the build
  drops the suffix. Measured in Blender first (travel, renders) to decide what
  each move is; the user named no roles, so these are defaults to tune:
  - **SWIPE** = the close attack, in the slam's place: SWIPE_TRIGGER 3.8 m,
    contact clip 0.533 s (f33, the shield's point furthest out), 25, unguarded
    knocks down (SWIPE_THROW 12) and the JUMP follows **as the swipe ends** --
    its point lands 0.7 s after the knock-down, inside the player's window
    (invulnerable 0.6 s, down 1.12 s: player.gd `invulnerable_time`,
    KNOCK_FALL + KNOCK_UP). Its 3.15 m lunge is stretched 0..1.6x so the point
    arrives on them.
  - **JUMP** = the jump slash as before, contact now 0.50 s (f31), JUMP_END 1.15.
  - **DROPKICK** = the other leap (LEAP_MIN..MAX 4-9 m, 50/50 with the jump,
    shared LEAP_COOLDOWN 3.5): feet out front at 1.0 s (f61, ~1.6 m up), 35,
    unguarded knocks down (10), no follow-up. Its early sidestep is dropped
    (`straight`): it dives straight at them.
  - **DASH** = the dash stab (3.4-7 m, 30% a roll, DASH_COOLDOWN 2.2): the clip
    stays in place, the body is thrown on an eased curve to put the point
    (1.94 m ahead at 0.233 s, f15) on them, re-aimed each frame, at most 5.5 m.
    15 damage.
  - One generic runner now (`_spec`, `_run_move`, `_contact`): every root-motion
    move stretches its travel before contact on what is LEFT (it re-targets each
    frame), keeps AFTER_CONTACT 0.3 of it after.
- **Build** (`tools/build_decrepit.py`): DROPKICK's knees are NOT eased -- its
  somersault (f21-30 the body spins, shield and calves 2-3 units a frame) reads
  to the flip detector as a dozen knee flips. A new `depop` pass spreads
  isolated one-frame pops (> 35 deg in a frame AND > 3x both neighbours) over
  +-3 frames: SWIPE f16 CALF_R (45 deg), DROPKICK f93 SHOULDER_L (47) and ARM_L
  (72). Not touched, and **left for the user**: DROPKICK f2-5 the shield arm
  whips ~300 deg over the head (38, 61, 75, 126 deg a frame) and stops dead --
  sustained, so authored (probably the IK target's keys), not a spike.
- **Seamless blending** (the user: "you shouldn't be able to tell when each
  animation starts or ends"). `enforcer_react.gd` `crossfade` is now
  INERTIALIZED (Bollo, GDC 2018) instead of freeze-and-smoothstep, for both the
  enforcer and the decrepit: the offset from the new clip and its velocity are
  taken at the switch and decayed on a quintic; the clip plays underneath from
  its first frame. Plus, in decrepit.gd: the crawl is re-entered at the phase
  nearest the pose shown (`_match_phase`, 48 samples, every rotation and
  position track), its playback rate eased (CRAWL_RATE_EASE 7/s) instead of
  jumped, the body's speed carried into a move (`_carry`, shed at CARRY_DECEL
  26 m/s^2) and back out of it (`_move_vel`), and a move's first step run on
  the tick it starts (it stood still a tick: 7.40 -> 0.00 -> 8.06 m/s).
- **Traps, all found by measuring** (each made the "seamless" blend freeze or
  jump while reading fine in code):
  - The skeleton updates **2-3 times in one frame** when a clip is switched (the
    seek, then the frame), and the mid-frame call is passed delta 0. Time and
    history advance once per FRAME (`Engine.get_process_frames()`), time from
    `get_process_delta_time()`.
  - Far rigs only move their CLIP every few frames (enemy.gd animation LOD, by
    distance from the PLAYER: Graphics.anim_full_distance 14 m) while the
    skeleton still updates between, so the last two poses are often the same:
    history is the last two DIFFERENT poses, each with the frame it appeared.
  - Bollo zeroes a velocity moving away from the new pose -- every such bone
    stopped dead at the switch. Kept (capped 2*x0/t1) and turned round.
  - Bollo shortens the blend when closing fast -- down to 1-2 frames, a dead
    stop. Floor INERTIA_MIN 0.1 s, the closing speed capped to fit.
  - The `.001` bones (ARM_L.001, FOOT_L/R.001) are IK helpers with NO skin
    weight; a smoothness check must measure the 10 weighted bones (+ the shield
    tip), or it chases motion nobody sees.
  - A harness that teleports the player in from 14 m measures LOD'd crawls no
    real fight has: let it close in.
- `decrepit_react.gd` sets `keep_tracking` (the layer stays on while awake, so a
  switch always knows how the rig was moving); enforcers keep the old on-demand
  behaviour (57 of them).
- Measured (throwaway harness, deleted: a decrepit vs a stub player, every move
  natural or forced, the camera at the player's eyes, 60 fps): swipe 25 ->
  knock-down -> jump 50 (combos 1); dash 15; dropkick blocked 3.5 (35 x 0.1);
  jump 50; parried swipe -> on its back and up. Per drawn frame, the worst
  change of velocity of any weighted bone or the shield tip across a switch,
  against the worst inside the clips: crawl->swipe 0.13-0.15x, swipe->jump
  0.11x, jump->crawl 0.06x, crawl->dash 0.17x, dash->crawl 0.02x,
  crawl->jump 0.03x, swipe->crawl 0.02x; crawl->dropkick 0.82x is the
  dropkick's own f2-5 whip (the switch frames themselves 0.07). The old
  freeze-and-ease on the same run: crawl->swipe 0.31x with a frozen frame.
  Enforcer, every switch forced: <= 0.37x, no errors. Game boot (--skip-title,
  2400 frames headless): no script errors, three decrepits spawned.
