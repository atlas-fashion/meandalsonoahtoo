## 148. The proels strike half again as fast, and run one blow into the next (2026-10-31)

The user: "Make the proels attacks faster. More like a short swordsman. Make all attacks seamless like the enforcer attacks." Asked: about 1.5x.

### Faster: one number, baked

There is still one tempo, as in note 142, now 1.5 times it.
- `BLOW_TEMPO` in prosthetic.gd and `TEMPO` in tools/anim_sword_skeleton.py both go from 1.15 to 1.725.
- Every blow and link is re-baked, along with both cooldowns.

| | was | now |
|---|---|---|
| light wind-up / swing / recovery | 0.78 / 0.21 / 1.13 s | 0.52 / 0.14 / 0.75 s |
| whole light blow | 2.12 s | 1.41 s |
| heavy wind-up / whole blow | 1.09 / 2.96 s | 0.72 / 1.97 s |
| link between blows | 0.65 s | 0.43 s |

What doesn't change:
- The keys are unmoved, so each blow's proportions (its weight) are as before.
- The gaits, strafes, reel and the leap are not blows and don't take the tempo. The leap's `LEAP_*` timing is the jump, as in note 146.
- Every clip but the blows, links and their `out_*` came out the same.

The re-bake took 33 s (`blender -b models/source/sword_skeleton/sword_skeleton.blend -P tools/anim_sword_skeleton.py`).

### Seamless: in again sooner, and on through the links

The enforcer feels seamless because it never stands between moves: each swipe chains into the next, and it walks off at a matched phase. The proels already have that machinery in their links and `out` clips (notes 138, 139). What made them feel stop-start was how rarely they used it, and how long they circled between exchanges. Changes in `sword_skeleton.gd`:
- **Chaining.** `CHAIN_SHARE` 0.4 -> 0.65, `CHAIN_ON_HIT` 0.75 -> 0.85 and `CHAIN_ON_GUARD` 0.5 -> 0.7. A light blow now mostly runs on through its link into a second, and often a third (`CHAIN_TIRED` and `CHAIN_MOST` are unchanged).
- **Resting.** `CHAIN_REST` 0.7 -> 0.3 s per blow added.
- **Circling.** After an exchange it circles a third of the time for 0.35-1.1 s (`CIRCLE_SHARE` 0.65 -> 0.35, `CIRCLE_LEAST` 0.7 -> 0.35, `CIRCLE_MOST` 2.2 -> 1.1). The rest of the time it goes straight back in.

Pack turn-taking, flanking a raised guard, evading and the leap are unchanged.

### `[reach]` sweeps between frames now

At the new tempo the point moves up to 64 m/s, over a metre per 60 fps frame. `reach_report`, which sampled frame by frame, reported `slash_2` as MISSES. The game doesn't sample that way: skeleton_sword.gd `strike` sweeps from last tick's blade in five steps. The report now sweeps the same way, in four steps from the frame before.

Every blow lands inside its window: lights at A+0.09-0.11 of a 0.14 s window, heavy at A+0.11 of 0.17.

### Measured

A headless harness put one proel 5 m from a still player in a corridor for 30 s. The player had 100,000 health instead of god mode, so the hits register.

| | blows | chained | landed | between wind-ups |
|---|---|---|---|---|
| note 146 | 12 | 6 | 10 | 1.5-1.6 s chained, 3.8-4.4 s otherwise |
| now | 19 | 8 | 19 | 1.0-1.05 s chained, 2.0-2.3 s otherwise |

### Traps

- **A test script that preloads an enemy script fails to compile.** enemy.gd names the `Sandbox` autoload, which doesn't exist yet when `-s` compiles the script. Load it at run time.
- **God mode stops damage before any signal.** To count hits, raise `max_health` and `health` instead.
