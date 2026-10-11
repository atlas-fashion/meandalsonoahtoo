# Performance: how to measure, and what was found

`benchmark.gd` hangs off `scenes/main.tscn` and does nothing unless the game is
launched with `--bench`, so it costs one string check in normal play. It parks
the player at four representative spots, spins a full circle at each, and
reports frame-time percentiles with renderer counters.

```
godot --path . --windowed -- --bench                      # current settings
godot --path . --windowed -- --bench --preset=potato      # one preset
godot --path . --windowed -- --bench --size=3440x1440     # at a given resolution
godot --path . --windowed -- --bench --ablate             # cost of each switch
godot --path . --windowed -- --bench --shot               # capture the pause menu
```

**Never run it with `--headless`** -- the dummy renderer reports zero draw calls
and the numbers are meaningless. It forces a windowed, fixed-size window and
disables vsync itself, because the first attempt at this read back a flat
20.00 ms everywhere and the whole measurement was just the refresh rate.

## What the measurements said

The scene is **not geometry bound**. At the worst spot in the level it draws
125-190 calls and under 100k triangles, and still costs 11-25 ms. The cost is
per-pixel. Ablation against an 11.42 ms baseline at that spot:

| change | saving |
| --- | --- |
| render scale 0.50 | **-6.87 ms** |
| render scale 0.70 | **-4.79 ms** |
| bloom off | -1.37 ms |
| SSAO off | -1.19 ms |
| torch shadows off | -0.80 ms |
| textures off | -0.81 ms |
| MSAA off | -0.43 ms |
| triplanar off | -0.18 ms |
| view distance 0.70 | +0.11 ms (nothing) |
| aggressive animation LOD | +0.08 ms (but -0.67 ms of physics) |

Resolution scale is worth more than everything else combined. Cutting the draw
distance or the mesh detail buys **nothing** and costs the look, which is why
the low presets keep both and take the frame out of resolution instead.

At 3440x1440, worst-case frame time by preset: Ultra 89.6 ms, High 74.7,
Medium 34.7, Low 19.2, Potato 9.3. VRAM 816 MB down to 205 MB, which matters on
a 2 GB card.

## Adding a quality setting

One property on `scripts/graphics_settings.gd`, one entry in each of the five
rows of `PRESETS`, and one line in `SPEC` in `scripts/pause_menu.gd`. The menu
builds its own widgets from `SPEC`, so there is no scene to edit.

Authored values are stashed per node with `set_meta` the first time a setting
touches them, so scaling is always applied to the original rather than
compounding on the last pass -- and a node that gets freed takes its own
originals with it.

---

# Generating models with Tripo

`tripo.ps1` calls the Tripo REST API directly. No MCP server, no `uv`, no
third-party package holding the API key.

```
./tools/tripo.ps1 -Mode text  -Prompt "a rusted iron portcullis" -Out models/portcullis.glb
./tools/tripo.ps1 -Mode image -Image ref.jpg -Out models/shield.glb -FaceLimit 4000
```

The key comes from the `TRIPO_API_KEY` environment variable
(`setx TRIPO_API_KEY "..."`, then restart the terminal). It is never printed,
logged or written to disk, and the multipart upload is built in-process rather
than shelled out to `curl.exe`, because a bearer token passed as a command-line
argument is readable by any other process on the machine.

A dropped connection costs nothing: the job keeps running server-side, and
`-TaskId <id>` resumes it without spending credits again. The poll loop retries
transient 5xx rather than aborting, which it used to do.

**Cost: 20 credits per text-to-3D generation**, measured (600 -> 580).

## What Tripo actually returns

Measured on a `-FaceLimit 6000` text-to-3D run:

| | |
| --- | --- |
| triangles | **5,315** -- `face_limit` is honoured, so no decimation needed |
| objects / materials | 1 / 1 |
| textures | **three 2048x2048 maps** (Color, NormalGL, ORM) |
| bounds | roughly unit cube, **origin at the centre, not the base** |

**The triangles are fine; the textures are the problem.** Three 2K maps is about
12 MB of VRAM per asset uncompressed, on a card with 2 GB. Set `-FaceLimit` at
generation and the geometry needs nothing further -- but the maps should be
dropped to 512 or 1024 and left to Godot's VRAM compression before anything
ships. A handful of 2K assets will cost more than the whole rest of the level.

## Still needed before it goes in the game

- **Downscale the textures.** See above. This is the one that matters.
- **Re-origin.** Tripo centres the mesh; most placement wants the origin on the
  floor of the object.
- **Check the facing.** Build/rotate so the exporter lands it on Godot -Z
  forward.
- **Kill shadow casting** if it is a first-person viewmodel -- an omni light
  rasterises it into all six faces of its shadow cube.
