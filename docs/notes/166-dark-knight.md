## 166. The dark knight: a closed, PBR-finished body and arms (2026-11-04)

The user: the attached "dark fantasy armored knight 3d model.glb" is the player
model; the arms must have no holes and look photorealistic. Replaces note 159's
fantasy armor everywhere it showed: the shadow alone, the body in co-op, the
first-person arms.

### The model (`models/source/armor/dark_knight.glb`)

Tripo again: blackened plate with gold seams, a torn tabard, T-pose facing glTF
+Z, 0.854 high, span / height 1.17 (the rig donor's 1.18). 31,272 triangles,
36,465 vertices that are only **15,939 places** -- Tripo splits a vertex at
every UV seam, and its atlas is thousands of tiny islands. One 4096 albedo and
nothing else: metallic 0, roughness 0.9, no normal map. 29 real openings once
welded (the pauldrons' undersides, the upper arms' sleeves inside them, the
tabard's free edge, a few pin holes).

### The body (`tools/build_player_knight.py`)

Same method as note 159 (scaled to 1.70 m, skinned onto the Meshy knight's
skeleton unchanged), with three changes:

- **Welded weights.** Weights are now worked out per welded place and smoothed
  over the welded edges, and every split copy of a place gets the same row. Note
  159 smoothed over the raw edges, which do not cross a seam, so the copies of
  one point could end with different weights and part under a bend -- a crack
  along a seam. That is the "holes" class of fault; it cannot happen now.
- **Arms nudged separately.** Slices (old armor vs new vs the rig): the torso
  sits where the old armor's did (`NUDGE` 2.5 cm back), but the arms are held
  3.5 cm further forward, so `ARM_NUDGE` 0.035 more, faded in over |x| 0.22-0.40
  (smoothstep) so the shoulder does not shear.
- **A PBR finish baked in Cycles** (OptiX), since the source has only colour:
  - normal map, tangent space, 4096: a Bump node (`BUMP_DISTANCE` 1.8 mm) on a
    height made from the albedo -- the plate's own shading (dark grime and
    carving low), the gold seams lowest, as grooves between plates. Baked, not
    computed in numpy, because the atlas's islands are too small for a filter
    to stay inside one;
  - ambient occlusion within `AO_DISTANCE` 12 cm (the creases, not the far side
    of the body), 2048;
  - roughness 0.55 + 0.20 dark + 0.20 crease on the plate, 0.38 on the gold;
    metal 0.60 plate, 0.90 gold (gold: bright, warm, saturated albedo; 7.1% of
    texels). Packed glTF ORM (R occlusion, G roughness, B metal), 2048;
  - the material double-sided (the tabard is one sheet). No emission: the gold
    is metal, not glow, so coop_avatar.gd / first_person_arms.gd `GLOW` simply
    find no emission now. `models/player_knight_knight_emission.jpg` deleted.
  First pass was plate roughness 0.40 base, metal 0.70, bump 2.5 mm: in game
  under a torch it read as wet, molten bronze; the values above read as worn
  dark steel.
- Albedo kept at 4096 (named `Image_0` so its .import carries over), normal 4096,
  ORM 2048, JPEG 90. `player_knight.glb` 1.7 -> 8.5 MB.

### The arms (`tools/build_player_knight_arms.py`)

- **Closed.** After the cut to the arm bones, the seam copies are welded
  (10,495 -> 4,402 vertices; UVs are per corner, so they survive) and every
  opening left is capped (`bmesh.ops.holes_fill`, triangulated): 6 openings,
  178 triangles, **0 open edges left** (it prints the count). A cap's corners
  take that vertex's existing UV, so it is the rim's own metal.
- Normals rebuilt on the welded, curled mesh: smooth, hard past 40 degrees
  (`SHARP`) -- the curled fingers now shade as bent.
- Same knuckle line as the fantasy armor (`KNUCKLE` 0.935: thumb at
  0.88-0.92, fingers from 0.94); `FINGER_Z` 1.333 -> 1.340 (fingers at
  z 1.32-1.37). Printed grip, held in `first_person_arms.gd` `GRIP`:
  (0.935, 1.307, -0.0554) -> (0.935, 1.314, -0.0736).
- `first_person_arms.gd` draws the arms material double-sided
  (`CULL_DISABLED`): belt and braces, a hand's breadth from the eye.
- 8,796 faces (was 3.4k); 641 KB.

### Seen in game

Throwaway `tools/shot_knight.gd` (deleted): the starting cell, facing its torch,
3440x1440 -- sword at rest and mid-slash, spear, axe, and the body from outside
under a warm lamp. The gauntlet and vambrace read as dark worn plate with gold
seams catching the torch; no gaps through the arm, at the cuff or at the
shoulder through a swing. The body: the whole knight, plates following the
bones.

### Measured

RTX 3060, 3440x1440, the user's settings, `--bench --size=3440x1440`, old
knight (HEAD) and new alternated, two runs each (avg fps; gpu ms at the spawn
corridor):

```
                     new 1    old 1    new 2    old 2    new 3*
spawn corridor        45.1     46.1     45.4     46.0     45.4
boss room centre      53.9     55.3     55.9     56.2     56.0
boss room edge        64.4     65.1     64.9     65.5     65.6
outer maze            50.2     52.9     52.9     54.1     54.0
chest room            37.8     37.9     38.5     38.4     38.5
surgery               36.2     36.8     36.9     37.0     37.1
OVERALL fps           47.9     49.0     49.1     49.5     49.4
gpu ms, spawn        20.09    19.75    20.01    19.81    19.94
primitives, spawn    11.67M   11.21M   11.67M   11.22M   11.54M
video memory (MB)   1740.4   1530.3   1740.4   1530.3   1657.8
```

The knight costs about 0.2 ms of GPU (0.45M more primitives a station: 31k
triangles in each shadow pass instead of 10.5k) -- inside run-to-run noise in
fps. *Run 3 after the normal and ORM maps were set to VRAM compression (the
headless import had left them lossless: +210 MB -> +128 MB).

**The whole game read 49 fps this session, old knight and new alike** (note
159 read 63-65 on the same settings). Nothing of the game's changed: the GPU sat
at 57% busy with the game closed (`nvidia-smi`; Wallpaper Engine the heaviest
process, Epic, Chrome) -- note 159's trap again. Judge 60 fps on an idle GPU.

Clean `--quit-after 2400 -- --skip-title` run: stderr empty.

### Traps

- Tripo's "boundary edges" are UV seams: 33,948 of them before welding, 696
  after. Count holes on a welded copy.
- `bpy.ops.object.bake(type="AO")` reads its distance from the scene's world;
  a factory-empty scene has none -- make one and set
  `world.light_settings.distance`.
- A bake target image made under a name the final image wants takes the name
  first: the final gets `.001`, and so does its file in the .glb.
- The welded tabard is part of the one body shell, so it could not be picked
  out as cloth by connectivity; it is metal like the rest.
- A texture new to a .glb, imported headless, comes in **lossless**:
  `detect_3d` only fires in the editor. Set `compress/mode=2` (and
  `compress/normal_map=1` for a normal map) in its .import by hand.
- `--resolution` on the command line still does not size a `--script`
  harness window (note 156): it came up 3440x1440.
