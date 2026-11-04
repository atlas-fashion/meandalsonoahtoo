## 159. The fantasy armor; shadows in small blocks at low LOD; hold 60 (2026-11-03)

The user: the attached "fantasy armor 3d model.glb" replaces the molten rust
knight as the player, first-person arms included; then rerun the optimisation
tests on the RTX 3060 at 3440x1440 and make the whole game hold 60 fps or
higher without visibly lowering quality.

### The armor (`tools/build_player_knight.py` -> `models/player_knight.glb`)

Source `models/source/armor/fantasy_armor.glb` (Tripo): a knight in dark plate
with gold glowing cracks, T-pose facing glTF +Z, 10.5k triangles, one 4096
albedo, **no skeleton**, 0.845 high. Its span / height is 1.18 -- the same as
the Meshy knight's (2.00 / 1.70) -- and slices through both at the same heights
line up to 1-4 cm, so it is skinned onto the **Meshy knight's skeleton
unchanged** (`models/source/knight/knight_meshy.glb`, now only the rig donor):

- scaled x2.0113 to 1.70 m, `NUDGE` 2.5 cm back (Blender +Y; its torso and legs
  sat 2-4 cm ahead of the knight's);
- each vertex takes the knight's skin weights at the nearest point of the
  knight's surface (BVH, barycentric), smoothed 3 passes along the armor's
  edges, 4 influences, normalised; 45 of 13,657 vertices were over 6 cm from
  the knight's surface;
- the knight's mesh dropped. Same bones, same rest: `coop_avatar.gd` posing,
  `first_person_arms.gd` IK and note 158's measured bone lengths all hold.
- Emission cut from the albedo as before (4.29% of texels: the gold cracks),
  now in the cracks' own colour (k * rgb, not a fixed orange); metallic 0.55,
  roughness 0.62; albedo 2048 JPEG, named `Image_0` so the old .import (VRAM
  compressed) carries over. 7.4 MB -> 1.7 MB.
- Checked posed in Blender (stride, arms down, elbow bent, head and spine
  turned): plates follow their bones, no tearing at hips, knees or shoulders.

The arms (`tools/build_player_knight_arms.py`): the knuckle line re-measured off
the armor's gauntlet -- thumb at |x| 0.87-0.93 hanging forward, fingers from
0.94 -- `KNUCKLE` 0.918 -> 0.935, `FINGER_Z` 1.355 -> 1.333. 3.4k faces (was
8.3k). `first_person_arms.gd` `GRIP` (0.918, 1.329, -0.0544) -> (0.935, 1.307,
-0.0554), as printed. Pictured in game: the gauntlet closed on the sword's hilt
at rest, and the guard -- the forearm flat across the view with its gold cracks.

Frame cost of the swap: none (A/B old knight vs armor, same session: 44.4 /
44.2 fps); 0.15-0.2M fewer primitives a station (10.5k triangles in each shadow
pass instead of 31k); video memory 1061.8 -> 1005.2 MB.

### The PC is not the PC of note 158

The same High settings that read 69-71 fps at notes 155-158 read **44 fps** at
the start of this session. Nothing in the game changed: the GPU was 10-30% busy
at idle (`nvidia-smi`; Wallpaper Engine the busiest process, Chrome, Epic,
others). Fullscreen did not help. And it moved through a run: `--ablate`'s
"baseline" and "baseline again" differed by 3.4 ms. So every claim below is an
**interleaved** measurement:

- **`tools/benchmark.gd --ab=key=value,...`**: at each station (or `--at=` a
  prefix), the settings in effect and the change are switched back and forth
  every 1.5 s for 6 rounds (order swapped on odd rounds, 0.35 s after each
  switch thrown away), the player spinning throughout. `--ab=code` flips
  `Benchmark.ab_on` for code to read.
- **`--fullscreen`**: as the game is played (window mode 3).
- Whole-build before/after: old scripts and new scripts alternated, two full
  `--bench` runs each, back to back.

Measured with `--ab` at the chest room (gpu ms, A -> B): torch shadows off
22.8 -> 14.3 (10.8M primitives -> 2.2M); SSAO off -1.5; bloom off -1.2;
render scale 0.77 -3.4; triplanar off and mist off within noise. Body shadow
off, or the torch light's sway off: 0.2-0.9 ms each. **Shadows are the frame.**

What does NOT help: caching. A static omni shadow is cached by Godot (harness:
light energy and colour changes keep it cached, a moving light redraws it), but
in play every lit torch has something moving in its reach -- the player's body,
enemies, rats, its own sway -- so they redraw every frame anyway.

Also measured: the frame runs 3-4 ms over `viewport_get_measured_render_time_gpu`
in every case, a bare test scene included (frame queue size 2 or 3, the same).
Budget against that, not against 16.7.

### Shadows in small blocks (`brick_level.gd` `_emit_shadows`, `SHADOW_BLOCK`)

A shadow pass draws every caster whose box reaches the light, and a MultiMesh
is one box: a torch touching the corner of a 4 x 4 cell chunk (24 m) drew all of
it, both hemispheres. Now each shadow-casting piece's chunk stays as it was for
the camera but casts nothing, and a shadows-only copy cut into 2 x 2 cell
blocks (12 m) casts instead -- same meshes, same transforms. 2,966 blocks.
`[brick] ... shadow blocks N` at build. `cap` and `skirt` (moon only) and the
floor pieces are untouched.

### At the lowest LOD (`SHADOW_LOD_BIAS` 0.001)

The blocks draw each piece's lowest imported LOD (wall 7,000 -> 4,655
triangles, vault 7,000 -> 3,500, arch 6,000 -> 3,000). And
`brick_level.shadow_lods` (called by maze.gd just before `_populate`) does the
same for every other static mesh the level built of 2,000+ triangles that has
LODs and casts -- the surgery's raised brick and beams, the chest rooms, the
boss hall, the morgue: a shadows-only copy as a CHILD (so it moves, hides and
frees with it), same material overrides, the original's cast switched off.
Skinned meshes skipped. 667 copies.

