## 175. A queued swipe goes straight on from the last; no return to the guard between (2026-11-10)

The user's goal: realistic, immersive, satisfying combat, first person the main view. Asked for:
when another swipe is queued, the sword blends straight from the end of one swipe into the next
instead of going back to the resting pose first.

### What it was

Note 174 made each cut play its whole clip before the next could start: the cut, its
follow-through, and then the blend home into the stance (`out` -> `end`, 0.27 / 0.26 pose s). The
next stroke then blended in from the stance (`in` 0.08). So a held combo went cut, home to the
guard, out again -- the hand came back to within ~4 cm of the guard between every stroke.

### What it is

- `player_motion.gd` MOVES: `slash` and `chop` have a `chain`, the pose second where the stroke is
  over and only its blend home is left -- the forehand's 0.50 (its `out` moved 0.48 -> 0.50 so the
  hand-over lands exactly on the backhand's first frame, clip 1.08), the backhand's 0.40 (its `out`).
  `chain_in`, how long the next move cross-fades in over the last: 0.14 for the forehand (the
  backhand's end is far from its gather), 0.08 for the backhand (the poses meet). Default for other
  moves `max(in, CHAIN_IN 0.1)`. `chain_point()`, `chain_in()`, `chain_fade()`.
- `player.gd` `_stroke_end()` over a cut is now `PlayerMotion.chain_point` (was `length`): a queued
  click (note 151) begins there; a click after it, during the blend home, begins at once.
- `_begin_pose`: a clip move begun over another still showing records it (`_from_kind`, `_from_t`,
  `_from_w` = its weight at the hand-over). The old move keeps running on its own clock under the new
  one (`_update_pose`, clamped to its length) at that weight, and is dropped once the new move's
  `chain_in` has passed. This also covers Q (heavy) or F (wave) over a cut, and a cut over the
  heavy's recovery -- those used to snap to the stance in one frame (the new move's `weight_in(0)` is
  0) and now cross-fade.
- `motion_weight(kind, t)`: the move's weight -- over a from-move, `chain_fade * weight_out`, else
  `PlayerMotion.weight`. `body_motion_from()`: [kind, t, w] of the from-move, or [].
- `coop_avatar.gd` `_apply_motion`: stance, then the from-move at its weight, then the new move at
  `motion_weight` (slerp layering, so at fade 1 it is wholly the new move); the attack lean uses the
  two combined.
- The view: `_ride_at(kind, t, w)` takes the weight; `_ride_blend` lerps the from-move's ride into
  the new move's (weighted by its `weight_out` only) by `chain_fade`, for both the ride and its
  fed-forward speed. `PlayerMotion.view_yaw` takes an optional weight.
- HUD LMB tile: full length is the forehand's `chain`, 0.50 x 1.25 = 0.625 s.

Cadence of a held combo: forehand 0.625 s, backhand 0.50 s real (note 174: 0.94 / 0.83; before it
0.39-0.50). Each stroke still plays its cut and follow-through whole; only the trip home is gone.
A single click still goes home to the guard over the rest of its clip.

### Measured

Throwaway harness, headless, `--fixed-fps 60` (main.tscn, `--no-enemies --no-intro`): one slash, one
chop, then a click every 0.05 s for 2.5 s, then a slash with Q pressed 0.5 s in; the knight's
`RightHand` (skeleton space, ~cm), its speed per frame, and `_view_rot` logged every frame.

```
single stroke: hand back within 4-5 units of the guard at its end
held combo:    hand at hand-over 86 / 101 units from the guard (never goes back)
forehand -> backhand  speed 347 198 153 75 | 30 31 46 55 100   (decel to the turn, then the backhand)
backhand -> forehand  speed 111 66 55     | 47 84 234 338 402  (straight on into the gather)
view (deg) through each hand-over: changes <= 0.1 a frame
slash cut -> Q heavy: cross-fades over 0.1 pose s (was a one-frame snap to the guard)
```

First version handed over at the backhand's 0.42, past its `out` 0.40: the from-move's weight was
frozen at 0.97, so the hand twitched 3% toward the guard for one frame (speed 44 -> 197 -> 77). Hand
over at or before `out`. Clean `--quit-after 600`: nothing on stderr. Frame time not measured: one
more clip laid on for 0.08-0.14 s after a hand-over.

### Traps

- A hand-over past the old move's `out` freezes it part way home: chain at or before `out`.
- `_ride_at` must not weight the new move by its own `weight_in` during the fade AND lerp by the fade
  -- that counts the fade twice; it uses `weight_out` there.
- The harness's rows and the pose are in step (checked: the first forehand's distance from the guard
  tracks `weight_in` of the logged time, not the frame before).
