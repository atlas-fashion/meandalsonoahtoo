"""Every animation of the Proel swordsman (notes 135, 136, 139), and the export. The
names in the files are its old ones: sword_skeleton.

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
    wind-up, swing and recovery, on enemy.gd's own clock (LIGHT, HEAVY, TEMPO), so
    nothing has to blend inside a blow. Their weight is timing (note 137): a long
    lift, a short swing, and a swing that does not stop where the blow ends. The
    beats are set out above `slash_1`. A LINK (note 138) takes one blow's recovery
    into another's wind-up, so a chain of them does not blend either.

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
from build_sword_skeleton import BONES, FINGERS, PARENT, PIN_KNEE_L, PIN_KNEE_R, ROOT, SEG, SRC, V, light_eyes

OUT = os.path.join(ROOT, "models", "sword_skeleton.glb")
FPS = 60
TAU = math.tau

# The light slice's and the heavy's three phases as they are keyed: wind-up, swing,
# recovery. TEMPO is how much faster than the keys every blow and link plays (note 142),
# so the proportions, which are the weight, cannot drift. Over TEMPO these are
# prosthetic.gd's BLADE_* and HEAVY_* and sword_skeleton.gd plays them at 1x, so the
# swing here is enemy.gd's ATTACK state and the blade can only hurt in it. Change both,
# and BLOW_TEMPO with TEMPO. `reel` and the gaits are not blows and do not take it.
LIGHT = (0.9, 0.24, 1.3)
HEAVY = (1.25, 0.3, 1.85)
TEMPO = 2.24  # 1.15 (note 142) x 1.5 (note 148) x 1.3 (note 167)
# How much of each recovery is keyed; the last of those keys is stretched to fill it,
# running down to a stand (`Blow.clock`, note 138).
LIGHT_KEYED, LIGHT_SETTLE = 1.0, 0.7
HEAVY_KEYED, HEAVY_SETTLE = 1.45, 1.05
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

# Going after someone, a proel has one of three gaits, so a pack does not move as one (note
# 141). Walk and run are the first and stay as they are. Each foot covers the ground at the
# same speed; what differs is the build of the stride and how the blade is carried.
# LOW: bent and long in the stride, the head out in front, the blade swept back and away.
WALK_LOW = dict(WALK_G, T=1.38, S=0.66, s=WALK_V * 1.38 * 0.66, z=1.235, lift=0.05, width=0.14, sway=0.04, proll=5.5, plean=7.0, lean=13.0, neck=-3.0, headp=-21.0,
                aswing=11.0, a0=13.0, aout=17.0, ael=38.0, rswing=4.0, r0=-24.0, rout=24.0, rroll=4.0, rel=12.0, rel_s=2.0, bp=-30.0, bpa=2.0, by=-4.0, curl=0.55)
RUN_LOW = dict(RUN_G, T=0.84, S=0.27, s=RUN_V * 0.84 * 0.27, z=1.15, lift=0.13, width=0.11, bob=0.024, plean=14.0, lean=19.0, lean_b=3.0, neck=-11.0, headp=-30.0,
               aswing=44.0, a0=16.0, aout=15.0, ael=58.0, rswing=6.0, r0=-30.0, rout=26.0, rroll=4.0, rel=14.0, rel_s=4.0, bp=-34.0, bpa=3.0, by=-4.0, curl=0.72, out_wide=46.0, out_el=36.0)
# HIGH: upright and quick, the shoulders rolling, the blade held up beside its head.
WALK_HIGH = dict(WALK_G, T=1.02, S=0.6, s=WALK_V * 1.02 * 0.6, z=1.3, lift=0.075, width=0.115, proll=3.5, plean=1.0, lean=1.5, pyaw=11.0, cyaw=14.0, neck=2.0, headp=-9.0,
                 aswing=10.0, a0=24.0, aout=20.0, ael=68.0, ael_s=5.0, rswing=3.0, r0=44.0, rout=30.0, rroll=0.0, rel=104.0, rel_s=2.0, bp=6.0, bpa=2.0, by=-6.0, curl=0.5)
RUN_HIGH = dict(RUN_G, T=0.66, S=0.33, s=RUN_V * 0.66 * 0.33, z=1.235, lift=0.15, bob=0.034, pyaw=17.0, proll=5.0, plean=5.0, lean=5.0, lean_b=1.6, cyaw=24.0, neck=-1.0, headp=-13.0,
                aswing=22.0, a0=30.0, aout=19.0, ael=84.0, ael_s=8.0, rswing=5.0, r0=48.0, rout=32.0, rroll=0.0, rel=108.0, rel_s=3.0, bp=8.0, bpa=3.0, by=-6.0, curl=0.5)


def walk(t, L):
    sp = Spec()
    gait(sp, t / L, WALK_G)
    return sp


def run(t, L):
    sp = Spec()
    gait(sp, t / L, RUN_G)
    return sp


def gait_fn(g):
    def fn(t, L):
        sp = Spec()
        gait(sp, t / L, g)
        return sp

    return fn


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


FIGHT_L = 6.6


def idle_fight(t, L):
    """The guard, alive (note 139): blown from the blow, the chest heaving and slowing,
    the weight going from foot to foot, the blade sagging and hauled back up a beat
    behind it, the claw working, the head looking about, a foot shifted and put back.
    `on` is 0 at both ends at no speed, so a blow still lands on the guard itself, and
    everything here may run at any period. The wrist flexes and never turns."""
    sp = fight_base(t, 2.2)
    if t <= 0.0 or t >= L:
        return sp
    on = sm(t / 0.7) * sm((L - t) / 0.7)
    blown = 1.0 - 0.62 * sm((t - 1.0) / 2.8)
    s = math.sin
    br = s(TAU * t / 1.25) * blown
    weight = s(TAU * t / 4.4)
    weight2 = s(TAU * t / 2.9 + 0.7)
    # The blade comes after the body that holds it up.
    sag = s(TAU * (t - 0.3) / 4.4 + 0.9)
    look = s(TAU * t / 5.1 + 0.4)
    p = sp.pelvis
    sp.pelvis = V(p.x + on * 0.04 * weight, p.y + on * 0.02 * weight2, p.z - on * (0.012 * br + 0.016 * weight * weight))
    sp.pelvis_q = rz(rad(16.0 + on * 6.0 * weight)) @ rx(rad(7.0 + on * 1.4 * br)) @ ry(rad(on * 2.6 * weight))
    a = sp.spine
    sp.spine = (a[0] + on * (3.0 * br + 1.3 * weight2), a[1] + on * (-6.0 * weight + 3.0 * sag), a[2] + on * -3.6 * weight)
    sp.neck = (sp.neck[0] - on * 1.2 * br, sp.neck[1] + on * 5.0 * look, on * 1.6 * weight)
    sp.head = (sp.head[0] + on * (-1.5 * br + 1.6 * s(TAU * t / 3.7)), sp.head[1] + on * 7.0 * s(TAU * t / 5.1 + 0.9), on * 2.4 * s(TAU * t / 6.3 + 1.7))
    sp.clav_l = (on * 3.0 * br, on * 1.6 * weight2)
    sp.clav_r = (on * (3.4 * br - 1.6 * sag), on * 3.0 * sag)
    r = sp.arm_r
    sp.arm_r = (r[0] + on * (6.0 * sag + 1.0 * br), r[1] + on * 4.0 * s(TAU * t / 3.1 + 2.0), r[2] - on * 8.0 * sag)
    sp.roll_r += on * 2.0 * sag
    sp.hand_r = wrist(GUARD["wr"][0] + on * 5.0 * s(TAU * t / 3.3 + 2.4), GUARD["wr"][1] + on * 3.0 * s(TAU * t / 4.1), 0.0)
    l = sp.arm_l
    sp.arm_l = (l[0] + on * 7.0 * weight2, l[1] + on * 6.0 * sag, l[2] + on * 10.0 * s(TAU * t / 3.9 + 1.1))
    sp.curl = 0.5 + on * (0.16 * s(TAU * t / 2.3) + 0.05 * s(TAU * t / 0.83))
    sp.spread = 1.0 - on * 0.3 * (1.0 + s(TAU * t / 3.1))
    # The feet get tired too: one is shifted and put back, then the other. Short of
    # the stance's own length, so a blow from here does not start with a skate.
    st_r, st_l = (STANCE["r"][0], STANCE["r"][1], STANCE["yr"]), (STANCE["l"][0], STANCE["l"][1], STANCE["yl"])
    x, y, z, yaw, pitch, toe = step_foot(st_r, ((2.5, 2.95, (-0.13, -0.33, -9.0), 0.03), (5.3, 5.75, st_r, 0.03)), t)
    sp.foot_r = (V(x, y, z), pitch, yaw, 0.0, toe)
    x, y, z, yaw, pitch, toe = step_foot(st_l, ((3.65, 4.05, (0.2, 0.28, 25.0), 0.03), (4.75, 5.15, st_l, 0.03)), t)
    sp.foot_l = (V(x, y, z), pitch, yaw, 0.0, toe)
    return sp


# --- Blows ----------------------------------------------------------------------------

class Blow:
    """A blow's channels, each keyed on its own times. The feet are in the
    WORLD: root motion is taken off them, so a planted foot stands still."""

    def __init__(self, keyed, settle=None):
        """`keyed`: where the last key is. `settle`: from here the clip's clock runs
        down to a stand, so the end takes twice the time the keys gave it."""
        self.keyed = keyed
        self.settle = keyed if settle is None else settle
        self.L = self.settle + 2.0 * (keyed - self.settle)
        self.ch = {}
        self.foot_keys = {}

    def clock(self, t):
        """Key time at clip time `t`. The keys drive the blade home and stop it at the
        last one, however fast it is going, and every channel gets there together. So
        the keys' own time slows at a steady rate from `settle` to nothing at the end:
        each joint comes to rest as a heavy thing does, with no last-moment stop."""
        if t <= self.settle or self.keyed <= self.settle:
            return t
        u = min(1.0, (t - self.settle) / (self.L - self.settle))
        return self.settle + (self.keyed - self.settle) * (2.0 * u - u * u)

    def pace(self, t):
        """How fast `clock` is running at clip time `t`: 1, down to 0 at the end."""
        if t <= self.settle or self.keyed <= self.settle:
            return 1.0
        return max(0.0, 1.0 - (t - self.settle) / (self.L - self.settle))

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


def blow_clip(bl, tempo=1.0):
    """`bl` as a clip, played `tempo` times as fast as it is keyed."""

    def fn(t, L):
        t *= tempo
        # The blurs narrow with the clock, or a blow would stop short of the guard
        # by what they take off the last key.
        g = bl.pace(t)
        t = bl.clock(t)
        ch = bl.ch
        sp = fight_base()
        rooty = ch["root"](t)
        sp.root = V(0, -rooty, 0)
        p = blur(ch["pelvis"], t, 0.03 * g)
        sp.pelvis = V(p[0], p[1], p[2])
        # Blurred too: at the end of a 2 m lever the hips and chest are as sharp
        # as anything the arm does.
        q = blur(ch["pq"], t, 0.04 * g)
        sp.pelvis_q = rz(rad(q[1])) @ rx(rad(q[0])) @ ry(rad(q[2]))
        sp.spine = blur(ch["spine"], t, 0.04 * g)
        sp.neck = ch["neck"](t)
        sp.head = ch["head"](t)
        # Hardly at all: a wider tent than this takes the speed off the swing,
        # and the speed is the blow.
        a = blur(ch["arm"], t, 0.025 * g)
        sp.arm_r = (a[0], a[1], blur(ch["elbow"], t, 0.025 * g))
        sp.roll_r = a[2]
        w = blur(ch["wrist"], t, 0.03 * g)
        sp.hand_r = wrist(*w)
        al = blur(ch["arm_l"], t, 0.05 * g)
        sp.arm_l = (al[0], al[1], al[2])
        sp.roll_l = GUARD["rl"]
        sp.curl = ch["curl"](t)
        sp.clav_r = ch["clav_r"](t)
        sp.clav_l = ch["clav_l"](t)
        sp.foot_l = bl.foot("l", t, rooty)
        sp.foot_r = bl.foot("r", t, rooty)
        return sp

    fn.bl = bl
    return fn


def _b():
    """The guard a blow leaves from and comes home to: idle_fight's own first frame, to
    the degree, so the clip that takes over has nothing to move."""
    b = fight_base()
    return dict(p=(b.pelvis.x, b.pelvis.y, b.pelvis.z), pq=(7.0, 16.0, 0.0), spine=b.spine, neck=b.neck, head=b.head,
                arm=(b.arm_r[0], b.arm_r[1], b.roll_r), el=b.arm_r[2], wrist=GUARD["wr"], al=b.arm_l)


# Each blow below runs the same six beats, and each channel takes them late of the
# one under it, so the weight goes through the body the way a real one does:
#
#   the load    it sags into the blow before it lifts: hips down, the blade dips
#   the haul    hips and legs drive the blade up, chest and shoulder after, the arm
#               slowing into the top; the shoulder hikes with the effort
#   the hang    the arm all but stopped at the top while the hips have already
#               gone: the stretch between them is what the swing lets go
#   the swing   hips, chest, shoulder, then the elbow, which stays shut until the
#               arm has its speed; the blade goes last and fastest. The ATTACK
#               window is this and nothing else
#   the carry   nothing stops it: the swing's speed runs off over the next third of
#               a second, the arm going on past the blow and pulling the chest, the
#               shoulder and the trailing foot after it
#   the heave   hung out at the end of the arm; the body comes back first and the
#               blade is dragged home after it

def slash_1(k=1.0):
    """Light: hauled back over its right shoulder, then down across the body. It does
    not stop at the left hip: the arm runs on past it and the chest bends after it.
    The right foot stamps in under the blow; the left is dragged up after."""
    w, a, _r = LIGHT
    A, B = w, w + a
    E = B + LIGHT_KEYED
    n = _b()
    bl = Blow(E, B + LIGHT_SETTLE)
    bl.key("root", [(0.0, 0.0), (A - 0.2, 0.0), (A, 0.22 * k), (A + 0.1, 0.56 * k), (B, 0.64 * k), (B + 0.3, 0.68 * k), (E, 0.68 * k)])
    bl.key("pelvis", [(0.0, n["p"]), (0.15, (0.012, 0.03, 1.205)), (0.42, (0.03, 0.08, 1.235)), (A - 0.16, (0.04, 0.11, 1.27)), (A + 0.02, (0.02, 0.0, 1.25)), (A + 0.12, (-0.03, -0.12, 1.19)),
                      (B + 0.03, (-0.05, -0.16, 1.15)), (B + 0.3, (-0.06, -0.15, 1.14)), (B + 0.6, (-0.04, -0.12, 1.16)), (B + 0.85, (-0.01, -0.04, 1.22)), (E, n["p"])])
    bl.key("pq", [(0.0, n["pq"]), (0.15, (10.0, 12.0, -1.0)), (A - 0.2, (0.0, -26.0, -3.0)), (A - 0.04, (2.0, -14.0, -2.0)), (A + 0.1, (12.0, 16.0, 3.0)), (B, (17.0, 30.0, 5.0)), (B + 0.12, (19.0, 36.0, 6.0)),
                  (B + 0.34, (20.0, 40.0, 6.0)), (B + 0.6, (18.0, 36.0, 5.0)), (B + 0.85, (11.0, 22.0, 2.0)), (E, n["pq"])])
    bl.key("spine", [(0.0, n["spine"]), (0.15, (13.0, -6.0, 0.0)), (0.46, (1.0, -18.0, 5.0)), (A - 0.08, (-10.0, -31.0, 9.0)), (A + 0.02, (-8.0, -27.0, 8.0)), (A + 0.13, (14.0, 8.0, -9.0)),
                     (B, (24.0, 18.0, -13.0)), (B + 0.1, (28.0, 22.0, -15.0)), (B + 0.26, (30.0, 24.0, -16.0)), (B + 0.54, (29.0, 22.0, -14.0)), (B + 0.82, (20.0, 10.0, -6.0)), (E, n["spine"])])
    bl.key("neck", [(0.0, n["neck"]), (A, (-4.0, 14.0, -4.0)), (A + 0.16, (-3.0, -4.0, 4.0)), (B + 0.2, (-10.0, -18.0, 6.0)), (B + 0.8, (-5.0, -8.0, 2.0)), (E, n["neck"])])
    bl.key("head", [(0.0, n["head"]), (A, (-14.0, 13.0, -5.0)), (A + 0.18, (-16.0, -6.0, 4.0)), (B + 0.22, (-22.0, -20.0, 6.0)), (B + 0.85, (-19.0, -8.0, 2.0)), (E, n["head"])])
    # Up with the effort of the lift, and dragged down and forward by what it
    # threw.
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (0.15, (-3.0, 2.0)), (A - 0.1, (13.0, -7.0)), (A + 0.1, (2.0, 10.0)), (B + 0.05, (-6.0, 18.0)), (B + 0.45, (-9.0, 21.0)), (B + 0.8, (-4.0, 10.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (A, (3.0, 6.0)), (B, (2.0, -8.0)), (B + 0.5, (2.0, -10.0)), (E, (0.0, 0.0))])
    # swing, out, roll.
    bl.key("arm", [(0.0, n["arm"]), (0.15, (20.0, 26.0, 13.0)), (0.42, (56.0, 33.0, 5.0)), (A - 0.14, (101.0, 36.0, -6.0)), (A - 0.04, (111.0, 36.0, -9.0)), (A + 0.02, (113.0, 36.0, -9.0)),
                   (A + 0.1, (105.0, 33.0, -4.0)), (A + 0.15, (88.0, 22.0, 3.0)), (A + 0.19, (74.0, 11.0, 10.0)), (B, (75.0, 3.0, 18.0)), (B + 0.06, (91.0, -2.0, 28.0)), (B + 0.12, (101.0, -9.0, 38.0)),
                   (B + 0.2, (108.0, -15.0, 46.0)), (B + 0.32, (114.0, -19.0, 50.0)), (B + 0.5, (115.0, -22.0, 52.0)), (B + 0.66, (106.0, -20.0, 49.0)), (B + 0.86, (64.0, -4.0, 34.0)), (E, n["arm"])])
    bl.key("elbow", [(0.0, n["el"]), (0.2, 64.0), (0.5, 78.0), (A - 0.06, 93.0), (A + 0.1, 92.0), (A + 0.15, 74.0), (A + 0.2, 46.0), (B, 28.0), (B + 0.08, 14.0), (B + 0.2, 10.0), (B + 0.4, 13.0), (B + 0.66, 20.0), (B + 0.86, 46.0), (E, n["el"])])
    bl.key("wrist", [(0.0, n["wrist"]), (0.2, (-2.0, -4.0, 0.0)), (A - 0.1, (-14.0, 0.0, 0.0)), (A + 0.1, (-16.0, 0.0, 0.0)), (A + 0.2, (2.0, 0.0, 0.0)), (B + 0.12, (12.0, 0.0, 0.0)), (B + 0.5, (10.0, 0.0, 0.0)), (B + 0.8, (-4.0, 0.0, 0.0)), (E, n["wrist"])])
    bl.key("arm_l", [(0.0, n["al"]), (A - 0.08, (46.0, 24.0, 82.0)), (A + 0.14, (10.0, 36.0, 50.0)), (B + 0.1, (-24.0, 48.0, 30.0)), (B + 0.62, (-22.0, 50.0, 30.0)), (E, n["al"])])
    bl.key("curl", [(0.0, 0.5), (A, 0.25), (A + 0.16, 0.7), (B + 0.5, 0.6), (E, 0.5)])
    # The right foot goes in under the blow; the left is dragged up by what the
    # blow carried on with.
    bl.feet("r", [(A - 0.14, A + 0.11, (-0.15, -0.26 - 0.68 * k), -8.0, 0.03 + 0.045 * k)])
    bl.feet("l", [(A + 0.15, B + 0.42, (0.17, 0.22 - 0.68 * k), 22.0, 0.025 + 0.025 * k)])
    return blow_clip(bl, TEMPO), bl.L / TEMPO


def slash_2(k=1.0):
    """Light: the backhand. The arm dragged across to the left hip, the elbow forward
    and the upper arm rolled in, then the elbow opens and the blade comes up across the
    body and out high on its right. It rises on past the blow until its own weight
    stops it, hangs there, and is let back down."""
    w, a, _r = LIGHT
    A, B = w, w + a
    E = B + LIGHT_KEYED
    n = _b()
    bl = Blow(E, B + LIGHT_SETTLE)
    bl.key("root", [(0.0, 0.0), (A - 0.18, 0.0), (A, 0.2 * k), (A + 0.11, 0.5 * k), (B, 0.57 * k), (B + 0.3, 0.6 * k), (E, 0.6 * k)])
    bl.key("pelvis", [(0.0, n["p"]), (0.2, (0.02, 0.01, 1.205)), (A - 0.08, (0.04, 0.03, 1.19)), (A + 0.02, (0.03, 0.0, 1.195)), (A + 0.13, (0.0, -0.1, 1.21)), (B + 0.03, (-0.05, -0.13, 1.25)),
                      (B + 0.3, (-0.05, -0.13, 1.27)), (B + 0.62, (-0.04, -0.11, 1.24)), (B + 0.82, (-0.01, -0.04, 1.215)), (E, n["p"])])
    bl.key("pq", [(0.0, n["pq"]), (0.2, (10.0, 26.0, 1.0)), (A - 0.1, (12.0, 38.0, 3.0)), (A + 0.02, (11.0, 28.0, 2.0)), (A + 0.12, (8.0, 2.0, -2.0)), (B + 0.05, (3.0, -30.0, -5.0)),
                  (B + 0.3, (2.0, -38.0, -6.0)), (B + 0.62, (3.0, -30.0, -4.0)), (B + 0.85, (5.0, -2.0, -2.0)), (E, n["pq"])])
    bl.key("spine", [(0.0, n["spine"]), (0.2, (13.0, 8.0, -2.0)), (A - 0.04, (18.0, 34.0, -9.0)), (A + 0.15, (8.0, -6.0, 5.0)), (B + 0.05, (-6.0, -34.0, 12.0)), (B + 0.26, (-10.0, -42.0, 14.0)),
                     (B + 0.6, (-5.0, -36.0, 12.0)), (B + 0.85, (6.0, -14.0, 3.0)), (E, n["spine"])])
    bl.key("neck", [(0.0, n["neck"]), (A, (-2.0, -18.0, 3.0)), (A + 0.17, (0.0, 2.0, -3.0)), (B + 0.2, (0.0, 18.0, -5.0)), (B + 0.8, (0.0, 6.0, -1.0)), (E, n["neck"])])
    bl.key("head", [(0.0, n["head"]), (A, (-20.0, -17.0, 4.0)), (A + 0.18, (-16.0, 3.0, -2.0)), (B + 0.22, (-13.0, 17.0, -4.0)), (B + 0.85, (-15.0, 5.0, -1.0)), (E, n["head"])])
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (0.2, (-3.0, 6.0)), (A - 0.06, (-5.0, 15.0)), (A + 0.1, (-1.0, 9.0)), (B + 0.05, (10.0, 2.0)), (B + 0.3, (14.0, 0.0)), (B + 0.8, (5.0, 1.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (A, (2.0, -6.0)), (B, (2.0, 7.0)), (B + 0.5, (2.0, 8.0)), (E, (0.0, 0.0))])
    bl.key("arm", [(0.0, n["arm"]), (0.13, (22.0, 22.0, 16.0)), (0.4, (24.0, -6.0, 46.0)), (A - 0.14, (25.0, -30.0, 72.0)), (A - 0.04, (26.0, -35.0, 77.0)), (A + 0.03, (26.0, -36.0, 78.0)),
                   (A + 0.08, (31.0, -28.0, 81.0)), (A + 0.13, (42.0, -7.0, 84.0)), (A + 0.18, (55.0, 18.0, 85.0)), (B, (72.0, 42.0, 83.0)), (B + 0.08, (84.0, 56.0, 79.0)),
                   (B + 0.2, (92.0, 63.0, 73.0)), (B + 0.34, (94.0, 65.0, 68.0)), (B + 0.46, (93.0, 64.0, 64.0)), (B + 0.62, (84.0, 59.0, 52.0)), (B + 0.8, (62.0, 48.0, 36.0)), (E, n["arm"])])
    bl.key("elbow", [(0.0, n["el"]), (0.3, 64.0), (A - 0.1, 73.0), (A + 0.08, 75.0), (A + 0.14, 60.0), (A + 0.2, 32.0), (B + 0.04, 15.0), (B + 0.14, 9.0), (B + 0.36, 13.0), (B + 0.6, 30.0), (B + 0.84, 56.0), (E, n["el"])])
    bl.key("wrist", [(0.0, n["wrist"]), (0.2, (-4.0, 0.0, 0.0)), (A - 0.1, (-14.0, 0.0, 0.0)), (A + 0.1, (-13.0, 0.0, 0.0)), (A + 0.22, (-6.0, 0.0, 0.0)), (B + 0.14, (-14.0, 0.0, 0.0)), (B + 0.5, (-12.0, 0.0, 0.0)), (E, n["wrist"])])
    bl.key("arm_l", [(0.0, n["al"]), (A - 0.3, (-4.0, 44.0, 44.0)), (A + 0.06, (-10.0, 50.0, 40.0)), (A + 0.2, (24.0, 32.0, 66.0)), (B + 0.1, (48.0, 22.0, 84.0)), (B + 0.6, (40.0, 22.0, 78.0)), (E, n["al"])])
    bl.key("curl", [(0.0, 0.5), (A, 0.65), (A + 0.16, 0.3), (B + 0.5, 0.42), (E, 0.5)])
    # The left goes past where the stance wants it, so it shuffles back as the right
    # comes up: both done by LINK_OUT, and the foot does not skate home in the idle.
    bl.feet("l", [(A - 0.14, A + 0.11, (0.09 + 0.08 * (1.0 - k), 0.22 - 0.8 * k), 28.0, 0.03 + 0.045 * k), (B + 0.34, B + 0.5, (0.17, 0.22 - 0.6 * k), 22.0, 0.02)])
    bl.feet("r", [(B + 0.06, B + 0.36, (-0.15, -0.26 - 0.6 * k), -7.0, 0.025 + 0.025 * k)])
    return blow_clip(bl, TEMPO), bl.L / TEMPO


def slash_3(k=1.0):
    """Light: the overhead. Heaved straight up until the blade lies down its back, then
    down the middle, the elbow opening late. It misses the floor by a hand and runs on
    low past the forward foot, the body folding after it, and has to be levered back."""
    w, a, _r = LIGHT
    A, B = w, w + a
    E = B + LIGHT_KEYED
    n = _b()
    bl = Blow(E, B + LIGHT_SETTLE)
    bl.key("root", [(0.0, 0.0), (A - 0.18, 0.0), (A, 0.18 * k), (A + 0.1, 0.44 * k), (B, 0.5 * k), (B + 0.3, 0.54 * k), (E, 0.54 * k)])
    bl.key("pelvis", [(0.0, n["p"]), (0.15, (0.0, 0.03, 1.2)), (0.42, (0.0, 0.08, 1.24)), (A - 0.12, (0.0, 0.11, 1.28)), (A + 0.02, (0.0, 0.05, 1.26)), (A + 0.12, (-0.01, -0.1, 1.21)),
                      (B + 0.03, (-0.02, -0.16, 1.12)), (B + 0.26, (-0.03, -0.17, 1.1)), (B + 0.58, (-0.03, -0.14, 1.12)), (B + 0.84, (-0.01, -0.05, 1.19)), (E, n["p"])])
    bl.key("pq", [(0.0, n["pq"]), (0.15, (10.0, 12.0, 0.0)), (A - 0.14, (-4.0, 4.0, 0.0)), (A - 0.02, (-2.0, 5.0, 0.0)), (A + 0.12, (14.0, 12.0, 0.0)), (B + 0.04, (23.0, 20.0, 0.0)), (B + 0.16, (26.0, 30.0, 1.0)), (B + 0.34, (27.0, 38.0, 2.0)),
                  (B + 0.58, (24.0, 34.0, 2.0)), (B + 0.85, (12.0, 20.0, 1.0)), (E, n["pq"])])
    bl.key("spine", [(0.0, n["spine"]), (0.15, (14.0, -6.0, 0.0)), (A - 0.06, (-22.0, -10.0, 4.0)), (A + 0.03, (-19.0, -9.0, 4.0)), (A + 0.14, (20.0, -2.0, -3.0)), (B + 0.04, (38.0, 4.0, -5.0)),
                     (B + 0.16, (42.0, 14.0, -7.0)), (B + 0.34, (43.0, 22.0, -8.0)), (B + 0.58, (40.0, 18.0, -6.0)), (B + 0.85, (20.0, 2.0, -2.0)), (E, n["spine"])])
    bl.key("neck", [(0.0, n["neck"]), (A, (2.0, 0.0, 0.0)), (A + 0.17, (-10.0, 0.0, 0.0)), (B + 0.2, (-22.0, 0.0, 0.0)), (B + 0.85, (-8.0, 0.0, 0.0)), (E, n["neck"])])
    bl.key("head", [(0.0, n["head"]), (A, (-8.0, 2.0, 0.0)), (A + 0.18, (-22.0, 0.0, 0.0)), (B + 0.24, (-32.0, 0.0, 0.0)), (B + 0.85, (-22.0, 0.0, 0.0)), (E, n["head"])])
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (0.15, (-3.0, 2.0)), (A - 0.08, (15.0, -3.0)), (A + 0.1, (4.0, 6.0)), (B + 0.05, (-5.0, 14.0)), (B + 0.45, (-8.0, 17.0)), (B + 0.82, (-3.0, 8.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (A, (6.0, 2.0)), (B, (-2.0, 6.0)), (B + 0.5, (-3.0, 7.0)), (E, (0.0, 0.0))])
    bl.key("arm", [(0.0, n["arm"]), (0.15, (20.0, 25.0, 13.0)), (0.42, (74.0, 25.0, 8.0)), (A - 0.14, (127.0, 16.0, 3.0)), (A - 0.04, (134.0, 14.0, 1.0)), (A + 0.03, (135.0, 14.0, 0.0)),
                   (A + 0.08, (127.0, 12.0, 0.0)), (A + 0.13, (104.0, 9.0, 1.0)), (A + 0.18, (84.0, 6.0, 3.0)), (B, (78.0, 3.0, 5.0)), (B + 0.08, (78.0, -8.0, 7.0)), (B + 0.2, (80.0, -18.0, 9.0)),
                   (B + 0.36, (82.0, -24.0, 10.0)), (B + 0.58, (78.0, -22.0, 10.0)), (B + 0.85, (46.0, 4.0, 11.0)), (E, n["arm"])])
    bl.key("elbow", [(0.0, n["el"]), (0.2, 64.0), (0.5, 80.0), (A - 0.08, 93.0), (A + 0.09, 94.0), (A + 0.14, 74.0), (A + 0.19, 38.0), (B, 22.0), (B + 0.12, 18.0), (B + 0.34, 22.0), (B + 0.6, 28.0), (B + 0.85, 50.0), (E, n["el"])])
    bl.key("wrist", [(0.0, n["wrist"]), (0.2, (-2.0, 0.0, 0.0)), (A - 0.1, (-18.0, 0.0, 0.0)), (A + 0.1, (-18.0, 0.0, 0.0)), (A + 0.2, (2.0, 0.0, 0.0)), (B + 0.12, (8.0, 0.0, 0.0)), (B + 0.55, (4.0, 0.0, 0.0)), (E, n["wrist"])])
    bl.key("arm_l", [(0.0, n["al"]), (A, (52.0, 26.0, 88.0)), (A + 0.15, (20.0, 30.0, 56.0)), (B + 0.1, (-14.0, 36.0, 34.0)), (B + 0.6, (-6.0, 34.0, 42.0)), (E, n["al"])])
    bl.key("curl", [(0.0, 0.5), (A, 0.2), (A + 0.16, 0.75), (B + 0.5, 0.62), (E, 0.5)])
    bl.feet("r", [(A - 0.14, A + 0.11, (-0.15, -0.26 - 0.54 * k), -6.0, 0.03 + 0.04 * k)])
    bl.feet("l", [(A + 0.18, B + 0.46, (0.17, 0.22 - 0.54 * k), 22.0, 0.025 + 0.025 * k)])
    return blow_clip(bl, TEMPO), bl.L / TEMPO


def heavy(k=1.0):
    """The heavy slice: a long heave back in two pushes, the whole body coiled onto its
    right leg, the upper arm rolled in so the elbow's bend lies flat and the blade
    trails behind at chest height; then flat across the whole front, the left foot
    stamped, the hips leading, the elbow opening last. Then it cannot stop it: the
    blade drags it round past the blow, the right foot staggers to catch it, and it
    stands bent over the arm before it can drag the thing home."""
    w, a, _r = HEAVY
    A, B = w, w + a
    E = B + HEAVY_KEYED
    n = _b()
    bl = Blow(E, B + HEAVY_SETTLE)
    bl.key("root", [(0.0, 0.0), (0.3, -0.03), (A - 0.3, -0.1), (A - 0.04, -0.09), (A + 0.14, 0.2 * k), (B, 0.42 * k), (B + 0.3, 0.5 * k), (B + 0.6, 0.52 * k), (E, 0.52 * k)])
    bl.key("pelvis", [(0.0, n["p"]), (0.2, (-0.01, 0.03, 1.2)), (0.52, (-0.04, 0.09, 1.22)), (0.76, (-0.04, 0.1, 1.2)), (A - 0.14, (-0.06, 0.13, 1.16)), (A + 0.02, (-0.05, 0.09, 1.155)), (A + 0.14, (0.0, 0.0, 1.16)),
                      (B, (0.06, -0.12, 1.15)), (B + 0.3, (0.07, -0.14, 1.14)), (B + 0.75, (0.05, -0.12, 1.16)), (B + 1.05, (0.02, -0.05, 1.2)), (E, n["p"])])
    bl.key("pq", [(0.0, n["pq"]), (0.2, (9.0, 8.0, 1.0)), (0.56, (8.0, -22.0, 2.0)), (0.8, (8.0, -28.0, 3.0)), (A - 0.12, (9.0, -46.0, 4.0)), (A + 0.05, (9.0, -36.0, 4.0)), (A + 0.2, (8.0, 8.0, 0.0)), (B - 0.02, (10.0, 44.0, -5.0)),
                  (B + 0.28, (11.0, 56.0, -6.0)), (B + 0.75, (11.0, 48.0, -4.0)), (B + 1.05, (9.0, 26.0, -1.0)), (E, n["pq"])])
    bl.key("spine", [(0.0, n["spine"]), (0.2, (13.0, -8.0, 1.0)), (0.56, (10.0, -34.0, 8.0)), (0.82, (9.0, -40.0, 9.0)), (A - 0.04, (5.0, -62.0, 11.0)), (A + 0.09, (6.0, -54.0, 10.0)), (A + 0.22, (12.0, -4.0, -3.0)), (B, (17.0, 36.0, -13.0)),
                     (B + 0.22, (20.0, 44.0, -15.0)), (B + 0.75, (19.0, 36.0, -11.0)), (B + 1.05, (13.0, 12.0, -4.0)), (E, n["spine"])])
    bl.key("neck", [(0.0, n["neck"]), (A, (0.0, 34.0, -5.0)), (A + 0.2, (-2.0, 6.0, 2.0)), (B + 0.15, (-6.0, -28.0, 7.0)), (B + 0.8, (-3.0, -14.0, 3.0)), (E, n["neck"])])
    bl.key("head", [(0.0, n["head"]), (A, (-16.0, 30.0, -6.0)), (A + 0.22, (-17.0, 4.0, 2.0)), (B + 0.15, (-20.0, -28.0, 8.0)), (B + 0.8, (-18.0, -12.0, 2.0)), (E, n["head"])])
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (0.2, (-3.0, 3.0)), (A - 0.06, (6.0, -15.0)), (A + 0.14, (1.0, 5.0)), (B, (0.0, 20.0)), (B + 0.5, (-5.0, 24.0)), (B + 1.0, (-2.0, 8.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (A, (2.0, 12.0)), (B, (1.0, -12.0)), (B + 0.6, (1.0, -14.0)), (E, (0.0, 0.0))])
    bl.key("arm", [(0.0, n["arm"]), (0.2, (25.0, 21.0, 18.0)), (0.56, (50.0, 48.0, 54.0)), (0.82, (56.0, 58.0, 68.0)), (A - 0.14, (64.0, 74.0, 83.0)), (A - 0.03, (66.0, 78.0, 86.0)), (A + 0.04, (67.0, 79.0, 87.0)),
                   (A + 0.12, (69.0, 75.0, 87.0)), (A + 0.17, (75.0, 63.0, 86.0)), (A + 0.21, (84.0, 48.0, 84.0)), (A + 0.25, (95.0, 35.0, 82.0)), (B, (109.0, 26.0, 79.0)), (B + 0.06, (110.0, 12.0, 76.0)),
                   (B + 0.14, (111.0, 1.0, 73.0)), (B + 0.26, (112.0, -7.0, 71.0)), (B + 0.46, (110.0, -11.0, 68.0)), (B + 0.72, (95.0, -6.0, 60.0)), (B + 1.05, (46.0, 12.0, 32.0)), (E, n["arm"])])
    bl.key("elbow", [(0.0, n["el"]), (0.56, 84.0), (0.82, 90.0), (A - 0.08, 106.0), (A + 0.12, 108.0), (A + 0.18, 84.0), (A + 0.24, 48.0), (B, 22.0), (B + 0.08, 10.0), (B + 0.2, 8.0), (B + 0.4, 11.0), (B + 0.75, 30.0), (B + 1.05, 58.0), (E, n["el"])])
    bl.key("wrist", [(0.0, n["wrist"]), (0.3, (-8.0, 6.0, 0.0)), (A - 0.1, (-18.0, 12.0, 0.0)), (A + 0.12, (-16.0, 14.0, 0.0)), (A + 0.26, (2.0, 14.0, 0.0)), (B + 0.2, (10.0, 12.0, 0.0)), (B + 0.8, (6.0, 8.0, 0.0)), (E, n["wrist"])])
    bl.key("arm_l", [(0.0, n["al"]), (A, (62.0, 18.0, 70.0)), (A + 0.18, (26.0, 30.0, 58.0)), (B + 0.1, (-20.0, 42.0, 34.0)), (B + 0.8, (-8.0, 36.0, 42.0)), (E, n["al"])])
    bl.key("curl", [(0.0, 0.5), (A, 0.2), (A + 0.2, 0.7), (B + 0.6, 0.6), (E, 0.5)])
    # Back onto the right leg, then the left stamps forward; the right is dragged
    # round after the blade and the left has to shuffle back under it.
    bl.feet("l", [(0.3, 0.68, (0.2, 0.1), 24.0, 0.04), (A - 0.1, A + 0.14, (0.22, 0.1 - 0.46 * k), 32.0, 0.03 + 0.04 * k), (B + 0.76, B + 1.16, (0.17, 0.22 - 0.52 * k), 22.0, 0.025 + 0.025 * k)])
    bl.feet("r", [(B + 0.08, B + 0.5, (-0.15, -0.26 - 0.52 * k), -7.0, 0.03 + 0.03 * k)])
    return blow_clip(bl, TEMPO), bl.L / TEMPO


# --- Chains ---------------------------------------------------------------------------
#
# A blow can go on into another (note 138): the swing's carry is the next wind-up's
# start. A LINK is a short clip from one blow, part way through its recovery, to
# another, part way through its wind-up; the game swaps clips at those moments with
# nothing to blend. Which is why a link depends on neither blow's step: by LINK_OUT
# every light has its feet back in the stance, and every blow is still in it at
# LINK_IN.
#
# Each channel keeps to its own blow as long as it can, so the weight still goes through
# the body in order: hips first, then chest and shoulder, the arm next, and the elbow
# last. Between those times it runs a quintic from the one track to the other, its
# position and speed matching at both ends; the speed the arm carries in is kept, so it
# swings on a little before it turns.

LINK = 0.75                 # as keyed, like these three; sword_skeleton.gd LINK_TIME
LINK_OUT = 0.62             # after the swing's end; ... CHAIN_OUT
# How long before its swing each blow is joined; ... CHAIN_IN.
LINK_IN = {"slash_1": 0.22, "slash_2": 0.22, "slash_3": 0.22, "heavy": 0.28}
LINKS = (("slash_1", "slash_2", "link_1_2"), ("slash_2", "slash_1", "link_2_1"), ("slash_2", "slash_3", "link_2_3"), ("slash_2", "heavy", "link_2_h"), ("slash_3", "slash_2", "link_3_2"))
# When each channel leaves the old track and is on the new one, s into the link.
HANDOVER = dict(root=(0.0, LINK), pelvis=(0.04, 0.58), pq=(0.05, 0.6), spine=(0.06, 0.62), neck=(0.12, 0.66), head=(0.14, 0.68), clav_r=(0.08, 0.64), clav_l=(0.08, 0.62),
                arm=(0.1, 0.72), elbow=(0.16, 0.72), wrist=(0.16, 0.7), arm_l=(0.06, 0.64), curl=(0.12, 0.62))


def splice(f0, t0, f1, t1, s0, s1):
    """`f0` from `t0` until `s0`, `f1` to `t1` from `s1`, and a quintic between them
    that starts and ends at their speeds, with no acceleration of its own."""

    def vals(v):
        return list(v) if isinstance(v, tuple) else [v]

    e = 1.0 / 120.0
    p0 = vals(f0(t0 + s0))
    v0 = [(a - b) / (2.0 * e) for a, b in zip(vals(f0(t0 + s0 + e)), vals(f0(t0 + s0 - e)))]
    p1 = vals(f1(t1 - LINK + s1))
    v1 = [(a - b) / (2.0 * e) for a, b in zip(vals(f1(t1 - LINK + s1 + e)), vals(f1(t1 - LINK + s1 - e)))]
    h = s1 - s0
    tup = isinstance(f0(t0), tuple)

    def at(t):
        if t <= s0:
            return f0(t0 + t)
        if t >= s1:
            return f1(t1 - LINK + t)
        u = (t - s0) / h
        u3, u4, u5 = u ** 3, u ** 4, u ** 5
        out = []
        for d in range(len(p0)):
            a = p0[d] + v0[d] * h * u
            # What is left to go, by the standard basis with zero end acceleration.
            k = p1[d] - p0[d] - v0[d] * h
            m = (v1[d] - v0[d]) * h
            out.append(a + k * (10.0 * u3 - 15.0 * u4 + 6.0 * u5) + m * (-4.0 * u3 + 7.0 * u4 - 3.0 * u5))
        return tuple(out) if tup else out[0]

    return at


BLOW_FNS = {}


def link_clip(a, b):
    """From blow `a` at LINK_OUT to blow `b` at LINK_IN before its swing."""
    A = BLOW_FNS[a](1.0)[0].bl
    Bb = BLOW_FNS[b](1.0)[0].bl
    w, s, _r = HEAVY if a == "heavy" else LIGHT
    t0 = w + s + LINK_OUT
    w, s, _r = HEAVY if b == "heavy" else LIGHT
    t1 = w - LINK_IN[b]
    bl = Blow(LINK)
    for name, (s0, s1) in HANDOVER.items():
        if name == "root":
            continue
        bl.ch[name] = splice(A.ch[name], t0, Bb.ch[name], t1, s0, s1)
    # The world the feet stand in starts at this link's root; the heavy has stepped back
    # by the time it is joined, and its left foot gone back with it.
    bl.ch["root"] = track([(0.0, 0.0), (LINK, Bb.ch["root"](t1))])
    if b == "heavy":
        bl.feet("l", [(0.06, 0.44, (0.2, 0.1), 24.0, 0.04)])
    fn = blow_clip(bl, TEMPO)
    fn.out = (a, t0, b, t1)
    return fn, LINK / TEMPO


# --- Standing down, and turning on guard -------------------------------------------------

def lerp(a, b, e):
    return tuple(x + (y - x) * e for x, y in zip(a, b))


def mj(u):
    """Minimum jerk."""
    u = max(0.0, min(1.0, u))
    return u * u * u * (10.0 + u * (-15.0 + 6.0 * u))


def relax():
    """Nobody left to fight: out of the guard and into the idle, on its own feet. The
    two stances are a stride apart, and without this the feet skate it."""
    L = 1.4
    bl = Blow(L)
    bl.feet("r", [(0.14, 0.56, (-0.2, -0.09), -12.0, 0.035)])
    bl.feet("l", [(0.5, 0.94, (0.2, 0.03), 13.0, 0.035)])

    def fn(t, _L):
        a = fight_base()
        b = idle(0.0, 6.0)
        sp = Spec()
        # The hips go first and the blade is let down last.
        hips = mj(t / 1.0)
        body = mj((t - 0.1) / 1.05)
        arm = mj((t - 0.16) / 1.2)
        sp.pelvis = a.pelvis.lerp(b.pelvis, hips)
        sp.pelvis_q = a.pelvis_q.slerp(b.pelvis_q, hips)
        sp.spine = lerp(a.spine, b.spine, body)
        sp.neck = lerp(a.neck, b.neck, body)
        sp.head = lerp(a.head, b.head, body)
        sp.clav_l = lerp(a.clav_l, b.clav_l, body)
        sp.clav_r = lerp(a.clav_r, b.clav_r, body)
        sp.arm_l = lerp(a.arm_l, b.arm_l, arm)
        sp.arm_r = lerp(a.arm_r, b.arm_r, arm)
        sp.roll_l = a.roll_l + (b.roll_l - a.roll_l) * arm
        sp.roll_r = a.roll_r + (b.roll_r - a.roll_r) * arm
        sp.hand_l = a.hand_l.slerp(b.hand_l, arm)
        sp.hand_r = a.hand_r.slerp(b.hand_r, arm)
        sp.curl = a.curl + (b.curl - a.curl) * arm
        sp.spread = a.spread + (b.spread - a.spread) * arm
        sp.foot_l = bl.foot("l", t, 0.0)
        sp.foot_r = bl.foot("r", t, 0.0)
        return sp

    return fn, L


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


def turn_guard(sgn):
    """`turn`, on guard: the same steps taken from the fighting stance, the blade kept
    up. The other way the arm drops to the idle's and comes back up as the turn ends."""
    T = 0.9
    sweep = math.degrees(TURN_RATE) * T * 0.5

    def fn(t, L):
        sp = fight_base(t, L)
        phi = t / T
        for side, base, off, st in (("l", STANCE["yl"], 0.0, STANCE["l"]), ("r", STANCE["yr"], 0.5, STANCE["r"])):
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
            pos = rz(rad(a)) @ V(st[0], st[1], 0.0)
            ft = (V(pos.x, pos.y, ANKLE + lift), -10.0 * lift / 0.05, base + a, 0.0, 0.0)
            if side == "l":
                sp.foot_l = ft
            else:
                sp.foot_r = ft
        q = sgn * 5.0
        sp.pelvis_q = rz(rad(16.0 + q)) @ rx(rad(7.0))
        s = sp.spine
        sp.spine = (s[0], s[1] + sgn * 5.0, s[2])
        n, h = sp.neck, sp.head
        sp.neck = (n[0], n[1] + sgn * 6.0, n[2])
        sp.head = (h[0], h[1] + sgn * 8.0, h[2])
        return sp

    return fn, T


