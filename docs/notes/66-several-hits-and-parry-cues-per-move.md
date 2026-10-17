## 66. Several hits and parry cues per move; add them on the timeline (2026-10-17)

The user: "support multiple, I'll do it manually". Supersedes note 65's single
`*_CUE` and the single contacts.

- **decrepit.gd**: each move's blows and cues are LISTS of clip seconds --
  `SWIPE_HITS` / `SWIPE_CUES`, `JUMP_*`, `DROPKICK_*`, `DASH_*` (as shipped, one
  of each: today's values). `_events` puts them on the move's own clock at its
  start (the dash's clip runs slowed through its slide: `_dash_clock`; its FIRST
  hit is its arrival), sorted; `_run_move` fires every cue (`parry_cue`) and
  then every blow (`_contact`) as the clock passes it. Each blow uses the latest
  cue opened before it (player.gd keeps one per attacker and a blow uses it
  up), so cue -> hit -> cue -> hit gives each blow its own parry; a move with
  no cue falls back to the guard-timing rule. Every blow deals the move's
  damage. The lunge / leap is aimed to land the FIRST hit, and how far the clip
  has travelled by then is now read off the root table at that time (the
  *_ROOT_AT_HIT constants are gone), so moving the first hit keeps it aimed.
  The dash's own cue code (`_dash_cue_check`) is gone: the general path does it.
- **tools/timing_preview**: one marker per element ("HIT n", "parry cue n"),
  bound to its index. On a decrepit clip, INSERT a marker named "hit" or
  "parry" (right-click the timeline -> Insert Marker) and its time is added to
  the move's list; DELETE a HIT n / parry cue n and it is taken out (a move
  keeps at least one hit; the last one comes back); drag to move. Lists are
  written back sorted, the markers renumbered. Markers named anything else are
  left alone. A cue's label says how its window closes against the NEXT hit,
  and flags a cue another cue REPLACES before that hit ("no effect").
- **Gameplay found while testing**: a blocked blow shoves the player 5 m back,
  and an unguarded swipe knocks them down (0.6 s immune) -- so a second swipe
  hit 0.17 s later whiffs on its own unless the player stays in reach. A
  multi-hit move wants its hits within reach of each other's shove (or a
  smaller shove for the blocked hits before the last).
- Measured (throwaway harnesses, deleted; scripts restored after): timeline --
  "hit" at 0.65 -> SWIPE_HITS [0.533, 0.65]; "parry" at 0.6 -> SWIPE_CUES
  [0.283, 0.6], renumbered, cue 2 "closes 0.20 s after HIT 2"; a third cue at
  0.5 made cue 1 "REPLACED by cue 2 before HIT 1"; HIT 2 dragged to 0.7;
  deleting cue 2 and HIT 2; the last hit refused and restored; other markers
  ignored; compiles (12/12). Gameplay, the real player, the swipe at hits
  [0.533, 0.7] cues [0.283, 0.6], kept in reach: guard held -> both blocked
  (2.5, 2.5, 2 cues); hit 1 blocked then a tap in cue 2's window -> hit 2
  parried; unguarded -> 25 then the follow-up jump 50; jump 50, dropkick 35,
  dash 15 from 12 m, a dash tap parried (7/7).
