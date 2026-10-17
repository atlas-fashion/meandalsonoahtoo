## 29. Darker still, the Tripo torch everywhere, 5-piece doors, the domed prison (2026-10-10)

- **No torches at doors** (brick kit: `place_torches` skips `out.doors`).
  **Darker**: `module_torch_density` 0.4, `module_ambient` 0.12,
  `module_torch_energy` 1.7, court `SKY_LIGHT_ENERGY` 12 (was 22), `SKY_ENERGY`
  0.3. Torches 414 -> 208. Mean luminance at 12 corridor spots 0.0324 -> 0.0170
  (0.0657 two passes ago). Bench (RTX 3060, 3440x1440): 91.9 fps, worst p99
  18.75 ms, 1015 MB.
- **Every torch wears the Tripo torch** ("torch_mount", cut from the torch
  pillar by `cut_torch_mount` -- ring, handle and wrapped head, 1.44 m, ray-mapped:
  the pillar's face on that side is 0.31 m from its centre, not 0.45). torch.gd
  `kit_mount` (default true) hides Plate/Arm/Ring/Handle/Head and moves Flame,
  Halo, Embers and Light out to the kit torch's head. Off for the torch pillar
  (it has its own carved torch) and the boss hall's braziers. hand_torch.gd reads
  the moved flame position. Never put the old procedural body back.
- **Doors break into 5 uneven pieces**: `door_debris.pieces_for(mesh, cols,
  rows, slant, merge_top)` -- cut lines each tilted up to `slant`, the top row
  one piece; brick doors use 2 x 3, slant 0.55, merged top (wood_door
  `_split_for`, keyed on the leaf mesh's name "Boards"). Measured: 5 pieces.
- **The prison is a domed hall** (`dungeon_room._build_domed_prison`, brick kit
  only; the old block is `_build_block_prison`). The cells ARE the arcade: every
  arch round the court (one per non-corner ring cell, `_prison_bays`) is shut by
  a two-leaf Tripo jail gate ("jail_gate_l/_r", cut from the gate of Tripo's
  "prison cell" -- which came back as a little roofed hut -- and stretched to the
  brick arch's 3.36 x 4.55 m opening), and walls ("wall" + "wall_top") across
  every ring-to-ring arch split the arcade into cells; the doorway bays stay open.
  A brick band over the arches to `DOME_BASE` 8.35, a dark ring closing the
  corners, the Tripo dome ("prison_dome": came back on its side, stood up and
  normalised to radius 1 in `build_dome`) at `DOME_RADIUS` 8.5 with its oculus
  open; a red spot and a faint additive shaft fall through it onto the generator;
  four ember lights under the dome; a Tripo torch on every arch; four gibbet
  cages with skeletons on 14 m chains. The court's sky lights are removed
  (`_drop_sky_lights`). Cells carry "door" + "door2" and "open"/"open2"
  (relative swing); `_open_cells` / `_power_off_now` swing both. 11 cells per
  room here; 5 prisoners, 1 locker (the chest), the rest bones.
- Measured in a harness: 2 prison rooms, 11 cells each; cutting the power opened
  11 of 11 gates and let out 5 prisoners; a door kicked into 5 pieces.
- **Trap fixed**: `Graphics._apply_to_node` is called deferred and was TYPED, so
  any light or mesh freed before it ran (the prison removing the court's sky
  lights) errored "Cannot convert argument 1 from Object to Object". It is
  untyped now and skips freed nodes.
- Tripo: dome, cell bay (unused: a solid wall), cell (gate source) -- 120
  credits; ~360 left.
- **Lighting, second pass (2026-10-10, "way too dark... more torches, way less
  bright, increase the firelight effect")**: `module_torch_density` 1.1 (469
  torches), `module_torch_energy` 1.3, `module_ambient` 0.3, `TORCH_RANGE` 20 /
  `TORCH_ATTENUATION` 0.4 (wide soft overlapping pools). torch.gd firelight:
  `flicker_amount` 0.62, gutters more often and deeper, the light SWAYS with the
  flame (`sway` 7 cm, noise), its colour runs hot (HOT) as it flares and ember
  red (EMBER) as it gutters (`colour_swing` 0.35), halo 1.6x. Measured: mean
  luminance 0.0321 (2 of 12 spots near-black; 0.0147 with energy 0.85 and range
  15 -- doubling the count while halving energy left it DARKER). Cost: 79.9 fps,
  worst p99 23.64 ms (91.9 / 18.75 before); chest room 14.9 -> 19.8 ms. Lights
  are per-pixel: count and range are the levers if this must come back down.

