## 136. The sword skeleton is the user's rusty metal golem, every clip rebuilt on it (2026-10-30)

Noah made a Tripo model, "rusty metal golem 3d model.glb", and asked for it in place
of the body in note 135, with all the animations rebuilt: realistic and smooth, and
**no arm twisting** (check the forearm and upper-arm roll on every attack).

This supersedes note 135's model, its bones' positions, its blows and its dropped
blade. What note 135 says about the game side still holds: `sword_skeleton.gd`,
`sword_skeleton_react.gd`, the inertialized switches, root motion and the numbers
(100 health, 4.6 m/s, light 12, heavy 26, the same timers).

### The pipeline

```
blender -b --factory-startup -P tools/build_sword_skeleton.py
blender -b models/source/sword_skeleton/sword_skeleton.blend -P tools/anim_sword_skeleton.py
godot --headless --import --path .
```

The first takes about a minute and a half. The source lives at
`models/source/sword_skeleton/rusty metal golem 3d model.glb` (68 MB, under the
`.gdignore`, and it must stay there: 2 million triangles in the project is the kind
of file that has taken the editor down before). It had been dropped in `models/` and
Godot had imported it; those copies are gone.

### What the source is

1.94 million triangles, 0.98 m tall, no rig, three 4096 maps. Three things about it
decided everything else:

- **It is one surface cut into 375 UV charts**, not 375 pieces. The charts look like
  armour plates in a coloured render and are not: rigging chart by chart would open a
  crack along every border. Weights go by vertex, on a mesh welded along the charts.
- **The blade grows out of the right forearm.** There is no right hand, only an iron
  ring at the wrist, and the blade is 20 degrees off the line of the forearm. So
  `hand.R` is a stub inside the ring, the wrist barely moves, and **the blow is the
  whole arm**, 1.82 m from shoulder to point.
- **It stands turned 28 degrees to its right**, feet wide and the head turned back the
  other way. `YAW` squares the hips and shoulders to X. Each limb's own turn is taken
  up by `X` below.

### The model

`build_sword_skeleton.py`:

