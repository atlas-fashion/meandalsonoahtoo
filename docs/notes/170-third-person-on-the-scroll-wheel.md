## 170. Third person on the scroll wheel (2026-11-05)

The user: "give me the ability to switch to third person for testing. make the
player face the direction that they are walking rather than the camera when in
third person ... do it with the scroll wheel like skyrim".

### Controls (player.gd `_unhandled_input`)

- Mouse wheel DOWN pulls the camera out of the knight's eyes, `THIRD_STEP` 0.6 m
  a notch, starting at `THIRD_MIN` 1.2 m, up to `THIRD_MAX` 4.8 m.
- Mouse wheel UP brings it back in. Below THIRD_MIN it goes straight back into
  first person.
- `third_person` is the target distance. `_third` follows it smoothly.
- The wheel isn't bound to anything else in play: the weapon wheel has the
  mouse while it is open, and the map takes the wheel for its zoom.

### The camera (`_update_third_person`, after `_update_head`)

- **Position**: over the right shoulder (`THIRD_SHOULDER` 0.45 right, 0.25 up),
  `_third` metres behind the head's height, orbiting with the look (yaw and
  pitch).
- **Walls**: a ray from the head keeps it `THIRD_WALL` 0.2 m short of anything
  the player collides with or the level geometry. The ray first used
  `geometry_mask` alone and went straight through a wall on layer 1.
- **First person** puts the camera back at the head's origin
  (`camera.transform` = identity).
- **What holds it in first person**: a scene, death, hiding or a robot rat's
  eyes (`in_third_person`).

### Facing

- **The knight** (coop_avatar.gd, the one body, note 168) turns to face the way
  it walks: `_body_yaw` from the velocity in the player's frame, at
  `THIRD_TURN` 9 rad/s.
- **Back to the aim** whenever its hands are at work (`_hands_at_work`): a
  stroke or any pose, the guard, a slam, the spear's or the axe's moves,
  drinking. So everything goes where the crosshair is.
- **What it holds** turns with it. The head's yaw is turned by `_body_yaw`
  (everything held is posed in the head's frame), while the camera keeps the
  player's own look.
- **Its own camera sees the whole knight**, helmet and pauldrons too, and its
  shadow, instead of the headless copy (`set_third_person`).

### Seen

Headless renders at 60 fps:
- scrolled out 3.6 m, from behind;
- walking left, facing left;
- walking back, facing the camera;
- a slash turning back to the aim;
- backed against a wall, the camera in front of it;
- scrolled back in, first person again.
