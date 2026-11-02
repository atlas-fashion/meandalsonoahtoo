"""Every animation of the Proel builder (note 149), and the export.

    blender -b models/source/proel_builder/proel_builder.blend -P tools/anim_proel_builder.py
    blender -b models/source/proel_builder/proel_builder.blend -P tools/anim_proel_builder.py -- --check
    blender -b models/source/proel_builder/proel_builder.blend -P tools/anim_proel_builder.py -- --sheet <dir> [clip,clip [frames]]
    godot --headless --import --path .

Opens the .blend tools/build_proel_builder.py wrote, writes one action a clip at 60
fps, saves the .blend and exports models/proel_builder.glb.

It works as tools/anim_sword_skeleton.py does (notes 135-137, read those): each clip is
a function of time returning a `Spec`, `solve` turns that into bone rotations, the legs
by two-bone IK and the arms by joint angles, never reached for. The hammer hangs on the
axle in its yoke, so `ham` swings it about that, a hinge across X like the elbow.

Its two moves:

    the POUND     `slam_walk`, `slam_stand`: walking at the player, the hammers coming
                  down in turn, one each stride. Each hoist takes most of the two
                  seconds, goes up in front, bends back over the shoulder and hangs; the
                  drive is 0.3 s and stops dead on the floor. The body does not stop: it
                  goes on down past the hammer, which `pin` holds where it landed, and
                  shudders. The left hammer lands on the left foot, the right on the
                  right. Both clips have the same arms and the same clock, so one takes
                  over from the other mid-stride.

    the SPIN      `spin_w`, `spin_s`: one clip each, wind-up, swing, recovery, starting on
                  the frame a left hammer lands in `slam_walk` or `slam_stand` and ending
                  inside `slam_in`, so neither end needs a blend (note 151). `root` x is the
                  turn, in radians, as for the swordsman's pivots: the game lifts that track out
                  and turns the model by it, so a blow that breaks it off leaves it
                  facing wherever it had got to. Its weight is in `Trail`: the hips'
                  turn is laid out by `Turn` and the chest and hammers are worked out
                  from it as weights on springs, so they are left behind by the first
                  shove, take the body round after that, and carry on when it stops.
                  The left foot pivots under it, the right stamps once a turn (`Foot`).

    the REEL      `reel_wl`, `reel_wr`, `reel_sl`, `reel_sr`, `reel_o`: parried, by which hammer
                  and in stride or standing, or in the spin (`reel_body`). Each starts from
                  the pose the guard met and ends inside `slam_in`.

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
SLAM_V = 1.15
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
SPIN_A = 1.15
# The spin starts on the pound's own frame, a left hammer landing, in stride or standing
# (`spin`): the pound lets go over SPIN_IN, and what is left of the stride over SPIN_CARRY.
SPIN_IN = 0.75
SPIN_CARRY = 0.5
# Its last seconds are the first of `slam_in`, and the game goes on from there
# (proel_builder.gd SPIN_JOIN).
SPIN_JOIN = 0.9
SPIN_UP = 0.5
SPIN_CRUISE = 1.3
SPIN_DOWN = 1.1
SPIN_REST = 2.0
SPIN_COIL = -110.0
SPIN_TURN = 1080.0
SPIN_LIVE = (SPIN_A + 0.3, SPIN_A + SPIN_UP + SPIN_CRUISE + SPIN_DOWN - 0.45)
# The circle the hammers ride: how far it tips, degrees, and which way round is lowest,
# and how much faster it goes coming down that side, of the top speed.
SPIN_TILT = 11.0
SPIN_TILT_AT = 0.0
SPIN_LURCH = 0.14
# How far past the end it is pulled before it comes back, of the top speed.
SPIN_BACK = 0.1
# Where in the turn the right foot first stamps.
SPIN_STAMP = 215.0
# How far it walks itself round in that, forward.
SPIN_TRAVEL = 1.5
# Parried (proel_builder.gd REEL_TIME), how far back that takes it, and how long before a
# hammer lands a blow on the guard usually comes. Its end is `slam_in` too (REEL_JOIN).
REEL = 2.2
REEL_BACK = 1.0
REEL_EARLY = 0.07
REEL_JOIN = 0.7

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
        self.yaw_l = 0.0                 # the whole arm round the chest, to its left
        self.yaw_r = 0.0
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
# Some of each hammer's vertices, off the mesh, as modelled: where it reaches, and its middle.
BOX = {}
MID = {}


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
        MID[side] = sum(BOX[side], Vector((0, 0, 0))) / len(BOX[side])
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
    fk("upper_arm.L", rz(rad(sp.yaw_l)) @ rx(rad(-sw)) @ ry(rad(-out)) @ rz(rad(-sp.roll_l)))
    fk("forearm.L", rx(rad(-el)))
    fk("hammer.L", rx(rad(-sp.ham_l)))
    sw, out, el = sp.arm_r
    fk("upper_arm.R", rz(rad(sp.yaw_r)) @ rx(rad(-sw)) @ ry(rad(out)) @ rz(rad(sp.roll_r)))
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
    return s.P[h] + s.G[h] @ (MID[side] - RH[h])


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
    """Standing as it was made: feet wide, stooped, the hammers hanging from its arms. It
    never quite stands still: the weight goes from foot to foot and the hammers go on
    swinging a little from their arms."""
    sp = Spec()
    br = harm(t, L, (2, 1.0, 0.0), (5, 0.18, 0.2))
    sw = harm(t, L, (1, 1.0, 0.1), (3, 0.3, 0.45))
    sp.pelvis = V(0.04 * sw, 0.0, 1.165 - 0.012 * br)
    sp.pelvis_q = rz(rad(3.0 * sw)) @ rx(rad(3.0)) @ ry(rad(-2.0 * sw))
    sp.spine = (6.0 + 2.6 * br, -3.0 * sw, 2.0 * sw)
    sp.neck = (1.0 * br, 5.0 * harm(t, L, (1, 1.0, 0.55)), 0.0)
    sp.head = (-4.0 + 2.0 * harm(t, L, (3, 1.0, 0.1)), 12.0 * harm(t, L, (1, 1.0, 0.6), (2, 0.35, 0.9)), 2.0 * harm(t, L, (1, 1.0, 0.0)))
    sp.clav_l = (-3.0 + 3.0 * br, 0.0)
    sp.clav_r = (-3.0 + 3.0 * br, 0.0)
    sp.arm_l = (6.0 + 4.0 * sw, 20.0 + 1.5 * br, 10.0 + 3.0 * harm(t, L, (2, 1.0, 0.7)))
    sp.arm_r = (6.0 - 4.0 * sw, 20.0 + 1.5 * br, 10.0 + 3.0 * harm(t, L, (2, 1.0, 0.1)))
    sp.ham_l = 5.0 * harm(t, L, (2, 1.0, 0.8), (3, 0.4, 0.1))
    sp.ham_r = 5.0 * harm(t, L, (2, 1.0, 0.3), (3, 0.4, 0.6))
    sp.foot_l = (V(0.33, 0.0, ANKLE), 0.0, 18.0, 0.0, 0.0)
    sp.foot_r = (V(-0.33, 0.02, ANKLE), 0.0, -18.0, 0.0, 0.0)
    return sp


def foot_mix(a, b, w):
    return (a[0].lerp(b[0], w), a[1] + (b[1] - a[1]) * w, a[2] + (b[2] - a[2]) * w, a[3] + (b[3] - a[3]) * w, a[4] + (b[4] - a[4]) * w)


def mix(sp, o, w, feet=False):
    """`sp`, `w` of the way to `o`, joint by joint; its root stays its own."""
    sp.pelvis = sp.pelvis.lerp(o.pelvis, w)
    sp.pelvis_q = sp.pelvis_q.slerp(o.pelvis_q, w)
    for k in ("spine", "neck", "head", "clav_l", "clav_r", "arm_l", "arm_r"):
        setattr(sp, k, lerp(getattr(sp, k), getattr(o, k), w))
    for k in ("roll_l", "roll_r", "yaw_l", "yaw_r", "ham_l", "ham_r", "knee_out"):
        x = getattr(sp, k)
        setattr(sp, k, x + (getattr(o, k) - x) * w)
    if feet:
        sp.foot_l = foot_mix(sp.foot_l, o.foot_l, w)
        sp.foot_r = foot_mix(sp.foot_r, o.foot_r, w)


# --- The pound ------------------------------------------------------------------------
#
# One arm's clock runs 0 to 1 from the moment its hammer lands to the next, and almost all
# of it is the wind-up. The hammer stays on the floor while the body goes on down past it
# (`pin`), then it is dragged up by the elbow, hoisted in front, the forearm folding back
# over the shoulder, each stage slower than the last; a hang at the top, still creeping
# back; and the drive, an eighth of the clock. The drive is not keyed: it gathers speed all
# the way down and stops dead on the floor, which is what a tenth of a ton of iron does.
# Keys are (clock, swing, out, elbow, hammer, roll).

ARM_HIT = (84.0, 25.0, 4.0, -4.0, 0.0)
ARM_STUCK = 0.09
ARM_FREE = 0.17
ARM_TOP_AT = 0.78
ARM_TOP = (164.0, 22.0, 84.0, 24.0, 0.0)
ARM_DRIVE_AT = 0.85
ARM_CREST = (168.0, 22.0, 88.0, 30.0, 0.0)
ARM_KEYS = track([(0.0, ARM_HIT), (ARM_STUCK, ARM_HIT), (0.2, (64.0, 22.0, 14.0, 6.0, 0.0)), (0.36, (58.0, 23.0, 42.0, 20.0, 0.0)), (0.52, (84.0, 24.0, 72.0, 26.0, 0.0)),
                  (0.64, (126.0, 24.0, 86.0, 28.0, 0.0)), (0.73, (156.0, 23.0, 88.0, 27.0, 0.0)), (ARM_TOP_AT, ARM_TOP)])


def arm_at(a):
    """One arm's channels at its clock `a`."""
    a %= 1.0
    if a < ARM_TOP_AT:
        return ARM_KEYS(a)
    if a < ARM_DRIVE_AT:
        return lerp(ARM_TOP, ARM_CREST, sm((a - ARM_TOP_AT) / (ARM_DRIVE_AT - ARM_TOP_AT)))
    u = (a - ARM_DRIVE_AT) / (1.0 - ARM_DRIVE_AT)
    # The shoulder goes first, the elbow late, the hammer last, whipped through.
    e = u ** 1.9
    el = sm(smr(u, 0.22, 1.0)) * 0.5 + 0.5 * smr(u, 0.22, 1.0) ** 2.5
    h = u ** 3.0
    return (ARM_CREST[0] + (ARM_HIT[0] - ARM_CREST[0]) * e, ARM_CREST[1] + (ARM_HIT[1] - ARM_CREST[1]) * e, ARM_CREST[2] + (ARM_HIT[2] - ARM_CREST[2]) * el,
            ARM_CREST[3] + (ARM_HIT[3] - ARM_CREST[3]) * h, 0.0)