1. Scale to 2.2 m, hips over the origin, turn 28 degrees, weld (0.4 mm).
2. Decimate to 42,000 triangles (21,032 vertices, 160 of them the eyes' triangles).
   Twice: evenly to twice the budget, then with the fingers and mask held.
3. The colour and metal maps are the source's, byte for byte (4096). The metal map's
   red is all ones, so it serves as ORM. Its mean metallic is 0.02 and roughness 0.81.
4. Only the normal map is baked: 8 samples at 4096 from the 1.94M triangles and their
   own normal map, brought down to 2048. 15 seconds.
5. 34 bones. The joints were measured by slicing the mesh and off grids laid over it.
6. Two eyes in `SkelGlow`, because the texture's eyes cannot glow, and that surface
   is what the telegraph swaps.

**Weights** (`labels`, `soft_weights`): a watershed along the surface from the
vertices lying close round each bone, then a few steps of smoothing across each
joint. Along the surface, so a rib stays with the chest however near the upper arm
comes, and the blade and thigh never mix. Hinges get 2 steps (metal should not bend
like skin), the spine 10, the shoulders and hips 4-6.

### The animations

23 clips at 60 fps: note 135's 21 plus `haul` and `idle_haul`.

The old arm was reached for by IK: `solve` was given a grip, a blade direction and an
edge, and the arm's roll fell wherever the solution put it. That is what twists an
arm. **Here the arms are joint angles**: the upper arm's swing, its lift out, its roll
about its own length, the elbow, the wrist, each a track of keys. So:

- The **forearm cannot roll**. `forearm.*` is `rx(-el)` and nothing else: a hinge.
- The **wrist does not turn** in any blow (`twist` stays 0; `wrist turn` in `--check`
  reads 0, the heavy's 1-2 degrees being its side lift).
- The **upper arm's roll is keyed** and read back. `--check` prints the spin about the
  bone's own length, frame to frame, and what it adds up to. Frame to frame, so it has
  no reference pose to go singular on overhead.
- Arcs come from joints turning, chest first, then the upper arm, the elbow opening
  last. No grip has to be aimed.

Every bone has `X`, from the bone as modelled into the **canonical** pose the angles
are written in: limbs straight down, each hinge across X, feet flat and forward.
`G = D @ X` is the bone's rotation from its modelled pose. Knee hinges come from the
pins on the knees (`PIN_KNEE_L/R`), elbows from the plane the arm is bent in.

The blade's flat is read from the mesh in `bind_rest`: its width lies in the elbow's
plane (0.108 wide, 0.035 thick), so an elbow opening cuts with the edge. A flat cut
(`heavy`, `slash_2`) wants the elbow's plane flat, so those hold the upper arm rolled
in about 80 degrees and the elbow opens across the body. `--check` reports how far the
edge is off the cut through the swing.

```
             upper arm spin    peak    wrist turn   tip jolt   edge off the cut
slash_1      -73..+6           5.8/f   0            0.215      mean 29
slash_2      0..+77            3.5/f   0            0.141      mean 45
slash_3      -52..+0           3.3/f   0            0.115      mean  9
heavy        -45..+46          1.6/f   1-2          0.068      mean 31
```

Degrees; jolt in m/frame/frame, the tip being 1.8 m out. The spin in a swing is what
an overhand throw does: rolled out at the cock, rolled in through the finish.

- `death_*` keep the blade. It is the forearm. `death_s` kneels propped on it.
- `haul` / `idle_haul`: the arm back and the blade dragged behind, clear of the cart.
  There is no hand for a handle, so `_haul_anim` puts the right arm back to the clip's
  pose after `pose_hauler`.
- `gait`, `turn`, `stagger` and the shape of the blows are note 135's, on longer legs:
  `z` 1.285 walking, 1.21 running, the stride the same at the same speed.

### In the game

- `sword_skeleton_blade.gd` sweeps from the **elbow** to the point. From the wrist, a
  player close in stands inside the blade's arc, and the whole arm is the weapon anyway.
- `sword_skeleton_react.gd` `HEAD_REST_FACE`: the skull as modelled does not look at
  +Z, so the head look starts from where it does look.
- `sword_skeleton.gd`: `need` now allows for what the speed coming in will carry it
  (v^2 / 2a, 0.7 m from a run). Without that a full step from a run ends in the player.
- `stop_distance` 1.0 (was 0.5).
- The eyes' points moved. `_shoulder_blade` is gone.
- `compress/mode=2` by hand on the two new maps' `.import`, as note 135 says.

### Measured

Throwaway windowed harnesses, deleted. All on the 3060.

**A fight**, the real game's sandbox, one golem against a player standing still, on
the pose shown (a last-in-chain modifier):

- Standing still, 40 s: 19 of 20 attacks landed, each at 12 or 26, in the ATTACK window.
- With the player teleported 5.5 m every 6 s, so it runs, turns and swings on the way
  in: 13 of 16. The misses are blows the teleport walked away from.

Smoothness on the pose shown, m/frame/frame, skeleton space:

```
worst of any switch           tip 0.062   hand.L 0.036   head 0.023   foot 0.087
inside a clip                 tip 0.229 (slash_1)        foot 0.083
```

Note 135's worst switch was 0.14 at the tip. One reading of 0.42 at the claw in a whole
run, on the first frame a just-spawned golem ran: the layer had not been tracking yet.

Walk, run and the `gait` clips are 0.018 and 0.049 in `--check`. No clip's tip goes under
-0.03 m. The top of a raised blade is 3.29 m, under the 3.5 m walls.

**In the real level**: a cart's crew of 3 walked on `haul`, each killed from a different
side played `death_b`, `death_f`, `death_s` and was gone 8 s later. No script errors.

**Sixteen in view, fighting** (3440x1440, 900 frames, vsync off):

```
              avg ms   fps   p99 ms   gpu ms   video mem
note 135      6.09-6.15 164  9.5      4.8-4.9  895.5 MB
golem         7.19      139  10.93    5.65     911.6 MB
```

Not the same harness as note 135's, which was deleted. +13k triangles and the 4096
maps; the worst case still has 9 ms to spare at 60.

**The level bench** (`--bench --size=3440x1440 --no-intro`, editor closed):

```
                     overall fps   worst p99 (ms)   video mem
note 135               80.0         19.25           977.0 MB
now                    72.2-72.7    19.22-25.00     989.7 MB
now, --no-enemies      74.3         20.83           957.9 MB
```

The 80 to 72 is not the golem: with **no enemies at all** the same run gives 74.3, so
every enemy in the level together costs 1.6 fps. Something else moved between note 135's
run and these, and it was not looked into. Use 74.3 / 72.7 as the baseline.

### Traps

- **`bpy.data.images.load(path, check_existing=True)` hands back a copy you made**
  if its `filepath_raw` is that path, with the copy's packed data. The first build
  shipped the 4096 maps while saying 2048, in a 25 MB .blend. They looked right, so
  they stayed, on purpose now: the rivets are what this model is.
- **A decimate vertex group is not a gentle preference.** A held edge's cost gets its
  length added, and every other edge costs next to nothing, so held edges are never
  taken: the hand kept 40,000 triangles and the body collapsed to a few dozen. Decimate
  evenly first, then hold. And the weights are inverted: with `invert_vertex_group`
  off, weight 1 means decimate freely.
- **`orphans_purge` takes a material you are holding** if nothing uses it yet.
- **A wrist flex keeps going round.** On a golem whose blade already sits 20 degrees past
  the forearm, a backhand wound up with the elbow at 96 points the blade straight up.
- **Prone, forward is the floor.** A bent elbow in a fall forward drives the blade
  through it: fold the arm back, and let the wrist open.
- **The spine needs blurring too.** At the end of a 2 m lever a key on the chest is
  as sharp as anything the arm does.
- **Long heredocs through the Bash tool still do not parse here.** Write the file.
- **`Graphics.apply_all` turns vsync and `fps_cap` back on.** A harness that wants
  unthrottled numbers sets them after the level is built.
- **A screenshot saved in a frame shows as that frame's script time** on the debug
  overlay: 6 FPS, 1152 ms.

### Not done

- Sounds, as in note 135.
- Hit reactions are the enforcer's data, as in note 135.
- `slash_2`'s edge is the furthest off its cut: mean 45 degrees, worst 82 at the ends of
  the swing. It reads as a rising cut, but it is the one to tune first.
- The blade dragged in `haul` was judged on a Blender sheet, not in the corridor: the
  harness's crew noticed the player and the camera ended up facing a wall.
- ORM has no baked occlusion: the source has none and it was not missed in the corridor.