**Pictured A/B** (old whole chunks / blocks / blocks at low LOD, three times
each, 3440x1440, corridors by torches): the differences between the variants
were the same size as between two pictures of one variant 0.4 s apart -- the
torches' own flicker (e.g. 9.8% of pixels off by >4% old vs old, 11.7% old vs
new). One early "darker ceiling" in the old picture did not repeat.

### Hold 60 (`Graphics.hold_60`, "Hold 60 fps" in the settings)

A new knob (section 3: High and Medium on, Ultra / Low / Potato off; a saved
profile without the key takes its preset's value). `graphics_settings.gd`
`_process`: the GPU's own frame time, smoothed over 0.35 s; over `DYN_OVER`
12.8 ms the 3D scale steps down `DYN_STEPS` (1.0, 0.92, 0.85, 0.78, 0.72 of
`render_scale`, at most one step per 0.6 s); it steps back up when the step
above is predicted (time goes with the pixels) under `DYN_UNDER` 11.6, no
sooner than 2.5 s after a change (each change re-makes the render buffers: a
hitch). Under the player's own scale it upscales with **FSR** (sharpened), at
their own scale bilinear as before. Held while paused; off in co-op (the halves
are sub-viewports). `Graphics.current_scale()`.

### Measured (RTX 3060, 3440x1440, the user's High, `--bench --size=3440x1440`,
old and new scripts alternated)

```
                     before 1   after 1    before 2   after 2      (avg fps)
spawn corridor         42.7      61.9        50.2      66.2
boss room centre       49.9      69.4        59.5      70.9
boss room edge         54.8      72.9        62.2      73.9
outer maze             56.6      66.3        64.6      69.8
chest room             41.8      52.8        42.9      54.1
surgery                42.5      52.5        42.9      57.6
OVERALL fps            48.1      62.7        53.7      65.4
worst p99 ms          29.11     24.02       29.45     25.00
primitives, chest      13.2M     9.2M        13.3M     9.2M
video memory          1061.8    1005.2 MB
```

Corridors, the boss hall and the outer maze now average over 60 (p95 15-18 ms).
**The chest rooms and the surgery do not yet**: 52-58 fps, gpu 14.5-15.8 ms
already at the 0.72 floor -- what is left there is shadows of skinned enemies
(the caged proel builders, 42k triangles each, enforcers) and the rooms' own
geometry, which resolution does not touch. Next lever there: a cheaper shadow
for skinned enemies, or proper decimated shadow proxies (Blender) for the kit
and the rooms instead of the import's 50% LODs.

Clean `--quit-after 2400 -- --skip-title` run: stderr empty.

### Traps

- **A benchmark on this PC is only good against a run interleaved with it.**
  Two identical `--bench` runs 3 minutes apart: 48.1 and 53.7 fps.
- `--at=chest room` passed through PowerShell's `Start-Process -ArgumentList`
  splits on the space: `--ab`'s `--at=` matches a prefix (`--at=chest`).
- A shadows-only copy must keep the original's material overrides, or an
  alpha-cut surface casts a solid shadow.
- The Tripo armor has no rig; Meshy's knight did. A rig moved between two
  bodies of the same proportions keeps every pose; check proportions by slices
  before reaching for a new rig.
- `var split := not (piece in A or piece in B)` will not infer: give it `bool`.