# The body has one clock for both arms, running twice as fast: 0 a hammer landing. The
# hammer stops dead and the body does not: it goes on down, stays there a moment under
# the weight, heaves up with the next arm, rears at the top, and drops with the drive.
# The key before zero is only there to leave the body still moving at the landing.
BOW_TOP = 0.69
BOW_HIT = (50.0, 19.0, 1.03)
BOW_KEYS = track([(-0.05, (41.0, 16.0, 1.05)), (0.0, BOW_HIT), (0.11, (58.0, 22.0, 1.0)), (0.26, (53.0, 20.0, 1.015)), (0.44, (30.0, 11.0, 1.07)), (0.58, (9.0, 5.0, 1.125)), (BOW_TOP, (0.0, 3.0, 1.15))])


def bow_at(b):
    """(spine pitch, pelvis pitch, pelvis height) at the body's clock `b`."""
    b %= 1.0
    if b < BOW_TOP:
        return BOW_KEYS(b)
    e = ((b - BOW_TOP) / (1.0 - BOW_TOP)) ** 2.2
    return lerp(BOW_KEYS(BOW_TOP), BOW_HIT, e)


def shudder(dt):
    """What a landing sends through everything else, `dt` s after it."""
    return math.exp(-dt / 0.1) * math.sin(TAU * dt / 0.2) if dt > 0.0 else 0.0


def swap_side(b):
    """Which shoulder is in: +1 as the left lands, -1 as the right does. It eases over
    through the hoist and most of the way goes with the drive."""
    n = math.floor(b)
    x = b - n
    if x < BOW_TOP:
        p = 0.28 * sm(x / BOW_TOP)
    else:
        p = 0.28 + 0.72 * ((x - BOW_TOP) / (1.0 - BOW_TOP)) ** 1.7
    return math.cos(math.pi * (n + p))


def pin(sp, side, at):
    """The arm's angles that hold the hammer at `at` in the root's frame while the body
    moves over it. Arms are joint angles, so the body's follow-through would otherwise
    take the hammer down through the floor."""
    name = "arm_l" if side == "L" else "arm_r"
    for _ in range(5):
        here = hammer_mid(solve(sp), side)
        miss = at - here
        if miss.length < 0.001:
            break
        base = getattr(sp, name)
        cols = []
        for k in range(3):
            d = list(base)
            d[k] += 1.0
            setattr(sp, name, tuple(d))
            cols.append(hammer_mid(solve(sp), side) - here)
        setattr(sp, name, base)
        m = Matrix(((cols[0].x, cols[1].x, cols[2].x), (cols[0].y, cols[1].y, cols[2].y), (cols[0].z, cols[1].z, cols[2].z)))
        step = m.inverted_safe() @ miss
        setattr(sp, name, tuple(x + max(-12.0, min(12.0, y)) for x, y in zip(base, step)))


