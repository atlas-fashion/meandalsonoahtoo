## 191. Every blow shoves: the knockback made to show (2026-11-16)

The user, after note 190: "the knockback didn't seem to come into effect at all".

### Why it didn't show

- **Enemies.** Note 190 handed the player's blows to `knock`, at each swing's
  `stagger_chance` (0.4 for a cut, 0.1 for a jab). Only a stagger moved the
  body. Any other blow went into enemy.gd's `_knockback`, which is applied only
  while stunned or staggered and just decays otherwise. So most cuts moved
  nothing. The template shoves on every hit, even mid-attack.
- **The player.** The slide worked, but the template's 3 m/s (recovery 8)
  slid 0.35 m, small enough to miss.

### The fix

- **combat/knockback.gd `shove(body, push_velocity)`:**
  - The first blow gives the body a Knockback child with `drive` set. It moves
    its parent itself (`move_and_collide` each physics tick, the template's
    exponential slide), whatever the body's own movement does, so it works for
    every enemy kind without touching their `_slide`s.
  - How much a body takes: its `knockback_taken` (mimic 0, the Remnant 0, the
    surgeon 0.25), else 1 - `knockback_resistance` (a scout takes 0.85).
  - Nothing slides once `_dying`, `caged` or `hauled_by`.
- **player.gd `_hit_target`:** a blow that does not stagger shoves, along the
  blade's way, at the weapon's knockback × the swing's multiplier. A stagger
  still throws as before (no double push). Poise is untouched: the shove never
  interrupts.
  - Distances (≈ speed × taken / 8): a cut 5.5 m/s ≈ 0.7 m, the heavy swipe
    8.8 ≈ 1.1 m, a jab 3.5 ≈ 0.45 m, the lunge 5.25 ≈ 0.65 m.
- **player.gd `blow_knockback` 3 -> 5:** an enemy's blow slides the player
  about 0.6 m (×0.5 blocked, none parried).

### Measured (throwaway harness, real level, default seed)

- 3 of 3 cuts that landed on a scout without staggering it shoved it, peak
  4.67 m/s (5.5 × 0.85). The two cuts that didn't land were left out (no
  health lost).
- A blow on the player: the slide started at 5 m/s and carried the player
  0.58 m.
- A `--quit-after 2400 -- --skip-title` run: no errors.

### Trap

- **A blow inside the player's grace window is not taken at all, shove
  included** (`invulnerable_time` 0.6 s). The first real-level check read 0.04
  m because a scout had just struck. Clear `_invulnerable_until` before testing
  a blow.
