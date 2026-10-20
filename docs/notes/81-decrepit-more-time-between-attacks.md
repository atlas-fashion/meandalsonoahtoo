## 81. The decrepit: more time between attacks (2026-10-20)

The user: "add a little more time between the decrepit enforcer's attacks".
Every gap the decrepit leaves between moves was made about 20% longer, in
`scripts/decrepit.gd` (constants only; no logic changed):

| constant | before | after | what it gates |
|---|---|---|---|
| CLOSE_PAUSE | 0.25-0.7 s | 0.3-0.85 s | the breath after any move ends before the next close-in move (`_end_move` -> `_close_ready`) |
| SWIPE_COOLDOWN | 1.3 s | 1.55 s | from the swipe's start |
| JUMP_COOLDOWN | 3.0 s | 3.6 s | from the jump slash's start |
| DROPKICK_COOLDOWN | 3.5 s | 4.2 s | from the dropkick's start |
| DASH_COOLDOWN | 2.2 s | 2.65 s | from the dash's start |

Left alone on purpose:
- The swipe -> jump slash combo on a knocked-down player (`_combo_pending`):
  it is one attack, and its timing is what lands the jump before they are up.
- Getting up from a parry (`_knock_t` end) still resets every cooldown and the
  breath to now: "straight back into the attack" is that move's point
  (note 61). Lengthening the lie (KNOCK_LIE) is the lever if that reads too
  fast.
- The move clips, hit windows and parry cues (the user's own timings, last
  retuned 2026-10-18 in the timing preview): untouched.

The cooldowns run from a move's START, so for the swipe the binding gap is
whichever ends later: 0.733 s of clip + the breath, or SWIPE_COOLDOWN. Before:
max(0.98-1.43, 1.3) s between swipe starts; after: max(1.03-1.58, 1.55) s.

Not measured in game: this change was made in a cloud session without Godot.
Note 61's harness trap applies to anyone who checks it: enemy.gd's clocks are
wall time, so run without `--fixed-fps` or no cooldown ever expires.
