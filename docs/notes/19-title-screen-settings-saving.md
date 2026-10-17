## 19. Title screen, settings, saving (2026-10-09)

- **The main scene is `scenes/title.tscn`** (`scripts/title_screen.gd`): Play (the
  four save slots), Settings, Quit. **`-- --bench` and `-- --skip-title` go
  straight into the level with no slot** (nothing is ever saved then), so the
  benchmark commands in section 1 still work unchanged. Harnesses that load
  `scenes/main.tscn` directly are also slotless. The title text is the project
  name (`application/config/name`).
- **`scripts/settings_panel.gd`** (class `SettingsPanel`) is the one settings page,
  shown by the title and the pause menu: CONTROLS (mouse sensitivity) and the
  graphics SPEC that used to live in pause_menu.gd. New graphics knobs go in its
  SPEC now. Sensitivity is `Graphics.mouse_sensitivity` (0.1-3.0, a multiplier
  on `player.mouse_sensitivity`, via `player._look_scale()`), saved in
  graphics.cfg under [controls], and in no preset: moving it never flips to Custom.
- **Pause menu**: Resume, Save game, Settings, Exit to title (saves first), Quit
  to desktop (saves first).
- **Saves autoload** (`scripts/save_system.gd`): 4 slots in user://saves
  (`store_var`, written to a .tmp and swapped in). Autosaves every 60 s of
  unpaused play and on `Saves.request(reason)`: anchor attuned, puzzle solved,
  shard won (chest opened / mimic killed), shards set in the door, boss killed,
  and once at the start of a new game so the slot shows. A save waits until it
  is safe: never in a cutscene, dead, hidden or waking (a shard in flight to the
  door is in neither the pack nor the door).
- **What is saved** (maze.gd `save_state`): the seed (the level is rebuilt from
  it), the player (`player.save_state`: position, yaw, pitch, health, every
  inventory slot, the slot in hand), the active anchor, the map and its
  checkpoint snapshot, kicked doors, looted cages, emptied coffins (by their
  order in the tree, which the seed fixes; unnamed nodes get run-dependent
  names, so paths cannot be used), each puzzle room's solved/looted, the shard
  door, and `boss_defeated`. **The boss now stays dead** once killed (he used
  to respawn on every death). Not saved: enemies (repopulated, as after a
  death), item drops lying on the floor, cooldowns.
- **Loading**: `restore_world` runs BEFORE `_populate` (so a dead boss is never
  spawned and a kicked door never arms), `restore_player` AFTER it (because
  `_populate` forgets the mimic, which a solved room puts back). A solved room
  is restored to its finished look (levers set / load on the scales / mirrors
  aligned / bells rung, plinth up, the chest open or the reward waiting).
- Harness trap: point `Saves.save_dir` somewhere else (and put back any setting
  you touch), or a test run writes into the player's own slots.
- Measured in a harness (31/31): title up; a slot started a new game and was
  written at once; autosave on the clock; a requested save held through a
  scene and written after it; Save game from the pause menu; Exit to title; the
  slot card's summary; loaded the same seed, the player 0.00 m from where they
  saved, same facing, health, coins and shard, the anchor, door 5 kicked (door 4
  still shut), cage 2 looted (cage 1 not), coffin 3 empty (coffin 2 not), the
  solved room with its plinth up, the door's sockets, the boss still dead, the
  map; sensitivity doubled the look and was written to graphics.cfg; delete.
- **Saving revised (2026-10-09, at the user's request)** -- supersedes the event
  saves above: the ONLY automatic save is the one every 60 s of play; the rest
  are by hand (pause menu Save game, or "Save and leave"). The `Saves.request`
  calls at anchors, puzzles, shards, the door and the boss are gone; the one
  `request` left writes a NEW game's slot once the player is up, so the named
  slot exists. Exit to title / Quit to desktop no longer save by themselves:
  they ask (Save and leave / Leave without saving / Cancel) and say how long ago
  the last save was (`Saves.since_saved`).
- **New games are named** on the title (LineEdit, `Saves.NAME_MAX` 24, trimmed,
  empty -> "Game N"); `Saves.game_name`, kept in the slot's meta.
- **A slot card shows only the game's name, the zone and when it was saved** --
  deliberately no shards, puzzles or play time (play time is still stored).
- **Zones**: maze.gd `zone` (this level is 1), `ZONE_NAMES` {1: "Zone 1"}
  (placeholder), `zones_cleared` (a zone's boss killed; saved), `zones_open()`
  (1 and every zone after a cleared one). Nothing reads `zones_open` yet: the
  zones after 1 are not built -- the user will start them when zone 1 is done.
- **A new game starts with the player getting up** off the cell floor
  (`player.wake_up()` = the respawn's wake), only when started from a slot; a
  loaded game and slotless runs (benchmark, harnesses, --skip-title) start
  standing. Harness trap: the first frames of a fresh level are slow, so the
  wake takes longer in real seconds than WAKE_END -- wait on `is_waking()`.
- Measured (20/20): an empty slot asks for a name; the game started with the
  player getting up, no control and nothing written meanwhile; the slot written
  once up with the trimmed name and "Zone 1" and no progress fields; no save at
  an anchor, a solved room, a shard or the boss; the boss's death cleared zone 1
  and opened zone 2; autosave on the clock; Exit to title asked and, left
  without saving, wrote nothing; a loaded game did not get up again and kept
  zone 1 cleared.
- **Into the game through black (2026-10-09)**: choosing a slot shows
  "DESCENDING..." for `LOADING_HOLD` 0.7 s, then the title fades to black over
  `LOADING_FADE` 1.0 s; the HUD's blackout starts at full black whenever there
  is a slot, so the level builds behind black. A new game's player gets up out
  of it (`wake_up` -> `_begin_wake(true)`), a loaded game fades in
  (`hud.fade_black_when_steady`). **Both wait for the frames to settle first**
  (3 frames in a row under 0.1 s, or 3 s): the level's first frame is a long
  stall, and it swallowed the whole 1.3 s fade -- black to clear in ONE frame,
  a cut. Measured: before, [1.0, 0.0] in one step; after, the get-up lifts at
  most 0.035 a frame over ~75 frames, a load 0.017 over ~59. The wake's own
  clock is also capped at 0.05 s a frame so a later stall cannot skip it.
- **Torch flame tips fade out** (2026-10-09, `shaders/torch_flame.gdshader`): the
  tongues used to reach the top of the 0.72 m flame card still bright and stop
  in a straight line there. Heat now burns out between `burnout` (0.58-0.78 of
  the card, moved by slow noise so the cut-off is never level) and 0.96, so the
  tip thins and cools through the ember reds to nothing. The flame reads ~10%
  shorter; the card (torch.tscn Mesh_flame) can be made taller if that is missed.

