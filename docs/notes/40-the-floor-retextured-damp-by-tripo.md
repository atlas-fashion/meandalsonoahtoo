## 40. The floor retextured damp by Tripo (2026-10-14)

- `tools/tripo_texture.ps1` (new; Tripo v3 `/models/texture`) retextured the
  floor's ORIGINAL generation, task 7b41eb15-... (found in the usage log and in
  the kit texture's file name), with a "damp dungeon flagstones" prompt at
  v3.5, detailed: 20 credits, 300 left. Same mesh and UV islands, so it drops
  into the kit build: `build_brick_kit.build_floor` reads
  `brick_kit_raw/floor_damp.glb` when it exists.
- What came back, measured: albedo cold neutral grey, mean 0.29 (the old tan
  0.41); roughness 0.79-0.91 (old 0.92-1.0) with NO distinct puddle regions;
  and a nearly flat normal map (0.475-0.522 against the old 0.32-0.68). So the
  build grafts the ORIGINAL normal map back on (`relief_normal`; UVs match),
  `brick_level.meshes` keeps the floor's roughness map (`roughness` 1.0) where
  every other piece is flattened to 0.95, and the puddles are still damp.gd's
  decals. The sheen only shows while the "Damp floors and drips" knob has the
  floor's specular on.
- Traps: the v3 API answers on `openapi.tripo3d.ai` (the docs' `.com` host
  gives this key 401); `-Model` must be v2.5 / v3.0 / v3.5 (the generator's
  v3.1-20260211 is refused, no charge); a PowerShell parameter cannot be called
  `$Input` (automatic variable); the two new textures imported as
  `compress/mode=0` again -- patched to 2. The old floor colour / ORM jpgs are
  deleted; its NormalGL is still used.
- Bench (RTX 3060, 3440x1440, Ultra, editor closed): 75.5 fps, worst p99
  26.79 ms, 1086 MB (76.3 / 26.97 / 1084 before) -- noise.

