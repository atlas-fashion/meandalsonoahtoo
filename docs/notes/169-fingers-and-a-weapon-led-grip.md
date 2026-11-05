## 169. Fingers, and a grip the weapon leads (2026-11-05)

The user: "rig the hand and fingers in a way that is always holding the weapon,
and follows the position and rotation of it. the sword is trying to follow the
hand and even then the hand is clipping in weird ways into the weapon."

### Finger bones (tools/build_player_knight.py)

The Meshy rig the knight borrows (note 155) has no fingers. Each hand now gets:
- `<Side>HandFinger1..3`: one chain for the four fingers, from the knuckle line
  at |x| 0.935 out to 0.996 (`FINGER_JOINTS`), at `FINGER_Z` 1.345 and
  `FINGER_Y` 0.075;
- `<Side>HandThumb1..2`: `THUMB_JOINTS`, the thumb forward of the palm and below
  it.

Every gauntlet vertex past the knuckle line goes to the finger chain, and every
thumb vertex to the thumb, blended across ±5 mm at each joint. 897 finger and
388 thumb vertices. They go only to those bones: the borrowed weights had left
the fingertips a share of the forearm, which held them half straight however
far they curled. Rebuilt in 27 s.

### The grip (first_person_arms.gd)

- **The weapon leads.** `_held` gives each held thing a grip frame: where the
  fist closes, Z along the haft, X a sword's edge.
- **Outside an attack clip** the weapon is posed by its own moves and the hand
  is put exactly on its grip. The knuckles go along the sword's edge, on
  whichever side the arm comes from. The arm reaches it by IK; if the arm falls
  short, the weapon comes back with the wrist.
- **Through a clip** the arm is the capture's own, bone for bone, blended by the
  move's weight. The weapon goes in that hand's grip (`_clip_frame`), along the
  fist's own grip line.
  - The first try turned the sword to where the capture's prop seemed to lie
    (note 167's `BLADE_REST`) and solved the fist onto that. The IK's forearm
    twist then fought the capture's, and the gauntlet pinched mid-cut.
- **The seat.** `GRIP` (0.925, 1.306, -0.0736) seats the handle in the palm at
  the root of the fingers. It was the old curled-mesh fist's centre, under the
  knuckles, which is the middle of this gauntlet's fingers.
- **Fingers close until they touch** (`_grip_curl`):
  - Each joint in turn, knuckle first, closes as far as it can (up to
    `CLOSE_MAX`) before the finger beyond it comes within the handle. The
    handle is a cylinder of `HANDLE_R` about the haft's line (sword 1.6 cm,
    spear 1.7, axe 1.8, flask 3.4, rat's tail 0.4), and each finger is
    `HALF_FINGER` 9 mm thick.
  - The thumb lies along the haft (`THUMB_ON`).
  - Worked out once per hand and kind, in the hand's rest frame.
  - Empty, the hand hangs loose (`CURL_LOOSE`). The guard's left hand is a fist
    (`CURL_FIST`), eased out as the guard hands back.

### Seen

Close-ups along and across the hilt: the fingers round its front and under it,
with no clipping.

In first person, through a forehand slowed 20x:
- the gauntlet stays whole all through the cut;
- the sword is in the fist at every frame;
- the arm no longer pinches at the wrist.

### Traps

- **Bending the fingers at the knuckle first** (1.05 rad, a fist's worth) put
  them straight down through a handle that ran under the knuckles. Close them
  by contact.
- **The curl looked right in numbers but not on screen.** The bones moved; the
  vertices only followed them partway, because the fingertips still carried
  some forearm weight.
