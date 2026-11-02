"""Every animation of the Proel builder (note 149), and the export.

    blender -b models/source/proel_builder/proel_builder.blend -P tools/anim_proel_builder.py
    blender -b models/source/proel_builder/proel_builder.blend -P tools/anim_proel_builder.py -- --check
    blender -b models/source/proel_builder/proel_builder.blend -P tools/anim_proel_builder.py -- --sheet <dir> [clip,clip]
    godot --headless --import --path .

Opens the .blend tools/build_proel_builder.py wrote, writes one action a clip at 60
fps, saves the .blend and exports models/proel_builder.glb.

It works as tools/anim_sword_skeleton.py does (notes 135-137, read those): each clip is
a function of time returning a `Spec`, `solve` turns that into bone rotations, the legs
by two-bone IK and the arms by joint angles, never reached for. The hammer hangs on the
axle in its yoke, so `ham` swings it about that, a hinge across X like the elbow.

Its two moves:

    the POUND     `slam_walk`, `slam_stand`: walking at the player, the hammers coming
                  down in turn, one each stride. Each hoist goes up in front and bends
                  back over the shoulder, hangs, and is driven down straight onto its
                  underside with the whole body bowing after it. The left hammer lands
                  on the left foot, the right on the right. Both clips have the same
                  arms and the same clock, so one takes over from the other mid-stride.

    the SPIN      `spin`: one clip, wind-up, swing, recovery. `root` x is the turn, in
                  radians, as for the swordsman's pivots: the game lifts that track out
                  and turns the model by it, so a blow that breaks it off leaves it
                  facing wherever it had got to. Its weight is in the speed: `Turn` is
                  a long ramp, and the arms and hips read how hard it is accelerating
                  (the hammers trail going up and overtake coming down) and how fast
                  it is going (they ride out and up, and sag as it dies). The feet are
                  planted on the floor and picked up in turn as the body comes round.

`root` y is the root motion: the game moves the body by it (proel_builder.gd).

Axes: X the builder's left, -Y its front, Z up. A rotation vector here:
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
from build_proel_builder import BONES, PARENT, PIN_KNEE_L, PIN_KNEE_R, ROOT, SEG, SRC, V, light_eyes

OUT = os.path.join(ROOT, "models", "proel_builder.glb")
FPS = 60
TAU = math.tau

# The speeds the clips are authored for (proel_builder.gd WALK_SPEED, SLAM_SPEED).
WALK_V = 1.1
SLAM_V = 0.9
TURN_RATE = math.radians(70.0)
# One stride of each foot, so two hammers: proel_builder.gd SLAM_CYCLE.
SLAM_T = 2.0
# Where in the stride each hammer lands: proel_builder.gd SLAM_AT.
HIT_L, HIT_R = 0.06, 0.56
# Into the pound from a stand (proel_builder.gd SLAM_IN), and where in the stride it ends.
SLAM_IN = 1.3
IN_PHASE = 0.32

# The spin's phases on its clip's clock: proel_builder.gd SPIN_WINDUP, SPIN_SWING,
# SPIN_RECOVER, whose wind-up runs until the hammers are moving and whose swing ends as
# they sag. SPIN_A is the coil; then SPIN_UP to get going, SPIN_CRUISE flat out, and
# SPIN_DOWN running out of turn; SPIN_REST getting up.
SPIN_A = 1.3
SPIN_UP = 1.25
SPIN_CRUISE = 0.55
SPIN_DOWN = 1.9
SPIN_REST = 1.8
SPIN_COIL = -75.0
SPIN_TURN = 720.0
SPIN_LIVE = (SPIN_A + 0.55, SPIN_A + SPIN_UP + SPIN_CRUISE + SPIN_DOWN - 0.5)
# How far it walks itself round in that, forward.
SPIN_TRAVEL = 1.5
# Parried (proel_builder.gd REEL_TIME), and how far back that takes it.
REEL = 1.7
REEL_BACK = 0.75

HEEL = 0.10         # the heel behind the ankle
BALL = 0.20         # the ball ahead of it
ANKLE = 0.19        # the ankle over the sole


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


def sm(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def smr(x, a, b):
    return sm((x - a) / (b - a))


def mj(u):
    """Minimum jerk."""
    u = max(0.0, min(1.0, u))
    return u * u * u * (10.0 + u * (-15.0 + 6.0 * u))


def lerp(a, b, e):
    return tuple(x + (y - x) * e for x, y in zip(a, b))


def track(keys):
    """Cubic through (t, value) keys, floats or tuples, flat at both ends; tangents held
    down where a key is a local peak, so a pose keyed as the extreme is the extreme."""
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
    """`fn` over a tent `w` either side of `t`: takes the kick out of a track keyed hard,
    and keeps its timing."""
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


def harm(t, L, *terms):
    """A sum of whole-number harmonics, so it loops: (cycles, amount, phase)."""
    return sum(a * math.sin(TAU * (n * t / L + p)) for n, a, p in terms)


class Spec:
    """One frame. Lengths in metres in the root's frame; angles in degrees."""

    def __init__(self):
        self.root = V(0, 0, 0)
        self.pelvis = V(0, 0, 1.2)
        self.pelvis_q = Quaternion()
        self.spine = (0.0, 0.0, 0.0)     # p, y, r, spread over the three bones
        self.neck = (0.0, 0.0, 0.0)
        self.head = (0.0, 0.0, 0.0)
        self.clav_l = (0.0, 0.0)         # up, forward
        self.clav_r = (0.0, 0.0)
        self.arm_l = (4.0, 20.0, 10.0)   # swing forward, out, elbow
        self.arm_r = (4.0, 20.0, 10.0)
        self.roll_l = 0.0                # the upper arm's roll: + turns the elbow's
        self.roll_r = 0.0                # bend in across the body, on either arm
        self.ham_l = 0.0                 # the hammer on its axle: + forward
        self.ham_r = 0.0
        # Feet: the ankle, then the foot's pitch (toes down +), yaw, roll, and the toes' bend.
        self.foot_l = (V(0.3, 0.0, ANKLE), 0.0, 16.0, 0.0, 0.0)
        self.foot_r = (V(-0.3, 0.0, ANKLE), 0.0, -16.0, 0.0, 0.0)
        self.knee_out = 0.2


REST = {}
RH = {}
for _b in BONES:
    RH[_b[0]] = _b[2]


def frame_of(y, x):
    """A rotation whose Y is `y`, its X as near `x` as can be."""
    y = y.normalized()
    x = (x - y * x.dot(y)).normalized()
    z = x.cross(y)
    return Matrix(((x.x, y.x, z.x), (x.y, y.y, z.y), (x.z, y.z, z.z))).to_quaternion()


def seg(b):
    return SEG[b][1] - SEG[b][0]