def sole(pitch):
    """The ankle's height with a foot pitched this far and its heel or ball on the floor."""
    a = rad(pitch)
    return ANKLE * math.cos(a) + (BALL if a > 0.0 else HEEL) * math.sin(a)


def step_foot(start, steps, t):
    """Where a foot is on the floor at `t`: (x, y, z, yaw, pitch, toe). `start` (x, y,
    yaw) and each of `steps`, (t0, t1, (x, y, yaw), lift), are in the WORLD the root
    stood in at the start, and a step runs round the middle of the body, so a turn of
    180 degrees does not bring a foot through the other leg."""
    x, y, yaw = start
    z, pitch, toe = ANKLE, 0.0, 0.0
    for t0, t1, to, lift in steps:
        if t >= t1:
            x, y, yaw = to
        elif t > t0:
            u = (t - t0) / (t1 - t0)
            e = sm(u)
            a0, a1 = math.atan2(y, x), math.atan2(to[1], to[0])
            sweep = (a1 - a0 + math.pi) % TAU - math.pi
            r0, r1 = math.hypot(x, y), math.hypot(to[0], to[1])
            r, a = r0 + (r1 - r0) * e, a0 + sweep * e
            x, y = r * math.cos(a), r * math.sin(a)
            yaw = yaw + (to[2] - yaw) * e
            pitch = 14.0 * (1.0 - sm(u / 0.4)) * sm(u / 0.14) - 12.0 * sm((u - 0.72) / 0.28)
            z = lift * math.sin(math.pi * u) ** 1.1 + sole(pitch)
            toe = -5.0 * math.sin(math.pi * u)
        if t1 <= t < t1 + 0.1:
            pitch = -12.0 * (1.0 - sm((t - t1) / 0.1))
            z = sole(pitch)
    return x, y, z, yaw, pitch, toe


