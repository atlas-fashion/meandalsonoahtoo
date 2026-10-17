## 53. Enforcer eye rings traced from the lenses (2026-10-15)

- Each eye is a grey domed LENS in a raised bronze bezel. The glow rings were
  fixed-size TorusMeshes on the EyeL/EyeR markers, and those markers (centroids
  of the two "front-most bulges") sat on each lens's INNER edge, ~5 cm off its
  centre at the authored size: the rings were off-centre and cut into the bezel.
- `tools/build_enforcer.py` now builds the rings into the model ("EyeGlowL" /
  "EyeGlowR", bone-parented to HEAD; `measure_lenses` + `build_eye_glow`):
  the head rendered front-on in ortho, workbench, texture colour under flat
  light; each lens = the grey disc (saturation < 0.22, value > 0.33) in its half
  of the image; outline traced on 96 bearings, re-centred three times, then
  low-passed to `LENS_HARMONICS` 3 (a 5-point average still left it visibly
  wobbling -- the rust speckle nicks the trace); rays from those image points
  back along the view onto the mesh; a band over `LENS_BAND` 0.70-0.95 of the
  lens radius, `GLOW_LIFT` 0.004 off the surface along its normal. The EyeL/EyeR
  markers are moved to the lens centres. Measured: lens radius 0.050 / 0.052
  (authored units), centres x -0.142 / +0.170. Per-vertex texture sampling did
  not work: the lens is only a handful of big triangles.
- enforcer.gd puts `_eye_mat` on those meshes (kept out of `_parts`); the torus is
  a fallback only. Checked with a close camera: rings alone vs with the body
  are identical complete circles head-on (nothing covers them); from the side
  the near bezel's lip hides part of a ring, as it hides that part of the lens.
- Not benchmarked: two 288-quad bands replace two tori.

