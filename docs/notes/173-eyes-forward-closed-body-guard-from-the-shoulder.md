## 173. The eyes at the front of the helmet, a closed body under them, the guard built from the shoulder (2026-11-09)

The user (through the project's coordinator): move the first-person camera
forward on the knight, so that looking straight down shows only the front of
his body; and the blocking arm "detaches and floats" -- keep it attached and
natural.

### What was wrong

Measured with a throwaway windowed harness (bones in the head's frame, shots
looking ahead, 45 and 89 degrees down, the guard at level, 35 down and 30 up,
lit with a lamp on the camera so the dark armour reads):

- **The camera sat in the middle of the helmet.** The helmet runs from 0.15 m
  behind the camera to 0.19 m ahead of it; the visor is at the front. In the
  guard stance (note 171) the whole knight also leans forward and crouches: its
  Head bone is 0.16 m BELOW the camera and its left shoulder 0.18 m ahead.
- **Looking down, the chest folded under the eye.** The walk pose bends the
  chest by 0.3 of the look, and under any clip (the stance included) a further
  `LOOK_BEND` 0.6 of it: looking straight down the chest bent about 70 degrees
  and the shoulders came up under the camera.
- **The eye's copy of the body was open.** Notes 168-171 cut every triangle of
  the head, neck, shoulders (pauldrons) and left upper arm out of the mesh the
  camera draws. Looking down showed the open neck and the shoulder sockets --
  into the inside of the body.
- **The guard's forearm had no upper arm** (the left upper arm was cut, note
  171), so it hung in the air. And its elbow and fist were fixed points in front
  of the eye (note 158), tuned for the old separate arms model and its braced
  shoulder. On the real body the shoulder in the stance is already 0.18 m ahead,
  so the IK threw the elbow out to -0.39 (in front of the fist at -0.25) and the
  forearm came back at the face.

### The eyes (player.gd `_eye_offset`, `EYE_FORWARD`, `EYE_LEAN`, `EYE_DROP`)

- The `head` node (everything held is posed in its frame) is unchanged; the
  Camera3D under it now sits `EYE_FORWARD` 0.11 m ahead along the head's
  heading (levelled, so it is forward whatever the pitch).
- Looking down the neck carries the eyes further out and a little lower:
  + `EYE_LEAN` 0.14 x and - `EYE_DROP` 0.05 x the sine of how far down (0.25 m
  ahead and 5 cm lower looking straight down); looking up the lean runs back.
- Eased out over 0.3 s (`_eye_w`) when dead, hidden or through a rat's eyes.
  Third person sets the camera itself, as before.

### A closed body for the eye (coop_avatar.gd `_make_view_meshes`, `sync_view`)

- **No triangles are cut any more.** The eye's knight is the same mesh and skin
  on a skeleton of its own (`_view_skel`). first_person_arms.gd, the last thing
  to pose the body each frame, calls `sync_view`, which copies every bone's
  pose across and then FOLDS `VIEW_FOLD` (Head, LeftShoulder, RightShoulder):
  each scaled to `FOLD` 0.01 about its joint, its children's offset and scale
  divided back so the arms come out exactly where they were. The helmet shrinks
  into the top of the neck and the pauldrons into the collar; the armour round
  them closes over where they were. No holes.
- The left upper arm is drawn again: the raised guard is attached to the body.
- Whatever is still within `EYE_CLEAR_NEAR` 0.10 m of the camera is not drawn,
  dithered in by `EYE_CLEAR_FAR` 0.16 (`distance_fade` PIXEL_DITHER on the
  eye's own copies of the materials).
- Seen from outside, in co-op and in the shadow: the whole knight, unchanged.

### The chest looking down (coop_avatar.gd `LOOK_DOWN_BEND`)

Looking down, the chest bends only `LOOK_DOWN_BEND` 0.3 as far (walk pose and
the clip's bend alike); looking up, as before. During an attack the bend goes
back to the full look by the attack's own weight (`lerpf(bend_pitch, pitch, w)`),
so a cut aimed down still goes down.

### The guard from the shoulder (first_person_arms.gd `_update_guard`)

- The poses are now DIRECTIONS out of the body's own shoulder, each laid at the
  bone's real length: `GUARD_UPPER` (-0.28, 0.12, -1) the upper arm, driven
  forward and a little out; `GUARD_FORE` (1, 0.04, 0.06) the forearm, flat
  across the view. The parry the same way (`PARRY_UPPER`, `PARRY_FORE`). So
  elbow and fist are always where the arm can put them.
- `GUARD_PITCH` 0.6: the guard's frame turns that much with the look, so
  looking down the arm stays nearer the chest instead of being pinned in view.
- **Down** is wherever the body's own walk and stance have the arm this frame
  (read before the guard touches it), so the drop hands back with no jump; the
  old fixed `DOWN_ELBOW` / `DOWN_WRIST` are gone.
- Springs, breath, look lag, recoil, shudder and the plate are note 158's.

Measured, level look: shoulder (-0.13, -0.20, -0.18), elbow (-0.20, -0.17,
-0.42), fist (0.11, -0.15, -0.40) in the head's frame -- the forearm a flat bar
0.29-0.31 m ahead of the eye. Looking 35 degrees down and 30 up it keeps the
same shape. On screen the forearm crosses the lower middle, the upper arm
running into it from the lower left.

### Seen

- Straight down: the gorget, the breastplate, the upper arms, the sword arm;
  no helmet, no neck or shoulder holes, nothing of the back.
- 45 degrees down: the floor ahead, the arms at the edges.
- The guard at level, down and up: attached, flat, braced.

Clean windowed runs with `--quit-after 1500`, with and without the intro: no
errors or warnings. Not benchmarked: the change adds a second skeleton for the
eye (a pose copy of ~60 bones a frame) and a dither on its materials; nothing
else drawn changed.

### Traps

- **The skeleton's own space is the glTF armature's**, about a hundredth of a
  metre's scale away from the head's frame: the arm's `len_upper` / `len_fore`
  are in it. Laying a pose in head space with them put the fist at full reach;
  take lengths in the frame you lay the pose in.
- **A dither near the eye opens holes too**: at 0.14-0.22 m it ate the top of
  the left pauldron and showed the arm inside it. Fold what is in the way;
  keep the dither short.
- **Pose the body's look-bend for the eye, not just for the cut**: the chest
  following a straight-down look put the shoulders and back under the camera
  whatever the camera's offset.
- Harness: `Input.action_press` does not raise the guard -- player.gd reads the
  physical key or button (`_action_held`). Send the binding's own event through
  `Input.parse_input_event`.
