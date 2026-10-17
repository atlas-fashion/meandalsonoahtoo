## 43. The criers (2026-10-14; were the bombers)

- **Renamed**: `scripts/crier.gd`, `scenes/crier.tscn`, node "Crier", group
  "crier" (was bomber / "bomber"); maze's `flyer_scene` and bone_cage's shard
  helper (`CRIER._solid_piece`) follow. The player's haft-strike code and its
  comments still say "bomber": nothing calls it.
- **Behaviour** (supersedes section 42's wind-up and lunge): the moment it SEES
  the player -- in `aggro_range` 32 m, a clear line on the sight layer (doors
  block it), the player not hidden or in a scene; checked every 0.1 s, every
  tick while seen -- it flies STRAIGHT at the face at `rush_speed` 14 m/s
  (walk 4.25). Out of sight it navigates to where it last saw them for
  `memory` 5 s, then hangs bobbing. Reaching the face it STICKS with no blow;
  the only attack is the explosion after `face_fuse` 1.8 s, through the guard
  (`take_damage(50, dir, self)`): parried 0, blocked 10%. Shatters either way.
- **Model**: the warden's head (warden.gd `_fill_head`: plate box, neck, brass
  lens rim, aerial; built with warden's static `_box` / `_cyl` / `_mat`) at
  `HEAD_SCALE` 2.0, merged once and shared, centred on the box, with the gold
  crystal lens as its own mesh. The lens blinks (gold -> white-hot) with the
  light; the plates warm with the fuse (their own material copy) and flash on
  a hit. On the face it is turned round so the lens looks at the eyes.
  `_pieces` now cuts every surface of the mesh, not just the first.
- Measured (9/9): rushed in at 14.0 m/s, stuck 0.73 s after appearing 10 m
  away, 100 health after sticking; unguarded 50, RMB 0.25 s before -> 0, guard
  held -> 5; 9 pieces; 20 + 20 alive, a third breaks it; behind a shut door
  never on the face; control, the door open -> stuck.
- Bench (RTX 3060, 3440x1440, Ultra, editor closed): 73.6 fps, worst p99
  27.81 ms, 1090 MB (74.5 / 27.13 / 1090 before) -- noise.