# Rotations from the bone as modelled into the canonical pose (limbs straight down, each
# hinge across X, the feet flat and pointing forward), and each hinged bone's own frame.
X = {}
RF = {}
LEN = {}
# Which way each toe points as modelled, degrees to its left of straight ahead.
FOOT_YAW = {"L": 30.0, "R": -37.0}
# Some of each hammer's vertices, off the mesh, as modelled: where it reaches.
BOX = {}


def bind_rest(arm, body):
    import numpy as np
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
        # Both axles lie across X, as the pins in the elbow and the yoke do.
        for b in ("upper_arm." + side, "forearm." + side):
            RF[b] = frame_of(seg(b), V(1, 0, 0))
            X[b] = canon_arm @ RF[b].inverted()
            LEN[b] = seg(b).length
        X["hammer." + side] = X["forearm." + side]
    me = body.data
    co = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    for side in "LR":
        gid = body.vertex_groups["hammer." + side].index
        pts = [co[v.index] for v in me.vertices if any(g.group == gid and g.weight > 0.6 for g in v.groups)]
        BOX[side] = [Vector(p.tolist()) for p in pts[::6]]
        print("[rig] hammer.%s %d verts" % (side, len(pts)), flush=True)


def two_bone(s, t, a, b, pole, soft=0.97):
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
    fk("hammer.L", rx(rad(-sp.ham_l)))
    sw, out, el = sp.arm_r
    fk("upper_arm.R", rx(rad(-sw)) @ ry(rad(out)) @ rz(rad(sp.roll_r)))
    fk("forearm.R", rx(rad(-el)))
    fk("hammer.R", rx(rad(-sp.ham_r)))

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


def hammer_low(s, side):
    """The lowest point of a hammer, solved."""
    h = "hammer." + side
    return min((s.P[h] + s.G[h] @ (c - RH[h])).z for c in BOX[side])


def hammer_mid(s, side):
    h = "hammer." + side
    c = sum(BOX[side], Vector((0, 0, 0))) / len(BOX[side])
    return s.P[h] + s.G[h] @ (c - RH[h])


# --- The gait ------------------------------------------------------------------------

def stance_foot(p, s, h_up, t_down, pf, pr):
    """p 0..1 through the stance: (y, z, pitch, toe bend). `s` the ground it travels;
    heel, flat, ball."""
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


def foot_at(phi, T, S, s, h_up, t_down, pf, pr, lift, y0):
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
    z += lift * math.sin(math.pi * w ** 0.8) ** 1.4
    toe = -p1 * (1.0 - sm(w / 0.5))
    return y + y0, z, pitch, toe


def gait(sp, phi, g):
    """Fills `sp` for phase `phi` (0: left heel strike, 0.5: right)."""
    T, S, s = g["T"], g["S"], g["s"]
    a = (phi, T, S, s, g["heel"], g["toe"], g["pf"], g["pr"], g["lift"], g.get("y0", 0.0))
    yl, zl, pl, tl = foot_at(*a)
    a = (phi + 0.5, T, S, s, g["heel"], g["toe"], g["pf"], g["pr"], g["lift"], g.get("y0", 0.0))
    yr, zr, pr_, tr = foot_at(*a)
    w = g["width"]
    sp.foot_l = (V(w, yl, zl), pl, g["fyaw"], 0.0, tl)
    sp.foot_r = (V(-w, yr, zr), pr_, -g["fyaw"], 0.0, tr)
    c = math.cos
    sn = math.sin
    bob = -g["bob"] * c(2.0 * TAU * (phi + 0.02))
    x = g["sway"] * sn(TAU * (phi + 0.04))
    sp.pelvis = V(x, g.get("hip_y", 0.0), g["z"] + bob)
    yaw = -g["pyaw"] * c(TAU * (phi + 0.01))
    roll = -g["proll"] * sn(TAU * (phi + 0.05))
    sp.pelvis_q = rz(rad(yaw)) @ rx(rad(g["plean"])) @ ry(rad(roll))
    cy = g["cyaw"] * c(TAU * (phi - 0.02))
    sp.spine = (g["lean"], cy - yaw * 0.6, -roll * 0.7)
    tot_yaw = yaw + cy - yaw * 0.6
    sp.neck = (g["neck"], -tot_yaw * 0.5, roll * 0.25)
    sp.head = (g["headp"], -tot_yaw * 0.42, roll * 0.15)
    # The arms hang: the hammers' weight keeps them to a sway, each late on its leg.
    al = -g["aswing"] * c(TAU * (phi - 0.09))
    sp.arm_l = (g["a0"] + al, g["aout"], g["ael"] + 2.0 * sn(TAU * phi))
    sp.arm_r = (g["a0"] - al, g["aout"], g["ael"] - 2.0 * sn(TAU * phi))
    sp.ham_l = -al * 0.6
    sp.ham_r = al * 0.6
    sp.clav_l = (-3.0 + 2.0 * c(TAU * (phi + 0.5)), 0.0)
    sp.clav_r = (-3.0 + 2.0 * c(TAU * phi), 0.0)


WALK_G = dict(T=1.5, S=0.62, s=WALK_V * 1.5 * 0.62, heel=16.0, toe=28.0, pf=0.14, pr=0.58, lift=0.07, width=0.24, fyaw=14.0, z=1.135, bob=0.016, sway=0.05, pyaw=7.0,
              proll=4.0, plean=4.0, cyaw=8.0, lean=9.0, neck=-2.0, headp=-4.0, aswing=7.0, a0=5.0, aout=19.0, ael=10.0)


def walk(t, L):
    sp = Spec()
    gait(sp, t / L, WALK_G)
    return sp


# --- Standing -------------------------------------------------------------------------

def idle(t, L):
    """Standing as it was made: feet wide, stooped, the hammers hanging from its arms."""
    sp = Spec()
    br = harm(t, L, (2, 1.0, 0.0), (5, 0.18, 0.2))
    sw = harm(t, L, (1, 1.0, 0.1), (3, 0.3, 0.45))
    sp.pelvis = V(0.012 * sw, 0.0, 1.165 - 0.005 * br)
    sp.pelvis_q = rz(rad(1.2 * sw)) @ rx(rad(3.0)) @ ry(rad(-0.8 * sw))
    sp.spine = (6.0 + 1.2 * br, -1.0 * sw, 0.8 * sw)
    sp.neck = (0.5 * br, 3.0 * harm(t, L, (1, 1.0, 0.55)), 0.0)
    sp.head = (-4.0 + 1.0 * harm(t, L, (3, 1.0, 0.1)), 6.0 * harm(t, L, (1, 1.0, 0.6), (2, 0.35, 0.9)), 1.2 * harm(t, L, (1, 1.0, 0.0)))
    sp.clav_l = (-3.0 + 1.5 * br, 0.0)
    sp.clav_r = (-3.0 + 1.5 * br, 0.0)
    sp.arm_l = (6.0 + 1.2 * sw, 20.0 + 0.6 * br, 10.0 + 1.5 * harm(t, L, (2, 1.0, 0.7)))
    sp.arm_r = (6.0 - 1.2 * sw, 20.0 + 0.6 * br, 10.0 + 1.5 * harm(t, L, (2, 1.0, 0.1)))
    sp.ham_l = 2.0 * harm(t, L, (2, 1.0, 0.8))
    sp.ham_r = 2.0 * harm(t, L, (2, 1.0, 0.3))
    sp.foot_l = (V(0.33, 0.0, ANKLE), 0.0, 18.0, 0.0, 0.0)
    sp.foot_r = (V(-0.33, 0.02, ANKLE), 0.0, -18.0, 0.0, 0.0)
    return sp


