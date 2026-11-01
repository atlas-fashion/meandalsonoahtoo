## 146. The proels' leap: a jump slam that closes the gap; parried, it goes over on its back (2026-10-31)

The user: "The proels should also have a jump slam to get them close to the player. The jump
slam should knock the player down. If the jump slam gets parried, it should throw the proel back
onto the ground, and the proel should get up quickly." Walk, run and every clip that already
existed came out byte for byte identical: 92 clips in, 97 out, 5 new.

### The clips (`tools/anim_sword_skeleton.py`, "The leap")

`jump_slam`, 3.17 s, one clip the whole move, a blow's clock (`Blow`), so it ends on idle_fight's
first frame at no speed. Not on `TEMPO`: how long it is in the air is the jump, not the pace of its
blows. Note 142's number does not touch it.

```
0.00  the load        it sinks, hips down to 0.97 m, and the blade is hauled up as it goes
0.62  LEAP_OFF        the feet leave the floor, the arm dragging, the blade lying back over it
1.03  the top         pelvis 1.83 m, head 2.55 m, back arched, knees up, feet 0.91 m off the floor
1.16  LEAP_A          the swing: enemy.gd's ATTACK. Hips, chest, shoulder, then the elbow
1.42  LEAP_LAND       the feet come down, the left out wide, the right ahead
1.56  LEAP_STRIKE     the point meets the floor. The ATTACK window ends
2.32  LEAP_FREE       the blade is out of the floor and it can turn again
3.17                  on guard
```

**`root` is only ever forward.** The capsule stays on the floor and the clip does the height, so
there is no gravity, no ceiling and no landing to get wrong. `LEAP_REACH` 5.4 m in the air, 6.55 m in
all; the game stretches the flight to fit. `leap_root` stops dead on the landing, and the body's
carry after that is the hips', because that stays right whatever the stretch was.

**The point stays in the floor.** The chest folding and the elbow opening bring the blade down, more than
the shoulder does. The body is still sinking after the point has hit, so
the arm opens from `ARM_DOWN` 98 to `ARM_STUCK` 113 to keep the point where it is: tip 0.07 m at the
strike and -0.03 m at its lowest. Then the clang rings out through the arm, as `reel`'s does.

**`leap_run`, `_low`, `_high`** (`leap_in`): off the run, in stride. The clip starts as the gait's own
left foot strike and runs as that gait; the left comes through as the free knee, the right goes down,
takes the weight and is what it leaves the floor from. Body and arms go from the gait, still running,
to the jump by a minimum-jerk weight, as `out_clip` does the other way. From `LEAP_JOIN` 0.90 s it is
the jump_slam exactly. All three leave the floor at the same 0.62 s, so the game has one clock.

**`thrown`**, 2.05 s, also a blow's clock. It starts from the jump at the top of the swing and
goes over: the arm flung back past its head, legs up, on its back at 0.5 s, 1.84 m back. It skids, and
does not lie there: from 0.92 s the knees come in, the blade is put out to its side and it hauls
itself up over it, into the guard.

### In the game (`sword_skeleton.gd`, enemy.gd's LUNGE)

