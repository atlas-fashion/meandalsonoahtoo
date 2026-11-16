## 188. The scout's look remade with ForgeGUI, on the same rig: every animation untouched (2026-11-15)

The ask (Noah, 2026-11-14): "Have forgeGUI remake the scouts look. Keep all logic and
animations the same. make sure the new scout model works perfectly with the current
scout animations." And on 2026-11-15, while this was being tested: "I am running a game
at the same time. All tests shouldnt unfocus my focused window."

This replaces the LOOK of note 134 (the Blender scout). `scout.gd` is untouched; the
rig, the gait, the IK, the springs, the cloth and every move of notes 127-129 are
untouched. `models/scout.glb` and `tools/build_scout.py` stay, and `-- --old-scout`
draws the old one for an A/B.

### What was built

- **The generations** (ForgeGUI, Meshy, PBR 2048 maps), in `models/source/scout_forge/`:
  - `body_v1.glb`, job `6314c5fc-f41e-4d0c-b817-b92566607788`: "a lean, slightly hunched
    humanoid robot scout soldier from a dark medieval dungeon, realistic and grim,
    soulslike ...": dark riveted iron plate, brass goggle eyes and ear gears, a grated
    mouth, a torn hessian cowl, pouches on a belt, tassets. 1.70 m, A-pose, one welded
    shell.
  - `body_v1_rigged.glb`, job `210b4713-f4e9-4e6a-a4fe-a2b722e409f9`: the same body
    rigged by ForgeGUI (`generation_rig_3d`). The build reads this one.
  - `spear_v1.glb`, job `94ed40dc-affb-486d-bcf6-75e26e71540f`: a barbed war spear with
    a bound shaft.
- **`tools/build_scout_forge.py`** (Blender, 15 s, no bake) fits them onto the scout's
  own rig and writes `models/scout_forge.glb` (body 15,432 triangles and 30,638
  vertices, was 33,762 triangles over two surfaces; the lenses 40; the spear 5,000, was
  1,816; 31 bones; six maps, body 2048, spear 1024) and `scripts/scout_forge_binds.gd`.
- **`scout_body.gd`**: `MODEL` is the new glb, `OLD_MODEL` the old; `_load_model` reads
  `MAPS` from the binds script and `_binds(from, maps)` multiplies each bone's map into
  its bind. Nothing else in the file changed: 2 surfaces instead of 3, the glow still
  found by the material name `ScoutGlow`.

### How it fits (the idea worth keeping)

The rig's rests are all identity orientations at `BONES`, arms and legs straight down.
The generation stands in an A-pose with its own proportions. Instead of re-posing and
re-skinning the mesh, each scout bone gets an **affine map from the generation's pose to
the rig's rest**, and that map goes into the skin's bind (`bind = rest^-1 * map`). The
mesh stays exactly as generated; the rig draws it as generated whenever it is posed as
the generation stands, and every animation drives it as it drove the old mesh.

- The whole body is scaled once, `SCALE` 1.095: shoulders 1.449 and hip sockets 0.925
  land on the rig's 1.45 and 0.93. 1.86 m tall, as the old scout.
- Trunk, neck and head: the identity.
- Each limb bone: turned about its own joint from its A-pose direction to straight
  down, and stretched along its length to the rig's bone (upper arm x1.117, forearm
  x1.04, thigh x1.10, shin x0.90).
- The fists: their centre onto the rig's grip, `GRIP_OFF` 0.07 below the wrist, so the
  shaft runs through them. The feet: rigid, the ankle's pivot onto the rig's, the toes
  turned straight (the stance turns them out itself).
- Weights: Meshy's bones summed onto the scout's (`MAP`), then `clean_weights`: a thigh
  lets go of what is above its socket and of the other side of the body, and the
  weights are smoothed 3 passes over the welded surface.
- **The eyes**: `find_lenses` casts rays over the face and picks the brass rims out of
  the albedo; two discs sit 8 mm proud of the glass as the surface `ScoutGlow`, which
  `_eyes` drives as before.
- **The cowl on the mantle's strands** (`cowl_weights`, `COWL`): the rig's verlet mantle
  (`_cloak`) still runs, so the cowl's hem hangs on the upper bone of the two strands
  either side of each vertex. Cloth is found by the **metal map** (cloth 0.0, plate
  0.6); the share grows from nothing at 1.46 m to 0.32 at the hem (1.22 m), is whole
  round to 90 degrees from straight behind and gone by 125, and is cut where an arm
  holds the vertex. Each strand's map undoes the turn `_cloak` gives it at rest
  (`_swing(down, ...)`), so the cowl hangs as generated when the cloth hangs still.
- **The dungeon's grade** (`grade`): albedo lifted by a gamma of 1.5, metal scaled to
  0.35, on the body and the spear.

