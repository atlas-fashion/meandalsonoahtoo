## 31. Prison ceiling and gates remade by Tripo, doors, respawn inventory (2026-10-11)

- **The prison's first dome was lopsided** (its collar half a radius off its
  base, the upper shell one-sided -- Tripo built a partial piece) and open at
  the top, its corners closed by a flat ring in `stone_plain_albedo`, which is
  so dark it renders black on plain meshes. Replaced by a second Tripo dome
  ("prison_dome2": symmetrical, closed, ribbed -- but an EXTERIOR on a solid
  base disc). `build_brick_kit.build_dome_inside` cuts the disc away and
  reverses every face so the brick and ribs line the inside; exported as
  "prison_dome" (radius 1, base z 0). The hall sizes it to the room's CORNERS
  (`inner * sqrt 2 + 0.3`, squashed `DOME_RISE` 0.62): it springs from just
  outside the band, so every view up meets wall or dome. The ring, the
  oculus beam and shaft, and the gibbets are gone; ember lights moved up.
  Band segments overlap (`cell_size + 0.7`) -- end to end they left slots.
- **Cell gates are a second Tripo pass** ("jail_gate": a flat pointed-arch
  gate full of bars, cross bands, lock plate), fitted to the brick arch's
  probed opening (3.32 m to 3.3 m, apex 4.8) at 3.28 x 4.74 x 0.2 and split
  into two leaves on their hinges (`GATE_HALF` 1.64). The first pass (cut from
  Tripo's "prison cell" hut) was sparse and broken.
- A third generation, "prison_vault" (a square rib vault), came back as a
  cross of iron rods -- unused. Tripo balance 350.
- **Doors**: 7 uneven pieces (3 x 3, merged top, slant 0.5); thrown at
  `LAUNCH_MIN..MAX` 10-15 m/s away from the player (was 4-7.5), up 1.2-3.4.
  Measured: each piece's furthest reach from the door 5.7-12.3 m (the old
  launch: under 1 m by the same moment). The brick door's stone frame was
  hollow inside once its leaf was cut out of it, so `wood_door._drop_frame`
  hides it and disables its jambs when the door breaks (and on load),
  leaving the corridor's own complete arch.
- **Respawn keeps the inventory as it was at death** -- `_respawn` no longer
  calls `_reset_inventory` (which topped potions back up); it only runs for a
  new game. Measured: 1 potion and 4 bone fragments at death -> identical slots
  after the respawn.

