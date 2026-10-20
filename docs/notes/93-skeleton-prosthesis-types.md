## 93. Skeleton types: a prosthesis for a hand (2026-10-20)

The user: "Separate skeletons into different types ... different prostheses on
their hands that do different things": a DRILL hand (dashes like the old
skeleton, found in the mining room), a SWORD hand (no dash; a light and a heavy
slice), a SHIELD on both arms (guards other skeletons), a big HAMMER hand
(slower, heavy hitting), a CROSSBOW hand (replaces the bow skeletons).

- **`scripts/prosthetic.gd`** extends enemy.gd; `var hand` (&"drill", &"blade",
  &"hammer", &"shield") has a setter that sets the type's numbers (`_apply_hand`),
  so set it BEFORE the body enters the tree and anything set after wins (the
  callers' `wanders`, `aggro_range`). `make(scene, hand)` = enemy.tscn +
  set_script + hand; `_init` re-sets enemy.tscn's overrides (a script swap drops
  them, as for the archer).
  - drill: 100 hp, 4.5 m/s, jab (NORMAL, `Move.THRUST`, 14) + the old charge as
    its dash (SLAM 18 m/s x 0.45 s, 8 s cooldown, 18 dmg, also THRUST pose).
  - blade: 100 hp, 4.6 m/s, no closing move (`_pick_attack`: out of reach it
    walks). Light = the old cut (NORMAL, 12, 1.6 s cooldown); heavy = SLAM
    re-used as a planted step (2.5 m/s x 0.42 s), wind-up 0.85, recovery 0.95,
    26 dmg, 4.5 s cooldown, picked 40% of the times both are ready, posed as
    the new `Move.SWEEP` (flat across the front at chest height).
  - hammer: 140 hp, 3.4 m/s, accel 14, knockback resistance 0.45; one move, the
    overhead smash (NORMAL posed `Move.CHOP`, 0.5 s), wind-up 0.95, recovery
    1.2, 30 dmg; an unguarded hit calls `player.knock_down(dir, 6.5)`.
  - shield: 120 hp, 3.9 m/s, unarmed; bash (NORMAL, range 1.2, 9 dmg, shove 8,
    half through a guard). Group "shield_guards".
