## 11. The Shade and the hiding places (2026-10-08)

- **The Shade** (`scripts/stalker.gd`, built in code, spawned by
  `maze._spawn_stalker` in `_populate` so a death resets it >= `stalker_min_distance`
  50 m from the player; group "stalker"). The skeleton model at 1.75x (~3.3 m)
  with `shaders/ghost.gdshader` (unshaded, translucent, both sides drawn, fresnel
  rim, upward wisps, a ragged fade at the bottom; instance uniforms `base_y`,
  `anger`, `flash`) plus a fluttering open-cylinder shroud, a glow on the head
  bone and (with `Graphics.effects`) a cold distance-faded omni. Moves by hand
  along the navmesh with `collision_mask = 0` -- nothing stops it, doors
  included -- floating `hover` over the path's height; layers 1+3, so it blocks
  the player and is hit by the sword and slam.
  States WANDER/PAUSE (corridor tiles from `_spawn_candidates`, 12-45 m hops),
  HUNT, SEARCH, WINDUP/STRIKE/RECOVER. Sees 26 m in a 140 deg cone, 4.5 m all
  round, with line of sight on layer 2. Hunting it always knows where the player
  is and follows at `hunt_speed_ratio` 1.07 x their `move_speed` (measured
  4.55 vs 4.25 m/s) until they hide; then it goes to where it lost them, searches
  `search_time` 7 s after arriving and goes back to wandering. Struck or kicked
  (`alert`) it hunts. Strike: within 3 m, 0.8 s wind-up, 55 damage + throw,
  UNBLOCKABLE (`player.take_damage` skips the guard for an attacker with
  `unblockable`). No knockback. `max_health` 5000 x `damage_taken_scale` 0.2: a
  20-point cut does 4 -- meant to be killed LATER; those two are the knobs.
  `death_drops` / `death_coins` are a PLACEHOLDER reward (a skull, 150 coins).
- **Hiding places** (`scripts/hiding_spot.gd`, `maze._place_hiding_spots`, 18,
  farthest-point spread over the free side walls of corridor straights -- not
  niche walls, torch walls, door cells, the spawn or under the boss hall), built
  before the bake (layers 1+2, grid tiles WALL). A louvred wardrobe in the door
  wood (`HIDE_FROM_CENTRE` 1.40 from a straight's centre). E aimed at it: walk
  up, doors open, `player.hide_in()`; E again: `leave_hiding()` in front.
  Hidden (`player.is_hidden()`): body collision off, held still, hands empty,
  look clamped to +-0.95 rad yaw / +-0.6 pitch out of the doors, `take_damage`
  and `drain_health` ignored, unseen by the Shade, `enemy._can_see` and
  `Interact.looked_at` (so no other prompt fires from inside). The door leaves
  are hidden while occupied; the HUD's `HideSlats` overlay is the doors.
- **The warning** (`shaders/dread.gdshader`, `hud._update_dread`, NOT gated on
  effects -- it is gameplay): frost in a band at the screen's BORDER (a circle
  from the centre swallowed an ultrawide's sides first), thicker from 34 m to
  7 m, deeper toward the Shade's bearing, pulsing on a heartbeat (52 -> 150 bpm,
  +20 hunted); hunted, the very edge darkens and "IT HUNTS YOU" shows. Trap:
  `fract(sin(dot(...)))` hashing loses precision on the GPU and read as squares;
  it uses Dave Hoskins' arithmetic hash. All new canvas shaders are drawn once at
  load (`opacity` 0, meta "warming") so the first use does not compile.
