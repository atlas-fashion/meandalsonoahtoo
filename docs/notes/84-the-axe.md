## 84. The axe: slash, a throw that stays in its mark, berserk (2026-10-20)

The user asked for a third weapon: "a regular slash attack that does 30
health, and hits every .75 seconds", a mid attack where it "gets thrown, and
does the same 30 damage ... stay[s] at the target for 2 seconds, leaving you
vulnerable with no weapon for that duration, and then flies back to you ...
unless the target dies", and a heavy attack, "a berserk mode that lasts for 7
seconds, and makes the player faster and halves all his attack times. The
player should stop when berserk mode is activated, and there should be a
visual effect on the ground and around the screen."

**Where.** `scripts/axe.gd`, a Node3D under `Head` made in `player._ready`
next to the spear and built the same way (it does its own fighting; the
player routes LMB / Q / F to `axe.slash()` / `throw()` / `berserk()` while it
is in hand and `_spear_free()`). `Inventory.ITEMS[&"axe"]` ("Bearded Axe",
kind Weapon, so it blocks), icon `ItemIcon._axe`, stats in
`inventory_screen._stats_for`, glyphs `axe_slash` / `axe_throw` / `berserk` in
attack_icons.gd, a level on the workbench (`player.UPGRADABLE`) and in the
sandbox menu. A new game puts it on the weapon wheel's DOWN slot (2); saves
from before it are handed one once (`restore_state`, flag `axe_given` in
`save_state`).

- **Slash (LMB):** `SLASH_DAMAGE` 30 to every damageable body within
  `SLASH_REACH` 2.6 m of the eye and `SLASH_ARC` 65 deg of the crosshair
  (flat angle; anything within 0.6 m counts whatever the angle), line of sight
  checked (`player._is_blocked`), once each; stagger chance 0.3. One per
  `SLASH_EVERY` 0.75 s on its own physics clock; a click that comes early is
  held and fired on the beat, as the spear's stab. Pose: WIND 0.12 / CUT 0.14
  / BACK 0.3, the hand swung round `SWING_PIVOT` in a plane through the
  up-right diagonal and straight ahead (`_swing(a)`, -25 to 205 deg), haft
  radial, edge leading.
- **Throw (Q):** 0.22 s wind-up over the shoulder, then a top-level
  "ThrownAxe" flies at 30 m/s end over end (turning about `BALANCE` 0.4 m up
  the haft), up to 30 m. Each step: a ray (stone, layer 9, hitbox mask) and a
  `FLY_RADIUS` 0.35 sphere at the step's end for bodies (with LOS). A body
  takes `THROW_DAMAGE` 30 (stagger always, `alert()`), and the axe is placed
  edge first `STICK_PROUD` 0.3 m short of the hit, haft standing up and back
  toward the thrower, and RIDES the body (`_stuck_local` relative to its
  transform) for `STICK_TIME` 2 s, then flies back at 30 m/s. Killed by the
  blow, or dead while it is in it (`_is_down`: freed, `_dying`, `_dead` or
  `health <= 0`) -> straight back. Stone or nothing in range -> straight back.
  Bodies already dying are flown through (`_fly_exclude`).
- **No weapon while it is away:** no slash, throw, berserk or guard
  (`axe.busy()` in `_start_block`), and `player.select_slot` refuses to change
  hands until it is caught (`axe_away()`).
- **Berserk (F):** `ROAR_TIME` 0.6 s planted (`player._berserk_roaring` zeroes
  horizontal velocity in `_physics_process`, before the dash branch) with a red
  shockwave ring racing out over the floor, then `BERSERK_TIME` 7 s: walking
  pace x `BERSERK_SPEED` 1.5 on the floor and in the air (`_berserk_speed`),
  and every axe time x `BERSERK_ATTACK_SCALE` 0.5 (`time_scale()`: the slash
  interval and the pose clock, so the cut, the wind-up and the catch all run
  twice as fast). `BERSERK_COOLDOWN` 20 s after it wears off. Respawn
  (`axe.reset()`) ends it and clears the cooldown. Berserk is the AXE's: the
  sword's and spear's timings are untouched by it (only the speed carries over
  if the player switches weapons mid-berserk).
- **Berserk's look:** on the floor, `shaders/berserk_ground.gdshader` on a
  3.2 m plane at the feet (two red rings, 18 flaring runes between, a glow;
  additive, `depth_draw_never`; a plain `strength` uniform on the axe's own
  material). Round the screen, hud.gd `_update_berserk_glow`: a red radial
  gradient TextureRect throbbing with a pulse, harder over the roar -- the
  beam glow's pattern, no shader. Both are gameplay information, so not gated;
  the only extra light (`BerserkLight`, red omni, 3.5 m, no shadow) and the
  roar's dust are behind `Graphics.effects`.

**Measured** in a throwaway sandbox harness (headless, real physics), 31/31:
the axe on slot 2 of a new game; one slash 30.0; spammed for 3 s, 4 slashes
0.73 / 0.75 / 0.75 s apart; an enemy behind not cut; thrown at 8 m, 30.0 after
0.45 s, stuck, moved 1.0 m with its target; switch, guard, slash and berserk
all refused meanwhile; left the target after 2.00-2.02 s, caught ~0.3 s later;
a killing throw back at once; a target killed while the axe was in it, back
at once; a miss back after 2.2 s; the roar 0.00 m/s against 4.25 walking;
berserk 6.38 m/s (x1.50); ground ring and red edges (alpha 0.7) up; berserk
slashes 0.34-0.39 s apart; 7 s; both looks gone after; refused on cooldown,
19.4 s left. Re-broken (STICK_TIME 0.5, BERSERK_ATTACK_SCALE 1.0) the two
matching checks failed (left after 0.52 s; berserk slashes 0.74 s apart).
Screenshots (Xvfb, compatibility renderer) checked the rest pose, the cut, the
axe standing out of an enforcer, and the ring and red edge. NOT benchmarked on
the P620: the cost is one additive 3.2 m plane at the feet and one blended
full-screen rect, both only while berserk.

**Traps.**
- A ray-thin throw missed a skeleton that took one step sideways in the
  quarter second the axe was in the air: hence the `FLY_RADIUS` sphere.
- Buried AT the ray's hit, the stuck axe was invisible: an enforcer's collision
  capsule sits well inside its model. `STICK_PROUD` keeps it on the surface.
- Hanging the stuck axe's haft straight down hid it behind the body's own
  limbs; it stands up and back toward the thrower now.
- The cut's hit fires in `_physics_process` while the pose advances in
  `_process`; a long frame could carry the pose straight from CUT to BACK, so a
  slash still unstruck when BACK is seen strikes then.
- An `instance uniform` on the ground plane errored under the compatibility
  renderer (this level already exhausts its 4096 instance-uniform slots); a
  plain uniform on the axe's own material does the same job.