**`_try_leap`**, first thing in `_chase`. From the run only at a left foot strike, where the clip
takes over with no blend (`_put_on`, at the gait's own time); from a stand or a walk every `LEAP_THINK`
0.5 s (`_switch`, `BLEND_BLOW`). `LEAP_SHARE` 0.6 each time. Then:

- on `lunge_cooldown` 9 s, seen, within `LEAP_LEVEL` 0.8 m up or down, within `LEAP_AHEAD` of where it
  faces (cos 0.85);
- the flight can be stretched to fit, `LEAP_MIN` 0.55 to `LEAP_MAX` 1.3. That is 5.4-9.8 m from a
  stand and 7.7-12.1 m at a left strike, centre to centre: the run-in covers about 3 m on its own;
- `_leap_clear`: rays at 0.5 and 2.7 m, and a floor under five places along the way;
- `_take_turn`: it is a blow, so note 140's one at a time still holds.

`can_lunge` stays false: nothing rolls for this, it asks for itself.

**`_tend_leap`.** As it leaves the floor (`_leave_floor`) it picks `_leap_to`, where they are plus
`LEAP_LEAD` 0.35 s of their going, and faces it. From there it is committed: `_face` does nothing while
`_leap_held`, up to `LEAP_FREE`, so the blade does not sweep round in the floor. `_blow_scale` eases
(`LEAP_EASE` 4/s) to what lands it `LEAP_STANDOFF` 1.5 m short of that point. It starts from 1 because
the feet are planted until it leaves. In the air (`_in_air`) `apply_knockback` is ignored and a rat
cannot `scare` it: a stagger clip from 0.9 m up would drop it through a blend. Damage still lands.

**The blow.** `LEAP_DAMAGE` 30, the blade's own sweep, as every proel blow. `_on_blow_landed` ->
`_leap_lands_on`: unguarded, `knock_down` at `LEAP_THROW` 6.5, the hammer's; a guard turned on it, a
`LEAP_SHOVE` 5 and no floor. **`_leap_strike`**, as the point meets the floor: dust (`_leap_dust`, 26
puffs, behind `Graphics.effects`), the view shakes within `LEAP_FELT` 12 m, and anyone on the floor
within `LEAP_SHOCK` 1.5 m of the point who has not been hit takes 14 and goes down the same way. So a
sidestep inside a stride still pays, and a jump clears it. All players: `Coop.all()`.

**Parried.** player.gd calls `reel_from` as it always did. If `_leaping`, it plays `thrown` for
`THROWN_TIME` 2.05 s instead of `reel` for 1.5, then `THROWN_WARY` 0.5 s of circling before it goes in.
Nothing else changed in the parry: the general `parry_window` of 0.5 s, half the blow reflected,
fellows may step in at `TURN_PARRIED`. `_leap_lands_on` is skipped once `_reeling`, so the player
stays standing. It blends in at `BLEND_THROWN` 0.14 s, from wherever in the air it was.

### Measured

Throwaway windowed sandbox harness, deleted. A standing player unless it says otherwise, 2-3 runs each.

```
standing, 6.5 and 8 m        jump_slam; hits at clip 1.40-1.42 s for 30; knocked down
running in from 22 m         leap_run*; 4.6 m/s at the swap, no blend; hits at 1.40 s; knocked down
sidestepping after it left   missed, 3 of 3 (3.0-3.4 m off at the strike)
running away                 never caught; 10.9 m off becomes 7.4 m, top speed 8.8 m/s
guard held                   3 health (30 x 10%), not knocked down
parried                      `thrown` at 1.40 s, player unhurt and standing, up 2.05 s later,
                             next wind-up 1.82 s after that
shoved in the air            not stunned, the leap goes on
scared in the air            false
killed in the air            death_b, no errors
three proels from 20 m       0 frames of 2 going at once in 30 s; 1 leap: the rest are close by then
closing 22 m                 6.62 s with the leap, 7.59 s without
```

`--check`: worst jolt 0.131 at the tip, against 0.286 on slash_3. `[leap]` jump_slam ends 0.0018 m off
the guard, thrown 0.0000 m, both with the tip stopped; every `leap_run*` starts 0.0000 m off its gait
at under 0.03 m/s, and joins the jump 0.0000 m off, the worst speed gap 0.62 m/s, a foot in the air.
Tip peak 28.5 m/s, highest 3.57 m (slash_3 3.31 m). Wrist turn within 1 degree. Upper arm's roll peaks
at 3.5/f, `leap_run_low` 6.9/f: its blade starts behind it and has furthest to come. Blade to body at
the closest 0.20 m.

**Corridors**, the real level, proels spawned 10-18 m off a player on a random navmesh point, 3 runs
of 20 rounds: 19 leaps, 0 through a wall, at most 0.36 m off the navmesh, no errors.

**The export**: compared accessor by accessor, the 92 old clips are identical; meshes, skin, nodes,
materials and images the same. GLB 22.89 -> 24.20 MB. **Clean run**: `--quit-after 1500 -- --skip-title
--no-intro`, windowed: stderr empty. No `--bench`: the only new drawing is 26 puffs on a strike, behind
`Graphics.effects`.

### Traps

- **Rays at two heights do not see a pit.** One leapt the sewer's channel, went off the edge, and fell
  from y -8.2 to -11.7, flying the clip all the way down. Hence `_floor_at`, and the same check on the
  lead: someone running along the edge does not get led over it.
- **A blade hauled up in flight stands straight up.** The first pass swung it up from low behind it
  with the body already at the top: tip 3.99 m, through any ceiling. Hauled up during the load, it
  passes the vertical with the chest folded and the hips low.
- **The arm does not bring the point down.** With the chest folded 90 degrees, 56 degrees of swing
  points the blade straight down through the floor at -0.52 m. Add the chest's pitch to the arm's.
- A foot leaving the floor at flight speed runs a metre behind the body on a plain Hermite. `air_foot`
  with `trail` lets that speed run off first. Not on `leap_in`'s short stretches: on 0.06 s of Hermite
  the foot hit 5.8 m/s at the join.
- `save_png` of a 3440x1440 grab holds the main thread about a second and `_now()` runs through it
  (as note 143). A held guard older than `parry_window` is a block, so shots taken before a parry
  turned every parry into a block.
- Blender's `foot off its mark` reads 0.69 m here and means nothing: the most is in the air, where the
  feet have nothing to reach.
- Long heredocs through the Bash tool fail here (note 141 again).

### Not done

- No `out` clip from the landing: it recovers the whole 1.61 s, even if they have run. That is the
  opening a missed leap gives away.
- `thrown` is blended into from wherever the parry caught it, not joined.
- A leap on a player in a shut hiding spot, or at someone who drops out of sight in the air, lands
  where it was going. Nothing else is cancelled by that.
- Sounds, as in note 137.