CONTACT = {}


def contact(side):
    """Where a hammer lands in the root's frame, with the arm as keyed."""
    if side not in CONTACT:
        sp = Spec()
        sp.pelvis = V(0.0, 0.0, 1.135)
        stand_stance(sp)
        pound(sp, HIT_L if side == "L" else HIT_R, None)
        s = solve(sp)
        CONTACT[side] = hammer_mid(s, side) + V(0.0, 0.0, -hammer_low(s, side))
    return CONTACT[side]


def pound(sp, phi, walking=0.0):
    """The arms and the body of the pound, over a gait or a stance, at phase `phi`.
    `walking`: how fast the floor goes by, so a hammer on it stays where it landed; None
    for the arms just as keyed."""
    b = (phi - HIT_L) * 2.0
    p, pp, z = bow_at(b)
    al = arm_at(phi - HIT_L)
    ar = arm_at(phi - HIT_R)
    sp.arm_l, sp.ham_l, sp.roll_l = (al[0], al[1], al[2]), al[3], al[4]
    sp.arm_r, sp.ham_r, sp.roll_r = (ar[0], ar[1], ar[2]), ar[3], ar[4]
    since = (b % 1.0) * SLAM_T * 0.5
    jolt = shudder(since)
    late = shudder(since - 0.04)
    # +1 as the left lands, -1 as the right does: the torso turns the landing shoulder in,
    # and leans down over that side.
    which = swap_side(b)
    down = 0.45 + 0.55 * max(0.0, min(1.0, p / BOW_HIT[0]))
    yaw = -15.0 * which
    roll = 9.0 * which * down
    q = sp.pelvis
    sp.pelvis = V(q.x + 0.05 * which, q.y - 0.09 * (z - 1.135) / (1.0 - 1.135) * 0.5, z - 0.012 * jolt)
    sp.pelvis_q = rz(rad(-6.0 * which)) @ rx(rad(pp)) @ ry(rad(4.0 * which * down))
    sp.spine = (p + 5.0 * jolt, yaw, roll)
    # The clavicle of the landing arm drives down and forward, the rising one hikes.
    dl = bow_shoulder(phi - HIT_L)
    dr = bow_shoulder(phi - HIT_R)
    sp.clav_l, sp.clav_r = dl, dr
    # The head stays on what it is after, over all of that, and snaps a beat late.
    tot = yaw * 0.9 - 6.0 * which
    sp.neck = (-p * 0.34, -tot * 0.5, -roll * 0.4)
    sp.head = (-p * 0.42 - 2.0 + 8.0 * late, -tot * 0.4, -roll * 0.3)
    if walking is None:
        return
    for side, hit in (("L", HIT_L), ("R", HIT_R)):
        a = (phi - hit) % 1.0
        arm = sp.arm_l if side == "L" else sp.arm_r
        if a < ARM_FREE:
            hold = 1.0 - smr(a, ARM_STUCK, ARM_FREE)
            pin(sp, side, contact(side) + V(0.0, walking * a * SLAM_T, 0.0))
            kept = sp.arm_l if side == "L" else sp.arm_r
            arm = lerp(arm, kept, hold)
            # The head rocks on its corner and settles.
            if side == "L":
                sp.ham_l += 5.0 * late * hold
            else:
                sp.ham_r += 5.0 * late * hold
        elif 0.3 < a < 0.7:
            # The other arm, on its way up, feels the floor through the body.
            arm = (arm[0] - 7.0 * jolt, arm[1], arm[2] + 3.0 * late)
        if side == "L":
            sp.arm_l = arm
        else:
            sp.arm_r = arm


SHOULDER_KEYS = track([(0.0, (-12.0, 16.0)), (0.09, (-14.0, 18.0)), (0.3, (-3.0, 4.0)), (0.6, (10.0, -2.0)), (ARM_TOP_AT, (15.0, -7.0)), (ARM_DRIVE_AT, (16.0, -8.0))])


def bow_shoulder(a):
    a %= 1.0
    if a < ARM_DRIVE_AT:
        return SHOULDER_KEYS(a)
    return lerp((16.0, -8.0), (-12.0, 16.0), ((a - ARM_DRIVE_AT) / (1.0 - ARM_DRIVE_AT)) ** 1.5)


SLAM_S = 0.56
SLAM_G = dict(T=SLAM_T, S=SLAM_S, s=SLAM_V * SLAM_T * SLAM_S, heel=14.0, toe=22.0, pf=0.1, pr=0.6, lift=0.11, width=0.25, fyaw=13.0, z=1.135, bob=0.0, sway=0.0, pyaw=0.0,
              proll=0.0, plean=0.0, cyaw=0.0, lean=0.0, neck=0.0, headp=0.0, aswing=0.0, a0=0.0, aout=0.0, ael=0.0)


def slam_walk(t, L):
    """Walking at them, a hammer to each foot."""
    sp = Spec()
    phi = t / L
    gait(sp, phi, SLAM_G)
    pound(sp, phi, SLAM_V)
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
    """How far round it has come at clip time `t`, and how fast, from `SPIN_COIL` on. The
    turn is laid out as a speed: let go all at once, flat out for the three turns, and it
    stops short on its feet and is pulled on past the end and comes back. The hammers ride
    a tilted circle, so flat out it goes faster on the way down and slower on the way up."""

    def __init__(self):
        self.n = 2400
        self.dt = (SPIN_UP + SPIN_CRUISE + SPIN_DOWN) / self.n
        whole = rad(SPIN_TURN - SPIN_COIL)
        self.top = whole / (0.6 * SPIN_UP + SPIN_CRUISE + 0.36 * SPIN_DOWN)
        self.coil = track([(0.0, 0.0), (0.12, 0.05), (0.72, 0.84), (0.98, 0.965), (SPIN_A, 1.0)])
        for _ in range(8):
            self.lay_out()
            self.top *= whole / self.table[-1]
        self.lay_out()

    def lay_out(self):
        self.table = [0.0]
        self.rates = [0.0]
        for i in range(self.n):
            w = self.rate(SPIN_A + (i + 0.5) * self.dt, self.table[-1])
            self.table.append(self.table[-1] + w * self.dt)
            self.rates.append(w)

    def rate(self, t, gone):
        k = self.shape(t)
        return self.top * k * (1.0 + SPIN_LURCH * max(k, 0.0) * math.sin(gone + rad(SPIN_COIL + SPIN_TILT_AT)))

    def shape(self, t):
        """0 to 1 of the top speed, and a little below 0 where it comes back."""
        u = t - SPIN_A
        if u <= 0.0:
            return 0.0
        if u < SPIN_UP:
            return 1.0 - (1.0 - sm(u / SPIN_UP)) ** 1.7
        u -= SPIN_UP
        if u < SPIN_CRUISE:
            return 1.0
        u = (u - SPIN_CRUISE) / SPIN_DOWN
        back = math.sin(math.pi * smr(u, 0.6, 1.0)) ** 2 * smr(u, 0.6, 0.7)
        return 1.0 - sm(u / 0.7) - SPIN_BACK * back

    def sample(self, table, t):
        f = (t - SPIN_A) / self.dt
        i = max(0, min(int(f), self.n - 1))
        return table[i] + (table[i + 1] - table[i]) * max(0.0, min(f - i, 1.0))

    def speed(self, t):
        """rad/s."""
        return self.sample(self.rates, t) if t > SPIN_A else 0.0

    def at(self, t):
        """Degrees."""
        if t < SPIN_A:
            return SPIN_COIL * self.coil(t)
        return SPIN_COIL + math.degrees(self.sample(self.table, t))

    def when(self, deg):
        """The clip time it first reaches `deg`, past the coil."""
        lo, hi = SPIN_A, SPIN_A + SPIN_UP + SPIN_CRUISE + SPIN_DOWN * 0.75
        for _ in range(40):
            mid = (lo + hi) * 0.5
            if self.at(mid) < deg:
                lo = mid
            else:
                hi = mid
        return hi


