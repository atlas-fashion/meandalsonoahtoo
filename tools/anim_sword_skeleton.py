"""Every animation of the sword skeleton (notes 135, 136), and the export.

    blender -b models/source/sword_skeleton/sword_skeleton.blend -P tools/anim_sword_skeleton.py
    blender -b models/source/sword_skeleton/sword_skeleton.blend -P tools/anim_sword_skeleton.py -- --check
    blender -b models/source/sword_skeleton/sword_skeleton.blend -P tools/anim_sword_skeleton.py -- --sheet <dir> [clip,clip]
    godot --headless --import --path .

Opens the .blend tools/build_sword_skeleton.py wrote, writes one action a clip
at 60 fps, saves the .blend and exports models/sword_skeleton.glb.

Nothing is keyed by hand on bones. Each clip is a function of time returning a
`Spec`: where the feet are, what the hips and spine do, and each arm's joint angles.
`solve` turns a Spec into bone rotations (two-bone IK for the legs), so the feet
stay exactly where they are put.

    the ARMS are joint angles, never reached for: the upper arm's swing, its lift
    out to the side and its ROLL about its own length; the elbow, a hinge and
    nothing else; the wrist. This golem's blade grows out of its forearm, so a
    blow is the whole arm swung from the shoulder. An arm solved to reach a point
    rolls wherever the solution falls, and that is what twisted the old body's
    arms; here a roll is a key on a track, the arc comes from the joints turning,
    and `--check` measures it anyway (`spin`).

    the GAIT (`gait`) is built like a walk: a foot in stance is a point on the
    floor going backwards at the ground speed, rolling heel, flat, ball; in
    swing it runs a Hermite from toe-off to the next strike, with the speeds it
    had at each end. The hips ride over it, bob at the mid-stance (the walk) or
    the flight (the run); pelvis, chest and arms turn against each other.

    the BLOWS are keyed, a chain of late starts from the floor up: step, hips,
    chest, shoulder, then elbow, then wrist. One clip is the whole blow:
    wind-up, swing and recovery, on enemy.gd's own clock (LIGHT and HEAVY), so
    nothing has to blend inside a blow.

`root` is the root motion: where the body goes. The game takes that track out
of the clip and moves the CharacterBody3D by it, so a planted foot stays planted
through a step.

The model is skinned in its own pose, feet wide and arms hanging at angles. Every
bone has a rotation `X` from that pose into the CANONICAL one the angles here are
written in: legs and arms straight down, each hinge across X, the feet flat and
pointing forward. D (canonical) @ X is the rotation of the bone from the pose it
was modelled in.

Axes: X the skeleton's left, -Y its front, Z up. A rotation vector here:
    Rx(+) tips the top forward (toes down); Rz(+) turns it to its left;
    Ry(+) leans the top to its left.
"""

import bpy
import math
import os
import sys
from mathutils import Matrix, Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from build_sword_skeleton import BONES, FINGERS, PARENT, PIN_KNEE_L, PIN_KNEE_R, ROOT, SEG, SRC, V

OUT = os.path.join(ROOT, "models", "sword_skeleton.glb")
FPS = 60
TAU = math.tau

# enemy.gd / prosthetic.gd: the light slice's and the heavy's three phases.
LIGHT = (0.45, 0.32, 0.70)
HEAVY = (0.85, 0.42, 0.95)
# The speeds the locomotion clips are authored for (sword_skeleton.gd).
WALK_V = 1.55
RUN_V = 4.6
TURN_RATE = math.radians(100.0)
# A blow thrown from close in shuffles this share of the stride.
SHORT = 0.26

HEEL = 0.10         # the heel behind the ankle
BALL = 0.20         # the ball ahead of it
ANKLE = 0.19        # the ankle over the sole
# How far the claw's curl is from the fingers as modelled.
CURL0 = 0.4


def rad(d):
    return math.radians(d)


def rx(a):
    return Quaternion((1, 0, 0), a)


def ry(a):
    return Quaternion((0, 1, 0), a)


def rz(a):
    return Quaternion((0, 0, 1), a)


def rot(p=0.0, y=0.0, r=0.0):
    """Degrees: pitch (forward), yaw (to its left), roll (lean to its left)."""
    return rz(rad(y)) @ rx(rad(p)) @ ry(rad(r))


def wrist(flex=0.0, dev=0.0, twist=0.0):
    """Degrees, from the wrist as modelled: bent forward, out to the side (which
    side a +ve is depends on the arm), turned in its ring."""
    return rz(rad(twist)) @ rx(rad(-flex)) @ ry(rad(dev))