def pivot(sgn, deg, guard):
    """A real turn on the spot (note 139): the head goes first, then the chest, then the
    hips, the blade dragged round after them, and the feet are picked up and set down
    on the floor. `root` x is the whole turn, in radians: the game takes that track
    out with the step (sword_skeleton.gd `_lift_roots`) and turns the model by it. Each
    foot's place below is on the floor, turned back by the root at that moment, so a
    planted foot does not move. It comes back to the stance it left."""
    T = {(90, False): 0.86, (180, False): 1.2, (90, True): 0.72, (180, True): 0.98}[(deg, guard)]
    whole = sgn * deg

    def base():
        return fight_base() if guard else idle(0.0, 6.0)

    b = base()
    home = {"l": b.foot_l, "r": b.foot_r}
    inside, outside = ("l", "r") if sgn > 0 else ("r", "l")

    def at(side, turned):
        """The stance's place for this foot, with the body turned this far."""
        q = rz(rad(turned)) @ home[side][0]
        return (q.x, q.y, home[side][2] + turned)

    if deg == 90:
        plan = {inside: [(0.02 * T, 0.52 * T, at(inside, whole), 0.05)], outside: [(0.42 * T, T - 0.11, at(outside, whole), 0.05)]}
    else:
        plan = {inside: [(0.0, 0.4 * T, at(inside, whole * 0.55), 0.05), (0.66 * T, T - 0.11, at(inside, whole), 0.05)], outside: [(0.3 * T, 0.76 * T, at(outside, whole), 0.055)]}

    def fn(t, _L):
        sp = base()
        u = t / T
        turned = whole * mj((u - 0.06) / 0.9)
        sp.root = V(rad(turned), 0, 0)
        size = math.sqrt(deg / 90.0)

        def bell(w):
            return math.sin(math.pi * max(0.0, min(1.0, w))) ** 2

        lead, mid, late = bell(u * 1.2), bell(u), bell((u - 0.15) / 0.85)
        p = sp.pelvis
        sp.pelvis = V(p.x + sgn * 0.02 * math.sin(TAU * u), p.y, p.z - 0.022 * size * math.sin(TAU * u) ** 2)
        sp.pelvis_q = rz(rad(sgn * 5.0 * size * mid)) @ sp.pelvis_q
        a = sp.spine
        sp.spine = (a[0] + 2.0 * mid, a[1] + sgn * 12.0 * size * mid, a[2] + sgn * 2.0 * mid)
        sp.neck = (sp.neck[0], sp.neck[1] + sgn * 10.0 * size * lead, sp.neck[2])
        sp.head = (sp.head[0], sp.head[1] + sgn * 18.0 * size * lead, sp.head[2])
        # Hung out at the end of its arm, the blade is the last to come.
        r = sp.arm_r
        sp.arm_r = (r[0] + 4.0 * late, r[1] + sgn * 9.0 * size * late, r[2] + 8.0 * late)
        l = sp.arm_l
        sp.arm_l = (l[0], l[1] + 7.0 * mid, l[2] + 6.0 * mid)
        sp.curl += 0.12 * mid
        q = rz(rad(-turned))
        for side in "lr":
            f = home[side]
            s0 = (f[0].x, f[0].y, f[2])
            x, y, z, yaw, pitch, toe = step_foot(s0, plan[side], t)
            ank = q @ V(x, y, 0.0)
            ft = (V(ank.x, ank.y, z), pitch, yaw - turned, 0.0, toe)
            if side == "l":
                sp.foot_l = ft
            else:
                sp.foot_r = ft
        return sp

    return fn, T