TURNING = None
TRAILING = None


def spin_clock():
    global TURNING
    if TURNING is None:
        TURNING = Turn()
    return TURNING


class Trail:
    """The chest and the hammers, as weights on springs behind the hips. The spin's hips
    are laid out by `Turn`; these are worked out from them, frame by frame, so everything
    the hammers do comes from what the hips did: left behind by the first shove, swinging
    through and taking the chest with them, and when the hips stop, carrying on past them
    and hauling the chest round, then swinging back. The hammers pull on the chest as hard
    as it pulls on them, which is what makes them heavy."""

    # Stiffness, damping and how much a hammer weighs against the chest.
    CHEST = (150.0, 7.0)
    HAMMER = (46.0, 3.8)
    PULL = 0.9

    def __init__(self, L):
        tn = spin_clock()
        self.dt = 0.002
        n = int(L / self.dt) + 2
        hips = [rad(tn.at(i * self.dt)) for i in range(n)]
        kc, cc = self.CHEST
        kh, ch = self.HAMMER
        tc = th = hips[0]
        wc = wh = 0.0
        self.c = []
        self.h = []
        for i in range(n):
            wp = (hips[min(i + 1, n - 1)] - hips[i]) / self.dt
            ac = kc * (hips[i] - tc) + cc * (wp - wc) + self.PULL * (kh * (th - tc) + ch * (wh - wc))
            ah = kh * (tc - th) + ch * (wc - wh)
            wc += ac * self.dt
            wh += ah * self.dt
            tc += wc * self.dt
            th += wh * self.dt
            self.c.append(math.degrees(tc - hips[i]))
            self.h.append(math.degrees(th - tc))

    def at(self, t):
        f = max(0.0, t / self.dt)
        i = min(int(f), len(self.c) - 2)
        u = f - i
        return self.c[i] + (self.c[i + 1] - self.c[i]) * u, self.h[i] + (self.h[i + 1] - self.h[i]) * u


def eased_off(t, v, over):
    """How far something moving at `v` goes in `t` while being stopped over `over` s."""
    u = min(t / over, 1.0)
    return v * over * (u - u ** 3 + 0.5 * u ** 4)


def walked(t, v=0.0):
    """How far forward it has got at clip time `t`: the rest of a stride at `v`, then
    the spin's own walk."""
    return eased_off(t, v, SPIN_CARRY) + SPIN_TRAVEL * mj((t - SPIN_A) / (SPIN_UP + SPIN_CRUISE + SPIN_DOWN * 0.7))


def on_floor(spot, t, t_walk=None, v=0.0):
    """A point `spot` in the body's frame at `t`, on the floor as it was before it moved."""
    p = rz(rad(spin_clock().at(t))) @ V(spot[0], spot[1], 0.0)
    return p.x, p.y - walked(t if t_walk is None else t_walk, v)


class Foot:
    """One foot through the spin: where it stands, and between that it is carried with the
    body, not walked. A stance is (down at, up at, (x, y) on the floor, yaw, yaw_at, swivel),
    with `yaw` the foot's turn from the body's at `yaw_at`. A foot `swivel` 1 spins on the
    ball with the body; 0 stays as it was put down."""

    def __init__(self, stances, lift, push, v=0.0):
        self.stances = stances
        self.lift = lift
        self.push = push
        self.v = v

    def stand(self, st, t):
        tn = spin_clock()
        turned = tn.at(t)
        q = rz(rad(-turned))
        at = q @ V(st[2][0], st[2][1] + walked(t, self.v), 0.0)
        return at, st[3] - (1.0 - st[5]) * (turned - tn.at(st[4]))

    def at(self, t):
        """In the body's frame: (ankle x, y), z, yaw, pitch, toe bend."""
        cur = self.stances
        for i, st in enumerate(cur):
            if t <= st[1]:
                if t >= st[0] or i == 0:
                    a, yaw = self.stand(st, t)
                    return a, ANKLE, yaw, 0.0, 0.0
                was = cur[i - 1]
                u = (t - was[1]) / (st[0] - was[1])
                a0, y0 = self.stand(was, was[1])
                a1, y1 = self.stand(st, st[0])
                e = 0.0005
                v0 = (self.stand(was, was[1])[0] - self.stand(was, was[1] - e)[0]) / e
                v1 = (self.stand(st, st[0] + e)[0] - self.stand(st, st[0])[0]) / e
                d = (st[0] - was[1]) * self.push
                u2, u3 = u * u, u * u * u
                h00, h10, h01, h11 = 2 * u3 - 3 * u2 + 1, u3 - 2 * u2 + u, -2 * u3 + 3 * u2, u3 - u2
                pos = a0 * h00 + v0 * (h10 * d) + a1 * h01 + v1 * (h11 * d)
                yaw = y0 + (y1 - y0) * sm(u)
                z = ANKLE + self.lift * math.sin(math.pi * u) ** 0.8
                pitch = 14.0 * (1.0 - sm(u / 0.4)) * sm(u / 0.14) - 12.0 * sm((u - 0.7) / 0.3)
                return pos, z, yaw, pitch, -6.0 * math.sin(math.pi * u)
        a, yaw = self.stand(cur[-1], t)
        return a, ANKLE, yaw, 0.0, 0.0


