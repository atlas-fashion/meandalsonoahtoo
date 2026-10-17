## 69. The dropkick's left-foot hitbox (2026-10-17)

The user: "add a hitbox to the left foot as well for the dropkick animation".
Supersedes note 68's reach check for the dropkick.

- `scripts/shield_hitbox.gd` is now any BONE's hitbox (`setup(..., node_name)`);
  the decrepit has a second, "FootHitbox", on FOOT_L, sized the same way (the
  vertices skinned to the bone, x1.5): 1.38 x 1.52 x 1.15 m. The dropkick's
  windows test it (`_touches`, with a clear line); the shield's box is not live
  during the dropkick, the foot's not during anything else (`_set_hitbox(shield,
  foot)`).
- **The window had to move.** Tracking the foot box's centre from the body
  through the clip (in game, 8 m off -- at 40 m the animation LOD does not
  animate it at all): over the top of the flip at f47 (1.4 m ahead, 4.2 m up),
  OUT IN FRONT f49-f51 (2.2 m ahead, sweeping down 3.0 -> 1.2 m: head and chest
  height), at the floor f53, planted from f55. The window note 68 set, f55-f61,
  came from "whichever foot is furthest out" and opened after the left one had
  landed: 0 damage from every distance, the box's centre never nearer the
  player than ~1.9 m. Now DROPKICK_HITS [[0.8167, 0.8833]] (f49-f53), and
  DROPKICK_TIP -- what the leap is stretched to land -- is the left foot's own
  reach, 2.1 m (was 2.53 x MODEL_SCALE = 1.64, "the furthest foot").
- Measured (throwaway harnesses, deleted; the sandbox, real time): the dropkick
  from 5, 6 and 7.5 m landed 35 each through the foot box (its centre within
  0.33-0.47 m of the player's middle), the foot box live and the shield's not;
  the swipe (+ its follow-up jump 75), the jump 50 and the dash 15 from 10 m
  still land through the shield box with the foot's never live. A windowed
  capture shows the foot box coming down past the player's head.
