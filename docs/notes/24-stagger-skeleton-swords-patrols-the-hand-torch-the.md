## 24. Stagger, skeleton swords, patrols, the hand torch, the crystal mine (2026-10-10)

- **Stagger is a roll per hit** (`player.knock(body, impulse, stun, chance)`;
  stun floored at `stagger_min_time` 0.45). A stagger shoves the enemy and
  cancels its attack (`enemy._staggered`: wind-up / swing / recovery dropped,
  `_on_staggered` -- the archer loses its draw; the warden's beam already drops
  when stunned) and it lurches away from the blow (`_flinch`, a tween on
  `visual.rotation`). A blow that does NOT stagger hurts but neither moves nor
  interrupts. Chances: sword cut `slash_stagger_chance` 0.4, spin and slam 1.0;
  spear stab `STAB_STAGGER` 0.1, dash and the thrown spear's blast (its heavy)
  1.0. Poise-bearers (the boss) keep their hyper-armour. Measured: 120 real
  cuts -> 38%, 200 real stabs -> 7-11%; chance 1 mid-wind-up -> back to CHASE,
  no blow, winds up again; chance 0 -> the blow lands.
- **Spear stab effort**: walking at `spear_stab_move_scale` 0.45 while a stab
  is out (4.25 -> 1.91 m/s measured), and `_stab_effort` -- push 7 cm forward,
  dip, nod, shoulders rolling to alternate sides (`spear.stab_side`), FOV drawn
  in 2.6 deg (72.4 measured) and a strain tremor that builds while it is spammed
  (`_stab_strain`). Composed in `_update_head` / `_update_dash_view` (the FOV
  early-out includes `_stab_fov`).
- **Skeletons carry swords** (`scripts/skeleton_sword.gd`; enemy.gd `armed`,
  `weapon`), and the SWORD is what hurts: the blade swept from last tick to this
  one vs the player's capsule, once per attack (`_sword_connect`). The right arm
  is posed in code over the clip (two-bone reach + hand along the blade, blended
  by phase): cut = high on its side down across, charge = overhead chop, lunge =
  thrust, spin = arm out. A cut steps in (`_attack_step`, up to 4 m/s, to a
  0.45 m gap). Archers, wardens and prison prisoners are unarmed (old reach
  test); miners carry a PICK. Traps: posing must run only on ticks the rig was
  advanced (`_anim_stepped`) or the blend compounds; `_play_state_anim`'s
  `seek(0, true)` re-poses the whole rig from the new clip, so it re-runs the
  arm (one glitch frame per cut before); the sword is a CHILD of the body,
  re-placed only on rig steps (it followed the hand to 2 cm). Measured: stood in
  front 14/14 per blow, only during ATTACK; stepped back as it cut 0/4; behind
  it as the cut starts 0/3 (control, the old reach test: 3/3).
- **Scenes use the weapon in hand** (`player._scene_weapon`, `scene_reach()`,
  `spear_scene_pose()`): the cage stab and the bomber haft strike pose the spear
  instead of drawing the sword when the spear is held (driven through the skull
  tip 0.138 m past; the BUTT into the bomber). The spear's TIP_REACH 2.07 vs the
  sword's 2.08 keeps the cage stand-off. **Cage scene hands back control the
  frame the skull bursts**; the coins fly after and are paid on arrival.
- **Packs patrol** (`scripts/patrol.gd`, maze `patrols`): every corridor
  skeleton pack walks in a column -- leader on navmesh legs of 14-40 m between
  corridor points, followers on its trail, the warden at the back -- and fights
  as ever when it sees the player. Traps, all measured: a follower's goal on a
  short trail was the leader itself and the pack leant on each other and stood
  still (4 of 49 patrols) -> extrapolate behind the heading; a follower in front
  of its leader in a corridor jammed both -> members pass through each other
  while both march, solid again in a fight; routes through shut wooden doors
  (the navmesh runs through them; group "wood_doors") are refused. Result: 49 of
  49 leaders and 178 of 178 members moved > 12 m in 30 s, moving 94% of
  samples, 0 off the navmesh. `archer_share` 0.85 (+ `second_archer_share`
  0.45 in packs of 4+): 89% of 2+ packs measured.
  **Shipped with the freed-object trap** (section 4): killing a patrol's leader
  passed the freed body to `_alive(m: Node3D)` -- a script error every tick,
  seen in play, missed because no harness killed a patrolling enemy. `members`
  and `_leader` are untyped now and `_prune` drops the dead. Test: 43 members
  of 12 patrols killed leader-first while marching, then a death and respawn:
  0 errors; control with the typed parameter put back: 180.
