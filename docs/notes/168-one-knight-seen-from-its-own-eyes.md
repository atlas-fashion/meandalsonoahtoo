## 168. One knight, seen from its own eyes (2026-11-05)

The user had three things to say about note 167:
- "the animations look awful in first person. they're too fast, all over the
  place and keep tearing";
- "don't have two sets of animations, that's counterproductive. use higgsfield
  to generate first person animations. the player shouldn't have two separate
  models for the camera and for third person, it should all be one model from
  different perspectives";
- asked about the camera, the weapon size and the scope: "make rotation
  adjustable", "decide one size and make the sword hitbox reach further than
  the model", "everything. items shouldn't have their own player model".

Higgsfield can't make new animations. Its 3D tools only rig a mesh with one of
Meshy's 678 library clips, so the attacks stay note 167's library clips. What
changed is that they are now seen from the knight's own eyes.

### One body (coop_avatar.gd)

- **The knight is drawn for its own camera.** It uses a copy of its mesh with the
  head, neck and pauldrons cut away (`HEAD_BONES`; `_cut_head` drops every
  triangle a corner of which is carried mostly by those bones). The cut is
  done once and shared by every player.
  - Alone: the headless copy is on the world layer; the whole knight casts the
    shadow on `SOLO_LAYER`.
  - Co-op: the headless copy is on the player's own viewmodel layer; the whole
    knight is on the other half's avatar layer.
- **No first-person arms model.** `models/player_knight_arms.glb` and its tool
  are gone. **No co-op props.** The body's own sword and spear copies are gone:
  the weapons under the head are the only ones, at real depth
  (`sword_draw_depth` 1.0, was 0.12) and on the world layer, so every camera
  sees them in the knight's hand. `_sweep_view_layers` is gone.
- **The pauldrons are cut** from the eye's copy. They sit at camera height
  either side and filled the bottom of the view through every cut.
- **Attack clips:**
  - The chest bends with the look (`LOOK_BEND` 0.6) and leans into the attack
    (`ATTACK_LEAN` 0.22 rad), so cuts go where the player looks, below the
    shoulder-height captures.
  - The sword's clips leave the left arm to the walk or guard (`right_only`):
    Left_Slash was captured with a shield on it, which came up across the view.
  - The body keeps each clip's own arm pose (`clip_arm`) for
    first_person_arms.gd.

### The arms (first_person_arms.gd)

- **They solve the body's own skeleton** instead of a copy.
- **The shoulder is the body's real joint.** It is never moved, so the arm never
  parts from the torso. Out of reach, the wrist stops short. The rest of the
  grip is note 169.
- **The guard's left arm** keeps its springs (note 158) and hands back to the
  walk when it is down and still (`_guard_w`).

### The camera

The camera rides the clip's head (player.gd `_head_ride`):
- its offset since the move's stance, weighted by the move: the ult's leap, the
  lunges and the crouches;
- plus `Graphics.head_sway` of its turn. That is **Settings → Controls → Head
  sway**, 0-100%, default 25%, saved under [controls].

Walking keeps the camera's own bob, not the body's.

### One size

- The sword is held at `SWORD_LENGTH` 1.25 m. The model is built 2.65 long, so it
  is scaled about its grip (`_real_size_sword`).
- The hit reaches `sword_hit_reach` 2.15 blade lengths from the guard.
- The potion is full size at full distance (held_potion.gd: SCALE 1, HOLD
  doubled; it was half size, half distance).

### Slower clips (player_motion.gd)

The cuts now run at 1.3-1.7x the capture; note 167 ran them at 2.5-3x. The first-person mapping
(`fp_sword`, the aim fix, `FP_LOWER`, the shoulder shift, the parry overlay,
the spear's posed sweep) is all gone: the hand is the body's.

| | bites (pose s) | real s to the hit | end |
|---|---|---|---|
| forehand | 0.25-0.40 | 0.31 | 0.75 |
| backhand | 0.15-0.31 (ends at its follow-through: the capture's recovery turned the body sideways) | 0.19 | 0.66 |
| heavy | 0.72-0.92 | 0.90 | 1.45 |
| ult | wave at 0.74, committed to 0.92 | 0.93 | 3.3 |
| spear jabs | 0.09 | | every 0.28 |
| lunge | 0.26, after 0.36 | | rest 0.62 |
| sweep | 0.6 | | |

Hits, measured with a frozen enemy and the player pinned:
- 1.4 and 1.9 m: every cut lands.
- 2.4 m: the forehand and the ult land. The backhand and the heavy missed, so
  the reach went from 1.9 to 2.15 after that run; it was not re-measured.

### Traps

- **`rm` of a glob or `$VAR/...`** is refused; use `${VAR:?}` paths.
- **A heredoc with `\'` in it** breaks the shell; write a script file instead.
- **A skinned mesh's vertices are in metres** even when its node is scaled 0.01.
  Don't multiply them by the node transform.
