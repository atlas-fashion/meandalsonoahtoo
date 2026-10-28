## 118. The surgery: the pen soldiers face the hall; no black gaps in its walls (2026-10-27)

The user: enemies in the surgery "always appear sideways", and there are
"black gaps in the architecture the player can't enter; fill them with
geometry that matches the surrounding architecture".

### The soldiers faced the back of their pens

`surgery.gd` `_build_dispatch` gave every pen spot a yaw of `-PI/2` in the
plan's frame, and the soldier dropped in the pens by the entrance scene
(`_intro`) the same. An enemy faces its **-Z** (enemy.gd `_face`:
`atan2(-dir.x, -dir.z)`), and `Basis(UP, -PI/2)` turns -Z to **+X** -- the
pens' own back wall (the pens are column N-1, the +X side). So from the hall
they showed their backs, and from the aisle along the bars their profile.
Now `PI/2` (+-0.25 jitter): -X, out through the bars. Measured in a
throwaway harness: the six pen soldiers' facing in the plan frame went from
(0.97..1.0, 0, ...) to (-0.97..-1.0, 0, ...). Thrown soldiers and the claw's
cargo were already right (the claw hangs a body at its own yaw; turned loose,
it chases and `_face`s).

### The gaps were slits between the raised brick pieces

`_raise_walls` carries the brick kit's wall piece up to the roof (two courses,
3.5-7 and 7-10.5 m) on every wall face. The piece's edges are ragged (it is
5.19 m wide nominally, scaled to the 6 m cell), so where two pieces meet --
along +-3 and +-9 m, exactly where the gothic frames are open at their joins
(note 101) -- there were wedge-shaped slits, mostly 4-8.6 m up, through to
nothing (behind the walls the corridors' lids stop at 6.4 m). With the fog
they read as black.

Fixed with a second skin of the **same brick mesh** behind the raised brick
(`BackingBrick`, a MultiMesh, in `_raise_walls`): pieces half a cell along
(their joins behind the front pieces' solid middles), set back from the wall
face by `BACK_ROWS` -- a row at 3.5 m 0.45 m back and a row at 5.6 m (to
9.1 m, past the 8.6 m ceiling) 0.6 m back, so the overlap does not z-fight.
A slit now shows recessed brick. Over a way in only the upper row (from
5.6 m), clear of the corridor's vault (crown 5.1 m). It casts no shadow.

The moon shade (note 114) is untouched: `_build_roof`'s shadows-only box
still spans the hall; the backing sits at its edge and needs none.

### Measured

Throwaway harnesses (deleted), windowed: the environment's background made
magenta, fog and mist off, distance culling off, flat ambient; a camera at 9
spots at eye height and one at 6 m, 8 headings x 2 pitches; magenta pixels
counted at quarter size (the background renders as dark purple through the
grade, so the test is relative: b > 0.06, r > 0.6 b, g < 0.3 b).

```
                       magenta px (160 views)
before                 121,316
backing, 3 rows          659
backing, 2 rows          990     (kept: what is left is scattered specks)
```

The "before" run is the re-break check: the test sees the slits. From the
corridors outside both ways in, looking back at the arch and up at the vault:
identical before and after (nothing pokes through).

Bench, RTX 3060, 3440x1440, surgery station (avg ms / gpu ms / p99):

```
before                  16.90 / 15.04 / 22.86     17.14 / 15.08 / 23.35
backing casting, 3 rows 18.36 / 16.53 / 25.19
soldier fix only        17.10 / 15.03 / 25.00
backing, 2 rows, no cast 17.20 / 15.31 / 25.00    17.61 / 15.29 / 25.34
```

The backing costs ~0.25 ms of GPU. Casting shadows it cost 1.5 ms (the
torches' shadow passes), which is why it does not. The p99 rose ~2 ms with the
soldier fix alone (no geometry changed); it is the soldiers now facing the
station's camera -- not investigated further.

### Traps

- **An enemy faces -Z.** A yaw for an enemy is `atan2(-dir.x, -dir.z)`; check
  which way -Z ends up, not +Z.
- **`cast_shadow = ON` is not free for hidden geometry.** Geometry behind a
  wall still renders into every torch's shadow pass; anything only there to
  be glimpsed through a slit should not cast.
- A magenta background renders as dark purple through the game's grade;
  detect it by hue, not by absolute value.
