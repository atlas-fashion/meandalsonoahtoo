## 121. A damp, misty sewer; enemies more often and mostly alone; dark dirt in the floor's joints (2026-10-27)

The user:
- "Add hyper-realistic mist to the sewers. The sewers should feel very damp."
- "Make enemies spawn more frequently. They should commonly be found solo, and
  less frequently in groups of 2 or 3."
- "Add a dark dirt texture to the black spaces in the floor."

### The sewer's damp (`sewer.gd`, `shaders/sewer_mist.gdshader`, `shaders/sewer_stone.gdshader`)

Three layers. Everything to do with mist runs through `Graphics.volumetric_fog`
(note 112: off on Low and Potato, where the old exponential haze is all
there is).

**The air.** `_haze_env` (on while the camera is below, as before) now also
saves and switches the volumetric mist's settings, and `_unhaze` puts them
back:
- density AIR_DENSITY 0.028 (the dungeon's 0.022);
- albedo AIR_ALBEDO (0.74, 0.77, 0.74);
- anisotropy 0.35;
- ambient inject AIR_AMBIENT 0.16;
- length AIR_LENGTH 30 m, so the froxels are spent where a pipe can be seen.

The dungeon keeps ambient inject at 0 (note 112), because up there it glows
through the stone. Down here nothing outside can leak in, so the damp ambient
lights a faint veil everywhere.

**The ground mist.** `_build_mist` lays one FogVolume box per sewer cell (149):
- the whole cell, from 0.1 m under the water up to MIST_TOP 3.6;
- held in `_chunks`, so hidden while the camera is above;
- one shared material, the fog shader `sewer_mist.gdshader`.

The shader:
- density MIST_DENSITY 0.35 at the water, thinning by e every MIST_THIN 0.75 m
  above it;
- torn into wisps (smoothstep 0.32-0.78) by two octaves of a seamless 64^3
  NoiseTexture3D (simplex, 3 octaves);
- sampled in **world** space and drifting on two different winds, so it rolls
  slowly along the pipes;
- because it is sampled in world space, neighbouring boxes are one mist with no
  seams. Each box fades in only at its top and bottom.

On top of the wisps there is a thin floor of mist (`haze` 0.035).

**The moss lights the mist.** `_moss_light` sets `light_volumetric_fog_energy`
MOSS_MIST 1.6 and the meta `mist_lit`. `Graphics._apply_light` (note 112 zeroes
the mist energy of every unshadowed light) keeps it for a light with that meta.
This is safe:
- the moss is in the sewer's chunks, hidden whenever the camera is above;
- its 4.5 m range ends 7 m short of the dungeon floor.

**Drips.** `_build_drips`:
- one drip in DRIP_SHARE 0.55 of the straight cells (75 on the default seed);
- each at the crown (`PIPE_SPRING + sqrt(PIPE_HALF^2 - off^2)`, within 0.3 m of
  the axis), falling into the channel water;
- damp.gd's drop shader (`water_drip.gdshader`), its glint DRIP_GLINT
  (0.16, 0.42, 0.26), the moss's green;
- periods 1.4-3.8 s;
- emitting only within DRIP_RANGE 22 m and while the camera is below
  (`_tick_drips`).

The sewer joins the group "damp", so `Graphics.damp` reaches `set_enabled`. That
turns the drips and the walls' wet film off together.

**Wet walls** (`sewer_stone.gdshader`, uniform `damp`):
- a film down the damp streaks (less where thick mold drinks it);
- condensation under the crown;
- 22% darker there and wet (rough toward 0.2, specular toward 0.6), so the
  walls catch the moss's light.

**Tuning, from screenshots.** The first pass (air density 0.05, ambient inject
0.6, a green albedo, ground mist 0.9, moss mist 2.5) was a green soup. Two passes
brought it down to the values above:
- a pipe now shows wet, glinting walls, green halos round the moss, and the
  far end of the pipe lost in pale haze;
- the chambers stay the greenest, since their culvert lights light the mist
  round the grilles.

**Cost.** In the sewer, GPU time measured twice each way:

```
new mist   2.85 / 2.83 ms
old mist   2.68 / 2.72 ms
```

That is about 0.15 ms. The FogVolumes are cheap because the froxel grid's cost
does not depend on how many volumes there are.

### Spawning (`maze.gd`)

- **Group sizes.** `red_pack_min` / `red_pack_max` (an even 1-5) are replaced by
  `pack_size_weights` [0.66, 0.24, 0.10] for one, two and three
  (`_roll_pack_size`). The size counts everyone in the group.
- **Enforcers.** A group of two or three is led by an enforcer as one of its
  members with `pack_enforcer_share` 0.45. A lone skeleton never is.
  - `_spawn_pack` has a new parameter, `escort`: the corridor spawner passes
    it, and the chest-room packs keep the old default (true).
  - Before this, every skeleton pack brought an enforcer on top of its 1-5
    skeletons.
- **More of them.** `enemies_per_corridor_cell` 0.25 -> 0.32.
  - With smaller groups, the skeleton rolls that progression skips at the
    start (counted as placed, note 120) also count fewer bodies. So the criers
    roughly doubled, and every later population has more, smaller encounters.

Measured (seed 20260918, windowed harness, deleted):
- 20,000 rolls: 66% one, 25% two, 10% three.
- **At the start:** 108 criers (note 120 had 48-49). 150 corridor encounters,
  every one alone. (The block wardens and prisoners are as before.)
- **With all five types out** (`_populate` with every type released):
  - 218 skeletons (note 120: 135), 34 enforcers, 95 criers;
  - clustering the corridor enemies by position (within 3.5 m) gives 274
    encounters: 226 single, 39 of two, 8 of three, and 1 cluster of six (two
    groups placed side by side).

### The floor's joints (`brick_level.gd`, `shaders/floor_dirt.gdshader`)

The black was the **bed** under the flagstones (`_bed`, note 27), a flat
untextured brown 0.085. Painting it unshaded magenta in a shot proved the joints
show it.

It is now `BrickLevel.bed_material()`, shared with the beds round the manholes
(`manhole.gd`) and the surgery's hatch (`surgery_power.gd`), which had their own
copies of the flat colour.

The material is a ShaderMaterial on `floor_dirt.gdshader`:
- the sewer's Higgsfield **sludge** (`textures/sewer_sludge.png` + its normal
  map), recoloured from olive to earth by its own luminance:
  - `deep` (0.1, 0.075, 0.053) to `grit` (0.42, 0.315, 0.22) over
    luminance 0.02-0.3;
  - 18% of the source hue kept;