def spin_feet(home_l, home_r, start_l, start_r, v):
    """The left is the pivot, as for someone throwing the hammer. Out of the pound the right
    goes first, it is on its toes already, then the left, to stand wide for the coil. It steps
    in under the body as the turn starts and spins on its ball, hopping forward each time the
    right is down. The right pushes off and is carried round, stamping once a turn, and goes on
    the floor for good as the hips stop. Both end where idle stands, at the turn's end."""
    tn = spin_clock()
    end = SPIN_A + SPIN_UP + SPIN_CRUISE + SPIN_DOWN
    when = tn.when
    pivot = (0.05, -0.02)
    out = (-0.4, -0.42)
    home = lambda f: on_floor((f[0].x, f[0].y), end, None, v)

    def stance(down, up, spot, yaw, swivel, t_walk=None):
        return (down, up, on_floor(spot, down, t_walk, v), yaw, down, swivel)

    def coiled(down, up, spot, yaw, swivel):
        """Where `spot` will be under the body at the top of the coil."""
        return (down, up, on_floor(spot, SPIN_A, None, v), yaw, SPIN_A, swivel)

    l, r = [(-1.0, 0.5, (start_l[0].x, start_l[0].y), start_l[2], 0.0, 0.0)], [(-1.0, 0.04, (start_r[0].x, start_r[0].y), start_r[2], 0.0, 0.0)]
    # The coil: one heavy step each, wide, to wind up on.
    r.append(coiled(0.46, when(-30.0), (-0.42, 0.14), -18.0, 0.6))
    l.append(coiled(0.92, when(-96.0), (0.46, -0.3), 18.0, 0.4))
    # The turns.
    for a in (SPIN_STAMP, SPIN_STAMP + 360.0):
        t0, t1 = when(a), when(a + 104.0)
        l.append(stance(when(a - 285.0), when(a - 5.0), pivot, 10.0, 1.0, (t0 + t1) * 0.5))
        r.append(stance(t0, t1, out, -20.0, 0.55))
    # Running out, the steps coming slower and wider as it does, and the last of each
    # where idle stands, with the turn still to finish over them.
    l.append(stance(when(SPIN_STAMP + 435.0), when(895.0), pivot, 10.0, 1.0))
    r.append(stance(when(880.0), when(960.0), (-0.42, -0.2), -20.0, 0.6))
    l.append(stance(when(950.0), when(1010.0), (0.3, -0.15), 14.0, 0.5))
    r.append((when(1040.0), end + 9.0, home(home_r), home_r[2], end, 0.0))
    l.append((when(1065.0), end + 9.0, home(home_l), home_l[2], end, 0.0))
    return Foot(l, 0.05, 0.3, v), Foot(r, 0.15, 0.3, v)


def spin(walking):
    """From a left hammer on the floor, in stride or standing, with no blend: the body twists
    away over it and hauls it across the front, the right one still going up and drawn back,
    down into a coil round to its right, low. It does not wait there: it goes on tightening,
    shaking under the load, the hammers still swinging into it. Then the hips go, the chest
    after them, and the hammers last of all, dragged; by the end of the first turn they have
    caught it up and it is the hammers that are turning the body, leaning out against them,
    the left foot spinning under it and the right snatched round, stamping once a turn to
    stay up. They ride a tilted circle, high behind it and low in front. It stops its feet,
    the hammers go on and drag it round past where it meant to stop, then they drop, and take
    it down with them, and it heaves itself up straight into the next hoist (`slam_in`)."""
    tn = spin_clock()
    v = SLAM_V if walking else 0.0
    pound_at = slam_walk if walking else slam_stand
    end = SPIN_A + SPIN_UP + SPIN_CRUISE + SPIN_DOWN
    L = end + SPIN_REST
    trail = Trail(L)
    i0 = idle(0.0, 6.0)
    start = pound_at(HIT_L * SLAM_T, SLAM_T)
    fl, fr = spin_feet(i0.foot_l, i0.foot_r, start.foot_l, start.foot_r, v)
    coil = track([(0.0, 0.0), (0.14, 0.06), (0.76, 0.84), (1.0, 0.965), (SPIN_A, 1.0), (SPIN_A + 0.12, 0.8), (SPIN_A + 0.38, 0.0)])
    idl = idle(0.0, 6.0)

    def fn(t, _L):
        sp = idle(0.0, 6.0)
        turned = tn.at(t)
        w = max(tn.speed(t), 0.0)
        chest, ham = trail.at(t)
        # Each of them lets go of the coil after the one below it.
        ch, cc, ca = coil(t), coil(t - 0.06), coil(t - 0.14)
        # Flying: how far the arms have gone out on the speed.
        fly = smr(w, tn.top * 0.32, tn.top * 0.82)
        rest = smr(t, end + 0.35, L - 0.1)
        down = smr(t, end - 0.62, end - 0.08) * (1.0 - smr(t, end + 0.75, L - 0.15))
        heave = math.sin(TAU * (t - end) / 0.95) * smr(t, end, end + 0.3) * (1.0 - smr(t, L - 0.8, L - 0.2))
        # Held at the top of the coil only by what is pulling against it.
        strain = smr(t, 0.55, 0.95) * (1.0 - smr(t, SPIN_A - 0.02, SPIN_A + 0.1))
        quake, quake_late = strain * math.sin(TAU * t / 0.11), strain * math.sin(TAU * (t - 0.03) / 0.11)
        # The tilted circle, fixed on the floor: read off in the body's frame.
        ang = rad(turned - SPIN_TILT_AT)
        tilt_p, tilt_r = SPIN_TILT * fly * math.cos(ang), -SPIN_TILT * fly * math.sin(ang)
        z = 1.165 - 0.11 * sm(t / SPIN_A) * (1.0 - fly) - 0.13 * fly - 0.16 * down * (1.0 - fly) + 0.012 * heave + 0.11 * smr(t, end + 0.75, L - 0.1) - 0.05 * strain
        # Leaning out against the hammers, away from the left one, which rides further out.
        sp.pelvis = V(-0.13 * fly, 0.0, z)
        sp.pelvis_q = rz(rad(-24.0 * ch)) @ rx(rad(3.0 - 7.0 * fly + 18.0 * down + 7.0 * ch + tilt_p * 0.5)) @ ry(rad(tilt_r * 0.5 - 4.0 * fly))
        twist = 1.1 * chest + 15.0 * fly - 34.0 * cc
        sp.spine = (6.0 - 5.0 * fly + 34.0 * down + 3.0 * heave + 8.0 * cc + tilt_p * 0.8 + 0.9 * quake, twist, tilt_r * 0.8 - 6.0 * fly)
        # The head comes last of all.
        sp.neck = (-3.0 * fly - 10.0 * down, 16.0 * cc - 0.4 * twist - 8.0 * fly, 0.0)
        sp.head = (-6.0 * fly - 14.0 * down - 3.0 * heave - 4.0, 22.0 * cc - 0.3 * twist - 8.0 * fly, 0.0)
        # Out on the speed, the left the further, each swinging round the shoulder as the
        # hammers trail or overrun, and the one on the high side of the circle lifted.
        see = 0.9 * tilt_r
        la = (10.0, 26.0 + 54.0 * fly - see, 16.0 - 12.0 * fly + 8.0 * down)
        ra = (10.0, 26.0 + 42.0 * fly + see, 16.0 + 2.0 * fly + 8.0 * down)
        # Then they are let fall.
        sag = 12.0 * (1.0 - fly) * (1.0 - ca)
        la, ra = (la[0], la[1] - sag, la[2]), (ra[0], ra[1] - sag, ra[2])
        sp.arm_l = lerp(lerp(la, (64.0 + 1.5 * quake, 4.0, 34.0 + 1.5 * quake_late), ca), idl.arm_l, rest)
        sp.arm_r = lerp(lerp(ra, (-34.0 - 1.5 * quake_late, 46.0, 14.0), ca), idl.arm_r, rest)
        round_arm = 42.0 * math.tanh((ham + 10.0 * fly) / 42.0) * (1.0 - ca) * (1.0 - rest)
        sp.yaw_l, sp.yaw_r = round_arm, round_arm
        sp.ham_l = 16.0 * ca + 10.0 * down * (1.0 - rest) - 0.6 * ham * (1.0 - rest) + 4.0 * quake_late
        sp.ham_r = -14.0 * ca + 10.0 * down * (1.0 - rest) + 0.6 * ham * (1.0 - rest) - 4.0 * quake_late
        sp.clav_l = (6.0 * cc + 7.0 * fly - 8.0 * down - 2.0, 10.0 * cc)
        sp.clav_r = (6.0 * cc + 5.0 * fly - 8.0 * down - 2.0, -8.0 * cc)
        sp.root = V(rad(turned), -walked(t, v), 0.0)
        for f, side in ((fl, "l"), (fr, "r")):
            a, zf, yaw, pitch, toe = f.at(t)
            ft = (V(a.x, a.y, zf), pitch, yaw, 0.0, toe)
            if side == "l":
                sp.foot_l = ft
            else:
                sp.foot_r = ft
        sp.knee_out = 0.2 + 0.25 * fly
        # The pound, going on as it was and let go of; the feet have to catch it up
        # (the right is on its toes as it starts).
        if t < SPIN_IN:
            was = pound_at(HIT_L * SLAM_T + t, SLAM_T)
            mix(sp, was, 1.0 - mj(t / SPIN_IN))
            if t < 0.2:
                sp.foot_r = foot_mix(was.foot_r, sp.foot_r, smr(t, 0.0, 0.2))
        # And into the next hoist.
        if t > L - SPIN_JOIN:
            u = t - (L - SPIN_JOIN)
            mix(sp, slam_in(u, SLAM_IN), mj(u / SPIN_JOIN), True)
        return sp

    return fn, L