- **Check it against the settings contract** in `CLAUDE.md` section 3 if it
  costs frame time.

---

# Player sword

**In use: `models/player_sword_meshy.glb`** (2026-09-30), the Meshy model the
user supplied, fitted to the pivot by `build_meshy_sword.py`:

```
blender -b --factory-startup -P tools/build_meshy_sword.py -- models/player_sword_meshy.glb
godot --headless --import --path .
```

The sources -- the FBX and its four 2K maps, as delivered -- are kept in
`models/source/meshy_sword/`, under a `.gdignore` so Godot never imports the
raw FBX. The script measures the mesh rather than trusting it: the hilt must be
the end with the widest slice (the crossguard) or it turns the sword over; it
centres on the BLADE's cross-section, not the bounding box (guard and pommel
are not symmetric); and one uniform scale puts the pommel at 0.0 and the tip at
2.65 on the same axes as below, so the strokes, the hit box and the framing are
unchanged. Full resolution, 46,442 triangles: decimating generated meshes is
what broke normal-mapped shading in this project before. A fresh material is
built from the four maps (Blender packs metallic + roughness for glTF).
Measured: 59.9 fps / worst p99 25.79 ms (no cost), video memory +65 MB.

The old procedural sword below still builds and is kept as a fallback; to go
back, point `3_sword` in `scenes/player.tscn` at `player_sword.glb`.

`models/player_sword.glb` is generated by `build_sword.py` from the reference
photo -- a straight double-edged blade with a central fuller, a brass crossguard
whose quillons droop and flare, a corded leather grip and a flat fan pommel.
1,264 triangles, three surfaces (steel / leather / brass).

```
blender --background --factory-startup --python tools/build_sword.py -- out.glb
```

It is built along Blender **+Z**, because the exporter maps that to glTF and
Godot **+Y**, which is the axis `Head/SwordPivot` points the sword down. Its
footprint deliberately matches the box meshes it replaced -- butt at 0.0, tip at
2.65, blade 0.26 wide, guard 0.62 across -- so the first-person framing does not
move. Measured after the swap, the tip sits 41.7% from the top of the screen
against 43.0% before.

## Sword strokes and the sweep trail

`slash` and `chop` are both horizontal sweeps now -- `slash` right to left,
`chop` left to right, alternating. Both are 0.5 s authored and play at
`attack_speed` (1.7x), so a stroke takes about 0.30 s. Verified by sampling the
blade tip in head space: slash runs +2.59 to -2.42 on X, chop -2.01 to +2.74.

The slam has its own `dive` clip. It used to borrow `chop` as an overhead pose,
which stopped making sense once `chop` became horizontal. `dive` deliberately
carries **no method tracks**, so it cannot open the sword's hit window.

**The sweep trail draws the hit query, not the blade.** `_resolve_hits` does not
test the blade volume -- it sweeps a sphere of `attack_reach` from the player's
chest and keeps whatever lies within `_sweep_half_angle()` of the camera's
facing. A blade-shaped ribbon would therefore advertise a thin line while a wide
wedge is what actually cuts. `_build_sweep_mesh` draws that wedge, from the same
origin, at the same radius, with the same half-angle, re-aimed every frame
because the query reads the current facing too. Verified: outer edge at exactly
3.400 m against `attack_reach` 3.40, arc half-width 0.654 rad against the
query's 0.654.

Cost at 1280x720 with continuous swinging: **none measurable** -- p99 identical
with it on and off (3.33 / 4.17 ms), 378.1 vs 377.3 avg fps, i.e. inside noise.
It is gated on `Graphics.effects` regardless, since it is additive transparency.

> The ultrawide A/B could not be completed: the Quadro P620 lost the Vulkan
> device (TDR) twice at 3440x1440, including on the *cheaper* trail-off run.
> That is a driver/hardware limit under sustained load, not an effect cost.

**Viewmodel meshes must not cast shadows.** `player.gd` switches this off for
everything under `Head` at startup. The torch beside them is a shadow-casting
omni, so anything held there is rasterised into all six faces of its shadow
cube: leaving the sword casting measured **+1.4 to +1.9 ms** at 3440x1440 and
added ~8,600 primitives for a 1,264 triangle mesh. With it off, the scene draws
*fewer* calls than it did with the old box sword.

---

# Skeleton animation pipeline

`models/ossuary_skeleton_rigged.glb` is generated, not hand-edited. It is built
from the original `Ossuary_Skeleton.blend` (which ships a full 80-bone FK rig)
by `build_skeleton.py`, which:

1. drops the `03 | Studio` collection,
2. folds the 58 finger and toe bone weights into the parent hand/foot and
   deletes those bones, leaving 22,
