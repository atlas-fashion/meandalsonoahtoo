## 92. No sticking to corners (2026-10-20)

The user: "Make the enemies and players not stick to corners."

**Why they stuck.** The brick kit's collision (`brick_level.gd`) steps out of
the wall line at every archway and junction: an arch leg's inner face is at
`ARCH_INNER` 1.69 m from the corridor's centre against the wall face's
`WALL_FACE` 1.9 (0.21 m proud), and a junction pillar's at
`PILLAR_AT - PILLAR_HALF` = 1.55 (0.35 m proud). A capsule walking straight
along a wall meets the step's vertical EDGE and rounds it -- that mostly
worked. But a body leaning into the wall as it walks (anyone steering by
hand, and enemies whose path hugs a wall) slides along the wall into the
crease and meets the step's face square on; move_and_slide has nothing left
to slide along and stops dead. A path cutting a junction's corner jams on the
pillar the same way.

**The fix** is code, not geometry: `scripts/corner_slip.gd`
`CornerSlip.slide(body)` is move_and_slide, then, only when the body made
less than `STUCK` (35%) of the headway it asked for:
1. Works out the way it is really trying to go: the heading turned along any
   wall it was leaning on (slide collisions whose normal is shallower than
   `SQUARE` -0.6), and along any it glances off on lifted probes ahead.
2. If the way ahead is clear off the floor, walks it (see the jam below).
3. If something stands square across it, tries sideways offsets
   `SIDE_STEPS` (0.06 ... 0.55 m) each way, nearest first, for a spot from
   which the way is clear, and steps toward it at walking pace.
Another walker in the way (a CharacterBody3D) is a crowd, not a corner: left
alone. A whole wall is wider than 0.55 m, so walking straight into one still
just stops.

Wired in: `enemy.gd` `_slide()` replaces every `move_and_slide()` in
`enemy.gd`, `archer.gd`, `decrepit.gd`, `enforcer.gd`, `sewer_lizard.gd`;
`player.gd`'s main walk (the one before `_update_locomotion()` at the end of
the physics step) calls `CornerSlip.slide(self)`. Not the cutscene hold, the
planted axe, the spear dash or the slam: those stand still or are meant to be
stopped by stone.

**Measured** with a throwaway harness (built the real brick level, seed
20260928, headless -- collision only, no MultiMesh readback) that walked
player-sized capsules (r 0.4) at 4.5 m/s for 3 s:

```
                       before   after
hug (along the wall)    6/344   0/344
hug leaning 19° in    344/344   0/344
cutting each turn     511/511   0/511
head-on into a wall   0/150 slipped   0/150 slipped (still stop at the face)
ended inside stone        0       0
```

**Traps.**
- The first version probed "ahead" along the raw heading. Leaning into a
  wall that heading points into the wall, so no sideways spot ever looked
  free and the leaning case barely improved (1148 -> 890 stuck). Project the
  heading along the leaned-on wall first.
- A capsule pressed onto a pillar's edge sometimes sinks a hair into the
  floor and jams: every move_and_slide reports only the floor with zero
  travel, while a probe lifted `LIFT` 0.08 m is clear. That branch steps it on
  from the lifted spot; floor snap and gravity set it down.
- Test trials have to be fair: a "hug" walk where the wall ends at a side
  opening walks into the side corridor's far wall and correctly stops.
- "It's not expect to not find the most reachable polygons" (note 77) showed
  once in 8 game boots with this change and 0 in 5 without; it comes from a
  sewer lizard's wander path query and is intermittent by layout, so this is
  not conclusive either way. Watch for it.
