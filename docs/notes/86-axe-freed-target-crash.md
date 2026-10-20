## 86. The axe: no crash when what it is stuck in is freed (2026-10-20)

**The bug.** The user hit `Invalid type in function '_is_down' in base
'GDScript'. The Object-derived class of argument 1 (previously freed) is not a
subclass of the expected argument class.` `axe.gd` `_is_down(body: Node)` was
typed, and `_update_flight` state 1 passes it `_stuck_in`, the enemy the
thrown axe is riding in. When that enemy is freed while the axe is in it (killed
by something else, or its corpse cleaned up inside the 1 s STICK_TIME), the
freed object hits the typed parameter and errors before the
`is_instance_valid` check inside can run. This is the section 4 trap: a freed
object cannot be passed to a typed parameter.

**The fix** (`scripts/axe.gd`):
- `_is_down(target)` is untyped, checks `is_instance_valid` first, then casts
  to `Node`.
- `_strike` checks `is_instance_valid(body)` straight after `take_damage`, and
  if the blow freed it the axe flies back without calling `knock` / `alert` /
  `hit_landed` (all take a typed body).
- `_slash` does the same: the hit still counts for `struck`, but a body freed
  by the blow is not knocked.

**Verified** with a throwaway `extends SceneTree` harness that `load()`s
`axe.gd` (the entry file cannot name `Graphics`, so a plain `--check-only` on
axe.gd fails on that line and proves nothing). It reported the script loads,
and `_is_down` of a freed `Node` and of `null` both return true with no error.