- **Hand torch** (`scripts/hand_torch.gd`, under the camera): `torch.tscn`
  without its bracket, light or embers, at SCALE 0.1 / DEPTH 0.17 placed from
  the frustum each frame (`CORNER` -0.975, -0.86) -- the flame's tongues and the
  head at the far bottom-left, left of the HUD bars. On screen the flame is
  ~0.47 x SCALE / DEPTH of the view height (0.3 filled 83%). Traps: torch.gd
  turns embers back on with the effects knob, and paused they froze into one
  big glowing block -- free them before it enters the tree. No light: per-pixel
  cost over the whole screen, and it would change the corridors' look.
- **The crystal mine** (`dungeon_room.gd` kind "mine", maze `mine_rooms` 1, never
  the mimic's room): a faceted rock face (`_rock_mesh`, flat-shaded noise
  sphere, `rock` material; smooth-shaded it read as orange clay) with gold/red
  crystal seams, 3 electric drills (spinning bits, sparks with effects, brass
  cables to the generator), 4 miners at the face + 2 at an ore heap by a cart on
  rails (decor skeletons swinging picks on `attack_1/2`, ball and chain), 2
  wardens. The generator runs on the room's SHARD (its colour). Entering raises
  the alarm and every miner is let loose with its pick; with wardens AND miners
  down, E takes the shard (no chest here) and the drills spin down. Deaths:
  wardens back unless all destroyed; killed miners stay dead, the rest back at
  work. Saved: `miners_dead`. Measured 16/16 (harness trap: the room's block is
  15 m from its centre, so "4 m outside the court" is inside the alarm).
- Bench (RTX 3060, 3440x1440, editor closed): 102.5-103.1 fps, worst p99
  15.7 ms, 1386 MB; with `patrols` off 107.3 / 13.8 (earlier today, before this
  wave: ~118-121). The patrols cost ~4 fps, mostly physics at the chest-room
  station; the rest of the drop is CPU (cpu ms ~ frame ms) and was not pinned
  down -- the swords measured as nothing. Not benchmarked on the P620.
- **HUD: health under the hotbar, attack icons on the left** (hud.gd
  `_layout_health`, laid out in code so hud.tscn is untouched): the health bar
  is the hotbar's width (570) centred under it, numbers on the bar, the ghost
  bar under that; the hotbar is raised to `HOTBAR_BOTTOM` -62 (the held-item
  label and drink bar follow it). The orange slam bar is hidden. A ROW at the
  bottom, `GAP` 18 px left of the hotbar / health bar, its foot level with the
  health bar's (placed at the user's request after a left column, then a
  bottom-left column): `scripts/attack_icons.gd` (an HBoxContainer), three
  rounded tiles for the weapon in
  hand -- heavy (F), mid (Q), regular (LMB) -- with drawn glyphs and the
  hotbar's cooldown look (shade draining down, whole seconds on cooldowns of
  1 s+, a rim flash when one comes back). Data: `player.attack_cooldowns()` /
  `spear.attack_cooldowns()` as [kind, seconds left, of how long, key], -1 =
  unusable (the spear in flight). The sword's cut and spin have no cooldown of
  their own: their tiles show the stroke in progress (to `_bite_end` /
  SPIN_TURN) and the slam recovery. Measured: swapping to the sword and back,
  the throw counted 0.92 s down over 0.93 s; the slam kept counting while the
  spear was out; hidden with the potion in hand. Trap: a Label reparented with
  `set_anchors_preset` keeps its old offsets (sat left of centre) -- use
  `set_anchors_and_offsets_preset`. The hand torch's `CORNER` went to -1.15
  once the health bar no longer hid that corner.

