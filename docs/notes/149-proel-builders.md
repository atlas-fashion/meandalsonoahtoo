## 149. The hammer skeletons are Proel builders: the rusted golem, the pound and the spin (2026-11-01)

Noah made a second Tripo golem, "rusted metal golem 3d model.glb": the swordsman's family,
but each forearm ends in a yoke and an iron head half a metre across. The ask: "Use this for
the hammer skeletons, and call them proel builders. Their moveset should be a slow walk
toward the player while slamming the ground with alternating hammers, and a really heavy
looking spin attack."

The hand is still `&"hammer"`: it is in the saves and in `CONTAINED`. What a player reads says
PROEL BUILDER. This replaces note 93's hammer hand (the overhead smash, the prosthesis on the old
rig). `skeleton_sword.gd` keeps its `&"hammer"` kind, used by nothing now but its strike radius.

### The pipeline

```
blender -b --factory-startup -P tools/build_proel_builder.py
blender -b models/source/proel_builder/proel_builder.blend -P tools/anim_proel_builder.py
godot --headless --import --path .
```

As note 136, and the files are forks of the swordsman's, not shared with them: its export is
checked byte for byte and nothing here should be able to move it. The source lives at
`models/source/proel_builder/rusted metal golem 3d model.glb` (it was in Noah's Downloads).
Editor closed for the import. `models/proel_builder.glb.import` was written before the first
import with the swordsman's `[params]` (`animation/fps=60`), and the three maps set to
`compress/mode=2`.

### The model

1.92M triangles, 0.98 m tall, no rig, stands square. Scaled to 2.2 m and moved 12 cm so the hips
are over the origin; 42,000 triangles with the mask held; its own 4096 colour and metal maps,
the normal map baked. 23 bones: the swordsman's names, no fingers, no `blade`, and `hammer.*` from
the axle in each yoke through the head, hinged across X like the elbow. Because the bones keep
those names, `sword_skeleton_react.gd` drives this rig too (new `rest_face`: this skull looks
straight ahead, stooped).

**A head hangs 7 cm from its leg, and that was the whole problem with the weights.** Three tries:

1. Nearest bone: head vertices beside the shin went to the shin, and a sliver the length of the
   leg followed the hammer through every swing.
2. A box fitted to each head: it took vertices off the leg as well.
3. `hammer_of`: the leg's middle at each height, off the slices, and `LEG_CLEAR` past it is hammer.
   Those vertices are settled before any others and no other vertex may start as a hammer.

That left one sliver, because **the left head's lower corner has grown into the shin**: at the
source they are one surface. `fused` stops the smoothing crossing that join, and `part_hammers`
deletes the 41 faces on it. What is left is a hole a few centimetres across inside the shin.

### The animations

16 clips at 60 fps: `idle`, `walk`, `turn_l/r`, `slam_in`, `slam_walk`, `slam_stand`, `spin`,
`reel`, `stagger_b/f/l/r`, `death_b/f/s`. Specs, joint-angle arms and two-bone legs as note 136.

**The pound.** `SLAM_T` 2.0 s a stride of each foot at `SLAM_V` 0.9 m/s, so a hammer a second, the
left on the left foot, the right on the right. One arm's clock runs from its hammer landing:
stuck on the floor, dragged up by the elbow, hoisted in front, the forearm folding back over
the shoulder, a hang at the top (2.56 m), and the drive. The drive is not keyed: `arm_at` gathers
speed all the way down and stops dead on the floor. Keys through a Hermite arrive with no speed,
which reads as being set down. The body has its own clock, twice as fast: it bows after the
hammer, 50 degrees of spine and 19 of pelvis, because **an arm this long still ends 0.5 m off the
floor standing up**: the shoulders have to come down 0.45 m to reach it. Arms 0.45 m ahead of
the hips at landing, 0.43 m out. They land at 14.7 m/s, lowest points -0.03 and -0.01 m.

The first pass landed on the middle of the body. The chest's turn carries the arm's forward reach
across the body, about 0.4 m for 35 degrees: 21 degrees is as much as it can take.

`slam_walk` and `slam_stand` are the same arms and the same clock, so one takes over at the same
time with a blend on the legs. `slam_in` raises one hammer from the stand and ends on the pound's
own frame at `IN_PHASE`, with no blend, or the first hoist would pop.

**The spin.** One clip, 6.8 s: `SPIN_A` 1.3 s coil, 75 degrees the wrong way, then 720 degrees of
real turn: 1.25 s to get going, 0.55 s flat out (6.5 rad/s), 1.9 s running out, 1.8 s getting up.
`root` x is the turn, as the swordsman's pivots: the model takes it, and **a parry leaves it facing
wherever it had got to**. Baking the turn into the pelvis would have made that a snap.

The weight comes from the speed being read by everything else: `push` (how hard it is
accelerating) moves the hips ahead of the chest and the hammers behind it going up, and the other
way coming down; `fly` (how fast) takes the arms out and up; as it dies they sag, it bows and heaves.
Hammers ride 0.67-1.47 m up and out to 1.4 m. Feet are planted on the floor and picked up in
turn every 130 degrees (`spin_steps`, `floor_foot`), 8 and 7 steps, shortest 0.15 s. It walks itself
1.5 m forward through it.

### In the game

`scripts/proel_builder.gd` extends prosthetic.gd, not sword_skeleton.gd: nearly all of that file is
the swordsman's way of fighting, and its `_roots` static would mix two sets of clips with the same
names. `prosthetic.gd script_for` picks it. `proel_builder_hammers.gd` extends skeleton_sword.gd and
sweeps each arm, elbow to head; `live` says which can hurt.

| | |
| --- | --- |
| health, speed | 140 (note 93's), 0.9 m/s engaged, 1.1 m/s walking about |
| a hammer | 30 and a knockdown, a shove of 5 through a guard |
| the floor | 12 within 1.7 m of the head, no flinch, felt 14 m off |
| the spin | 40 and a throw of 10 m/s, shove of 5 through a guard, 9 s cooldown |
| turning | 1.3 rad/s at most (`_face`) |

- It pounds whenever it is **engaged**, at any distance, so it can be heard coming... once it has sounds.
- The pound is not enemy.gd's state machine, which would stop it walking. State stays CHASE and
  `_tend_pound` reads the beats off the clip: cue 0.5 s before a landing, live 0.3 s, then `_land`.
- A hammer can be parried: `parry_cue` 0.5 s before, listening 0.55 s, and `reel_from` plays `reel`,
  1.7 s, back 0.75 m on its feet. The floor's shock goes through `take_damage` with no attacker,
  so it can be blocked and not parried. The spin has no cue and parries as any blow does.
- **A cue left open by a hammer that met nobody must be cleared at the spin**, or the spin's
  blow uses it up and a raised guard stops parrying (`_start_spin`).
- The spin is asked for at a landing (`_land`), 0.75 of the time, within a gap of 2.6 m: the arm is
  down and it is already bowed. The body takes its line at them there and holds it.
- Ordinary blows and shoves do not break its stride: only a shove of 8.5 (`SHOVE_STOPS`, the same as a
  shield's guard), for the 1.2 s of its stagger. Nothing but a parry stops the spin.
- It stops walking at a gap of 0.35 m. The hammer's arc passes 1.3 m out at chest height, so that
  is well inside reach.

### Measured

Throwaway windowed harnesses in the sandbox, deleted. The player standing still, health raised.

- Standing still, 30 s: two spins, each landed 40 with a knockdown. A shock of 12 at the first.
- Spin off, 22 s: 5 hammers of 30, each a knockdown, and 5 shocks of 12, every 3 s. The body
  stops at a gap of 1.07 m centre to centre and goes on when they are thrown clear.
- Parry pressed through each cue: reels at 7.7, 11.8 and 18.0 s, each 1.5 s, stepping back 0.75 m.
- A parry at 3.03 s into the spin: the body took the model's heading to the hundredth, up again
  in 1.6 s, walking.
- A shove of 3 and a blow of 10: clip unbroken. A shove of 12: `stagger_b`. Note the first version
  was over in 0.14 s: the stun was the default 0.25 s and the pound took straight back over.
- All three deaths played, gone 6.4 s later.
- The real level: 7 builders (5 caged, 2 in the pens). A block's power cut: uncaged, 3 more loose,
  no errors. **The walk out through the back doors was not watched**: they went dormant, far off.

**Frame time could not be measured properly.** Rainbow Six Siege and Roblox were running on the PC
through all of this, and an empty sandbox read 118 ms of process time. Same harness, one run, 16 of
each fighting, 1280x720:

```
              process ms   physics ms
nobody        117.6         0.9
16 swordsmen  131.1         8.2
16 builders   152.2        13.2
```

Video memory with 16 in view, 3440x1440: swordsmen 934.8 MB, builders 1008.5 MB. **Re-measure with the
PC otherwise idle.** Note the 5 ms of physics: it is the first thing to look at.

### Traps

- **`TIME_PROCESS` is not your frame.** With another game on the GPU it holds the wait. Compare
  against the same run with nobody spawned before believing a number, and read the task list first.
- **A screenshot saved in a frame stretches the harness's clock** but not `_now()`: the wind-up read
  0.8 s. Time things with no screenshots.
- **A harness setting `_blocking` from `_process` is undone by the next physics tick.** Test a
  parry by setting `_block_pressed_at`, or by calling `reel_from`.
- **`float(null)` errors**: `o.get("_wanted_at")` on a builder from a swordsman's `_pack` would. The
  builders have their own group, `proel_builders`, and do not join `proels`.

### Not done

- Sounds, as for the swordsman. The pound most of all.
- Their hammers span 1.85 m and a containment back door is 1.2 m wide: they will go through its frame.
- It keeps the pound's feet while turning on the spot in `slam_stand`, so they skate a little.
- `death_s` leaves the left hammer 0.37 m into the floor, under the body; `death_b` a corner 0.09 m.
- It takes no part in the swordsmen's turns (note 140).
- Hit reactions are the enforcer's data, scaled down.
