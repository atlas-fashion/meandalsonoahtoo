## 79. Local co-op split-screen (2026-10-18)

The user: "a local splitscreen mode using both keyboard and controller" --
asked, co-op (not versus), across the whole game at once (not the sandbox
first). Player 1 on keyboard and mouse, the LEFT half; player 2 on a
controller, the RIGHT half. Off, the game is exactly the one-player game
(a harness checked: one player, one HUD, no split, actions unsplit).

- **Starting it** (title_screen.gd): a Co-op button between Play and Sandbox
  opens a page (who uses what, whether a controller is connected) with Play
  together (the save slots, headed "CHOOSE A CO-OP SAVE") and Sandbox
  together; both wait for a controller. `-- --coop` on the command line, with
  `--skip-title` / `--sandbox` / `--bench`, starts straight in. Play and
  Sandbox call `Coop.stop()`; so does `Saves.exit_to_title`.
- **`Coop` autoload** (scripts/coop.gd): `active`, `players` (registered by
  player.gd in `_enter_tree`, by `player_index`), `player(i)`, `all()`,
  `nearest(pos, skip_hidden)`, `user_for(node, current)` (whoever uses an
  interactable: kept while in a scene with it or hidden in it, else the
  nearest), `owns(p, event)` / `device_player(event)` (keys and the real
  mouse are player 1's; joypad events, and the pad cursor's made-up mouse --
  device pad.gd SYNTH_DEVICE -- player 2's; an InputEventAction with device
  ACTION_DEVICE_P2 99 is player 2's, for tests), `act` / `held` /
  `just_pressed` / `vector` / `axis` (POLLED input: `start` copies every
  non-ui action A into "p1_A" with its keyboard / mouse events and "p2_A"
  with its joypad events; the originals stay whole for menus and for event
  code behind `owns`), `set_mouse(p, mode)` and `aim_ready(p)` (only player 1
  touches the mouse; player 2 needs no captured mouse to attack), `ui_root(p)`
  (their half), `camera(p)` (their own head camera, for aiming and
  `looked_at`), `view_camera(p)` (the camera DRAWING their half: its
  Environment, its frustum), `hud(p)`, `huds()`, `announce(p, ...)`,
  `announce_all(...)`.
- **The second player and HUD are in scenes/main.tscn always** (Player2 with
  `player_index = 1`, HUD2 with `player_index = 1`, and a SplitScreen node
  last). Outside co-op each takes itself away in `_enter_tree` (out of its
  group, processing off, freed) before anything can see it -- the maze builds
  in its own `_ready`, before the players', and finds them already in.
- **The split** (scripts/split_screen.gd): two SubViewports in containers
  side by side (a 3 px black divider), both on the root's World3D; the root
  stops drawing 3D (`disable_3d`). Each half has a Camera3D that takes its
  player's camera every frame (`_process` at priority 1000 and again on
  `frame_pre_draw`): transform, FOV, near / far, attributes -- or the robot
  rat's eyes while that player drives one (rat_control.gd `view_camera`, the
  rat's own SELF_LAYER left out). Each camera has its own COPY of the world's
  Environment (`use_view_environment`), so a dash or low health greys only
  that half, the Remnant's frost grade (hud.gd) and the sewer's haze
  (sewer.gd `_haze_env`, each half by its own camera's height; the sewer
  drawn while either camera is down there) likewise. Each player's HUD, and
  each player's explore map (maze.gd makes one a player; player 1's is the
  one saved), moves into its half; a half's 2D canvas is 1280 wide -- the
  width every HUD layout was made for -- and as tall as its shape asks
  (`size_2d_override`), so every screen fits, smaller. A half passes on the
  MOUSE only when it is its own player's (`HalfContainer._propagate_input_event`).
  Graphics settings reach both halves (graphics_settings.gd
  `apply_to_viewport`, `_apply_environment` takes the cameras' copies too).
- **Layers.** Each player's first-person pieces (everything under the head)
  go on VIEWMODEL (bits 16 / 17); each has a stand-in body for the other to
  see (scripts/coop_avatar.gd: a hooded, cloaked figure from primitives, rust
  red for player 1, steel blue for player 2, sword or spear and a lit torch,
  a name over the head, lying down when dead, gone while hiding) on AVATAR
  (bits 13 / 14). A half's camera draws its own viewmodel and the other's
  avatar only: the other's sword, pulled to the eye by `use_z_clip_scale`,
  would fill the wrong screen.
- **The players** (player.gd): `_unhandled_input` asks `Coop.owns` first;
  look, move, jump, block-held and dodge-held are polled through `Coop`;
  attacks need `Coop.aim_ready`; no slow motion in co-op (the clock is both
  players'). The players pass through each other (collision exceptions): in
  a one-cell corridor neither could get by, and two bodies on one spot were
  thrown 86 m apart.
- **Placing** (maze.gd `_place_player` / `_place_one` / `_partner_spot` /
  `_settle_partner`): player 2 a step beside player 1 (right, left, back,
  ahead, two diagonals, at 1 and 0.7 m, wherever there is floor and no
  stone) at the start, at an anchor, on the sandbox plane, after a teleport
  (sandbox_world.gd moves the party). At build time the physics space does
  not yet hold the level's floors, so player 2 is placed again two physics
  frames later.
- **Deaths** (maze.gd `_on_player_respawned`, bound per player): a fallen
  player rises at the anchor (or the start) and joins back in; the world
  resets -- the map snapshot, the population -- only when nobody was left
  standing. An attuned anchor is the party's (both spawn points).
- **Saving**: `save_state` adds "player2" and "coop": true; `restore_player`
  puts player 2 back beside player 1. A one-player save loaded in co-op
  starts player 2 fresh; a co-op save loaded alone ignores player 2. Saving
  waits until it is safe for both (save_system.gd `_safe`).
- **The world** -- every `get_first_node_in_group("player")` (46, in 27
  files) looked at:
  - Enemies (enemy.gd `_resolve_player`): the nearest player standing and
    not hidden, chosen again every TARGET_EVERY 0.5 s while chasing, kept
    unless the other is TARGET_STICK 1.3x nearer, never changed mid-swing.
    The crier (the nearest; a crier on a face stays on it; it hears every
    player's guard), the Remnant (one quarry at a time, picked each second
    while not on a trail; a half's HUD shows the hunt only when it is that
    player hunted; the torches' chill is the colder HUD's), arrows and goo
    (hit either player).
  - Interactables -- bone cage, chest, convoy, dungeon room, hiding spot,
    item drop, manhole, mimic, morgue, puzzle room, rat, anchor, shard door,
    wood door, workbench: their user is `Coop.user_for`; `Interact.looked_at`
    takes the player (`by`) and looks along their eyes; each `Prompt` carries
    the `player` it is up for, so only that HUD's crosshair turns
    (`Interact.focus(tree, player)`); `Interact.pressed(event, by)` takes E
    only from their device; scene cameras use theirs. `Interact.chooser`
    (the first player near and looking) is there for new objects. The
    workbench opens in its user's half and keeps that user while open.
  - Global words go to both HUDs (a boss / the mimic fallen, the Remnant
    banished, Autosaved, the fade out of a loaded game); a player's own
    (pickups, the bench, NO ROOM) to theirs.
  - Wall torches rank and cull by the nearer of the two cameras
    (torch.gd `_camera_points`): both halves stay lit.
  - Spawn distances (the stalker, convoys, decrepits, rats, the sewer's
    out-of-sight spots) still measure from player 1: both start together.
- **UI per player**: inventory_screen.gd, radial_menu.gd, explore_map.gd and
  rat_control.gd ask `Coop.owns` and poll through `Coop`; attack_icons.gd
  labels player 2's pad keys always. The pad cursor (pad.gd) is player 2's
  only in co-op: kept on the right half, starting in its middle, never
  touching the real pointer (player 1's); `Pad.for_player(p)` replaces
  `using_pad` where a screen asks whether its player is on a pad. The
  rat's-eye overlay goes to its player's half.
- **Trap -- "BUG, indexing did not unpair geometries from light"**, 266 of
  them a run, in co-op only: changing `layers` on a GeometryInstance3D that
  is already lit leaves it paired with its lights. The viewmodel sweep now
  hides an instance while its layers change; the avatar is built, layers and
  all, before it enters the tree. 0 since. (Not the root's `disable_3d`:
  bisected.)
- **Measured** (throwaway harness, deleted; headless): one player 9/9; co-op
  game 41/41; co-op sandbox 41/41 -- two players, two HUDs, the split up, the
  root not drawing, a view each on one world, HUDs and maps in their halves,
  1280-wide canvases, each camera on its player's eyes, an Environment each,
  player 2 1.0 m beside player 1, layers and masks, a stand-in each, torches
  ranked on two points; p1_ actions keys only, p2_ pad only; the pad walks
  player 2 and not player 1 and the keys the reverse; a pad button and a key
  owned right; player 2's attack swings only player 2's sword; player 2
  jumps alone; a skeleton by player 2 goes for player 2, turns on player 1
  when they come far nearer, and hurts player 2; the workbench's user is
  player 2, its prompt up for them alone, player 1's E does nothing, player
  2's opens it in their half; player 2 down -> player 1 standing, player 2
  up at the start, the world not reset; both down -> both up, the world
  reset; the save holds and restores player 2 beside player 1. Re-broken
  (`owns` always true; the HUDs left in the root) -> 5 failures, as they
  should. Windowed: both halves, the stand-ins and names, player 2's
  inventory in its half with the pad cursor.
- **Cost** (`--bench`, RTX 4070 at 1280x720 -- NOT the P620; player 1 tours
  the stations while player 2 stays at the start, so the halves see
  different places -- the worst case): 118.5 -> 81.5 fps overall; worst p99
  15.05 -> 19.05 ms; spawn corridor 7.28 -> 10.39 ms, chest room 12.17 ->
  15.60 ms; draw calls about doubled (1704 -> 3435 at the spawn corridor);
  video memory 647 -> 722 MB (a second shadow atlas). The pixels drawn are a
  full screen's either way -- the cost is per camera: culling, draw calls,
  shadow passes and the post passes run once for each half.
- **Not done**: the stand-in is a placeholder figure (its sword hides against
  the robe from in front); the decrepit / enforcer / lizard / damp camera
  uses (sparks and drips facing a camera) still use player 1's; spawn
  distances measure from player 1; no versus.
