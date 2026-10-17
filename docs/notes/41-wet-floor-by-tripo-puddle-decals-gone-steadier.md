## 41. Wet floor by Tripo, puddle decals gone, steadier torch flicker (2026-10-14)

- **The floor is the original tan stone, wet** (supersedes section 40's dark
  grey retexture, whose files are deleted). At the user's request Tripo makes
  the wetness: `tools/tripo_image.ps1` (new; v3 image-to-image, seedream,
  5 credits) edited the user's floor photo into the same tile wet with puddles,
  and `tools/tripo_texture.ps1 -Image` (20 credits) retextured the floor's
  original generation from that picture -> `brick_kit_raw/floor_wet.glb`.
  A text prompt with the photo as `-StyleImage` (20 credits) came back dry,
  looking just like the photo. 255 credits left.
- **Tripo paints water into the colour only.** Its roughness map was matte on
  all three retextures (0.79-1.0). `build_brick_kit.wet_gloss` turns Tripo's
  water into gloss: where the wet colour is darker than the dry `floor.glb`
  colour (same UVs), blurred over 40 texels because the two textures' grain
  does not line up -> roughness `WET_POOL_ROUGH` 0.1, everywhere else
  `WET_BASE_ROUGH` 0.62 ("kinda wet"). 20% of texels end below 0.3. The floor
  uses Tripo's own normal map this time (0.33-0.67, real relief).
- **The decal puddles are removed** (damp.gd lays drips only; `WET_LAYER` is
  gone from brick_level). The drips stay: 72 in this level. The damp knob
  still switches the floor's specular, so with it off the floor is matte.
- **Torch flicker smoothed** (`torch.gd`): a low-pass on the flicker
  (`FLICKER_SMOOTH` 0.03 s) and gutters that sink in over `GUTTER_IN` 0.12 s
  instead of in one frame. Measured on 24 torches for 60 s at a fixed 60 fps
  (light energy / base, frame to frame): mean jump 0.157 -> 0.064, p99
  0.498 -> 0.190, max 1.12 -> 0.30, frames jumping > 0.15 45% -> 5%; the swing
  itself kept most of its size (sd 0.210 -> 0.172). 0.05 s halved the jumps
  again but cut the swing by 27%, more than "slightly".
- Bench (RTX 3060, 3440x1440, Ultra, editor closed): 74.1 fps, worst p99
  27.72 ms, 1085 MB (75.5 / 26.79 / 1086 before) -- noise.

