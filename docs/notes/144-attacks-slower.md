## 144. Every weapon's attacks slower: one number (2026-10-31)

The user: "Slow down all of the players attacks on all weapons". No amount given,
so 25% longer (20% slower), chosen as noticeable but moderate.

- **`player.gd` `attack_time_scale` 1.25**, an export at the top beside
  `attack_damage`. It is the one number to turn: 1.0 is the old pace, every
  authored timing stays as it was written, and each weapon divides its clock by
  this. Player 2 has the same default.
- **Sword.** `_update_pose` advances `_pose_time` by `delta / attack_time_scale`
  for `ATTACK_POSES` (cut, chop, spin, the slam's raise and strike), so every
  `SWING_*`, `SPIN_*` and `SLAM_*` follows at once. The guard, a haft strike and
  the cage stab are scripted to their scenes and keep their time. The slam's
  getting up (`_slam_recover_until`, `_slam_crouch`) and its dive
  (`slam_descent_speed`) follow too. `_spin_view_yaw`'s look-ahead is on the pose
  clock, so it gets the scaled delta, or the view runs ahead of the blade.
- **Spear.** `time_scale()` over `_pose_t`, so the stab's bite and the throw's
  wind-up follow; `STAB_EVERY` and `DASH_COOLDOWN` scale. The dash is slower, not
  shorter: `DASH_TIME` up and `DASH_SPEED` down by the same factor, the same 5.44 m.
- **Axe.** `time_scale()` was already there for berserk, so it now carries
  `attack_time_scale` as well. Berserk still halves the result.
- **Followed:** the view punch (`attack_kick_time`), the spear's strain decay (or
  it stops building at the slower beat), the HUD icons (`attack_cooldowns`), and
  the inventory's "Stab rate", "Dash cooldown" and "Slash rate".
- **Left alone, on purpose:** long recharges (spear throw 10 s, slam 20 s, berserk
  20 s), speeds of things in flight (a thrown spear or axe), the berserk roar, the
  guard and parry, damage, the flinch's second, thrown rats (a utility item, not a
  weapon), and `sweep_trail_life` (the streak fades on its own clock, so it spans a
  little less of the arc).

**Measured.** A throwaway harness on the real player in the sandbox, each attack
at 1.0 then 1.25, in real seconds (one frame of noise, headless at 60 Hz):

```
                         1.0     1.25
cut, whole stroke       0.433    0.533
cut, bite ends          0.283    0.350
spin, whole             1.017    1.267
spin, bite ends         0.633    0.783
ground slam lands       0.235    0.285
air slam from 12 m      0.386    0.485
slam down for           0.998    1.248
stab every              0.248    0.314
dash time               0.333    0.400
dash speed             17.00    13.60
dash metres             5.450    5.440
dash every              1.416    1.767
spear throw wind-up     0.250    0.317
chop every              0.747    0.946
chop lands              0.400    0.517
berserk chop every      0.381    0.480
axe throw wind-up       0.517    0.633
```

The spin still turns exactly one circle and the view lands where it started (6.28
rad peak, 0.000 after). On a frozen skeleton 1.8 m ahead every blow connects for the
same damage at both paces: cut 20, spin 20, stab 10, chop 60. HUD totals scale with
it (cut 0.27 -> 0.34, spin 0.62 -> 0.78, stab 0.25 -> 0.31, dash 1.40 -> 1.75).

**Traps.**
- Both of the harness's first checks passed or failed for its own reasons. A body
  set to `PROCESS_MODE_DISABLED` is taken out of the physics space (its default
  `disable_mode`), so every attack did 0 damage at both paces; freeze it with
  `set_physics_process(false)` instead. And `is_on_floor()` is stale for a physics
  frame after lifting the player, so the "air" slam ran the ground path until the
  harness waited three ticks.
- Anything comparing `_pose_time` with a previous step has to use the scaled step:
  the spin's release was `_pose_time - delta`, which with `delta` larger than the
  step would fire the punch twice over a frame.
