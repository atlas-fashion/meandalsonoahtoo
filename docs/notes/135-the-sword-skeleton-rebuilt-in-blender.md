## 135. The sword skeleton rebuilt in Blender: a new body and every animation baked (2026-10-30)

**Note 136 replaced this body and its blows with the user's rusty metal golem.** The
game side below (root motion, inertialized switches, the numbers) still stands.

Noah gave a concept image: very tall and gaunt, a patchwork of rusted scale plate
eaten through with holes over maroon sinew and tan bone, a small bald skull in a
mask of vertical slits, amber eyes, a long serrated blade, a bare-bone claw. The
ask: make that instead of the sword skeletons, with "a very realistic set of
animations for everything it needs", and "all animations should be perfectly
smooth between all other ones".

This replaces the look of the sword hand in note 93 (`&"blade"`: the cuffed blade,
the arm posed in code). The numbers and the AI of note 93 are unchanged: 100
health, 4.6 m/s, light 12, heavy 26, the same timers. Drill, hammer, shield and
crossbow skeletons keep the old rig.

### The pipeline

```
blender -b --factory-startup -P tools/build_sword_skeleton.py
blender -b models/source/sword_skeleton/sword_skeleton.blend -P tools/anim_sword_skeleton.py
godot --headless --import --path .
```

The first writes the mesh, rig and maps into `models/source/sword_skeleton/`. The
second adds every clip, saves the .blend and exports `models/sword_skeleton.glb`.
Change an animation and only the second needs running. Add `-- --check` to the
second to print the worst jolt in each clip (the change of a joint's velocity in
one frame, and where), and `-- --sheet <dir> [clips]` for a strip of poses in
Workbench. Both are fast and were how most faults were found.

`build_sword_skeleton.py` borrows the helpers from `build_scout.py`, which is why
that file's `main()` is now guarded.

### The model

29,382 triangles (scout 34,182), about 34,000 vertices once split, 34 bones (the
old rig 21), one 2048 atlas. Height 2.2 m: under `DOOR_H` 2.35 and `BACK_DOOR_H`
2.3. Blender frame: X its LEFT, -Y its front, Z up, so the glTF has the old rig's
axes (+X left, +Z front) and the bones keep the old names (`upper_arm.R`, `head`,
...), plus `toe.*`, the claw's `f0`-`f4`, and `blade`. convoy.gd, skeleton_eyes.gd
and everything else written for that rig reads this one.

Three surfaces, by material name:

- **SkelCore**, opaque: bone, sinew, struts, the armour that stays whole, the blade.
- **SkelShell**, alpha scissor, both sides, no thickness: sheets of scale plate and
  webs of sinew. A hole must go right through, so a shell with thickness would not
  do (the hole would show its own inner wall).
- **SkelGlow**: the eyes, the amber lines in the right arm, the knee hub.

There is no high mesh. The maps bake off the low mesh itself: a procedural material
reads three vertex attributes set part by part (`sk_col`, `sk_pbr`, `sk_kind`). The
scales, rivets and scale-shaped holes are a Voronoi field in rest space, so they
run across every UV seam, and a hole is decided at each scale's own centre, so a
scale goes whole. Bake took under a minute on the 3060.

### The animations

21 clips at 60 fps. Nothing is keyed on bones: each clip is a function of time
returning a `Spec` (where the feet are, what the hips and spine do, where the
sword hand goes, how the blade lies), and `solve` turns that into bone rotations by
two-bone IK, so a foot stays where it is put.

| clips | what |
| --- | --- |
| `idle` 6 s, `idle_fight` 2.2 s | relaxed; guard, used while `engaged` |
| `walk` 1.17 s at 1.55 m/s, `run` 0.73 s at 4.6 m/s | the gait below, same phase |
| `turn_l`, `turn_r` | stepping round on the spot, played by the model's turn speed |
| `slash_1`, `slash_2`, `slash_3` | light: diagonal, backhand, overhead, 1.47 s |
| `heavy` | the heavy slice, 2.22 s |
| each of those + `_s` | the same blow with a shuffle (0.26 of the step), close in |
| `stagger_b/f/l/r` | thrown by a blow, two catching steps, 1.1 s |
| `death_b/f/s` | falls back, forward, or to its knees and over; lets go of the blade |

- **The gait** (`gait`): a foot in stance is a point on the floor going backwards at
  the ground speed, rolling heel, flat, ball; in swing it runs a Hermite from
  toe-off to the next strike at the speeds it had at each end. Hips bob, sway and
  turn; chest and arms turn against them; the head rides level.
- **A blow is one clip**, wind-up, swing and recovery, cut to enemy.gd's timers
  (`LIGHT`, `HEAVY`). Nothing blends inside a blow, and no clip is stretched.
- **Root motion**: `root` is lifted out of each clip once (`_lift_roots`) and kept
  as a curve. In a blow `_slide` moves the body by it, scaled to the reach needed
  (0.6-1.25), so the planted foot stays planted. Under 0.32 m needed it plays `_s`.
- Fingers, toes and the blade are real tracks. The death clips drop the blade: it
  leaves the hand at the hand's speed, falls and rings on the floor.

### In the game

`scripts/sword_skeleton.gd` extends prosthetic.gd. `prosthetic.gd script_for(hand)`
picks it, and every maker goes through that. It swaps the model in `_enter_tree`
(before the `@onready` lookups) and gives the capsule 2.1 m, so the head can be hit.

enemy.gd gained four small hooks, all defaulting to the old behaviour:
`_own_material`, `_hang_eyes`, `_arm`, `_fold_up`.

