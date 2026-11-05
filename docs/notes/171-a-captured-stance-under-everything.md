## 171. A captured stance under everything (2026-11-05)

The user, with a third-person screenshot of the knight holding the sword out
low and stiff at its side: "very very awkward pose. you can also tell in first
person".

### Why it was awkward

The attacks were captured clips, but nothing else was. At rest, the arm was
IK'd onto the old first-person rest pose (`REST_POS` / `REST_ROT`). That pose
was made for the 2.65 m first-person sword drawn at the hip. With the knight's
real sword, the arm stood straight out to the side and the wrist bent to point
the blade.

### The stance (player_motion.gd &"stance", coop_avatar.gd)

- **The clip.** Higgsfield's Sword_Parry (147): a held high guard, the weapon
  raised across the body. It runs on its own loop clock (`loop`, `_stance_t`)
  and is stripped as `models/anims/sword_guard.glb`.
  - Combat_Stance (89, 8 credits) was tried first. It looks right from outside,
    but holds the weapon low at the hip, below the view from the eyes. It was
    dropped.
- **When.** Whenever the hands are free to hold a weapon in it: player.gd
  `stance_wanted`, eased in and out over `STANCE_BLEND` 0.18 s.
  - The sword at rest, blocking, or in any of its clips.
  - The spear doing nothing posed of its own (spear.gd `stance_ok`).
  - The axe when not `busy`.
  - Not the slam, the haft strike, a scene, a throw, the flask or a rat: those
    are still IK'd to their own poses.
- **Layers** (`_apply_motion` → `_apply_clip`):
  - The stance goes on first, the attack or parry over it.
  - The body's `motion_w` is the two combined.
  - The arm kept for first_person_arms.gd (`clip_arm`) is the stance blended
    toward the attack by its weight.
  - So every stroke starts from the stance and blends back into it.
  - The left arm keeps to the walk (`right_only`; the capture held a shield).
- **Weapons.** The arms solver treats the axe like the sword and spear
  (`motion_w`), so all three sit in the stance's fist.
- **Hips.** They now take the clip's height from the capture's own rest, not
  from the move's first frame. A crouched stance with the hips left at standing
  height pushed the feet through the floor.
- **The left arm.** Down at the side lower (`lfore`).
- **The eye's copy** also leaves out the left upper arm (`HEAD_BONES` +
  "LeftArm"). It hung under the eye as a dark blob at the corner of the view;
  the forearm and fist, the guard, are still drawn.

### Seen

- **From outside:** the knight in a guard, sword raised diagonally across the
  body; the spear and the axe the same.
- **From the eyes:** the gauntlet at the bottom right, the weapon rising across
  the view, nothing else in the way.
- **A forehand** flows out of the guard and back.

Hits, measured with a frozen enemy:
- 1.4 and 1.9 m: every cut lands.
- 2.4 m: the forehand and the heavy land; the backhand doesn't.

The game runs clean headless.