def sm(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def smr(x, a, b):
    return sm((x - a) / (b - a))


def track(keys):
    """Cubic through (t, value) keys, floats or tuples, flat at both ends;
    Catmull-Rom tangents held down where a key is a local peak, so a pose keyed
    as the extreme is the extreme."""
    ts = [k[0] for k in keys]
    vec = not isinstance(keys[0][1], (int, float))
    vals = [list(k[1]) if vec else [float(k[1])] for k in keys]
    n = len(keys)
    dim = len(vals[0])
    tan = [[0.0] * dim for _ in range(n)]
    for i in range(1, n - 1):
        for d in range(dim):
            a = (vals[i][d] - vals[i - 1][d]) / max(ts[i] - ts[i - 1], 1e-6)
            b = (vals[i + 1][d] - vals[i][d]) / max(ts[i + 1] - ts[i], 1e-6)
            if a * b <= 0.0:
                tan[i][d] = 0.0
            else:
                tan[i][d] = 2.0 * a * b / (a + b)

    def at(t):
        if t <= ts[0]:
            out = vals[0]
        elif t >= ts[-1]:
            out = vals[-1]
        else:
            i = 0
            while t > ts[i + 1]:
                i += 1
            h = ts[i + 1] - ts[i]
            u = (t - ts[i]) / max(h, 1e-6)
            u2, u3 = u * u, u * u * u
            h00, h10, h01, h11 = 2 * u3 - 3 * u2 + 1, u3 - 2 * u2 + u, -2 * u3 + 3 * u2, u3 - u2
            out = [h00 * vals[i][d] + h10 * h * tan[i][d] + h01 * vals[i + 1][d] + h11 * h * tan[i + 1][d] for d in range(dim)]
        return tuple(out) if vec else out[0]

    return at


def blur(fn, t, w, n=4):
    """`fn` over a tent `w` either side of `t`: takes the kick out of a track
    keyed hard, and keeps its timing."""
    tot = 0.0
    acc = None
    for i in range(-n, n + 1):
        k = 1.0 - abs(i) / (n + 1)
        v = fn(t + w * i / n)
        tot += k
        if isinstance(v, tuple):
            acc = [x * k for x in v] if acc is None else [a + x * k for a, x in zip(acc, v)]
        else:
            acc = v * k if acc is None else acc + v * k
    return tuple(a / tot for a in acc) if isinstance(acc, list) else acc / tot


class Spec:
    """One frame. Lengths in metres in the root's frame; angles in degrees."""

    def __init__(self):
        self.root = V(0, 0, 0)
        self.pelvis = V(0, 0, 1.30)
        self.pelvis_q = Quaternion()
        self.spine = (0.0, 0.0, 0.0)     # p, y, r, spread over the three bones
        self.neck = (0.0, 0.0, 0.0)
        self.head = (0.0, 0.0, 0.0)
        self.clav_l = (0.0, 0.0)         # up, forward
        self.clav_r = (0.0, 0.0)
        self.arm_l = (6.0, 12.0, 18.0)   # swing forward, out, elbow
        self.arm_r = (6.0, 12.0, 24.0)
        self.roll_l = 0.0                # the upper arm's roll: + turns the elbow's
        self.roll_r = 0.0                # bend in across the body, on either arm
        self.hand_l = Quaternion()
        self.hand_r = Quaternion()
        self.curl = 0.4
        self.spread = 0.5
        # Feet: the ankle, then the foot's pitch (toes down +), yaw, roll, and
        # the toes' bend.
        self.foot_l = (V(0.17, 0.0, ANKLE), 0.0, 8.0, 0.0, 0.0)
        self.foot_r = (V(-0.17, 0.0, ANKLE), 0.0, -8.0, 0.0, 0.0)
        self.knee_out = 0.12


REST = {}
RH = {}
for _b in BONES:
    RH[_b[0]] = _b[2]
TIP_REST = SEG["blade"][1]


def frame_of(y, x):
    """A rotation whose Y is `y`, its X as near `x` as can be."""
    y = y.normalized()
    x = (x - y * x.dot(y)).normalized()
    z = x.cross(y)
    return Matrix(((x.x, y.x, z.x), (x.y, y.y, z.y), (x.z, y.z, z.z))).to_quaternion()


def seg(b):
    return SEG[b][1] - SEG[b][0]


# Rotations from the bone as modelled into the canonical pose, and each hinged
# bone's own frame as modelled.
X = {}
RF = {}
LEN = {}
# Which way each toe points as modelled, degrees to its left of straight ahead.
FOOT_YAW = {"L": 50.0, "R": -31.0}
# The skull as modelled is turned off the body and tips over.
HEAD_OFF = rz(rad(-28.0)) @ ry(rad(8.0))
NECK_OFF = rz(rad(-10.0))
BLADE_EDGE = V(1, 0, 0)


def bind_rest(arm, body):
    for b in arm.data.bones:
        REST[b.name] = b.matrix_local.to_quaternion()
    canon_leg = frame_of(V(0, 0, -1), V(-1, 0, 0))
    canon_arm = frame_of(V(0, 0, -1), V(1, 0, 0))
    for side, pin in (("L", PIN_KNEE_L), ("R", PIN_KNEE_R)):
        for b in ("thigh." + side, "shin." + side):
            d = seg(b)
            RF[b] = frame_of(d, -pin)
            X[b] = canon_leg @ RF[b].inverted()
            LEN[b] = d.length
        q = rz(rad(-FOOT_YAW[side]))
        X["foot." + side] = q
        X["toe." + side] = q
        # The elbow folds in the plane the arm is bent in as modelled.
        u, f = seg("upper_arm." + side), seg("forearm." + side)
        hinge = f.cross(u).normalized()
        for b in ("upper_arm." + side, "forearm." + side):
            RF[b] = frame_of(seg(b), hinge)
            X[b] = canon_arm @ RF[b].inverted()
            LEN[b] = seg(b).length
        # The wrist as modelled is its neutral.
        X["hand." + side] = X["forearm." + side]
    X["blade"] = X["hand.R"]
    X["head"] = HEAD_OFF
    X["neck"] = NECK_OFF
    # The blade's flat: the widest way across it, out of the mesh.
    import numpy as np
    me = body.data
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    a, b = np.array(SEG["blade"][0]), np.array(SEG["blade"][1])
    ax = (b - a) / np.linalg.norm(b - a)
    t = (co - a).dot(ax)
    perp = (co - a) - t[:, None] * ax
    m = (t > 0.25) & (t < 0.8) & (np.linalg.norm(perp, axis=1) < 0.07)
    p = perp[m]
    _u, s, vt = np.linalg.svd(p - p.mean(0), full_matrices=False)
    global BLADE_EDGE
    BLADE_EDGE = Vector(vt[0].tolist()).normalized()
    print("[rig] blade edge as modelled", tuple(round(x, 3) for x in BLADE_EDGE), "width", round(float(np.ptp(p.dot(vt[0]))), 3), "thick", round(float(np.ptp(p.dot(vt[1]))), 3), "canonical",
          tuple(round(x, 3) for x in (X["hand.R"] @ BLADE_EDGE)), flush=True)


def two_bone(s, t, a, b, pole, soft=0.96):
    d = t - s
    dist = d.length
    reach = a + b
    # A soft limit: a leg nearly straight slows, never snaps.
    knee = reach * soft
    if dist > knee:
        over = dist - knee
        room = reach * 0.9995 - knee
        dist = knee + room * (1.0 - math.exp(-over / room))
    dist = max(dist, abs(a - b) + 0.01)
    u = d.normalized()
    p = (pole - u * pole.dot(u)).normalized()
    h = (a * a - b * b + dist * dist) / (2.0 * dist)
    side = math.sqrt(max(a * a - h * h, 0.0))
    j = s + u * h + p * side
    return j, s + u * dist, u.cross(p).normalized()


class Solved:
    pass


def solve(sp):
    """Bone -> local rotation, plus the two locations."""
    L, D, G, P = {}, {}, {}, {}
    I = Quaternion()

    def fk(b, q):
        p = PARENT[b]
        L[b] = q
        D[b] = D[p] @ q
        G[b] = D[b] @ X.get(b, I)
        P[b] = P[p] + G[p] @ (RH[b] - RH[p])

    L["root"] = I
    D["root"] = I
    G["root"] = I
    P["root"] = V(0, 0, 0)
    L["pelvis"] = sp.pelvis_q
    D["pelvis"] = sp.pelvis_q
    G["pelvis"] = sp.pelvis_q
    P["pelvis"] = sp.pelvis.copy()
    sa = sp.spine
    fk("spine.01", rot(sa[0] * 0.3, sa[1] * 0.3, sa[2] * 0.34))
    fk("spine.02", rot(sa[0] * 0.34, sa[1] * 0.34, sa[2] * 0.34))
    fk("chest", rot(sa[0] * 0.36, sa[1] * 0.36, sa[2] * 0.32))
    fk("neck", rot(*sp.neck))
    fk("head", rot(*sp.head))
    fk("clavicle.L", rot(sp.clav_l[1], 0.0, 0.0) @ ry(rad(-sp.clav_l[0])))
    fk("clavicle.R", rot(sp.clav_r[1], 0.0, 0.0) @ ry(rad(sp.clav_r[0])))

    # Legs.
    for side, foot, sgn in (("L", sp.foot_l, 1.0), ("R", sp.foot_r, -1.0)):
        ank, pitch, yaw, roll, toe = foot
        tb, sb, fb, kb = "thigh." + side, "shin." + side, "foot." + side, "toe." + side
        hip = P["pelvis"] + G["pelvis"] @ (RH[tb] - RH["pelvis"])
        pole = rz(rad(yaw)) @ V(sgn * sp.knee_out, -1.0, 0.0)
        knee, end, hinge = two_bone(hip, ank, LEN[tb], LEN[sb], pole)
        G[tb] = frame_of(knee - hip, hinge) @ RF[tb].inverted()
        P[tb] = hip
        G[sb] = frame_of(end - knee, hinge) @ RF[sb].inverted()
        P[sb] = knee
        D[fb] = rz(rad(yaw)) @ rx(rad(pitch)) @ ry(rad(roll))
        G[fb] = D[fb] @ X[fb]
        P[fb] = end
        fk(kb, rx(rad(toe)))

    # The arms: joint angles. `roll` is the upper arm's about its own length.
    sw, out, el = sp.arm_l
    fk("upper_arm.L", rx(rad(-sw)) @ ry(rad(-out)) @ rz(rad(-sp.roll_l)))
    fk("forearm.L", rx(rad(-el)))
    fk("hand.L", sp.hand_l)
    sw, out, el = sp.arm_r
    fk("upper_arm.R", rx(rad(-sw)) @ ry(rad(out)) @ rz(rad(sp.roll_r)))
    fk("forearm.R", rx(rad(-el)))
    fk("hand.R", sp.hand_r)
    fk("blade", I)

    # The claw, from the fingers as modelled.
    c = sp.curl - CURL0
    sprd = sp.spread - 0.5
    Gh = G["hand.L"]
    for i, name in enumerate(FINGERS):
        fan = (-0.16, -0.04, 0.06, 0.19)[i] * sprd
        q0 = ry(rad(70.0 * c)) @ rx(rad(-fan * 32.0))
        G[name + ".L"] = Gh @ q0
        P[name + ".L"] = P["hand.L"] + Gh @ (RH[name + ".L"] - RH["hand.L"])
        G[name + "b.L"] = G[name + ".L"] @ ry(rad(84.0 * c))
        P[name + "b.L"] = P[name + ".L"] + G[name + ".L"] @ (RH[name + "b.L"] - RH[name + ".L"])
    G["f0.L"] = Gh @ rx(rad(38.0 * c))
    P["f0.L"] = P["hand.L"] + Gh @ (RH["f0.L"] - RH["hand.L"])
    G["f0b.L"] = G["f0.L"] @ rx(rad(44.0 * c))
    P["f0b.L"] = P["f0.L"] + G["f0.L"] @ (RH["f0b.L"] - RH["f0.L"])

    out = Solved()
    out.q = {}
    for name in G:
        r = REST[name]
        par = PARENT[name]
        rel = G[name] if par is None else G[par].inverted() @ G[name]
        out.q[name] = r.inverted() @ rel @ r
    r = REST["root"]
    out.root_loc = r.inverted() @ sp.root
    r = REST["pelvis"]
    out.pelvis_loc = r.inverted() @ (sp.pelvis - RH["pelvis"])
    out.P = P
    out.G = G
    out.L = L
    out.D = D
    return out


# --- The gait ------------------------------------------------------------------------

def stance_foot(p, s, h_up, t_down, pf, pr):
    """p 0..1 through the stance: (y, z, pitch, toe bend). `s` the ground it
    travels; heel, flat, ball."""
    g = -s * 0.5 + s * p
    pitch = 0.0
    toe = 0.0
    if p < pf:
        pitch = -h_up * (1.0 - sm(p / pf))
        a = rad(pitch)
        y = g + HEEL + (-HEEL * math.cos(a) - ANKLE * math.sin(a))
        z = -HEEL * math.sin(a) + ANKLE * math.cos(a)
    elif p > pr:
        pitch = t_down * sm((p - pr) / (1.0 - pr)) ** 1.2
        a = rad(pitch)
        y = g - BALL + (BALL * math.cos(a) - ANKLE * math.sin(a))
        z = BALL * math.sin(a) + ANKLE * math.cos(a)
        toe = -pitch
    else:
        y, z = g, ANKLE
    return y, z, pitch, toe


def foot_at(phi, T, S, s, h_up, t_down, pf, pr, lift, y0, swing_pitch=0.0):
    phi = phi % 1.0
    if phi < S:
        y, z, pitch, toe = stance_foot(phi / S, s, h_up, t_down, pf, pr)
        return y + y0, z, pitch, toe
    e = 0.002
    dur = (1.0 - S) * T
    st_dur = S * T
    y1, z1, p1, t1 = stance_foot(1.0, s, h_up, t_down, pf, pr)
    y1b, z1b, p1b, _t = stance_foot(1.0 - e, s, h_up, t_down, pf, pr)
    y0a, z0a, p0a, _t = stance_foot(0.0, s, h_up, t_down, pf, pr)
    y0b, z0b, p0b, _t = stance_foot(e, s, h_up, t_down, pf, pr)
    dt = e * st_dur
    w = (phi - S) / (1.0 - S)
    w2, w3 = w * w, w * w * w
    h00, h10, h01, h11 = 2 * w3 - 3 * w2 + 1, w3 - 2 * w2 + w, -2 * w3 + 3 * w2, w3 - w2

    def herm(a, va, b, vb):
        return h00 * a + h10 * dur * va + h01 * b + h11 * dur * vb

    y = herm(y1, (y1 - y1b) / dt, y0a, (y0b - y0a) / dt)
    z = herm(z1, (z1 - z1b) / dt, z0a, (z0b - z0a) / dt)
    pitch = herm(p1, (p1 - p1b) / dt, p0a, (p0b - p0a) / dt)
    # Lifted through the swing, the heel coming up early in a run.
    z += lift * math.sin(math.pi * w ** 0.8) ** 1.4
    pitch += swing_pitch * math.sin(math.pi * w) ** 2
    toe = -p1 * (1.0 - sm(w / 0.5))
    return y + y0, z, pitch, toe


def gait(sp, phi, g):
    """Fills `sp` for phase `phi` (0: left heel strike, 0.5: right)."""
    T, S, s = g["T"], g["S"], g["s"]
    a = (phi, g["T"], S, s, g["heel"], g["toe"], g["pf"], g["pr"], g["lift"], g.get("y0", 0.0), g.get("sw_pitch", 0.0))
    yl, zl, pl, tl = foot_at(*a)
    a = (phi + 0.5, g["T"], S, s, g["heel"], g["toe"], g["pf"], g["pr"], g["lift"], g.get("y0", 0.0), g.get("sw_pitch", 0.0))
    yr, zr, pr_, tr = foot_at(*a)
    w = g["width"]
    sp.foot_l = (V(w, yl, zl), pl, 9.0, 0.0, tl)
    sp.foot_r = (V(-w, yr, zr), pr_, -9.0, 0.0, tr)
    c = math.cos
    sn = math.sin
    run = g.get("run", False)
    if run:
        bob = -g["bob"] * c(2.0 * TAU * (phi - S * 0.5))
    else:
        bob = -g["bob"] * c(2.0 * TAU * (phi + 0.02))
    x = g["sway"] * sn(TAU * (phi + 0.04))
    # The weight of the blade pulls the hips a little to its left, to balance.
    sp.pelvis = V(x + 0.006, g.get("hip_y", 0.0) + g.get("surge", 0.0) * c(2.0 * TAU * phi), g["z"] + bob)
    yaw = -g["pyaw"] * c(TAU * (phi + 0.01))
    roll = -g["proll"] * sn(TAU * (phi + 0.05))
    sp.pelvis_q = rz(rad(yaw)) @ rx(rad(g["plean"])) @ ry(rad(roll))
    cy = g["cyaw"] * c(TAU * (phi - 0.02))
    sp.spine = (g["lean"] + g.get("lean_b", 0.0) * c(2.0 * TAU * (phi - 0.1)), cy - yaw * 0.6, -roll * 0.7 + g.get("croll", 0.0) * sn(TAU * (phi - 0.02)))
    # The head rides level, a beat behind the chest.
    tot_yaw = yaw + cy - yaw * 0.6
    sp.neck = (g["neck"], -tot_yaw * 0.5, roll * 0.25)
    sp.head = (g["headp"] + g.get("nod", 0.0) * c(2.0 * TAU * (phi - 0.14)), -tot_yaw * 0.42, roll * 0.15)
    # The claw swings against the left leg, loose, its forearm late.
    al = -g["aswing"] * c(TAU * (phi - 0.05))
    ael = g["ael"] + g.get("ael_s", 0.0) * sn(TAU * (phi - 0.02 + 0.25))
    sp.arm_l = (g["a0"] + al, g["aout"] + 1.5 * sn(TAU * phi), ael)
    # The sword arm: heavy; it hardly swings, and the blade drags after it.
    ar = g["rswing"] * c(TAU * (phi - 0.08))
    arel = g["rel"] + g.get("rel_s", 0.0) * c(TAU * (phi - 0.18))
    sp.arm_r = (g["r0"] + ar, g["rout"], arel)
    sp.roll_r = g["rroll"]
    sp.roll_l = 6.0
    sp.hand_r = wrist(g["bp"] + g["bpa"] * c(TAU * (phi - 0.2)), g["by"], g.get("broll", 0.0))
    sp.hand_l = rot(-6.0 + 7.0 * sn(TAU * (phi - 0.12)), 0.0, 0.0)
    sp.curl = g["curl"] + 0.05 * sn(TAU * (phi + 0.1))
    sp.spread = 0.6
    sp.clav_l = (-1.0 + 2.0 * c(TAU * (phi + 0.5)), g.get("cf", 0.0) * al / max(g["aswing"], 1.0))
    sp.clav_r = (-3.0, g.get("cf", 0.0) * 0.6 * ar / max(g["rswing"], 1.0))


WALK_G = dict(T=1.2, S=0.63, s=WALK_V * 1.2 * 0.63, heel=20.0, toe=34.0, pf=0.16, pr=0.56, lift=0.06, width=0.12, z=1.285, bob=0.018, sway=0.032, pyaw=8.0,
              proll=4.5, plean=3.0, cyaw=9.0, lean=4.0, neck=2.0, headp=-13.0, nod=1.6, aswing=15.0, a0=4.0, aout=13.0, ael=21.0, ael_s=4.0, rswing=5.0, r0=7.0,
              rout=14.0, rroll=8.0, rel=32.0, rel_s=2.5, bp=0.0, bpa=3.0, by=-6.0, curl=0.42, cf=3.0, knee=0.1)
RUN_G = dict(T=0.74, S=0.3, s=RUN_V * 0.74 * 0.3, heel=8.0, toe=40.0, pf=0.14, pr=0.42, lift=0.17, width=0.095, z=1.21, bob=0.03, sway=0.02, pyaw=13.0, proll=4.0,
             plean=9.0, cyaw=17.0, lean=11.0, lean_b=2.2, neck=-6.0, headp=-22.0, nod=2.4, aswing=36.0, a0=8.0, aout=11.0, ael=68.0, ael_s=12.0, rswing=9.0, r0=16.0,
             rout=20.0, rroll=14.0, rel=56.0, rel_s=5.0, bp=4.0, bpa=4.0, by=-8.0, curl=0.6, cf=8.0, run=True, y0=0.05, sw_pitch=14.0, surge=0.01, hip_y=-0.03)


def walk(t, L):
    sp = Spec()
    gait(sp, t / L, WALK_G)
    return sp


def run(t, L):
    sp = Spec()
    gait(sp, t / L, RUN_G)
    return sp


def trailing(sp):
    """The arm back and the blade dragged behind it, clear of the cart in front:
    how a crew carries it, hauling (sword_skeleton.gd `_haul_anim`)."""
    sp.arm_r = (sp.arm_r[0] * 0.4 - 32.0, 14.0, 8.0)
    sp.roll_r = 0.0
    sp.hand_r = wrist(-42.0, 0.0, 0.0)
    return sp


def haul(t, L):
    return trailing(walk(t, L))


# --- Standing -------------------------------------------------------------------------

def harm(t, L, *terms):
    """A sum of whole-number harmonics, so it loops: (cycles, amount, phase)."""
    return sum(a * math.sin(TAU * (n * t / L + p)) for n, a, p in terms)


def idle(t, L):
    """Standing as it was made: feet wide, the blade hanging forward and out from
    the right, the claw half shut, head stooped. It sways, and looks about a little."""
    sp = Spec()
    br = harm(t, L, (2, 1.0, 0.0), (5, 0.18, 0.2))
    sw = harm(t, L, (1, 1.0, 0.1), (3, 0.3, 0.45))
    sp.pelvis = V(0.022 + 0.011 * sw, -0.004 + 0.004 * harm(t, L, (2, 1.0, 0.3)), 1.285 - 0.004 * br)
    sp.pelvis_q = rz(rad(3.5 + 1.2 * sw)) @ rx(rad(2.0)) @ ry(rad(-2.4 - 0.8 * sw))
    sp.spine = (5.0 + 0.9 * br, -3.5 - 1.0 * sw, 3.0 + 0.8 * sw)
    sp.neck = (2.0 + 0.5 * br, 1.0 + 3.0 * harm(t, L, (1, 1.0, 0.55)), 0.0)
    sp.head = (-12.0 - 0.4 * br + 1.0 * harm(t, L, (3, 1.0, 0.1)), 2.0 + 7.0 * harm(t, L, (1, 1.0, 0.6), (2, 0.35, 0.9)), 1.2 * harm(t, L, (1, 1.0, 0.0)))
    sp.clav_l = (-2.0 + 1.2 * br, 1.0)
    sp.clav_r = (-4.5 + 0.8 * br, 1.0)
    sp.arm_l = (5.0 + 1.5 * sw, 15.0 + 0.6 * br, 24.0 + 2.5 * harm(t, L, (2, 1.0, 0.7)))
    sp.arm_r = (8.0 + 0.8 * sw, 16.0 + 0.5 * br, 30.0 + 1.0 * harm(t, L, (2, 1.0, 0.1)))
    sp.roll_r = 6.0
    sp.roll_l = 8.0
    sp.hand_r = wrist(1.5 * harm(t, L, (2, 1.0, 0.25)), -8.0, 0.0)
    sp.hand_l = rot(-5.0, -4.0, 0.0)
    # The claw never quite stills.
    sp.curl = 0.4 + 0.05 * harm(t, L, (3, 1.0, 0.0)) + 0.04 * harm(t, L, (7, 1.0, 0.3))
    sp.spread = 0.7 + 0.2 * harm(t, L, (2, 1.0, 0.5))
    sp.foot_l = (V(0.2, 0.03, ANKLE), 0.0, 13.0, 0.0, 0.0)
    sp.foot_r = (V(-0.2, -0.09, ANKLE), 0.0, -12.0, 0.0, 0.0)
    return sp


def idle_haul(t, L):
    return trailing(idle(t, L))


STANCE = dict(l=(0.17, 0.22), r=(-0.15, -0.26), pz=1.235, yl=22.0, yr=-7.0)
# The guard: the blade forward and up, the claw out for balance.
GUARD = dict(arm=(24.0, 24.0, 70.0), roll=12.0, wr=(4.0, -6.0, 0.0), al=(30.0, 20.0, 66.0), rl=14.0)


def fight_base(t=0.0, L=2.2):
    sp = Spec()
    br = harm(t, L, (1, 1.0, 0.0), (2, 0.25, 0.3))
    sp.pelvis = V(0.006 + 0.006 * br, 0.0, STANCE["pz"] - 0.007 * br)
    sp.pelvis_q = rz(rad(16.0)) @ rx(rad(7.0))
    sp.spine = (9.0 + 1.2 * br, -8.0, 0.0)
    sp.neck = (0.0, -3.0, 0.0)
    sp.head = (-17.0 - 0.8 * br, -3.0, 0.0)
    sp.foot_l = (V(STANCE["l"][0], STANCE["l"][1], ANKLE), 0.0, STANCE["yl"], 0.0, 0.0)
    sp.foot_r = (V(STANCE["r"][0], STANCE["r"][1], ANKLE), 0.0, STANCE["yr"], 0.0, 0.0)
    g = GUARD
    sp.arm_r = (g["arm"][0] + 0.8 * br, g["arm"][1], g["arm"][2] + 1.2 * br)
    sp.roll_r = g["roll"]
    sp.hand_r = wrist(*g["wr"])
    sp.arm_l = (g["al"][0] + 1.2 * br, g["al"][1], g["al"][2] + 1.5 * br)
    sp.roll_l = g["rl"]
    sp.hand_l = rot(-14.0, 10.0, 0.0)
    sp.curl = 0.5
    sp.spread = 1.0
    return sp


def idle_fight(t, L):
    return fight_base(t, L)


# --- Blows ----------------------------------------------------------------------------

class Blow:
    """A blow's channels, each keyed on its own times. The feet are in the
    WORLD: root motion is taken off them, so a planted foot stands still."""

    def __init__(self, length):
        self.L = length
        self.ch = {}
        self.foot_keys = {}

    def key(self, name, keys):
        self.ch[name] = track(keys)

    def feet(self, side, plants):
        """`plants`: (t0, t1, (x, y), yaw, lift) for each step: the foot lifts at
        t0 from where it was and lands at t1 there. Before the first step it
        stands where the stance has it."""
        self.foot_keys[side] = plants

    def foot(self, side, t, root):
        st = STANCE["l" if side == "l" else "r"]
        pos = (st[0], st[1])
        yaw = STANCE["yl"] if side == "l" else STANCE["yr"]
        pitch = 0.0
        z = ANKLE
        toe = 0.0
        for t0, t1, to, yaw1, lift in self.foot_keys.get(side, []):
            if t >= t1:
                pos, yaw = to, yaw1
            elif t > t0:
                u = (t - t0) / (t1 - t0)
                e = sm(u)
                pos = (pos[0] + (to[0] - pos[0]) * e, pos[1] + (to[1] - pos[1]) * e)
                yaw = yaw + (yaw1 - yaw) * e
                z = ANKLE + lift * math.sin(math.pi * u) ** 1.1
                pitch = -18.0 * math.sin(math.pi * u) * (u - 0.35)
                # Pushed off the ball first, on the heel at the end.
                pitch += 18.0 * (1.0 - sm(u / 0.4)) * sm(u / 0.14)
                pitch -= 14.0 * sm((u - 0.72) / 0.28)
                toe = -6.0 * math.sin(math.pi * u)
            # A foot just down settles flat.
            if t1 <= t < t1 + 0.12:
                pitch = -14.0 * (1.0 - sm((t - t1) / 0.12))
                a = rad(pitch)
                z = ANKLE * math.cos(a) - HEEL * math.sin(a)
        # The root has gone `root` forward (-Y): the world's floor is that far
        # behind it.
        return (V(pos[0], pos[1] + root, z), pitch, yaw, 0.0, toe)


def blow_clip(bl):
    def fn(t, L):
        ch = bl.ch
        sp = fight_base()
        rooty = ch["root"](t)
        sp.root = V(0, -rooty, 0)
        p = ch["pelvis"](t)
        sp.pelvis = V(p[0], p[1], p[2])
        # Blurred too: at the end of a 2 m lever the hips and chest are as sharp
        # as anything the arm does.
        q = blur(ch["pq"], t, 0.05)
        sp.pelvis_q = rz(rad(q[1])) @ rx(rad(q[0])) @ ry(rad(q[2]))
        sp.spine = blur(ch["spine"], t, 0.05)
        sp.neck = ch["neck"](t)
        sp.head = ch["head"](t)
        a = blur(ch["arm"], t, 0.07)
        sp.arm_r = (a[0], a[1], a[3])
        sp.roll_r = a[2]
        w = blur(ch["wrist"], t, 0.05)
        sp.hand_r = wrist(*w)
        al = blur(ch["arm_l"], t, 0.06)
        sp.arm_l = (al[0], al[1], al[2])
        sp.roll_l = GUARD["rl"]
        sp.curl = ch["curl"](t)
        sp.clav_r = ch["clav_r"](t)
        sp.clav_l = ch["clav_l"](t)
        sp.foot_l = bl.foot("l", t, rooty)
        sp.foot_r = bl.foot("r", t, rooty)
        return sp

    return fn


def _b():
    b = fight_base()
    g = GUARD
    return dict(p=(b.pelvis.x, b.pelvis.y, b.pelvis.z), pq=(7.0, 16.0, 0.0), spine=(9.0, -8.0, 0.0), neck=(0.0, -3.0, 0.0), head=(-17.0, -3.0, 0.0),
                arm=(g["arm"][0], g["arm"][1], g["roll"], g["arm"][2]), wrist=g["wr"], al=g["al"])


def slash_1(k=1.0):
    """Light: raised back over its right shoulder, then down across the body to its
    left hip. The right foot drives forward through the blow; the left comes up
    after it."""
    w, a, r = LIGHT
    A, B = w, w + a
    E = A + a + r
    n = _b()
    bl = Blow(E)
    bl.key("root", [(0.0, 0.0), (0.28, 0.0), (A + 0.03, 0.14 * k), (A + 0.17, 0.52 * k), (B + 0.1, 0.62 * k), (E, 0.62 * k)])
    bl.key("pelvis", [(0.0, n["p"]), (0.2, (0.02, 0.05, 1.24)), (A - 0.05, (0.03, 0.09, 1.26)), (A + 0.12, (-0.03, -0.1, 1.19)), (B + 0.03, (-0.05, -0.15, 1.16)),
                      (B + 0.3, (-0.02, -0.06, 1.21)), (E, n["p"])])
    bl.key("pq", [(0.0, n["pq"]), (A - 0.04, (2.0, -22.0, -3.0)), (A + 0.13, (12.0, 16.0, 3.0)), (B + 0.04, (18.0, 40.0, 5.0)), (B + 0.34, (12.0, 22.0, 2.0)), (E, n["pq"])])
    bl.key("spine", [(0.0, n["spine"]), (0.08, (10.0, -2.0, 0.0)), (A, (-10.0, -30.0, 9.0)), (A + 0.15, (14.0, 12.0, -9.0)), (B + 0.05, (26.0, 36.0, -14.0)),
                     (B + 0.34, (16.0, 12.0, -5.0)), (E, n["spine"])])
    bl.key("neck", [(0.0, n["neck"]), (A, (-4.0, 14.0, -4.0)), (A + 0.16, (-3.0, -4.0, 4.0)), (B + 0.1, (-9.0, -16.0, 6.0)), (E, n["neck"])])
    bl.key("head", [(0.0, n["head"]), (A, (-14.0, 13.0, -5.0)), (A + 0.18, (-16.0, -6.0, 4.0)), (B + 0.12, (-20.0, -18.0, 6.0)), (E, n["head"])])
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (A, (12.0, -7.0)), (A + 0.13, (2.0, 10.0)), (B, (-4.0, 16.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (A, (3.0, 6.0)), (B, (2.0, -8.0)), (E, (0.0, 0.0))])
    # swing, out, roll, elbow.
    bl.key("arm", [(0.0, n["arm"]), (0.2, (74.0, 34.0, 2.0, 62.0)), (A - 0.05, (112.0, 36.0, -14.0, 92.0)), (A + 0.02, (114.0, 36.0, -16.0, 94.0)), (A + 0.1, (92.0, 26.0, -2.0, 78.0)),
                   (A + 0.18, (66.0, 8.0, 16.0, 50.0)), (A + 0.26, (48.0, -12.0, 34.0, 24.0)), (B + 0.04, (38.0, -26.0, 48.0, 12.0)), (B + 0.14, (34.0, -30.0, 52.0, 18.0)),
                   (B + 0.4, (28.0, -8.0, 34.0, 46.0)), (E, n["arm"])])
    bl.key("wrist", [(0.0, n["wrist"]), (0.2, (-8.0, -4.0, 0.0)), (A, (-16.0, 0.0, 0.0)), (A + 0.12, (-8.0, 0.0, 0.0)), (A + 0.22, (10.0, 0.0, 0.0)), (B + 0.1, (8.0, 0.0, 0.0)), (E, n["wrist"])])
    bl.key("arm_l", [(0.0, n["al"]), (A - 0.05, (46.0, 24.0, 82.0)), (A + 0.14, (10.0, 34.0, 50.0)), (B + 0.06, (-14.0, 38.0, 36.0)), (B + 0.4, (12.0, 28.0, 52.0)), (E, n["al"])])
    bl.key("curl", [(0.0, 0.5), (A, 0.25), (A + 0.16, 0.7), (B + 0.3, 0.45), (E, 0.5)])
    # The right foot goes in under the blow; the left is dragged up after it.
    bl.feet("r", [(A - 0.05, A + 0.19, (-0.16, -0.26 - 0.62 * k), -8.0, 0.03 + 0.045 * k)])
    bl.feet("l", [(B + 0.1, B + 0.42, (0.17, 0.22 - 0.62 * k), 22.0, 0.025 + 0.025 * k)])
    return blow_clip(bl), E


def slash_2(k=1.0):
    """Light: the backhand. The arm wound across to the left hip, the elbow forward
    and the upper arm rolled in, then the elbow opens and the blade comes up across
    the body and out high on its right."""
    w, a, r = LIGHT
    A, B = w, w + a
    E = A + a + r
    n = _b()
    bl = Blow(E)
    bl.key("root", [(0.0, 0.0), (0.3, 0.0), (A + 0.04, 0.16 * k), (A + 0.18, 0.48 * k), (B + 0.1, 0.56 * k), (E, 0.56 * k)])
    bl.key("pelvis", [(0.0, n["p"]), (A - 0.04, (0.04, 0.03, 1.2)), (A + 0.13, (0.0, -0.1, 1.21)), (B + 0.03, (-0.05, -0.13, 1.25)), (B + 0.34, (-0.01, -0.03, 1.22)), (E, n["p"])])
    bl.key("pq", [(0.0, n["pq"]), (A - 0.05, (12.0, 38.0, 3.0)), (A + 0.12, (8.0, 2.0, -2.0)), (B + 0.05, (3.0, -30.0, -5.0)), (B + 0.36, (5.0, -4.0, -2.0)), (E, n["pq"])])
    bl.key("spine", [(0.0, n["spine"]), (A, (18.0, 34.0, -9.0)), (A + 0.15, (8.0, -6.0, 5.0)), (B + 0.04, (-6.0, -34.0, 12.0)), (B + 0.36, (6.0, -14.0, 3.0)), (E, n["spine"])])
    bl.key("neck", [(0.0, n["neck"]), (A, (-2.0, -18.0, 3.0)), (A + 0.17, (0.0, 2.0, -3.0)), (B + 0.1, (0.0, 16.0, -5.0)), (E, n["neck"])])
    bl.key("head", [(0.0, n["head"]), (A, (-20.0, -17.0, 4.0)), (A + 0.18, (-16.0, 3.0, -2.0)), (B + 0.12, (-13.0, 15.0, -4.0)), (E, n["head"])])
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (A, (-3.0, 14.0)), (B, (10.0, 2.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (A, (2.0, -6.0)), (B, (2.0, 7.0)), (E, (0.0, 0.0))])
    bl.key("arm", [(0.0, n["arm"]), (0.2, (26.0, -6.0, 46.0, 62.0)), (A - 0.05, (26.0, -32.0, 76.0, 70.0)), (A + 0.02, (26.0, -34.0, 78.0, 72.0)), (A + 0.1, (36.0, -14.0, 84.0, 56.0)),
                   (A + 0.18, (50.0, 16.0, 86.0, 28.0)), (A + 0.26, (66.0, 40.0, 84.0, 12.0)), (B + 0.04, (80.0, 56.0, 76.0, 12.0)), (B + 0.14, (86.0, 60.0, 68.0, 18.0)),
                   (B + 0.4, (60.0, 40.0, 26.0, 50.0)), (E, n["arm"])])
    bl.key("wrist", [(0.0, n["wrist"]), (0.2, (-6.0, 0.0, 0.0)), (A, (-14.0, 0.0, 0.0)), (A + 0.12, (-6.0, 0.0, 0.0)), (A + 0.22, (-8.0, 0.0, 0.0)), (B + 0.1, (-12.0, 0.0, 0.0)), (E, n["wrist"])])
    bl.key("arm_l", [(0.0, n["al"]), (A, (-8.0, 34.0, 44.0)), (A + 0.14, (24.0, 30.0, 66.0)), (B + 0.05, (46.0, 22.0, 84.0)), (B + 0.4, (32.0, 22.0, 70.0)), (E, n["al"])])
    bl.key("curl", [(0.0, 0.5), (A, 0.65), (A + 0.16, 0.3), (B + 0.3, 0.5), (E, 0.5)])
    bl.feet("l", [(A - 0.08, A + 0.2, (0.09 + 0.08 * (1.0 - k), 0.22 - 0.74 * k), 28.0, 0.03 + 0.045 * k)])
    bl.feet("r", [(B + 0.04, B + 0.36, (-0.15, -0.26 - 0.56 * k), -7.0, 0.025 + 0.025 * k)])
    return blow_clip(bl), E


def slash_3(k=1.0):
    """Light: the overhead. Straight up, the blade down its back, then down the
    middle, the elbow opening late and the body folding after it."""
    w, a, r = LIGHT
    A, B = w, w + a
    E = A + a + r
    n = _b()
    bl = Blow(E)
    bl.key("root", [(0.0, 0.0), (0.3, 0.0), (A + 0.03, 0.14 * k), (A + 0.16, 0.42 * k), (B + 0.08, 0.5 * k), (E, 0.5 * k)])
    bl.key("pelvis", [(0.0, n["p"]), (A - 0.05, (0.0, 0.1, 1.27)), (A + 0.12, (-0.01, -0.1, 1.22)), (B + 0.02, (-0.02, -0.16, 1.12)), (B + 0.34, (-0.01, -0.05, 1.19)), (E, n["p"])])
    bl.key("pq", [(0.0, n["pq"]), (A - 0.05, (-3.0, 4.0, 0.0)), (A + 0.14, (14.0, 12.0, 0.0)), (B + 0.04, (24.0, 16.0, 0.0)), (B + 0.36, (12.0, 14.0, 0.0)), (E, n["pq"])])
    bl.key("spine", [(0.0, n["spine"]), (A, (-20.0, -10.0, 4.0)), (A + 0.15, (20.0, -2.0, -3.0)), (B + 0.05, (40.0, 2.0, -5.0)), (B + 0.34, (20.0, -4.0, -2.0)), (E, n["spine"])])
    bl.key("neck", [(0.0, n["neck"]), (A, (2.0, 0.0, 0.0)), (A + 0.17, (-10.0, 0.0, 0.0)), (B + 0.08, (-20.0, 0.0, 0.0)), (E, n["neck"])])
    bl.key("head", [(0.0, n["head"]), (A, (-8.0, 2.0, 0.0)), (A + 0.18, (-22.0, 0.0, 0.0)), (B + 0.1, (-30.0, 0.0, 0.0)), (E, n["head"])])
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (A, (14.0, -3.0)), (B, (-4.0, 13.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (A, (6.0, 2.0)), (B, (-2.0, 6.0)), (E, (0.0, 0.0))])
    bl.key("arm", [(0.0, n["arm"]), (0.2, (88.0, 24.0, 6.0, 62.0)), (A - 0.05, (134.0, 14.0, 2.0, 92.0)), (A + 0.02, (136.0, 14.0, 0.0, 94.0)), (A + 0.1, (118.0, 10.0, 0.0, 84.0)),
                   (A + 0.18, (90.0, 6.0, 2.0, 54.0)), (A + 0.26, (74.0, 4.0, 4.0, 22.0)), (B + 0.04, (78.0, 2.0, 6.0, 14.0)), (B + 0.14, (76.0, 2.0, 6.0, 22.0)), (B + 0.4, (46.0, 14.0, 10.0, 50.0)), (E, n["arm"])])
    bl.key("wrist", [(0.0, n["wrist"]), (0.2, (-6.0, 0.0, 0.0)), (A, (-20.0, 0.0, 0.0)), (A + 0.12, (-6.0, 0.0, 0.0)), (A + 0.22, (12.0, 0.0, 0.0)), (B + 0.1, (6.0, 0.0, 0.0)), (E, n["wrist"])])
    bl.key("arm_l", [(0.0, n["al"]), (A, (52.0, 26.0, 88.0)), (A + 0.15, (20.0, 30.0, 56.0)), (B + 0.06, (-12.0, 34.0, 34.0)), (B + 0.4, (14.0, 26.0, 52.0)), (E, n["al"])])
    bl.key("curl", [(0.0, 0.5), (A, 0.2), (A + 0.16, 0.75), (B + 0.3, 0.45), (E, 0.5)])
    bl.feet("r", [(A - 0.04, A + 0.18, (-0.14, -0.26 - 0.5 * k), -6.0, 0.03 + 0.04 * k)])
    bl.feet("l", [(B + 0.08, B + 0.4, (0.17, 0.22 - 0.5 * k), 22.0, 0.025 + 0.025 * k)])
    return blow_clip(bl), E


def heavy(k=1.0):
    """The heavy slice: a long wind-up, the whole body coiled back on its right
    leg, the upper arm rolled in so the elbow's bend lies flat and the blade trails
    behind at chest height; then flat across the whole front, the left foot planted,
    the hips leading, the elbow opening last; and it overbalances after it and has
    to catch itself."""
    w, a, r = HEAVY
    A, B = w, w + a
    E = A + a + r
    n = _b()
    bl = Blow(E)
    bl.key("root", [(0.0, 0.0), (0.2, -0.03), (A - 0.2, -0.1), (A, -0.07), (A + 0.16, 0.22 * k), (B, 0.42 * k), (B + 0.3, 0.46 * k), (E, 0.46 * k)])
    bl.key("pelvis", [(0.0, n["p"]), (0.3, (-0.03, 0.07, 1.21)), (A - 0.06, (-0.06, 0.13, 1.16)), (A + 0.14, (0.0, 0.0, 1.16)), (B, (0.06, -0.12, 1.15)), (B + 0.34, (0.03, -0.08, 1.18)), (E, n["p"])])
    bl.key("pq", [(0.0, n["pq"]), (0.3, (8.0, -18.0, 2.0)), (A - 0.06, (9.0, -46.0, 4.0)), (A + 0.13, (8.0, 4.0, 0.0)), (B - 0.04, (10.0, 56.0, -5.0)), (B + 0.34, (10.0, 42.0, -3.0)), (E, n["pq"])])
    bl.key("spine", [(0.0, n["spine"]), (0.36, (10.0, -32.0, 8.0)), (A, (5.0, -62.0, 11.0)), (A + 0.17, (12.0, -8.0, -3.0)), (B, (18.0, 50.0, -14.0)), (B + 0.3, (16.0, 34.0, -10.0)), (B + 0.62, (12.0, 8.0, -3.0)),
                     (E, n["spine"])])
    bl.key("neck", [(0.0, n["neck"]), (A, (0.0, 34.0, -5.0)), (A + 0.2, (-2.0, 6.0, 2.0)), (B + 0.05, (-5.0, -24.0, 7.0)), (B + 0.5, (-2.0, -10.0, 2.0)), (E, n["neck"])])
    bl.key("head", [(0.0, n["head"]), (A, (-16.0, 30.0, -6.0)), (A + 0.22, (-17.0, 4.0, 2.0)), (B + 0.05, (-18.0, -24.0, 8.0)), (B + 0.5, (-17.0, -9.0, 2.0)), (E, n["head"])])
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (A, (4.0, -15.0)), (A + 0.16, (1.0, 5.0)), (B, (2.0, 20.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (A, (2.0, 12.0)), (B, (1.0, -12.0)), (E, (0.0, 0.0))])
    bl.key("arm", [(0.0, n["arm"]), (0.3, (56.0, 52.0, 52.0, 84.0)), (A - 0.14, (64.0, 74.0, 84.0, 104.0)), (A + 0.02, (66.0, 78.0, 86.0, 108.0)), (A + 0.1, (74.0, 62.0, 86.0, 84.0)), (A + 0.19, (80.0, 34.0, 84.0, 44.0)),
                   (A + 0.28, (82.0, 4.0, 80.0, 16.0)), (B, (80.0, -20.0, 76.0, 10.0)), (B + 0.12, (76.0, -30.0, 72.0, 14.0)), (B + 0.4, (58.0, -14.0, 56.0, 34.0)), (B + 0.7, (40.0, 12.0, 30.0, 60.0)), (E, n["arm"])])
    bl.key("wrist", [(0.0, n["wrist"]), (0.3, (-8.0, 6.0, 0.0)), (A, (-18.0, 12.0, 0.0)), (A + 0.14, (-6.0, 14.0, 0.0)), (A + 0.28, (8.0, 14.0, 0.0)), (B + 0.2, (6.0, 10.0, 0.0)), (E, n["wrist"])])
    bl.key("arm_l", [(0.0, n["al"]), (A, (62.0, 18.0, 70.0)), (A + 0.18, (26.0, 30.0, 58.0)), (B, (-16.0, 40.0, 34.0)), (B + 0.45, (10.0, 30.0, 50.0)), (E, n["al"])])
    bl.key("curl", [(0.0, 0.5), (A, 0.2), (A + 0.2, 0.7), (B + 0.3, 0.45), (E, 0.5)])
    # Back onto the right leg, then the left stamps forward and the right
    # drags round after the blade.
    bl.feet("l", [(0.14, 0.4, (0.2, 0.1), 24.0, 0.04), (A - 0.08, A + 0.16, (0.22, 0.1 - 0.4 * k), 32.0, 0.03 + 0.04 * k), (B + 0.42, B + 0.76, (0.17, 0.22 - 0.46 * k), 22.0, 0.025 + 0.025 * k)])
    bl.feet("r", [(B + 0.06, B + 0.4, (-0.15, -0.26 - 0.46 * k), -7.0, 0.03 + 0.03 * k)])
    return blow_clip(bl), E


# --- Hit and fall ---------------------------------------------------------------------

def stagger(dirn):
    """Thrown by a blow. `dirn` where it is thrown toward: "b" back, "f"
    forward, "l" its left, "r" its right. The head goes last, the feet catch
    it in two steps, the sword arm flies out."""
    L = 1.1
    d = {"b": (0.0, 1.0), "f": (0.0, -1.0), "l": (1.0, 0.0), "r": (-1.0, 0.0)}[dirn]
    dx, dy = d
    lean_p = -dy * 24.0         # top goes the way it is thrown
    lean_r = dx * 18.0

    def fn(t, _L):
        sp = idle(0.6, 4.0)
        hit = blur(track([(0.0, 0.0), (0.06, 0.5), (0.14, 1.0), (0.3, 0.86), (0.52, 0.34), (0.8, -0.1), (L, 0.0)]), t, 0.05)
        late = blur(track([(0.0, 0.0), (0.09, 0.2), (0.18, 1.0), (0.36, 0.84), (0.6, 0.2), (0.86, -0.14), (L, 0.0)]), t, 0.07)
        dip = track([(0.0, 0.0), (0.12, 0.3), (0.34, 1.0), (0.58, 0.6), (0.86, 0.1), (L, 0.0)])(t)
        p0 = sp.pelvis
        sp.pelvis = V(p0.x + dx * 0.12 * hit, p0.y + dy * 0.1 * hit, p0.z - 0.1 * dip)
        sp.pelvis_q = sp.pelvis_q @ rot(lean_p * 0.5 * hit, -dx * 9.0 * hit, lean_r * 0.5 * hit)
        s0 = sp.spine
        sp.spine = (s0[0] + lean_p * 1.2 * hit + 8.0 * dip, s0[1] - dx * 22.0 * hit, s0[2] + lean_r * 1.1 * hit)
        n0, h0 = sp.neck, sp.head
        sp.neck = (n0[0] + lean_p * 0.5 * late, n0[1] + dx * 8.0 * late, n0[2] + lean_r * 0.45 * late)
        sp.head = (h0[0] + lean_p * 0.9 * late, h0[1] + dx * 14.0 * late, h0[2] + lean_r * 0.8 * late)
        l0, r0 = sp.arm_l, sp.arm_r
        sp.arm_l = (l0[0] + dy * 22.0 * late + 6.0 * late, l0[1] + (14.0 + dx * 12.0) * late, l0[2] + 26.0 * late)
        sp.arm_r = (r0[0] + max(dy, 0.0) * 12.0 * late + 6.0 * late, r0[1] + (12.0 - dx * 12.0) * late, r0[2] + (12.0 + 12.0 * max(-dy, 0.0)) * late)
        sp.hand_r = wrist(-10.0 * late, -8.0, 0.0)
        sp.curl = 0.4 + 0.45 * hit
        sp.spread = 1.0
        # Two catching steps. The body itself is carried by the knockback.
        back = dy > 0
        for side, t0, t1, off in (("r" if (back or dx < 0) else "l", 0.08, 0.3, 0.22), ("l" if (back or dx < 0) else "r", 0.26, 0.5, 0.19)):
            ft = sp.foot_l if side == "l" else sp.foot_r
            ank = ft[0].copy()
            u = max(0.0, min(1.0, (t - t0) / (t1 - t0)))
            e = sm(u)
            # Out along the blow, then home again as the clip ends.
            hme = sm((t - 0.62) / 0.42)
            ank = ank + V(dx, dy, 0.0) * (off * e * (1.0 - hme))
            ank.z = ANKLE + 0.06 * math.sin(math.pi * u) + 0.03 * math.sin(math.pi * max(0.0, min(1.0, (t - 0.62) / 0.42)))
            pit = -10.0 * math.sin(math.pi * u)
            nf = (ank, pit, ft[2], ft[3], ft[4])
            if side == "l":
                sp.foot_l = nf
            else:
                sp.foot_r = nf
        return sp

    return fn, L


def death_back():
    """Struck from the front: the head snaps back, the knees go, it folds down
    onto its back; the arms fall after it, and the blade rings on the floor."""
    L = 2.3

    def fn(t, _L):
        sp = idle(0.0, 4.0)
        fall = track([(0.0, 0.0), (0.2, 0.06), (0.46, 0.26), (0.74, 0.66), (0.94, 1.0), (1.03, 0.96), (1.14, 1.0)])(t)
        torso = track([(0.0, 0.0), (0.14, 0.1), (0.46, 0.26), (0.76, 0.72), (0.96, 1.0), (1.05, 0.965), (1.18, 1.0)])(t)
        z = 1.285 + (0.17 - 1.285) * fall
        y = track([(0.0, 0.0), (0.28, 0.14), (0.62, 0.42), (0.96, 0.8), (L, 0.8)])(t)
        sp.pelvis = V(0.02, y, z)
        ang = -86.0 * torso
        sp.pelvis_q = rx(rad(ang)) @ ry(rad(-3.0 * torso))
        wob = track([(0.0, 0.0), (0.96, 0.0), (1.02, -6.0), (1.14, 2.0), (1.3, 0.0), (L, 0.0)])(t)
        sp.spine = (track([(0.0, 5.0), (0.14, -9.0), (0.5, -5.0), (0.96, 2.0), (1.1, 4.0), (L, 3.0)])(t) + wob, -6.0 * torso, 4.0 * torso)
        sp.neck = (track([(0.0, 2.0), (0.08, -16.0), (0.4, -10.0), (0.96, 2.0), (1.06, 8.0), (L, 6.0)])(t), 6.0 * torso, 0.0)
        sp.head = (track([(0.0, -12.0), (0.09, -30.0), (0.45, -18.0), (1.0, -6.0), (1.08, -2.0), (L, -4.0)])(t), 16.0 * sm((t - 0.9) / 0.5), 4.0 * torso)
        a = track([(0.0, 0.0), (0.16, 0.5), (0.5, 1.0), (0.96, 0.5), (1.2, 0.12), (L, 0.1)])(t)
        sp.arm_l = (5.0 + 18.0 * a - 16.0 * torso, 15.0 + 26.0 * a + 28.0 * torso, 24.0 + 20.0 * a - 22.0 * torso)
        sp.arm_r = (8.0 + 20.0 * a - 6.0 * torso, 16.0 + 28.0 * a + 44.0 * torso, 30.0 + 22.0 * a - 26.0 * torso)
        sp.hand_r = wrist(-22.0 * torso, -8.0 + 8.0 * torso, 0.0)
        sp.curl = 0.4 + 0.45 * sm(t / 0.2) - 0.45 * sm((t - 1.0) / 0.5)
        sp.spread = 1.0
        # The legs: feet stay, knees rise, then slide out straight-ish.
        ky = track([(0.0, 0.0), (0.72, 0.02), (1.0, 0.1), (1.4, 0.2), (L, 0.2)])(t)
        sp.foot_l = (V(0.2 + 0.1 * fall, 0.03 - ky * 0.2, ANKLE), -30.0 * fall, 13.0 + 20.0 * fall, 0.0, 0.0)
        sp.foot_r = (V(-0.2 - 0.16 * fall, -0.09 - ky * 1.4, ANKLE * (1.0 - 0.2 * fall)), -46.0 * fall, -12.0 - 30.0 * fall, 0.0, 0.0)
        sp.knee_out = 0.12 + 1.1 * fall
        return sp

    return fn, L


def death_fwd():
    """Struck from behind: thrown forward, a stumbling step, then down on its
    face, one arm under it."""
    L = 2.2

    def fn(t, _L):
        sp = idle(0.0, 4.0)
        fall = track([(0.0, 0.0), (0.25, 0.08), (0.56, 0.44), (0.82, 1.0), (0.9, 0.97), (1.0, 1.0)])(t)
        torso = track([(0.0, 0.0), (0.14, 0.18), (0.4, 0.38), (0.8, 1.0), (0.9, 0.97), (1.02, 1.0)])(t)
        y = track([(0.0, 0.0), (0.3, -0.16), (0.82, -0.72), (L, -0.72)])(t)
        sp.root = V(0, 0, 0)
        sp.pelvis = V(0.02, y, 1.285 + (0.2 - 1.285) * fall)
        sp.pelvis_q = rx(rad(84.0 * torso)) @ ry(rad(4.0 * torso))
        wob = track([(0.0, 0.0), (0.82, 0.0), (0.9, 6.0), (1.02, -2.0), (1.2, 0.0), (L, 0.0)])(t)
        sp.spine = (track([(0.0, 5.0), (0.1, 22.0), (0.5, 14.0), (0.84, -2.0), (L, -5.0)])(t) + wob, 3.0, -4.0 * torso)
        sp.neck = (track([(0.0, 2.0), (0.1, -14.0), (0.6, -10.0), (0.84, -8.0), (L, -10.0)])(t), 0.0, 0.0)
        sp.head = (track([(0.0, -12.0), (0.12, -26.0), (0.6, -20.0), (0.86, -14.0), (L, -14.0)])(t), -34.0 * sm((t - 0.74) / 0.3), 0.0)
        a = track([(0.0, 0.0), (0.2, 0.5), (0.55, 0.8), (0.84, 1.0), (L, 1.0)])(t)
        b = track([(0.0, 0.0), (0.2, 0.3), (0.45, -0.1), (0.86, -0.3), (L, -0.3)])(t)
        sp.arm_l = (5.0 + 92.0 * a, 15.0 + 20.0 * a, 24.0 + 6.0 * a)
        sp.arm_r = (8.0 + 47.0 * b, 16.0 + 44.0 * sm(t / 0.5), 30.0 - 22.0 * sm((t - 0.1) / 0.4))
        sp.hand_r = wrist(-26.0 * sm(t / 0.4), -8.0, 0.0)
        sp.curl = 0.4 + 0.45 * sm(t / 0.2)
        sp.spread = 1.0
        # One stumbling step with the right foot, then both slide back flat.
        st = max(0.0, min(1.0, (t - 0.08) / 0.3))
        ry_ = -0.09 + (-0.56 + 0.09) * sm(st)
        rz_ = ANKLE + 0.09 * math.sin(math.pi * st)
        ly = 0.03
        rise = sm((t - 0.5) / 0.32)
        sp.foot_r = (V(-0.2, ry_ + rise * 0.78, rz_ + rise * 0.0), 78.0 * rise, -12.0, 0.0, 0.0)
        sp.foot_l = (V(0.2, ly + rise * 0.3, ANKLE + rise * 0.06), 80.0 * rise, 13.0, 0.0, 0.0)
        sp.knee_out = 0.12 + 0.3 * fall
        return sp

    return fn, L


def death_side():
    """The legs just stop: down on both knees, it hangs there a moment with its
    head dropping, then topples over to its left."""
    L = 2.5

    def fn(t, _L):
        sp = idle(0.0, 4.0)
        kn = track([(0.0, 0.0), (0.1, 0.06), (0.42, 1.0), (0.5, 0.96), (0.58, 1.0)])(t)
        over = track([(0.0, 0.0), (0.8, 0.0), (1.08, 0.3), (1.32, 1.0), (1.4, 0.97), (1.5, 1.0)])(t)
        pz = 1.285 + (0.66 - 1.285) * kn + (0.26 - 0.66) * over
        sp.pelvis = V(0.02 + 0.5 * over, 0.04 * kn, pz)
        sp.pelvis_q = rx(rad(14.0 * kn - 8.0 * over)) @ ry(rad(84.0 * over))
        sp.spine = (5.0 + 24.0 * kn - 8.0 * over, 0.0, 6.0 * kn - 3.0 * over)
        sp.neck = (2.0 + 16.0 * kn, 0.0, 0.0)
        sp.head = (-12.0 + 30.0 * sm((t - 0.3) / 0.5) - 14.0 * over, 0.0, 10.0 * over)
        sp.arm_l = (5.0 + 8.0 * kn + 30.0 * over, 15.0 + 8.0 * kn + 34.0 * over, 24.0 + 12.0 * over)
        sp.arm_r = (8.0 + 30.0 * kn + 2.0 * over, 16.0 + 16.0 * kn - 8.0 * over, 30.0 + 14.0 * kn - 26.0 * over)
        sp.hand_r = wrist(14.0 * kn - 30.0 * over, -8.0, 0.0)
        sp.curl = 0.4 + 0.25 * kn
        sp.spread = 0.8
        # The shins flat on the floor behind: ankles back and low.
        sp.foot_l = (V(0.2 + 0.5 * over, 0.03 + 0.6 * kn, ANKLE - 0.06 * kn + 0.26 * over), 66.0 * kn, 13.0, 16.0 * over, 0.0)
        sp.foot_r = (V(-0.2 + 0.25 * over, -0.09 + 0.7 * kn, ANKLE - 0.06 * kn + 0.04 * over), 66.0 * kn, -12.0, 16.0 * over, 0.0)
        return sp

    return fn, L


# --- Turning on the spot ----------------------------------------------------------------

def turn(sgn):
    """Stepping round: root yaw is the game's; in the root's frame a planted
    foot sweeps the other way, and each in turn is picked up and set ahead."""
    T = 0.9
    sweep = math.degrees(TURN_RATE) * T * 0.5

    def fn(t, L):
        sp = idle(t * 4.0 / T, 4.0)
        phi = t / T
        for side, base, off, x in (("l", 13.0, 0.0, 0.19), ("r", -12.0, 0.5, -0.19)):
            p = (phi + off) % 1.0
            stance = 0.52
            if p < stance:
                u = p / stance
                a = sgn * sweep * (0.5 - u)
                lift = 0.0
            else:
                u = (p - stance) / (1.0 - stance)
                e = sm(u)
                a = sgn * sweep * (-0.5 + e)
                lift = 0.05 * math.sin(math.pi * u)
            pos = rz(rad(a)) @ V(x, 0.0, 0.0)
            ank = V(pos.x, pos.y - 0.02, ANKLE + lift)
            ft = (ank, -10.0 * lift / 0.05, base + a, 0.0, 0.0)
            if side == "l":
                sp.foot_l = ft
            else:
                sp.foot_r = ft
        sw = math.sin(TAU * phi * 2.0)
        sp.pelvis = V(0.012 * math.sin(TAU * phi), -0.01, 1.28 + 0.008 * math.cos(TAU * phi * 2.0))
        sp.pelvis_q = rz(rad(sgn * 7.0)) @ rx(rad(2.0))
        sp.spine = (5.0, sgn * 9.0, 2.0 * sw)
        sp.neck = (2.0, sgn * 8.0, 0.0)
        sp.head = (-12.0, sgn * 12.0, 0.0)
        return sp

    return fn, T


# --- Bake -----------------------------------------------------------------------------

CLIPS = []
CHECK = ("head", "chest", "hand.L", "hand.R", "forearm.L", "forearm.R", "foot.L", "foot.R", "toe.L", "toe.R", "shin.L", "shin.R")
BLOWS = ("slash_1", "slash_2", "slash_3", "heavy")


def make_clips():
    def loop(name, fn, L):
        CLIPS.append((name, fn, L, True))

    def once(name, fn_len):
        CLIPS.append((name, fn_len[0], fn_len[1], False))

    loop("idle", idle, 6.0)
    loop("idle_fight", idle_fight, 2.2)
    loop("walk", walk, WALK_G["T"])
    loop("run", run, RUN_G["T"])
    loop("haul", haul, WALK_G["T"])
    loop("idle_haul", idle_haul, 6.0)
    a, b = turn(1.0), turn(-1.0)
    loop("turn_l", a[0], a[1])
    loop("turn_r", b[0], b[1])
    for k, tag in ((1.0, ""), (SHORT, "_s")):
        once("slash_1" + tag, slash_1(k))
        once("slash_2" + tag, slash_2(k))
        once("slash_3" + tag, slash_3(k))
        once("heavy" + tag, heavy(k))
    for d in "bflr":
        once("stagger_" + d, stagger(d))
    once("death_b", death_back())
    once("death_f", death_fwd())
    once("death_s", death_side())


def spin_about_z(q0, q1):
    """How far the second rotation has turned about the bone's own length from the
    first, in degrees: the twist part of the rotation between them."""
    d = q0.inverted() @ q1
    if d.w < 0.0:
        d = -d
    return math.degrees(2.0 * math.atan2(d.z, d.w))


def roll_report(name, lq, L):
    """An arm's roll as it is seen: its spin about its own length, frame by frame,
    and how far that adds up to. Spin is measured from one frame to the next, so
    it has no reference pose to go singular on, overhead or anywhere."""
    out = []
    for arm, key in (("R", "upper_arm.R"), ("L", "upper_arm.L")):
        tot, lo, hi, worst, at = 0.0, 0.0, 0.0, 0.0, 0
        qs = lq[key]
        for i in range(1, len(qs)):
            s = spin_about_z(qs[i - 1], qs[i])
            tot += s
            lo = min(lo, tot)
            hi = max(hi, tot)
            if abs(s) > worst:
                worst, at = abs(s), i
        out.append("%s upper roll %+.0f..%+.0f (peak %.1f/f @%d)" % (arm, lo, hi, worst, at))
    tw = [spin_about_z(Quaternion(), q) for q in lq["hand.R"]]
    out.append("wrist turn %+.0f..%+.0f" % (min(tw), max(tw)))
    print("[roll]  %-12s %s" % (name, "  ".join(out)), flush=True)


def blow_report(name, tips, grips, edges, A, B, root_of):
    """Where the blade is through the swing, and whether it cuts with its edge."""
    best = None
    lead = []
    for i in range(int(A * FPS), min(int(B * FPS) + 1, len(tips) - 1)):
        v = (tips[i + 1] - tips[i - 1])
        if v.length > 1e-5:
            axis = (tips[i] - grips[i]).normalized()
            vv = (v - axis * v.dot(axis)).normalized()
            lead.append(math.degrees(math.acos(min(1.0, abs(vv.dot(edges[i]))))))
    # The blade through the place the player stands: 1.3 m ahead of it at the
    # end of its step.
    zs, far = [], 0.0
    for i in range(int(A * FPS), min(int(B * FPS) + 1, len(tips))):
        t = tips[i] - V(0, root_of[i], 0)
        far = max(far, -t.y)
        zs.append(round(tips[i].z, 2))
    print("[blow]  %-12s tip z %.2f..%.2f, forward %.2f, speed peak %.1f m/s, edge off the cut: mean %.0f worst %.0f deg" % (
        name, min(zs), max(zs), far, max((tips[i + 1] - tips[i]).length * FPS for i in range(len(tips) - 1)), sum(lead) / max(len(lead), 1), max(lead) if lead else 0.0), flush=True)


def bake_clip(arm, name, fn, L, loop_):
    n = int(round(L * FPS))
    frames = n + 1
    data = {}
    for pb in arm.pose.bones:
        data[pb.name] = []
    roots, pelvs = [], []
    tracks = {}
    tips, grips, edges, rootz, low_tip = [], [], [], [], 9.0
    lq = {"upper_arm.R": [], "upper_arm.L": [], "hand.R": []}
    for f in range(frames):
        t = f / FPS
        ph = (f % n) / FPS if loop_ else t
        sp = fn(ph, L)
        s = solve(sp)
        for b, q in s.q.items():
            data[b].append(q)
        for b in CHECK:
            tracks.setdefault(b, []).append(s.P[b].copy())
        tip = s.P["blade"] + s.G["blade"] @ (TIP_REST - RH["blade"])
        tracks.setdefault("tip", []).append(tip)
        low_tip = min(low_tip, tip.z)
        tips.append(tip)
        grips.append(s.P["blade"].copy())
        edges.append(s.G["blade"] @ BLADE_EDGE)
        rootz.append(-sp.root.y)
        for b in lq:
            lq[b].append(s.L[b].copy())
        roots.append(s.root_loc)
        pelvs.append(s.pelvis_loc)
    # The worst jolt in the clip: change of a joint's velocity in one frame.
    worst = (0.0, "", 0)
    for b, pts in tracks.items():
        for i in range(2, len(pts)):
            dv = ((pts[i] - pts[i - 1]) - (pts[i - 1] - pts[i - 2])).length
            if dv > worst[0]:
                worst = (dv, b, i)
    print("[check] %-12s %.4f  %s @ %d   lowest tip %.2f" % (name, worst[0], worst[1], worst[2], low_tip), flush=True)
    roll_report(name, lq, L)
    base = name[:-2] if name.endswith("_s") else name
    if base in BLOWS:
        w, a, _r = HEAVY if base == "heavy" else LIGHT
        blow_report(name, tips, grips, edges, w, w + a, rootz)
    # Quaternion continuity, frame to frame.
    for b, qs in data.items():
        for i in range(1, len(qs)):
            if qs[i].dot(qs[i - 1]) < 0.0:
                qs[i] = -qs[i]
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    slot = act.slots.new('OBJECT', arm.name)
    layer = act.layers.new("L")
    strip = layer.strips.new(type='KEYFRAME')
    bag = strip.channelbag(slot, ensure=True)

    def curve_of(path, group, idx, vals):
        fc = bag.fcurves.new(path, index=idx, group_name=group)
        fc.keyframe_points.add(len(vals))
        co = []
        for i, v in enumerate(vals):
            co += [float(i), v]
        fc.keyframe_points.foreach_set("co", co)
        fc.keyframe_points.foreach_set("interpolation", [1] * len(vals))    # LINEAR
        fc.update()

    for b, qs in data.items():
        if not qs:
            continue
        path = 'pose.bones["%s"].rotation_quaternion' % b
        for k in range(4):
            curve_of(path, b, k, [q[k] for q in qs])
    for b, vals in (("root", roots), ("pelvis", pelvs)):
        path = 'pose.bones["%s"].location' % b
        for k in range(3):
            curve_of(path, b, k, [v[k] for v in vals])
    act.frame_range = (0.0, float(n))
    return act


def sheet(arm, actions, out_dir, only, count=9):
    """A strip of poses per clip, in Workbench: enough to judge a pose."""
    import numpy as np
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'SINGLE'
    sc.display.shading.single_color = (0.62, 0.58, 0.52)
    sc.display.shading.show_cavity = True
    sc.display.shading.show_shadows = True
    sc.render.resolution_x, sc.render.resolution_y = 300, 340
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    cd = bpy.data.cameras.new("Cam")
    cd.lens = 66.0
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    gm = bpy.data.meshes.new("Fl")
    gm.from_pydata([(-9, -9, 0), (9, -9, 0), (9, 9, 0), (-9, 9, 0)], [], [(0, 1, 2, 3)])
    sc.collection.objects.link(bpy.data.objects.new("Fl", gm))
    os.makedirs(out_dir, exist_ok=True)
    arm.animation_data_create()
    for name, act in actions.items():
        if only and name not in only:
            continue
        arm.animation_data.action = act
        arm.animation_data.action_slot = act.slots[0]
        L = act.frame_range[1]
        strip = []
        for view, loc in (("side", V(6.6, -0.5, 1.3)), ("q", V(-3.6, -5.6, 1.5))):
            row = []
            for i in range(count):
                f = L * i / (count - 1)
                sc.frame_set(int(round(f)))
                bpy.context.view_layer.update()
                root = arm.pose.bones["root"].matrix.translation.copy()
                cam.location = loc + V(0, root.y, 0)
                at = V(0, root.y - 0.3, 1.38)
                cam.rotation_euler = (at - cam.location).to_track_quat('-Z', 'Y').to_euler()
                sc.render.filepath = os.path.join(out_dir, "_f.png")
                bpy.ops.render.render(write_still=True)
                img = bpy.data.images.load(sc.render.filepath, check_existing=False)
                w, h = img.size
                px = np.empty(w * h * 4, dtype=np.float32)
                img.pixels.foreach_get(px)
                row.append(px.reshape(h, w, 4)[::-1])
                bpy.data.images.remove(img)
            strip.append(np.concatenate(row, axis=1))
        pic = np.concatenate(strip, axis=0)
        h, w, _c = pic.shape
        out = bpy.data.images.new("sheet_" + name, w, h, alpha=True)
        out.pixels.foreach_set(pic[::-1].ravel())
        out.filepath_raw = os.path.join(out_dir, name + ".png")
        out.file_format = 'PNG'
        out.save()
        bpy.data.images.remove(out)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    sheet_dir = argv[argv.index("--sheet") + 1] if "--sheet" in argv else None
    only = None
    if sheet_dir:
        i = argv.index("--sheet") + 2
        if i < len(argv):
            only = argv[i].split(",")
    arm = bpy.data.objects["SwordSkeletonRig"]
    body = bpy.data.objects["SwordSkeletonBody"]
    bind_rest(arm, body)
    arm.animation_data_create()
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    make_clips()
    sc = bpy.context.scene
    sc.render.fps = FPS
    actions = {}
    for name, fn, L, loop_ in CLIPS:
        if only and name not in only:
            continue
        actions[name] = bake_clip(arm, name, fn, L, loop_)
    if "--check" in argv:
        return
    if sheet_dir:
        sheet(arm, actions, sheet_dir, only)
        return
    arm.animation_data.action = None
    # The exporter takes every action of the rig, one clip each, by name.
    sc.frame_start = 0
    sc.frame_end = 200
    # Godot names what it extracts <glb>_<image>.
    for img in bpy.data.images:
        if img.name.startswith("sword_skeleton_"):
            img.name = img.name[len("sword_skeleton_"):]
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "sword_skeleton.blend"), compress=True)
    b = bpy.data.objects["SwordSkeletonBody"]
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    b.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format='GLB',
        use_selection=True,
        export_animations=True,
        export_animation_mode='ACTIONS',
        export_force_sampling=True,
        export_anim_slide_to_zero=True,
        export_frame_step=1,
        export_optimize_animation_size=False,
        export_skins=True,
        export_def_bones=False,
        export_yup=True,
        export_apply=False,
        export_tangents=True,
        export_image_format='AUTO',
    )
    print("[anim] wrote", OUT, flush=True)


main()
