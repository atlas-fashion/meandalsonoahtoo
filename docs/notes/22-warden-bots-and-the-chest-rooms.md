## 22. Warden bots and the chest rooms (2026-10-09)

- **The puzzle rooms are no longer built.** `maze._build_puzzle_rooms` now builds
  `scripts/dungeon_room.gd` (group "chest_room"; maze.gd still keeps them in
  `_puzzles` and saves them under "puzzles"). `puzzle_room.gd` is left on disk,
  unused. Kinds: `prison_rooms` (2) PRISON BLOCKS, chosen by the seed and never
  the mimic's room; the rest `vacant` -- a dais with the chest (or the mimic) --
  until the user picks designs for them. Nothing seals any more: `sealed` is
  always false, `is_warding` never true (stalker.gd reads group "chest_room").
  The rooms' `on_world_reset` is now called from the END of `_populate` (after
  the corridor intruder count), so the first build gets it too.
- **The prison block**: two rows of four barred cells across the court (FRONT
  4.4 m from the centre, cells 2.5 x 2.7 x 2.9 m), a generator in the aisle on a
  red crystal (red omni, pistons, flywheel), brass conduits, a red lock lamp
  over every door, three warden bots posted in the aisle facing the cells
  (`POSTS`: x, z, row watched), guard-boxed to the room (`aggro_box_*`). Five
  cells hold a prisoner (the skeleton model playing idle, eyes attached), one
  is the LOCKER with the room's shard chest (`chest.locked` until the power is
  cut) and crates, the rest bones. Entering (1.8 m inside the block) alarms the
  wardens. All destroyed -> `wardens_down` -> E on the crystal: it flies to the
  player (`red_crystal` item), the generator gutters out, the doors swing OUT
  into the aisle (hinge +X along the door; a turn of a about Y takes +X to
  (cos a, 0, -sin a), so back row -1.75, front row +1.75 -- the first sign was
  wrong and the test proved it), door collision off, each decor prisoner is
  swapped for a real enemy (`maze.adopt_enemy`) that comes out alerted, and the
  chest unlocks. Bars are layer 1 only (they do not block sight); the doors'
  collision is armed on `level_built`, after the bake, so cells stay in the
  navmesh. Deaths: wardens come back unless all were destroyed; a cut
  generator stays cut; prisoners let out and not yet killed are back in their
  open cells. Save: kind, looted, wardens_down, powered_off, prisoners_down,
  freed_alive (cell indices).
- **Warden bots** (`scripts/warden.gd`, extends enemy.gd, group "wardens";
  display "WARDEN BOT" -- the boss is THE WARDEN, these are his machines). Put
  on an enemy.tscn instance like the archer; `_enter_tree` throws the skeleton
  away and builds a crude robot from primitives merged per rigid part (static
  mesh cache, one surface per material: hips, thighs, shins, torso barrel with a
  caged gold crystal, box head with a gold lens, a beam arm ending in a crystal,
  a club arm), animated in code (stride, bob, head, arm aim, club swing). The
  chest crystal is the first mesh, so enemy.gd's state material IS the crystal
  material; every crystal shares it. 240 health, 2.7 m/s, knockback resistance
  0.85, club 22, capsule r 0.55 h 2.25. Drops `gold_crystal` (0.6) or a potion.
- **The beam**: clear line through stone (2|256; its fellows do not block) and
  within 20 m -> CHARGE 0.65 s (thin aiming line, crystals flare) -> FIRE up to
  3.2 s, swinging after the player at 0.95 rad/s, the player tested as a capsule
  -> `player.beam_hit(5, delta, dir)`: 5 a second paid by the tick, no
  invulnerability window, slowed to `beam_slow` 0.45 (0.725 behind a raised
  guard, which takes `block_damage_taken` 0.1 of it; ghosts 0.2), spills a
  drink, damage marker every 0.5 s; HUD gold edge glow (`hud._update_beam_glow`,
  `player.beam_amount()`). VENT 1.6 s. Between beams it holds its ground inside
  12 m (it does not walk into melee; it clubs if you come to it). The drawn beam
  stops 0.8 m short of a player it is on and has no flare there, and the tubes
  taper with no caps: drawn to the chest it filled the bottom of the view as a
  gold wedge ending in a flat disc.
- **One with every skeleton pack** (`maze._spawn_pack` -> `_spawn_warden`,
  `wardens_with_packs`, aggro 22): beside its escort (the pack's first) on the
  side furthest from the rest; it does NOT collide with its pack
  (`add_collision_exception_with`) -- two sentries side by side walled it in
  7.6 m from its escort -- and steps aside to `PACK_ROOM` 1.2 m when awake.
  Idle it follows its escort along the navmesh when further than 3.6 m.
- Measured (35/35): 44-50 pack wardens, every corridor skeleton within 4 m of
  one at spawn, nearest pack-mate 0.78 m at spawn / >1.8 m awake; escorts moved
  ~8 m along their corridors, every warden back within 3.6-4.0 m in 8 s; beam
  first fires 0.73 s after spotting, exactly 5.00/s while firing, fires again
  after venting; walking under it 1.91 m/s (4.25 free); guarded 0.50/s; stone
  stops it; prison: 8 cells / 5 prisoners / 1 locker, doors solid after the
  bake, alarm wakes all three, no crystal until they fall, E takes it, 8 of 8
  doors out into the aisle (control with the sign flipped: 0 of 8), no door
  collision left, 5 prisoners out and 4+ walked clear in 4 s, chest unlocked;
  death after the power cut: 4 loose back, no wardens; death with wardens
  standing: all 3 back; a saved state restored into the other prison. Bench
  (RTX 3060, 3440x1440): 121.2 fps, worst p99 12.50 ms, 1381 MB (same-session
  before: 122.2 / 12.50).
- **Harness traps**: the Remnant kills in one blow whatever the health; over a
  long test it finds the player, the world resets and every enemy under test is
  freed ("previously freed" errors mid-test). Set `stalker_enabled = false`
  before adding the scene. And place a measuring spot relative to where the
  enemy IS -- a warden that had been hunting stood 2 m from a spot computed off
  its post, so it clubbed instead of beaming and the beam "never fired".

