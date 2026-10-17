## 42. Parry the bombers; the door's own Tripo arch; doors in 23 pieces (2026-10-14)

- **Bombers are fought, not struck with E** (`scripts/bomber.gd` rewritten; the
  haft strike, its prompt and `swat()` are gone from it -- `player.haft_strike`
  is now unused). 50 health; every weapon hurts it (the weapons' `swat` skips
  no longer match). States CHASE -> WINDUP (0.4 s, swells and flares) -> LUNGE
  (15 m/s at the face) -> FACE. It only winds up within `lunge_range` 3.4 m
  with a clear line on the SIGHT layer (2) -- shut doors are on it -- and not
  at a hidden player or one in a scene. Reaching the face is a blow through
  `player.take_damage(latch_damage 8, dir, self)`: the player's own guard
  decides it. Parried (read from the player's `guarded` signal, which fires
  inside that call) it is thrown off and SHATTERS, harmless. Otherwise it sticks
  -- placed every frame in `_process` (process_priority 10, after the camera)
  FACE_DIST 0.78 in front of the eye, drawn at FACE_SCALE 0.62 -- blinking for
  `face_fuse` 1.8 s, then `take_damage(explosion_damage 50, dir, self)` again
  through the guard (block 10%, parry 0), and it shatters (bigger, burning)
  with a fireball. Killed by damage it shatters harmlessly. Health bar back.
- On the face its glow is scaled by FACE_GLOW 0.35 and its light by FACE_LIGHT
  0.25, and it blinks hot orange (FACE_HOT): at the full white blink, at the
  camera, it was a flat white disc and lit every wall in view white. The sphere
  is 24 x 12 segments now (12 x 6 showed facets that close).
- Measured with the real right mouse button (12/12): unguarded -> wound up,
  lunged, stuck 0.68 s after spawn, rode the face to 2 mm, 8 + 50 taken; RMB
  as it lunges -> 0 taken, 10 pieces; guard held from before -> 5.8 (10% of
  each); RMB 0.25 s before it goes off -> only the 8; 20 + 20 leaves it alive,
  a third breaks it; behind a shut door 4 s -> never wound up, no damage;
  control, the same door open -> attacked.
- **The door's stone is Tripo's empty arch** (`door_arch`, tools/README.md):
  the door photo edited to the arch with no door, image to model. Kicked, the
  door leaves one stone throughout -- the old `door_frame` was cut from the door
  piece, hollow where the leaf was, and lined by a strip in another texture
  (`_door_reveal_mesh`, removed). The leaf is drawn `LEAF_FIT` (1.05, 1.03)
  larger to tuck into the new jambs and head, and has a dark BACKING sheet in
  its middle plane: the door piece's leaf has a pinhole, which the old frame
  had hidden. Light test (unlit magenta panel behind each shut door, 6 doors x
  2 sides x 3 views): 707 px before the backing (all through that one hole),
  0 after; control with the leaves hidden 1.56M.
- **Doors break into 23 pieces** (`wood_door._split_for`: 4 x 6, slant 0.35,
  head not merged; the old 7 without `Graphics.effects`): median longest side
  0.78 m (was 1.05), largest 1.21 (was 1.99); the burst 12 ms the first time,
  ~1.5 after (11 / 0.7 before), frames still at vsync. `door_debris.shatter`
  now puts the leaf's scale on each piece's mesh and box (a RigidBody takes no
  scale).
- Tripo: 5 + 40 credits, 210 left.
- Bench (RTX 3060, 3440x1440, Ultra, editor closed): 74.5 fps, worst p99
  27.13 ms, 1090 MB (74.1 / 27.72 / 1085 before) -- noise.

