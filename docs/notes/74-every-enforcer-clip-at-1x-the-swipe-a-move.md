## 74. Every enforcer clip at 1x: the swipe a move of its own (2026-10-17)

The user, asking why the enforcer's timeline had a "wind-up ends" marker: "all
enemy animations should have the same principles" -- the decrepit's (notes 59,
63-68). The marker was SWIPE_CONTACT, the frame its clip was synced to
enemy.gd's wind-up end: the swipe ran on enemy.gd's WINDUP / ATTACK / RECOVER
timer (windup_time 0.6) and its clip was slowed to x0.58 to fit.

- **The swipe is a move** (enforcer.gd `_start_swipe` / `_run_swipe` /
  `_end_swipe`, as the decrepit's `_run_move`): SWIPE_1_BAKED at 1x from its
  first frame, every time a clip second on the move's own clock (`_swipe_t`):
  SWIPE_HITS (the shield box's windows, unchanged), SWIPE_CUES [0.1167] with
  SWIPE_LISTEN 0.25 (player.gd `parry_cue`; the window closes as the blow
  lands -- the old "guard up <= 0.5 s before" rule no longer applies to it),
  SWIPE_END 1.1. It swings at gap <= SWIPE_TRIGGER 1.65 (the old normal_range
  + 0.4), SWIPE_COOLDOWN 2.2 from the start, turns after the player at
  TURN_SWIPE until 0.08 s before the blow, glows the wind-up colour until the
  first window and the strike's inside one (`is_attacking`), and is broken off
  by a stagger, the beam, the hunt dropping, or any tick `_chase` did not run
  it. `can_normal` is false and `_chase` always returns true: enemy.gd never
  swings for it. windup_time / normal_* / recover_time and SWIPE_CONTACT are
  gone.
- **The charge at 1x**: BEAM_BAKED plays at its own speed to its settle
  (`_beam_set_at`, 0.743 s); CHARGE_TIME (0.65, the clip x1.14) is gone.
- **Timing preview** (enforcer): the swipe's markers as the decrepit's -- parry
  cue, HIT start / end, "move ends (SWIPE_END)"; "parry" markers can be added on
  SWIPE_1_BAKED. The beam's charge label reads the clip.
- Pacing: the blow lands 0.38 s after the swipe starts (was 0.6 s of wind-up
  plus); the move is 1.1 s (was 1.65).
- Measured (throwaway harness, deleted; sandbox, real time): 5 swipes, 5 hits
  of 22, each 0.383 s in with the clip at 0.383 (rate 1.0 throughout, enemy.gd
  state CHASE); the cue opened at 0.117 s; a block pressed 0.2 s in PARRIED
  (stunned, reeling, the swipe broken off), one at 0.05 s (before the cue) was
  a plain block (2.2). The charge lasted 0.74-0.76 s. Blends (shown pose):
  walk->charge 0.19x, charge->recoil 0.04x, recoil->walk 0.16x, swipe->walk
  0.17x; walk->swipe: the switch frames themselves <= 0.1x, the window's worst
  0.56x is the clip's own draw-back starting at full speed.
