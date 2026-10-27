## 117. Sandbox: teleport anywhere from the map; heals in the menu (2026-10-27)

The user, for the sandbox: place a pin on the map to teleport anywhere in the
maze, and give yourself heals.

- **Map teleport** (sandbox only, `Sandbox.active`): on the map -- the
  inventory's Map page (M) or the stand-alone full map -- **T** (keyboard,
  physical key) or **Y** (pad) teleports to the mark under the cursor if there
  is one (a quick pin, a noted mark: within `PIN_PICK`), else to the spot under
  the cursor. So "drop a pin, then T on it" works, and so does T anywhere.
  explore_map.gd `_sandbox_teleport` (called from `_map_input`): the cursor's
  world x, z (`_panel_to_world`); a spot in the rock (its cell not in
  `_built.cells`) goes to the nearest open cell's centre; the height is that
  level's `to_world(cell).y` (0 in the dungeon, `sewer.FLOOR_Y` in the sewer --
  whichever level the map shows is the level you land on). Then the screen
  shuts (the inventory's `set_open(false)` via `Coop.hud(player)
  ._inventory_screen` when embedded, else `set_full_map_open(false)`) and
  sandbox_world.gd `teleport_to_map(at, yaw)` lands it, keeping the player's
  facing.
- **Landing** (`teleport_to_map`): a ray from `MAP_RAY_UP` 1.6 m above the
  level's floor height down to `MAP_RAY_DOWN` 6 m below (under every corridor
  ceiling; short of the sewer 12 m down, so a dungeon spot never drops into
  it), then `NavigationServer3D.map_get_closest_point` on the world's nav map,
  taken only if within `MAP_NAV_REACH` 4 m sideways and 1 m up/down -- a spot
  on a pillar, a vat or a wall edge lands beside it. `teleport(at, yaw, snap)`
  got `snap` (default true, as before) so the found floor is not re-snapped.
  The sandbox world is found by the new group `&"sandbox_world"` (added in
  `build`).
- Hints: the map's own hint line and the inventory's Map footer show
  "T / Y Teleport" in the sandbox only; the sandbox menu's TELEPORT column says
  so above its list (the list's scroll 470 -> 430 px for it).
- **Heals** (sandbox menu, GIVE ITEMS): "Heal to full" (`player.heal(max_health)`)
  and "5 health potions" (`add_item(&"health_potion", 5)`, the normal
  consumable path), above the rats and crystals.
- Measured (throwaway harness, deleted; headless): 40/40 random open cells via
  a real T key event from the Map page landed within 0.25 m of the cell centre
  and stood on the dungeon floor 40 frames later; the screen shut and
  `ui_open` released each time; a spot in the rock went to the nearest open
  cell (6.7 cells away) on the floor; a quick pin 4 px off the cursor won
  (0.00 m off the pin); from the sewer, 10/10 sewer cells landed in the sewer,
  the map still on its sewer level; outside the sandbox T did nothing (the
  screen stayed open, nobody moved); Heal to full 25 -> 100; potions 3 -> 8.
  Windowed screenshots checked (map footer, landing, menu); a clean
  `--quit-after` sandbox run had no errors.
- **Trap hit**: the nearest-open-cell search first reassigned the cell it was
  measuring FROM inside its own loop (`cell = c`), so each closer find moved
  the origin and a rock spot landed 38 cells away. The rock test caught it;
  the search now measures from a fixed `from`.
