## 54. The sewer remade with Higgsfield (2026-10-15)

Supersedes section 50's pipe: the CSG tubes with their water strip, the inlets
and `tools/build_sewer_brick.py` (deleted). The layout (manhole cells, links,
spurs, 165 cells at `FLOOR_Y` -12), the ladders, the climb, the map level and
the light separation are unchanged.

- **The kit is generated** (`tools/build_sewer_kit.py` ->
  `models/sewer/sewer_kit.glb`; sources and job ids in `models/source/sewer_hf/`,
  see tools/README.md). Higgsfield `gpt_image_2_5` (high, 1.5 credits, the
  user's wall and vault photos as references, prompted dark and creepy in the
  dungeon's brick) made two concepts, five asset images and a brick texture;
  Tripo H3.1 via Higgsfield (9 credits each) made the models. 57 credits spent
  of the Plus trial's 110. The free plan cannot use `gpt_image_2_5`.
- **Straights are the Tripo tunnel**, 6 m, round brick vault (crown 3.70 m
  over the walkways), walkways each side of a 0.88 m channel, one MeshInstance
  per cell with a shared trimesh collision. Turned 90 deg for E-W cells
  (`_tunnel_basis`). Black water stands in the channel at `WATER_Y` -0.32
  (wading, `water_surface_at`; measured 0.57 m deep standing in it).
- **Junctions, bends, ends and manhole cells are round CSG chambers**
  (`CH_R` 3.0, wall 3.9 m, a dome rising 1.7 m) in the HF brick, world
  triplanar. Each open side has a MOUTH cut to the tunnel's measured profile
  (`TUNNEL_PROFILE`, from tunnel_profile.json) so the tunnel slots in; each
  shut side has an alcove holding the Tripo GATE (rusted, padlocked). 16
  chambers, 149 tunnel sections, 32 gates, 107 bone heaps / fungus clumps.
- **Trap: `map.to_world` already includes `FLOOR_Y`.** Adding it again put the
  mouth and alcove cutters 12 m below the chambers: no mouth was cut, and the
  tunnels ran into blank wall. Probed with rays from each chamber's centre:
  open sides now miss, shut sides hit the alcove at 3.55 m.
- **Trap: the tunnel rendered black beside a lit torch**: the build's
  `normals_make_consistent` had turned every inside face away (see
  tools/README.md). A dark render is not always a lighting problem -- check the
  winding first.
- **Kit materials**: metallic and its texture off, the packed roughness map
  dropped (Tripo's is glossy; a wet-plastic sheen under the torches), roughness
  0.85 (grate 0.6, metallic 0.55), albedo dimmed per piece (`KIT_TINT`, tunnel
  0.85).
- **Light**: a torch every second tunnel section (sides alternating) and one
  per chamber, 92 in all, `TORCH_REACH` 13 m with `TORCH_FALLOFF` 0.55 (the
  dungeon's physical 1.0 left the section between torches black, 9 m from the
  nearest). One torch per section cost ~1 ms more GPU (each lit torch redraws
  the kit for its shadows); reach 16 cost 1-2 ms more. Measured GPU time at
  3440x1440 on the RTX 3060 (vsync-capped, so GPU time is the honest figure):
  sewer 11.6-14.2 ms against 10.9 at the dungeon's spawn.
- Bench (RTX 3060, 3440x1440, editor closed): 66.6 fps, worst p99 31.02 ms,
  1180 MB (68.6 / 34.22 / 1157 with the old sewer) -- noise, +23 MB of kit
  textures. Not benchmarked on the P620.