# --- The pound ------------------------------------------------------------------------
#
# One arm's clock runs 0 to 1 from the moment its hammer lands to the next. The arm's
# keys: stuck, then dragged up off the floor by the elbow, hoisted in front of it, the
# forearm folding back over the shoulder; a hang at the top; and the drive. The drive is
# not keyed: it gathers speed all the way down and stops dead on the floor, which is
# what a tenth of a ton of iron does. Keys are (clock, swing, out, elbow, hammer, roll).

ARM_HIT = (84.0, 25.0, 4.0, -4.0, 0.0)
ARM_TOP_AT = 0.8
ARM_TOP = (164.0, 22.0, 84.0, 24.0, 0.0)
ARM_KEYS = track([(0.0, ARM_HIT), (0.05, ARM_HIT), (0.16, (62.0, 22.0, 16.0, 6.0, 0.0)), (0.32, (58.0, 23.0, 44.0, 20.0, 0.0)), (0.5, (86.0, 24.0, 74.0, 26.0, 0.0)),
                  (0.66, (130.0, 24.0, 90.0, 28.0, 0.0)), (0.75, (159.0, 23.0, 90.0, 27.0, 0.0)), (ARM_TOP_AT, ARM_TOP)])


def arm_at(a):
    """One arm's channels at its clock `a`."""
    a %= 1.0
    if a < ARM_TOP_AT:
        return ARM_KEYS(a)
    u = (a - ARM_TOP_AT) / (1.0 - ARM_TOP_AT)
    # The shoulder goes first, the elbow late, the hammer last, whipped through.
    e = u ** 2.0
    el = sm(smr(u, 0.2, 1.0)) * 0.5 + 0.5 * smr(u, 0.2, 1.0) ** 2.5
    h = u ** 3.0
    return (ARM_TOP[0] + (ARM_HIT[0] - ARM_TOP[0]) * e, ARM_TOP[1] + (ARM_HIT[1] - ARM_TOP[1]) * e, ARM_TOP[2] + (ARM_HIT[2] - ARM_TOP[2]) * el,
            ARM_TOP[3] + (ARM_HIT[3] - ARM_TOP[3]) * h, 0.0)


# The body has one clock for both arms, running twice as fast: 0 a hammer landing. It
# bows after the hammer, stays down a moment under its weight, and comes up with the next.
BOW_TOP = 0.6
BOW_KEYS = track([(0.0, (50.0, 19.0, 1.03)), (0.08, (50.0, 19.0, 1.03)), (0.28, (29.0, 11.0, 1.065)), (0.46, (11.0, 6.0, 1.115)), (BOW_TOP, (4.0, 4.0, 1.135))])


def bow_at(b):
    """(spine pitch, pelvis pitch, pelvis height) at the body's clock `b`."""
    b %= 1.0
    if b < BOW_TOP:
        return BOW_KEYS(b)
    e = ((b - BOW_TOP) / (1.0 - BOW_TOP)) ** 2.2
    return lerp(BOW_KEYS(BOW_TOP), BOW_KEYS(0.0), e)


def pound(sp, phi):
    """The arms and the body of the pound, over a gait or a stance, at phase `phi`."""
    b = (phi - HIT_L) * 2.0
    p, pp, z = bow_at(b)
    al = arm_at(phi - HIT_L)
    ar = arm_at(phi - HIT_R)
    sp.arm_l, sp.ham_l, sp.roll_l = (al[0], al[1], al[2]), al[3], al[4]
    sp.arm_r, sp.ham_r, sp.roll_r = (ar[0], ar[1], ar[2]), ar[3], ar[4]
    # +1 as the left lands, -1 as the right does: the torso turns the landing shoulder in,
    # and leans down over that side.
    which = math.cos(TAU * (phi - HIT_L))
    down = 0.45 + 0.55 * (1.0 - b % 1.0 if b % 1.0 < BOW_TOP else (b % 1.0 - BOW_TOP) / (1.0 - BOW_TOP))
    yaw = -15.0 * which
    roll = 9.0 * which * down
    q = sp.pelvis
    sp.pelvis = V(q.x + 0.05 * which, q.y - 0.09 * (z - 1.135) / (1.0 - 1.135) * 0.5, z)
    sp.pelvis_q = rz(rad(-6.0 * which)) @ rx(rad(pp)) @ ry(rad(4.0 * which * down))
    sp.spine = (p, yaw, roll)
    # The clavicle of the landing arm drives down and forward, the rising one hikes.
    dl = bow_shoulder(phi - HIT_L)
    dr = bow_shoulder(phi - HIT_R)
    sp.clav_l, sp.clav_r = dl, dr
    # The head stays on what it is after, over all of that.
    tot = yaw * 0.9 - 6.0 * which
    sp.neck = (-p * 0.34, -tot * 0.5, -roll * 0.4)
    sp.head = (-p * 0.42 - 2.0, -tot * 0.4, -roll * 0.3)


SHOULDER_KEYS = track([(0.0, (-12.0, 16.0)), (0.06, (-12.0, 16.0)), (0.3, (-3.0, 4.0)), (0.6, (10.0, -2.0)), (ARM_TOP_AT, (15.0, -7.0)), (1.0, (-12.0, 16.0))])


def bow_shoulder(a):
    return SHOULDER_KEYS(a % 1.0)


SLAM_S = 0.6
SLAM_G = dict(T=SLAM_T, S=SLAM_S, s=SLAM_V * SLAM_T * SLAM_S, heel=14.0, toe=22.0, pf=0.1, pr=0.6, lift=0.11, width=0.25, fyaw=13.0, z=1.135, bob=0.0, sway=0.0, pyaw=0.0,
              proll=0.0, plean=0.0, cyaw=0.0, lean=0.0, neck=0.0, headp=0.0, aswing=0.0, a0=0.0, aout=0.0, ael=0.0)


def slam_walk(t, L):
    """Walking at them, a hammer to each foot."""
    sp = Spec()
    phi = t / L
    gait(sp, phi, SLAM_G)
    pound(sp, phi)
    return sp


def stand_stance(sp):
    sp.foot_l = (V(0.3, -0.03, ANKLE), 0.0, 15.0, 0.0, 0.0)
    sp.foot_r = (V(-0.3, -0.03, ANKLE), 0.0, -15.0, 0.0, 0.0)


def slam_stand(t, L):
    """The same, with nowhere to go: the feet stay where they are, and the weight goes
    from one to the other."""
    sp = Spec()
    phi = t / L
    sp.pelvis = V(0.0, 0.0, 1.135)
    stand_stance(sp)
    pound(sp, phi)
    return sp


