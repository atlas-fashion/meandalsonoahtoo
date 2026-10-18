## 75. The enforcer's swipe loop: swipe 2 dashes; beams broken off (2026-10-17)

The user sent SWIPE_2_BAKED (ENFORCER_UNBAKED.blend, 42 frames, a backhand): close
in, the enforcer always breaks off its beam for swipe 1; swipe 1 connecting
throws 1.75x as far; missed or blocked, swipe 2 dashes at the player and swings;
missed or blocked again, round again -- until (A) a blow connects, (B) it is
parried (it recovers, then resumes the loop) or (C) the player is far enough
for the beam. "make sure to create a blend between swipe 2 and 1."

- **Clip**: appended to `models/source/enforcer/ENFORCER_BAKED.blend` on its own
  NLA track; the build exports it and prints its shield path (fastest f12-14).
  Measured in Blender: the backhand sweeps across the front f3-15 with the
  torso lunging 0.42 m (in the clip), swings up and over f28-36, and stands up
  f17-42 (it starts crouched, as swipe 1 is after its strike).
- **The loop** (enforcer.gd THE SWIPE LOOP, `_start_swipe(kind, blend, from)`,
  `_run_swipe`, `_loop_on`, `_slide_step`): each swipe a move on its own clock;
  nothing connected by its chain point, it starts the other. Swipe 1 -> 2 at
  SWIPE_CHAIN 0.533 (after its hit window, which the user had moved to
  0.333-0.517 in the timeline): its pose there is swipe 2's first (joints
  0.1-0.8 units apart; best at f30, inside that window), BLEND_CHAIN_12 0.15.
  Swipe 2 -> 1 at SWIPE2_CHAIN 0.35 (f22) into swipe 1 at SWIPE1_LOOP_ENTRY
  0.2333 (f15), BLEND_CHAIN_21 0.2: crouched to crouched -- played to its end
  swipe 2 stands up and swipe 1 crouches again ("he shouldn't get back up
  briefly between swipe 2 and 1"). No authored link: the straight blend was
  rendered first, the shield stays in front, clear of the body. Swipe 1's own
  crouch (f15-16) ducks the torso 0.1 m under the blend: tried entering after
  it (f16 -> f17, torso dead level) -- the user preferred the duck, and the
  time between swipes went uneven; reverted.
- **Swipe 2's dash**: from SWIPE2_LUNGE 0.083 the body slides to SWIPE2_ARRIVE
  1.3 m from the player, arriving as its hit window opens (SWIPE2_HITS
  0.15-0.233); the slide lasts distance / SWIPE2_SLIDE_SPEED 14, at most
  SWIPE2_SLIDE_MAX 0.45, never less than that bit of clip at 1x (no slow motion
  up close); the clip slowed to fill it; eased (fast, then easing into the
  blow), re-aimed every frame. Its cues and blows are mapped through the slide
  (`_swipe_clock`) at the lunge. SWIPE2_CUES [0.1333], SWIPE2_LISTEN 0.25.
- **Ends**: (A) a blow connects -> that swipe plays to SWIPE_END / SWIPE2_END,
  then the walk; the next loop SWIPE_COOLDOWN 1.1 after. (B) parried ->
  `_resume_loop`: once the stagger is over, swipe 1 if close, swipe 2 if within
  LOOP_BREAK. (C) at a chain point the player is beyond LOOP_BREAK 7 m -> the
  loop ends (the beam may follow). Close in during a charge or a fire it
  `_cancel_beam`s for swipe 1, whatever its role or cooldown.
- **The throw**: SWIPE1_THROW_SCALE 1.75 is distance; the throw is x sqrt(1.75)
  (distance goes with its speed squared: x1.75 on the throw sent them 17.6 m).
  Measured: 6.61 m -> 11.24 m (x1.70).
- **player.gd `guarded_invulnerable_time` 0.25** (new): a blocked or parried
  blow gives that much grace instead of `invulnerable_time` 0.6 -- at 0.6
  swipe 2, landing 0.36 s after a blocked swipe 1, always met an invulnerable
  player and never connected (measured: its box overlapped them, every time).
- **Timing preview**: SWIPE_2_BAKED's markers (lunge -> DASH, parry cue, HIT
  start / end, chain into swipe 1, end), swipe 1's chain into swipe 2 and its
  loop entry; all draggable, "hit" / "parry" can be added on both.
- Measured (throwaway harness, deleted; sandbox, real time): unguarded -> swipe 1
  hits (22), thrown, the loop over, then the beam; block held -> S1 S2 S1 S2...,
  every blow blocked (2.2), ~0.33 s apart; stepped 4 m off as swipe 1 swings ->
  swipe 2 dashes from 4 m and hits; put 9 m off -> loop over, beam; walked in
  while it fired -> beam broken off, swipe 1; parried at the cue -> stagger
  2.1 s, swipe 1 again (three times). Blends (shown pose): walk->S1 0.10x,
  S1->S2 0.28x, S2->S1 0.52x of the clips' own p99.
- **Parry stagger 1.5 s** (was 2.1; the user: "0.6 seconds shorter"): enforcer.gd
  PARRY_STAGGER and enforcer_react.gd STAGGER, every key time scaled by 1.5/2.1
  so the whole reaction plays, faster. Measured: 3 parries, stunned 1.50 s each.
- **A breather** (the user: "far too pressuring"): after every LOOP_PAUSE_EVERY 3rd
  swipe of a loop that did not connect, LOOP_PAUSE 0.5 s before the next -- the
  swipe plays on through its follow-through meanwhile, turning to face the
  player; then the next with the plain move blend, swipe 1 from its START (its
  whole wind-up; entering it at its loop entry evened the pauses out, but the
  user preferred this). The count restarts with each new loop. Measured, block
  held: blows 0.30-0.35 s apart, 0.85 and 1.03 s across the pauses. SWIPE2_HITS start moved to 0.1667 by the user.
