## 114. No moonlight through the roofs: the surgery and the prison shaded from the moon (2026-10-27)

The user: "No moonlight should make it through architecture roofs (surgery
room, jail room)". The jail room is the domed prison (`dungeon_room.gd`
`_build_domed_prison`); the starting jail cell (note 12) was measured too and
was never lit.

### Why the moon got in

A shadow pass culls faces turned away from the light, as the camera does
(`shadow_reverse_cull_face` off, `SHADOW_CASTING_SETTING_ON`). Seen from the
moon above, these roofs show only their BACK faces, so they cast nothing:

- the surgery's ceiling (`surgery.gd` `_build_roof`) is a `PlaneMesh` with
  `flip_faces`, facing down into the hall;
- the prison's dome is the Tripo dome turned inside out (build_brick_kit.py);
- the surgery's raised brick (`_raise_walls`) and the prison's frieze band face
  into the room, so on the moon's side they let it in through the walls too.

So **note 96's "It casts the moon's shadow" and note 38's "the prison dome ...
now cast" were wrong**: `cast_shadow` was on, but the faces it would cast with
were culled. Both floors were as moonlit as an open court, and the volumetric
mist (note 112) carried moon shafts inside.

### The fix: `BrickLevel.moon_shade(parent, size, at)` (brick_level.gd)

An invisible `BoxMesh`, `SHADOW_CASTING_SETTING_SHADOWS_ONLY`, on
`MOON_ONLY_LAYER` (every torch leaves that layer out of its caster and cull
masks, note 38). A box is closed: its faces toward the moon cast, so nothing
under its top or behind its moon-side sides is moonlit; a light INSIDE it sees
only back faces and they cull, so it shades no lamp in the room.

- Surgery (`_build_roof`): the ceiling's span + 0.4 (half a metre into the
  walls) square, from 0.1 m under the floor to `CEIL` + 0.4.
- Prison (`_build_dome_hall`): the whole block (`_block` x 2) square, the
  cells with it, from under the floor to the dome's AABB top + 0.3.

Not chosen: `SHADOW_CASTING_SETTING_DOUBLE_SIDED` on the roofs. It would also
need every wall panel on the moon's side double-sided, and adds back faces to
every torch shadow pass; the box costs one draw in the moon's cascades only.

### Measured

Throwaway harness (`tools/_moon_leak.gd`, deleted): every other light and every
torch hidden, a camera of its own, four views per spot (two down, two up);
moon on, moon off, moon on again (the noise floor), 90 frames apart for the
mist's reprojection; mean brightening and share of pixels brightened > 4/255.

```
spot (view 0)        before                after             noise
surgery corner +1+1  0.0922  42.95%        0.0002  0.02%     0.0000
surgery corner +1-1  0.0620  26.49%        0.0002  0.03%     0.0000
prison centre        0.1043  49.20%        0.0002  0.05%     0.0001
prison corner +1-1   0.1195  52.88%        0.0017  1.25%     0.0018
open court (control) 0.1042  47.44%        0.1044 47.46%     0.0012
boss hall (control)  0.0381  42.78%        0.0381 42.77%     0.0000
```

Every surgery and prison view is now within its noise floor (the prison's
noise is its animated generator and beams); the morgue and the starting jail
cell were already dark (<= 0.0004); the open court and the boss hall, which
are meant to be moonlit, are unchanged. The harness was run once with the
shades hidden (`--no-shade`) to confirm it sees the leak.

Bench, RTX 3060, 3440x1440, the user's profile (editor open, idle), before /
after: overall 74.2 / 74.7 fps, worst p99 22.73 / 22.50 ms; surgery 17.17 /
17.00 ms, chest room 17.01 / 17.14 ms. No cost (noise).

### Traps

- **`cast_shadow = ON` is not "this casts".** A one-sided mesh casts only with
  the faces that look at the light. Check a roof from the moon's side: a
  downward plane, an inside-out dome or an inward-facing wall panel lets it
  through. Measure moon on against moon off; do not trust the setting.
- A shadows-only blocker belongs on `MOON_ONLY_LAYER`, or torches whose masks
  include it pay for it in their shadow passes.