def slam_in(t, L):
    """From a stand into the pound: one hammer stays down and the other is hoisted, with
    the body coming up to it, and at the end of it the stride is at IN_PHASE, in step."""
    a = idle(0.0, 6.0)
    phi = (IN_PHASE - (L - t) / SLAM_T) % 1.0
    b = slam_stand(phi * SLAM_T, SLAM_T)
    u = t / L
    body, arm = mj(u / 0.9), mj(u)
    sp = Spec()
    sp.pelvis = a.pelvis.lerp(b.pelvis, body)
    sp.pelvis_q = a.pelvis_q.slerp(b.pelvis_q, body)
    sp.spine = lerp(a.spine, b.spine, body)
    sp.neck = lerp(a.neck, b.neck, body)
    sp.head = lerp(a.head, b.head, body)
    sp.clav_l = lerp(a.clav_l, b.clav_l, body)
    sp.clav_r = lerp(a.clav_r, b.clav_r, body)
    sp.arm_l = lerp(a.arm_l, b.arm_l, arm)
    sp.arm_r = lerp(a.arm_r, b.arm_r, arm)
    sp.ham_l = a.ham_l + (b.ham_l - a.ham_l) * arm
    sp.ham_r = a.ham_r + (b.ham_r - a.ham_r) * arm
    for side, fa, fb in (("l", a.foot_l, b.foot_l), ("r", a.foot_r, b.foot_r)):
        e = mj(u)
        ft = (fa[0].lerp(fb[0], e), 0.0, fa[2] + (fb[2] - fa[2]) * e, 0.0, 0.0)
        if side == "l":
            sp.foot_l = ft
        else:
            sp.foot_r = ft
    return sp


# --- The spin -------------------------------------------------------------------------

class Turn:
    """How far round it has come at clip time `t`, and how fast, from `SPIN_COIL` on."""

    def __init__(self):
        n = 2400
        self.dt = (SPIN_UP + SPIN_CRUISE + SPIN_DOWN) / n
        # A smooth ramp up, flat out, and a long smooth run down: the area sets the speed.
        whole = rad(SPIN_TURN - SPIN_COIL)
        self.top = whole / (0.5 * SPIN_UP + SPIN_CRUISE + 0.5 * SPIN_DOWN)
        self.table = [0.0]
        for i in range(n):
            self.table.append(self.table[-1] + self.speed(SPIN_A + (i + 0.5) * self.dt) * self.dt)

    def speed(self, t):
        """rad/s."""
        u = t - SPIN_A
        if u <= 0.0:
            return 0.0
        if u < SPIN_UP:
            return self.top * sm(u / SPIN_UP)
        if u < SPIN_UP + SPIN_CRUISE:
            return self.top
        return self.top * (1.0 - sm((u - SPIN_UP - SPIN_CRUISE) / SPIN_DOWN))

    def push(self, t):
        """rad/s/s."""
        return (self.speed(t + 0.01) - self.speed(t - 0.01)) / 0.02

    def at(self, t):
        """Degrees."""
        if t < SPIN_A:
            return SPIN_COIL * mj(t / SPIN_A)
        f = (t - SPIN_A) / self.dt
        i = min(int(f), len(self.table) - 2)
        return SPIN_COIL + math.degrees(self.table[i] + (self.table[i + 1] - self.table[i]) * min(f - i, 1.0))

    def when(self, deg):
        """The clip time it reaches `deg`, past the coil."""
        lo, hi = SPIN_A, SPIN_A + SPIN_UP + SPIN_CRUISE + SPIN_DOWN
        for _ in range(40):
            mid = (lo + hi) * 0.5
            if self.at(mid) < deg:
                lo = mid
            else:
                hi = mid
        return hi


TURNING = None


def spin_clock():
    global TURNING
    if TURNING is None:
        TURNING = Turn()
    return TURNING


def spin_steps(home, offset):
    """Each foot's steps, from where it stands: it stays planted while the body comes
    round it and is picked up and set ahead, a third of a turn at a time. (t0, t1, (x, y,
    yaw), lift), on the floor as it was before the body moved."""
    tn = spin_clock()
    stride = 130.0
    out = []

    def at(deg):
        q = rz(rad(deg)) @ V(home[0].x, home[0].y, 0.0)
        return (q.x, q.y, home[2] + deg)

    # The coil: one step round with the turn, to wind up on.
    out.append((0.12 + offset * 0.36, 0.56 + offset * 0.36, at(SPIN_COIL), 0.06))
    a = SPIN_COIL + stride * (0.65 + offset)
    while a < SPIN_TURN - 25.0:
        t1 = tn.when(a)
        t0 = max(t1 - 0.3, tn.when(a - stride * 0.42), out[-1][1] + 0.02)
        lift = 0.05 + 0.05 * min(1.0, 3.0 / max(tn.speed(t1), 0.1))
        out.append((t0, t1, at(a), lift))
        a += stride
    # The last: home, heavily, as it runs out.
    end = SPIN_A + SPIN_UP + SPIN_CRUISE + SPIN_DOWN
    t0 = max(out[-1][1] + 0.05, end - 0.9 + offset * 0.42)
    out.append((t0, t0 + 0.42, at(SPIN_TURN), 0.09))
    return out


def walked(t):
    """How far forward it has got at clip time `t`."""
    return SPIN_TRAVEL * mj((t - SPIN_A) / (SPIN_UP + SPIN_CRUISE + SPIN_DOWN * 0.7))


def floor_foot(start, steps, t):
    """Where a foot is on the floor at `t`: (x, y, z, yaw, pitch, toe), on the floor as it
    was, each step running round the middle of the body, wherever that has got to, so a
    turn does not bring a foot through the other leg."""
    x, y, yaw = start
    z, pitch, toe = ANKLE, 0.0, 0.0
    d = walked(t)
    for t0, t1, to, lift in steps:
        d1 = walked(t1)
        # Placed where the body will be as it lands.
        tx, ty = to[0], to[1] - d1
        if t >= t1:
            x, y, yaw = tx, ty, to[2]
        elif t > t0:
            u = (t - t0) / (t1 - t0)
            e = sm(u)
            a0, a1 = math.atan2(y + d, x), math.atan2(ty + d, tx)
            sweep = (a1 - a0 + math.pi) % TAU - math.pi
            r0, r1 = math.hypot(x, y + d), math.hypot(tx, ty + d)
            r, a = r0 + (r1 - r0) * e, a0 + sweep * e
            x, y = r * math.cos(a), r * math.sin(a) - d
            yaw = yaw + (to[2] - yaw) * e
            pitch = 12.0 * (1.0 - sm(u / 0.4)) * sm(u / 0.14) - 10.0 * sm((u - 0.72) / 0.28)
            z = ANKLE + lift * math.sin(math.pi * u) ** 1.1
            toe = -5.0 * math.sin(math.pi * u)
            break
    return x, y, z, yaw, pitch, toe


