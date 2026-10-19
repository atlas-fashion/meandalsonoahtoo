## 80. Co-op: what its frame time costs, the torch share, two monitors (2026-10-18)

The user, after note 79: "why is it costing framerate? ... it should be
basically 2 cameras in the same rendered space" -- then "try to cut co-op's
frame-time cost. Measure each change with --bench --coop and tell me what each
one costs in looks", and "make it so that i can choose to put them across
different monitors".

- **Why it costs.** It IS two cameras on one World3D (one copy of the level,
  of its meshes, lights and physics). What runs twice is per camera: culling,
  the draw calls, every shadow pass (the shadow-casting torches, the moon's
  cascades) and the post passes. The pixels are one screen's either way. On
  the RTX 4070 the doubled draw-call submission is what shows; per-pixel cuts
  do nothing there.
- **Experiments** (`--coop --bench`, RTX 4070 at 1280x720, overall average
  fps; the baseline measured 77.3 and 81.8 on two runs, so about +-3 is
  noise; each was a throwaway hook, deleted):

  | change | fps | looks |
  |---|---|---|
  | baseline | 77.3 / 81.8 | -- |
  | moon shadow 2 cascades | 81.7 | (noise -- not kept) |
  | moon shadow off | 81.2 | (noise) |
  | shadow atlas halved | 79.4 | (noise) |
  | mesh LOD threshold 2 | 81.2 | (noise) |
  | SSAO half / off | 81.6 / 81.5 | (noise) |
  | glow off | 81.2 | (noise) |
  | MSAA off | 80.5 | (noise) |
  | omni shadows dual paraboloid | 79.7 | (noise) |
  | camera far 75% | 80.6 | 200 fewer draws, no gain |
  | 12 lit torches (of the preset's) | 82.4 | (noise) |
  | **8 lit torches** | **88.4 / 87.5** | draws 3441 -> 2897; about 1 ms |

  Looks of 8 torches (screenshots at the spawn corridor and the boss room):
  close up, nothing; FARTHER torches stop lighting their walls -- their flame
  and embers still burn, but the warm pool round a far torch goes dark, so a
  long corridor reads darker at its far end.
- **Kept: `coop_torch_share`** (graphics_settings.gd; all five PRESETS 0.5;
  settings_panel.gd "Co-op lit torches", 25-100 %). torch.gd ranks
  `torch_lights * coop_torch_share` torches (at least 4) while `Coop.active`;
  off co-op it reads nothing. 1.0 is note 79's co-op exactly.
- **Measured with it**: `--coop --bench` 88.7 fps overall (from 81.5 in note
  79), spawn corridor 9.44 ms, boss room centre 12.66 ms, chest room 13.93
  ms, draws about 2900 at each station; one player `--bench` 120.2 fps, the
  same as before (119.3).
- **Two monitors** (coop.gd `two_screens`, `second_screen`; title_screen.gd
  a "Screen:" button on the Co-op page cycling split screen -> player 2 on
  each other monitor -> split screen, disabled "one monitor found" with one;
  `-- --coop --coop-monitors` picks the first monitor that is not the game
  window's). split_screen.gd `_second_window`: player 1's view fills the
  game's window (no divider); player 2's view is a real OS window
  (`root.gui_embed_subwindows = false` while it is up), borderless, covering
  that monitor, `unfocusable` (the keyboard and mouse stay with player 1),
  on the root's World3D, its canvas stretched from 1280 x 720 like the game
  window's, no 3D audio listener (player 1's half hears). Their HUD, panels
  (`Coop.ui_root`) and explore map go into it.
  - Input: Godot sends events that belong to no window -- joypad buttons
    and sticks, InputEventActions -- to EVERY window, so the unfocusable
    window gets player 2's controller with nothing done. Passing them in by
    hand (`push_input`) as well delivered each twice: the inventory opened
    and shut in one press. The pad cursor (pad.gd `use_viewport`) is drawn
    in that window, kept to it, starts at its centre, and its made-up mouse
    is `push_input` into it (`_deliver`) -- that mouse does belong to a
    window, and the window never has the focus to get it.
  - Cost: the same as the split (two cameras); player 2's window draws at
    its monitor's resolution, not half of one.
- **Verified** (throwaway harness, windowed, deleted): player 2's window is
  up, borderless, unfocusable, covering monitor 4 at (1920, 0) 1920x1080;
  player 1's view fills the game window; player 2's HUD, panels and camera
  there, on their eyes; an inventory action and a REAL controller button
  each open player 2's inventory once (not open-and-shut -- the harness
  failed with the hand-forwarding in); the pad cursor in their window.
  Screenshots of both windows checked. Clean boots (one player, co-op
  split, co-op monitors) with no errors or warnings.
- **Not done**: the screen choice is not saved between sessions; moving the
  game window to another monitor after starting does not move player 2's.
