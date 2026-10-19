## 78. The Tripo rat, animated, and held by the tail (2026-10-18)

The user: the live rat is their model ("mouse with bones.blend"), with "very
lifelike and realistic" animations for running and for being caught, rigged;
equipped, the player holds it by the tail and it squirms and shakes. (Same
day: the robot rat costs 1 gold crystal and does 200 -- note 77's amendment.)
The robot rat keeps its procedural look (rat_model.gd).

- **The model** (`models/rat.glb`, built by `tools/build_rat.py` from
  `models/source/rat/mouse_with_bones.blend`; tools/README.md "The live rat").
  The file's Tripo rig is not used (head and forelegs off the root, not the
  spine; tail off a "limb"; 3 tail bones): the script keeps the textured
  566-vertex mesh, builds a clean 29-bone rat (Root, Hips, Spine1-2, Chest,
  Neck, Head, Tail0-6 + TailTip, Thigh/Shin/Foot/Toes and UpperArm/Forearm/
  Hand each side) placed through the mesh's parts (from the Tripo weights'
  vertex clusters), skins it with automatic weights (the 20 small islands --
  ears, eyes, whiskers -- to the head; smoothed; 4 bones a vertex), and poses
  four looped clips in code, 30 fps, baked to keys:
  - **Run** (10 f): a half-bound gallop -- hind feet land together (L at 0,
    R at 0.03 of the cycle) and push off over 0.3 of it, the forefeet land
    one after the other (0.45, 0.52), the back arches as the hind feet come
    up under it (~0.9) and stretches in the long flight (~0.4), the body
    rides up off each push, the head is held steady against it, the tail
    streams out with a wave down it. Legs by analytical two-bone IK
    (`two_bone`), knees forward, elbows back; RUN_STRIDE 0.8 source m a cycle.
  - **Idle** (150 f): down on all fours, sniffing in bursts, head turning, a
    forepaw lifting now and then, tail lying out.
  - **Rear** (150 f): up on its haunches (the model's own pose), nose working,
    looking about, forepaws twitching.
  - **Dangle** (120 f): hung by the tip of its tail, head down; curls belly-in
    up toward the hand, throws itself side to side, twists, forelegs reaching
    and grabbing, hind legs kicking and splaying, head lifting and swinging.
- **In the game** (`scripts/rat_look.gd`, shared): the glb at SCALE 0.5
  (about 0.27 m nose to rump, the tail as long again), turned so the nose
  faces -Z, every clip looped, not drawn beyond rat.gd DRAW_RANGE. rat.gd
  plays Run while it moves, at ground speed / (RUN_STRIDE 0.4 m per 0.333 s),
  capped at RUN_MAX_RATE 3.5 (above that the legs only strobe); Rear when it
  has noticed the player and frozen, and in REAR_SHARE 0.3 of its pauses;
  Idle otherwise; Dangle, tumbling, when thrown. The clip pauses while the rat
  sleeps. **RUN_SPEED 7 -> 5.5 m/s, BOLT_SPEED 9.5 -> 7.5** (the player
  walks 4.25): at the old speeds even the capped gait slid badly.
- **Held by the tail** (rat_control.gd). Choosing a live rat on the quick
  wheel (player.gd `use_consumable` -> `take_rat`) now takes it IN HAND
  instead of throwing it; catching one with E (rat.gd `grab` ->
  `hold_caught`) does too, with CAUGHT_FIT 1.6 s of extra fury. The held rat
  is a rat_look.gd placed in world space every frame (top level): turned with
  the player's yaw (not the view's pitch -- it hangs plumb), twisted about its
  tail (HOLD_TWIST, round a facing HOLD_FACING), swung (HOLD_SWING) and shaken
  (HOLD_SHAKE, fast sines), all doubled in the fit, then moved so its TailTip
  bone is exactly at PINCH (head space, lower right of the view) -- the swing
  pivots about the fingers. Its Dangle clip is stepped by hand
  (`advance`, faster in the fit) just before, so the tip is this frame's. Its
  material is pulled toward the eye like the sword's (`use_z_clip_scale`).
  Eased up into view over HOLD_RAISE. While held: LMB (or the wheel again)
  throws it from where it hangs (`throw_held`; it vanishes from the hand at
  once), RMB puts it away; Q / F do nothing. Put away (still carried) on
  choosing a weapon (`selection_changed`), drinking, anything that takes the
  hands, or none left. The sword (player.gd `_update_sword` `away`) and the
  spear (spear.gd `held`) go down while one is held. rat_control.gd hears the
  keys first: it is under the player's head.
- **Traps**: (build) opening the source resets the scene to 24 fps; the
  non-deforming TailTip is dropped unless `export_def_bones` is off; the
  texture is named after the packed image's path; swinging the hind toes put
  the ankle above the hip and tore the rump -- the swing drives the ankle on a
  low arc; the rig's preview camera has to frame each clip on its own extent.
  (game) The sword's put-away runs on `frame_pre_draw`, which never fires
  headless: a harness must step `_update_sword` itself.
- **Measured** (throwaway harness, deleted; headless): 23/23 -- the rat wears
  the glb; sitting Idle; darting Run up to 3.50x; frozen it Rears; asleep its
  clip is paused; grabbed -> in hand at once and carried; shown; TailTip
  0.0000 m from the pinch; Dangle; body 0.26 m below the fingers; it moved
  0.062 m on its tail in 30 frames; sword duck 1.00; LMB throws it from where
  it hung, one fewer carried; it flies in Dangle and lands to Run; the wheel
  takes one in hand without throwing, RMB keeps it, choosing a weapon puts it
  away, the wheel again throws it. Re-broken (no tail anchoring; no sword
  condition): 4 failures, as they should. Windowed screenshots checked: three
  rats in a corridor (Idle / Rear / Run), the rat just caught and later in
  hand, the throw.
- **Cost** (`--bench`, RTX 4070 at 1280x720 -- NOT the P620; relative only):
  with rats 126.0 and 127.3 fps overall, without 129.8; per station +0.04 to
  +0.33 ms avg (spawn +0.04/+0.22, boss centre +0.08/+0.12, edge +0.10/-0.06,
  outer +0.32/+0.27, chest +0.24/+0.33), physics +0.2 to +0.4 ms, video
  memory +0.9 MB. The procedural rats measured 128.1 against 129.9 / 130.8
  (note 77): the skinned, animated rat costs a little more, just above the
  run-to-run spread (two no-rat runs have differed by 0.9 fps). Still no
  quality knob; if the P620 shows it, the levers are DRAW_RANGE / SLEEP_RANGE
  and rat_look.gd's AnimationPlayer (manual, at a lower rate when far).
