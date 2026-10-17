## 61. The decrepit's dash slides in; every move close in (2026-10-17)

Supersedes note 59's dash (a quarter-second stab lunge, 3.4-7 m) and its
move choice (the swipe alone close in).

- **The dash is the gap closer** (the user: "he should slide to you"):
  decrepit.gd `_dash_step`. The clip plays its crouch and is thrown into the
  lunge (DASH_LUNGE 0.233 s, f15), then is HELD there (`anim.speed_scale` 0)
  while the body SLIDES at the player along the floor: re-aimed every frame on
  what is left of the way (the player moving included; turning until the last
  quarter), fast at once and easing off (`_ease_slide`, 1 - (1 - u)^2) to
  arrive with the point on them; time = travel / DASH_SLIDE_SPEED 15 m/s,
  clamped DASH_SLIDE_MIN..MAX 0.1-0.9 s; at most DASH_TRAVEL 13 m; scraping
  sparks under its front every SCRAPE_EVERY 0.05 s (`_scrape`, effects on,
  no light). On arrival the blow (15) and the rest of the clip, rising out of
  the lunge (DASH_RECOVER 0.2). Its spec's contact and end are INF: both come
  from the slide. From DASH_MIN..DASH_MAX 4.5-14 m (35% a roll), and close in.
- **Every move close in** (the user: "make the swipe not the only close range
  attack"): within CLOSE_RANGE 3.8 m `_pick_close` picks among the moves off
  cooldown by CLOSE_WEIGHTS (swipe 0.4, jump 0.2, dropkick 0.2, dash 0.2), the
  last one used at CLOSE_REPEAT 0.3 of its weight, after a breath of
  CLOSE_PAUSE 0.25-0.7 s from the last move's end (`_close_ready`). The jump
  and the dropkick shrink their travel to land on them (stretch from 0); each
  now has its own cooldown (JUMP_COOLDOWN 3.0, DROPKICK_COOLDOWN 3.5; was a
  shared LEAP_COOLDOWN). Further off: the dash, or a leap (jump / dropkick,
  whichever is ready) at LEAP_MIN..MAX 4-9 m.
- **Harness trap**: enemy.gd's clocks are WALL time (`_now` =
  Time.get_ticks_msec), so under `--fixed-fps` (which drops real-time sync) a
  small scene runs ~100x real time and no cooldown ever expires -- the close
  fight made 0 moves in "40 s". Anything that depends on cooldowns runs without
  `--fixed-fps` (or by the frame on a heavy scene, as the level is).
- Measured (throwaway harness, deleted; a stub player, real time): a dash from
  8.0 m slid in over 0.30 s with the lunge held every slide frame, stopped
  2.01 m off (the point on them) and landed 15; the player stepping 3 m aside
  mid-slide, it re-aimed and hit (2.37 m off); held 2.5 m in front of it for
  40 s: all four moves -- swipe 11, dropkick 7, jump 5, dash 4 -- 27 in all.
