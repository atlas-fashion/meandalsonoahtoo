## 82. Co-op: each player on the other's map; player 1's HUD no longer squashed (2026-10-19)

The user: "make it so that each player can see the other on the minimap. also
player one's ui is squished".

- **The other player on the map** (explore_map.gd, "The other player"): in
  co-op each player's map draws the other (`_partners`: every other
  `Coop.all()` player on the map's level -- the dungeon or the sewer, by
  LEVEL_SPLIT_Y as the map itself switches) as the map's own arrow shape
  (`_draw_arrow`) in their stand-in's colour brightened (PARTNER_COLOURS:
  player 1 orange (1.0, 0.52, 0.22), player 2 blue (0.38, 0.66, 1.0); the
  map's own arrow stays the one bright red), grey when fallen. On the
  minimap (`_draw_mini_marks`) it is turned with the heading-up map and points
  the way they face; beyond the minimap's reach a smaller arrow waits on the
  rim (PARTNER_RIM 11 px in) pointing toward them. On the full map
  (`_draw_full_marks`) at their place, north up, redrawn every frame while
  open in co-op. Outside co-op nothing changes (`_partners` is empty).
- **Player 1's squashed HUD** (split_screen.gd): `resized` set each half's 2D
  canvas (`size_2d_override`, 1280 wide by the half's shape) only at build and
  when the WINDOW resized -- but at build the containers had not been laid
  out, so the halves read the SubViewport's default 512 square and player 1's
  canvas stayed 1280 x 1280: squashed into its half, and with player 2 on
  another monitor (note 80) stretched across the whole game window (player
  2's window stretches its own canvas, so it was fine). Each SubViewport's
  own `size_changed` now calls `resized`, which writes the override only when
  it differs (writing it can raise `size_changed` again).
- **Measured** (throwaway harness, windowed, deleted): before -- player 1's
  canvas 1280 x 1280 in both modes (screenshot: text and minimap squashed
  flat); after -- split halves 1280 x 1445 and 1280 x 1442 for 638 x 720 and
  639 x 720 halves, two monitors 1280 x 720 for player 1's 1280 x 720 view,
  player 2's window 1280 x 720. Player 2 placed 8 m off: player 1's minimap
  and full map show the blue arrow, player 2's the orange one (screenshots
  checked). Clean boots, one player and `--coop`, no errors or warnings.
