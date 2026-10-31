## 140. Proels reel from a parry, strafe on guard, and fight as a pack: one blow at a time, none through another (2026-10-31)

Noah: "The Proels shouldnt be knocked back that far when parried, they should reel back,
and be stunned for a little bit, kinda like the enforcers. Give the proels the ability to
strafe, and let them attack smart to try to kill the player. If there is more than one
proel agroed on a player, they all shouldnt faze into eachother or attack at the same
time."

Fills note 139's "no way to get round a raised guard". Walk, run and every clip that
already existed came out byte for byte identical: 57 clips in, 62 out, 5 new.

### The parry (`reel`, `reel_from`)

A parry threw every enemy with `apply_knockback(away * parry_push 14, parry_stun 0.9)`: 7.07 m
on a proel. The enforcer takes the same throw with `knockback_resistance` 0.85. player.gd
`_on_guarded` now asks `attacker.has_method("reel_from")` first, so only proels change.

`reel`, 1.5 s, `tools/anim_sword_skeleton.py` `reel`, a blow's clock (`Blow(1.3, 1.1)`), so it
ends on idle_fight's first frame at no speed. The arm is flung wide and the chest goes back
after it; three steps back and one to set the stance (rear foot first, so the legs do not
cross); hunched with the blade hanging and the clang ringing out of the elbow at 11 Hz; the
guard hauled back up. `root` steps it back `REEL_BACK` 1.08 m, driven through `_blow` and
`_slide` like a blow, so its feet stay planted.

