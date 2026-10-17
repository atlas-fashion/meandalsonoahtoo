## 71. No dash at close range (2026-10-17)

The user: "the dash is meant to play over a long distance, when it's triggered
up close it looks like a slow motion attack". Supersedes note 61's dash among
the close-range moves.

- decrepit.gd `CLOSE_WEIGHTS` is now swipe 0.5, jump 0.25, dropkick 0.25 (the
  dash's 0.2 dropped, the rest scaled up); `_pick_close` no longer offers it.
- The dash now only starts from `_chase`'s gap-closing branch: DASH_MIN 7 m ..
  DASH_MAX 14 m, off cooldown, a clear floor (note 70). Between CLOSE_RANGE
  3.8 m and 7 m it crawls in or leaps.
