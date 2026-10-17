## 38. Night and the red moon (2026-10-14)

- **The red sky and its fake lights are gone.** The courts, the boss hall and
  the floors under the skylights are lit by the scene's "MoonLight"
  DirectionalLight3D, set up by `maze._setup_moon` (it was a faint, shadowless
  blue light at 0.07 that lit every corridor through its roof): `MOON_COLOUR`
  (1.0, 0.16, 0.09), `moon_energy` 2.4, `MOON_ELEVATION` 72 / `MOON_AZIMUTH` 45,
  PSSM 4 splits to `MOON_SHADOW_DISTANCE` 95 m (chunks are culled at 70 m +
  half a block; past the shadow distance it would light everything it faces).
  `place_room_lights` now places nothing (returns the empty holder the prison
  and puzzle code still look in; `faked := true` for the old omnis), the
  skylight spotlights are off (`SKYLIGHT_SPOTS`), the boss hall's sky lights
  and the rock fills are gone.
- **High, because of the skylights**: the shaft is 1.65 m deep through a 1.0 x
  2.4 m opening. At 62 deg the light landed on the corridor wall; at 72 it
  makes a barred pool on the floor (the grate and liner now cast).
- **Everything open to the sky must cast**: the prison dome, band, partitions
  and gates, the boss hall's walls (`boss_hall._add_mesh` had shadows OFF, so
  the hall let the moon through its walls), the morgue's dead and coffins, the
  shard door, the portcullis and the mine's props now cast. The corridor lid
  and skirts cast too -- the Tripo vault has small holes -- on their own visual
  layer `BrickLevel.MOON_ONLY_LAYER`, which every torch leaves out of its
  `shadow_caster_mask` and cull mask. Skylight cells used to have NO lid; they
  get a frame of lid round the shaft (a stray spot of moon came through the
  vault's holes beside the pool).
- **The boss hall's stone was too dark to light**: its textures average ~0.12
  albedo against the flagstones' 0.41 (energy-10 sky lights hid that). Paving
  0.72 -> 1.25, walls x1.65 on the colour (~3x linear).
- **Graphics**: the moon is on only with shadows (`_apply_light`, meta "moon");
  Hard uses 2 splits, Soft 4. On Potato (no shadows) it is OFF -- it would
  light every corridor -- so the courts have only the base light there.
- **The sky** (`shaders/sky_clouds.gdshader`): night colours, the moon's disc
  drawn at `LIGHT0_DIRECTION` (`moon_size` 0.06 rad, mottled, limb darkened,
  `moon_intensity` 7 -- at 16-28 ACES burnt its core to peach), a red haze and
  corona, clouds near it catching its light, sparse twinkling stars. Disc and
  stars are drawn in the full-res pass behind the clouds: the quarter-res pass
  writes cloud coverage to ALPHA (`_compute_full(dir, out cover)`; Godot
  shaders have no mutable globals).
- Measured (harness, torch flicker frozen so moon-on/off differ only by the
  moon): 8 corridor spots, worst +0.0002 luminance (none); every skylight's
  floor pool shows the bars; courts 1.1-4x brighter; the boss hall lit with
  column shadows. Harness traps: after a teleport the nearest torches fade in
  over ~0.4 s -- wait 90 frames before comparing shots; a player with
  collision_mask 0 falls through the floor while you wait; and the boss hits a
  test player down to low health, which desaturates every shot.
- Bench (RTX 3060, 3440x1440, Ultra, editor closed): **65.1 fps, worst p99
  33.33 ms, 1106 MB** (72.3 / 27.78 before). The moon's 4 cascades redraw the
  level's geometry; the prison (dome now casting) is the worst, 28.7 ms.

