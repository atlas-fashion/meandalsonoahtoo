## 109. The claw home when it dies; the surgeon takes it -- two openings to his fight; a stand-in body; his three moves (2026-10-25)

The user:
- "The Claw should revert to over the table when powered off."
- "Right now there are 2 ways to power off the claw. There should then be 2
  ways that the surgeon fight starts. The first should be an add on to the
  climb out of the underground part. The surgeon should knock the player down
  as hes climbing out of the powering room, and the surgeon should walk over to
  the table, stand on it, and take the claw off of the robot arm and put it on
  his back. The cutscene should be dramatic as the surgeon walks up to the
  player after the player was knocked down, and saying 'who are you' very
  slowly. The player should then quizically ask who the surgeon is, and the
  surgeon should say 'No matter, you will die for what you've done'. then
  starting the battle."
- "The surgeon should not be the model that was created. Make a temporary
  model. It should have robotic arms and legs."
- "Its attacks should be a 'spear dash' with a precision needle bionic hand, a
  fast spin using all 4 apendages, while the surgeon uses the claw on his back
  as legs, and a delayed jump onto his back, slamming the claw into the
  ground."

The second opening was not described. **Chosen:** the booth route (the lever)
plays the same scene from the point he gets up -- to the table, the claw, to
the player, the same three lines -- since he needs the claw for his moves.

### The claw home (`surgical_table.gd _die_out`)

The power going, the gantry runs back over the table (`_b_goal` zero at 0.35
pace). Once there (or 2.6 s in), the arm pays out until the claw hangs DEAD_TIP
0.55 over the table top (`_dead_len`). The fingers loosen, the lights fade over
4 s, and DEAD comes at DEAD_TIME 4.5 once it has settled. There is no crash
into the floor any more.

`set_dead_now` (a save) puts it there too, wherever an old save had it lying.

`take_claw()` (only once dead) hands the claw node over and sets
`claw_taken`. The table then stops posing the claw, its fingers, its eye light
and its glow; the arm ends empty at its wrist.

### The two openings (`surgery_control.gd`)

**The crystal route** (`ambush`):
- surgery_power.gd `_surgeon_leaves(true)` -- in the dark of the climb out --
  calls `leave(at)`, which brings him down to wait beside the hatch, 1.7 m past
  where they step off, facing it (SCRIPTED, so nothing starts the fight
  early). It returns whether he came.
- After `end_climb`, `ambush(p)`: a backhand ("strike" pose), sparks, a shake.
  The player is thrown back 1.1 m and put on the floor in a cutscene
  (`scene_lean` (0, -1.3, 0.35), `scene_frame` roll 24, looking up at him).
- Then `_claim(p, true)`.

**The booth route** (`surgeon_rises`): after the lever, it waits for the table
to reach DEAD (the claw home), then `_claim(nearest player, false)`. He gets up
from where the kick left him first.

**`_claim`** (everyone in the cutscene, letterboxed, their views following his
eyes via `_process_look`):
1. He walks (`walk_to`, round the vats on his grid) to the table's nearer long
   side.
2. Hops up onto it (`hop_to`).
3. Reaches up ("reach"); `take_claw` -> `mount_claw`, with a shake.
4. Hops down toward them.
5. Walks to them: 1.5 m off and looming over them where they lie; or, the
   booth route, 2.4 m short of under the booth.
6. The lines (scripts/subtitles.gd, a new typed-subtitle overlay over the
   letterbox):
   - THE SURGEON: "Who...   are...   you..." at 0.15 s a letter;
   - YOU: "...Who are you?";
   - THE SURGEON: "No matter. You will die for what you've done."
7. The knocked player gets up, the cutscene ends, and `begin_fight(true)`
   starts the fight at once.

Measured: about 32-36 s from the lever or the climb to the fight (the walk
across the vats is most of it).

**Saves and resets.** `_arm_him()` puts the claw on his back at once, from:
- a restore (`restore_boss`, alive or dead);
- a world reset (`reset_boss`; from SCRIPTED or DOWN he waits at his spot, the
  fight starting when a player comes into the hall, no scene);
- a fight begun without the scene.

`leave()` with no spot still means waiting at his spot, armed.

### The stand-in body (`surgeon_boss.gd`)

