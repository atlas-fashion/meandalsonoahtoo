## 172. The sword with weight: a physics layer over the clips (2026-11-05)

The user asked about games whose attacks run on dynamic armatures (Half Sword,
Blade & Sorcery, Exanima, Hellish Quart), then: "come up with a prototype".
The version before it is kept on the branch `backup/before-physics-arm` and
the tag `v-before-physics-arm` (c012b68).

### The idea

The captured clip is the TARGET, not the pose, the way Exanima and Hellish
Quart drive their bodies. A simulated sword is carried toward where the clip
has it, the world gets a say, and the arm is bent to hold the sword where it
ended up. Sword only: the spear, the axe, the flask and the rat are as before.

### The simulation (scripts/sword_physics.gd, owned by first_person_arms.gd)

It runs in the knight's own frame (the skeleton's, orthonormal), on two damped
springs, in substeps of 1/240 s:
- **The hilt**, stiff (`HILT_SPRING` 34 rad/s, damping 0.85): the arm carrying
  it is strong.
- **The blade's turn about the hilt**, softer and under-damped (`BLADE_SPRING`
  17 rad/s, 0.5). Its mass is out along the blade, so a fast stroke trails the
  wrist, swings on past where the clip stops, and settles back.
- **Limits**: never more than `MAX_LAG` 0.7 rad or `MAX_SLIP` 0.12 m off the
  clip; it is still the stroke.
- **Turning the body** leaves `TURN_DRAG` 0.35 of the blade's turn behind.

The world:
- **Walls** (layers 1 and 2; anything that can be cut is passed through):
  - first a ray from the eye out to the hilt; where it meets a wall the hilt
    stops just short. A stroke that steps the knight forward would otherwise
    put the whole fist in the wall.
  - then a ray up the blade from the hilt; where it meets a wall the blade is
    turned about the hilt until its tip is `WALL_GAP` 3 cm off it, and the
    swing into it is turned back (`BOUNCE` 0.3).
  - a first meeting faster than `CLANG_SPEED` 2.2 m/s at the tip is a clang:
    block sparks where it struck and a jolt of the view (`_take_clang`). A
    blade only pressed to the wall stops dead, with no bounce or sparks.
- **A cut that lands bites** (`hit_landed` → `bite`): the blade loses half its
  swing and kicks back a little.

### The arm (first_person_arms.gd `_bend_to`)

From the pose the clip and the IK left, the arm is bent so the fist goes from
the clip's grip to the simulated one, keeping the pose's plane and twist:
- the hand turned with the sword about the handle;
- the elbow opened or closed for the reach;
- the upper arm swung to point at it.

The sword is then put in the fist as it ended up (`_clip_frame`), so the hand
always has it. Bending from the capture's own pose, rather than solving the
arm afresh, keeps the forearm twist that pinched the gauntlet in note 169 out
of it.

### What lands is unchanged

The hits follow the clip's sword, not the drawn one (player.gd `_hit_pivot`,
set by the arms each frame). The weight is seen and felt; what a stroke reaches
and when it lands are as timed.

### The setting

"Sword weight" in the settings (`Graphics.sword_weight`, saved under
[controls]), 0..1, default 1. It scales how loose the springs are. At 0 the
sword is exactly the clip's, walls and all, as before this note.

### Measured (headless, 60 fps)

- **Walls**, 0.85 m in front, a slash, a chop and a heavy: the tip got 1.21,
  0.60 and 0.60 m past the wall at weight 0; at weight 1, 0.000 m. The blade
  lies along the wall for a few frames, then the stroke carries on.
- **Hits**, a frozen enemy at 1.4, 1.9 and 2.4 m: identical to weight 0, the
  same hits at the same frames. Drawing the hits from the simulated sword had
  delayed them a frame and cost the heavy its 2.4 m reach, which is why they
  follow the clip.
- **The stance**: no added jitter (the biggest step a frame 6.8 mm, against
  7.2 at weight 0).
- **A 90° turn in 9 frames**: the tip drags up to 0.21 m behind (0.06 at weight
  0) and settles back within about 15 frames.

Seen: in first person the blade trails the fist through the wind-up and the
cut, and lies flat along a wall instead of going into it. From outside, the
heavy is whole, with the sword in the fist all through.

### Traps

- **A blade ray started up the blade** (12 cm, to skip the fist) starts inside
  the wall once the hilt is pressed to it, and sees nothing. It starts at the
  hilt.
- **The slash steps the body forward**, so the hand itself reaches into a wall
  0.85 m away. Hence the eye-to-hilt ray first.
- **`class_name` scripts aren't known to `--script` harnesses** until the editor
  has scanned them. It is preloaded (`const SwordPhysics := preload(...)`).

### Not yet

- The knight's body still goes through walls in third person; only the sword
  is stopped.
- No sound: the game has no clang to play yet.
- The springs are one set for every stroke. The heavy could be looser and the
  slash tighter.
