## 141. Proels hunt in three gaits; their blows hit harder (2026-10-31)

Noah: "When the proels are targeting a player, the walking animation shouldnt be identical
between proels, just for some differentiation. The sword swipe should do more damage."

Read as the proels' sword, not the player's. Walk, run and every clip that existed came out
byte for byte identical: 62 clips in, 92 out, 30 new. Supersedes note 93's 12 and 26.

### The damage

`attack_damage` 12 -> 20 (slash_1/2/3), `HEAVY_DAMAGE` 26 -> 36 (`prosthetic.gd`). For comparison:
enforcer 22, decrepit swipe 25, hammer 30. Everything that weighs a blow reads these, so
`_finishes`, `_worth` and `_press_on` follow. A block still takes 10% (2 and 3.6). A parry
reflects half, so a parried proel now loses 10 or 18 of its 100, not 6 or 13.

### The gaits (`_style`, `STYLES`)

A proel after someone moves one of three ways, so a pack does not move as one. "Targeting" is
mostly a run and, close in, strafing, so both vary, as well as the walk it uses at a low
speed. The silhouette is what tells them apart: where the blade is carried.

```
""        walk, run as they were          the blade out in front
"_low"    long bent stride, head out      swept back and away; guard pointing down in front
"_high"   upright and quick, shoulders    held up beside its head; guard raised
          rolling
```

`tools/anim_sword_skeleton.py` `WALK_LOW`, `RUN_LOW`, `WALK_HIGH`, `RUN_HIGH` are the ordinary
gait dicts, so each foot still covers the ground at `WALK_V` or `RUN_V`. `STRAFE_LOW` and
`STRAFE_HIGH` are added to the guard by `strafe(deg, st)`: their own step, height, lean and arm
angles. The clips are `walk_low`, `run_high`, `strafe_l_low` and so on, plus 9 `out_*_run_low` /
`_high` each, so going off from a blow or the guard joins the gait with no blend, as note 139's
do. There are no `out_*_walk_*`: an `out` clip walks only when nobody is engaged, and then it is
plain walk.

`_update_locomotion` takes `_run_clip` and `_walk_clip` only while `engaged`. Walking about it is
plain walk and run, whatever its style. `_strafe_clip`, `_leave` and the guard's `out_g` add
`_style`; `_tend_out` reads the gait to join off the end of the `out` clip's own name.

### Sharing them out (`_share_gaits`)

`_ready` deals a style at random. `_look_for_fellows` calls `_share_gaits` every `PACK_EVERY` while
engaged: of two after the same player on the same gait, the one with the higher instance id
takes whichever gait fewest of them have, if that has fewer than its own. So up to three on a
player are all different. With four or more some share, and none keeps swapping. Changing
mid-run is an ordinary `_switch`, phase kept. The style is not saved.

### Measured

Throwaway windowed sandbox harness, deleted.

```
3 proels forced onto one gait, 1 s later    3 different gaits in 12 of 12 trials
hits taken unguarded in a 44 s fight        20.0 x 7, 36.0 x 3, nothing else
frames on strafes in that fight             every direction seen in all three styles
out clips seen                              10 kinds, across all three styles
planted foot on a run's flat, m/s, median   run 0.18-0.88, low 0.11-0.81, high 0.79-0.93
```

The last is 13-22 samples a run and noisy: the new runs slip about as the old one does, and
`high` is at the top of that range. `--check` on the new clips: worst jolt 0.064, legs 0.055 m
off their mark at worst, blade 0.164 m clear of the body at the closest, tip never under 0.03 m.

**Clean run**: `--quit-after 1500 -- --skip-title --no-intro`, windowed. No `--bench`: nothing new
is drawn. GLB 20.97 -> 23.10 MB.

### Traps

- **A blade going from in front to behind goes through the leg and the floor.** The `out` clips
  lerp the arm, and with `RUN_LOW`'s arm behind it that passes the hanging point: tip -0.18 m,
  -0.07 m through the shin. `out_wide` and `out_el` in a gait dict swing it round the outside in
  `out_clip`. The plain gaits do not have them, so their clips stay the same.
- **Over the shoulder does not work on this blade.** It is 2 m long and grows out of the forearm:
  an elbow of 124 stood it straight up behind the head, 0.11 m off the chest, and no lower.
  Raised beside the head it reaches 2.9 m. Walls are 3.5 m.
- `strafe_b` is "backward", so a style cannot be `_b`. Hence `_low` and `_high`.
- A proel 28 m off and `alert()`ed once walks: `engaged` is false, so it plays plain walk. A
  harness measuring the hunting run must alert it every tick, from nearer.
- Long heredocs through the Bash tool fail here. Write the script with the Write tool.

### Not done

- `idle_fight` and the blows are the same for all three. A blow from `_low` or `_high` starts with
  a bigger blend, `BLEND_BLOW` 0.3 s.
- The blade in `_high` can clip through a low lintel.