### Measured

Throwaway harnesses (deleted), all run on a hidden desktop (see below):

- **Sandbox, the real `scout.gd`**, the mesh skinned on the CPU each sampled frame:
  idle, walking about, hunting and fighting by itself (it made spot, dash, swipe x2,
  tri-stab x2), each move forced, a reel, death. No script errors, no NaN.
  - Fist centre to the spear's shaft, worst over every phase: 0.027 m right, 0.028 m
    left. The old model in the same run: 0.025 right, 0.060 left.
  - Poses compared with `-- --old-scout` in the same run, picture by picture: the same
    stance, stab, swipe, dash and fall.
  - Edges opened (how far two joined vertices part from their modelled distance):
    0.047 m worst at idle, 0.095 m worst in a fight, all at the hip crease where a
    thigh turns under the tassets; the same before and after the cowl went onto the
    strands.
  - The cowl: 308 vertices carry over 0.12 on the strands; its hem strays up to
    0.045 m at idle, 0.08 walking, 0.12 in a fight or a dash from where the chest
    alone would hold it.
- **The real level**: 51 scouts; the player stood 3.4 m from the nearest, which
  spotted, stabbed and swiped. The old scout in the same corridor for comparison.
- **Clean run**: `--quit-after 1500 -- --skip-title --no-intro`: nothing from the
  scout. (Two `It's not expect to not find the most reachable polygons` from
  `sewer_lizard.gd` `_wander`, a lizard's own path query: in 2 of the 4 real-level
  runs, none in the first with the new scout. Not this change's.)
- **Frame time: NOT measured.** Noah was playing another game on the PC throughout, so
  a bench would have been invalid and would have slowed his game. Fewer triangles
  than the old body (15.4k against 33.8k), one surface fewer, the same 2048 maps plus
  three 1024 maps for the spear, which had shared the plate's. Measure on an idle PC:
  sandbox, 16 scouts, `-- --old-scout` against none, interleaved.

### Traps

- **One lens did not glow.** The left disc's winding was flipped "for the mirror", but
  its frame (`u`, `v`, the normal) is the same handed frame on both sides, so the flip
  faced it into the head. One winding for both.
- **As generated the scout was invisible in the dungeon.** Dark iron (albedo 0.25) at
  metal 0.6: at 3.4 m in a corridor only its eyes and a ghost of the cowl showed, where
  the old tan plate read plainly. Note 134 had the rule already (metal low, or it goes
  black here). The sandbox's flat light hid it completely: **look at a new enemy in the
  real level before calling its look done.**
- **Albedo cannot tell the cowl from the plate** (0.28 against 0.25 luminance); the
  metal map can. And the generation is one welded shell: the hem is joined to the plate
  under it, so at a share of 0.4 with a hard edge the joining faces drew out into
  slivers on a stab. A smaller share, 4 smoothing passes of the cloth mask and one of
  the share, and nothing over the arms cured it.
- **The worst-case numbers of a harness that teleports the scout are the teleport**:
  the cloth snaps when the body jumps 8 m. Strand turns of 90 degrees "at idle" were
  that.
- **Meshy's "Left" is the figure's own left**, which, turned to face -Z, is the rig's L
  at -x.
- `tools/__pycache__` appears if another script imports the build script; delete it.

### Tests must not take the screen (`tools/hidden_run.ps1`)

A plain `--windowed` Godot run opened at 3440x1440 over Noah's game, took focus and
played the game's sound. `tools/hidden_run.ps1` starts a command line on a separate
Windows desktop that is never shown (`CreateDesktop`, `STARTUPINFO.lpDesktop`): Vulkan
on the 3060 renders there as usual, and nothing the process does (windows, focus, mouse
capture) reaches the user's desktop.

```
& tools\hidden_run.ps1 -Cmd '"<godot_console.exe>" --path . --windowed --audio-driver Dummy --script res://tools/x.gd -- ...' -Log <file> -Cwd <project> [-TimeoutSec 300]
```

- Always add `--audio-driver Dummy`.
- Call it with `&` from PowerShell; through a nested `powershell -File` the quotes in
  `-Cmd` are mangled and `CreateProcess` fails with error 3.
- Take pictures from a `SubViewport` of the harness's own (`world_3d = root.world_3d`,
  its own `Camera3D`), or from `root.get_texture()`; both work there.
- Blender `-b` and `godot --headless --import` open nothing and need no wrapper.

### Not done

- Frame time and video memory, as above.
- The eyes are plain discs (the old lenses had rings) and smaller than the old ones;
  `EYE_ENERGY` is unchanged.
- The mantle's lower bones (`CloakNB`) carry nothing now; the cloth still simulates
  them.
- Sounds, as notes 127 and 134.
