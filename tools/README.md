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
`-NoTexture` asks for geometry only (no texture, no PBR): 10 credits.

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
- **The door's stone is its own Tripo piece** (2026-10-14):
  `brick_kit_raw/door_arch.glb`, the user's door photo edited to an empty arch
  (`tools/tripo_image.ps1`, 5 credits) then image to model (40 credits).
  `build_door_arch` fits it to the old frame's outside (legs to +-1.8 m, 5.0 m
  tall, 1.12 m deep about the leaf's middle); its opening came out +-0.93 m,
  0.84 at 3.25 m, 0.64 at 3.6 m. `door_frame` is still exported as a fallback.
- **The floor is Tripo's wet retexture** (2026-10-14):
  `models/source/brick_kit_raw/floor_wet.glb`. First `tools/tripo_image.ps1`
  (seedream, 5 credits, task 293e33be-...) edited the user's floor photo
  (`brick_kit_refs/floor.webp`, as PNG) into the same tile wet, with puddles;
  then `tools/tripo_texture.ps1 -Source 7b41eb15-e4ce-4f27-8bf5-28915ac730f6
  -Model v3.5-20260815 -Image <that picture>` (task 44cc5755-..., 20 credits)
  retextured the floor's original generation from it. Same mesh and UVs as
  `floor.glb`. Tripo paints the water into the COLOUR only -- its roughness
  map is matte (0.90-1.0) -- so `build_floor` derives the gloss (`wet_gloss`):
  where the wet colour is darker than the dry `floor.glb` colour, blurred ->
  roughness 0.1, elsewhere `WET_BASE_ROUGH` 0.62. Delete `floor_wet.glb` to
  build the original dry floor again.
- **The prison hall's frieze and generator** (2026-10-14): text prompts,
  `brick_kit_raw/prison_frieze.glb` (task 1f3f6ee0-...) and
  `prison_generator.glb` (task 0eab5b58-...). The frieze in use is
  `prison_frieze_brick.glb`, remade from the edited wall photo (CLAUDE.md 45).
  `build_frieze` takes a 6.7 m slice
  of the frieze at a uniform scale; `build_generator` fits the machine to 2 m
  across. See CLAUDE.md section 45.
- **The morgue's pieces** (2026-10-15): `brick_kit_raw/wall_loculi.glb` (the
  wall photo edited into a catacomb burial wall, task 8fe2a084-..., then image
  to model) and `morgue_slab.glb` (text). `pier_face` is cut from the wall piece.
  See CLAUDE.md section 47.
- **The manhole cover** (2026-10-15): `brick_kit_raw/manhole_cover.glb`, text
  prompt, `tripo.ps1 -NoTexture` (geometry only: 10 credits, task 990ec001-...).
  `build_manhole_cover` stands it flat, pattern up, 1.08 m across and
  `COVER_T` 0.1 thick; the game paints it dark rusted iron (manhole.gd).
  `floor_notch` is the floor tile with a half circle (`MANHOLE_R` 0.5) cut
  from the middle of its +X edge -- two of them round a hole. CLAUDE.md 50.

# The sewer's textures and props (2026-10-15, Higgsfield)

```
blender -b --factory-startup -P tools/build_sewer_texture.py
blender -b --factory-startup -P tools/build_sewer_kit.py
godot --headless --import --path .
```

Sources are in `models/source/sewer_hf/` (a `.gdignore` folder), all made with
Higgsfield's `gpt_image_2_5` (high): `tex_brick.png` (from the user's wall
photo), `tex_mold.png`, `tex_sludge.png`, `tex_moss.png`, the concept images,
and `raw_bones.glb` (Tripo H3.1 through Higgsfield). The sewer's geometry is not
generated: it is one CSG in `scripts/sewer.gd` (CLAUDE.md section 55).

`build_sewer_texture.py` writes `textures/sewer_hf_albedo/_normal` (the brick,
cropped between two matching rows), `sewer_mold` (colour + a mask in alpha),
`sewer_sludge` + `_normal`, and `sewer_moss` (glow + alpha, faded round its
edge: every moss decal is the whole image). Generated "tileable" images do not
quite wrap (edge steps 1.3-1.5x a neighbouring column); `heal` takes the step
out -- the mismatch across each wrap, low-passed along the edge, spread over a
band either side -- and the build prints the ratio before and after (all now
0.95-1.07). Normal maps are green-up (OpenGL); the brick's was inverted before.

`build_sewer_kit.py` writes `models/sewer/sewer_kit.glb` with "bones" only.