The Meshy surgeon is no longer used (its preload and clips are gone from
surgery_control.gd). Instead, `_build_body` makes a figure from primitives:
- a dark coat and skirt, a leather apron, brass bands;
- a bald head, a steel jaw-plate, red-lensed goggles;
- iron arms and legs: brass ball joints (with a faint glow, so they read in the
  dark) and steel shafts (half-metallic -- mirror steel read black in the hall);
- a three-fingered clamp for the left hand and, for the right, the long
  emissive precision NEEDLE;
- a socket high on his back for the claw.

He faces +Z. Every joint is a Node3D. Named poses (`_pose_angles`: stand,
work, alert, reach, strike, loom, dash_wind, dash, spin, crouch, tuck, back,
down, dead, dizzy) are eased each frame (`_animate`), with a walk cycle on top.

The old API stays: `play("die" | "alert" | "work")` maps to poses, and
`hold_end` snaps one.

**The claw on his back** (`mount_claw`): reparented to the socket, its old
hitbox off, its eye lit. Its modes:
- **carry:** folded up over his shoulder (x0.7);
- **legs:** let down and lengthened under him (x1.1), fingers splayed -- the
  spin;
- **back:** out of his back fingers-first -- the slam, the fingers shutting as
  it lands.

### His three moves (`_fight`, `begin_move`)

Between moves he walks at the nearest player (WALK_SPEED 2.2, his grid round
the vats) and rests REST 0.8-1.6 s. Then by distance: over 4.5 m, DASH 60% /
SLAM; under 3 m, SPIN 55% / SLAM; otherwise any of the three. Every number is
a first guess, at the top of the script.

- **DASH:** DASH_WIND 0.65 s, crouched, needle drawn back, turning onto them
  (the parry cue opens 0.3 s before the end of it). Then DASH_SPEED 17 for
  DASH_TIME 0.32 s straight through: DASH_DAMAGE 28 to whoever the needle's
  line passes within DASH_REACH 0.9 of. Stone or a vat ends it. DASH_RECOVER
  0.6.
- **SPIN:** SPIN_RISE 0.45 up on the claw (the cue 0.25 before), then
  SPIN_TIME 1.3 at SPIN_RATE 15 rad/s, arms and legs out, drifting after them.
  Anyone within SPIN_REACH 2.5 takes SPIN_DAMAGE 12 every SPIN_EVERY 0.3. Then
  down, and dizzy SPIN_DIZZY 0.7.
- **SLAM:** a crouch (SLAM_CROUCH 0.35); a leap SLAM_HEIGHT 3.4 up (0.45); a
  hang SLAM_HANG 0.55, turning onto his back and still following them (the cue
  covers the hang and the drop); down in SLAM_DROP 0.22 claw-first. The table's
  floor-crack effect plays; within SLAM_HIT 2.0, SLAM_DAMAGE 34; anyone
  unguarded within SLAM_KNOCK 3.8 is knocked down. Then on his back SLAM_LIE
  1.4 (blows land SLAM_EXPOSED 1.5x) and up in 0.6.
- **Parries:** a parry of the needle or the spin -- through `_hit`, or the
  player's `apply_knockback` -- staggers him (STAGGER_TIME 1.4, "dizzy"), shoved
  back.

### Measured (throwaway harness, headless, both routes; deleted)

Booth route 10/10, three times:
- the stand-in (30+ primitive parts);
- after the lever, the claw back over the table (0.00 m off);
- him on the table, the claw on his back;
- the three lines in order;
- the fight on;
- DASH 28 damage; SPIN 24-36; SLAM 34 and knocked down;
- a parried needle staggers him;
- killed: the bars down.

Crystal route 12/12, three times:
- the crystal out, the machine off, the claw home;
- climbing out: knocked down (the view at -1.30);
- the claw taken, the lines, the fight, control back;
- the moves as above.

One early run missed the spin and slam: the test's player was standing behind
a vat. Placing them with a clear line fixed it.

Re-broken (`take_claw` handing nothing over), the claw check fails, as it
should.

Windowed screenshots:
- the claw hanging low over the table;
- him from the front (red goggles, the needle, the claw up over his shoulder)
  and from behind;
- the dash lean, the spin (arms out, up on the claw), the slam (on his back on
  the claw).

His iron read near-black at first and was brightened.

### Not done

- A real model and animation for him (this one is a stand-in, as asked).
- A voice: the lines are subtitles.
- Sounds for his moves.
- Balancing the fight.
