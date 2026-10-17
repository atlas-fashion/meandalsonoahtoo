## 35. No torchlight through walls; carts are searched, then hidden in (2026-10-12)

- **Only shadowed torches give light** (`torch.gd` `_rank`, static, run every
  `RANK_PERIOD` 4 frames by whichever torch processes first): every torch hung
  by `_hang_torch` (meta "torch_shadow") is ranked by distance from the camera
  and only the nearest `Graphics.torch_lights` give light (Ultra 16, High 12,
  Medium 10, Low 8, Potato 6; settings "Lit torches", replacing section 33's
  shadow distance); every one of them casts. The rest keep flame and halo and
  give none (`light.visible = false`). A torch fades over `LIT_FADE` 4 m at the
  edge of the set (eased, `LIT_EASE`), and at most `SHADOW_SLOTS` 24 are ever lit
  -- the atlas is now 4 + 4 + 16 slots -- because a lit torch with no slot casts
  nothing and lights through the wall again. After a jump (respawn) the old set
  is still fading as the new one fades in: the furthest fading ones go out at
  once to stay within 24. Torches no longer have a Godot distance fade
  (`Graphics._apply_light`): it could switch a shadow off before its light.
  Potato has no shadows at all, so there torches DO light through walls.
- Measured (harness): walking 40 stretches of the level, at most 24 lit, every
  lit torch casting on every frame; 4 spots with a torch 3-10 m behind stone and
  none in sight, that torch boosted 20x: shadowed 0.009 / 0.007 / 0.014 (the
  base light), its shadow switched off 0.040 / 0.028 / 0.068 -- the control
  sees the leak. (A 4th spot read the same both ways: the torch was round the
  corner ahead, lighting the floor through the opening -- legitimate.) Bench
  (RTX 3060, 3440x1440, Ultra): 72.3 fps, worst p99 27.78 ms, chest room 41.6
  (79.4 / 22.81 when 8 cast and the rest leaked).
- **Hiding carts** (`hiding_spot.gd`) start SHUT. E "Search": walk up, the lid
  swings open, `_roll`: health potion 0.15, coins 0.19 (3-7), bone fragments
  0.19 (1-3), else nothing ("Empty" toast); the find rises out of the tray and
  flies to the player (`ItemDrop.give`: a drop spawned already taken; coins now
  have their own stack-of-coins drop visual). No room: the rest pops out onto
  the floor. The lid stays open; only a searched cart offers "Hide". Hidden, the
  lid rests at `LID_SLIT` -0.08 rad and the eye sits 4 cm under the rim in the
  middle of the tray: the slit along the front is the view out. Saved as
  "carts" (searched indices; the old "coffins" list named every cart and is
  ignored). Measured over 20,000 rolls: empty 0.47, coins 0.20, bones 0.19,
  potion 0.15, coins always 3-7.
- **The lid was see-through from inside**: the kit lid (a Tripo crate's top
  boards) is one-sided, so from below it was not drawn and a hidden player saw
  the corridor and the torches straight through it. `_both_sides` gives the lid
  two-sided copies of its materials.
- **Peeking is removed** (the slit replaces it): player `_update_peek`,
  `peek_amount`, the peek bar's exports, and the HUD's PeekBar are gone. The
  section 11 notes on peeking describe removed code.

