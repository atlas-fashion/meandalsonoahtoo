## 45. The prison's frieze, generator and energy beams; no chest in the cells (2026-10-14)

- **The band over the prison's arches is Tripo's frieze** (`prison_frieze`, text
  prompt): a moulded course, a corbel table and a cornice overhanging the court
  by 0.38 m. Raw it is 1.0 x 0.09 x 0.215 with both faces carved alike;
  `build_brick_kit.build_frieze` scales it UNIFORMLY to `FRIEZE_HEIGHT` 3.5 m
  (16 m long) and cuts a `FRIEZE_LEN` 6.7 m slice from the middle, so the
  corbels keep their proportions -- one slice per bay, overlapping the next as
  the brick band did; at the corners the two cornices cross like a mitre.
  `dungeon_room._build_dome_hall` falls back to the brick wall without it.
- **The generator is Tripo's** (`prison_generator`, text prompt): riveted iron
  drum, flywheel, glowing coil, brass pipes, an open cradle on top. 2.0 m
  square, 2.79 m tall (`GEN_WIDTH`). The crystal floats IN the cradle at
  `GEN_CRYSTAL_AT` 0.9 of its height (2.55 m); collision is its box capped at
  2 m. Its materials get specular, metallic 0.5, roughness 0.5 -- the kit's
  matte, no-specular stone setting made it a dull lump. The mine uses the same
  machine; its pistons and flywheel (primitives) only exist without the kit.
- **Yellow energy beams replace the floor cables**: one per cell from the
  crystal to the cell's red lock lamp (`_build_beams`; `cell["lock"]`), a shared
  open unit cylinder (radius 0.055, 24 rings) stretched per beam, drawn by
  `shaders/energy_beam.gdshader` (additive, unshaded; soft edges from facing,
  pulses running out to the lock, ends pinned and the middle shivering;
  instance uniforms `beam_length`, `power`, `seed`). Cutting the power makes
  them stutter out with the machine (`power` = `_power`^3 x a random flicker)
  and hides them at 0.
- **No chest in the cells**: there is no locker cell any more (five cells hold
  prisoners, the rest bones). The room's shard comes out with the crystal
  (`_cut_power`, when the room has no `_reward`), as in the mine. An older save
  with the power cut but the chest never opened is owed it: `restore_state`
  gives it deferred, after the player is restored, and marks the room looted.
- Tripo: 30 credits each, 150 left. New texture sets patched to
  `compress/mode=2`.
- Measured (harness, both prisons): 10 beams for 10 cells, each ending 0.000 m
  from its lock; no chest; no floor cables; frieze and machine in place; E on
  the crystal gave the red crystal AND the shard, room looted, beams all out
  4 s later, 10 of 10 gates open; the owed-shard load path gave the shard and
  saved as looted. Bench (RTX 3060, 3440x1440, Ultra, editor closed): 74.7 fps,
  worst p99 26.91 ms, 1102 MB (73.6 / 27.81 / 1090 before).
- **The cornice is remade in the walls' brick** (2026-10-14, at the user's
  request): the carved frieze's pale stone did not match the corridor walls. A
  Tripo retexture of it with the wall photo as a style image (20 credits, task
  a54d3774-...) came back pale brown stone -- not used. What worked is how the
  walls themselves were made: `tools/tripo_image.ps1` edited the wall photo
  (`brick_kit_refs/wall.webp`) into a long, low wall of the same dark charcoal
  bricks and brown mortar with brick corbels under an overhanging brick cornice
  (5 credits), then image to model (40 credits) ->
  `brick_kit_raw/prison_frieze_brick.glb`, which `build_frieze` prefers (it now
  finds the long axis and the side the cornice juts to itself). 6.7 m slice at
  3.5 m tall, cornice 0.56 m proud, 6,000 tris. 85 credits left. The old
  frieze's extracted textures are deleted. Bench: 74.6 fps, worst p99
  27.31 ms, 1102 MB (74.7 / 26.91 / 1102 before).

