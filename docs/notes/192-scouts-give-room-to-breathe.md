## 192. Scouts give room to breathe (2026-11-16)

The user: "Scouts need to give the player a bit of time to breathe. Make their
attack chains a little less aggressive, but still super smooth."

### Why they never let up

- **Openings ended every breath.** A scout punishes an opening at once
  (`_opening`: knocked down, drinking, or within 0.45 s of the player's swing
  ending). Note 190's combat has the player swinging all the time, so nearly
  every breath was cut to nothing. The real wait after a move averaged 0.37 s,
  and could be as short as 0.13 s.
- **Chains were mostly "open" chains.** `CHAIN_CHANCE_OPEN` 0.75 applied
  almost always for the same reason. In 40 s against a swinging player, 10 of
  19 moves ran straight into a second.

### The change (scout.gd)

- **A longer breath:** `CLOSE_PAUSE` 0.2-0.6 -> 0.65-1.15 s. After a chain
  (two moves back to back) it is longer, `CHAIN_PAUSE` 1.2-1.7 s. Coming in
  after being spotted keeps the old quick start, `SPOT_PAUSE` 0.2-0.5 s.
- **Openings shave a breath, they no longer end it:** an opening cuts the
  breath to no less than `BREATH_FLOOR` (70%) of what was rolled
  (`_breath_floor`). The same floor applies to its dart back in after
  stepping out of a swing.
  - Broken off during its wind-up (it had not struck yet), it owes no breath,
    as before.
- **Fewer chains:** `CHAIN_CHANCE` 0.3 -> 0.18, `CHAIN_CHANCE_OPEN`
  0.75 -> 0.45. Still never three in a row.
- **Smooth:** the breath is spent circling as before, never standing.
  Fresh from a move it keeps 0.5 m further off (circle distance 1.6 -> 2.1 m
  edge to edge), easing back in as the breath runs out. The shift goes
  through its acceleration, so there is no lurch.

The moves themselves (tri-stab, swipe, dash, their timing and drive) are
untouched.

### Measured

The real level, one scout against a god-mode player who swings every 1.5 s,
40 s, two runs:

|                     | before | after       |
|---------------------|--------|-------------|
| breath between moves | 0.37 s avg, 0.13 min | 0.69-0.71 s avg, 0.33 min (a wind-up break-off) |
| chains              | 10     | 2-5         |
| stabs thrown        | 29     | 22-23       |
