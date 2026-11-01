## 145. The flinch: planted for half a second, then free (2026-10-31)

The user: "If the player is hit, instead of just not being able to attack, the player should
be almost planted still for half a second. If the player can move he should be able to
attack." Supersedes note 143's numbers: its second at half speed is gone. Everything else
there stands (the view, the weapon knocked down, what stops the attack under way, what stays
free, what is not a flinch).

- **`player.gd` `flinch_time` 1.0 -> 0.5, `flinch_move_scale` 0.5 -> 0.1.** "Almost planted" read
  as a tenth of walking pace, not zero, so they can still shuffle. One clock: `is_flinching()`
  is the lock on attacks and the slow alike, so the moment they can move they can swing. The
  view and the weapon dip reach home on the same clock.
- **`FLINCH_PLANT` 4.0**, on the floor only: the ground's stopping rate times this while
  flinching. A target speed alone is not planted. At `acceleration` 14 someone at a run
  slides on for 0.27 s and 0.6 m, half the flinch.
- Ghost, swimming and the air still go through `_flinch_speed_scale`, so they drop to a tenth
  of their speed too. `flinch_move_scale`'s range now starts at 0.

**Measured**, a throwaway windowed harness on the real player in the sandbox, walking, attack
pressed every tick, then a blow:

```
speed, m/s      4.25 before   3.32 at 0.02 s   0.43 from 0.12 s to 0.42 s   full again at 0.52 s
moved           0.31 m in the flinch
is_flinching    false at 0.500 s
first swing     0.517 s, the next tick (the harness's press comes after the player's tick)
view            exactly zero at the end
```

**This takes away note 143's chain.** Invulnerability is 0.6 s, so the next blow cannot land until
the flinch has been over for 0.1 s. A pack can no longer keep the attacks locked.
