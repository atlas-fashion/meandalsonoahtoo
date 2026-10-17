## 62. Parry cues: the attack listens for block (2026-10-17)

The user's design: rather than a window on the player's guard, an attack marks a
point in itself and "when the marker is triggered, listen for block input for
the next x seconds".

- **player.gd** ("Parry cues"): `parry_cue(attacker, listen)` opens a window
  [now, now + listen] for that attacker (`_parry_cues`, by instance id; ones
  older than 5 s are dropped). Every block press that COULD have raised the
  guard -- a weapon in hand; not dead, in a scene, in a menu, drinking,
  ghosting, slamming or knocked down / in a slam's recovery -- is timed
  (`_note_block_press` -> `_block_pressed_at`), mid-attack too: it is the
  PRESS that is timed, not the guard, and a tap counts held or not. When that
  attacker's blow lands, `_guard(blow, attacker)` uses the cue up: a press in
  its window (from the front, `block_arc`) PARRIES; otherwise a raised guard
  blocks and no guard takes it in full. Attackers that open no cue (skeletons,
  enforcers, criers, the boss...) keep the old rule (guard up within
  `parry_window` 0.5 s of the blow).
- **decrepit.gd**: each move's `_spec` has `cue` (clip seconds) and `listen`;
  `_run_move` calls `parry_cue` as the clip passes the cue. Defaults place each
  window to close as the blow lands (cue = contact - listen): SWIPE_LISTEN
  0.25, JUMP_LISTEN 0.3, DROPKICK_LISTEN 0.25, DASH_LISTEN 0.2. The dash's blow
  comes when its slide arrives, so its cue opens DASH_LISTEN before the
  estimated arrival -- during the crouch for a short slide, during the slide
  for a long one (`_dash_step`, `_dash_cued`).
- The cue is DATA in the move table keyed to clip time, not a key in the .glb:
  a reimport regenerates the clips (a key added in Godot would be lost), and
  the code already tracks each clip's time through stretching and holds.
- Measured (throwaway harness, deleted; the real player in the sandbox, real
  time -- the clocks are wall time, note 61): 23/23. For each of swipe, jump,
  dropkick and dash: a tap inside the cue's window parried (0 damage, the
  decrepit on its back); the guard held from before the cue blocked (10%: 2.5,
  5, 3.5, 1.5); a tap before the cue, no press, and a press after the blow
  all took it in full; uncued attacker: guard up 0.1 s parried, 1.1 s blocked;
  a press while knocked down was ignored. Harness trap: `_check_block` drops
  a guard whose button is not actually held -- press the action
  (`Input.action_press`) rather than only calling `_start_block`.
