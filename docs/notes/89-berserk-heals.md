## 89. Berserk heals 7 a second (2026-10-20)

The user: "make the player heal 7 health per second in berserk mode."

`scripts/axe.gd` `_berserk_heal(delta)`, called from `_physics_process`:
`BERSERK_HEAL` **7.0** health a second while `is_berserk()` and not
`is_roaring()` -- the seven seconds of berserk, not the 0.6 s roar before
them -- so a full berserk restores 49. Written straight into `player.health`
(capped at `max_health`, nothing while `_dead`) with `health_changed` emitted,
as a potion's drink is (`player._update_drink`); not through `player.heal()`,
whose `healed` signal raises a HUD toast and would fire every frame.

**Measured** in a throwaway sandbox harness (headless, real physics), 7/7: at
20 health, nothing over 1 s before berserk and nothing in the roar; 7.00 a
second once it began; +49.00 over the whole berserk; nothing in the second
after; from 98, capped at 100. Clean `--quit-after 900 -- --skip-title` run: no
errors.
