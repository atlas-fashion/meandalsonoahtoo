## 33. Torch shadows (2026-10-12)

- **Nothing cast shadows before this**: every torch light had `shadow_enabled`
  false and every brick chunk `cast_shadow` OFF (the settings menu still said
  the hand torch -- removed in section 9 -- was the only caster). Now every
  torch hung by `module_level._hang_torch` casts (meta `torch_shadow`), and the
  corridor pieces cast except `brick_level.NO_SHADOW` (floor, bed, cap, skirt:
  lit only from above or outside the corridor). Doors (frame + leaf), hiding
  carts, convoy carts, anchors (not the crystal), the workbench and skeleton
  swords cast too; skinned enemies always did. Torch mounts and the pilaster
  pillar do NOT (they would shade their own light).
- **The knobs** (`Graphics`): `shadows` 0/1/2 (off / hard / soft) as before,
  now acting on the torches; hard = `SHADOW_DUAL_PARABOLOID` (2 passes), soft =
  `SHADOW_CUBE` (6). New `shadow_distance` (Ultra 14, High 12, Medium 10, Low 8,
  Potato 0; menu "Torch shadow distance"), applied as each torch's
  `distance_fade_shadow` -- past it a torch lights but does not cast. And the
  CAP: the positional atlas's quadrants are its slots, and a light with no slot
  casts nothing, the slots going to the lights covering most of the screen.
  `_apply_viewport` gives soft 2 quadrants of 4 (8 torches), hard 1 (4), the
  rest disabled. Atlas sizes raised: Low and Medium 2048, High 4096. A key
  missing from an older graphics.cfg now takes the saved preset's value
  (`load_settings`), not the script default.
- **The level had been lit THROUGH its walls.** Torches reach 20 m at
  attenuation 0.4 and lit the next corridor through the stone; with shadows on
  everything, mean luminance fell 2-3x in corridors and 30x in the spawn's jail
  cell, which had no torch of its own (it has one now, at 0.6 energy, on its
  left wall). Measured per station (same shots, `--bench --shot`): energy 2.4
  restored rooms but left stretches with no torch in sight black; ambient 0.3
  -> 0.45 changed nothing visible (ACES); density 1.5 lit every stretch but,
  once capped, ran 1.5-3x the old brightness at 59 fps. Kept: density 1.1,
  `module_torch_energy` 1.3 -> 1.4 -- every station back within ~20% of before.
  Torches beyond the cap still light through walls, as before.
- **Cost** (RTX 3060, 3440x1440, Ultra, editor closed): before 83.1 fps / worst
  p99 22.22 ms / 1016 MB. Uncapped, 24 m: 40.9 fps, chest room 18.9 (51M prims:
  six passes over every chunk in 20 m, per torch; render CPU 17 -> 44 ms).
  Flame sway forcing a redraw every frame was NOT it (42.5 with sway 0). 12 m:
  50.8; capped at 8: 59.4; dual paraboloid instead of cube: 61.8 (kept cube on
  soft); the 1.5 density alone without shadows: 65.9. Final (1.1, 8 slots,
  14 m, cube): **73.1 fps, worst p99 25.00 ms, 1060 MB**; chest room (domed
  prison, a torch on every arch) 44.9 vs 53.3. Not benchmarked on the P620.
- Measured in a harness (11/11): Ultra loaded with no shadow_distance in the
  file -> 14 (re-broken without the preset fallback: 8, caught); 502 torches all
  casting, cube, 14 m; atlas 4+4 slots; 940 brick chunks cast, none of floor /
  bed / cap / skirt; jail torch; Potato none cast; High 12 m; Low dual
  paraboloid, 4 slots, 8 m; Ultra -> Potato -> High -> Low -> Ultra: 0 of 661
  lights differ; graphics.cfg untouched.
- `tools/benchmark.gd`'s header now reports "torch shadows N torches to X m".

