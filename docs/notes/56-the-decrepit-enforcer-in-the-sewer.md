## 56. The decrepit enforcer, in the sewer (2026-10-15)

- **The user's model** (`models/source/enforcer/PUTRID_ENFORCER_BAKED.blend`): a
  hunched, one-armed Tripo mech whose arm is a great pointed shield, on a 13-bone
  rig, with three baked clips -- CRAWL_BAKED (wander and chase), STABS_BAKED (the
  shield slam: three thrusts), JUMP_BAKED (the jump slash). The file also has the
  unbaked sources (JUMP on an unmuted track) and a SWIPE that was never baked and
  sits in a muted stash: only the baked three go out. `tools/build_decrepit.py`
  -> `models/decrepit.glb` (see tools/README.md). Drawn at `MODEL_SCALE` 0.65.
- **Build traps, all found by measuring**:
  - Root motion: STABS and JUMP carry the body forward (the jump 2.2 m). Pulled
    out of the clips in the build (TORSO and the two foot roots shifted back
    per frame) so they play in place; the travel is printed as the ROOT_* tables
    in decrepit.gd, and the BODY moves along them. Doing this at runtime fights
    the reaction layer's cross-fade, which blends bone positions too.
  - **The baked IK FLIPS the knees**: the crawl's last frame had both knees on
    the other side from its first (a 0.98 model-unit pop every loop, ~0.6 m in
    game), and STABS / JUMP flip a knee mid-clip in 2-3 frames. The IK
    constraints are dropped (the keys are the solved pose) and each knee's bend
    angle about its hip-foot line is eased across every flip over 7 frames
    either side, the leg re-solved so the foot stays put; the crawl as a cycle.
    Worst knee step per frame in Godot: crawl 0.98 -> 0.21, stabs 0.59 -> 0.21;
    the jump's 0.5 is the body leaping 2 m.
  - **The colour atlas baked pure BLACK**: Tripo marks every part fully
    metallic, and a metal has no diffuse colour. Metallic is zeroed before the
    bake. (The source images and UVs were fine -- check the BSDF first.)
- **scripts/decrepit.gd** (extends enemy.gd, group "decrepits", "DECREPIT
  ENFORCER", 150 health): chases at `CHASE_SPEED` 7.4 m/s (player 4.25), the crawl
  played at the rate that keeps its feet planted (4.886 m/s at the authored size).
  Its own move machine (`_run_move`) owns the body during an attack:
  - SHIELD SLAM within `SLAM_TRIGGER` 2.9 m: thrusts at clip 0.45 / 0.73 / 1.18 s,
    the first that lands deals 25 through the player's guard (`_strike` reads the
    `guarded` signal and the health). Unguarded: `player.knock_down(dir, 12)` --
    and at once the JUMP SLASH on them where they fell, re-aimed through its
    flight (the clip's travel scaled each frame so the point lands on them), 50
    at clip 0.70 s, after the player's 0.6 s of invulnerability and before they
    are up (1.12 s). Blocked: a tenth, shoved, standing.
  - JUMP SLASH on its own at 4-9 m with a clear floor (45% a roll, 3.5 s
    cooldown); sparks where the point hits the stone, hit or miss.
  - PARRIED (either): `_start_knockdown` topples the whole body back about its
    heels (KNOCK_FALL 0.4, KNOCK_PITCH 1.32 rad), lies KNOCK_LIE 1.0 s, heaved up
    in KNOCK_RISE 0.55 -- forward past upright into its crouch -- with the limbs
    flailing and twitching over it on the reaction layer; then straight back into
    the attack (measured: attacking 0.02-0.43 s after rising).
- **scripts/decrepit_react.gd**: the enforcer's reaction layer with this
  creature's clips -- three hits (HIT_SNAP head snapped back then hunching lower,
  HIT_WRENCH twisted and the shield swung across, HIT_BUCKLE knees giving), random
  and never twice running, the KNOCKED limbs, and a feral TWITCH now and then
  while it hunts. enforcer_react.gd now takes its clip set from `hits` /
  `stagger_clip` members (the enforcer's by default).
- Sparks on every blow: the enforcer's (`ENF._spark_burst`, shared and warmed).
- **It walks on its own floor**: sewer.gd `_build_feral_floor` lays boxes over
  every channel at walkway height on physics layer 14 (`FERAL_FLOOR`, 1 << 13),
  which only it collides with -- it straddles the water, the player still wades.
  The sewer has a navmesh now (`_build_nav`, its own NavigationRegion3D, parsed
  from group "sewer_nav": the stone and that floor; cell 0.25, radius 0.5): 482
  polygons, a path from one end of the sewer to the other.
- **Seen in the dark**: two amber eye points (markers found by sampling the
  mask's texture for its pale eyes) and a faint amber omni ahead of its face
  (`GLOW_*`, sewer layer + layer 1): without it only the eyes showed and an
  attack could not be read.
- **One at a time, only in the sewer** (maze.gd `_spawn_decrepit`): placed with
  the population, in a sewer cell >= `decrepit_spawn_clear` 30 m from the player
  and out of their sight; killed, the next comes `decrepit_respawn` 45 s later.
- Measured in a harness (18/18, re-run after every change): one, in the sewer,
  150 health; navmesh path end to end; chase 7.40 m/s; slam 25 + knocked down,
  then the jump 50 (100 -> 75 -> 25); jump from range 50 after a 4.7-5.6 m leap;
  parried: on its back (1.32 rad), ~1 s down, attacking again within 0.5 s;
  blocked 2.5; three reactions, never twice running; sparks; respawned 180-330 m
  off. **Smoothness**: bone positions in the model's frame, sampled once per
  drawn frame from `Skeleton3D.skeleton_updated` (the pose AFTER the
  cross-fades -- `get_bone_global_pose` in a plain frame read the clip without
  them and made every switch look like a snap), flagging any step more than
  2.5x the larger of the last two plus 0.2: 0 over 856 frames and 11 clip
  changes; control with the cross-fades removed: flagged at once.
- Bench (RTX 3060, 3440x1440, editor closed): 67.9 fps, worst p99 30.97 ms,
  1214 MB (67.6 / 31.06 / 1190 before; +23 MB its atlas).