- **enemy.gd hooks** (all default to the old behaviour): `_windup_for`,
  `_recover_for` (stored as `_windup_len` / `_recover_len`, which
  `_update_sword` now uses for the arm's phase), `_damage_for`, `_sword_move`
  (attack kind -> skeleton_sword `Move`), `_on_blow_landed` (after both the
  blade's and the reach test's hit). `_covering_shield(blow)` is asked at the
  top of `take_damage` (the guard's `block_for` takes it) and of
  `apply_knockback` (the shove is dropped), so a guarded ward is neither hurt
  nor staggered.
- **The shield guards** (`prosthetic.gd _chase`): it picks a ward every 0.6 s --
  nearest skeleton within 12 m, a crossbowman counting half as far, never
  another shield or one another shield holds (meta `shield_guard`) -- and stands
  GUARD_AHEAD 1.5 m in front of it on the line to the player, facing the player.
  Within bash range, or with the player on its ward, it falls back to the
  ordinary chase and bashes. `covers(ward, blow)`: guard up, blow into its front
  (facing . blow < -0.35), standing 0.4-3 m toward the blow's source from the
  ward and < 0.75 m off its line. Its own front: blocked to a 10% chip
  (`_deflect` swell + the boss on the shield flares). Guard BREAK: a blow of 40+
  (half lands) or a shove of 8.5+ (the slam 9, spin 11, spear dash 9, blasts,
  a parry 14) drops it for 1.5 s. The archer's `_find_cover` already stood
  behind any non-archer; with a shield that is a stable pair.
- **The prostheses' look** (`skeleton_sword.gd`, kinds blade / drill / hammer):
  the HAND BONE is shrunk to 0.02 (`set_bone_pose_scale`) -- the rig's clips
  have NO scale tracks (checked: 0 in all nine), so it stays shrunk; the rigid
  bind means the hand island simply collapses into the wrist. The tool sits at
  the wrist in an iron cuff with two straps, along the forearm, turned only
  `PROSTHESIS_TURN` 0.45 toward the swing's blade line (a held sword turns all
  the way). `_point` must NOT be run on the shrunk hand: it orthonormalizes the
  basis and would undo the scale. Reaches: blade 1.05, drill 0.62, hammer 0.86
  (+0.12 strike radius for its head). The drill's bit is its own node and spins
  (7 rad/s idle, up to 46 through the wind-up and attack). Hauling a cart, a
  prosthesis is carried at the wrist pointed up (`_at_belt`).
- **The shield's look** (`scripts/skeleton_shield.gd`): a 0.72 x 1.1 m tower
  shield (planks, iron rim and bands, a boss with its own flare material) hung
  between both wrists; both hands shrunk; both arms two-bone reaching for grips
  on its back. Carried low in front out of a fight (`raise` 0), braced at the
  chest in one, driven 0.32 m forward in a bash. Posed only on rig steps; the
  type marks `_anim_stepped` after `_play_state_anim` (the seek re-poses the
  rig, the sword trap from note 24) and clears it itself (enemy.gd only clears
  it for a `_sword`).
- **The crossbow** (`archer.gd`): the bow is gone; the left hand is shrunk and a
  crossbow (cuff, stock, nut, an 8-box prod across the front, two string spans,
  the bolt on top) is strapped along the left forearm, so it hangs down at rest
  and points along the shot when the arm comes up. Bolts: `arrow.gd fire(...,
  as_bolt)` (0.4 m, thicker, stubby vanes), 18 dmg. After each shot the string
  is loose (`_cock` 0) and the right hand hauls it back over RELOAD 1.3 s after
  0.35 s; it cannot start an aim until cocked. Name "CROSSBOW SKELETON".
- **Where they are** (maze.gd): `_spawn_pack` -- archers as before (crossbows),
  and every other skeleton is a prosthetic: a SHIELD leads (member 0, the
  patrol's front) `shield_share` 0.6 of packs with someone to guard (3+, or 2
  with a crossbow); the rest roll `_melee_hand()`: HAMMER `hammer_share` 0.35,
  else SWORD. Jail-cell stock: the same sword/hammer roll. Rolls use their own
  `_hand_rng` (seeded from the level seed in `_populate`), so the other spawns
  are where they were. Convoy crews: sword hands (convoy.gd). The mine
  (dungeon_room.gd): the decor miners have a drill on `forearm.R` (a
  BoneAttachment, out by the hand's rest length) with a spinning bit, and are
  let loose as DRILL skeletons (`_spawn_prisoner(..., &"drill")`). Prison
  prisoners still fight bare-handed. The Warden (boss.tscn, enemy.gd) keeps his
  sword. Sandbox: Sword / Drill / Hammer / Shield / Crossbow skeleton (the old
  held sword and pick entries removed).
- Measured (throwaway harnesses, headless sandbox + the real level, player
  standing still): sword hand 12 swings in 25 s -- 8 light, 4 heavy, top attack
  speed 2.5 m/s (no dash), hits exactly 12 and 26; drill dashed at 18.0 m/s,
  hits 18 (dash) and 14 (jabs); hammer 4 hits of 30, 4 knockdowns, chase 3.40
  m/s; hands 0.020 after a second of clips; shield 0.64 m out in front, 1.34 m
  up; shield stood 0.14 m off the player-crossbow line, 1.44 m in front of its
  ward; a blow at the ward along that line: ward 60 -> 60, shield 120 -> 119; from
  behind the ward took 10; its own front 20 -> chip 2, from behind 20; a
  shove of 11 broke the guard. Real level (seed of the run): 59 sword, 36
  hammer, 24 shield, 34 crossbow (+60 enforcers, 3 decrepits, 25 lizards, the
  Warden); all 12 convoy crew sword hands; 6 of 6 miners with drills; a miner
  let loose is a drill skeleton with its Drill node. (The module level stocks no
  jail cells, so their sword/hammer roll ran in no measurement.) Clean
  `--quit-after` run of the game afterwards: no errors.
- Trap: `get_meta(key, null)` with a null default still errors when the key is
  missing ("does not have any 'meta' values") -- use `has_meta` first.
