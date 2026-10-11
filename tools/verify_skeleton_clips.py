"""Re-import the exported GLB and MEASURE what each clip actually does.

Checks the shipped artifact, not the authoring intent -- the pose specs were
written from reasoning about axis signs, and reasoning about axis signs is
exactly the thing that is silently wrong half the time.
"""

import bpy
import sys

GLB = sys.argv[sys.argv.index("--") + 1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)

arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
dg = bpy.context.evaluated_depsgraph_get()

print("ARMWORLD", [round(v, 3) for row in arm.matrix_world for v in row])
print("BONES", len(arm.data.bones))
print("ACTIONS", sorted(a.name for a in bpy.data.actions))

# Rest-pose sanity: which way does this thing face?
fl = arm.data.bones["foot.L"]
d = (fl.tail_local - fl.head_local).normalized()
print("REST foot.L dir (%.3f,%.3f,%.3f)  -> toes point %s"
      % (d.x, d.y, d.z, "-Y (forward)" if d.y < -0.3 else "??"))


def sample(action_name, frame, bones):
    act = bpy.data.actions.get(action_name)
    if act is None:
        print("MISSING", action_name)
        return None
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = act
    if hasattr(ad, "action_slot") and act.slots:
        try:
            ad.action_slot = act.slots[0]
        except Exception:
            pass
    bpy.context.scene.frame_set(int(frame))
    ev = arm.evaluated_get(bpy.context.evaluated_depsgraph_get())
    out = {}
    for b in bones:
        pb = ev.pose.bones[b]
        out[b] = (ev.matrix_world @ pb.head).copy()
        out[b + ":tail"] = (ev.matrix_world @ pb.tail).copy()
    out["__chest"] = (ev.matrix_world @ ev.pose.bones["chest"].matrix).copy()
    return out


def rel_to_chest(vals, bone):
    """Where a hand sits in the torso's own frame.

    The off arm swings through the world whenever the chest rotates into a
    punch, which is correct mechanics -- so 'is it still in guard?' can only be
    asked relative to the chest.
    """
    return vals["__chest"].inverted() @ vals[bone]


def show(tag, vals, bones):
    parts = []
    for b in bones:
        v = vals[b]
        parts.append("%s=(%.3f,%.3f,%.3f)" % (b, v.x, v.y, v.z))
    print("  %-22s %s" % (tag, "  ".join(parts)))


ok = True


def check(label, cond, detail):
    global ok
    print("  %-52s %s   %s" % (label, "PASS" if cond else "FAIL", detail))
    if not cond:
        ok = False


LIMBS = ["foot.L", "foot.R", "hand.L", "hand.R", "head", "pelvis"]

print("\n--- idle ---")
for f in (0, 24, 48):
    show("frame %d" % f, sample("idle", f, LIMBS), ["head", "hand.L"])

print("\n--- walk (stride + limp) ---")
w0 = sample("walk", 0, LIMBS)
w12 = sample("walk", 12, LIMBS)
show("f0", w0, ["foot.L", "foot.R"])
show("f12", w12, ["foot.L", "foot.R"])
check("walk f0: LEFT foot leads (smaller Y)",
      w0["foot.L"].y < w0["foot.R"].y - 0.08,
      "L.y=%.3f R.y=%.3f" % (w0["foot.L"].y, w0["foot.R"].y))
check("walk f12: RIGHT foot leads (mirrored)",
      w12["foot.R"].y < w12["foot.L"].y - 0.05,
      "L.y=%.3f R.y=%.3f" % (w12["foot.L"].y, w12["foot.R"].y))
stride0 = abs(w0["foot.L"].y - w0["foot.R"].y)
stride12 = abs(w12["foot.L"].y - w12["foot.R"].y)
check("walk: strides differ (the limp)", abs(stride0 - stride12) > 0.02,
      "stride f0=%.3f  f12=%.3f" % (stride0, stride12))

print("\n--- run (lean + bigger stride) ---")
r0 = sample("run", 0, LIMBS)
show("f0", r0, ["foot.L", "foot.R", "head", "pelvis"])
check("run: torso leans forward (head ahead of pelvis)",
      r0["head"].y < r0["pelvis"].y - 0.05,
      "head.y=%.3f pelvis.y=%.3f" % (r0["head"].y, r0["pelvis"].y))
run_stride = abs(r0["foot.L"].y - r0["foot.R"].y)
check("run: stride longer than walk", run_stride > stride0,
      "run=%.3f walk=%.3f" % (run_stride, stride0))

print("\n--- attack_1: left straight ---")
a0 = sample("attack_1", 0, LIMBS)
a3 = sample("attack_1", 3, LIMBS)
show("guard f0", a0, ["hand.L", "hand.R"])
show("peak f3", a3, ["hand.L", "hand.R"])
reach = a0["hand.L"].y - a3["hand.L"].y
throw_l = (a3["hand.L"] - a0["hand.L"]).length
throw_r = (a3["hand.R"] - a0["hand.R"]).length
check("attack_1: LEFT fist travels", throw_l > 0.28, "fist moves %.3f m" % throw_l)
check("attack_1: and drives forward", reach > 0.15, "forward %.3f m" % reach)
off_r = (rel_to_chest(a3, "hand.R") - rel_to_chest(a0, "hand.R")).length
check("attack_1: left leads, right holds guard (torso frame)",
      throw_l > off_r * 2.5, "L %.3f m vs off-arm %.3f m" % (throw_l, off_r))

print("\n--- attack_2: right hook ---")
b0 = sample("attack_2", 0, LIMBS)
b4 = sample("attack_2", 4, LIMBS)
show("guard f0", b0, ["hand.R"])
show("peak f4", b4, ["hand.R"])
hook_travel = (b4["hand.R"] - b0["hand.R"]).length
check("attack_2: RIGHT fist travels", hook_travel > 0.3,
      "fist moves %.3f m" % hook_travel)