# --- Out of a blow, into the walk or the run ---------------------------------------------
#
# The player has gone: it goes after them, in stride, with no blend (note 139). An OUT
# clip takes over from a blow once the carry is spent, and ends on the first frame of the
# walk or the run at that clip's own speed, so the game swaps clips at both ends.
#
#   the arm      each channel crossfades from the blow, still running on its own clock,
#                to the gait, also running, by a minimum-jerk weight: nothing has to stop
#                at either end. Hips and head first, the elbow last, as in a link.
#   the right    is planted, ahead, in every blow by OUT_AT. It is left where it stands,
#                and rolls off the ball as the body goes over it, by the gait's own
#                `stance_foot`: that is the first stride.
#   the root     is what that foot says it must be. It starts from nothing and has
#                reached the gait's speed by the moment the foot leaves the floor.
#   the left     whatever it was doing (the carry drags it up from behind) it goes on,
#                through, and lands where the gait strikes: phase 0 of the clip.

# When a blow can break off, by its clip's clock: just past the carry, the right foot
# down. sword_skeleton.gd OUT_AT.
OUT_AT = dict(slash_1=(LIGHT[0] + LIGHT[1] + 0.32) / TEMPO, slash_2=(LIGHT[0] + LIGHT[1] + 0.38) / TEMPO, slash_3=(LIGHT[0] + LIGHT[1] + 0.32) / TEMPO, heavy=(HEAVY[0] + HEAVY[1] + 0.52) / TEMPO)
# The first stride, against the time it would take at the gait's own speed. A blow that
# leaves the blade high wants longer to get it down: slash_2's comes from over its shoulder.
OUT_STRIDE = dict(slash_1=2.1, slash_2=2.9, slash_3=2.1, heavy=2.5)
# How far through the clip each part hands over.
OUT_MIX =dict(pelvis=(0.0, 0.8), pq=(0.0, 0.85), spine=(0.04, 0.9), neck=(0.0, 0.7), head=(0.0, 0.72), clav=(0.05, 0.9), arm=(0.1, 1.0), elbow=(0.18, 1.0), wrist=(0.18, 1.0), arm_l=(0.0, 0.85), curl=(0.1, 0.8))


def gait_foot(g, phi, side):
    """A foot of the gait at phase `phi`, as `gait` has it."""
    sgn = 1.0 if side == "l" else -1.0
    y, z, p, toe = foot_at(phi + (0.0 if side == "l" else 0.5), g["T"], g["S"], g["s"], g["heel"], g["toe"], g["pf"], g["pr"], g["lift"], g.get("y0", 0.0), g.get("sw_pitch", 0.0))
    return (V(sgn * g["width"], y, z), p, sgn * 9.0, 0.0, toe)


def foot_vals(f):
    return (f[0].x, f[0].y, f[0].z, f[1], f[2], f[4])


def out_clip(src, t0, L0, g, gait_fn, stride=1.75):
    """From `src`, the blow's clip, at `t0`, to phase 0 of the gait `g`."""
    s, S, Tg, y0 = g["s"], g["S"], g["T"], g.get("y0", 0.0)
    speed = s / (S * Tg)
    a = src(t0, L0)
    p0 = (a.foot_r[0].y - y0 + s * 0.5) / s
    if S < 0.5:
        # The run: the foot is off the floor a flight before the left comes down.
        d = s * (1.0 - p0)
        flight = (1.5 - S) % 1.0 * Tg
        T = round((stride * d / speed + flight) * FPS) / FPS
        Tr = T - flight
    else:
        # The walk: still on it, heel coming up.
        d = s * (0.5 / S - p0)
        Tr = T = round(max(0.62, 1.6 * d / speed) * FPS) / FPS

    def root_at(x):
        if x >= Tr:
            return d + speed * (x - Tr)
        u = x / Tr
        return d * (3.0 * u * u - 2.0 * u * u * u) + speed * Tr * (u * u * u - u * u)

    dt = 1.0 / FPS
    start = foot_vals(a.foot_l)
    before = foot_vals(src(t0 - dt, L0).foot_l) if t0 > 0.0 else start
    v0 = [(p - q) / dt for p, q in zip(start, before)]
    end = foot_vals(gait_foot(g, 1.0, "l"))
    prior = foot_vals(gait_foot(g, 1.0 - dt / Tg, "l"))
    v1 = [(p - q) / dt for p, q in zip(end, prior)]

    def left(x):
        u = min(1.0, x / T)
        u2, u3 = u * u, u * u * u
        h00, h10, h01, h11 = 2 * u3 - 3 * u2 + 1, u3 - 2 * u2 + u, -2 * u3 + 3 * u2, u3 - u2
        c = [h00 * p + h10 * T * v + h01 * q + h11 * T * w for p, v, q, w in zip(start, v0, end, v1)]
        z = c[2] + g["lift"] * 0.9 * math.sin(math.pi * u) ** 2
        return (V(c[0], c[1], z), c[3], c[4], 0.0, c[5])

    def right(x):
        p = p0 + root_at(x) / s
        last = gait_foot(g, 1.0 + (x - T) / Tg, "r")
        w = mj(x / T)
        if p >= 1.0:
            foot = last
        else:
            y, z, pitch, toe = stance_foot(p, s, g["heel"], g["toe"], g["pf"], g["pr"])
            foot = (V(0.0, y + y0, z), pitch, 0.0, 0.0, toe)
        on = src(t0 + x, L0).foot_r
        # A foot just down settles flat, as it was going to.
        e = mj(x / 0.14)
        pitch = on[1] + (foot[1] - on[1]) * e
        z = on[0].z + (foot[0].z - on[0].z) * e
        return (V(a.foot_r[0].x + (last[0].x - a.foot_r[0].x) * w, foot[0].y, z), pitch, a.foot_r[2] + (last[2] - a.foot_r[2]) * w, 0.0, foot[4])

    def mix(name, x):
        lo, hi = OUT_MIX[name]
        return mj((x / T - lo) / (hi - lo))

    def fn(x, _L):
        b = src(t0 + x, L0)
        n = gait_fn((x - T) % Tg, Tg) if x < T else gait_fn(0.0, Tg)
        sp = Spec()
        sp.root = V(0, -root_at(x), 0)
        w = mix("pelvis", x)
        sp.pelvis = b.pelvis.lerp(n.pelvis, w)
        sp.pelvis_q = b.pelvis_q.slerp(n.pelvis_q, mix("pq", x))
        w = mix("spine", x)
        # It throws its weight forward to get going.
        push = math.sin(math.pi * x / T) ** 2
        sp.spine = lerp(b.spine, n.spine, w)
        sp.spine = (sp.spine[0] + 7.0 * push, sp.spine[1], sp.spine[2])
        sp.neck = lerp(b.neck, n.neck, mix("neck", x))
        sp.head = lerp(b.head, n.head, mix("head", x))
        w = mix("clav", x)
        sp.clav_l = lerp(b.clav_l, n.clav_l, w)
        sp.clav_r = lerp(b.clav_r, n.clav_r, w)
        w = mix("arm", x)
        e = mix("elbow", x)
        sp.arm_r = (b.arm_r[0] + (n.arm_r[0] - b.arm_r[0]) * w, b.arm_r[1] + (n.arm_r[1] - b.arm_r[1]) * w, b.arm_r[2] + (n.arm_r[2] - b.arm_r[2]) * e)
        # A blade going from in front to behind it goes round the outside, or it goes through
        # the leg and the floor (the low gait, note 141).
        sp.arm_r = (sp.arm_r[0], sp.arm_r[1] + g.get("out_wide", 0.0) * push, sp.arm_r[2] + g.get("out_el", 0.0) * push)
        sp.roll_r = b.roll_r + (n.roll_r - b.roll_r) * w
        sp.hand_r = b.hand_r.slerp(n.hand_r, mix("wrist", x))
        w = mix("arm_l", x)
        sp.arm_l = lerp(b.arm_l, n.arm_l, w)
        sp.roll_l = b.roll_l + (n.roll_l - b.roll_l) * w
        sp.hand_l = b.hand_l.slerp(n.hand_l, w)
        w = mix("curl", x)
        sp.curl = b.curl + (n.curl - b.curl) * w
        sp.spread = b.spread + (n.spread - b.spread) * w
        sp.foot_l = left(x)
        sp.foot_r = right(x)
        return sp

    fn.out = (src, t0, L0, gait_fn, Tg)
    return fn, T


