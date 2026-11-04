## 165. Walk and sprint both 0.75 m/s faster, the gap kept (2026-11-04)

The user: "speed the player up, and keep the distance between the walk speed and
the sprint speed". No amount given; +0.75 m/s picked. Supersedes note 162's walk
(2.5) and note 161's sprint (4.25).

### What changed

- `scripts/player.gd`: `move_speed` 2.5 -> **3.25**, `sprint_speed` 4.25 ->
  **5.0**. The gap stays 1.75 m/s (the sprint is now 54% faster than the walk,
  was 70%). The blend is untouched: `_update_sprint`'s critically damped spring
  on `_sprint_k`, `sprint_blend_time` 0.3, `_pace()` lerping the two.
- `SCENE_WALK_SPEED` stays 3.3: scripted scene walks keep the pace they were
  timed at.
- `scripts/stalker.gd` `_hunt_speed`: the Remnant still runs at
  `hunt_speed_ratio` 1.35 x `sprint_speed`, so it rose with it (5.74 -> 6.75 m/s)
  and still outruns a sprint by the same ratio; the dash stays the way out
  (note 161's design). The fallback when the player has no `sprint_speed` is
  now 5.0. Everything else that scales from `move_speed` (attack, drink, axe
  carry scales) scales from the new walk, as before.

### Measured

Throwaway windowed harness (deleted), forward held, Shift sent as a physical key:

```
walk 3.250 m/s   sprint 5.000 m/s   back to walk 3.250
ramp, every 0.05 s after Shift: 3.25 3.33 3.50 3.71 3.92 4.12 4.29 4.43 4.55 4.65
```

Clean `--quit-after` windowed run into the maze: no errors. No frame-time cost.