- After an export, the extracted `sewer_kit_*.jpg` imports, and new texture
  PNGs, come in at `compress/mode=0`: set them to 2 with mipmaps and re-import.
- **Never `normals_make_consistent` a shell you stand inside** (learnt on the
  first pass's generated tunnel): it points the normals away from the shell's
  middle, so from inside every face was a back face and rendered black.

# The enforcer (2026-10-15)

```
blender -b models/source/enforcer/ENFORCER_BAKED.blend -P tools/build_enforcer.py
godot --headless --import --path .
```

Builds `models/enforcer.glb` from the user's rigged mech: only the BAKED clips
(second delivery: WALK_BAKED, BEAM_BAKED, BEAM_RECOIL_BAKED, SWIPE_1_BAKED; every
unbaked track and action is removed, one of them was an UNMUTED NLA track;
SWIPE_1_BAKED was replaced by the user's re-bake, CLAUDE.md 73),
bone markers (EyeL/EyeR, Muzzle, Shield), the parts joined into one mesh with a
2K baked atlas (`models/source/enforcer/enforcer_atlas.png`). Set the extracted
atlas texture to `compress/mode=2` after the first import. See CLAUDE.md 48.
The eye glow rings ("EyeGlowL" / "EyeGlowR", bone-parented to HEAD) are traced
from the lenses by the build: a flat-lit ortho render of the head, the grey
lens discs found and their outlines kept to LENS_HARMONICS harmonics, rays
back onto the mesh, a band over 0.70-0.95 of each lens lifted GLOW_LIFT off it.
Traps: the .blend may be saved in pose/edit mode (the script forces object
mode first); and Godot will NOT re-extract `models/enforcer_enforcer_atlas.jpg`
over an existing file -- if the mesh changes, delete it and
`.godot/imported/enforcer.glb-*` and re-import (CLAUDE.md 51).

# Retexturing with Tripo

```
./tools/tripo_texture.ps1 -Source <task id | model.glb> -Prompt "..." -Out models/x.glb
./tools/tripo_texture.ps1 -Source <task id> -Image picture.png -Out models/x.glb
./tools/tripo_image.ps1 -Image ref.png -Prompt "the same, but wet" -Out edited.png
```

A text prompt alongside the generation's own reference (`-StyleImage`) came
back looking exactly like the reference and ignored "wet" altogether; editing
the reference picture first and texturing from it (`-Image`) is what carried
the change.

The v3 `/models/texture` endpoint. Pass the task id of the Tripo generation
when there is one: Tripo keeps its UVs. The id of an old generation is in the
usage log (`GET /v3/account/usage`), and a kit texture's file name ends in it
(`brick_kit_Color_<task id>.jpg`). Traps: the v3 API is on
`openapi.tripo3d.ai` -- the `.com` host in Tripo's docs answers our key with
401; `-Model` must be one of v2.5-20250123 / v3.0-20250812 / v3.5-20260815
(the generator's v3.1-20260211 is refused, free); `$Input` is a PowerShell
automatic variable, so the parameter is `-Source`. Every new texture the kit
export brings imports as `compress/mode=0`: patch to 2 and re-import.

# The decrepit enforcer (2026-10-15)

```
blender -b models/source/enforcer/PUTRID_ENFORCER_BAKED.blend -P tools/build_decrepit.py
godot --headless --import --path .
```

Builds `models/decrepit.glb` from the user's file (second delivery 2026-10-17):
only the BAKED clips -- CRAWL_BAKED, SWIPE_BAKED, JUMP_BAKED, DROPKICK_BAKED,
DASH_BAKED. CRAWL and DASH arrive as `CRAWL_BAKED.001` / `DASH_BAKED.001`
(Blender's duplicate suffix), which the build drops; every unbaked source
action and track (some unmuted) and the empty STABS are removed. The build
asserts all five are present. With:

- the root motion taken out of SWIPE, JUMP and DROPKICK (printed as `root ...`
  tables, copied into scripts/decrepit.gd's ROOT_SWIPE / ROOT_JUMP /
  ROOT_DROPKICK -- re-copy them if the clips change); DASH plays in place;
- the IK constraints dropped and the knee flips eased (`smooth_knees`; the
  crawl as a cycle, so its loop no longer pops) -- except DROPKICK, whose
  somersault the flip detector misreads (`NO_KNEE_EASE`);
- one-frame pops spread over a few frames (`depop`: a bone turning > 35 deg in
  a frame and > 3x both neighbouring frames; found SWIPE f16 CALF_R, DROPKICK
  f93 SHOULDER_L / ARM_L);
- the parts joined into one mesh on a baked colour atlas
  (`models/source/enforcer/decrepit_atlas.png`) -- with metallic zeroed first, or
  the bake is black;
- bone markers "ShieldTip" (ARM_L), "EyeL" / "EyeR" (HEAD) and "Chest" (TORSO, the
  plating under the mask, for the crystal);
- printed for the script: the crawl's ground speed, and per attack clip a
  "contacts" line (shield point furthest forward / lowest, foot furthest
  forward, with frame and clip time) plus a per-frame track -- decrepit.gd's
  *_HITS / *_TIP come from these.

To change the clips: bake in Blender (only names ending `_BAKED` go out), copy
the file to `models/source/enforcer/`, run the build, re-copy the root tables
and hit times (*_HITS) into decrepit.gd, import, and check every switch (see
CLAUDE.md docs/notes/59).

After an import, set `models/decrepit_decrepit_atlas.jpg.import` to
`compress/mode=2` with mipmaps and re-import.

---

# The live rat (2026-10-18)

**In use: `models/rat.glb`**, the user's Tripo rat ("mouse with bones.blend",
kept as `models/source/rat/mouse_with_bones.blend`), rebuilt by
`build_rat.py`:

```
blender -b --factory-startup -P tools/build_rat.py -- models/rat.glb
blender -b --factory-startup -P tools/build_rat.py -- --preview <dir> [Run Idle Rear Dangle]
godot --headless --import --path .
```

The Tripo rig in the file is NOT used (the head and forelegs hang off the root,
not the spine; the tail hangs off a "limb"; three tail bones). The script keeps
the 566-vertex mesh and its texture, builds a clean 29-bone skeleton through
the mesh's parts (placed from the Tripo weights' clusters), skins it with
automatic weights (islands -- ears, eyes, whiskers -- to the head; smoothed,
4 bones a vertex), and authors four looped clips at 30 fps by posing in code
(`turn` about a world axis relative to the parent; analytical two-bone IK for
the legs, `two_bone`), baked to plain keys on NLA tracks:

- **Run** (10 f): a half-bound gallop, RUN_STRIDE 0.8 source m a cycle.
- **Idle** (150 f), **Rear** (150 f, the model's own standing pose).
- **Dangle** (120 f): hung by the tail, head down, writhing. `TailTip` is a
  bone at the very end of the tail to hang it by.

`--preview` writes contact sheets (side and three-quarter) of each clip.
Traps: opening the source resets the scene, so the fps is set after the load
(it came out 24); `export_def_bones` must be off or the non-deforming
`TailTip` is dropped; the texture is named after the packed image's PATH, so
the script sets it; swinging the hind TOES through the air put the ankle above
the hip and the thigh up through the rump (tearing) -- the swing drives the
ANKLE on a low arc instead. In the game: `scripts/rat_look.gd` (scale 0.5,
nose to -Z). Note 78.

# The surgery's kit (2026-10-21, Higgsfield)

```
blender -b --factory-startup -P tools/build_surgery_kit.py -- models/surgery
blender -b --factory-startup -P tools/build_surgery_kit.py -- --preview <dir> [names]
godot --headless --import --path .
```

Sources are in `models/source/surgery_hf/` (a `.gdignore` folder): for each
piece a `ref_*.png` (Higgsfield `gpt_image_2_5`, high, with the user's
reference picture of the surgery as an `image_references` input) and the
`raw_*.glb` Tripo H3.1 made from it -- the table, ring, claw, arm segment,
shelf, worktable, chandelier, jar and chest. `chart.png` is the anatomy chart
(copied to `textures/surgery_chart.png`). Prompt each piece ALONE on a plain
grey background, "whole object visible", or Tripo reconstructs the scene.

`build_surgery_kit.py` fits each to `models/surgery/<name>.glb`: welds, then
decimates to its budget (never decimate unwelded Tripo output --
`prep_kit_asset.py`), turns it so its front faces Blender -Y (Godot +Z), scales
it along one named axis, re-origins it (floor centre, or the top for hanging
pieces), sets its metallic factor (Tripo ships 1.0 on everything) and shrinks
its maps. `--preview` renders each from the front with Workbench: check which
way it faces before exporting -- the shelf first came out back to front.

- The extracted `<name>_*.jpg` imports come in at `compress/mode=0`: set them
  to 2 and re-import.
- The game lights these with their own albedo as emission (surgical_table.gd
  `glow`, `EMISSION_OP_MULTIPLY`): the candle flames, amber lamps and specimen
  fluid are the bright parts of the pictures. With the default ADD operator the
  whole piece would glow white.

The medieval set (note 96) is built the same way: `maiden`, `rack`, `gibbet`,
`brazier`, `pillory`, `toolrack`, `barrels`, `candelabra`. A generated hearth
was dropped: Tripo filled its firebox in solid (surgery.gd builds the hearth).
Concave openings -- a firebox, an archway -- are what image-to-3D fills in;
check the preview for them before paying for texture detail.

The rebuilt hall (note 98) adds 42 more: the architecture (`wallbay`, `jamb`,
`lintel`, `frieze`, `beam`, `brace`, `corbel`; the `fit` axis scales each to
exact dimensions), the study, the testing area, the shipping line and the
machine's parts. Most Tripo returns face +X; render each raw model from +X and
from -Y before choosing its yaw (one front render cannot tell +X from -X).
`textures/surgery_planks.png` and `surgery_flame.png` are generated pictures
used as textures (the ceiling, the flame licks).

The redone surgery (note 99) adds 23: skull-free wall frames, the gantry's
`girder` and `endtruck`, six shelves (`shelf_*`) for the maze, the tray rail
and cart, the pens' portcullis and bars, the disposal shaft's grate, and the
booth and lift (`platform`, `boothwindow`, `boothdoorwall`, `door`,
`console`, `handrail`, `liftcage`). `boothwindow`'s panes are split off as a
"Glass" object (`GLASS` / `split_glass()`) to be drawn see-through. The claw's
impact effects use `textures/surgery_fx_dust.png`, `surgery_fx_crack.png` and
`surgery_fx_chip.png` (generated pictures).

Note 102 adds four: `vat_bones` and `vat_gold` (the pushable vats; round tubs,
fitted by their longest horizontal extent so the tub itself is ~2.3 m across),
`crystal` (the powering room's, 2 m) and `hatch` (the trapdoor lid, hinges on
its -X edge). Pass Tripo `face_limit` (100000 or less) when converting: note
99's returns came at 1.4 M triangles. `-- --reduce [names]` welds and decimates
a raw that is over RAW_MAX in place before it is committed. The powering room is
furnished with note 98's machine pieces (`galvanic`, `pistons`, `column`,
`leverbox`, `flywheel`, `gear`, `clampmount`, `cable`, `track`) -- no new build
for those.

# The surgeon (2026-10-22, Higgsfield / Meshy)

```
blender -b --factory-startup -P tools/build_surgeon.py
```

`models/source/surgery_hf/raw_surgeon*.glb`: one Meshy image-to-3D character
rigged three times, each with one clip ("Checkout_Gesture",
"Alert_Quick_Turn_Right", "Fall_Dead_from_Abdominal_Injury"). The script puts
all three on the first armature as NLA tracks "work", "alert", "die", drops
Meshy's stray icosphere, and writes `models/surgery/surgeon.glb`.

Note 100: an optional 9th field `crop` keeps only the bottom fraction of a raw
model's height before fitting (the lift cage's chains and pulley, 0.745). Find
the fraction from a height profile of the raw (vertex extent per band). After
rebuilding a piece, check its textures' `.import` files: a rebuild can come back
with mipmaps off and a new uid -- `git checkout` them and reimport.

# The scout (2026-10-30, Blender, note 134)

```
blender -b --factory-startup -P tools/build_scout.py                       # model, bake, export
blender -b --factory-startup -P tools/build_scout.py -- --no-bake          # keep the maps
blender -b --factory-startup -P tools/build_scout.py -- --preview <dir>    # Cycles renders, no export
godot --headless --import --path .
```

`tools/build_scout.py` needs no source: it builds everything in Python, about 2
minutes with OptiX. It writes `models/source/scout/scout.blend` (low and high
meshes, rig, materials), the maps beside it, and `models/scout.glb`. `--no-bake`
keeps both the plate maps and the mantle's, so a change to `cloth_maps` needs a
full run, and any change to the geometry moves the UVs, so it needs one too.

The rig belongs to `scripts/scout_body.gd`: same bone names, same rests, and the
mantle's strand formulas are copied from it. Change them in both. Blender's
frame in the script is X right, Y forward, Z up.

The five extracted maps keep VRAM compression in their committed `.import` files.
After a change, check that those files still say `"vram_texture": true`; if one
says false, delete its files in `.godot/imported/` and import again.