- **Smoothness**: `sword_skeleton_react.gd` extends enforcer_react.gd for its
  `crossfade` and hit reactions (a blow that does not stagger plays over any clip).
  It adds a head that follows the player, and on this rig `free_velocity`: the
  inertialization keeps a bone's speed whole and starts with no acceleration of its
  own. `_rot_before` / `_pos_before` make the offset's speed relative to the new
  clip's own motion, which matters from one moving clip to another.
- **Walk and run share a phase**, so one takes over mid-stride (`_switch`). Out of a
  stand it starts on the right foot, the one ahead.
- **Heading**: `_face` snaps; the model follows on a critically damped spring
  (`_turn_model`, its child `Model`, so the body's yaw and every test on it stay
  exact). That spring's speed plays the turning clips.
- **The blade** (`sword_skeleton_blade.gd`): only skeleton_sword.gd's swept `strike`
  is kept, reading the real `blade` bone, so a blow lands where the clip swings it.
- **Telegraph**: eyes and lines swap to a hotter material through a blow.
- **Death**: `_fold_up` plays the clip by where the last blow came from, lies 6 s,
  then flattens as the scout does. `_slide` does nothing once dead, or gravity
  would take it through the floor with the capsule off.
- **Carts**: `_haul_anim` walks, convoy.gd puts the arms on the handles, and
  `_shoulder_blade` holds the blade up out of the way.

### Measured

Throwaway windowed harnesses, deleted. All on the 3060.

**A fight** (one skeleton against a player standing still, on the pose actually
shown, read by a last-in-chain modifier): 20 s with nothing interfering, 10 of 10
then 9 of 10 attacks landed on two runs, each at 12 or 26, in the ATTACK window. The
one miss was not looked into.

Smoothness, as the change of a joint's velocity in one frame, m/frame/frame, on the
skeleton's own space. First pass to last:

```
                         first      last
inside a slash (tip)     0.28       0.12-0.17
inside the run           0.30       0.06
run > slash              0.37       0.06-0.08
run > stagger            1.07*      0.05-0.11
heavy > stagger          0.62       0.14
walk > run               0.35       0.09
worst of any switch                 0.14 (the blade's tip; 0.09 off the blade)
```
*measured in world space, with the shove in it.

The worst switch is below the blade's own worst inside a clip. Only the blade tip
gets near that; it is 1.2 m out on the end of everything.

Foot slip at a steady pace, straight on: 0.062 m per metre walked, worst frame
0.022 m (only 4.8 m of the run qualified).

**In the real level**: 7 at the start (5 caged, 2 in the pens). A cart's crew of 3
walked hauling with the blade up, broke off when set upon and ran. A block's 5
prisoners walked out through their doors (8.2 m). A pen soldier turned loose came at
the player and swung. No script errors.

**Sixteen in view, fighting** (3440x1440, 900 frames, the worst case, two runs each):

```
              avg ms   fps     p99 ms   gpu ms   video mem
old body      4.74-5.18  193-211  6.8-7.8  3.6-4.1  887.0 MB
new body      6.09-6.15  163-164  9.5      4.8-4.9  895.5 MB
```

**The level bench** (`--bench --size=3440x1440 --no-intro`, editor closed):

```
                     overall fps   worst p99 (ms)   video mem
note 134               80.6         18.06           958.2 MB
now                    80.0         19.25           977.0 MB
```

The "before" here is note 134's run, not one taken the same hour. Few of the bench's
stations show a sword skeleton, so this says the level is unaffected, not what a
crowd costs: the table above says that.

**Clean run**: `--quit-after 1500 -- --skip-title --no-intro`, windowed: stderr empty.

### Traps

- **glTF NLA export wrote every clip at rest.** `export_animation_mode='NLA_TRACKS'`
  with layered actions gave identity on every bone and no error. `'ACTIONS'` works.
  Check a clip's keys after exporting, not just its name.
- **Keys from frame 1 start each clip 1/60 s in**, and a loop then holds a frame.
  Key from frame 0 and set `export_anim_slide_to_zero`.
- **A leg near straight snaps its knee**, however smooth the foot: the knee's speed
  goes to infinity at full reach. The soft limit starts at 0.96 of reach, and the
  run's stance is short enough to stay inside it (S 0.3, not 0.37).
- **Keys close together kick**: a Hermite over 0.07 s peaks at 6 / h^2. The fast
  channels go through `blur`.
- **Bollo's opening acceleration is 20 x0 / t1^2.** On a long blade that was the
  kick at every switch, and it reads like a pop. `free_velocity` starts at 0 instead.
- **`_attach_eyes` already exists** in enforcer.gd and decrepit.gd with another
  signature; hence `_hang_eyes`.
- **`material_override` flattens a multi-surface mesh**, and enemy.gd set one on any
  mesh with a StandardMaterial3D: hence `_own_material`.
- **`anim.play(x, -1, rate)` and `speed_scale` multiply.** enemy.gd's chase plays at
  rate squared after a switch; `_switch` plays at 1 and sets `speed_scale` alone.
- **A harness measuring in world space sees the body's shove**, and one standing 14 m
  off sees animation LOD. Both looked like pops. Measure in the skeleton's space and
  close in.
- **`current_animation_position` errors on a stopped player**: a blow's clip ends a
  frame or so before enemy.gd's recovery does.

### Not done

- Sounds.
- Hit reactions are the enforcer's data, not this creature's own.
- No foot locking: a stop out of a run slides the planted foot a little as the idle
  takes over, and a very short shove can slide the feet.
- The look of a hauling crew was checked by numbers (blade axis, clips), not by eye:
  the harness's camera landed inside rock.
