## 58. Three decrepits, the sewer lizard, a proud grating, walkable manholes (2026-10-16)

- **Decrepits**: 250 health; up to `decrepit_max` 3 at once, each placed alone
  (maze.gd `_spawn_decrepit` -> `_sewer_spot`: >= `decrepit_spawn_clear` 30 m from
  the player, out of sight, >= `decrepit_apart` 40 m from every other); a killed
  one is replaced after `decrepit_respawn` 45 s (a queue, one at a time).
  Measured: 3, nearest two 67-69 m apart; one killed -> 2, then 3 again.
- **The sewer lizard** (`scripts/sewer_lizard.gd`, group "sewer_lizards",
  "SEWER LIZARD", 30 health): a PLACEHOLDER built from primitives and animated in
  code (spine and tail snaking, legs in diagonal pairs, head rearing and jaw
  dropping to spit, throat glowing), slick dark-green clearcoat skin with a faint
  radioactive mottle. `sewer_lizards_per_cell` 0.15 (25 here), out of sight,
  sewer only. Keeps 4.5-10 m off (scuttles back, sidles, comes on), and with a
  line within 16 m spits every `SPIT_EVERY` 1 s (`SPIT_WINDUP` 0.24 s): a gob of
  `scripts/goo.gd`, lobbed to land on where the player will be, 5 damage through
  the guard (a tenth blocked; the arrow's Proxy absorbs a parry's reflect),
  splashing green on stone. Trap (again, CLAUDE.md section 6): the default
  emission operator ADDS the emission texture to the emission colour -- a white
  colour rendered the whole lizard flat white; `EMISSION_OP_MULTIPLY`.
  Measured: 4 spits in ~5 s (one second apart, the first after the wind-up), 5
  each; guarded 0.5 each; crowded to 2.2 m it backed off to 4.85.
- **The grating clipped into the floor** because its top was flush with the
  walkway (coplanar faces fighting). It now stands `GRATING_LIFT` 0.012 m proud,
  rails resting on the channel's lips; collision raised with it. 0 vertices flush.
- **Open manholes are walkable**: the Blocker cylinder is never switched on (the
  dungeon's floor collision runs whole under the hole). Walked across one with
  the real W key, lowest y 0.00.
- maze `_report_room_intruders` skips anything below y -4 (sewer enemies sat
  under a chest room on the map grid and were counted as intruders).
- Sewer enemies hide their visuals while the camera is above ground. Bench (RTX
  3060, 3440x1440): 63.0 / 63.3 fps with them, 64.7 / 65.5 with no sewer enemies
  at all, worst p99 ~33-35 ms either way, 1202 MB -- ~0.5 ms above ground, not
  pinned down (they are dormant there).
