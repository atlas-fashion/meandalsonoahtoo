## 16. The Remnant (2026-10-08)

- **The big ghost is "the Remnant"** (was the Shade): `display_name` "THE
  REMNANT", node "Remnant", comments renamed. Still `scripts/stalker.gd` and
  group "stalker" in code.
- **No overlay warning any more.** The frost/heartbeat rect and "IT HUNTS YOU"
  label are gone from the HUD (`shaders/dread.gdshader` is now unused). Instead
  (`hud._update_dread`, gameplay info, not gated on effects):
  - **Torches go ice blue when it is very close**: `torch.gd` static `chill`
    (0 fire, 1 ice) = 1 - smoothstep(`CHILL_NEAR` 6, `CHILL_FAR` 18 m), eased
    over ~1 s. Every torch IN RANGE (they already skip work out of range)
    lerps its light from its own colour (`_fire_colour`, read once) to
    `ICE_LIGHT`, and the flame shader mixes an `_ice` ramp by the `chill`
    instance uniform (flame and halo). Only touched when chill changes.
  - **While it HUNTS: an icy grade** -- a 1D colour-correction LUT
    (GradientTexture1D) on the scene's environment, red held down and blue
    lifted (mid grey -> 0.34/0.47/0.60, shadows lifted blue), blended by the
    eased hunt amount (`HUNT_IN` 1.5 s, `HUNT_OUT` 3 s) and set to null at 0.
    The first curve (mid grey -> 0.25/0.42/0.60) took this red-lit level
    nearly to black. Measured mean luminance: normal 10.8, hunted 13.3 (blue
    21.3 vs red 13.9), torches chilled 16.5.
  - **And the camera** (`player.set_remnant_hunt`): a fine noise tremble
    (`remnant_shake` 5 mm, `remnant_shake_roll` 0.45 deg) and the FOV drawn in
    `remnant_fov_in` 2.5 deg, breathing +-0.8 over 5 s. Measured: FOV
    -3.30..-1.70 deg, frame-to-frame head motion 10.7x calm.
- **Trap fixed in passing**: `_update_dash_view` returned early (resetting the
  FOV) unless a dash/swing/jump/zoom/lunge was active, so a FOV term added
  only in its composition line never showed. The spin's FOV effort was exposed
  to the same gap; both are now in the early-out test.
- **One blow kills** (`stalker.one_shot` true): the strike deals
  max(`strike_damage`, 10x the player's max health), so even ghost mode's 0.2
  dies. Turn it off when the player has upgrades to face it.
- Measured (12/12): far -> 9 torches fire, no grade, FOV exact; 4.5 m (not
  hunting) -> 9 of 9 torches blue, still no grade; hunting -> grade, FOV,
  tremble; gone -> every torch back to exactly its own colour, grade null, FOV
  75.000; one blow killed at full health, and in ghost mode.
- **Torches cool earlier** (2026-10-08): `CHILL_FAR` 18 -> 32 m, `CHILL_NEAR`
  6 -> 10 m, so the blue is a warning in time to act. Measured chill: 40 m 0.00,
  30 m 0.02, 24 m 0.30, 18 m 0.70, 12 m 0.98, 9 m 1.00.
- **Item drops never fall through or into anything** (2026-10-08,
  `item_drop.gd`). Measured first with a stress harness: ~560 drops released at
  random REACHABLE navmesh points (body height; the navmesh also covers the tops
  of the wall boxes -- islands nobody reaches -- so unfiltered random points are
  bogus), one in four also from 0.35 m inside the nearest wall, 4 over every
  coffin and anchor, the throne seat and the jail cell, and one onto every
  coffin lid, which is then slid open. Judged: never settled; under a floor
  (straight up is a surface's underside); floating (nothing under it); inside
  (point overlap with a static shape -- a ray from inside a box never sees the
  box -- or back faces in 2+ directions). Before: 26 of 687 bad -- 21 left
  floating where coffin lids had been, 5 inside the boss hall's wall or the
  throne (layer 9 only, which drops ignored). Fixes:
  - lands on `LAND_MASK` 1|2|256 (layer-1-only props like the jail bed, the
    layer-9 throne), passing through characters and loose bodies
    (`_world_ray` re-casts excluding them); back faces ignored -- landing on
    one meant resting on a ledge INSIDE a wall's shell;
  - re-checks its support every `SUPPORT_CHECK` 0.25 s while resting, falls
    again if it has gone;
  - released inside solid (`_is_buried`), it steps out toward the player (who
    is always in the open) on its FIRST FRAME -- `spawn` adds it to the tree
    before setting its position, so `_ready` sees the origin;
  - if it comes to rest buried anyway (a lid sliding round it), out and down
    again, up to 3 times;
  - last resort: `LOST_DROP` 4 m below where it was dropped, or falling
    `LOST_TIME` 4 s, it is put on the ground under its drop point.
  After: 0 of 2,061 over three runs.
- **The Remnant hunts faster**: `hunt_speed_ratio` 1.07 -> 1.35. Measured 5.74
  m/s against a 4.25 walk: walking away loses ~1.5 m/s, a full ghost burst
  (2.5x for 4 s, 5 s refill) still opens ~20 m, so escaping means using ghost.

