## 32. Anchors save progress; the workbench (2026-10-11)

- **Any anchor can be attuned again, the active one included** (respawn_anchor.gd):
  the active one's prompt reads "E   Save progress" and E re-snapshots the map
  through the same `maze._on_anchor_attuned` (announced "PROGRESS BOUND").
  The player always rises at the one attuned LAST.
- **Upgrades live on the player** (player.gd): `weapon_levels` (id -> level,
  default 1, `UPGRADABLE` sword and spear), `armor_level`, `UPGRADE_MAX` 10.
  `weapon_damage_scale(id)` = 1 + `UPGRADE_DAMAGE` 0.08 per level above 1 --
  applied to the cut / spin (`_stroke_damage`), the slam, and the spear's stab,
  dash and throw blast (`spear._scale()`). `damage_negation()` =
  `ARMOR_STEP` 0.04 per level above 1, applied in `take_damage` after guards
  and ghost, and in `beam_hit`. `upgrade_cost(level)` = round(3 x 1.5^(level-1))
  gold crystals: 3, 5, 7, 10, 15, 23, 34... `upgrade(what)` pays and returns
  false when it cannot. Saved as "weapon_levels" / "armor_level". The
  inventory's item card shows Level and the scaled damage.
- **The workbench** (`scripts/workbench.gd`, procedural -- no Tripo, by the
  user's choice): plank bench with iron straps and a shelf, an anvil on a stone
  block, a grinding wheel (spins up on each upgrade), hammer and tongs, a tray
  of glowing gold crystals; one collision box (1+2), built in
  `dungeon_room._build_mine` before the bake, front right of the court facing
  its middle, clear of the wardens' patch. E aimed at it opens a screen: one
  row per upgradable weapon CARRIED plus Armor -- level, effect now -> next,
  cost, Upgrade (disabled when short or mastered); pad works it by focus.
  `ui_open` and a freed mouse while up. The screen is a CanvasLayer added LAST
  under the root (inner class `Screen`), so it reads Escape / Tab / E before
  the pause menu and the inventory: Escape closes it WITHOUT pausing.
- Stone colour trap again: light grey stone blew out to flat pink under the
  court's red sky light, 0.13 went to black silhouettes; 0.24 with the plain
  stone normal map, triplanar, reads as stone.
- Measured in a harness (34/34): re-attune A -> 2 newly charted cells in the
  snapshot, kept through a death while 2 uncharted-since were forgotten
  (control); B then A -> rose at A; bench prompt when aimed, E opens, rows
  sword/spear/armor, nothing affordable with 0 crystals, Escape closes without
  pausing, costs 3/5/7/10, 20 crystals bought sword 2, 3, spear 2, armor 2, 3
  for exactly 3+5+3+3+5, armor 4 refused with 1 left; a 50 hit at armor 3 took
  46.00; a real sword cut at level 3 dealt 23.20 (20 x 1.16); spear scale 1.08;
  levels survive save_state / restore_state.

