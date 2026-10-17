## 39. Damp floors and drips (2026-10-14)

- **Wet patches** (`scripts/damp.gd`, built by `maze._place_damp` after the
  clutter, brick kit only): 607 Decals that touch only the floor slabs -- the
  floor MultiMeshes are also on `BrickLevel.WET_LAYER` (1 << 13), the decals'
  `cull_mask`. Black albedo with the wetness in its alpha (`albedo_mix` 0.6,
  0.72 under a drip) darkens the stone; the ORM's green takes roughness from
  0.32 at the damp edge to 0.07 where water stands. Textures are 4 noise blobs
  made once at load. One corridor cell in three gets a patch (half of them
  along the foot of a wall, long way along it), courts more, one under every
  drip. The floor material gets specular (SCHLICK_GGX) only while damp is on.
- **The torches gave no specular at all** (`light_specular = 0` in
  `_hang_torch`, from the Tripo-module days: a glossy hotspot on the stone read
  as a lamp). With that, even a floor at roughness 0.04 rendered identical to a
  matte one -- measured. Now `TORCH_SPECULAR` 0.8 in the brick kit only; the
  brick materials themselves have specular disabled, so only surfaces that ask
  for gloss (wet patches, metal, the sword) respond.
- **No SSR.** It was the WHOLE cost of this feature (~1 ms a station, +80 MB at
  3440x1440) and adds nothing visible: the flames are additive transparent
  cards, which screen-space reflections never see, and a mirror-smooth floor
  under SSR with the torches' specular off looked the same as dry stone.
- **Drips** (70): single-particle GPUParticles3D whose process shader
  (`shaders/water_drip.gdshader`) runs one drop's whole life from its age --
  a bead swells on the stone, lets go, falls the measured height stretching
  with speed, splashes flat, gone till the next (period 1.8-4.6 s). Hung from
  the vault's underside found by `TriangleMesh.intersect_ray` up through the
  vault mesh itself, within 0.75 m of the corridor's middle (clear of clutter
  and carts), never in door, cart or skylight cells. `TORCH_DRIP_SHARE` 0.32 of
  torch straights, 0.04 of the rest: a drop is only ever seen by the light it
  catches. Measured: 0 of 70 drop paths blocked; falls 4.6-5.6 m. One node runs
  the range checks (emitting only within 26 m).
- **The drop is a glint, not water.** A 1 cm clear bead lit honestly showed as
  not one pixel in 40 frames from 2.4 m. It is unshaded and additive in the
  torches' colour (`DROP_GLINT`): a small warm streak falling through the dark.
- Traps: **`GPUParticles3D.preprocess` on an emitter that starts with
  `emitting = false` (as these do until the player is near) leaves it drawing
  nothing, ever** -- reproduced in an empty scene with a stock
  ParticleProcessMaterial too. Desync with a shader `phase` uniform instead.
  And filming a drop with screenshots: each stalls ~1 s, so slow-motion via
  `speed_scale` sampled the 1 s fall almost never; a big red unshaded debug
  drop at full speed proved the pipeline, then the real drop was found in the
  frames.
- Knob `Graphics.damp` ("Damp floors and drips"; off on Potato) hides the
  patches and drips and puts the floor back to matte.
- Bench (RTX 3060, 3440x1440, Ultra, editor closed, same session): before
  76.9 fps / worst p99 26.19 ms / 1082 MB; with damp (no SSR) 76.3 / 26.97 /
  1084 -- noise. (With SSR it was 72.2 / 27.46 / 1161.)

