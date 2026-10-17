## 51. The enforcer's second delivery; manholes open from above only; walk-over pickup (2026-10-15)

- **New enforcer file** (`models/source/enforcer/ENFORCER_BAKED.blend`, the
  user's second delivery): baked clips WALK_BAKED, BEAM_BAKED, the new
  BEAM_RECOIL_BAKED (the cannon kicking as it fires) and SWIPE_1_BAKED (renamed
  from SWIPE_BAKED, reworked). The file also carries the unbaked sources
  (WALK, BEAM, BEAM_RECOIL, SWIPE_1), one of them on an UNMUTED NLA track that
  would have been exported: `build_enforcer.py` now removes every track and
  action not ending in _BAKED. Same mesh (the atlas came out byte-identical).
  Eyes (cyan rings at `EYE_GLOW`), crystal colour and beam unchanged.
- Measured in Blender, used in enforcer.gd: BEAM_RECOIL starts exactly on
  BEAM_BAKED's settled pose and kicks the muzzle 0.23 m back by frame 18 WITHOUT
  returning, so firing plays it once and holds its end (`_hold_recoil`,
  `ANIM_RECOIL_CLIP`). SWIPE_1: shield guarded in front at frame 1, drawn back
  over 11-21, swept across the chest at 22-25 (seen in renders) --
  `SWIPE_CONTACT` 21/60 (was 31/60).
- **Enemies woken by `alert()` fought frozen.** Dozing (`_update_dormancy`)
  switches the AnimationPlayer off; `alert()` (prison alarms, kicked doors,
  every hit) and maze `_turn_loose` clear `_dormant` without switching it back
  on, so the rig never advanced: every prison enforcer beamed and swiped stuck
  in its first frame, and the old "measured" clip checks (section 48-49) only
  read the clip's NAME. `_advance_anim` now re-activates the rig whenever the
  body is awake. Measured: the charge reaches 0.76 s of BEAM_BAKED (its
  settled pose), the swipe plays to 0.99 s, the recoil is held at its end;
  control without the fix: 0.00 s, 0.00 s, never held. Skeletons woken the
  same way were affected too.
- **Manholes open from above only** (manhole.gd): under a covered manhole the
  ladder shows "E   Sealed" and E toasts "The cover is shut from above" and
  does nothing (the shove-off-from-below is removed); `_climb_up` refuses
  unless OPEN. Once lifted from the dungeon side it works both ways.
- **Walk-over pickup** (item_drop.gd `_auto_take`): a resting drop within
  `AUTO_REACH` 0.9 m of the player's feet is taken without E if the player
  already carries that item -- a stack of it, or a quick slot kept for it that
  has run dry -- and there is room for all of it. Not in a scene, dead,
  climbing or hidden. Anything not carried still needs E.
- Measured (harness, 24/24): potion walked over taken; uncarried skull left
  lying, then taken where the player stood once one was carried; a dry kept
  potion slot counts; coins 3 -> 8; nothing from 2 m; sealed ladder said
  Sealed and E left the player at y -12 with the cover on; lifted from above,
  climbed up from below; clips exactly the four baked; two ring eyes; recoil
  clip while firing and held; swipe and knock-down.
- Bench (RTX 3060, 3440x1440, editor closed): 66.9 fps, worst p99 35.70 ms,
  1157 MB (68.6 / 34.22 and 65.4 / 30.26 on the same layout before) -- noise.
- **Struck enforcers throw sparks** (enforcer.gd `take_damage` -> `_hit_sparks`,
  2026-10-15): every blow that lands sprays a random 8-26 hot streaks (3-6 and
  no light with `Graphics.effects` off) from the point on its body facing the
  player (`_hit_point`: the body axis at the eye's height, clamped to
  `HIT_LOW`..`HIT_HIGH`, out `HIT_SURFACE` 0.62), back toward them and up,
  falling and cooling white -> orange -> red over ~0.5 s, plus a 0.14 s warm
  flash of light. Streaks are two crossed quads aligned to velocity
  (`particle_flag_align_y`), shared mesh and material, warmed at load. First
  pass at 7 mm wide with the colour driven to 2.2 read as fat white sausages
  under the glow; 3.5 mm at 1.0 reads as sparks. Measured: 11 of 12 real cuts
  landed and 11 bursts, every one 0.62 m out on the side facing the player;
  amounts seen 8-26; a miss none; effects off 3-6 and no light; all freed.

