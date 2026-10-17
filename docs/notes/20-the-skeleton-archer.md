## 20. The skeleton archer (2026-10-09)

- **`scripts/archer.gd`** extends enemy.gd. The maze puts it on an `enemy.tscn`
  instance BEFORE it enters the tree (`set_script`), at the back of a skeleton
  pack of 2+ with chance `archer_share` 0.5 (7 in the test level) -- never
  alone, so it has fellows to hide behind. Its numbers are in `_init` (a script
  swap drops the scene's overrides): 60 health, move 3.3 (slower than the
  player's 4.25), vision 140 deg, punch 8 when touched.
- **enemy.gd hooks**: every skeleton joins group "skeletons"; the chase calls
  `_chase(...)` (default false) after the wander/out-of-reach handling, so a
  kind can hunt its own way and fall back to the swing by returning false.
- **Shooting**: draws for 0.85 s (the bow comes up, string back, arrowhead
  brightens), looses when it has a clear line through stone (allies do not
  block), next shot 3-4.5 s after. **Distance**: backs off below 8 m along the
  navmesh (5 headings, best one further away), comes on beyond 17 m or with no
  line; slower than the player and stopped by corners, so it is caught.
  **Cover**: with a non-archer skeleton within 12 m it goes to stand 1.6 m
  behind it on the far side from the player, and only draws once settled there
  (or 1.5 s overdue) -- drawing mid-way left it standing in the open.
- **Arrows** (`scripts/arrow.gd`): 26 m/s, straight. The player and the archer
  are tested as capsules (`Geometry3D.get_closest_points_between_segments`), not
  by layer -- the player shares layer 1 with every skeleton. The hit is
  `take_damage(15, travel, proxy)`, so the guard applies: blocked, it falls
  aside (1.5 through); **parried, it homes back on its archer at 30 m/s and
  hits for the FULL 15** -- the player's own half-reflect lands on the `Proxy`,
  which takes nothing (and sits 1.3 m below the arrow, because the guard flash
  is placed 1.3 m above an attacker's origin). Stone stops it; it sticks 6 s.
- **The aim pose is code** (the rig has no bow clips): `_point_bone` turns a
  bone's +Y onto a direction with `set_bone_global_pose`, blended by `_aim`;
  left arm along the shot, right elbow out and back, hand to the jaw. The bow
  is procedural (arc of boxes, string spans, nocked arrow) placed at hand.L.
- Measured (harness, real right-click parry): 7 archers spawned; arrows 3.05-
  4.3 s apart, every hit 15; held off at 13.9 m; a parried arrow took exactly
  15 off its archer; a held guard let 1.5 through; backed from 4 to 9 m from a
  player standing still; chased with the keys, caught (0.8 m); with a fellow
  between, it stood 2.3 m behind it at 0.97 alignment. Posed bones measured:
  hand.L 0.70 m out along the shot, hand.R beside the jaw.