def spin():
    """Coiled round to its right, the hammers drawn back and across. It starts to come
    round so slowly that for a moment nothing seems to happen; the hips go, then the
    chest, and the hammers come last, dragged. By the first turn they are flying and it
    is being pulled round after them, and it takes all of the second to stop."""
    tn = spin_clock()
    end = SPIN_A + SPIN_UP + SPIN_CRUISE + SPIN_DOWN
    L = end + SPIN_REST
    i0 = idle(0.0, 6.0)
    home = {"l": i0.foot_l, "r": i0.foot_r}
    plan = {"l": spin_steps(home["l"], 0.0), "r": spin_steps(home["r"], 0.5)}
    coil = track([(0.0, 0.0), (0.3, 0.1), (SPIN_A - 0.05, 1.0), (SPIN_A + 0.6, 0.86), (SPIN_A + SPIN_UP + 0.1, 0.0)])

    def fn(t, _L):
        sp = idle(0.0, 6.0)
        turned = tn.at(t)
        w = tn.speed(t)
        fast = (w / tn.top) ** 2
        push = tn.push(t) / tn.top
        # Coiled.
        c = coil(t)
        # Flying: how far the arms have gone out on the speed.
        fly = smr(w, 0.7, tn.top * 0.8)
        rest = smr(t, end - 0.15, L - 0.15)
        down = smr(t, end - 1.05, end + 0.1) * (1.0 - smr(t, end + 0.5, L - 0.1))
        heave = math.sin(TAU * (t - end) / 0.95) * smr(t, end, end + 0.3) * (1.0 - smr(t, L - 0.7, L - 0.1))
        z = 1.165 - 0.085 * sm(t / SPIN_A) - 0.13 * down + 0.012 * heave + 0.085 * smr(t, end + 0.1, L - 0.1)
        sp.pelvis = V(0.0, 0.0, z)
        # The hips go first and the chest lags them: both read how hard it is pushing.
        sp.pelvis_q = rz(rad(-22.0 * c + 16.0 * push)) @ rx(rad(3.0 - 7.0 * fly + 16.0 * down + 6.0 * sm(t / 0.6) * c)) 
        sp.spine = (6.0 - 4.0 * fly + 30.0 * down + 3.0 * heave + 6.0 * c, -32.0 * c - 26.0 * push, 0.0)
        sp.neck = (-3.0 * fly - 9.0 * down, 16.0 * c + 8.0 * push, 0.0)
        sp.head = (-6.0 * fly - 12.0 * down - 3.0 * heave - 4.0, 22.0 * c, 0.0)
        # Drawn back and across in the coil: the left hammer over to the right hip, the
        # right one out behind. Flying, they ride out on the speed and trail the hips or
        # overrun them. Then they are let fall.
        out_a = 24.0 + 45.0 * fly + 3.0 * math.sin(TAU * t / 0.8) * fly
        lag = 26.0 * push * (0.3 + 0.7 * fly)
        sag = 12.0 * (1.0 - fly) * (1.0 - c)
        la = (10.0 + lag, out_a - sag, 18.0 - 8.0 * fly + 8.0 * down)
        ra = (10.0 - lag, out_a - sag, 18.0 - 8.0 * fly + 8.0 * down)
        lc = (64.0, 4.0, 34.0)
        rc = (-34.0, 46.0, 14.0)
        sp.arm_l = lerp(la, lc, c)
        sp.arm_r = lerp(ra, rc, c)
        idl = idle(0.0, 6.0)
        sp.arm_l = lerp(sp.arm_l, idl.arm_l, rest)
        sp.arm_r = lerp(sp.arm_r, idl.arm_r, rest)
        sp.ham_l = 16.0 * c + 10.0 * down * (1.0 - rest)
        sp.ham_r = -14.0 * c + 10.0 * down * (1.0 - rest)
        sp.clav_l = (6.0 * c + 6.0 * fly - 8.0 * down - 2.0, 10.0 * c)
        sp.clav_r = (6.0 * c + 6.0 * fly - 8.0 * down - 2.0, -8.0 * c)
        sp.root = V(rad(turned), -walked(t), 0.0)
        q = rz(rad(-turned))
        d = walked(t)
        for side in "lr":
            f = home[side]
            x, y, zf, yaw, pitch, toe = floor_foot((f[0].x, f[0].y, f[2]), plan[side], t)
            ank = q @ V(x, y + d, 0.0)
            ft = (V(ank.x, ank.y, zf), pitch, yaw - turned, 0.0, toe)
            if side == "l":
                sp.foot_l = ft
            else:
                sp.foot_r = ft
        sp.knee_out = 0.2
        return sp

    return fn, L


# --- Hit and fall ---------------------------------------------------------------------

def reel():
    """Parried: the hammer comes back up off the guard and takes the arm and the whole
    body back with it, two heavy steps, and it stands stunned, getting its weight back."""
    L = REEL

    def fn(t, _L):
        sp = idle(0.0, 6.0)
        hit = blur(track([(0.0, 0.0), (0.08, 0.6), (0.2, 1.0), (0.5, 0.84), (1.0, 0.36), (L, 0.0)]), t, 0.04)
        late = blur(track([(0.0, 0.0), (0.12, 0.3), (0.26, 1.0), (0.6, 0.8), (1.1, 0.3), (L, 0.0)]), t, 0.05)
        back = REEL_BACK * mj(t / 1.1)
        sp.root = V(0, back, 0)
        p0 = sp.pelvis
        sp.pelvis = V(p0.x, p0.y + 0.08 * hit, p0.z - 0.09 * track([(0.0, 0.0), (0.3, 1.0), (0.9, 0.7), (L, 0.0)])(t))
        sp.pelvis_q = sp.pelvis_q @ rot(-12.0 * hit, 0.0, 0.0)
        s0 = sp.spine
        sp.spine = (s0[0] - 22.0 * hit, s0[1], s0[2])
        sp.neck = (sp.neck[0] + 14.0 * late, sp.neck[1], 0.0)
        sp.head = (sp.head[0] + 12.0 * late, sp.head[1], 0.0)
        l0, r0 = sp.arm_l, sp.arm_r
        sp.arm_l = (l0[0] + 70.0 * late, l0[1] + 16.0 * late, l0[2] + 42.0 * late)
        sp.arm_r = (r0[0] + 46.0 * late, r0[1] + 22.0 * late, r0[2] + 30.0 * late)
        sp.ham_l = 30.0 * late
        sp.ham_r = 24.0 * late
        for side, t0, t1 in (("r", 0.1, 0.5), ("l", 0.46, 0.94)):
            ft = sp.foot_l if side == "l" else sp.foot_r
            u = max(0.0, min(1.0, (t - t0) / (t1 - t0)))
            ank = ft[0].copy()
            # On the floor: each foot goes the whole way back in one step.
            ank.y += REEL_BACK * sm(u) - back
            ank.z = ANKLE + 0.08 * math.sin(math.pi * u)
            nf = (ank, -10.0 * math.sin(math.pi * u), ft[2], 0.0, 0.0)
            if side == "l":
                sp.foot_l = nf
            else:
                sp.foot_r = nf
        return sp

    return fn, L