- projected from above in world space (`span` 0.85 m), so neighbouring cells
  run on as one ground;
- normal map at 1.4;
- damp: roughness 0.93 on the clods, 0.5 on the wet film between them;
  specular 0.35.

The Higgsfield connector available here can read only the catalog and history
(no generation tool), so no new image was made. The sludge was already a
photographic wet-earth texture in the project. The old organic level's
`ground_albedo.png` was considered and rejected for its cartoon green curls.

**The first pass was too dark.** `deep` 0.022 and `grit` 0.19 left most of the
sludge at about 0.04 albedo: black again.
- SSAO (intensity 2.5) crushes a 6 cm crevice. With SSAO off the same joints
  read clearly brown.
- SSAO is the user's setting, and a real crevice is dark, so the albedo was
  raised instead.
- Now a corridor at eye height shows the joints as dark brown earth lines; up
  close, the lit joints show the clods.

### Bench

RTX 3060, the default bench window, editor open and idle, at the start of a
game:

```
                    before            after
overall fps         135.8             134.7
worst p99 (ms)      16.67             12.60
```

The before run's worst p99 was one chest-room spike. Physics rose 0.4-0.6 ms
at the spawn corridor and the outer maze: the extra criers. That is noise
overall.

The all-released population (more skeletons than note 120's 135) was not
benched. A clean `--quit-after 900` windowed run had no errors or warnings.

### Traps

- **The torches are in no group.** A harness looking for them in "torches" found
  none and fell back to the player's start: the jail cell, where the camera
  ended up inside the walls. Find them by script (`torch.gd`).
- **A harness coroutine that errors never reaches `quit()`.** The game runs on
  until the timeout. Guard the lookups and quit on failure.
- **Dark albedo in a crevice reads black.** Judge a joint material with SSAO on,
  the way the game draws it.