# --- Moving on guard ----------------------------------------------------------------------
#
# Circling someone (note 140): the body faces them and the feet go wherever it is going.
# A foot is the walk's own (`foot_at`), run along the way it is going from where the
# fighting stance has it, so the right foot stays ahead and the left behind, each on its
# own line, and they pass each other as a walk's do. The hips and feet turn a share of
# the way toward the going, and the chest turns back by as much: the blade stays on them.

STRAFE_V = 1.5      # sword_skeleton.gd STRAFE_SPEED
STRAFE_T = 1.0
STRAFE_S = 0.6
STRAFE_HIP = 0.33
STRAFE_FOOT = 0.42
# The hunting gaits' own guards (note 141), over the fighting stance: longer or quicker
# steps, how far down it is, how far over, and the two arms' angles added to the guard's.
STRAFE_LOW = dict(T=1.22, S=0.62, lift=0.055, dz=-0.055, lean=7.0, head=-6.0, arm=(-14.0, 8.0, -30.0), wrist=-6.0, arm_l=(-8.0, 6.0, -14.0), curl=0.12)
STRAFE_HIGH = dict(T=0.82, S=0.58, lift=0.09, dz=0.03, lean=-4.0, head=3.0, arm=(24.0, 8.0, 34.0), wrist=4.0, arm_l=(8.0, 2.0, 8.0), curl=-0.05)


def strafe(deg, st=None):
    """`deg`: the way it goes, 90 to its left, -90 to its right, 0 straight at them."""
    T, S = (st["T"], st["S"]) if st else (STRAFE_T, STRAFE_S)
    lift = st["lift"] if st else 0.07
    s = STRAFE_V * T * S
    th = rad(deg)
    dx, dy = math.sin(th), -math.cos(th)
    side = abs(math.sin(th))
    heel, toe = 16.0 - 9.0 * side, 28.0 - 12.0 * side
    hip = deg * STRAFE_HIP
    fy = deg * STRAFE_FOOT
    # Going ahead the two lines close up: the stance's stagger is no use to a walk.
    al = (STANCE["l"][0], STANCE["l"][1] * (0.4 + 0.6 * side))
    ar = (STANCE["r"][0], STANCE["r"][1] * (0.4 + 0.6 * side))
    # The hips go over whichever foot is down, across the way it is going.
    nx, ny = -dy, dx
    if (al[0] - ar[0]) * nx + (al[1] - ar[1]) * ny < 0.0:
        nx, ny = -nx, -ny

    def foot(a, phi, yaw):
        y, z, pitch, tb = foot_at(phi, T, S, s, heel, toe, 0.16, 0.56, lift, 0.0)
        return (V(a[0] - dx * y, a[1] - dy * y, z), pitch, yaw, 0.0, tb)

    def fn(t, _L):
        phi = (t / T) % 1.0
        c, sn = math.cos, math.sin
        sp = fight_base(t, T)
        if st:
            sp.pelvis = sp.pelvis + V(0.0, 0.0, st["dz"])
            sp.spine = (sp.spine[0] + st["lean"], sp.spine[1], sp.spine[2])
            sp.head = (sp.head[0] + st["head"], sp.head[1], sp.head[2])
            sp.arm_r = tuple(a + b for a, b in zip(sp.arm_r, st["arm"]))
            sp.arm_l = tuple(a + b for a, b in zip(sp.arm_l, st["arm_l"]))
            sp.hand_r = wrist(GUARD["wr"][0] + st["wrist"], GUARD["wr"][1], 0.0)
        sp.foot_l = foot(al, phi, STANCE["yl"] + fy)
        sp.foot_r = foot(ar, phi + 0.5, STANCE["yr"] + fy)
        shift = 0.032 * sn(TAU * (phi + 0.04))
        p = sp.pelvis
        sp.pelvis = V(p.x + nx * shift, p.y + ny * shift, p.z - 0.014 * c(2.0 * TAU * (phi + 0.02)))
        swing = 6.0 * c(TAU * (phi + 0.01))
        sp.pelvis_q = rz(rad(16.0 + hip - swing)) @ rx(rad(7.0 + 3.0 * c(th))) @ ry(rad(3.0 * sn(th) - 2.5 * sn(TAU * (phi + 0.05))))
        a = sp.spine
        sp.spine = (a[0] + 1.2 * c(2.0 * TAU * (phi - 0.1)), a[1] - hip + swing * 0.8, a[2] + 1.8 * sn(TAU * (phi + 0.05)))
        sp.neck = (sp.neck[0], sp.neck[1] - swing * 0.2, sp.neck[2])
        # Both arms ride it a beat late, the blade later: it weighs more.
        r = sp.arm_r
        sag = c(TAU * (phi - 0.2))
        sp.arm_r = (r[0] + 2.0 * sag, r[1] + 1.5 * sn(TAU * (phi - 0.2)), r[2] - 2.5 * sag)
        sp.hand_r = wrist(GUARD["wr"][0] + (st["wrist"] if st else 0.0) + 1.5 * c(TAU * (phi - 0.3)), GUARD["wr"][1], 0.0)
        l = sp.arm_l
        sp.arm_l = (l[0] - 6.0 * c(TAU * (phi - 0.08)), l[1] + 2.0 * sn(TAU * phi), l[2] + 4.0 * c(TAU * (phi - 0.14)))
        sp.curl = 0.5 + (st["curl"] if st else 0.0) + 0.06 * sn(TAU * (phi + 0.1))
        return sp

    return fn, T


def strafe_back(st=None):
    """Backing off on guard: the guarded walk played backward, so the toe lands first."""
    fwd, T = strafe(0.0, st)

    def fn(t, L):
        return fwd((L - t) % L, L)

    return fn, T


# --- Parried ------------------------------------------------------------------------------
#
# The blade is turned back on it (note 140): the arm is flung wide and the chest goes back
# after it, and it reels back in two steps and a third, buckling. It stands hunched a
# moment with the blade hanging, the clang still in the arm, then hauls the guard back up.
# A blow's clock, so it ends on idle_fight's first frame at no speed.

REEL = 1.5          # sword_skeleton.gd REEL_TIME
REEL_BACK = 1.08


def reel():
    bl = Blow(1.3, 1.1)
    b = _b()
    back = REEL_BACK
    bl.key("root", [(0.0, 0.0), (0.12, -0.12), (0.3, -0.38), (0.52, -0.74), (0.78, -1.0), (1.0, -back), (1.3, -back)])
    bl.feet("l", [(0.04, 0.3, (0.2, 0.84), 24.0, 0.07), (0.62, 0.86, (STANCE["l"][0], STANCE["l"][1] + back), STANCE["yl"], 0.05)])
    bl.feet("r", [(0.18, 0.5, (-0.17, 0.4), -10.0, 0.07), (0.9, 1.16, (STANCE["r"][0], STANCE["r"][1] + back), STANCE["yr"], 0.04)])
    bl.key("pelvis", [(0.0, b["p"]), (0.14, (0.02, 0.1, 1.22)), (0.34, (0.01, 0.08, 1.19)), (0.6, (-0.02, -0.03, 1.15)), (0.85, (0.0, -0.04, 1.17)), (1.1, (0.01, -0.01, 1.22)), (1.3, b["p"])])
    bl.key("pq", [(0.0, b["pq"]), (0.14, (-8.0, 30.0, -4.0)), (0.34, (-4.0, 26.0, -6.0)), (0.6, (16.0, 10.0, 4.0)), (0.85, (14.0, 6.0, -3.0)), (1.1, (9.0, 14.0, 0.0)), (1.3, b["pq"])])
    bl.key("spine", [(0.0, b["spine"]), (0.14, (-16.0, 14.0, -4.0)), (0.34, (-10.0, 10.0, -6.0)), (0.6, (20.0, -4.0, 6.0)), (0.85, (18.0, -10.0, -4.0)), (1.1, (11.0, -8.0, 0.0)), (1.3, b["spine"])])
    bl.key("neck", [(0.0, b["neck"]), (0.18, (-10.0, 2.0, 0.0)), (0.4, (-4.0, 0.0, 3.0)), (0.62, (8.0, -6.0, 0.0)), (0.9, (6.0, 4.0, -2.0)), (1.3, b["neck"])])
    bl.key("head", [(0.0, b["head"]), (0.2, (-34.0, 0.0, -6.0)), (0.42, (-26.0, 6.0, 6.0)), (0.64, (-6.0, -8.0, 0.0)), (0.86, (-8.0, 10.0, -3.0)), (1.05, (-14.0, -6.0, 2.0)), (1.3, b["head"])])
    # Swing, out, roll: wide, then hanging, then hauled up. The elbow is opened by the blow.
    bl.key("arm", [(0.0, b["arm"]), (0.14, (52.0, 58.0, 4.0)), (0.34, (30.0, 66.0, 2.0)), (0.6, (24.0, 48.0, 6.0)), (0.85, (20.0, 38.0, 8.0)), (1.1, (22.0, 28.0, 10.0)), (1.3, b["arm"])])
    bl.key("elbow", [(0.0, b["el"]), (0.14, 34.0), (0.34, 28.0), (0.6, 30.0), (0.85, 40.0), (1.1, 60.0), (1.3, b["el"])])
    bl.key("wrist", [(0.0, b["wrist"]), (0.14, (-16.0, -10.0, 0.0)), (0.6, (-6.0, -8.0, 0.0)), (1.3, b["wrist"])])
    bl.key("arm_l", [(0.0, b["al"]), (0.16, (8.0, 58.0, 30.0)), (0.4, (-6.0, 50.0, 22.0)), (0.62, (18.0, 34.0, 34.0)), (0.9, (26.0, 26.0, 52.0)), (1.3, b["al"])])
    bl.key("curl", [(0.0, 0.5), (0.14, 0.2), (0.6, 0.85), (1.3, 0.5)])
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (0.14, (5.0, -4.0)), (0.6, (-6.0, 3.0)), (1.3, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (0.16, (4.0, -3.0)), (0.6, (-4.0, 2.0)), (1.3, (0.0, 0.0))])
    keyed = blow_clip(bl)

    def fn(t, L):
        sp = keyed(t, L)
        # The clang, ringing out through the arm.
        ring = smr(t, 0.1, 0.22) * (1.0 - smr(t, 0.5, 1.0)) * math.sin(TAU * 11.0 * t)
        r = sp.arm_r
        sp.arm_r = (r[0], r[1], r[2] + 1.6 * ring)
        return sp

    return fn, bl.L


# --- The leap -----------------------------------------------------------------------------
#
# A gap closer (note 146). It sinks, the blade swept down behind it; the legs throw it up and
# forward with the arm dragging after; it hangs at the top with the blade over its head and
# its back arched; on the way down it jackknifes, hips, chest, shoulder, then the elbow, and
# the blade comes down with all of it behind it, the point going into the floor as the body
# lands. Then it is folded over the arm, the clang ringing out, until it can wrench the blade
# out and drag it home. A blow's clock, so it ends on idle_fight's first frame at no speed.
#
# Not on TEMPO: how long it is in the air is the jump, not the pace of its blows. The capsule
# stays on the floor and the clip does the height, so `root` is only ever forward.
#
#   jump_slam                       from the guard: two feet
#   leap_run, _low, _high           off the run, in stride: one foot (`leap_in`)
#
# Each of those is the jump_slam from LEAP_JOIN on, so they all land the same, and `thrown`
# can start from it wherever they came from.

# All of these are sword_skeleton.gd's own: the same names. The ATTACK window is LEAP_A to
# LEAP_STRIKE, when the point meets the floor (`[leap]` in --check reads it); LEAP_B is the
# arm's last key before that. `LEAP_REACH` is the root's travel in the air, which the game
# stretches to fit.
LEAP_OFF = 0.62
LEAP_LAND = 1.42
LEAP_A = 1.16
LEAP_B = 1.5
LEAP_STRIKE = 1.56
LEAP_REACH = 5.4
LEAP_V = LEAP_REACH / (LEAP_LAND - LEAP_OFF)
# The last of the load, as the root gets up to speed; and the run after the feet come down.
LEAP_RAMP = 0.2
LEAP_STOP = 0.14
LEAP_JOIN = LEAP_OFF + 0.28
# It has the blade out of the floor by here, and can turn again.
LEAP_FREE = LEAP_LAND + 0.9
LEAP_KEYED, LEAP_SETTLE = LEAP_LAND + 1.3, LEAP_LAND + 0.85
# The arm as the point meets the floor: swing, out, roll. The chest folding brings it down.
# The body is still coming down after that, so the arm opens to keep the point where it is.
ARM_DOWN = (98.0, 4.0, 5.0)
ARM_STUCK = 113.0
# Where each foot comes down, its y on the floor with the root at zero there: the landing's
# run takes each up to the stance's own.
LAND_R = (-0.17, STANCE["r"][1] - LEAP_V * LEAP_STOP * 0.5, -10.0)
LAND_L = (0.2, STANCE["l"][1] - LEAP_V * LEAP_STOP * 0.5 + 0.04, 26.0)


def leap_root(t):
    """How far forward: up to speed in the last of the load, straight on through the air,
    and stopped dead on the landing. The body's carry after that is the hips'."""
    off, land, v = LEAP_OFF, LEAP_LAND, LEAP_V
    r0 = v * LEAP_RAMP * 0.5
    if t <= off - LEAP_RAMP:
        return 0.0
    if t <= off:
        u = (t - off + LEAP_RAMP) / LEAP_RAMP
        return v * LEAP_RAMP * (u * u * u - 0.5 * u * u * u * u)
    if t <= land:
        return r0 + v * (t - off)
    u = min(1.0, (t - land) / LEAP_STOP)
    return r0 + LEAP_REACH + v * LEAP_STOP * 0.5 * (2.0 * u - u * u)