def stagger(dirn):
    """Thrown by a blow. `dirn` where it is thrown toward: "b" back, "f" forward, "l" its
    left, "r" its right. Not far: the hammers hold it down, and swing on after the body."""
    L = 1.2
    d = {"b": (0.0, 1.0), "f": (0.0, -1.0), "l": (1.0, 0.0), "r": (-1.0, 0.0)}[dirn]
    dx, dy = d
    lean_p = -dy * 16.0         # top goes the way it is thrown
    lean_r = dx * 12.0

    def fn(t, _L):
        sp = idle(0.6, 4.0)
        hit = blur(track([(0.0, 0.0), (0.08, 0.5), (0.18, 1.0), (0.36, 0.86), (0.6, 0.34), (0.9, -0.08), (L, 0.0)]), t, 0.05)
        late = blur(track([(0.0, 0.0), (0.12, 0.2), (0.24, 1.0), (0.44, 0.84), (0.7, 0.2), (0.96, -0.14), (L, 0.0)]), t, 0.07)
        dip = track([(0.0, 0.0), (0.14, 0.3), (0.4, 1.0), (0.66, 0.6), (0.94, 0.1), (L, 0.0)])(t)
        p0 = sp.pelvis
        sp.pelvis = V(p0.x + dx * 0.08 * hit, p0.y + dy * 0.07 * hit, p0.z - 0.08 * dip)
        sp.pelvis_q = sp.pelvis_q @ rot(lean_p * 0.5 * hit, -dx * 7.0 * hit, lean_r * 0.5 * hit)
        s0 = sp.spine
        sp.spine = (s0[0] + lean_p * 1.2 * hit + 6.0 * dip, s0[1] - dx * 16.0 * hit, s0[2] + lean_r * 1.1 * hit)
        n0, h0 = sp.neck, sp.head
        sp.neck = (n0[0] + lean_p * 0.5 * late, n0[1] + dx * 6.0 * late, n0[2] + lean_r * 0.45 * late)
        sp.head = (h0[0] + lean_p * 0.9 * late, h0[1] + dx * 10.0 * late, h0[2] + lean_r * 0.8 * late)
        # The hammers come after, out the way it is going.
        l0, r0 = sp.arm_l, sp.arm_r
        sp.arm_l = (l0[0] - dy * 14.0 * late, l0[1] + dx * 12.0 * late + 3.0 * late, l0[2] + 8.0 * late)
        sp.arm_r = (r0[0] - dy * 14.0 * late, r0[1] - dx * 12.0 * late + 3.0 * late, r0[2] + 8.0 * late)
        sp.ham_l = -dy * 12.0 * late
        sp.ham_r = -dy * 12.0 * late
        back = dy > 0
        for side, t0, t1, off in (("r" if (back or dx < 0) else "l", 0.1, 0.36, 0.16), ("l" if (back or dx < 0) else "r", 0.3, 0.58, 0.13)):
            ft = sp.foot_l if side == "l" else sp.foot_r
            ank = ft[0].copy()
            u = max(0.0, min(1.0, (t - t0) / (t1 - t0)))
            e = sm(u)
            hme = sm((t - 0.7) / 0.42)
            ank = ank + V(dx, dy, 0.0) * (off * e * (1.0 - hme))
            ank.z = ANKLE + 0.05 * math.sin(math.pi * u) + 0.03 * math.sin(math.pi * max(0.0, min(1.0, (t - 0.7) / 0.42)))
            nf = (ank, -8.0 * math.sin(math.pi * u), ft[2], ft[3], ft[4])
            if side == "l":
                sp.foot_l = nf
            else:
                sp.foot_r = nf
        return sp

    return fn, L


def death_back():
    """Struck from the front: it stands a moment, the knees go and it goes over backward,
    the hammers hitting the floor either side of it after the body has."""
    L = 2.6

    def fn(t, _L):
        sp = idle(0.0, 4.0)
        fall = track([(0.0, 0.0), (0.26, 0.05), (0.56, 0.24), (0.86, 0.66), (1.06, 1.0), (1.15, 0.96), (1.26, 1.0)])(t)
        torso = track([(0.0, 0.0), (0.18, 0.08), (0.56, 0.24), (0.88, 0.72), (1.08, 1.0), (1.17, 0.965), (1.3, 1.0)])(t)
        z = 1.165 + (0.17 - 1.165) * fall
        y = track([(0.0, 0.0), (0.32, 0.1), (0.72, 0.36), (1.08, 0.72), (L, 0.72)])(t)
        sp.pelvis = V(0.0, y, z)
        sp.pelvis_q = rx(rad(-86.0 * torso))
        sp.spine = (track([(0.0, 6.0), (0.18, -7.0), (0.6, -5.0), (1.08, 2.0), (L, 3.0)])(t), 0.0, 0.0)
        sp.neck = (track([(0.0, 0.0), (0.1, -14.0), (0.5, -8.0), (1.08, 4.0), (L, 6.0)])(t), 0.0, 0.0)
        sp.head = (track([(0.0, -4.0), (0.12, -22.0), (0.55, -12.0), (1.12, 8.0), (L, 6.0)])(t), 12.0 * sm((t - 1.0) / 0.5), 0.0)
        # Out, and let drop: they land last.
        a = track([(0.0, 0.0), (0.3, 0.3), (0.7, 1.0), (1.06, 0.74), (1.3, 0.0), (1.38, 0.06), (1.48, 0.0), (L, 0.0)])(t)
        sp.arm_l = (6.0 - 14.0 * torso, 20.0 + 40.0 * torso + 16.0 * a, 10.0 + 22.0 * a)
        sp.arm_r = (6.0 - 14.0 * torso, 20.0 + 34.0 * torso + 16.0 * a, 10.0 + 22.0 * a)
        sp.ham_l = -8.0 * torso
        sp.ham_r = -8.0 * torso
        ky = track([(0.0, 0.0), (0.84, 0.02), (1.1, 0.1), (1.5, 0.2), (L, 0.2)])(t)
        sp.foot_l = (V(0.33 + 0.08 * fall, -ky * 0.2, ANKLE), -30.0 * fall, 18.0 + 16.0 * fall, 0.0, 0.0)
        sp.foot_r = (V(-0.33 - 0.12 * fall, 0.02 - ky * 1.2, ANKLE * (1.0 - 0.2 * fall)), -46.0 * fall, -18.0 - 26.0 * fall, 0.0, 0.0)
        sp.knee_out = 0.2 + 1.1 * fall
        return sp

    return fn, L