# A hook is mostly lateral, so it is judged on the crossing, not forward reach.
check("attack_2: hooks ACROSS the centreline", b4["hand.R"].x > 0.0,
      "x %.3f -> %.3f" % (b0["hand.R"].x, b4["hand.R"].x))
off_l = (rel_to_chest(b4, "hand.L") - rel_to_chest(b0, "hand.L")).length
check("attack_2: left holds guard (torso frame)", off_l < hook_travel * 0.4,
      "off-arm %.3f m vs hook %.3f m" % (off_l, hook_travel))
check("attack_1 and attack_2 are distinct moves",
      (a3["hand.L"] - b4["hand.L"]).length + (a3["hand.R"] - b4["hand.R"]).length > 0.4,
      "peak poses differ by %.3f m"
      % ((a3["hand.L"] - b4["hand.L"]).length + (a3["hand.R"] - b4["hand.R"]).length))

print("\n--- attack_3: overhead smash ---")
c0 = sample("attack_3", 0, LIMBS)
c3 = sample("attack_3", 3, LIMBS)
c7 = sample("attack_3", 7, LIMBS)
show("guard f0", c0, ["hand.L", "hand.R"])
show("raised f3", c3, ["hand.L", "hand.R"])
show("smash f7", c7, ["hand.L", "hand.R"])
check("attack_3: fists raise overhead", c3["hand.L"].z > c0["hand.L"].z + 0.35,
      "z %.3f -> %.3f" % (c0["hand.L"].z, c3["hand.L"].z))
check("attack_3: then smash down", c7["hand.L"].z < c3["hand.L"].z - 0.5,
      "z %.3f -> %.3f" % (c3["hand.L"].z, c7["hand.L"].z))
check("attack_3: both arms together", abs(c3["hand.L"].z - c3["hand.R"].z) < 0.06,
      "dz %.3f" % abs(c3["hand.L"].z - c3["hand.R"].z))
# Raised on X alone the fists end up 1.3 m apart and it reads as arms thrown
# open, not as a two-fisted raise.
gap3 = abs(c3["hand.L"].x - c3["hand.R"].x)
check("attack_3: fists close over the skull, not splayed", gap3 < 0.6,
      "fists %.3f m apart" % gap3)
check("attack_3: fists clear the head", c3["hand.L"].z > 2.0,
      "fist z %.3f, skull top ~2.13" % c3["hand.L"].z)

print("\n--- lunge: forward leap ---")
l0 = sample("lunge", 0, LIMBS)
l4 = sample("lunge", 4, LIMBS)
l14 = sample("lunge", 14, LIMBS)
l19 = sample("lunge", 19, LIMBS)
show("guard f0", l0, ["pelvis", "foot.L"])
show("crouch f4", l4, ["pelvis", "foot.L"])
show("soar f14", l14, ["pelvis", "foot.L"])
show("strike f19", l19, ["pelvis", "hand.L"])
check("lunge: crouches first", l4["pelvis"].z < l0["pelvis"].z - 0.1,
      "z %.3f -> %.3f" % (l0["pelvis"].z, l4["pelvis"].z))
check("lunge: leaves the ground", l14["pelvis"].z > l4["pelvis"].z + 0.3,
      "z %.3f -> %.3f" % (l4["pelvis"].z, l14["pelvis"].z))
check("lunge: feet tuck up while airborne", l14["foot.L"].z > l0["foot.L"].z + 0.15,
      "foot z %.3f -> %.3f" % (l0["foot.L"].z, l14["foot.L"].z))
check("lunge: lands into a strike", l19["pelvis"].z < l14["pelvis"].z - 0.25,
      "z %.3f -> %.3f" % (l14["pelvis"].z, l19["pelvis"].z))
# The controller supplies horizontal travel; the mesh must stay on its collider.
maxdrift = 0.0
for f in range(0, 27):
    s = sample("lunge", f, ["pelvis"])
    maxdrift = max(maxdrift, abs(s["pelvis"].x), abs(s["pelvis"].y))
check("lunge: no horizontal root drift off the collider", maxdrift < 0.12,
      "max |x|,|y| = %.3f m" % maxdrift)

print("\n--- jaw ---")
# Measured against the skull's own axis. World-space Z is useless here: the head
# bone rotates too, and that swamps the jaw's own movement.
def jaw_angle(clip, frame):
    import math as _m
    s = sample(clip, frame, ["jaw", "head"])
    hd = (s["head:tail"] - s["head"]).normalized()
    jd = (s["jaw:tail"] - s["jaw"]).normalized()
    return _m.degrees(_m.acos(max(-1.0, min(1.0, hd.dot(jd)))))

shut = jaw_angle("idle", 0)
wide = jaw_angle("attack_3", 3)
soar_jaw = jaw_angle("lunge", 14)
check("jaw opens during the smash", wide > shut + 8.0,
      "%.1f deg -> %.1f deg" % (shut, wide))
check("jaw opens mid-leap", soar_jaw > shut + 8.0,
      "%.1f deg -> %.1f deg" % (shut, soar_jaw))

print("\n--- clip lengths (seconds @24fps) ---")
for name in ("idle", "walk", "run", "windup", "attack_1", "attack_2",
             "attack_3", "lunge", "recover"):
    a = bpy.data.actions.get(name)
    if a:
        fr = a.frame_range
        print("  %-10s %5.2f s  (frames %.0f-%.0f)"
              % (name, (fr[1] - fr[0]) / 24.0, fr[0], fr[1]))

print("\nRESULT", "ALL PASS" if ok else "FAILURES PRESENT")