# --- Hit and fall ---------------------------------------------------------------------

def reel_body(s0, sgn, v, turn):
    """What a parry does, from the pose it met the guard in. `sgn` +1 the left hammer was
    stopped, -1 the right; `v` how fast it was walking; `turn` degrees it has come round by a
    time. Nothing here is keyed from a stand: the arm is knocked back up the way it came and
    folds, the hammer going on over the shoulder, and that drags the chest round and back and
    the whole body after it. It starts going backward late, as something this heavy does, and
    the feet only come when they have to: the rear one, the front one a long stumbling step,
    the toes up as the weight goes off them, and two more to get under it. Then the hammer
    comes back down behind that with all its weight and the body goes down after it, bowed,
    sagging on its knees, both hammers hanging, shoulders heaving, until it gets itself up."""
    L = REEL
    # Which is which: the arm that was stopped, and the other.
    hit_arm = track([(0.0, (118.0, 30.0, 82.0, 16.0)), (0.14, (146.0, 40.0, 112.0, 34.0)), (0.4, (170.0, 42.0, 126.0, 48.0)), (0.6, (154.0, 40.0, 112.0, 34.0)), (0.82, (92.0, 36.0, 62.0, -2.0)),
                     (1.0, (30.0, 32.0, 24.0, -16.0)), (1.14, (24.0, 28.0, 14.0, 6.0)), (1.4, (52.0, 24.0, 12.0, 2.0)), (1.8, (34.0, 21.0, 12.0, 0.0)), (L, (8.0, 20.0, 10.0, 0.0))])
    off_arm = track([(0.0, (96.0, 26.0, 70.0, 22.0)), (0.24, (84.0, 32.0, 64.0, 20.0)), (0.5, (52.0, 38.0, 42.0, 6.0)), (0.76, (30.0, 40.0, 26.0, -8.0)), (1.02, (34.0, 34.0, 16.0, -10.0)),
                     (1.3, (56.0, 26.0, 12.0, 0.0)), (1.8, (34.0, 21.0, 12.0, 0.0)), (L, (8.0, 20.0, 10.0, 0.0))])
    torso = track([(0.0, (12.0, 12.0, -3.0)), (0.16, (-18.0, 26.0, -7.0)), (0.4, (-30.0, 32.0, -8.0)), (0.62, (-14.0, 24.0, -2.0)), (0.86, (18.0, 2.0, 10.0)), (1.1, (42.0, -10.0, 15.0)),
                   (1.42, (48.0, -4.0, 8.0)), (1.76, (30.0, 0.0, 2.0)), (L, (6.0, 0.0, 0.0))])
    hips = track([(0.0, (1.09, 0.0, 6.0, 0.0, 0.0)), (0.2, (1.12, -10.0, 10.0, -0.05, 0.1)), (0.44, (1.07, -14.0, 12.0, -0.05, 0.12)), (0.7, (1.02, -2.0, 4.0, 0.0, 0.06)),
                  (0.92, (0.99, 6.0, -3.0, 0.05, 0.0)), (1.16, (0.93, 15.0, -6.0, 0.08, -0.04)), (1.45, (0.95, 16.0, -2.0, 0.04, -0.04)), (1.8, (1.06, 8.0, 0.0, 0.0, -0.02)), (L, (1.165, 3.0, 0.0, 0.0, 0.0))])
    shoulder_hit = track([(0.0, (-4.0, 8.0)), (0.2, (14.0, -14.0)), (0.5, (16.0, -12.0)), (0.9, (-8.0, 4.0)), (1.2, (-12.0, 10.0)), (L, (-2.0, 0.0))])
    shoulder_off = track([(0.0, (6.0, 0.0)), (0.4, (-4.0, 6.0)), (1.0, (-8.0, 8.0)), (L, (-2.0, 0.0))])
    neck = track([(0.0, 0.0), (0.1, 0.0), (0.24, 14.0), (0.44, 10.0), (0.7, -8.0), (1.1, 10.0), (1.5, 8.0), (L, 0.0)])
    head = track([(0.0, -4.0), (0.12, -4.0), (0.26, 20.0), (0.46, 8.0), (0.72, -14.0), (1.15, 22.0), (1.55, 14.0), (L, -4.0)])
    going = track([(0.0, 0.0), (0.12, 0.03), (0.44, 0.35), (0.92, 0.8), (1.3, 0.96), (1.72, 1.0)])

    def back(t):
        return REEL_BACK * going(t) - eased_off(t, v, 0.2)

    def spot(t, x, y):
        """A point (x, y) in the body's frame at `t`, on the floor."""
        p = rz(rad(turn(t))) @ V(x, y, 0.0)
        return V(p.x, p.y + back(t), 0.0)

    fa, fb = (s0.foot_l, s0.foot_r) if sgn > 0.0 else (s0.foot_r, s0.foot_l)
    idl = idle(0.0, 6.0)
    ha, hb = (idl.foot_l, idl.foot_r) if sgn > 0.0 else (idl.foot_r, idl.foot_l)
    a0, b0 = V(fa[0].x, fa[0].y, 0.0), V(fb[0].x, fb[0].y, 0.0)
    # The rear foot first, back and wide; the front one the long way past it; the rear
    # again; and the last of it to stand as the idle does. (Down, up, where, yaw.)
    b1 = spot(0.42, fb[0].x * 1.1, 0.3)
    b1.y = max(b1.y, b0.y + 0.16)
    a_up = 0.3 if v > 0.0 else 0.46
    steps_a = [(a_up, 0.92, spot(0.92, ha[0].x, -0.02), ha[2]), (1.44, 1.74, spot(1.74, ha[0].x, ha[0].y), ha[2])]
    steps_b = [(0.14, 0.42, b1, hb[2]), (1.02, 1.38, spot(1.38, hb[0].x, hb[0].y), hb[2])]
    lands = [0.42, 0.92, 1.38, 1.74]

    def foot(t, start, yaw0, steps, lift, rock):
        """In the body's frame: the ankle, pitch, yaw, toe bend."""
        at, yaw = start, yaw0
        pitch, z = 0.0, ANKLE
        for t0, t1, to, y1 in steps:
            if t <= t0:
                break
            if t >= t1:
                at, yaw = to, y1
                continue
            u = (t - t0) / (t1 - t0)
            # Picked up late and put down hard, flat.
            e = sm(u ** 1.25)
            at = at.lerp(to, e)
            yaw = yaw + (y1 - yaw) * e
            z = ANKLE + lift * math.sin(math.pi * u ** 0.8)
            pitch = -14.0 * math.sin(math.pi * u) * (1.0 - u)
            break
        p = rz(rad(-turn(t))) @ V(at.x, at.y - back(t), 0.0)
        if rock != 0.0 and pitch == 0.0 and z == ANKLE:
            # On its heel, the toes up, as the weight goes back off it.
            a = rad(rock)
            p = p + V(0.0, HEEL * (1.0 - math.cos(a)) - ANKLE * math.sin(a), 0.0)
            z = -HEEL * math.sin(a) + ANKLE * math.cos(a)
            pitch = rock
        return V(p.x, p.y, z), pitch, yaw - turn(t), 0.0, 0.0

    def fn(t, _L):
        sp = idle(0.0, 6.0)
        # An arm stopped dead is thrown back at once; the rest of it takes a moment to know.
        kick = 1.0 - (1.0 - min(t / 0.09, 1.0)) ** 3
        heel = 1.0 - (1.0 - min(t / 0.22, 1.0)) ** 2
        ta, tb = hit_arm(t), off_arm(t)
        s_a, h_a = (s0.arm_l, s0.ham_l) if sgn > 0.0 else (s0.arm_r, s0.ham_r)
        s_b, h_b = (s0.arm_r, s0.ham_r) if sgn > 0.0 else (s0.arm_l, s0.ham_l)
        aa = lerp(s_a + (h_a,), ta, kick)
        ab = lerp(s_b + (h_b,), tb, heel)
        q = max(0.0, shudder(t - 1.02))
        for land in lands:
            q += 0.6 * shudder(t - land)
        br = math.sin(TAU * (t - 1.2) / 0.8) * smr(t, 1.2, 1.45) * (1.0 - smr(t, L - 0.6, L))
        tz, tp, ty, tx, tb_y = hips(t)
        if sgn > 0.0:
            sp.arm_l, sp.ham_l, sp.arm_r, sp.ham_r = aa[:3], aa[3] + 3.0 * q, ab[:3], ab[3]
            sp.clav_l, sp.clav_r = shoulder_hit(t), shoulder_off(t)
        else:
            sp.arm_r, sp.ham_r, sp.arm_l, sp.ham_l = aa[:3], aa[3] + 3.0 * q, ab[:3], ab[3]
            sp.clav_r, sp.clav_l = shoulder_hit(t), shoulder_off(t)
        sp.clav_l = (sp.clav_l[0] + 3.0 * br, sp.clav_l[1])
        sp.clav_r = (sp.clav_r[0] + 3.0 * br, sp.clav_r[1])
        sp.pelvis = V(sgn * tx, tb_y * (0.4 if v > 0.0 else 1.0), tz + 0.012 * br - 0.018 * q)
        sp.pelvis_q = rz(rad(sgn * ty)) @ rx(rad(tp)) @ ry(rad(-sgn * 3.0 * math.sin(math.pi * min(t / 1.4, 1.0))))
        sa = torso(t)
        sp.spine = (sa[0] + 3.0 * br + 3.0 * q, sgn * sa[1], sgn * sa[2])
        sp.neck = (neck(t), -sgn * 5.0 * smr(t, 0.1, 0.4), 0.0)
        sp.head = (head(t) + 2.0 * br, -sgn * 7.0 * smr(t, 0.1, 0.4), 0.0)
        # The trunk has not heard yet.
        w = 1.0 - heel
        if w > 0.0:
            keep_a, keep_b, keep_h = sp.arm_l, sp.arm_r, (sp.ham_l, sp.ham_r)
            mix(sp, s0, w)
            sp.arm_l, sp.arm_r = keep_a, keep_b
            sp.ham_l, sp.ham_r = keep_h
        rock = -16.0 * smr(t, 0.1, a_up) if t < a_up else 0.0
        fta = foot(t, a0, fa[2], steps_a, 0.1, rock)
        ftb = foot(t, b0, fb[2], steps_b, 0.09, 0.0)
        # They start as the pose they met the guard in, a heel or a toe off the floor.
        e = smr(t, 0.0, 0.12)
        fta = foot_mix(fa, fta, e)
        ftb = foot_mix(fb, ftb, e)
        sp.foot_l, sp.foot_r = (fta, ftb) if sgn > 0.0 else (ftb, fta)
        sp.root = V(rad(turn(t)), back(t), 0.0)
        # And up into the next hoist.
        if t > L - REEL_JOIN:
            u = t - (L - REEL_JOIN)
            mix(sp, slam_in(u, SLAM_IN), mj(u / REEL_JOIN), True)
        return sp

    return fn, L


