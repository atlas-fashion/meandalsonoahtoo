## 112. Realistic fog that limits the view; the presets retuned for the RTX 3060 (2026-10-26)

The user asked for realistic fog that limits view distance, and for the game to
be re-optimised for the GPU it actually runs on now: an **RTX 3060 driving
3440x1440 at 59 Hz** (DESKTOP-ARKHI90), not the Quadro P620 that sections 1-5
of CLAUDE.md were written for.

### The 3060 is not the P620: what the frame costs now

Measured at 3440x1440 with the user's own saved profile (Custom: render 1.0,
4x MSAA, hard shadows, 16 lit torches, SSAO, bloom, view 1.25, anim Full, sim
range 1.25), before any change:

```
station            avg fps  1% low  avg ms  p99 ms     draws      prims
spawn corridor        70.5    49.2   14.19   20.31      1435    6503320
boss room centre      47.7    31.1   20.96   32.16      2122   10989377
boss room edge        48.3    32.6   20.70   30.65      1935    8625936
outer maze            82.1    52.3   12.18   19.12      1221    5076850
chest room            43.9    35.1   22.78   28.51      2296   13694437
surgery               37.9    30.0   26.40   33.33      2362   14054639
OVERALL 55.1 fps   worst p99 33.33 ms   video mem 1307 MB
```

`--ablate` (now from the settings in effect, see below) at the chest room,
where the 3060 is GPU-bound (gpu ms ~ frame ms):

- **Torch shadows are the frame.** Off: -6.6 ms, and 13.2M primitives drop to
  2.9M -- 10M triangles a frame are torch shadow passes over the brick kit
  (wall 7,000 tris, vault 8,000; each shadow pass draws whole 4x4-cell chunk
  MultiMeshes). 8 lit torches instead of 16: -3.2 ms; 12: -0.7.
- **Soft shadows are six-sided cubes** (`shadows` 2 -> `SHADOW_CUBE`): the old
  High preset (soft, 12 torches) drew 19M primitives at the chest room against
  12M for hard (dual paraboloid) with 16 torches. Hard instead of soft, all else
  equal: chest room 22.76 -> 17.48 ms.
- MSAA 4x off: -2.6 to -3 ms. Render scale 0.7: -4.8 ms. SSAO: -1.2. Bloom
  -0.6. **Mesh LOD, triplanar, shadow atlas size, the old exponential fog:
  nothing** (within noise). LOD cannot help shadows here: a chunk's LOD is
  chosen from its AABB, and the camera is inside the chunks round it.
- **The boss hall and the surgery are CPU-bound** (gpu ms 10-12 of an 18-26 ms
  frame), physics 7-12 ms a step: the enemies awake round the player. Sim
  range 0.75 took the boss room edge from 18.7 to 12.1 ms; anim LOD did little.
- The `cpu ms` column is `Performance.TIME_PROCESS`, which in Godot 4 is the
  whole frame's main-loop time, not script time. Judge CPU vs GPU from the new
  `gpu ms` column instead.

### The fog (`module_level.gd` `configure_environment`, constants `FOG_*`, `MIST_*`)

Two layers:

- **Depth fog** (`fog_mode = FOG_MODE_DEPTH`): density 1.0 = total at
  `FOG_SIGHT` 60 m, from `FOG_BEGIN` 3 m along `FOG_CURVE` 0.8 (thickens fast
  near, slowly far, like real air). Same dark `FOG_COLOUR`. `FOG_SKY` 0.35:
  the sky is veiled a little, never hidden. This is `Graphics.fog` as before.
- **Volumetric mist**: density 0.022, albedo (0.78, 0.8, 0.86), anisotropy 0.55
  (forward scatter: the halo round a torch you face), length = FOG_SIGHT,
  ambient inject **0**, temporal reprojection 0.85. A new knob,
  `Graphics.volumetric_fog`: 0 off, 1 on (froxels 64 x 48 deep), 2 fine
  (128 x 96), via `RenderingServer.environment_set_volumetric_fog_volume_size`.
  Settings menu "Volumetric mist". Presets: Ultra 2, High 1, Medium 1, Low 0,
  Potato 0. Script default 1, so a saved Custom profile without the key gets it.

Rules that came out of it:

- **Only shadow-casting lights light the mist** (`Graphics._apply_light`
  sets `light_volumetric_fog_energy` to 0 for any light whose shadow is off;
  authored value kept in the `gfx_light` meta). An unshadowed light would glow
  in the air through the stone. Harness-checked: 0 unshadowed lights in the mist.
