## 73. The enforcer's swipe, re-baked by the user (2026-10-17)

The user fixed the swipe's IK flips themselves (note 72) and sent
`ENFORCER_UNBAKED.blend` (Documents/blender/crystalia/Blender/), whose only
baked clip is SWIPE_BAKED -- 70 frames, the same length, so every timing
(SWIPE_CONTACT, SWIPE_HITS) stands. Same rig (rest pose 0.00000 apart) and
meshes.

- Swapped into `models/source/enforcer/ENFORCER_BAKED.blend` under the old
  name: the new action replaces SWIPE_1_BAKED on its NLA track (slot
  assigned), so the game, the build and the timing preview are unchanged. The
  walk, beam and recoil are the second delivery's, as before. Rebuilt with
  tools/build_enforcer.py; the atlas came out byte-identical.
- Measured: the flips are gone -- f14 (SHOULDER_L 135 deg, ARM_L 95 deg in a
  frame) and f23 (98) -- the biggest one-frame turn now 67 deg at f25-26, the
  strike itself; the shield's fastest frames 23-25 (was 24). Rendered in Godot
  between frames: the shield stays outside the body through f22-26 (it passed
  inside the torso at f22-24 before). In the sandbox 3 swipes of 3 landed, 22
  each, at clip 0.37 s (inside SWIPE_HITS 22/60..26/60).