def death_fwd():
    """Struck from behind: one stumbling step, the hammers going ahead of it to the
    floor, and it folds down on top of them, onto its face."""
    L = 2.5

    def fn(t, _L):
        sp = idle(0.0, 4.0)
        fall = track([(0.0, 0.0), (0.3, 0.08), (0.66, 0.44), (0.94, 1.0), (1.02, 0.97), (1.12, 1.0)])(t)
        torso = track([(0.0, 0.0), (0.18, 0.18), (0.48, 0.38), (0.92, 1.0), (1.02, 0.97), (1.14, 1.0)])(t)
        y = track([(0.0, 0.0), (0.36, -0.14), (0.94, -0.62), (L, -0.62)])(t)
        sp.pelvis = V(0.0, y, 1.165 + (0.22 - 1.165) * fall)
        sp.pelvis_q = rx(rad(82.0 * torso))
        sp.spine = (track([(0.0, 6.0), (0.14, 18.0), (0.6, 12.0), (0.96, -2.0), (L, -5.0)])(t), 3.0, 0.0)
        sp.neck = (track([(0.0, 0.0), (0.12, -12.0), (0.7, -9.0), (0.96, -8.0), (L, -10.0)])(t), 0.0, 0.0)
        sp.head = (track([(0.0, -4.0), (0.14, -20.0), (0.7, -16.0), (0.98, -12.0), (L, -12.0)])(t), -30.0 * sm((t - 0.84) / 0.3), 0.0)
        a = track([(0.0, 0.0), (0.24, 0.4), (0.6, 0.8), (0.94, 1.0), (L, 1.0)])(t)
        # Up past its head: lying on its front, that is along the floor ahead of it.
        sp.arm_l = (6.0 + 166.0 * a, 20.0 + 18.0 * a, 10.0 + 6.0 * a)
        sp.arm_r = (6.0 + 160.0 * a, 20.0 + 24.0 * a, 10.0 + 10.0 * a)
        sp.ham_l = -10.0 * a
        sp.ham_r = -10.0 * a
        st = max(0.0, min(1.0, (t - 0.1) / 0.36))
        ry_ = 0.02 + (-0.46 - 0.02) * sm(st)
        rz_ = ANKLE + 0.09 * math.sin(math.pi * st)
        rise = sm((t - 0.58) / 0.36)
        sp.foot_r = (V(-0.33, ry_ + rise * 0.72, rz_), 78.0 * rise, -18.0, 0.0, 0.0)
        sp.foot_l = (V(0.33, rise * 0.26, ANKLE + rise * 0.06), 80.0 * rise, 18.0, 0.0, 0.0)
        sp.knee_out = 0.2 + 0.3 * fall
        return sp

    return fn, L


def death_side():
    """The legs just stop: down on both knees with the hammers hanging straight, it stays
    there, the head dropping, and goes over to its left under the weight of one."""
    L = 2.7

    def fn(t, _L):
        sp = idle(0.0, 4.0)
        kn = track([(0.0, 0.0), (0.12, 0.06), (0.48, 1.0), (0.56, 0.96), (0.64, 1.0)])(t)
        over = track([(0.0, 0.0), (0.96, 0.0), (1.26, 0.3), (1.5, 1.0), (1.58, 0.97), (1.68, 1.0)])(t)
        pz = 1.165 + (0.66 - 1.165) * kn + (0.42 - 0.66) * over
        sp.pelvis = V(0.48 * over, 0.04 * kn, pz)
        sp.pelvis_q = rx(rad(12.0 * kn - 8.0 * over)) @ ry(rad(84.0 * over))
        sp.spine = (6.0 + 18.0 * kn - 8.0 * over, 0.0, 5.0 * kn - 3.0 * over)
        sp.neck = (14.0 * kn, 0.0, 0.0)
        sp.head = (-4.0 + 26.0 * sm((t - 0.36) / 0.5) - 12.0 * over, 0.0, 8.0 * over)
        # Lying on its left, both go out in front of it along the floor, the right one
        # let fall across.
        sp.arm_l = (6.0 + 8.0 * kn + 72.0 * over, 20.0 + 10.0 * kn - 40.0 * over, 10.0 + 8.0 * over)
        sp.arm_r = (6.0 + 22.0 * kn + 56.0 * over, 20.0 + 16.0 * kn - 62.0 * over, 10.0 + 12.0 * kn)
        sp.foot_l = (V(0.2 + 0.5 * over, 0.6 * kn, ANKLE - 0.06 * kn + 0.34 * over), 66.0 * kn, 18.0, 16.0 * over, 0.0)
        sp.foot_r = (V(-0.2 + 0.25 * over, 0.02 + 0.68 * kn, ANKLE - 0.06 * kn + 0.04 * over), 66.0 * kn, -18.0, 16.0 * over, 0.0)
        return sp

    return fn, L


# --- Turning on the spot ----------------------------------------------------------------

def turn(sgn):
    """Stepping round: root yaw is the game's; in the root's frame a planted foot sweeps
    the other way, and each in turn is picked up and set ahead."""
    T = 1.3
    sweep = math.degrees(TURN_RATE) * T * 0.5

    def fn(t, L):
        sp = idle(t * 4.0 / T, 4.0)
        phi = t / T
        for side, base, off, x in (("l", 18.0, 0.0, 0.33), ("r", -18.0, 0.5, -0.33)):
            p = (phi + off) % 1.0
            stance = 0.55
            if p < stance:
                u = p / stance
                a = sgn * sweep * (0.5 - u)
                lift = 0.0
            else:
                u = (p - stance) / (1.0 - stance)
                e = sm(u)
                a = sgn * sweep * (-0.5 + e)
                lift = 0.06 * math.sin(math.pi * u)
            pos = rz(rad(a)) @ V(x, 0.0, 0.0)
            ank = V(pos.x, pos.y, ANKLE + lift)
            ft = (ank, -10.0 * lift / 0.06, base + a, 0.0, 0.0)
            if side == "l":
                sp.foot_l = ft
            else:
                sp.foot_r = ft
        sw = math.sin(TAU * phi * 2.0)
        sp.pelvis = V(0.016 * math.sin(TAU * phi), 0.0, 1.16 + 0.008 * math.cos(TAU * phi * 2.0))
        sp.pelvis_q = rz(rad(sgn * 6.0)) @ rx(rad(3.0))
        sp.spine = (6.0, sgn * 8.0, 2.0 * sw)
        sp.neck = (0.0, sgn * 7.0, 0.0)
        sp.head = (-4.0, sgn * 10.0, 0.0)
        return sp

    return fn, T


# --- Baking ---------------------------------------------------------------------------

CLIPS = []
CHECK = ("head", "chest", "forearm.L", "forearm.R", "hammer.L", "hammer.R", "foot.L", "foot.R", "shin.L", "shin.R")


