## 156. The knight's arms in first person (2026-11-03)

The user: "The player should see the knights arms when playing." The molten rust
knight (note 155) now holds what is in the right hand in the first-person view:
its gauntlet closed on the sword's hilt, up the spear's and the axe's hafts,
round the flask, pinching a live rat's tail.

### The mesh (`tools/build_player_knight_arms.py` -> `models/player_knight_arms.glb`)

Read from `models/player_knight.glb` (run after `build_player_knight.py`):

- Only the arms: every vertex whose strongest bone is Left/Right Arm, ForeArm
  or Hand; faces touching anything else cut. 8,343 faces, 12k vertices. The
  pauldrons ride the Shoulder bones and would sit on the camera.
- Fists: the rig has no finger bones, so the fingers are bent in the mesh round
  the knuckle line (Blender |x| 0.918, finger centre z 1.355) on a 2.6 cm
  radius, at most 2.75 rad, the rest carried straight on. The thumb (inside the
  knuckle line) is left lying out along the haft.
- Whole 24-bone skeleton kept; **no materials** (`export_materials="NONE"`):
  the game dresses it in the body's own material, so the 2048 maps are in video
  memory once. 693 KB.
- Prints each fist's grip centre in glTF space: (+-0.918, 1.329, -0.0544), held
  in `first_person_arms.gd` `GRIP`.

### The arm (`scripts/first_person_arms.gd`, node `KnightArms` under the Head)

Made in player.gd `_ready` after the hand torch. **Nothing animated**: each
frame (`process_priority` 900, after the player, the weapons and the sword's
AnimationPlayer) the fist is solved onto what is held, so every swing, guard,
parry, duck, queued stroke and throw moves it with no work here.

- `_right_target`: [kind, grip point, haft direction] from what is visible --
  the sword (between its measured guard and pommel, 0.42 toward the pommel,
  along the blade), the spear (`SPEAR_UP` 0.28 m up the shaft from its bands),
  the axe (`AXE_UP` 0.12 m up the haft), the flask, a live rat (rat_control.gd
  `_live`, its `tail_tip`, fist upright). Nothing visible: the arm is hidden.
- The fist frame: the haft through the fist, the forearm coming at it from the
  shoulder (the shoulder-to-grip line squared to the haft), back of the hand
  from those. Wrist = grip minus the turned grip offset.
- Two-bone IK shoulder -> elbow -> wrist, the elbow pushed down, out and back
  (`POLE`); the upper arm by the shortest turn, the forearm also twisted so its
  cuff matches the fist. Out of reach the shoulder slides toward the wrist
  (`set_bone_pose_position` on the Arm bone).
- The shoulder is the rig's joint moved down 9 cm (`SHOULDER_DROP`): the rig's
  sits at the top of the pauldron, and there the upper arm filled the bottom
  right of the view.
- **Drawn at the size of what it holds** (`SCALE_FOR`, `k`): the flask is half
  size 21 cm from the eye (held_potion.gd), so the arm there is half size,
  scaled about the eye -- on screen a full arm.
- One instance, the right arm; the left of that copy is folded to a point
  (Arm bone scale 0.0001). **No left arm**: the hand torch is held so low that
  only its flame shows (hand_torch.gd, `CORNER` y -1.15), its handle off the
  bottom of the view; the fist and arm would be too. Showing it means raising
  the torch, which changes its tuned look -- not done.
- Material: the body's, duplicated, `use_z_clip_scale` at `sword_draw_depth`
  (in front of walls, as the sword), emission 1.2 (the body's 2.2 glared a
  hand's breadth from the eye). No shadow (the body casts it, note 155). Under
  the Head, so co-op's `_sweep_view_layers` puts it on that player's viewmodel
  layer.

What shows: at rest the sword's hilt and fist sit on the bottom edge (the
sword's idle clip holds it there, unchanged); through a swing the whole gauntlet
and forearm cross the view; the spear and axe fists show at rest, lower right;
the flask in the fist; the rat hung from it.

### Measured

Placement, windowed harness (throwaway): the fist's grip point read back from
the posed skeleton was on its target to 0.0000 m for every kind and through a
slash, spear stab and axe chop.

RTX 3060, 3440x1440, High, `--bench --size=3440x1440`:

```
                   without arms        with arms
                   avg / p99 / gpu     avg / p99 / gpu
spawn corridor     15.22 / 16.67 / 13.93   15.14 / 16.67 / 13.88
boss room centre   12.58 / 14.38 / 11.13   12.78 / 14.59 / 11.07
boss room edge     11.53 / 14.85 /  9.90   11.51 / 13.68 /  9.90
outer maze         11.86 / 13.13 /  9.65   12.21 / 13.90 /  9.69
chest room         18.35 / 20.54 / 16.75   18.69 / 23.25 / 16.65
surgery            17.91 / 21.39 / 16.23   17.96 / 22.22 / 16.17
OVERALL            71.1 fps                70.4 fps
video memory       1061.7 MB               1061.9 MB
```

GPU time the same; the rest is run-to-run noise (the p99s move both ways). No
quality knob: nothing to save.

### Also

coop_avatar.gd `_goal_dir` slerped two nearly equal unit vectors, which raised
"The axis Vector3 (...) must be normalized" every frame (stderr full of it since
note 155); now a lerp, normalised.

### Traps

- `--resolution` on the command line did not size the window in a `--script`
  harness here (it came up 3440x1440); `--bench` needs `--size=3440x1440` or it
  runs 1280x720.
- Skeleton poses set in `_process` reach the skin the same frame (the update is
  deferred to the end of the process step); setting them at `frame_pre_draw`
  would lag a frame.
