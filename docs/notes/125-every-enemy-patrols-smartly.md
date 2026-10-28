## 125. Every corridor enemy patrols, and gets itself unstuck (2026-10-28)

The user: "Make sure all enemies smartly patrol the corridors. They shouldn't
get stuck on corners or stand up against a wall motionless."

This supersedes note 120's `patrol_share` 0.2 ("travelling groups rare"):
the newer instruction wins, and most encounters are single skeletons now (note
121). Convoys stay at one at most.

### Who patrols (maze.gd)
- **`patrol_share` 0.2 -> 1.0.**
- **The real bug:** `_spawn_pack` only ever made a patrol inside the
  enforcer-escort branch. A lone skeleton, or a pack with no enforcer (after
  note 121, nearly all of them), never patrolled whatever the share. It stood
  as a sentry or ambled its little wander patch.
  - Now any pack on patrol gets one (`_start_patrol(column)`), its enforcer at
    the back if it has one.
- Loose subjects (note 120) patrol on their own too: in `_spawn_loose` and in
  `turn_loose_subject` (the ones walking out of a block, note 122).
- collector.gd keeps a shackled subject's own patrol (meta "own_patrol") and
  gives it back if the collector dies.

### Smarter patrols (patrol.gd)
- **Goals in reach.**
  - `_plan` drew goals from every corridor point on the map, so few of 40
    picks fell in 14-40 m, and a leader with no plan stood still.
  - Goals now come from `sample_point`: a random 16 m bucket in reach, then a
    random point in it. The buckets (`_bucket`) are keyed by the points'
    contents and shared by every patrol and every crier.
  - A plan makes at most PLAN_PATHS 16 path queries.
  - **Trap:** the first try scanned every point for every plan, and with every
    patrol replanning the level ran at 1-3 fps. At that rate everything looks
    stuck, because every two-second headway check fails.
- **Longer legs.** The longest leg allowed went from 2x to 3x LEG_MAX.
- **Partial routes.** When nothing whole is found, it takes the best part-way
  route rather than standing:
  - a route whose end the navmesh does not quite reach (more than 3 m short);
  - or a route that meets a shut wooden door, cut 2.6 m short of the door
    (`_until_door`).
  - Either has to go at least PARTIAL_MIN 2 m, so a pocket between shut doors
    gets paced.
  - A failed plan waits 1 s (`_plan_after`); before, it re-ran every tick.
- **Unsticking.** No headway in 2 s, the leader now backs off for
  UNSTICK_TIME 0.7 s, away from the way it was heading and turned up to a
  radian at random. Its next route may not set off within ~53 degrees of that
  way (`_avoid`, for the first 30 tries).
- **Followers.** More than 2.5 m from their place in the column, they steer by
  a navmesh path to it, replanned twice a second; before, they went straight at
  it through the corner. Pressed in place for 2 s, they back off the same way
  (`_ways`, per member).
- Counters for measuring: `stalls`, `plan_fails`.

### Criers (crier.gd)
- They use the same bucket sampling, at most 8 path queries a plan.
- Partial routes too (`patrol._until_door`, at least 2 m).
- Stuck for 2 s: they back off for 0.8 s, away from where they were going and
  dropping a little out from under whatever they hit. The next route may not
  set off the same way (`_patrol_avoid`).

### Measured
Throwaway windowed harness, seed 20260918:
- every type released, then repopulated;
- 100 corridor enemies woken (`dormant_range` 0); the rest asleep, as they
  are in play away from the player;
- the player passive;
- 45 s of positions sampled every 0.5 s.

Before is this commit's parent, with the same harness:

```
                                   before    after
share of half-seconds standing     61.9 %    8.3 %
never left its spot in 45 s        36        5
fps during the test                26        29
```

The five that never left are in pockets behind shut doors. The worst case
before is "stood 6 s at some point": 94 of 100, against 68 after. That still
counts the criers' pauses (0.6-2 s at each stop) and the 1 s waits after a
failed plan.

Waking all 401 at once is not a fair test: it ran at 3 fps.

A clean `--quit-after 1500` windowed run had no errors or warnings.

Bench (RTX 3060, `--bench`, editor open), at the start: 105.2 fps, worst p99
13.87 ms (note 124: 104.8 / 13.93).

### Traps
- A harness has to watch its own frame rate. Wall-clock checks such as "no
  headway in 2 s" call everything stuck when the game crawls.
- `perl -0pi` with `\\\n` in a replacement writes a literal backslash-n, which
  broke crier.gd twice ("Expected new line after \"). Edit continued lines
  with the Edit tool.
