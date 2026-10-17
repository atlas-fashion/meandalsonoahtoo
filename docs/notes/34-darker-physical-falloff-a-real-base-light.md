## 34. Darker, physical falloff, a real base light (2026-10-12)

- **There was no base light.** With every torch switched off, the ambient
  (`module_ambient` 0.3 x `AMBIENT_ENERGY` 7) measured 0.0005 mean luminance --
  black -- and 3.0 read 0.045: ACES's toe eats low ambient whole. That is why
  every earlier "raise the ambient" test changed nothing visible. Measured
  sweep, torches off: 0.8 -> 0.004-0.006, 1.2 -> 0.010-0.014, 1.6 -> 0.016-
  0.022. **1.1 is "barely see"**: slabs and brick courses just readable, black
  a few metres off.
- **Ambient colour near-neutral** (0.17, 0.175, 0.19): the old (0.16, 0.175,
  0.225) made the dark read blue, and mixed with the orange fire turned the
  wall beside a torch magenta.
- **Torches darker and physical**: `TORCH_ATTENUATION` 0.4 -> 1.0,
  `TORCH_RANGE` 20 -> 14 m, `module_torch_energy` 1.4 -> 1.3. Beside a torch
  about half the old brightness, between torches down to the base light. At
  1.0 a torch adds little past ~12 m (14 vs 20 m: 10-25% less between
  torches), and it also cuts what an unshadowed torch leaks through a wall.
- Tested live with a harness that applied energy / attenuation / range /
  ambient to every torch and the environment at runtime and shot 3 spots
  beside a torch, 3 between (6-12 m from any light) and the 3 darkest
  straights (the densest map has none past ~12 m) -- no rebuild per config.
  Trap: "nearest light" includes the red skylight spots and cage lights; a
  "near" spot that read 0.025 with every torch off was lit by those.
- Bench (RTX 3060, 3440x1440, Ultra, editor closed): **79.4 fps, worst p99
  22.81 ms, 1060 MB** (73.1 / 25.00 before this; 83.1 / 22.22 before torch
  shadows). The shorter range paid for the shadows' cost.
- The boss hall is as dark as it was (lit mostly by its sky lights); not
  retuned.

