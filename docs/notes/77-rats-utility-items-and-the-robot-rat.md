## 77. Rats: utility items, live rats thrown, the robot rat (2026-10-18)

The user: a new category of item, UTILITY ("bombs, and usables that aren't
consumable"); a harmless, very fast rat that scurries about and can be grabbed
with E if you are quick, spawnable in the sandbox, carried as a live rat on the
quick wheel and thrown to scare enemies (landed, it scurries out of sight); live
rats made into ROBOT rats at the workbench with crystals, the enforcer's eye
colour, on the weapon wheel: attacking sets it down and the view goes to its
eyes; it detonates for 100 on command, or by itself after 10 s, with a cooldown.
(Amended the same day, below: no cooldown after all, and the blast hurts the
player too.)

- **Utility** (inventory.gd): kind "Utility"; each utility item names its wheel
  (`"wheel": "quick"` / `"weapon"`). `wheel_of(id)` now decides `slot_accepts`,
  `_home_order` and `quick_move` (weapons -> weapon wheel, consumables -> quick,
  else the item's "wheel", else the bag). `is_weapon` is still "Weapon" only, so
  a robot rat in hand cannot block. Items: `live_rat` (stack 5, quick),
  `robot_rat` (stack 3, weapon). inventory_screen.gd: a sixth category tab,
  Utility (tabs 44 wide, was 54, to fit over the bag), and stat cards for both.
  item_icon.gd `_rat` draws both (side on; the robot grey with cyan eye,
  crystal, antenna).
- **The rat** (`scripts/rat.gd`, procedural look `scripts/rat_model.gd` -- no
  Tripo). WILD: sits PAUSE 0.5-2.6 s, darts DART 2.5-9 m at RUN_SPEED 7 m/s
  (player walks 4.25) in a STRAIGHT line probed by a ray (`_reach`), stopping
  short of stone. Notices the player within NOTICE_MOVING 4 m (NOTICE_STILL 1.8
  m while they stand still), FREEZES for REACT 0.5 s -- the grab window -- then
  bolts BOLT 7-13 m at 9.5 m/s along the clearest of 7 headings away. Grab:
  the shared Interact prompt "E   Grab" when aimed within GRAB_REACH 3 m of
  the eye (margin 0.12, it is small); E -> `player.add_item(&"live_rat")`
  (full: "NO ROOM", it bolts). Never hurts anything. Asleep beyond SLEEP_RANGE
  25 m x `Graphics.npc_detail`; not drawn beyond DRAW_RANGE 20 m. Collides with
  1 | 9 (the player's floors and walls), never the player.
- **Thrown** (rat_control.gd `throw_rat`, from player.gd `use_consumable` when
  the quick slot holds a live rat): from the eye along the view at 11 m/s, +3
  up, + half the player's run, tumbling; one per 0.6 s. On landing,
  `rat.scare_around` calls `scare(at, SCARE_TIME 4 s)` on everything on the
  damageable layer within SCARE_RADIUS 8 m, then the rat runs for a spot
  8-15 m off that the player cannot see -- behind stone, or OUT OF THE VIEW
  (on the open sandbox plane there is no stone) -- and is freed once out of
  sight 0.3 s (or after 9 s whatever happens).
- **Scared** (enemy.gd `scare` / `is_scared` / `_on_scared` / `_run_scared`):
  runs from the spot at full `move_speed` along the navmesh to a point SCARE_RUN
  12 m off, then stands till the fright ends; checked in `_physics_process`
  after stuns, before the hunt, with `engaged` false (so enforcer.gd drops a
  beam or swipe itself). Refused by the bosses (`announce_death`), a summon, a
  stagger, a convoy hauler. archer.gd loses the drawn arrow (`_on_staggered`),
  decrepit.gd ends its move with no combo. crier.gd has its own: flies away at
  rush speed, keeping height, and forgets the player; not once it is on the
  face. The Remnant and the mimic are not scared.
- **The robot rat** (rat_control.gd, a child of the player's head:
  `player.rats`; the body `scripts/robot_rat.gd`). Built at the workbench
  (workbench.gd BUILD row, `_build_robot_rat`): 1 live rat + CRAFT_COST 3 gold
  crystals (refunded if there is no room). Its eyes, back crystal and antenna
  bulb glow in the enforcer's crystal colour READ OFF enforcer.glb's
  "EnforcerCrystal" material through the scene state (`enforcer_eye_colour`:
  (0.0012, 0.9129, 1.0)), at EYE_ENERGY 2.4 (the enforcer's rings run at 0.7;
  that does not read on eyes this small). In hand it sits in the palm, side on,
  drawn pulled toward the eye like the sword (`use_z_clip_scale`). LMB
  (`deploy`, on the floor, not ghosting or drinking): set down 1.1 m ahead (less
  if stone), one used, and `player.remote_view` on -- the body takes no
  movement, look, jump, dodge or attack input (player.gd), no wheel, inventory
  or map opens, `hands_busy` puts the sword and torch away -- and its camera
  (between the eyes, FOV 88, near 0.02) draws. WASD / left stick drive it at
  5.5 m/s, mouse / right stick turn it; LMB / RB DETONATES: BLAST_DAMAGE 100
  whole (no falloff -- it is a bomb) to everything damageable within
  BLAST_RADIUS 4 m not sheltered by stone, thrown out and staggered, the
  spear's firepot burst for the look. FUSE 10 s, then it goes off by itself.
  NO cooldown: another can be set down at once (see the amendment below).
  Death, a scene, or falling 30 m sets it off at once. Overlay: corner
  brackets, the fuse bar (red its last 3 s), keys, "YOUR BODY IS UNDER ATTACK"
  when the left body is struck -- lines and text only, no full-screen fill.
  A small cyan OmniLight (3.5 m, shadowless) at the eyes only with
  `Graphics.effects`.
- **HUD**: attack_icons.gd shows only as many tiles as `attack_cooldowns`
  returns (the robot rat: one, `rat_bomb` glyph), packed right by the bar.
- **Population** (maze.gd `_spawn_rats`, in `_populate` after the lizards):
  `rats_in_corridors` 24 on corridor tiles (the patrol points), `rat_clear` 10
  m from the player, `rat_apart` 6 m apart, and `rats_in_sewer` 8; under their
  own "Rats" node (not `_spawned`, so `_report_room_intruders` ignores them).
  **Sandbox**: KINDS "Rat (harmless; E to grab)"; sandbox_menu.gd GIVE ITEMS:
  live rat, robot rat, 10 gold crystals.
- **Traps**:
  - A per-variant ArrayMesh built with `SurfaceTool.append_from` and a
    non-uniform scale carried the normals unchanged: the body shaded in bands
    like a grub. `_add` merges by hand with the inverse-transpose normal basis.
    Packed arrays are VALUES in GDScript: appending through `dict["v"]`
    appended to a copy (every surface came out empty). Vertex colours are
    linear unless `vertex_color_is_srgb`: they came out pale.
  - A 0.08 m sphere collider slipped into the cracks between floor slabs; one
    fell out of the world. Both rats are flat boxes now, and a wild rat that
    drops 2.5 m below where it last stood is put back (`FALL_GUARD`).
  - Rats first darted along navmesh paths to random points. Measured with the
    rats on, "It's not expect to not find the most reachable polygons" was
    logged in about 1 boot in 4. Straight-line darts did NOT fix it: the cause
    was `_spawn_rats` drawing from the population `_rng`, which shifted every
    roll after it (the chests and what they bring). They have their own
    `_rat_rng` now, and the error went: 0 in 8 boots with rats, 0 in 14
    without. So some population this seed did not use to make logs that error
    now and then -- latent, not the rats'; not chased further.
  - From between its eyes the robot rat's own snout, lit by its eye light,
    filled the foot of the view: its parts are on visual layer 20
    (`SELF_LAYER`), which its camera leaves out.
  - `class_name RatModel` would not resolve until an editor import refreshed
    the class cache ("Identifier not declared"): it is preloaded by path
    (`RAT_MODEL`) instead, so a fresh clone runs without an import.
  - The harness had to `load()` rat.gd / rat_control.gd at run time: they name
    `Graphics`, and preloaded by the entry file they failed to compile.
- **Measured** (throwaway harnesses, deleted): 64/64 and 40/40 headless --
  slot rules both ways; 3 rats darted, top 7.0 m/s; a still player at 1.4 m
  noticed, frozen 0.3 s on, then 10-12 m away; E prompt in reach, none at 6 m,
  E -> carried on the quick wheel; 10 rats in a real corridor 12 s: all moved,
  0 ticks through a wall, none below the floor; thrown 10.3 m, skeletons
  1.8 -> 12.9 m and the enforcer 0.7 -> 6.1 m from the spot in 2.5 s, crier
  scared, the Warden not, the rat out of sight and gone within 2.5 s, fright
  over after 4 s; bench 5 gold + 1 rat -> robot rat, 2 gold left; eye colour
  equal to a live enforcer's CRYSTAL; deploy -> its camera current, W 5.2 m in
  1 s, the body 0.00 m; detonate 500 -> 400 at 1.5 m, untouched at 8 m; view
  home; cooldown refused; alone it went off at 9.90-9.95 s; death set it off.
  Re-broken: blast 50 and the scare branch off -> 3 failures, as they should.
  Windowed screenshots checked: rats in a corridor, the palm, the rat's-eye
  view and overlay, the blast, the Utility tab, the workbench.
- **Cost** (`--bench`, RTX 4070 at 1280x720 -- NOT the P620; relative only):
  first cut (4 surfaces a rat, drawn to 32 m, awake to 40 m) +110 draws at the
  spawn corridor and 125.5 vs 130.8 fps overall. Merged to one surface (+ glow)
  and 20 / 25 m: 128.1 fps with rats against 129.9 and 130.8 in two runs
  without -- inside the run-to-run spread (the two no-rat runs differed by 45
  draws and 0.9 fps). No quality knob: the per-rat cost is at the noise floor.
- **Amended (2026-10-18, the user): no cooldown between robot rats, and the
  blast hurts the player.** rat_control.gd: COOLDOWN and `charge()` are gone
  (the 12 s first shipped); the attack tile is never shaded; `deploy` asks
  only for free hands and the floor -- so after its own blast throws the
  player up, the next can go down the moment they land (37 ticks measured).
  `_blast_player`: if the player's capsule (0.4 x 1.8 m) is within
  BLAST_RADIUS 4 m of the blast and stone does not shelter them, they take
  BLAST_DAMAGE 100 through `take_damage` (armor applies; the sandbox's god
  switch spares them) and are thrown back. 100 kills from full health at
  armor 1 -- setting one off where it was put down, 1.1 m ahead, is death.
  Measured (throwaway harness, deleted): blown at the feet, 100 -> 0, dead;
  god mode, nothing; three set down back to back; driven 7.2 m off, untouched;
  armor 6, took 80. Re-broken (the player's blast off): both damage checks
  failed.
- **Amended again (2026-10-18, the user): a robot rat costs 1 gold crystal
  (CRAFT_COST, was 3) and its blast does 200 (BLAST_DAMAGE, was 100)** -- to
  the player too, so standing in it is death at any armor (level 10, the
  most, takes 36% off: 128).