- Measured in a harness (23/23): 18 placed, 0 stone hits in front of any back,
  narrowest passage left 2.85 m, all reachable; spawned 132 m off, wandered
  11-15 m in 8 s; saw the player down a corridor and hunted, dread up, label
  up; steady chase 4.55 m/s; E hid in 184 ms, it lost them, slats up, a 50 hit
  did nothing, it came within 1.0 m and gave up after ~9 s without finding
  them; E out 0.05 m from the front with collision back; its blow did 55
  through a held guard; a 20 cut did 4; dread off far away. NOT yet benchmarked
  (the wardrobes are ~9 draws each; the Shade one transparent skinned mesh).- **Hiding places are sarcophagi now** (2026-10-08; the louvred wardrobe is
  gone). `hiding_spot.gd`: a hollow stone coffin (2.3 x 1.05 x 0.95 m, arch
  stone at half the arches' texture scale -- at theirs it read as a woven
  check) lying along the wall at `HIDE_FROM_CENTRE` 1.22, with a carved lid
  that carries its own collision. States SEALED -> (E "Open": walk up, the lid
  grinds along the rim, one end open) GUARDED: a real skeleton from the maze's
  `enemy_scene`, adopted through `maze.adopt_enemy` (so a reset frees it), rises
  out of the open end and climbs over the rim with its physics held off and its
  rig stepped by the coffin, then is let loose and alerted -> killed: EMPTY for
  good, toast, and `explore_map.mark_hiding_place` -> (E "Hide") OCCUPIED: the
  player lies inside, eye just over the front rim, the lid drawn back over and
  propped `LID_GAP` 0.13 m -- the real gap IS the view out (the HUD overlay is
  only a vignette now, `slat_amount` 0). If the guard is freed without dying
  (the player died and the world reset), the coffin reseals and is guarded
  again. Map: pale bar along the wall, `COL_HIDE`, drawn only where charted,
  kept apart from the charted cells so a death does not forget it; legend
  "hiding place". Measured (22/22): 18 placed, 0 stone in front of a back,
  narrowest passage 2.52 m, all reachable; Open raised the skeleton in 717 ms
  and it stood 0.65 m from the front and hunted; no Hide prompt while it stood;
  killing it emptied the coffin and the map pixel read COL_HIDE; hidden, a ray
  out of the gap was clear, the lid 0.10 m over the eye, the rim below it; the
  Shade did not find them; out again; a reset resealed a guarded coffin and left
  the emptied one empty.- **Peeking** (2026-10-08): hidden in a sarcophagus the player now lies with the
  lid SHUT and eyes below the rim (`EYE_LOW` HEIGHT - 0.13) -- nothing to see but
  the inside of the coffin. Holding "jump" (Space) peeks: `player._update_peek`
  (run at the top of `_physics_process`, before the hidden early-out) eases
  `peek_amount()` 0 -> 1 over `peek_ease_time` 0.2 s, and the coffin
  (`_follow_peek`) lifts the lid to `_lid_propped()` and the body to `EYE_HIGH`
  with it. The peek bar works like the ghost bar: drains over `peek_duration`
  3 s, refills over `peek_refill` 4 s whenever not peeking (out of hiding too,
  and while held-and-locked), and run dry the key must be let go
  (`_peek_locked`). HUD: `PeekBar`, centred under the crosshair, ghost-bar
  colours, shown only while hidden.
- **Hiding makes enemies give up** (`enemy.gd`, so skeletons and the boss --
  NOT bombers, the orange flyers, which never ask; the mimic only fights in its
  sealed room, which has no hiding places). A guard goes home; anything else that
  was engaged walks away (`_begin_retreat` / `_run_retreat`): to its home or its
  furthest wander spot if 9 m clear, else to a navmesh point 11-20 m off found
  with `map_get_closest_point`, tried in the direction it already stands from
  the player first (a sentry adopts it as its new post), along the navmesh at
  `retreat_speed_scale` 0.5. `map_get_random_point` over the whole map almost
  never landed in that ring: the first version walked "away" to a home 4 m off.
  Seeing the player again calls it off. Bombers still blow up on the coffin;
  a hidden player takes no damage from it.
- Measured (17/17): shut, a forward ray hits stone; Space -> peek 1.0 in 0.4 s,
  the view out clear; bar 0.61 after ~1 s, dry and locked at ~3 s, +0.25 in 1 s
  after release, peeks again; bar hidden out of hiding. A skeleton engaged,
  still engaged with the player in the open (control), gave up once hidden and
  walked 4.6 -> 9.1 m (another run 2.4 -> 11.6) from the coffin; a bomber
  arriving after hiding flew in and blew itself up; the hidden player unhurt.
  Harness trap (again): a freed bomber compares equal to null, so an
  `if bomber != null` check silently skipped the bomber test.