def herm(p0, v0, p1, v1, u, h):
    u2, u3 = u * u, u * u * u
    return (2 * u3 - 3 * u2 + 1) * p0 + (u3 - 2 * u2 + u) * h * v0 + (-2 * u3 + 3 * u2) * p1 + (u3 - u2) * h * v1


def foot_of(sp, side):
    return sp.foot_l if side == "l" else sp.foot_r


def foot_tuple(f):
    return (f[0].x, f[0].y, f[0].z, f[1], f[2], f[4])


def air_foot(a, va, b, vb, u, h, tuck, trail=False):
    """Off the floor from `a` at speed `va` to `b` at speed `vb`, tucked `tuck` up on the way."""
    c = [herm(p, v, q, w, u, h) for p, v, q, w in zip(a, va, b, vb)]
    # The way along the body: what it left the floor at runs off in the first of it, rather
    # than carrying it a metre behind, and it comes through from there.
    if trail:
        k = 0.22 / h
        back = a[1] + va[1] * h * k * 0.33
        if u < k:
            c[1] = herm(a[1], va[1], back, 0.0, u / k, h * k)
        else:
            c[1] = herm(back, 0.0, b[1], vb[1], (u - k) / (1.0 - k), h * (1.0 - k))
    return (V(c[0], c[1], c[2] + tuck * math.sin(math.pi * u) ** 2), c[3], c[4], 0.0, c[5])


def jump_slam():
    n = _b()
    A, B, off, land = LEAP_A, LEAP_B, LEAP_OFF, LEAP_LAND
    E = LEAP_KEYED
    bl = Blow(E, LEAP_SETTLE)
    bl.ch["root"] = leap_root
    bl.key("pelvis", [(0.0, n["p"]), (0.16, (0.012, 0.05, 1.15)), (0.36, (0.02, 0.1, 1.0)), (0.5, (0.02, 0.07, 0.97)), (off - 0.05, (0.015, 0.0, 1.17)), (off, (0.01, -0.05, 1.3)),
                      (off + 0.16, (0.0, -0.05, 1.66)), (off + 0.3, (-0.01, -0.03, 1.8)), (off + 0.42, (-0.01, -0.02, 1.83)), (off + 0.6, (0.0, -0.01, 1.66)), (land - 0.06, (0.01, 0.0, 1.42)),
                      (land, (0.01, 0.0, 1.21)), (land + 0.1, (0.0, -0.09, 0.98)), (land + 0.22, (0.0, -0.13, 0.86)), (land + 0.36, (0.0, -0.14, 0.83)), (land + 0.62, (0.0, -0.13, 0.85)),
                      (land + 0.9, (0.0, -0.1, 0.92)), (land + 1.1, (0.0, -0.04, 1.08)), (E, n["p"])])
    bl.key("pq", [(0.0, n["pq"]), (0.16, (15.0, 18.0, 1.0)), (0.42, (30.0, 22.0, 2.0)), (0.5, (31.0, 20.0, 2.0)), (off, (9.0, 6.0, 0.0)), (off + 0.2, (-8.0, -10.0, -2.0)), (off + 0.4, (-13.0, -18.0, -3.0)),
                  (A, (-12.0, -18.0, -3.0)), (A + 0.1, (6.0, -4.0, 0.0)), (land, (22.0, 10.0, 3.0)), (land + 0.2, (31.0, 16.0, 3.0)), (land + 0.4, (32.0, 16.0, 3.0)), (land + 0.7, (31.0, 16.0, 2.0)),
                  (land + 1.05, (18.0, 16.0, 1.0)), (E, n["pq"])])
    bl.key("spine", [(0.0, n["spine"]), (0.16, (19.0, -8.0, 0.0)), (0.42, (31.0, -10.0, 0.0)), (0.5, (31.0, -10.0, 1.0)), (off, (-2.0, -7.0, 2.0)), (off + 0.22, (-18.0, -12.0, 4.0)), (off + 0.42, (-25.0, -15.0, 5.0)),
                     (A + 0.02, (-23.0, -15.0, 5.0)), (A + 0.12, (6.0, -4.0, 0.0)), (A + 0.22, (24.0, 6.0, -3.0)), (land + 0.08, (31.0, 10.0, -4.0)), (land + 0.24, (36.0, 12.0, -5.0)), (land + 0.42, (37.0, 12.0, -5.0)),
                     (land + 0.72, (35.0, 10.0, -4.0)), (land + 1.08, (20.0, 0.0, -1.0)), (E, n["spine"])])
    bl.key("neck", [(0.0, n["neck"]), (0.42, (-6.0, 0.0, 0.0)), (off + 0.1, (-4.0, 0.0, 0.0)), (A, (10.0, 3.0, 0.0)), (land + 0.12, (-14.0, 0.0, 0.0)), (land + 0.8, (-12.0, 0.0, 0.0)), (E, n["neck"])])
    bl.key("head", [(0.0, n["head"]), (0.42, (-30.0, 0.0, 0.0)), (off + 0.1, (-20.0, 0.0, 0.0)), (A, (-6.0, 4.0, 0.0)), (land + 0.16, (-38.0, 0.0, 0.0)), (land + 0.8, (-34.0, 0.0, 0.0)), (E, n["head"])])
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (0.42, (-5.0, -4.0)), (off + 0.2, (11.0, -3.0)), (A, (16.0, -4.0)), (A + 0.18, (2.0, 10.0)), (land + 0.2, (-8.0, 22.0)), (land + 0.8, (-6.0, 20.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (0.42, (-3.0, -3.0)), (off + 0.2, (7.0, 5.0)), (A, (6.0, 2.0)), (land + 0.2, (-3.0, 8.0)), (land + 0.8, (-2.0, 7.0)), (E, (0.0, 0.0))])
    # Swing, out, roll. Down behind it for the load, then up with the legs and on overhead,
    # dragging; it hangs there, and comes over on the way down.
    bl.key("arm", [(0.0, n["arm"]), (0.18, (40.0, 34.0, 8.0)), (0.42, (96.0, 46.0, 2.0)), (0.5, (112.0, 42.0, 0.0)), (off, (128.0, 26.0, 0.0)), (off + 0.2, (136.0, 17.0, 0.0)),
                   (A - 0.06, (138.0, 15.0, 0.0)), (A + 0.04, (137.0, 14.0, 1.0)), (A + 0.1, (130.0, 12.0, 1.0)), (A + 0.16, (122.0, 9.0, 2.0)), (A + 0.22, (117.0, 6.0, 3.0)), (B, ARM_DOWN),
                   (land + 0.24, (ARM_STUCK, 3.0, 6.0)), (land + 0.72, (ARM_STUCK + 1.0, 3.0, 7.0)), (land + 1.0, (78.0, 12.0, 9.0)), (E, n["arm"])])
    bl.key("elbow", [(0.0, n["el"]), (0.18, 78.0), (0.42, 90.0), (0.5, 96.0), (off, 100.0), (off + 0.2, 98.0), (A + 0.1, 96.0), (A + 0.16, 74.0), (A + 0.22, 42.0), (B, 14.0),
                     (land + 0.24, 13.0), (land + 0.72, 14.0), (land + 1.0, 40.0), (E, n["el"])])
    bl.key("wrist", [(0.0, n["wrist"]), (0.42, (-12.0, -4.0, 0.0)), (off + 0.1, (-16.0, 0.0, 0.0)), (A, (-18.0, 0.0, 0.0)), (A + 0.16, (-16.0, 0.0, 0.0)), (A + 0.24, (2.0, 0.0, 0.0)), (B, (8.0, 0.0, 0.0)), (land + 0.72, (8.0, 0.0, 0.0)), (E, n["wrist"])])
    bl.key("arm_l", [(0.0, n["al"]), (0.42, (-16.0, 42.0, 36.0)), (off, (46.0, 30.0, 70.0)), (off + 0.2, (72.0, 26.0, 74.0)), (A, (54.0, 36.0, 70.0)), (A + 0.2, (0.0, 46.0, 40.0)), (land + 0.14, (-20.0, 52.0, 26.0)),
                     (land + 0.72, (-16.0, 50.0, 30.0)), (E, n["al"])])
    bl.key("curl", [(0.0, 0.5), (0.42, 0.72), (off, 0.3), (A, 0.18), (land + 0.1, 0.85), (land + 0.72, 0.7), (E, 0.5)])
    # Down, the left planted well out and the right ahead; then each shuffled under it as it
    # heaves the blade out.
    d = leap_root(99.0)
    land_r = (LAND_R[0], LAND_R[1] - leap_root(land), LAND_R[2])
    land_l = (LAND_L[0], LAND_L[1] - leap_root(land), LAND_L[2])
    bl.feet("r", [(off, land, (land_r[0], land_r[1]), land_r[2], 0.0), (land + 0.9, land + 1.2, (STANCE["r"][0], STANCE["r"][1] - d), STANCE["yr"], 0.03)])
    bl.feet("l", [(off, land, (land_l[0], land_l[1]), land_l[2], 0.0), (land + 0.74, land + 1.08, (STANCE["l"][0], STANCE["l"][1] - d), STANCE["yl"], 0.04)])
    keyed = blow_clip(bl)
    dt = 1.0 / FPS

    def toes(side, k):
        """The load: the heels come up as the legs throw it, a foot on its ball."""
        f = bl.foot(side, k, leap_root(k))
        p = 44.0 * smr(k, off - 0.17, off + 0.02) if side == "l" else 36.0 * smr(k, off - 0.14, off + 0.03)
        return (V(f[0].x, f[0].y, sole(p) if p > 0.0 else f[0].z), p, f[2], 0.0, -p * 0.8)

    # The feet in the air. They go from where the load leaves them, at the speed it does,
    # up under the body and on to the floor; the root is taken out, so they move in its frame.
    def launch(side):
        a = foot_tuple(toes(side, off))
        b = foot_tuple(toes(side, off - dt))
        return a, [(p - q) / dt for p, q in zip(a, b)]

    def landing(side):
        land_f = LAND_L if side == "l" else LAND_R
        return (land_f[0], land_f[1], ANKLE * math.cos(rad(-14.0)) - HEEL * math.sin(rad(-14.0)), -14.0, land_f[2], 0.0), (0.0, LEAP_V, -1.4, 0.0, 0.0, 0.0)

    takeoff = {s: launch(s) for s in "lr"}
    downs = {s: landing(s) for s in "lr"}

    def foot_air(side, k):
        a, va = takeoff[side]
        b, vb = downs[side]
        return air_foot(a, va, b, vb, (k - off) / (land - off), land - off, 0.62 if side == "l" else 0.5, True)

    def fn(t, L):
        sp = keyed(t, L)
        k = bl.clock(t)
        for side in "lr":
            if k < off:
                f = toes(side, k)
            elif k < land:
                f = foot_air(side, k)
            else:
                f = bl.foot(side, k, leap_root(k))
            if side == "l":
                sp.foot_l = f
            else:
                sp.foot_r = f
        sp.knee_out = 0.12 + 0.2 * smr(k, off, off + 0.3) * (1.0 - smr(k, land + 0.8, land + 1.2))
        # The clang, ringing out through the arm and up the back.
        hit = LEAP_STRIKE
        ring = smr(t, hit - 0.01, hit + 0.05) * (1.0 - smr(t, hit + 0.2, hit + 0.62)) * math.sin(TAU * 11.0 * (t - hit))
        r = sp.arm_r
        sp.arm_r = (r[0] + 0.9 * ring, r[1], r[2] + 1.6 * ring)
        return sp

    fn.bl = bl
    return fn, bl.L


def leap_in(g, gfn, jump, L):
    """Off the run, in stride: the gait's own left foot strike to the jump_slam's flight. The
    left is the last foot it runs on and comes through as the free knee; the right goes
    down, takes the weight and is what it leaves the floor from. Body and arms go from the
    gait, still running, to the jump by a minimum-jerk weight, as `out_clip`'s do the other
    way. So the game swaps the run for this with no blend, at a left strike."""
    Tg, S, s, y0 = g["T"], g["S"], g["s"], g.get("y0", 0.0)
    speed = s / (S * Tg)
    off, join = LEAP_OFF, LEAP_JOIN
    strike = 0.5 * Tg
    # A little under the average: it sits down on the last step before it goes.
    r_off = speed * strike + (off - strike) * (0.5 * (speed + LEAP_V) - 0.5)

    def root_at(x):
        if x <= strike:
            return speed * x
        if x <= off:
            return herm(speed * strike, speed, r_off, LEAP_V, (x - strike) / (off - strike), off - strike)
        return r_off + leap_root(x) - leap_root(off)

    dt = 1.0 / FPS

    def right_down(x):
        p = (root_at(x) - root_at(strike)) / s
        y, z, pitch, toe = stance_foot(min(p, 1.0), s, g["heel"], g["toe"], g["pf"], g["pr"])
        return (V(-g["width"], y + y0 + max(p - 1.0, 0.0) * s, z), pitch, -9.0, 0.0, toe)

    leave = S * Tg

    def left_gait(x):
        return gait_foot(g, x / Tg, "l")

    # The two free stretches, each joining the jump at LEAP_JOIN at its speed.
    land_at = {s_: foot_tuple(foot_of(jump(join, L), s_)) for s_ in "lr"}
    land_v = {s_: [(p - q) / dt for p, q in zip(land_at[s_], foot_tuple(foot_of(jump(join - dt, L), s_)))] for s_ in "lr"}
    l0 = foot_tuple(left_gait(leave))
    lv = [(p - q) / dt for p, q in zip(l0, foot_tuple(left_gait(leave - dt)))]
    r0 = foot_tuple(right_down(off))
    rv = [(p - q) / dt for p, q in zip(r0, foot_tuple(right_down(off - dt)))]

    def mix(lo, hi, x):
        return mj((x / off - lo) / (hi - lo))

    def fn(x, _L):
        b = gfn(x % Tg, Tg)
        j = jump(x, L)
        if x >= join:
            j.root = V(0, -root_at(x), 0)
            return j
        sp = Spec()
        sp.root = V(0, -root_at(x), 0)
        w = mix(0.1, 1.0, x)
        sp.pelvis = b.pelvis.lerp(j.pelvis, w)
        sp.pelvis_q = b.pelvis_q.slerp(j.pelvis_q, mix(0.1, 1.0, x))
        sp.spine = lerp(b.spine, j.spine, mix(0.14, 1.0, x))
        sp.neck = lerp(b.neck, j.neck, mix(0.0, 0.8, x))
        sp.head = lerp(b.head, j.head, mix(0.0, 0.8, x))
        w = mix(0.1, 1.0, x)
        sp.clav_l = lerp(b.clav_l, j.clav_l, w)
        sp.clav_r = lerp(b.clav_r, j.clav_r, w)
        w = mix(0.12, 1.1, x)
        e = mix(0.2, 1.1, x)
        sp.arm_r = (b.arm_r[0] + (j.arm_r[0] - b.arm_r[0]) * w, b.arm_r[1] + (j.arm_r[1] - b.arm_r[1]) * w, b.arm_r[2] + (j.arm_r[2] - b.arm_r[2]) * e)
        # Round the outside, as `out_clip` takes it, though not as far: it is going up, not by.
        push = 0.4 * math.sin(math.pi * min(1.0, x / off)) ** 4
        sp.arm_r = (sp.arm_r[0], sp.arm_r[1] + g.get("out_wide", 0.0) * push, sp.arm_r[2] + g.get("out_el", 0.0) * push)
        sp.roll_r = b.roll_r + (j.roll_r - b.roll_r) * w
        sp.hand_r = b.hand_r.slerp(j.hand_r, e)
        w = mix(0.0, 0.9, x)
        sp.arm_l = lerp(b.arm_l, j.arm_l, w)
        sp.roll_l = b.roll_l + (j.roll_l - b.roll_l) * w
        sp.hand_l = b.hand_l.slerp(j.hand_l, w)
        w = mix(0.1, 0.9, x)
        sp.curl = b.curl + (j.curl - b.curl) * w
        sp.spread = b.spread + (j.spread - b.spread) * w
        sp.knee_out = 0.12 + (j.knee_out - 0.12) * smr(x, off, join)
        # The left.
        if x < leave:
            sp.foot_l = left_gait(x)
        else:
            sp.foot_l = air_foot(l0, lv, land_at["l"], land_v["l"], (x - leave) / (join - leave), join - leave, 0.3)
        # The right: the gait's, down, and away.
        if x < strike:
            sp.foot_r = gait_foot(g, x / Tg, "r")
        elif x < off:
            sp.foot_r = right_down(x)
        else:
            sp.foot_r = air_foot(r0, rv, land_at["r"], land_v["r"], (x - off) / (join - off), join - off, 0.12)
        return sp

    fn.leap = (gfn, Tg, jump)
    return fn, L