`reel_from`: ends whatever it was doing, faces the parrier, stuns it `REEL_TIME` 1.5 s (the
enforcer's `PARRY_STAGGER`), and blocks both blows until the reel is over. Then it is wary:
`REEL_WARY` 0.8 s more of circling before it goes in. While reeling `apply_knockback` is
ignored, so the stagger roll cannot cut short the opening the parry earned. The reflected
half of the blow and any hits still land. `REEL_TIME` and `REEL` are the same number: change both.

### Strafing (`strafe_l/r/f/b`)

`anim_sword_skeleton.py` `strafe`: 1.0 s loops authored for `STRAFE_V` 1.5 m/s. Each foot is
the walk's own `foot_at`, run along the way it is going, from where the fighting stance has
it. So the right foot stays ahead and the left behind, each on its own line, and they pass
as a walk's do. A true step-together only makes 0.6 m/s on legs this long, because a cycle
covers only the difference between the widest and narrowest stance. Hips turn 0.33 and feet
0.42 of the way toward the going, and the chest turns back by as much, so the blade stays on
them. `strafe_b` is `strafe_f` played backward, so the toe lands first.

`_update_locomotion` plays them while `_circling`, at `speed / STRAFE_SPEED`, 0.6-1.75.
`_strafe_clip` keeps the clip it has until the other axis is 1.4 times more of the speed, or
a diagonal flickers. `_switch` starts them at `STRAFE_FROM_GUARD` 0.3, with the feet nearest the
stance. `_on_guard` counts strafes and `reel`, so `out_g_*` still takes it off into a run.

### The fight (`_chase`, `_circle`, `_wants_blow`)

Close in it no longer stands and swings. `_chase` is enemy.gd's hook. Further than the ring
plus `RING_SLACK` 1.6 m, out of sight or more than 1.2 m above or below, it returns false and
the ordinary hunt brings it up. Inside, it circles until `_wants_blow`, with a blow ready:

- they are open (`_open`, note 139), or it is `BEHIND` them, 1.9 rad off where they face;
- they are nearly dead;
- its wait is over: after an exchange it works round them `CIRCLE_SHARE` 0.65 of the time, for
  0.7-2.2 s, and coming up on them it sizes them up half the time;
- a raised guard in front holds it back for up to `FLANK_TIME` 1.6 s, circling at `FLANK_SPEED`
  2.2 m/s toward where the guard does not cover (`_blind_way`), then it goes in anyway.

A swing starting within `EVADE_GAP` 2 m: half the time it steps back for `EVADE_TIME` 0.42 s, then
`_open` sends it straight back in as the swing ends. It keeps to `RING_CLOSE` 1.7 m (edge to edge,
just out of reach) alone, `RING_WAIT` 2.7 m with others on the player. It accelerates at
`STRAFE_ACCEL` 10 here, not 22: it weighs a lot. On a wall it turns back the other way.

### Taking turns (`_take_turn`, `on_turn`, `_turns`)

`_turns`, static, player instance id -> {who, free_at}. So co-op has one turn per player. A
proel takes the turn when it sets off and holds it to the end of its chain (`on_turn`: wind-up,
swing, or a recovery that may still chain, or up to `TURN_CLOSE` 2.2 s getting there). A stun ends
a turn. The next may go `TURN_GAP` 0.35 s after that swing ended, or `TURN_PARRIED` 0.2 s after a
parry: its fellows step in. `_pick_attack` asks too, so nothing swings without the turn.

Several asking at once are weighed (`turn_score`): longest since its last turn, furthest from
where they face, nearest. Waiters spread round the player (`_spread_way`: away from the
nearest fellow on the ring, if nearer than their share of the circle) and otherwise circle to
the blind side, so two end up either side of them and the one behind goes next.

### Keeping apart (`_keep_clear`)

Why they went through each other: capsules are far narrower than the body and blade, and on
the march a patrol's members have collision exceptions (patrol.gd, note 125). `_look_for_fellows`
keeps `_pack`, the proels within `PACK_REACH` 12 m, every `PACK_EVERY` 0.25 s. `_slide` then takes
out velocity toward a fellow nearer than `SPACE_FIGHT` 1.7 m (`SPACE_WALK` 1.2 walking about), and
parts them with a `move_and_collide` of its own, `SPACE_PUSH` 3.4 m/s at touching. One in a blow gets
`SPACE_IN_BLOW` 0.25 of that: the one not swinging gets out of the way. Proels only; other kinds
are not pushed.

### Measured

Throwaway windowed sandbox harness, deleted. A standing player in god mode, proels' health
held up, 40 s each.

```
parried proel       old throw 7.07 m       now 1.11 m at the furthest, 1.48 s stun,
                                           next wind-up 2.47 s after the parry
one proel           13 swings, 2.77 s apart, least 1.82; 17% of frames on strafe clips
two                 19 swings, 1.97 s apart, least 1.67; 16 of 19 from the side or back
three               19 swings, 2.01 s apart, least 1.67; 17 of 19 from the side or back
guard held, 40 s    12 swings, 11 from outside the guard's arc
```

```
                      two in wind-up/attack   two in attack   closest   frames under 1.2 m
three                 0 of 2392               0               1.66 m    0
three, control        917 of 2352             83              0.98 m    639
sixteen               0 of 1314               0               1.40 m    0
sixteen, control      1179 of 1271            383             0.68 m    20529
```

The control switched `_take_turn` and `_keep_clear` off, so these tests can fail.

**Corridors**, three spawned round a random navmesh point, 28 s each, 3 runs: two fought
normally, 12-13 swings, 0 overlaps, closest 1.32 and 1.90 m. In the third the proels never
reached the player and only one swing came, most likely a shut door or bars between them:
they pivoted and started off, and two jammed capsule to capsule at 0.78 m for 114 frames. Not
looked into further, and that spot is the one way they can still touch.

**Stepping out**: 1 of 5 swings timed to catch it circling, and only 5 such moments came in
30 s. It is rare: a player is usually swinging while it is mid-blow, and it is committed then.

**Stress**: 4 proels hit, shoved, parried and teleported at random for 25 s, then all killed:
no errors. **Clean run**: `--quit-after 1500 -- --skip-title --no-intro`, windowed: stderr empty.

**Cost**: in the crowd of 16, 76.9 fps against 70.1 with it off (the off case is swinging far
more), physics 4.64 against 4.63 ms. No `--bench`: nothing new is drawn. GLB 20.40 -> 20.97 MB.

`[reel]` in `--check`: ends 0.0000 off the guard, the tip stopped; worst jolt 0.077 at the tip as the arm is flung, frame 8;
legs 0.03 m past reach at worst, blade 0.34 m clear of the body, tip 0.15 m off the floor at its
lowest. `[strafe]` loops at 0.0000. Upper-arm roll in the strafes under 0.2/f, wrist turn 0.

### Traps

- **`_action_held` polls the physical keys.** `Input.action_press(&"block")` does nothing and
  `_check_block` drops the guard the next tick. A harness sets `_blocking` and `_block_since`
  each tick from `physics_frame`, which runs before the bodies do.
- **A push kept in `velocity` builds up.** enemy.gd eases `velocity` toward what it wants and
  keeps the rest, so adding a parting speed every tick adds to last tick's. It is a separate move.
- **The stance's stagger is no use going straight ahead**: feet 0.71 m in front of the hips. The
  two lines close up with `abs(sin)` of the direction.
- A foot's landing settle is 0.12 s long. A step ending inside that of the clip's end leaves the
  foot pitched at the end: the reel's last step ends at 1.16.
- The tip of a blade this long reaches the floor from a straight hanging arm: -0.08 m at first.
  The hang keeps a swing of 20 degrees and a bent elbow.
- A proel spawned in the sandbox on a level does not notice a player round a corner, so
  `engaged` stays false and a test reads as nothing happening. Alert it.

### Not done

- A blow in progress is committed: no stepping out of a wind-up or a recovery.
- Other enemy kinds still go through proels, and proels through them, as far as the capsules let.
- Only the proels use the pack and the turns. A proel and an enforcer can still swing together.
- Strafe clips switch by crossfade: reversing direction is a blend, not a step.
- The stagger's switch out of a swing (note 139) and the reel's are inertialized blends: `reel`
  starts from the guard, not from the blow it interrupts.
- Sounds, as in note 137.
