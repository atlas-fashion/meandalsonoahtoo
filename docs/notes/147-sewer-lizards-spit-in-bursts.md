## 147. The sewer lizards spit in bursts of four, then rest (2026-10-31)

The user: "The sewer lizards should shoot in a fast burst of 4 hits, and stop for a while."

Before, each lizard reared up (`SPIT_WINDUP` 0.24 s) and spat one gob every `SPIT_EVERY` 1.0 s.

Now (`scripts/sewer_lizard.gd` `_chase`) it does this:
- It rears up once, for the same `SPIT_WINDUP`.
- It then fires a burst of `BURST` 4 gobs, `BURST_GAP` 0.12 s apart. It stays planted and turned on the player, and aims each gob afresh with the same lead as before.
- It waits `BURST_REST` 2.8 s from the burst's end before it can rear up for the next.
- If the player gets out past 1.2 x `SPIT_RANGE` mid-burst, the burst stops short.

The cycle is about 3.4 s for 20 damage (4 x `SPIT_DAMAGE` 5). Before, it was about 3 gobs, or 15 damage, in the same time. The head snaps forward on every gob (`_rear`), so a burst reads as four quick jerks.

`SPIT_EVERY` is gone. The goo itself (goo.gd) is unchanged.

**Measured** (headless harness, a lizard in the sewer, the player held 7 m off on a clear line). The gobs left at:
- 0.57, 0.70, 0.83, 0.97 s
- 4.04, 4.17, 4.31, 4.44 s
- 7.53, 7.66, 7.80, 7.93 s

That is bursts of four 0.13 s apart (the 0.12 s gap rounded up to whole physics ticks), every 3.5 s.
