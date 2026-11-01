## 143. The flinch (2026-10-31)

The times and the slow here are superseded by note 145: half a second, all but planted.

The user: "If the player gets hit and is not knocked down, he should react, slow
down and not be able to attack for 1 second."

- **`player.gd` `_flinch(blow)`**, called from `take_damage` beside
  `_interrupt_drink`, so only for a hit that hurts: `guard == 0` and an attacker
  given. All three parts last `flinch_time` 1.0 s, on `_now()` like the slam's
  recovery.
- **The reaction.** `flinch_view()` is (drop m, pitch deg, roll deg) as
  `_knock_view`, added to `wake` in `_update_head`: `FLINCH_DROP` 0.06 m,
  `FLINCH_PITCH` 9 deg back from a blow in front (nodding forward from behind),
  `FLINCH_ROLL` 7 deg away from one at the side, at least `FLINCH_MIN_ROLL` 0.4 of
  that so a blow straight on still tips the head. In over `FLINCH_SNAP` 0.07 s,
  then (1-k)^2 home at exactly 1 s. A second blow starts from where the view has
  got to (`_flinch_start`), or it would jump. Also `_shake` 0.3, and the weapon in
  hand knocked down: `weapon_dip()` up to `FLINCH_WEAPON` 0.45 of its put-away
  motion (`_duck_transform` for the sword, `_raise` in spear.gd and axe.gd), not
  while a guard is up. In co-op the other player sees `coop_avatar.gd` lean the
  same way.
- **The slow.** `flinch_move_scale` 0.5 on walking, the air, ghosting and
  swimming (`_flinch_speed_scale`, next to `_beam_speed_scale`).
- **No attacking.** `is_flinching()` in `_start_attack`, `_start_spin`, the slam
  key, `_spear_free` (every spear and axe key, and the queued stab and chop
  forget themselves through it), and rat_control.gd `throw_rat` and `deploy`.
  `attack_cooldowns` counts it in `recover`, so every attack icon shades for the
  second, the slam's too. An attack key mid-drink does not spill the drink while
  locked (`_attack_key_spills_drink`): no attack is going ahead.
- **The attack under way cannot bite after the hit**, or a swing a frame old
  would land inside the lock. A cut goes to the `unblock` pose (home in 0.16 s).
  The spear's dash and throw wind-up and the axe's chop and throw wind-up stop
  (`interrupt()` on each; the spear has a new `Pose.BACK`, the axe had one). A
  spear stab bites 0.036 s in, so it plays out. A SPIN keeps turning with its
  blade dead: cancelling it would snap the head yaw back from up to a full turn.
  A SLAM lands as a dud (`_slam_armed` false, `_paint_slam_marker` repaints the
  floor). Berserk's roar is not stopped; nor is a weapon already in the air.
- **Stay free:** guard, ghost, drinking, jumping. A hit should not also take the
  way out of the next one.
- **Not a flinch:** a blocked or parried blow, a blow on the floor or in a scene
  (being held by the claw or strapped to the table is `in_cutscene` too), a beam
  (paid by the frame, has its own slow) or a cage-skull drain, their own robot rat's blast (`take_damage` with no
  attacker), and anything with "Player takes damage" off in the sandbox (it hurts
  nothing, so the check after `amount <= 0.0` never sees it).
- **Knockdown replaces it, in either order.** Callers do `take_damage` then
  `knock_down`, so `knock_down` clears the flinch, and `_flinch` refuses while
  `is_knocked_down()` for the blows that land on the floor. Getting up, they can
  swing at once.

**Measured.** On the real player scene, every physics tick: 4.25 -> 2.13 m/s, back
to full at t = 1.02 s; attack pressed every tick, first swing at t = 1.000 s; peak
9.0 deg on the head node, view exactly zero after. A from-the-right blow rolls +6.5
deg, one from behind pitches -8.4. Against real enemies in the sandbox, player
standing still: Proel 3 hits, 3 flinches; hammer 3 knockdowns, 0 flinches; drill 4,
4; shield 4, 4; crossbow 3, 3; crier 7, 7; scout 9 hits, 4 flinches, 3 knockdowns
(tri-stabs land inside a flinch); decrepit 9 hits, 4 and 5; lizard 12 hits, 5 and
1; enforcer up close 1 knockdown; the Remnant killed outright. Not one hit without
a reaction, no flinch left after a knockdown. Re-broken with `flinch_time` 0, 19
checks of the harness fail, so it sees the difference.

**Traps.**
- A harness cannot capture the mouse under `--headless`, so `aim_ready` is false
  and every attack key takes the mouse back: the first run failed all of them.
  Driven as co-op player 2 instead (`Coop.start()`, `player_index` 1, pad bindings
  through `_unhandled_input`, `p2_` actions held).
- `save_png` of a 3440x1440 grab takes about a second on the main thread, and
  `_now()` runs through it. A flinch appeared to have vanished right after a
  screenshot; rerun without shots it was all there.
- `is_flinching()` carries across an enemy swap in a harness: a rising edge at
  t = 0.28 was the last enemy's blow.

A pack can chain it: invulnerability is 0.6 s, so blows arriving faster than the
flinch ends keep the attacks locked. Guard and ghost are the way out. Not tuned
further; the user's second is the number.