def thrown(jump):
    """The leap parried (note 146): the blade is turned back on it in the air, and it goes
    over on its back. The arm is flung behind it and its legs come up; it hits the floor
    and skids; it does not lie there. The knees come in, the blade is planted out to
    its side and it hauls itself up over it, already looking at them, and comes up into
    the guard. A blow's clock, so it ends on idle_fight's first frame at no speed."""
    j = jump.bl
    n = _b()
    A = LEAP_A + 0.14
    down, up, E = 0.5, 0.92, THROWN_KEYED

    def at(name):
        return j.ch[name](A)

    bl = Blow(E, THROWN_SETTLE)
    bl.key("root", [(0.0, 0.0), (0.1, -0.34), (0.3, -1.02), (down, -1.52), (down + 0.22, -1.78), (down + 0.4, -1.84), (E, -1.84)])
    # Flat on its back is hips on the floor, tipped back 84 degrees: as `death_back` has it.
    p0 = at("pelvis")
    bl.key("pelvis", [(0.0, p0), (0.14, (0.01, 0.1, p0[2] + 0.02)), (0.32, (0.01, 0.34, 0.78)), (down - 0.02, (0.01, 0.4, 0.27)), (down + 0.05, (0.01, 0.4, 0.19)), (down + 0.11, (0.01, 0.4, 0.235)), (down + 0.2, (0.01, 0.38, 0.19)),
                      (up, (0.02, 0.34, 0.2)), (up + 0.16, (0.03, 0.25, 0.32)), (up + 0.3, (0.03, 0.12, 0.6)), (up + 0.46, (0.02, 0.0, 0.9)), (up + 0.66, (0.012, -0.02, 1.13)), (E, n["p"])])
    q0 = at("pq")
    bl.key("pq", [(0.0, q0), (0.14, (-30.0, -8.0, 0.0)), (0.32, (-66.0, 4.0, 2.0)), (down - 0.02, (-84.0, 8.0, 3.0)), (down + 0.08, (-80.0, 8.0, 3.0)), (down + 0.2, (-84.0, 8.0, 3.0)), (up, (-82.0, 6.0, 2.0)),
                  (up + 0.16, (-58.0, 8.0, 0.0)), (up + 0.3, (-14.0, 12.0, 0.0)), (up + 0.46, (22.0, 16.0, 0.0)), (up + 0.66, (18.0, 16.0, 0.0)), (E, n["pq"])])
    s0 = at("spine")
    bl.key("spine", [(0.0, s0), (0.14, (-30.0, -8.0, 4.0)), (0.32, (-14.0, -4.0, 2.0)), (down - 0.02, (10.0, -4.0, 2.0)), (down + 0.1, (-6.0, -6.0, 3.0)), (down + 0.22, (4.0, -6.0, 3.0)), (up, (10.0, -8.0, 3.0)),
                     (up + 0.16, (40.0, -10.0, 1.0)), (up + 0.3, (56.0, -12.0, 0.0)), (up + 0.46, (40.0, -12.0, 0.0)), (up + 0.66, (20.0, -10.0, 0.0)), (E, n["spine"])])
    bl.key("neck", [(0.0, at("neck")), (0.16, (-14.0, 0.0, 0.0)), (down - 0.04, (14.0, 0.0, 0.0)), (down + 0.12, (-4.0, 4.0, 0.0)), (up, (16.0, 4.0, 0.0)), (up + 0.4, (-12.0, 0.0, 0.0)), (E, n["neck"])])
    bl.key("head", [(0.0, at("head")), (0.16, (-30.0, 0.0, 0.0)), (down - 0.04, (10.0, 0.0, 0.0)), (down + 0.12, (-16.0, 6.0, 0.0)), (up, (14.0, 4.0, 0.0)), (up + 0.4, (-30.0, 0.0, 0.0)), (E, n["head"])])
    # Swing, out, roll: flung back past its head, out flat on the floor, then planted to prop it up.
    bl.key("arm", [(0.0, at("arm")), (0.14, (150.0, 40.0, 0.0)), (0.32, (120.0, 66.0, 2.0)), (down, (60.0, 84.0, 6.0)), (down + 0.2, (44.0, 86.0, 6.0)), (up, (32.0, 78.0, 8.0)), (up + 0.16, (40.0, 68.0, 8.0)),
                   (up + 0.3, (40.0, 54.0, 10.0)), (up + 0.5, (36.0, 40.0, 12.0)), (E, n["arm"])])
    bl.key("elbow", [(0.0, j.ch["elbow"](A)), (0.14, 36.0), (0.32, 20.0), (down, 16.0), (up, 18.0), (up + 0.2, 14.0), (up + 0.42, 34.0), (E, n["el"])])
    bl.key("wrist", [(0.0, at("wrist")), (0.14, (-22.0, -6.0, 0.0)), (down, (-8.0, -6.0, 0.0)), (up, (-6.0, -6.0, 0.0)), (E, n["wrist"])])
    bl.key("arm_l", [(0.0, at("arm_l")), (0.16, (60.0, 56.0, 40.0)), (0.34, (30.0, 70.0, 30.0)), (down, (0.0, 62.0, 20.0)), (up, (-10.0, 48.0, 24.0)), (up + 0.2, (-20.0, 38.0, 16.0)), (up + 0.42, (6.0, 30.0, 40.0)), (E, n["al"])])
    bl.key("curl", [(0.0, 0.3), (0.14, 0.12), (down, 0.9), (up, 0.8), (E, 0.5)])
    bl.key("clav_r", [(0.0, at("clav_r")), (0.16, (6.0, -8.0)), (down, (0.0, 0.0)), (up + 0.2, (12.0, 4.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, at("clav_l")), (0.16, (6.0, -6.0)), (down, (0.0, 0.0)), (up + 0.2, (8.0, 2.0)), (E, (0.0, 0.0))])
    keyed = blow_clip(bl)
    d = -1.84
    # The two feet: up off the floor with the fall, down flat with the knees up as it skids,
    # then planted, in order, where it will stand, as the stance has them at the clip's end.
    stand_r = (STANCE["r"][0], STANCE["r"][1] - d, 0.0)
    stand_l = (STANCE["l"][0], STANCE["l"][1] - d, 0.0)

    def feet(side, k, root):
        far = 1.0 if side == "l" else 0.82
        sx = 0.28 if side == "l" else -0.32
        st = stand_l if side == "l" else stand_r
        yw = STANCE["yl"] if side == "l" else STANCE["yr"]
        fall = smr(k, 0.0, 0.4)
        lie = smr(k, down, up)
        tuck = smr(k, up - 0.06, up + 0.14 if side == "r" else up + 0.26)
        y = -0.52 * far * (1.0 - tuck) + 0.04 * lie
        z = ANKLE + (0.5 * far * math.sin(math.pi * min(1.0, k / (down + 0.12))) ** 2) * (1.0 - tuck)
        x = sx + (st[0] - sx) * tuck
        y = y * (1.0 - tuck) + (st[1] + root) * tuck
        pitch = -44.0 * fall * (1.0 - tuck)
        yaw = (yw + (20.0 if side == "l" else -24.0) * (1.0 - tuck))
        return (V(x, y, z), pitch, yaw, 0.0, 0.0)

    start = {s_: foot_tuple(foot_of(jump(A, 3.0), s_)) for s_ in "lr"}

    def fn(t, L):
        sp = keyed(t, L)
        k = bl.clock(t)
        root = -sp.root.y
        for side in "lr":
            f = feet(side, k, root)
            w = mj(k / 0.22)
            a = start[side]
            f = (V(a[0] + (f[0].x - a[0]) * w, a[1] + (f[0].y - a[1]) * w, a[2] + (f[0].z - a[2]) * w), a[3] + (f[1] - a[3]) * w, a[4] + (f[2] - a[4]) * w, 0.0, 0.0)
            if side == "l":
                sp.foot_l = f
            else:
                sp.foot_r = f
        sp.knee_out = 0.12 + 0.9 * smr(k, 0.1, down) * (1.0 - smr(k, up + 0.1, up + 0.5))
        return sp

    return fn, bl.L


# sword_skeleton.gd THROWN_TIME is this clip's length: 2.05 s.
THROWN_KEYED, THROWN_SETTLE = 1.85, 1.65


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
    loop("idle_fight", idle_fight, FIGHT_L)
    loop("walk", walk, WALK_G["T"])
    loop("run", run, RUN_G["T"])
    loop("haul", haul, WALK_G["T"])
    loop("idle_haul", idle_haul, 6.0)
    a, b = turn(1.0), turn(-1.0)
    loop("turn_l", a[0], a[1])
    loop("turn_r", b[0], b[1])
    a, b = turn_guard(1.0), turn_guard(-1.0)
    loop("turn_gl", a[0], a[1])
    loop("turn_gr", b[0], b[1])
    once("relax", relax())
    for k, tag in ((1.0, ""), (SHORT, "_s")):
        once("slash_1" + tag, slash_1(k))
        once("slash_2" + tag, slash_2(k))
        once("slash_3" + tag, slash_3(k))
        once("heavy" + tag, heavy(k))
    BLOW_FNS.update(slash_1=slash_1, slash_2=slash_2, slash_3=slash_3, heavy=heavy)
    for a, b, name in LINKS:
        once(name, link_clip(a, b))
    gaits = (("walk", WALK_G, walk), ("run", RUN_G, run))
    for blow, tag in (("slash_1", "1"), ("slash_2", "2"), ("slash_3", "3"), ("heavy", "h")):
        for k, sh in ((1.0, ""), (SHORT, "s")):
            fn, L = BLOW_FNS[blow](k)
            for gname, g, gfn in gaits:
                once("out_%s%s_%s" % (tag, sh, gname), out_clip(fn, OUT_AT[blow], L, g, gfn, OUT_STRIDE[blow]))
    # Out of the guard, standing, the same way.
    for gname, g, gfn in gaits:
        once("out_g_" + gname, out_clip(lambda _t, _L: fight_base(), 0.0, 2.2, g, gfn))
    for s, side in ((1.0, "l"), (-1.0, "r")):
        for guard, name in ((False, "pivot_"), (True, "gpivot_")):
            once(name + side, pivot(s, 90, guard))
            once(name + side + "b", pivot(s, 180, guard))
    for d in "bflr":
        once("stagger_" + d, stagger(d))
    for tag, fn_len in (("l", strafe(90.0)), ("r", strafe(-90.0)), ("f", strafe(0.0)), ("b", strafe_back())):
        loop("strafe_" + tag, fn_len[0], fn_len[1])
    once("reel", reel())
    once("death_b", death_back())
    leap = jump_slam()
    once("jump_slam", leap)
    once("thrown", thrown(leap[0]))
    for tag, rg in (("", RUN_G), ("_low", RUN_LOW), ("_high", RUN_HIGH)):
        once("leap_run" + tag, leap_in(rg, gait_fn(rg), leap[0], leap[1]))
    once("death_f", death_fwd())
    once("death_s", death_side())
    # The hunting gaits (note 141). Only a proel after someone uses them, and an `out` clip
    # takes one after someone, so only their runs have `out` clips.
    for tag, wg, rg, st in (("_low", WALK_LOW, RUN_LOW, STRAFE_LOW), ("_high", WALK_HIGH, RUN_HIGH, STRAFE_HIGH)):
        loop("walk" + tag, gait_fn(wg), wg["T"])
        rfn = gait_fn(rg)
        loop("run" + tag, rfn, rg["T"])
        for blow, btag in (("slash_1", "1"), ("slash_2", "2"), ("slash_3", "3"), ("heavy", "h")):
            for k, sh in ((1.0, ""), (SHORT, "s")):
                fn, L = BLOW_FNS[blow](k)
                once("out_%s%s_run%s" % (btag, sh, tag), out_clip(fn, OUT_AT[blow], L, rg, rfn, OUT_STRIDE[blow]))
        once("out_g_run" + tag, out_clip(lambda _t, _L: fight_base(), 0.0, 2.2, rg, rfn))
        for way, fn_len in (("l", strafe(90.0, st)), ("r", strafe(-90.0, st)), ("f", strafe(0.0, st)), ("b", strafe_back(st))):
            loop("strafe_" + way + tag, fn_len[0], fn_len[1])


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


def pace_report(name, tips, A, B):
    """The blow's weight as speeds of the tip: slow up, fast down, and how long the
    swing takes to run off after the ATTACK window shuts."""
    v = [(tips[i + 1] - tips[i]).length * FPS for i in range(len(tips) - 1)]
    a, b = int(A * FPS), int(B * FPS)

    def part(i, j):
        s = v[i:j]
        return sum(s) / max(len(s), 1), max(s)

    up, swing, rec = part(0, a), part(a, b), part(b, len(v))
    peak = max(v)
    at = v.index(peak) / FPS
    # After the window: how long until it has shed nine tenths of the peak, and how
    # far the tip has gone on by then.
    i = b
    while i < len(v) and v[i] > peak * 0.1:
        i += 1
    carried = sum(v[b:i]) / FPS
    print("[pace]  %-12s wind-up %.1f (peak %.1f)  swing %.1f (peak %.1f @ A%+.2f)  recovery %.1f (peak %.1f)  carried on %.2f s, %.2f m, at B %.0f%% of peak" % (
        name, up[0], up[1], swing[0], swing[1], at - A, rec[0], rec[1], (i - b) / FPS, carried, 100.0 * v[min(b, len(v) - 1)] / peak), flush=True)


def seg_gap(a, b, c, d, n=8):
    """The gap between segments ab and cd, near enough: `ab` sampled onto `cd`."""
    u = d - c
    uu = max(u.dot(u), 1e-9)
    best = 9.0
    for i in range(n + 1):
        p = a + (b - a) * (i / n)
        s = max(0.0, min(1.0, (p - c).dot(u) / uu))
        best = min(best, (p - (c + u * s)).length)
    return best


# What the blade must not go through: bone to bone, and how thick it is there.
CLEAR = (("pelvis", "chest", 0.2), ("chest", "head", 0.13), ("thigh.L", "shin.L", 0.1), ("shin.L", "foot.L", 0.08), ("thigh.R", "shin.R", 0.1), ("shin.R", "foot.R", 0.08),
         ("upper_arm.L", "forearm.L", 0.07), ("forearm.L", "hand.L", 0.06))
# Where the blow is meant to land: the game stops its step this far from them,
# centre to centre (sword_skeleton.gd STANDOFF), and the sweep's test capsule.
STANDOFF = 1.3
TARGET_LOW, TARGET_HIGH, TARGET_R = 0.25, 1.55, 0.42


def reach_report(name, elbows, tips, rootz, A, B):
    """When the blade (elbow to point, as the game sweeps it) goes through someone
    standing where the step ends. It has to be inside the ATTACK window."""
    end = rootz[-1]
    low, high = V(0, -STANDOFF, TARGET_LOW), V(0, -STANDOFF, TARGET_HIGH)
    first, best = None, (9.0, 0)
    for i in range(int(A * FPS), int(B * FPS) + 1):
        # Swept from the frame before, in four steps, as the game does
        # (skeleton_sword.gd `strike`): at note 148's tempo the point moves over a
        # metre a frame, and frame by frame alone would step past them.
        for k in range(1 if i > 0 else 4, 5):
            t = k / 4.0
            j = max(i - 1, 0)
            off = V(0, -(rootz[j] + (rootz[i] - rootz[j]) * t) + end, 0)
            el = elbows[j] + (elbows[i] - elbows[j]) * t
            tp = tips[j] + (tips[i] - tips[j]) * t
            gap = seg_gap(el + off, tp + off, low, high)
            if gap < best[0]:
                best = (gap, i)
            if gap < TARGET_R and first is None:
                first = i
    print("[reach] %-12s %s, window A+0 .. A%+.2f, nearest in it %.2f m at A%+.2f" % (name, "lands at A%+.2f" % (first / FPS - A) if first is not None else "MISSES", B - A, best[0], best[1] / FPS - A), flush=True)


def bake_clip(arm, name, fn, L, loop_):
    n = int(round(L * FPS))
    frames = n + 1
    data = {}
    for pb in arm.pose.bones:
        data[pb.name] = []
    roots, pelvs = [], []
    tracks = {}
    tips, grips, edges, rootz, low_tip = [], [], [], [], 9.0
    high_tip, elbows, stretch, near = 0.0, [], 0.0, (9.0, "", 0)
    base = name[:-2] if name.endswith("_s") else name
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
        high_tip = max(high_tip, tip.z)
        tips.append(tip)
        grips.append(s.P["blade"].copy())
        elbows.append(s.P["forearm.R"].copy())
        edges.append(s.G["blade"] @ BLADE_EDGE)
        rootz.append(-sp.root.y)
        # A leg stretched past its reach leaves its planted foot behind.
        stretch = max(stretch, (s.P["foot.L"] - sp.foot_l[0]).length, (s.P["foot.R"] - sp.foot_r[0]).length)
        if base in BLOWS or name.startswith(("link_", "out_", "gpivot_", "pivot_", "strafe_", "reel", "walk_", "run_", "leap_", "jump_", "thrown")):
            edge_at = s.P["blade"] + (tip - s.P["blade"]) * 0.2
            for b0, b1, thick in CLEAR:
                gap = seg_gap(edge_at, tip, s.P[b0], s.P[b1]) - thick
                if gap < near[0]:
                    near = (gap, b0, f)
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
    print("[check] %-12s %.4f  %s @ %d   tip %.2f..%.2f   foot off its mark %.3f" % (name, worst[0], worst[1], worst[2], low_tip, high_tip, stretch), flush=True)
    roll_report(name, lq, L)
    if base in BLOWS:
        w, a, _r = HEAVY if base == "heavy" else LIGHT
        w, a = w / TEMPO, a / TEMPO
        blow_report(name, tips, grips, edges, w, w + a, rootz)
        pace_report(name, tips, w, w + a)
        reach_report(name, elbows, tips, rootz, w, w + a)
        print("[clear] %-12s blade to body %.3f (%s) @ %d" % (name, near[0], near[1], near[2]), flush=True)
    if name.startswith(("link_", "out_", "gpivot_", "pivot_", "strafe_", "reel", "walk_", "run_", "leap_", "jump_", "thrown")):
        v = [(tips[i + 1] - tips[i]).length * FPS for i in range(len(tips) - 1)]
        print("[pace]  %-12s tip mean %.1f peak %.1f m/s @ %.2f" % (name, sum(v) / len(v), max(v), v.index(max(v)) / FPS), flush=True)
        print("[clear] %-12s blade to body %.3f (%s) @ %d" % (name, near[0], near[1], near[2]), flush=True)
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


SEEN = ("head", "hand.L", "hand.R", "foot.L", "foot.R", "pelvis", "chest")


def seen_at(fn, t, L):
    s = solve(fn(t, L))
    return {b: s.P[b] for b in SEEN} | {"tip": s.P["blade"] + s.G["blade"] @ (TIP_REST - RH["blade"])}


def worst_gap(a, b):
    return max(((a[k] - b[k]).length, k) for k in a)


def seam_report():
    """The joins, by what shows: a blow's end against the first frame of idle_fight,
    how fast the tip is still going as it gets there, and each link against the clips
    on either side of it, in place and in speed, on both of a blow's steps."""
    fns = {c[0]: (c[1], c[2]) for c in CLIPS}
    guard = seen_at(idle_fight, 0.0, 2.2)
    for name, (fn, L) in fns.items():
        base = name[:-2] if name.endswith("_s") else name
        if base not in BLOWS:
            continue
        gap = worst_gap(seen_at(fn, L, L), guard)
        speed = []
        for ago in (0.4, 0.3, 0.2, 0.1, 0.05):
            a, b = seen_at(fn, L - ago, L), seen_at(fn, L - ago + 1.0 / FPS, L)
            speed.append("%.1f" % ((b["tip"] - a["tip"]).length * FPS))
        print("[seam]  %-12s end to guard %.4f (%s), tip speed at -0.4 .. -0.05 s: %s" % (name, gap[0], gap[1], " ".join(speed)), flush=True)
    dt = 1.0 / FPS
    for a, b, name in LINKS:
        fn, ln = fns[name]
        w, s, _r = LIGHT
        t0 = (w + s + LINK_OUT) / TEMPO
        w, _s, _r = HEAVY if b == "heavy" else LIGHT
        t1 = (w - LINK_IN[b]) / TEMPO
        for tag in ("", "_s"):
            fa, la = fns[a + tag]
            fb, lb = fns[b + tag]
            out = worst_gap(seen_at(fa, t0, la), seen_at(fn, 0.0, ln))
            into = worst_gap(seen_at(fn, ln, ln), seen_at(fb, t1, lb))

            def speed(f, t, L):
                p, q = seen_at(f, t - dt, L), seen_at(f, t + dt, L)
                return {k: (q[k] - p[k]) * (0.5 / dt) for k in p}

            vo = worst_gap(speed(fa, t0, la), speed(fn, 0.0, ln))
            vi = worst_gap(speed(fn, ln, ln), speed(fb, t1, lb))
            print("[link]  %-10s %-9s out %.4f (%s) speed %.3f (%s)   in %.4f (%s) speed %.3f (%s)" % (name, a + tag + ">" + b + tag, out[0], out[1], vo[0], vo[1], into[0], into[1], vi[0], vi[1]), flush=True)

    def speed_of(f, t, L, e=0.5 / FPS):
        p, q = seen_at(f, t - e, L), seen_at(f, t + e, L)
        return {k: (q[k] - p[k]) * (0.5 / e) for k in p}

    for name, (fn, L) in fns.items():
        if not name.startswith("out_"):
            continue
        src, t0, L0, gfn, Tg = fn.out
        if t0 > 0.0:
            at_start = worst_gap(seen_at(src, t0, L0), seen_at(fn, 0.0, L))
            vs = worst_gap(speed_of(src, t0 + 1.0 / FPS, L0), speed_of(fn, 1.0 / FPS, L))
        else:
            at_start, vs = (0.0, "-"), (0.0, "-")
        at_end = worst_gap(seen_at(fn, L, L), seen_at(gfn, 0.0, Tg))
        ve = worst_gap(speed_of(fn, L - 1.0 / FPS, L), speed_of(gfn, Tg - 1.0 / FPS, Tg))
        print("[out]   %-12s %.2f s   from the blow %.4f (%s) speed %.3f (%s)   into the gait %.4f (%s) speed %.3f (%s)" % (name, L, at_start[0], at_start[1], vs[0], vs[1], at_end[0], at_end[1], ve[0], ve[1]), flush=True)
    for name, (fn, L) in fns.items():
        if "pivot_" in name:
            base = fight_base if name.startswith("g") else (lambda: idle(0.0, 6.0))
            b = seen_at(lambda _t, _L: base(), 0.0, 1.0)
            print("[pivot] %-12s %.2f s   starts %.4f, ends %.4f off the stance, turned %.1f degrees" % (name, L, worst_gap(seen_at(fn, 0.0, L), b)[0], worst_gap(seen_at(fn, L, L), b)[0], math.degrees(fn(L, L).root.x)), flush=True)
    for name, (fn, L) in fns.items():
        if name == "jump_slam" or name == "thrown":
            sp_end = worst_gap(seen_at(fn, L, L), guard)
            print("[leap]  %-12s %.2f s   ends %.4f (%s) off the guard, root %.2f m, tip speed at -0.3 .. -0.05 s: %s" % (name, L, sp_end[0], sp_end[1], -fn(L, L).root.y, " ".join("%.1f" % ((seen_at(fn, L - a + 1.0 / FPS, L)["tip"] - seen_at(fn, L - a, L)["tip"]).length * FPS) for a in (0.3, 0.2, 0.1, 0.05))), flush=True)
        if name == "jump_slam":
            print("[leap]  tip z through the window: %s" % " ".join("%.2f" % seen_at(fn, LEAP_A + i * 0.04, L)["tip"].z for i in range(12)), flush=True)
            print("[leap]  highest tip %.2f head %.2f  feet at apex %.2f  pelvis at apex %.2f" % (max(seen_at(fn, i / 30.0, L)["tip"].z for i in range(100)), max(seen_at(fn, i / 30.0, L)["head"].z for i in range(100)), min(seen_at(fn, 1.02, L)["foot.L"].z, seen_at(fn, 1.02, L)["foot.R"].z), seen_at(fn, 1.02, L)["pelvis"].z), flush=True)
        if name.startswith("leap_run"):
            gfn, Tg, jump = fn.leap
            ljoin = worst_gap(seen_at(fn, LEAP_JOIN, L), seen_at(jump, LEAP_JOIN, L))
            print("[leap]  %-12s %.2f s   from the gait %.4f (%s) speed %.3f (%s)   into the jump %.4f (%s) speed %.3f (%s)" % (name, L, worst_gap(seen_at(fn, 0.0, L), seen_at(gfn, 0.0, Tg))[0], worst_gap(seen_at(fn, 0.0, L), seen_at(gfn, 0.0, Tg))[1],
                  worst_gap(speed_of(fn, 1.0 / FPS, L), speed_of(gfn, 1.0 / FPS, Tg))[0], worst_gap(speed_of(fn, 1.0 / FPS, L), speed_of(gfn, 1.0 / FPS, Tg))[1], ljoin[0], ljoin[1],
                  worst_gap(speed_of(fn, LEAP_JOIN - 1.0 / FPS, L), speed_of(jump, LEAP_JOIN - 1.0 / FPS, L))[0], worst_gap(speed_of(fn, LEAP_JOIN - 1.0 / FPS, L), speed_of(jump, LEAP_JOIN - 1.0 / FPS, L))[1]), flush=True)
        if name.startswith("strafe_"):
            print("[strafe] %-11s loop %.4f (%s), feet at the stance's distance from %.3f, ankle low %.3f" % (name, worst_gap(seen_at(fn, 0.0, L), seen_at(fn, L - 1e-6, L))[0], worst_gap(seen_at(fn, 0.0, L), seen_at(fn, L - 1e-6, L))[1], min((solve(fn(i * L / 60.0, L)).P["foot.L"] - solve(fn(i * L / 60.0, L)).P["foot.R"]).length for i in range(60)), min(fn(i * L / 60.0, L).foot_l[0].z for i in range(60))), flush=True)
        if name == "reel":
            print("[reel]  %.2f s   starts %.4f off the guard, ends %.4f (%s), back %.2f m, tip speed at -0.3 .. -0.05 s: %s" % (L, worst_gap(seen_at(fn, 0.0, L), guard)[0], worst_gap(seen_at(fn, L, L), guard)[0], worst_gap(seen_at(fn, L, L), guard)[1], fn(L, L).root.y, " ".join("%.1f" % ((seen_at(fn, L - a + 1.0 / FPS, L)["tip"] - seen_at(fn, L - a, L)["tip"]).length * FPS) for a in (0.3, 0.2, 0.1, 0.05))), flush=True)


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
        at_frames = [L * i / (count - 1) for i in range(count)]
        base = name[:-2] if name.endswith("_s") else name
        if base in BLOWS:
            # A blow's beats, not even steps: most of its frames are the slow ones.
            w, a, r = HEAVY if base == "heavy" else LIGHT
            at_frames = [FPS * x / TEMPO for x in (0.0, w * 0.2, w * 0.55, w, w + a * 0.5, w + a, w + a + 0.2, w + a + r * 0.5, w + a + r * 0.8)]
        strip = []
        for view, loc in (("side", V(6.6, -0.5, 1.3)), ("q", V(-3.6, -5.6, 1.5))):
            row = []
            for f in at_frames:
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
        seam_report()
        return
    if sheet_dir:
        sheet(arm, actions, sheet_dir, only)
        return
    arm.animation_data.action = None
    light_eyes(bpy.data.materials["SkelGlow"])
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