- **The moon's mist share is `maze.gd` `MOON_MIST` 0.3.** At 1.0, with ambient
  inject 0.04, the first pass washed the boss hall and the domed prison
  lavender-grey and the dark was gone. Ambient inject went to 0: the mist shows
  only where a light is, which is what fog in a dark dungeon looks like.
- **Past the fog nothing is drawn.** `Graphics._apply_visibility` clamps every
  authored `visibility_range_end` to `FOG_SIGHT` + the node's own reach (max
  corner distance of its AABB from its origin, `gfx_reach` meta), because a
  range is measured from the ORIGIN (note 6.09) and a 24 m chunk can have a wall
  in front of a far-away origin. Only nodes that already had a range are
  touched. `_fog_sight` is read from the environment in `_apply_environment`
  (depth mode at density 1 only), 0 = no clamp. In the boss hall this saved
  ~2.5 ms GPU and 2.2M primitives ("fog off" in the ablation is now SLOWER).
- **The sewer's haze is exponential.** `sewer.gd` `_haze_env` now saves and
  switches `fog_mode` too: in depth mode its density 0.06 would be a 6% veil.
- The mist's own cost at the chest room, in a run nothing else shared the GPU
  with: on 21.76 ms / off 21.84 (noise); fine +1.2 ms.
- `tools/preview_sky.gd` still forces `fog_sky_affect = 0` to judge the sky
  alone; `configure_environment` now sets it.

### Presets retuned (`graphics_settings.gd` PRESETS)

- **High**: render 1.0, MSAA off (FXAA), **hard** shadows, atlas 4096, 12 lit
  torches, SSAO, bloom, fog, mist 1, view 1.0, anim 1 (banded), sim range 0.9.
- **Medium**: as High at render scale 0.85, atlas 2048, LOD 2 px.
- Ultra gets mist 2; Low and Potato mist 0; otherwise unchanged.

At 3440x1440 on the 3060, all with the new fog (`--preset=high` plus `--set=`; the
Medium column was measured at LOD 1 px, which the ablation found makes no
difference):

```
                   old High values         new High              new Medium
station            avg ms   p99 ms      avg ms   p99 ms      avg ms   p99 ms
spawn corridor      15.33    22.71       11.89    16.67       11.72    16.67
boss room centre    20.39    29.17       15.51    17.37       15.29    16.67
boss room edge      21.69    51.72       11.77    14.58       11.57    14.11
outer maze          11.74    16.67       10.81    16.67       10.65    16.67
chest room          24.25    28.22       17.48    23.10       15.73    19.33
surgery             25.90    35.16       17.05    21.70       16.19    21.18
OVERALL fps          54.2                 73.6                  76.1
worst p99           51.72 ms              23.10 ms              21.18 ms
```

The user's own profile was switched to the new High (vsync and the 60 fps cap
kept): 55.1 fps / worst p99 33.33 ms before, 73.6 / 23.1 after.

### `tools/benchmark.gd` additions

- `gpu ms` column (`viewport_get_measured_render_time_gpu`).
- `--ablate` measures from the **settings in effect** (saved profile, or
  `--preset=`, plus `--set=`), not always High -- this supersedes CLAUDE.md
  section 2's "`--bench --ablate` is not usable on this level". It skips rows
  the baseline already has, and ends with "baseline again": if that disagrees
  with the first row, the spot changed during the run (the surgery station did:
  draw calls fell 2271 -> 771 after the first row) and the rows are not
  comparable. The chest room is the stable GPU-bound station.
- `--at=<station>` (where `--ablate` measures), `--only=word,word` (just those
  rows), `--set=key=value,...` (Graphics overrides, never saved).

### Traps

- **Another session's windowed harness on the same machine ruins timings.**
  Two ablations here showed 30-80 ms spikes and gpu ms of 37 because the
  surgery thread was running `_claw_harness.gd` at the same time. Benchmarks
  were rerun from a wrapper that waits until no other Godot process (except the
  editor) is running and flags any overlap; only clean runs are quoted above.
- A `--script` harness must `await process_frame` before loading main.tscn, or
  every script naming an autoload fails to compile ("Identifier not found:
  Coop").
- `env.fog_density` is stored as float32: compare 0.06 with `is_equal_approx`.
