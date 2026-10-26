## 110. The needle dash first and seen; the booth route's scene waits until they are down; a bigger claw (2026-10-25)

The user:
- "I didnt see the spear dash thing."
- "The cutscene shouldnt start for the player until he is out of the control
  room, if that ending is played out."
- "Make the claw bigger."

### The needle dash (`surgeon_boss.gd`)

Why it went unseen: he picked moves by distance and chance, and the dash came
only at range (over 4.5 m, 60%). After the scene he stands 1.5-2.4 m away, so
it hardly ever came. When it did, it was 0.65 s of wind-up and a 0.32 s blur.

**The deal.** He no longer rolls for a move. He deals his three round in turn
(`_deck`, a fresh shuffle each round), and the needle always comes first in
the fight.
- The spin waits until they are within SPIN_NEAR 3.6. If he has walked at
  them for DEAL_WAIT 3 s without getting that close, he gives it up for the
  next card.
- The needle and the slam go at any range.

**Too close for the needle.** If they are within DASH_CLOSE 3.5 when it starts
(decided in `begin_move`), he hops back DASH_BACK 2.6 m in 0.35 s first, then
winds up. That gives the run room to be seen.

**Seen.**
- DASH_WIND is 0.65 -> 0.85 s; DASH_TIME is 0.32 -> 0.4 s.
- The needle's emission ramps 0.6 -> 7 over the wind-up and blazes at 9 on
  the run (`_needle_glow`).
- A cyan light at its tip (`_needle_light`, range 2.5) lights the floor
  round him.
- The run leaves a streak of light from where it started to where it stopped
  (`_streak`: an additive bar fading over 0.5 s, plus sparks).
- The glow resets on the end of the move, a stagger and his death.

### The booth route's scene (`surgery_control.gd surgeon_rises`)

After the lever he still waits for the claw to come home (the table DEAD).
Then he lies where the kick left him until a player is out of the booth:
- below the booth floor by 0.6 m (so not on the landing either);
- in the hall;
- not dead and not in a cutscene (`_out_of_booth`).

Only then does `_claim` play for that player.

`_claim`'s walk now ends 2.2 m from them on the booth route (1.5 m from a
knocked player, as before). The old "short of under the booth window" spot is
gone, since they are no longer up there.

### The bigger claw (`surgical_table.gd`)

- CLAW_SCALE 0.95 -> 1.3, and CLAW_LEN 1.55 -> 2.12 with it.
- The hitbox scales with it.
- GRAB_RADIUS 1.3 -> 1.45 and SHAKE_RADIUS 2.6 -> 2.9.
- The thrown piece's claw capsule (`surgery_piece.gd CLAW_RADIUS`)
  0.85 -> 1.1.
- Its working height over the table (WORK and STRAP) follows CLAW_LEN.

A player it carries has to clear the vats under the longer claw, so it carries
higher:
- ROOT_Y 6.25 -> 6.4;
- CARRY_Y 5.75 -> 6.1.

On his back, the claw's poses are scaled to the new size:
- legs x0.87, so the fingertips stay on the floor for the spin;
- back x0.65;
- carry x0.6.

### Measured (throwaway harness, headless; deleted)

12/12, three times in a row:
- the claw model at scale 1.30;
- it catches and carries; feet at least 2.43 m over any vat passed (the vats
  are 1.97);
- booth route: lever pulled, still in the booth 9 s later: no scene, the
  table DEAD, him still DOWN;
- moved down into the hall: the scene starts at once; the fight in 27.8 s;
  he stops 2.4 m off;
- his first move is the needle; its light up to 4.2 (energy 9); the streak
  is there;
- the player put 1.5 m in front of him: by the wind-up he is 3.4 m off;
- the needle, the spin and the slam all come round within 30 s.

The first version of the hop-back never fired: it decided on `_mt < 0.01`, but
`_mt` has already gained a frame by the first `_dash` call. The harness caught
it, and moving the decision to `begin_move` fixed it.

Windowed screenshots:
- the bigger claw on the live arm over the vats;
- him winding up, the needle blazing cyan and lighting the floor, the bigger
  claw up over his shoulder;
- the streak along the run, the hit landing (28);
- him from the front with the claw on his back.

### Not done

- Sounds for the dash (a charge and a whip).
- Balancing the fight.