def reel(side, walking):
    """Parried in the pound: `reel_wl`, `reel_wr` in stride, `reel_sl`, `reel_sr` standing,
    each from the pose its hammer meets a guard in."""
    pound_at = slam_walk if walking else slam_stand
    hit = (HIT_L if side == "L" else HIT_R) - REEL_EARLY / SLAM_T
    return reel_body(pound_at(hit % 1.0 * SLAM_T, SLAM_T), 1.0 if side == "L" else -1.0, SLAM_V if walking else 0.0, lambda t: 0.0)


def reel_spinning():
    """Parried in the spin: flat out, the left hammer stopped. The rest of it does not stop
    at once: the body goes on round on what it had, its speed gone in 0.4 s, and comes back a
    little. `root` x is that turn, as in the spin, and the game scales it by how fast the
    spin was going."""
    tn = spin_clock()
    fn, L = spin(False)
    s0 = fn(SPIN_A + SPIN_UP + 0.6, L)
    top = tn.top

    def turn(t):
        return math.degrees(eased_off(t, top, 0.4)) - 18.0 * smr(t, 0.4, 1.1)

    return reel_body(s0, 1.0, 0.0, turn)


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
# Under this the fastest joint is not moving to the eye, m/s.
STILL = 0.2
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
    once("spin_w", spin(True))
    once("spin_s", spin(False))
    once("reel_wl", reel("L", True))
    once("reel_wr", reel("R", True))
    once("reel_sl", reel("L", False))
    once("reel_sr", reel("R", False))
    once("reel_o", reel_spinning())
    for d in "bflr":
        once("stagger_" + d, stagger(d))
    once("death_b", death_back())
    once("death_f", death_fwd())
    once("death_s", death_side())


