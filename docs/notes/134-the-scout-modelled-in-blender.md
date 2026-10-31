## 134. The scout modelled in Blender: a real model on the same rig, every animation untouched (2026-10-30)

The ask (from Noah, through the project coordinator): model the scout in Blender,
driven from its command line, and put it in the game in place of the look built
from primitives. Keep the .blend in the repo, keep gameplay and animations working.

This supersedes the mesh half of note 127 (`_Builder`, `_build_head` and the rest,
`_plate_textures`, the vertex-colour rust): all of it is gone from `scout_body.gd`.
The animation half of note 127 stands unchanged, and so do notes 128 and 129.

### What was built

`tools/build_scout.py` (Blender 5.2, no source file: it starts from an empty
scene) writes `models/source/scout/scout.blend`, its maps beside it, and
`models/scout.glb`. Godot extracts `models/scout_plate_{col,orm,nor}` and
`models/scout_cloth_{col,nor}` from the glb.

- **Body**: 34,182 triangles, 17,894 vertices, three surfaces named `ScoutPlate`,
  `ScoutCloth`, `ScoutGlow`. **Spear**: 1,816 triangles, same plate maps. The old
  spear was 2.4 m and this one is too: `SPEAR_TIP` 1.80, `SPEAR_BUTT` 0.60.
- **The helpers**: `lathe`, `shell` (a curved plate with thickness), `band` (a shell
  round an upright axis), `loft`, `gear` (real teeth), `blade` (forged diamond
  section), `rbox`, `arc_seg` (a finger joint bent round the shaft).
- **The look**, by part:
  - head: dome with iron gore straps, crest, brow band, goggles with knurled bezels
    and brass hoods bent low over the inner side (a glare, not a stare), real ear
    gears, nape lames, a slot mouth with steel teeth between lip and jaw;
  - body: pigeon breastplate with a keel, back plate and power box, gorget, belly
    lames, belt, buckled pouches, placket, skirt, two-tier tassets;
  - limbs: pauldrons with three lames, gear joints, winged cops, vambraces, cuisses
    in two plates, greaves with a rib that follows the calf, sabatons with instep
    lames and a toe cap;
  - hands: four fingers of three joints each and a thumb, closed on the shaft.
- **Low and high**: the low mesh is what the game draws. The high mesh is the low
  one plus detail that is only ever baked (about 32k faces of rivets, straps,
  knurling). Selected-to-active in Cycles (OptiX on the 3060, about 2 minutes),
  `cage_extrusion` 0.0075, `max_ray_distance` 0.02.
- **The plate material** (`plate_shader`) is procedural and reads two attributes
  set part by part: `scout_col` (colour + rust share) and `scout_pbr` (metal,
  roughness). Rust grows where noise and crevices agree, ambient occlusion puts
  grime in the gaps, and a Bevel node finds edges and wears them bright. That Bevel
  also rounds every hard edge in the baked normal map, so no bevel geometry is
  needed. Metal stays at most about 0.7, because full metal goes black in this
  dungeon.
- **The mantle** has its own 1024 maps drawn in numpy (`cloth_maps`): a weave,
  stains, road dirt up from the hem, and long tears in the alpha, which import as
  alpha scissor through the exporter's GREATER_THAN node.

### The mantle changed shape

It now stops at 103 degrees either side of straight behind (`span`), not 150, so
the pauldrons and breastplate show from the front, which is where the player sees
it. `STRANDS`, `STRAND_SPAN`, `_cloak_edge`, `_cloak_len` and `_cloak_hang` are
unchanged, and the Python copies of them must stay equal to the GDScript ones.

### Wiring it in (`scout_body.gd`)

- `_load_model` instantiates the glb once, takes the skinned mesh and the plain
  (spear) mesh, finds the glow surface by the material name `ScoutGlow`, and frees
  the scene. The skeleton is still built in code from `BONES`, so `_animate` is
  untouched.
- `_binds` makes a new Skin: the glb's bind order and names, with this rig's rests.
  See the first trap.

### Measured

Throwaway windowed harnesses (deleted):

- **Sandbox, the real `scout.gd`**: idle, tri-stab, swipe, dash, reel and death all
  ran and were looked at from two sides, with no script errors. The spear falls and
  the body folds as before.
- **Real level, the real lighting** (21 scouts, one woken in a corridor, 240 frames):
  worst palm to shaft 0.000 m (right), 0.028 m (left).
- **Clean run**: `--quit-after 1500 -- --skip-title --no-intro`, windowed: 0 errors
  or warnings on stderr, exit 0.

**Bench** (RTX 3060, 3440x1440, `--bench --size=3440x1440 --no-intro`, same seed, 21
scouts, editor closed, nothing else running). "Before" is `HEAD`'s `scout_body.gd`
put back for the run:

```
                     overall fps   worst p99 (ms)   video mem
before (primitives)     80.4         18.06           935.3 MB
after (uncompressed)    80.5         18.06          1019.6 MB
after (VRAM S3TC)       80.6         18.06           958.2 MB
```

No measurable frame cost; 23 MB of video memory. The bench stations rarely have a
scout in view, so this says the level is unaffected, not what a screen full of
scouts costs.

### Traps

- **The exporter does not keep a rest of identity.** Every Blender bone runs along
  +Y with no roll, and the glTF has no rotation on any of them except the root
  `Hips`, which carries the turn to Y-up. So each joint's world rest is that turn,
  and the glb's own inverse binds would lay the mesh down on its back on a rig with
  identity rests. `_binds` replaces them. The mesh's vertices are in model space
  either way.
- **`image.pixels` on a byte image is as stored**: sRGB, not linear. The first
  mantle wrote linear values and came out black.
- **`image.pixels` row 0 is the bottom row, UV v 0.** Flipping it put the tears at
  the collar.
- **`bmesh.ops.recalc_face_normals` flips open surfaces at will.** It turned
  gorgets and such inside out, and a bake from the wrong side reads as black jagged
  patches. Winding is now set where each part is built: `lathe` by its profile,
  closed parts by signed volume (`Acc.push`, `closed`).
- **A lathe's pole fan wound the opposite way to its quads.** Every gear hub was a
  black hole until that was fixed.
- **Smart UV Project spent the atlas badly**: most of it on hundreds of tiny
  islands, and on inner faces no one can see. Plates now unroll as they were built;
  inner faces share a patch in the corner (`INNER_FIT`, `fill_corner`); the head is
  given 1.7x density and the hands 1.5x. Blender's own `pack_islands` left half the
  atlas empty, so `shelf_pack` does it (71% filled).
- **The exporter's tangents need triangles**: "Could not calculate tangents" until
  the body and spear are triangulated.
- **A first `--import` left textures uncompressed.** The `.import` files must say
  `compress/mode=2`, `detect_3d/compress_to=0`, and `compress/normal_map=1` on the
  two normal maps; those are committed. Editing them was NOT enough for the plate
  maps: `--import` skipped them until their `.godot/imported/scout_plate_*` files
  were deleted. Check `"vram_texture": true`.
- **Deleting `scout.glb.import` and re-running `--import` through a PowerShell `*>`
  redirect imported nothing** and the game then failed on a null mesh. Run it with
  `Start-Process` and logs, and check the `.import` came back.
- **No system Python on this PC.** Blender's is at
  `C:\Program Files\Blender Foundation\Blender 5.2\5.2\python\bin\python.exe`.

### Not done

- Sounds, as note 127.
- `compress/high_quality` is off. Very close (under a metre) the BC1 blocks show.
  At fighting distance they do not.
