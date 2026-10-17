## 14. The spear (2026-10-08)

- **Second weapon, hotbar slot 3 at the start** (`scripts/spear.gd`, a Node3D
  under `Head` made in `player._ready`; `Inventory.ITEMS[&"spear"]`, icon
  `ItemIcon._spear`, stats in `inventory_screen._stats_for`). It does its own
  fighting; `player._unhandled_input` routes LMB / Q / F to `spear.stab()` /
  `dash()` / `throw()` while it is in hand and `_spear_free()`.
- **Stab (LMB)**: 10 damage, one per `STAB_EVERY` 0.28 s however fast it is
  clicked; a box `STAB_REACH` 2.7 m x 0.45 down the camera on the hitbox mask,
  first body only, line of sight checked, bombers skipped (they take the haft).
- **Dash (Q)**: `player.begin_spear_dash` drives the body at 17 m/s for 0.32 s
  (no steering); a 0.9 m sphere ahead hits everything once for 25 and shoves it
  aside. Cooldown 1.4 s. Trap: the dash ended at full speed and the normal
  movement code coasted it ANOTHER 6 m (11.3 m total) -- the exit now clamps
  horizontal speed to `move_speed`. Measured 6.3 m.
- **Throw (F)**: 0.24 s wind-up, then a top-level "ThrownSpear" flies 46 m/s by
  ray (stone, layer 9, hitbox mask) up to 42 m, EXPLODES where it stops
  (`BLAST_DAMAGE` 60 falling to half at `BLAST_RADIUS` 4.5, push 15, LOS from
  the blast, bombers `swat`ted, `alert()`), sticks 0.3 s, then is pulled back
  butt first along a glowing tether and caught (~1.4 s round trip at 10 m).
  Nothing works while it is away. The player takes no blast damage.
  Thrown point-blank at a wall it bursts at the wall, not beyond it.
- Fireball is `shaders/spear_blast.gdshader` (facing-weighted noise, `fade`
  instance uniform): a plain additive sphere read as a solid faceted dome.
  Warmed up at load: worst frame through the first throw 27.7 ms.
- Traps: hiding the spear Node3D while it was away hid its top_level TETHER
  child too -- hide `_model`, not the node. Fully metallic iron rendered black
  in these halls (nothing to reflect): metallic 0.4. The rest pose aims the
  blade right of and below the crosshair; pointed AT it, the blade sat behind
  the reticle 2 m out and the spear read as a dark stick.
- `respawn` calls `spear.reset()` (back in the hand, projectile freed).
- Measured in a harness, 19/19: slot 3; F throw -> 55.8 on the struck enemy,
  46.9 at 2.5 m, 0 at 9 m; stab/dash refused while away; LMB 10; spammed
  5 stabs in 1.4 s; nothing at 3.8 m; Q 6.3 m, second Q on cooldown 0 m; dash
  25 to each of two in line; bomber beside the blast popped (control: a blast
  14 m off left one untouched); reset.

- **Every weapon blocks** (2026-10-08). `_start_block` takes anything
  `Inventory.is_weapon` (kind "Weapon"), not only the sword; `_check_block`
  drops the guard if the item in hand changes (`_block_item`), and
  `_hold_guard` raises it again at once with the new one if RMB is still held.
  The sword keeps its pivot pose; the spear reads `player.guard_amount()` and
  blends to `spear._guard_pose()` (haft level across the body, its middle in
  front of the face, blade off left) -- a PLACEHOLDER. The plan (user): every
  weapon is a hologram projected by a crystal in the haft, and a SHIELD pops out
  of the haft on block; models and animations are in progress. Hooks for it:
  signal `guard_changed(raised)` (also on death/respawn), `guard_amount()` (eased
  0..1 over `GUARD_UP` / `GUARD_DOWN`), `guarded(parried, attacker)` and
  `_guard_kick` for the knock. The spear guard waits for a stab/dash/wind-up
  and for a thrown spear to be caught (`spear.busy()`); nothing else of the
  spear works while guarding (`_spear_free`). Measured with the real RMB
  (11/11): spear parry 0 taken / 20 back, block 4 of 40; stab, dash and throw
  refused while up (re-broken: the dash went through, 6 m and 25 damage); guard
  up after the stab, not during; none while thrown, up on the catch; spear ->
  sword with RMB held: down, up with the sword, which still blocks 4 of 40;
  potion in hand: no guard.

- **The sword's Q is a SPIN now; the thrust is gone** (2026-10-08). `_start_spin`
  -> pose `spin` (`_spin_pose`, timeline SPIN_WIND 0.2 / SPIN_TURN 0.62 /
  SPIN_END 1.0; the slash ends at 0.42): blade wound out right while the view
  coils `SPIN_COIL` against the turn, then the HEAD turns one full circle left
  (`_spin_view_yaw`, added to `head.rotation.y`; the body's yaw -- the aim --
  is never touched, and a whole turn ends exactly where it began) with the
  blade held at `SPIN_LEAD` leading it, so in the world it sweeps the whole
  circle. Hits are the cut's: the same swept-blade slab in `_resolve_hits`,
  `attack_damage`, `attack_push`, `attack_stun`, once per body; bites from
  SPIN_WIND to SPIN_TURN; committed (`_bite_end` = SPIN_END), Q mid-spin does
  nothing. No trail (it is drawn in the head's frame, where a spinning blade
  stands still). The thrust's exports, constants, pose, planting and its hit
  box are deleted; `_hilt_at` now always takes an aim (the cage stab uses it).
  The lunge speed lines stay for the spear's dash ("Lunge look" group).
- **Spear throw: 100 damage, 10 s cooldown** (`BLAST_DAMAGE`, `THROW_COOLDOWN`
  from the release; reset on respawn). Full damage within 1 m of the impact (a
  struck body's centre is ~0.9 m from where the spear hit it), half at the
  4.5 m edge. The cooldown shows on the spear's hotbar slot
  (`ItemSlot.set_cooldown`: a dark shade draining downward + seconds left,
  driven by `hud._update_slot_cooldowns` from `spear.throw_charge()`).
- Measured (all pass): spin hit enemies front, right, behind and left once
  each for 20, knockback 5.50 outward on all four = a cut's 5.50; 5 m off
  untouched; view turned 6.28 rad and ended at 0.0000 with the body's yaw
  unchanged; a second spin after it hits again; worst frame 17.2 ms (idle and
  a hand turn: 17.2 / 16.9). Throw: struck enemy 100.0; F again 1.9 s later
  refused; slot showed 9; clears at 10 s and throws again.
- **Harness trap**: a "50 ms first frame" of every attack was the harness --
  the timer started before a press helper that waits two frames, so the first
  sample spanned three vsyncs (3 x 16.7). Start the clock AFTER the press.