def make_clips():
    def loop(name, fn, L):
        CLIPS.append((name, fn, L, True))

    def once(name, fn_len):
        CLIPS.append((name, fn_len[0], fn_len[1], False))

    loop("idle", idle, 6.0)
    loop("walk", walk, WALK_G["T"])
    a, b = turn(1.0), turn(-1.0)
    loop("turn_l", a[0], a[1])
    loop("turn_r", b[0], b[1])
    loop("slam_walk", slam_walk, SLAM_T)
    loop("slam_stand", slam_stand, SLAM_T)
    once("slam_in", (slam_in, SLAM_IN))
    once("spin", spin())
    once("reel", reel())
    for d in "bflr":
        once("stagger_" + d, stagger(d))
    once("death_b", death_back())
    once("death_f", death_fwd())
    once("death_s", death_side())


def bake_clip(arm, name, fn, L, loop_):
    n = int(round(L * FPS))
    frames = n + 1
    data = {}
    for pb in arm.pose.bones:
        data[pb.name] = []
    roots, pelvs = [], []
    tracks = {}
    stretch = 0.0
    low = {"L": [], "R": []}
    mids = {"L": [], "R": []}
    for f in range(frames):
        t = f / FPS
        ph = (f % n) / FPS if loop_ else t
        sp = fn(ph, L)
        s = solve(sp)
        for b, q in s.q.items():
            data[b].append(q)
        for b in CHECK:
            tracks.setdefault(b, []).append(s.P[b].copy())
        for side in "LR":
            low[side].append(hammer_low(s, side))
            mids[side].append(hammer_mid(s, side))
            tracks.setdefault("mid" + side, []).append(mids[side][-1])
        # A leg stretched past its reach leaves its planted foot behind.
        stretch = max(stretch, (s.P["foot.L"] - sp.foot_l[0]).length, (s.P["foot.R"] - sp.foot_r[0]).length)
        roots.append(s.root_loc)
        pelvs.append(s.pelvis_loc)
    # The worst jolt in the clip: change of a joint's velocity in one frame.
    worst = (0.0, "", 0)
    for b, pts in tracks.items():
        for i in range(2, len(pts)):
            dv = ((pts[i] - pts[i - 1]) - (pts[i - 1] - pts[i - 2])).length
            if dv > worst[0]:
                worst = (dv, b, i)
    print("[check] %-12s %.2f s  jolt %.4f  %s @ %d   hammers low %.2f / %.2f, high %.2f / %.2f   foot off its mark %.3f" % (name, L, worst[0], worst[1], worst[2], min(low["L"]), min(low["R"]),
          max(p.z for p in mids["L"]), max(p.z for p in mids["R"]), stretch), flush=True)
    if name.startswith("slam_") and name != "slam_in":
        for side, phi in (("L", HIT_L), ("R", HIT_R)):
            i = int(round(phi * L * FPS))
            v = (mids[side][i] - mids[side][i - 1]).length * FPS
            print("[slam]  %-10s %s lands at %.2f s: lowest corner %.3f, the head at (%.2f, %.2f), it comes in at %.1f m/s" % (name, side, i / FPS, low[side][i], mids[side][i].x, mids[side][i].y, v), flush=True)
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


def spin_report():
    tn = spin_clock()
    fn, L = next((c[1], c[2]) for c in CLIPS if c[0] == "spin")
    s = [("%.1f" % (i * 0.5), "%.0f" % tn.at(i * 0.5), "%.1f" % tn.speed(i * 0.5)) for i in range(int(L * 2) + 1)]
    print("[spin]  top speed %.2f rad/s; live %.2f .. %.2f s of %.2f; t, degrees, rad/s: %s" % (tn.top, SPIN_LIVE[0], SPIN_LIVE[1], L, " ".join("/".join(x) for x in s)), flush=True)
    a = [solve(fn(SPIN_LIVE[0] + i * 0.15, L)) for i in range(int((SPIN_LIVE[1] - SPIN_LIVE[0]) / 0.15))]
    r = [V(hammer_mid(x, "L").x, hammer_mid(x, "L").y, 0.0).length for x in a]
    z = [hammer_mid(x, "L").z for x in a]
    print("[spin]  left head out %.2f .. %.2f m, up %.2f .. %.2f m in the live window" % (min(r), max(r), min(z), max(z)), flush=True)
    print("[spin]  ends %.3f m off the idle" % max((solve(fn(L, L)).P[b] - solve(idle(0.0, 6.0)).P[b]).length for b in CHECK), flush=True)
    feet = {"l": spin_steps(idle(0.0, 6.0).foot_l, 0.0), "r": spin_steps(idle(0.0, 6.0).foot_r, 0.5)}
    print("[spin]  steps: left %d, right %d; shortest %.2f s" % (len(feet["l"]), len(feet["r"]), min(s[1] - s[0] for v in feet.values() for s in v)), flush=True)


def sheet(arm, actions, out_dir, only, count=10):
    """A strip of poses per clip, in Workbench: enough to judge a pose."""
    import numpy as np
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'TEXTURE'
    sc.display.shading.show_cavity = True
    sc.display.shading.show_shadows = True
    sc.render.resolution_x, sc.render.resolution_y = 250, 320
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    cd = bpy.data.cameras.new("Cam")
    cd.lens = 52.0
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    gm = bpy.data.meshes.new("Fl")
    gm.from_pydata([(-19, -19, 0), (19, -19, 0), (19, 19, 0), (-19, 19, 0)], [], [(0, 1, 2, 3)])
    fl = bpy.data.objects.new("Fl", gm)
    sc.collection.objects.link(fl)
    os.makedirs(out_dir, exist_ok=True)
    arm.animation_data_create()
    for name, act in actions.items():
        if only and name not in only:
            continue
        arm.animation_data.action = act
        arm.animation_data.action_slot = act.slots[0]
        L = act.frame_range[1]
        at_frames = [L * i / (count - 1) for i in range(count)]
        strip = []
        for view, loc in (("side", V(6.6, -0.5, 1.5)), ("q", V(-3.6, -6.2, 1.7))):
            row = []
            for f in at_frames:
                sc.frame_set(int(round(f)))
                bpy.context.view_layer.update()
                rb = arm.pose.bones["root"].matrix.translation.copy()
                yaw = rb.x
                # The clip's turn is the game's: put it on the object here.
                arm.matrix_world = Matrix.Translation((0.0, rb.y, 0.0)) @ Matrix.Rotation(yaw, 4, 'Z') @ Matrix.Translation((-yaw, -rb.y, 0.0))
                bpy.context.view_layer.update()
                cam.location = loc + V(0, rb.y, 0)
                at = V(0, rb.y - 0.3, 1.45)
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
    arm.matrix_world = Matrix.Identity(4)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    sheet_dir = argv[argv.index("--sheet") + 1] if "--sheet" in argv else None
    only = None
    if sheet_dir:
        i = argv.index("--sheet") + 2
        if i < len(argv):
            only = argv[i].split(",")
    arm = bpy.data.objects["ProelBuilderRig"]
    body = bpy.data.objects["ProelBuilderBody"]
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
        spin_report()
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
        if img.name.startswith("proel_builder_"):
            img.name = img.name[len("proel_builder_"):]
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SRC, "proel_builder.blend"), compress=True)
    b = bpy.data.objects["ProelBuilderBody"]
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
