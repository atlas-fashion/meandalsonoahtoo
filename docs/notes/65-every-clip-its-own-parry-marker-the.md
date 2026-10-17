## 65. Every clip its own parry marker; the dash's slide is a fixed length (2026-10-17)

The user: "each animation should have its own independent animation marker".
Supersedes note 62's cue = contact - listen and note 61's variable slide.

- **Independent cues**: decrepit.gd `SWIPE_CUE` 0.283, `JUMP_CUE` 0.2,
  `DROPKICK_CUE` 0.75, `DASH_CUE` 0.2667 -- each move's cue is its own point in
  its clip, no longer worked out from the hit. Dragging HIT moves only the hit,
  dragging the cue only `*_CUE` (tools/timing_preview, note 64); `*_LISTEN` stays
  a number (the user's model: "when the marker triggers, listen x seconds"),
  and the cue's label says how long it listens and whether that window closes
  on the hit, before it or after it (moving one without the other shows it).
- **The dash's slide is a fixed length** (the user chose it from three: fixed
  slide, a fixed cue that long slides could outrun, or a cue relative to the
  arrival): `DASH_SLIDE_TIME` 0.4 s however far (at most DASH_TRAVEL 13 m, so
  up to ~32 m/s from far off), fast at once and easing off, re-aimed, scraping.
  Its clip plays on through the slide instead of holding: 1x to DASH_LUNGE
  0.233, then slowed from DASH_LUNGE to `DASH_CONTACT` 0.3 to fill the slide;
  the blow at arrival = clip DASH_CONTACT; the rest at 1x to `DASH_END` 0.35.
  So the dash has ordinary markers: lunge -> slide, parry cue, HIT (arrives),
  move ends -- all draggable. Removed: DASH_SLIDE_SPEED / MIN / MAX,
  DASH_RECOVER, `_dash_cued`.
- **Trap**: the dash's cue was first opened as the clip's POSITION passed
  DASH_CUE -- from 12 m the animation LOD (anim_full_distance 9 x npc_detail
  on some presets) advances the clip in strides, and the cue opened 0.05 s
  before the blow instead of 0.2. It is now the clip time turned into the
  move's own clock (`_dash_cue_check`: lunge + (cue - lunge) / slide rate).
- Measured (throwaway harnesses, deleted; the real player in the sandbox, real
  time): drags -- HIT +4 f wrote SWIPE_CONTACT 0.6 and the cue stayed at
  0.283 ("closes 0.07 s BEFORE the hit"), the cue -3 f wrote SWIPE_CUE only;
  the dash -- 4 separate markers (0.233 lunge, 0.2667 cue "closes on the hit",
  0.3 HIT, 0.35 end); slides from 4 m and 12 m both 0.42 s (0.40 + a tick or
  two) with the blow on arrival; the cue opened 0.20 s before the blow at
  both distances; a tap in the window parried at 6 m and 12 m.
