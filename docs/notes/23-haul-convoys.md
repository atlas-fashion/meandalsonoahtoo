## 23. Haul convoys (2026-10-09)

- **`scripts/convoy.gd`**, spawned by `maze._spawn_convoys` on every repopulate
  (in `_spawned`, so a death sends fresh ones out): a wheelbarrow cart of gold
  coins and red and gold crystals moved round the corridors by three skeletons
  -- one PUSHES at the handles, one PULLS a rope in front, one STEADIES the load
  at the side -- with a warden bot walking behind. Lore: refinery to
  consolidator; neither exists yet.
- **The road never nears a dead end** (`network`): the corridor graph without
  rooms, courts or shut doors (`Built.doors` edges), every cell with fewer than
  two ways on peeled off until none is left (the 2-core), then only the LARGEST
  connected piece kept -- rooms and doors split the loops, and a convoy started
  on a 6-cell loop had nowhere to go. 79-168 loop cells per seed of ~900
  corridor cells. `convoy_count` 4 but one per `convoy_loop_cells` 40 of loop.
  Legs are BFS paths of 8-26 cells (3+ if hemmed in), never back the way it
  came, joined on 14 m before the road ends (Chaikin-smoothed cell centres,
  arc-length lookups, cell lengths cached per smoothing -- searched per cell
  per tick they cost ~1 ms a frame). It may stand 2-4 s at a leg's end.
- **Convoys never meet**: each CLAIMS its road from behind its warden to the
  road's end (`claimed`); legs are planned off other convoys' claims, and with
  none clear the convoy waits at the end of its road and retries every 0.5 s
  (taking a claimed leg anyway sent two head on). A cart or warden on its road
  just ahead holds it (guard, 5 Hz). Starts >= `convoy_start_clear` 45 m from
  the player and each other, on unclaimed road, or not at all.
- **The crew are real skeletons with `enemy.hauled_by`**: enemy.gd skips its AI
  and physics for them (`_haul_anim`: walk/idle at `haul_speed`, then
  `convoy.pose_hauler` points the arms). The cart is steered like a barrow:
  axis from the pusher's road point to the wheel's (placed by its centre, the
  handles swung 0.5-0.8 m off the pusher's hands on bends; now 0.15 m). The
  steadier keeps to whichever side is clear (`_slot_clear`: road rays 4.5 m
  ahead and body-radius rays at its spot now and 3.2 m on), crossing IN FRONT
  of the wheel, or drops in line behind the pusher -- coffins stand 0.7 m into a
  corridor and it walked through them. Its checks run only within 40 m of the
  player. The cart is an AnimatableBody (layer 1; crew and warden excepted).
- **The warden** escorts a marker 4.6 m behind the cart. Asleep (enemy
  dormancy) it is carried on the marker -- otherwise 55 m behind in a minute;
  awake it stops colliding with any enemy it bumps (a sentry pack held it 14 m
  back) and is put back on its mark if > 8 m off and out of the player's sight.
- **Set upon** (`_set_upon`, 5 Hz): a crewman hurt, alerted (a kicked door) or
  gone, the warden engaged, the player within 4 m of any of them, or seen within
  16 m in the puller's 140-degree cone with a clear line -> `_let_go`: the crew
  are released (`hauled_by` null, home where they stand) and alerted, the
  warden too; the cart stays. E on it (`Interact.looked_at`) takes 20-40 coins,
  1-2 red and 1-3 gold crystals; the load disappears. `broke_because` says why.
- **Cost**: the cart is five meshes shared by every cart (body, wheel, coins
  MultiMesh, red and gold crystals; ~28 pieces was ~30 draws a cart) with a
  50 m visibility range, and a convoy > 60 m from the player moves at 10 Hz.
  A/B/A (RTX 3060, 3440x1440, editor closed): 118.2 / 116.7 fps with, 119.7
  without; worst p99 13.50 / 11.80 vs 12.08 (noise).
- Measured over six seeds: every convoy moved 50-61 m a minute, 0 of 480 cart
  samples off the loops, no dead-end cell on any route, crew clear of stone
  with the player near, carts never closer than 7 m (once the claims were in;
  before: 0.4 m), pusher's hands 0.15 m from the grips, warden within 8.2 m;
  seen from in front -> dropped in 0.02-0.2 s, a player 14 m behind unnoticed,
  a crewman hit -> dropped, all three crew and the warden then hunting; looted;
  a death -> a fresh set out. Harness traps: a blow lands inside the player's
  invulnerability window when other enemies are hitting them -- kill with
  `kill_in_scene`; and the steadier's checks are skipped far from the player, so
  test them with a stand-in "player" near (30 m above) each cart.


