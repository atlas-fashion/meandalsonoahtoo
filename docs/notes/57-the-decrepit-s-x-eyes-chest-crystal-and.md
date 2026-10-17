## 57. The decrepit's X eyes, chest crystal and fits; the channel grated over (2026-10-16)

- **Glow in the moss's green** (decrepit.gd `GLOW` = sewer.gd MOSS_GLOW): eyes,
  crystal and the face glow, so far off it passes for one more patch of moss
  (measured at 14 m: lost among the moss lights) until close.
- **X eyes**: two crossed bars (`EYE_BAR` 0.085 x `EYE_THICK` 0.014 m) on each
  EyeL / EyeR marker, sized in metres against the marker's rig scale, unshaded.
- **The enforcers' crystal in its chest**: the enforcer's is an octahedron (6
  verts, found in ENFORCER_BAKED.blend's tripo_part_21), so this one is built in
  code (`_attach_crystal`, `CRYSTAL_SIZE` 0.11 x 0.2 x 0.08 m, emissive, drawn
  both sides) on a new "Chest" marker (build_decrepit.py): a ray from in front
  onto faces skinned to TORSO, at the torso bone's root -- in the rest pose the
  mask covers the front from z 3.28 up, and the first try (60% up the bone) put
  the "chest" on the upper back above the eyes.
- **Spasmodic flicker** (`_process`, `_fit`): eyes and crystal each have fits --
  OUT for 35-170 ms, STUTTER on/off at 14-30 Hz, SURGE to 1.9x, sag DIM --
  over a fast shimmer, at random intervals, out of step; one fit in five runs
  through both. The face glow follows both. Measured over 360 frames: 40
  cut-outs, 14 surges, 119 sharp jumps; eyes and crystal equal on 70.
- **The channels are grated over** (sewer.gd `_build_gratings`, replacing the
  plate at each ladder's foot AND the decrepit's invisible floor, layer 14 --
  both removed): rails on the channel's lips and slats across, the water showing
  through, along every pipe, across every chamber and up to every culvert's
  grille; one metre piece instanced (889 in this level, one MultiMesh, one draw)
  with a box of collision per arm for everyone. Trap: boxes that only MET at a
  cell boundary let a ray straight down the seam slip between them (35 of 3,972
  points) -- each open arm laps 3 cm into the next cell. The player no longer
  wades anywhere in the sewer; `water_surface_at` is still there (it is below
  them). The navmesh bakes from the stone and the grating (mask 256).
- Measured (harness, 10/10): X of two 0.085 m bars in each eye; crystal 1.27 m
  up on its front; all three the moss's green; the fits above; 3,972 of 3,972
  points down the channels and 32/32 culverts on the grating; the player stands
  on it dry; navmesh 482 polygons; chase 7.15 m/s on the grating.
- Bench (RTX 3060, 3440x1440, editor closed): 66.9 / 67.7 fps, worst p99 34.04 /
  33.90 ms, 1195 MB (67.9 / 30.97 / 1214 before -- the average unchanged; the
  stations are all above ground).

