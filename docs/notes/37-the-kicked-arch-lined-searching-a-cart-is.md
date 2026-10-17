## 37. The kicked arch lined; searching a cart is a scene (2026-10-12)

- **The brick door frame is a shell** (measured with rays against its mesh):
  its opening has a reveal only on a lip at the front (z -0.05 to -0.3) and one
  at the back (-0.95 to -1.1); between them, where the Tripo door sat, a slot
  runs back to walls 1.75 m out and a ceiling at 4.96 m. With the door kicked
  out that was a hollow you saw into and, at angles, through. No Tripo needed:
  `module_level._door_reveal_mesh` extrudes the opening's measured outline
  (`DOOR_REVEAL`, half-width by height, pointed head to 4.32) across the slot
  (`DOOR_REVEAL_Z`, lapping each lip), as "GateFrame/Reveal", hidden until the
  door breaks (`wood_door._show_reveal`, on the kick and on load). Re-measured
  with the lining: 0.96 m at the jambs and 4.32 at the apex all the way through.
  Traps: wound the wrong way the lining showed its back face and rendered black
  even double-sided (the normal pointed out); and the arch material
  (stone_plain) read as flat plaster beside the frame's blocks -- it uses
  stone_grey (grey blocks, dark mortar), triplanar in the frame's own space.
- **Searching a cart** (`hiding_spot._search`, ~2.7 s once at the cart, was
  ~1.4): letterbox, weapon put away (`hands_busy`), step up to `SEARCH_STAND`
  0.55 m, crouch and reach -- two forearms with hands (primitives, placed each
  frame from shoulder points under the eye to the lid's front edge, hands
  levelled into the cart so the fingers hook under the edge) -- the lid sticks
  (lifts 0.11 rad, drops back, the arms tremble), gives with a jolt (`_shake`),
  and is heaved over (0.8 s) while the view rises and leans in over the rim
  (`player.scene_lean`, new: an eased head offset for scenes, cleared by
  `end_cutscene` and the respawn) and looks down into the tray; the hands let
  go once the lid is past upright. The find lies in the tray for the peek
  (`ItemDrop.give(..., wait)`) and flies to the player as control returns.
  Measured: the Tripo cart's tray floor is at 0.78 m (`KIT_TRAY_FLOOR`; the old
  `TRAY_FLOOR` 0.52 put the find under the boards). Death mid-scene: no hands,
  no letterbox, no lean left, weapon back, the cart left unsearched.
- **The drawn hands were removed** (2026-10-12, at the user's request): no
  forearms or hands in the cart search; the reach is a plain 0.4 s beat of the
  view leaning in. Everything else in the scene is unchanged (measured 2.6 s,
  finds delivered, no extra meshes on the cart).

