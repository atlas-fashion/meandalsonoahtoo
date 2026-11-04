## 163. The user's sword and spear (2026-11-04)

The user made a sword and a spear in Blender (Tripo pieces kitbashed together,
textures packed) and asked for them in place of the old ones. They are now the
first-person sword, the first-person spear, the thrown spear and what the co-op
body holds. Nothing was generated: these are his files, only fitted.

### Sources and build

- `models/source/weapons/sword.blend`, `spear.blend`, as he sent them (under
  `models/source/`'s `.gdignore`).
- `tools/build_weapons.py` (Blender headless) fits one and exports it:
  `blender -b --factory-startup -P tools/build_weapons.py -- sword models/sword.glb`,
  the same with `spear models/spear.glb`. The outputs are build artifacts.
- Each .blend holds one mesh along +Z. The script turns it over if the wide end
  (the sword's guard, the spear's head) is the wrong way, centres the blade or
  the haft on the axis, applies one uniform scale, and renames the Tripo
  materials to `SwordBlade` / `SwordHilt` and `SpearShaft` / `SpearSocket` /
  `SpearBlade` (it fails if one is missing).
- Measured on his meshes: sword 5,289 triangles (was the Meshy sword's 46,442),
  3.334 long, pommel at 0, guard at 0.92, blade 0.119 wide; 1024 maps (the
  blade's base colour, the hilt a full set). Spear 7,399 triangles, 16.456 long,
  butt at 0, the socket from 13.2, the blade to the end; 4096 base colours,
  13.4 MB as a GLB.

### Fitted to the old conventions

- **Sword**: along +Y, pommel 0, tip 2.65 (scale 0.795): the swings, the hit box
  and the framing stay. Guard at 0.713 (the Meshy one 0.554), so the hilt is
  longer and the fist (0.42 from guard to pommel) sits 0.30 below the guard.
- `player.gd` `_measure_sword` read only surface 0 of the mesh. His sword is two
  surfaces and the guard and pommel are on the second, so it now reads every
  surface. Read back in the game: pommel 0, guard 0.713, tip 2.65; the fist's
  grip point 0.414 up the hilt.
- **Spear**: along -Z, tip forward, the hand at the origin, butt end at +0.67
  and point at -2.07 (`BUTT_REACH`, `TIP_REACH` unchanged; scale 0.1665). His
  socket lands at 1.52-1.73 from the hand, where the old one was (1.49-1.55),
  and the fist (`SPEAR_UP` 0.28) on a plain stretch between two of the bulbs.
  The shaft is 0.13 thick (the old 0.04), about the sword's hilt.
- `spear.gd` `_build_model` instances `models/spear.glb` and gives each surface
  its own material: in hand a copy with `use_z_clip_scale` (as the sword); thrown,
  `SpearSocket` and `SpearBlade` get a lit copy (`_hot_mat`, emission 1.0/0.5/0.16
  x2.2, made once) so it can be followed out and back as before. `set_depth`
  walks the surface override materials. The procedural shaft, bands and leaf
  blade (`_blade_mesh`) and their materials are gone.
- `coop_avatar.gd` `_build_props`: the co-op body holds the same two models,
  the sword a metre long, held at the same grip point (`SWORD_GUARD` 0.713 is the
  build's printed guard), the spear 2.2 m, turned from -Z onto +Y. The box and
  cylinder props and their helpers are gone.
- His materials are kept as he set them: the blade and spear head are
  base-colour only, roughness 0.9, not metal. In first person the spear points
  almost straight ahead, so its bronze head is small and dark on screen -- as
  the old one was small, but it was bright steel.

### Checked (windowed harness, thrown away)

Every surface of both in-hand models has `use_z_clip_scale`; `set_depth(1)`
reached them; the thrown model's socket and blade glow and its shaft does not;
screenshots of the sword and spear in hand and of the co-op body holding each.

### Measured

RTX 3060, 3440x1440, the user's settings, `--bench --size=3440x1440`, the old
(Meshy) and the new sword alternated, four runs back to back (the bench holds
the sword; the spear's model is built at load either way):

```
            old      new      old      new
OVERALL    50.4     51.0     51.2     50.9 fps
worst p99  34.48    33.33    30.56    31.53 ms
video mem  1896.6   1884.3   1896.6   1884.3 MB
```

No cost: the difference is inside the run-to-run spread; 12 MB less video
memory (the Meshy sword's 2K maps out, the spear's 4K ones in). The whole
game read ~51 fps both ways that day, under note 159's 63-65, with the same
busy-background-GPU caveat as note 159 -- not this change.