def pace(name, side, mids, hit):
    """How the fall compares with the rise: from the floor to the top and back, how long
    each takes, and how fast the head goes at most."""
    n = len(mids) - 1

    def at(i):
        return mids[(hit + i) % n]

    def speed(i):
        return (at(i) - at(i - 1)).length * FPS

    top = -int(round((1.0 - ARM_DRIVE_AT) * n))
    off = min((i for i in range(-n + 1, top) if at(i).z - at(0).z > 0.06), default=top)
    print("[pace]  %-10s %s up %.2f s, %.1f m/s at most; drive %.2f s, %.1f m/s at most; last 0.1 s: %.2f m" % (name, side, (top - off) / FPS, max(speed(i) for i in range(off + 1, top + 1)), -top / FPS,
          max(speed(i) for i in range(top + 1, 1)), at(-6).z - at(0).z), flush=True)
    print("[pace]  %-10s %s head above its landing, s before: %s" % (name, side, " ".join("%.2f %.2f," % (-i / FPS, at(i).z - at(0).z) for i in (-60, -48, -36, -24, -18, -12, -6, -3))), flush=True)


def bake_clip(arm, name, fn, L, loop_):
    n = int(round(L * FPS))
    frames = n + 1
    data = {}
    for pb in arm.pose.bones:
        data[pb.name] = []
    roots, pelvs, rootm = [], [], []
    tracks = {}
    stretch = 0.0
    low = {"L": [], "R": []}
    mids = {"L": [], "R": []}
    for f in range(frames):
        t = f / FPS
        ph = (f % n) / FPS if loop_ else t
        sp = fn(ph, L)
        s = solve(sp)
        rootm.append(sp.root.copy())
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
    # The longest it goes with nothing moving: the fastest joint, with root motion and
    # the turn at a metre's reach counted in.
    quick = []
    for i in range(1, frames):
        fast = max((pts[i] - pts[i - 1]).length for pts in tracks.values())
        quick.append((fast + (rootm[i] - rootm[i - 1]).length) * FPS)
    run = best = last = 0
    for i, q in enumerate(quick):
        run = run + 1 if q < STILL else 0
        if run > best:
            best, last = run, i
    print("[still] %-12s slowest %.2f m/s; longest under %.2f m/s: %.2f s, to %.2f s" % (name, min(quick), STILL, best / FPS, last / FPS), flush=True)
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
            pace(name, side, mids[side], i)
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
    fn, L = next((c[1], c[2]) for c in CLIPS if c[0] == "spin_w")
    s = [("%.1f" % (i * 0.5), "%.0f" % tn.at(i * 0.5), "%.1f" % tn.speed(i * 0.5)) for i in range(int(L * 2) + 1)]
    print("[spin]  top speed %.2f rad/s; live %.2f .. %.2f s of %.2f; t, degrees, rad/s: %s" % (tn.top, SPIN_LIVE[0], SPIN_LIVE[1], L, " ".join("/".join(x) for x in s)), flush=True)
    a = [solve(fn(SPIN_LIVE[0] + i * 0.15, L)) for i in range(int((SPIN_LIVE[1] - SPIN_LIVE[0]) / 0.15))]
    r = [V(hammer_mid(x, "L").x, hammer_mid(x, "L").y, 0.0).length for x in a]
    z = [hammer_mid(x, "L").z for x in a]
    print("[spin]  left head out %.2f .. %.2f m, up %.2f .. %.2f m in the live window" % (min(r), max(r), min(z), max(z)), flush=True)
    print("[spin]  ends %.3f m off slam_in at %.2f s" % (max((solve(fn(L, L)).P[b] - solve(slam_in(SPIN_JOIN, SLAM_IN)).P[b]).length for b in CHECK), SPIN_JOIN), flush=True)
    i0 = idle(0.0, 6.0)
    st = slam_walk(HIT_L * SLAM_T, SLAM_T)
    fl, fr = spin_feet(i0.foot_l, i0.foot_r, st.foot_l, st.foot_r, SLAM_V)
    for side, f in (("left", fl), ("right", fr)):
        print("[spin]  %s foot down, up: %s" % (side, " ".join("%.2f-%.2f" % (x[0], min(x[1], L)) for x in f.stances)), flush=True)
    far, near, quick = 0.0, 9.0, 0.0
    was = None
    for i in range(int(L * FPS)):
        a, b = fl.at(i / FPS)[0], fr.at(i / FPS)[0]
        near = min(near, (a - b).length)
        far = max(far, a.length, b.length)
        if was is not None:
            quick = max(quick, (a - was[0]).length * FPS, (b - was[1]).length * FPS)
        was = (a, b)
    print("[spin]  feet: never nearer than %.2f m, never further from the middle than %.2f m, %.1f m/s in the body's frame at most" % (near, far, quick), flush=True)
    tr = Trail(L)
    print("[spin]  ahead of the hips, degrees, chest/hammers: %s" % " ".join("%.1f:%.0f/%.0f" % ((i * 0.25,) + tuple(tr.at(i * 0.25))) for i in range(int(L * 4) + 1)), flush=True)


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
            for i in range(0, len(row), 10):
                cut = row[i:i + 10]
                strip.append(np.concatenate(cut + [np.zeros_like(row[0])] * (min(len(row), 10) - len(cut)), axis=1))
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
    count = 10
    if sheet_dir:
        i = argv.index("--sheet") + 2
        if i < len(argv):
            only = argv[i].split(",")
        if i + 1 < len(argv):
            count = int(argv[i + 1])
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
        sheet(arm, actions, sheet_dir, only, count)
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
