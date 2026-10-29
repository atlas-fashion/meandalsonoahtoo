## 129. The scout tuned: tougher, faster, a driving tri-stab, two-move chains, and it reads the player (2026-10-29)

The user: "The scouts should have a little more health, they should be faster,
and they should attack faster. When the scout performs the 3 stab attack he
should move swiftly forward with each stab. He should be able to close the
gap between himself and the player. He should be able to chain 2 attacks
together, but not all the time. He should attack and move smart, with the
goal of killing the player."

The coordinator added: keep scouts weaker than enforcers.

Everything here is in `scripts/scout.gd` unless noted. Note 127 describes
the scout this tunes.

### Tougher and faster

| | before | after |
|---|---|---|
| health (an enforcer has 240) | 110 | 160 |
| hunting speed | 4.6 m/s | `HUNT_SPEED` 5.5 m/s |
| closing in | 2.3 | 3.2 |
| patrol | 1.3 | 1.5 |
| search | 2.3 | 2.8 |
| circling | 1.4 | 1.9 |
| acceleration | 16 | 24 |
| turning | 7.5 rad/s | 9.5 rad/s |
| turning in a move | 9 | 11 |

### Attacks faster
- **Every move's clock runs at `TEMPO` 1.25** (`_move_t += delta * _tempo()`),
  so all wind-ups, blows and recoveries are 20% shorter. The body plays
  `move_t`, so it follows.
  - A tri-stab takes 1.40 s, against 1.75.
  - The body's move springs are stiffer (scout_body.gd: spear omega 26 -> 31,
    body 15 -> 18).
  - **Exception**: the swipe's sweep itself (move seconds 0.56-0.86) runs at
    1x. Quickened, its front hand passed 20 m/s.
- `CLOSE_PAUSE` between close moves: 0.45-1.1 s -> 0.2-0.6 s.
- Swipe cooldown 3.2 -> 2.4 s; dash cooldown 4.5 -> 3.2 s.
- `DASH_SLIDE` 0.7 -> 0.8 move seconds (0.64 s real), so the burst keeps its
  speed.

### The tri-stab drives in (`STAB_DRIVE`, `_drive_step`)

Each stab has a step: [from, to, least, most] in move seconds and metres.

The step's length is set as it begins: as far as brings the point
`STAB_OVER` 0.25 m past the player's middle. The point is at `STAB_POINT`
2.05 m ahead of the body at full extension. Each step is clamped:
- stabs 1 and 2: 0.25 m to 1.1 m;
- the lunge: 0.45 m to 1.4 m;
- and never into the player.

It opens with a tri-stab from up to `STAB_GAP` 3.4 m, edge to edge (1.9 m
before); the stabs cover the rest.

### Chains (`CHAIN_AT`, `_try_chain`)

At a move's chain point it may go straight into another, without the pause:
- the chain points are just after the last blow (tri-stab 1.42, swipe 1.02,
  dash 1.32 move seconds);
- the chance is `CHAIN_CHANCE` 0.3, or `CHAIN_CHANCE_OPEN` 0.75 when the
  player is open (below);
- the second move is chosen for where they are: a swipe or tri-stab close
  in, a tri-stab within `STAB_GAP`, a dash from 5-9.5 m;
- a chained move never chains again (`_chained`), so two at most.

### Reading the player

- **Openings** (`_opening`): the player knocked down, drinking, or within
  0.45 s of a swing ending.
  - It attacks at once (no pause), and chains at 0.75.
  - Against someone on the floor the point is aimed low (`_feed`: their
    height taken as 0.35 m, not 1.0 m).
- **Their swings** (`_watch_swing`, read once a tick from player.gd
  `_attacking`):
  - A swing starting within 2.3 m makes it step back and a little aside
    (`_evade`: `EVADE_TIME` 0.32 s at `EVADE_SPEED` 4.2 m/s,
    `EVADE_CHANCE` 0.55).
  - This can happen in its own wind-up or recovery too, breaking the move
    off. Between its blows it is committed.
  - It comes straight back in as it lands.
- **A raised guard in front** (`_guard_front`: blocking, and the scout within
  `GUARD_FRONT` 60 degrees of the player's facing):
  - It circles to their side at `FLANK_SPEED` 2.8 m/s for up to
    `FLANK_TIME` 1.6 s, then strikes. A guard covers only the front
    (player.gd `_guard`, `block_arc`).
- **Backing away** (`_fleeing`: moving away from it at over 1.5 m/s): the
  dash roll is 0.9, not 0.6.
- Counters for the tests: `chains`, `evades`, `flanks`.

### Measured

Throwaway windowed sandbox harness (deleted). Last run, 12 of 13 at
the thresholds it was written with; the miss is the hand speed below:
- health 160;
- hunting top speed 5.50 m/s;
- from 3.6 m the tri-stab drove 2.25-3.18 m in, and its stabs landed (6-7
  blows);
- a tri-stab takes 1.40 s;
- in 40 s of fighting, 8-12 of 27-29 moves were chained, never a chain on a
  chain;
- with real player swings (`_start_attack`), it stepped out of 4-5 of 10;
- against a held guard: attacks from the side 6-7, from the front 0-1.

**The miss:** the harness flagged any hand or head moving more than 0.30 m
in one frame. The fastest was the swipe's front hand at 0.27-0.30 m (about
18 m/s, mid-sweep, smooth across frames). The last run read 0.302 m, just
over, and that run counts as a FAIL. Before the sweep was put back at 1x it
was 0.36 m.

The evade test read 0 of 10 when it set `player._attacking` by hand (the
player's own code clears it). The first real swings showed why: the scout
was nearly always mid-blow, and so committed. Letting it break off in its
recovery as well as its wind-up gave the 4-5 of 10.

**Bench** (RTX 3060, 3440x1440, `--bench`, editor open; seed of the run,
21 scouts):

```
                 overall fps   worst p99 (ms)
note 127 (0.08)      96.9      18.06 (surgery)
this                 94.9      16.67 (chest room)
```

The two are within the run-to-run noise seen in note 127.

A clean `--quit-after 1500` windowed run had no errors or warnings.
