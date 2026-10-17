## 47. The morgue rebuilt: an enclosed vaulted hall with Tripo burial walls and slabs (2026-10-15)

- **Solid walls, a roof, arches only at the doorways.** The morgue is no longer
  a cloister. `module_level._make_morgue_hall` (option "morgue", brick kit only)
  picks the room BEFORE the meshes -- the chest room furthest from the start,
  the spawn worked out early (`_pick_spawn` depends on nothing built) -- and
  turns its whole 5 x 5 block into `hall` cells (new `ModuleMaze.Cell.hall`):
  court off, classified from their openings (crosses inside, tees and corners
  round the ring). brick_level builds them as ordinary vaulted cells but puts
  NO arch between two hall cells and no junction pillars in them; the doorways
  keep their arch. maze `_pick_morgue` now just finds the room of kind
  "morgue". `place_torches` skips hall cells.
- **Piers** (`morgue._build_piers`): where four cross vaults meet, their
  corners leave a 2.2 m square open from 3 m up to the lid -- a square brick
  pier stands on every inside vertex (16) and a pilaster (proud of the burial
  walls by `PILASTER_PROUD`) on every one along the walls (16). Faces are kit
  "pier_face", cut from the wall piece (`build_pier_face`: the wall to 3.3 m
  plus two bands of its middle stacked to 7.9 m, 2.2 m wide, no stretching) round
  a dark core; one MultiMesh each. Collision on the walls' layers.
- **Tripo, from references found online** (Bing image search: crypt halls with
  groin vaults on squat piers and slabs in rows; Roman catacomb loculi; old
  mortuary slabs): "wall_loculi" -- the corridor wall photo edited
  (`tools/tripo_image.ps1`) into a catacomb burial wall, three rows of two
  niches each holding a linen-wrapped body, then image to model (45 credits;
  a first edit naming "dead body" was refused by Tripo, no charge) -- fitted to
  3.9 x 2.82 x 0.86 m, one between each pair of pilasters (12, 72 bodies); and
  "morgue_slab" -- text to model, a rough dark stone slab on two blocks with a
  linen-wrapped body (30 credits), 2.2 x 1.41 x 0.93 m, a pair in each inner bay
  either side of the middle aisle (12). Plus 8 old coffins in the corners, 14
  broken skeletons on the floor, the royal sarcophagus against the back wall
  (its Remnant scene unchanged), and a torch on every pilaster and every inside
  pier (32). Tripo balance 10.
- **The ring is a clear walk** along the burial walls. Slabs in the ring bays
  left gaps under a metre at their corners, which the navmesh (agent radius
  0.5) closes: a 1 m reachability map of the hall showed the whole interior cut
  off from both (corner) doorways and the path to the sarcophagus ending 7.87 m
  short. With the ring and the middle aisle clear: both doorways reach it
  (0.33 m), 0 props inside a pier, the Open prompt works.
- **Visibility range** (`_limit_view`): nothing in the hall had one, so its
  pieces were drawn through the rock from anywhere they were in front of the
  camera (+150-270 draw calls at every bench station). They now stop at 75 m
  (the MultiMeshes + the hall's half diagonal), like the level's chunks.
- Cost: in the hall 20.7-22.2 ms at 3440x1440 (the bench's chest room station is
  22.5-23.7). Bench (RTX 3060, editor closed): 70.1 fps, worst p99 28.01 ms,
  1117 MB -- and the previous commit, re-run in the same session for an A/B,
  70.6 / 27.85 / 1105. The drop from section 46's 74.4 is the machine on the
  day, not this change.
- `-- --modules` keeps the old cloister but gets the new dressing (no hall
  cells there): a fallback only.

