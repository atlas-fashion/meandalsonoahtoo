## 55. The sewer remade again: one stone, mold and sludge, moss light (2026-10-15)

Supersedes section 54's kit geometry and torches, at the user's request ("the
pipe bricks the same as the dome bricks... no walls between the modules in the
watercourse... black mold and sludge... no torches, moss and fireflies").

- **ONE CSG in ONE material** (`sewer.gd _build_csg`): each straight RUN is a
  single extrusion of the pipe outline (walls to `PIPE_SPRING` 1.9, round vault,
  crown 3.9 m, `PIPE_HALF` 2.0) from chamber centre to chamber centre, with its
  channel (`CHANNEL_HALF` 0.62, round invert 1.02 m down) cut the same way; the
  chambers (`CH_R` 2.8 -- 3.0 left adjacent unconnected chambers touching -- wall
  4.4 m, dome 1.8 m more) are CSG cylinders and spheres in the same tree, so the
  pipes' mouths are cut by the pipes themselves and the channels cross in every
  chamber. Measured: a ray down every run's centre line every 0.25 m (3,972
  samples, through every chamber) found the invert at exactly -1.02 everywhere
  but the ladder gratings: no lip, step or wall in the watercourse.
- **A closed side is a CULVERT** (`_culvert_deep`): the pipe outline at half size
  2.2 m into the rock (0.6 m where another pipe runs behind, 0.12 where another
  chamber does), the channel running into it, behind an iron grille built to its
  exact arch (`_build_grilles`: bars into the stone and down into the channel,
  two bands, an arch band, a padlock; one box of collision). A faint moss light
  deep in each culvert silhouettes the bars.
- **The stone** is `shaders/sewer_stone.gdshader`, all world triplanar
  (whiteout-blended normals; normal z rebuilt from x/y, as the import may pack
  two channels): the domes' Higgsfield brick, its speckle eased 40% toward its
  mean (in faint light only the brightest specks caught and the walls read as
  glitter), black mold (Higgsfield `tex_mold`, laid by world noise + lower walls +
  vertical damp streaks + the crown), a ragged sludge line at every wall's foot,
  Higgsfield sludge over the walkways, slime in the channel; wet surfaces glossy.
  Traps: a GLSL helper may only be handed samplers with the same hints (the
  noise needed its own function: "Sampler argument 0 ... called more than once");
  and the sludge projected from above smeared down every vertical face as
  streaks -- it is triplanar too.
- **Water** (`shaders/sewer_water.gdshader`): one plane per cell at `WATER_Y`
  -0.42, under the walkways (the stone hides it except in the channels), mapped
  in world space -- one surface end to end, no overlaps; deep culverts get their
  own strip. `water_surface_at` asks the cell and its neighbours' channel arms.
  Wading 0.60 m in a pipe, where channels cross, and up to a grille.
- **The ladder's foot is always over a channel** (the shaft is on the corridor's
  axis above; every chamber has an arm each way), so `_build_plates` lays an iron
  grating there with collision: the player stands on it dry.
- **Light**: no torches. Bioluminescent moss (Higgsfield `tex_moss`, faded round
  its edge in the texture build -- square decals showed their edges on the
  curved stone) as emissive decals in the crack at each wall's foot (cast at 45
  deg so they paint wall and walkway), patches up the walls; 60% of crack
  clusters and every culvert carry a faint green omni (`MOSS_LIGHT_ENERGY` 1.2,
  range 4.5, no shadows): 649 decals, 133 lights. Fireflies: GPU particles on
  turbulence in ~70% of cells, blinking out of step, 5 each (2 without
  `Graphics.effects`). While the camera is below, `_haze` swaps the fog to a
  glowing murky green (`HAZE_*`) and the ambient to `DAMP_AMBIENT` x
  `DAMP_AMBIENT_SCALE` 2.2, restoring both above. Measured mean luminance in
  game shots: pipe 0.034, chamber 0.029-0.043 (the dungeon between torches is
  ~0.01-0.03); flat-lit diagnostics confirmed the brick, mold and sludge read.
- `tools/build_sewer_kit.py` now exports only "bones" (the tunnel, gate and
  fungus models are gone, with their raw sources and images).
- Cost (RTX 3060, 3440x1440): sewer GPU 7.3-15.2 ms at 6 spots against 11.3 at
  the dungeon's spawn; most draw calls there are the dungeon above. Bench:
  67.6 fps, worst p99 31.06 ms, 1190 MB (66.6 / 31.02 / 1180 before) -- noise.
- Higgsfield: three more images (mold, sludge, moss) at 1.5 credits each.