3. joins the 79 skinned pieces and decimates 110,320 -> ~3,500 triangles,
4. applies one `Bone` material, and
5. authors nine clips: `idle`, `walk`, `run`, `windup`, `attack_1`, `attack_2`,
   `attack_3`, `lunge`, `recover`.

Rebuild it with (adjust the source path if the .blend moved):

```
blender --background "Ossuary_Skeleton.blend" --python tools/build_skeleton.py -- out.glb
```

Then copy `out.glb` over `models/ossuary_skeleton_rigged.glb` and let Godot
reimport.

## Before trusting a change

`verify_skeleton_clips.py` measures the exported file rather than the authoring
intent, which matters because the pose specs are written as armature-space
rotations and the signs are easy to get backwards:

```
blender --background --factory-startup --python tools/verify_skeleton_clips.py -- out.glb
```

`render_skeleton_poses.py` renders key frames to PNGs for a visual check.

## Things that bite

- **Bone-local axes.** A pose rotation of `+X` tips the body "top forwards", so
  it leans the spine forward but swings arms and legs *backwards*. The `root`
  bone's hop goes in local **Y** (bones point head-to-tail along local Y), not Z.
- **An arm's rest direction is 35 degrees out to the side**, and no amount of X
  rotation removes that. Raising an arm overhead needs roll (the Y term) or the
  fists end up 1.3 m apart.
- **Spine bend is cumulative** down `spine.01 -> spine.02 -> chest -> neck`.
  Around 40 degrees total is a hunch; 68 folds the skeleton in half.
- **glTF base colour is linear, Godot's `albedo_color` is sRGB.** The material
  uses the linear values that land on the intended `(0.604, 0.561, 0.471)`.
- **Every clip must drive the same track set** or a bone gets stranded partway
  through a cross-fade. The verifier asserts this.
- Emission is deliberately non-zero so Godot imports the material with
  `emission_enabled`; `enemy.gd` drives the energy per state from there.

# Held health potion

`models/potion_held.glb` is generated by `build_potion.py`: a lathed
round-bottomed flask with a lip, the liquid as its own inner volume filled to
two thirds, a cork and a three-turn twine wrap. 3,960 triangles, base at the
origin, standing on +Y.

```
blender -b --factory-startup -P tools/build_potion.py -- models/potion_held.glb
```

Its materials are placeholders with the right names; `scripts/held_potion.gd`
replaces them (alpha glass, glowing liquid) because the glTF round trip does
not carry alpha blending and emission reliably.
# Corridor doors (the gate)

`models/kit/gate_door.glb` is cut out of `module_gate.glb` by
`build_gate_door.py`: the gate's two leaves (each with its origin on its hinge,
cut cleanly at the seam and both hinge lines) and its moulded stone arch. The
cut follows measured curves, not the mesh's own grouping -- see the docstring.

```
blender -b --factory-startup -P tools/build_gate_door.py -- models/kit/gate_door.glb
godot --headless --import --path .
```

`SCALE` and the arch figures are duplicated as `GATE_*` constants in
`scripts/module_level.gd`; change both together.
# Brick kit (the corridors since 2026-10-10)

```
blender -b --factory-startup -P tools/build_brick_kit.py
godot --headless --import --path .
```

Builds `models/brick/brick_kit.glb` (one file, one object per piece, so the
variants share their source's textures) from the eight raw Tripo pieces in
`models/source/brick_kit_raw/`, which were generated from the user's photos in
`models/source/brick_kit_refs/` (image to model, `-TextureQuality detailed`,
40 credits each). Placed by `scripts/brick_level.gd`. Rebuild, never hand-edit.

- **After a first import, set the textures to VRAM compressed.** A headless
  `--import` never runs Godot's "used in 3D" detection, so every extracted map
  came in as `compress/mode=0` (lossless, uncompressed): 300 MB more video
  memory. The `.jpg.import` files under `models/brick/` now carry
  `compress/mode=2`; Blender rewrites the images on every build, but the
  `.import` settings survive.
- The vault variants are cut from ONE barrel that is decimated first. Thinned
  after cutting, the cut edges moved and the groin lines opened into cracks.
- Pieces are scaled to the cell in the script (WALL_FACE 1.9, SPRING 3.0,
  CROWN 5.1, VAULT_HALF 3.03 ...); the matching constants in
  `scripts/brick_level.gd` must follow them.
- Since 2026-10-10 the kit also carries the cart (`cart_body`, `cart_wheels`,
  `cart_lid`), the broken wood (`wood_support`, `wood_planks`, `wood_crate`),
  the door split into `door_frame` / `door_leaf`, and the cage wall's gate
  `cage_door`. The splits are cut AFTER the source piece is decimated, so the
  parts still meet.
