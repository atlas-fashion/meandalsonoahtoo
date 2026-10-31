"""Every animation of the sword skeleton (note 135), and the export.

    blender -b models/source/sword_skeleton/sword_skeleton.blend -P tools/anim_sword_skeleton.py
    blender -b models/source/sword_skeleton/sword_skeleton.blend -P tools/anim_sword_skeleton.py -- --sheet <dir> [clip,clip]
    godot --headless --import --path .

Opens the .blend tools/build_sword_skeleton.py wrote, writes one action a clip
at 60 fps, saves the .blend and exports models/sword_skeleton.glb.

Nothing is keyed by hand on bones. Each clip is a function of time returning a
`Spec`: where the feet are, what the hips and spine do, where the sword hand
goes and how the blade lies. `solve` turns a Spec into bone rotations (two-bone
IK for the limbs), so the feet stay exactly where they are put.

    the GAIT (`gait`) is built like a walk: a foot in stance is a point on the
    floor going backwards at the ground speed, rolling heel, flat, ball; in
    swing it runs a Hermite from toe-off to the next strike, with the speeds it
    had at each end. The hips ride over it, bob at the mid-stance (the walk) or
    the flight (the run); pelvis, chest and arms turn against each other.

    the BLOWS are keyed, a chain of late starts from the floor up: step, hips,
    chest, shoulder, then the hand, then the blade. One clip is the whole blow:
    wind-up, swing and recovery, on enemy.gd's own clock (LIGHT and HEAVY), so
    nothing has to blend inside a blow.

`root` is the root motion: where the body goes. The game takes that track out
of the clip and moves the CharacterBody3D by it, so a planted foot stays planted
through a step.

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
import build_sword_skeleton as body
from build_sword_skeleton import ALL_BONES, BONES, FINGERS, GRIP, HIP_X, PARENT, ROOT, SEG, SRC, V

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

HEEL = 0.075        # the heel behind the ankle
BALL = 0.17         # the ball ahead of it
ANKLE = 0.10        # the ankle over the sole
THIGH = 0.53
SHIN = 0.53


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
        self.root_yaw = 0.0
        self.pelvis = V(0, 0, 1.165)
        self.pelvis_q = Quaternion()
        self.spine = (0.0, 0.0, 0.0)     # p, y, r, spread over the three bones
        self.neck = (0.0, 0.0, 0.0)
        self.head = (0.0, 0.0, 0.0)
        self.clav_l = (0.0, 0.0)         # up, forward
        self.clav_r = (0.0, 0.0)
        self.arm_l = (6.0, 10.0, 18.0)   # swing forward, out, elbow
        self.arm_r = (6.0, 10.0, 18.0)
        self.grip = None                 # a grip point, with `blade` and `edge`
        self.blade = V(0, -1, 0)
        self.edge = V(0, 0, -1)
        self.blade_body = False          # blade, edge in the chest's frame
        self.wrist_l = None              # or a wrist target for the left arm
        self.pole_l = V(0.35, 1.0, -0.2)
        self.pole_r = V(-0.5, 0.9, -0.5)
        self.hand_l = rot(8.0, 0.0, 0.0)
        self.hand_r = rot(58.0, -10.0, 0.0)
        self.curl = 0.25
        self.spread = 0.0
        # Feet: the ankle, then the foot's pitch (toes down +), yaw, roll, and
        # the toes' bend.
        self.foot_l = (V(0.13, 0.0, ANKLE), 0.0, 4.0, 0.0, 0.0)
        self.foot_r = (V(-0.13, 0.0, ANKLE), 0.0, -4.0, 0.0, 0.0)
        self.knee_out = 0.12
        self.blade_at = None             # let go: world place of the blade bone


REST = {}
RH = {}
for _b in ALL_BONES:
    RH[_b[0]] = _b[2]


def bind_rest(arm):
    for b in arm.data.bones:
        REST[b.name] = b.matrix_local.to_quaternion()
    for name in ("thigh.L", "shin.L", "foot.L"):
        pass


def frame_of(y, x):
    """A rotation whose Y is `y`, its X as near `x` as can be."""
    y = y.normalized()
    x = (x - y * x.dot(y)).normalized()
    z = x.cross(y)
    return Matrix(((x.x, y.x, z.x), (x.y, y.y, z.y), (x.z, y.z, z.z))).to_quaternion()


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
    L, D, P = {}, {}, {}

    def fk(b, q):
        p = PARENT[b]
        L[b] = q
        D[b] = D[p] @ q
        P[b] = P[p] + D[p] @ (RH[b] - RH[p])

    L["root"] = Quaternion()
    D["root"] = Quaternion()
    P["root"] = V(0, 0, 0)
    L["pelvis"] = sp.pelvis_q
    D["pelvis"] = sp.pelvis_q
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
        hip = P["pelvis"] + D["pelvis"] @ (RH["thigh." + side] - RH["pelvis"])
        pole = rz(rad(yaw)) @ V(sgn * sp.knee_out, -1.0, 0.0)
        knee, end, hinge = two_bone(hip, ank, THIGH, SHIN, pole)
        F0 = frame_of(V(0, 0, -1), V(-1, 0, 0) * 1.0)
        # At rest: bone along -Z, the pole forward, the hinge d x p.
        h0 = V(0, 0, -1).cross(V(0, -1, 0))
        F0 = frame_of(V(0, 0, -1), h0)
        D_t = frame_of(knee - hip, hinge) @ F0.inverted()
        D_s = frame_of(end - knee, hinge) @ F0.inverted()
        fk_b = "thigh." + side
        L[fk_b] = D["pelvis"].inverted() @ D_t
        D[fk_b] = D_t
        P[fk_b] = hip
        s_b = "shin." + side
        L[s_b] = D_t.inverted() @ D_s
        D[s_b] = D_s
        P[s_b] = knee
        ft = "foot." + side
        D_f = rz(rad(yaw)) @ rx(rad(pitch)) @ ry(rad(roll))
        L[ft] = D_s.inverted() @ D_f
        D[ft] = D_f
        P[ft] = end
        fk("toe." + side, rx(rad(toe)))

    # The left arm.
    if sp.wrist_l is None:
        sw, out, el = sp.arm_l
        fk("upper_arm.L", rx(rad(-sw)) @ ry(rad(-out)))
        fk("forearm.L", rx(rad(-el)))
    else:
        s = P["clavicle.L"] + D["clavicle.L"] @ (RH["upper_arm.L"] - RH["clavicle.L"])
        e, w, hinge = two_bone(s, sp.wrist_l, 0.44, 0.44, sp.pole_l)
        F0 = frame_of(V(0, 0, -1), V(0, 0, -1).cross(V(0.35, 1.0, -0.2)))
        D_u = frame_of(e - s, hinge) @ F0.inverted()
        D_f = frame_of(w - e, hinge) @ F0.inverted()
        L["upper_arm.L"] = D["clavicle.L"].inverted() @ D_u
        D["upper_arm.L"] = D_u
        P["upper_arm.L"] = s
        L["forearm.L"] = D_u.inverted() @ D_f
        D["forearm.L"] = D_f
        P["forearm.L"] = e
    fk("hand.L", sp.hand_l)
    # The claw.
    c = sp.curl
    for name, _y, _l0, _l1, fan in FINGERS:
        f = fan * sp.spread
        fk(name + ".L", ry(rad(10.0 + 62.0 * c)) @ rx(rad(-f * 32.0)))
        fk(name + "b.L", ry(rad(10.0 + 78.0 * c)))
    fk("f0.L", rx(rad(6.0 + 38.0 * c)))
    fk("f0b.L", rx(rad(8.0 + 44.0 * c)))

    # The right arm.
    if sp.grip is None:
        sw, out, el = sp.arm_r
        fk("upper_arm.R", rx(rad(-sw)) @ ry(rad(out)))
        fk("forearm.R", rx(rad(-el)))
        fk("hand.R", sp.hand_r)
    else:
        b, e = sp.blade.normalized(), sp.edge
        if sp.blade_body:
            b = D["chest"] @ b
            e = D["chest"] @ e
        F0 = frame_of(V(0, -1, 0), V(0, 0, -1))
        D_h = frame_of(b, e) @ F0.inverted()
        wrist = sp.grip - D_h @ (GRIP - RH["hand.R"])
        s = P["clavicle.R"] + D["clavicle.R"] @ (RH["upper_arm.R"] - RH["clavicle.R"])
        el, w, hinge = two_bone(s, wrist, 0.44, 0.44, sp.pole_r)
        F0a = frame_of(V(0, 0, -1), V(0, 0, -1).cross(V(-0.5, 0.9, -0.5)))
        D_u = frame_of(el - s, hinge) @ F0a.inverted()
        D_f = frame_of(w - el, hinge) @ F0a.inverted()
        L["upper_arm.R"] = D["clavicle.R"].inverted() @ D_u
        D["upper_arm.R"] = D_u
        P["upper_arm.R"] = s
        L["forearm.R"] = D_u.inverted() @ D_f
        D["forearm.R"] = D_f
        P["forearm.R"] = el
        L["hand.R"] = D_f.inverted() @ D_h
        D["hand.R"] = D_h
        P["hand.R"] = w
    fk("blade", Quaternion())
    blade_loc = V(0, 0, 0)
    if sp.blade_at is not None:
        at, q = sp.blade_at
        L["blade"] = D["hand.R"].inverted() @ q
        D["blade"] = q
        blade_loc = at - P["blade"]
        P["blade"] = at
    out = Solved()
    out.q = {}
    for name in L:
        r = REST[name]
        out.q[name] = r.inverted() @ L[name] @ r
    r = REST["root"]
    out.root_loc = r.inverted() @ sp.root
    r = REST["pelvis"]
    out.pelvis_loc = r.inverted() @ (sp.pelvis - RH["pelvis"])
    r = REST["blade"]
    out.blade_loc = r.inverted() @ (D["hand.R"].inverted() @ blade_loc)
    out.P = P
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
    sp.foot_l = (V(w, yl, zl), pl, 7.0, 0.0, tl)
    sp.foot_r = (V(-w, yr, zr), pr_, -7.0, 0.0, tr)
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
    sp.hand_r = rot(g["bp"] + g["bpa"] * c(TAU * (phi - 0.2)), g["by"], g.get("broll", 0.0))
    sp.hand_l = rot(10.0 + 7.0 * sn(TAU * (phi - 0.12)), 0.0, 0.0)
    sp.curl = g["curl"] + 0.05 * sn(TAU * (phi + 0.1))
    sp.spread = 0.5
    sp.clav_l = (-1.0 + 2.0 * c(TAU * (phi + 0.5)), g.get("cf", 0.0) * al / max(g["aswing"], 1.0))
    sp.clav_r = (-3.0, g.get("cf", 0.0) * 0.6 * ar / max(g["rswing"], 1.0))


WALK_G = dict(T=1.16, S=0.63, s=WALK_V * 1.16 * 0.63, heel=20.0, toe=38.0, pf=0.16, pr=0.56, lift=0.052, width=0.1, z=1.135, bob=0.016, sway=0.03, pyaw=8.0,
              proll=4.5, plean=4.0, cyaw=9.0, lean=7.0, neck=6.0, headp=-4.0, nod=1.6, aswing=15.0, a0=4.0, aout=11.0, ael=21.0, ael_s=4.0, rswing=5.0, r0=5.0,
              rout=11.0, rel=16.0, rel_s=2.5, bp=62.0, bpa=4.0, by=-14.0, curl=0.3, cf=3.0, knee=0.1)
RUN_G = dict(T=0.74, S=0.3, s=RUN_V * 0.74 * 0.3, heel=8.0, toe=44.0, pf=0.14, pr=0.42, lift=0.15, width=0.075, z=1.06, bob=0.03, sway=0.02, pyaw=13.0, proll=4.0,
             plean=9.0, cyaw=17.0, lean=15.0, lean_b=2.2, neck=-5.0, headp=-9.0, nod=2.4, aswing=36.0, a0=8.0, aout=9.0, ael=68.0, ael_s=12.0, rswing=14.0, r0=-14.0,
             rout=16.0, rel=26.0, rel_s=5.0, bp=66.0, bpa=7.0, by=-22.0, curl=0.5, cf=8.0, run=True, y0=0.05, sw_pitch=14.0, surge=0.01, hip_y=-0.03)


def walk(t, L):
    sp = Spec()
    gait(sp, t / L, WALK_G)
    return sp


def run(t, L):
    sp = Spec()
    gait(sp, t / L, RUN_G)
    return sp


# --- Standing -------------------------------------------------------------------------

def harm(t, L, *terms):
    """A sum of whole-number harmonics, so it loops: (cycles, amount, phase)."""
    return sum(a * math.sin(TAU * (n * t / L + p)) for n, a, p in terms)


def idle(t, L):
    """Standing as in the concept: feet wide, weight on the left leg, the blade
    hanging out and down from the right, the claw open. It breathes, though it
    has no lungs, and sways, and looks about a little."""
    sp = Spec()
    br = harm(t, L, (2, 1.0, 0.0), (5, 0.18, 0.2))
    sw = harm(t, L, (1, 1.0, 0.1), (3, 0.3, 0.45))
    sp.pelvis = V(0.022 + 0.011 * sw, -0.004 + 0.004 * harm(t, L, (2, 1.0, 0.3)), 1.146 - 0.004 * br)
    sp.pelvis_q = rz(rad(3.5 + 1.2 * sw)) @ rx(rad(3.0)) @ ry(rad(-2.4 - 0.8 * sw))
    sp.spine = (9.0 + 0.9 * br, -3.5 - 1.0 * sw, 3.0 + 0.8 * sw)
    sp.neck = (5.0 + 0.5 * br, 1.0 + 3.0 * harm(t, L, (1, 1.0, 0.55)), 0.0)
    sp.head = (-3.0 - 0.4 * br + 1.0 * harm(t, L, (3, 1.0, 0.1)), 2.0 + 7.0 * harm(t, L, (1, 1.0, 0.6), (2, 0.35, 0.9)), 1.2 * harm(t, L, (1, 1.0, 0.0)))
    sp.clav_l = (-2.0 + 1.2 * br, 1.0)
    sp.clav_r = (-4.5 + 0.8 * br, 1.0)
    sp.arm_l = (5.0 + 1.5 * sw, 13.0 + 0.6 * br, 24.0 + 2.5 * harm(t, L, (2, 1.0, 0.7)))
    sp.arm_r = (8.0 + 0.8 * sw, 15.0 + 0.5 * br, 13.0 + 1.0 * harm(t, L, (2, 1.0, 0.1)))
    sp.hand_r = rot(66.0 + 1.5 * harm(t, L, (2, 1.0, 0.25)), -13.0, -6.0)
    sp.hand_l = rot(9.0, -4.0, 0.0)
    # The claw never quite stills.
    sp.curl = 0.33 + 0.05 * harm(t, L, (3, 1.0, 0.0)) + 0.04 * harm(t, L, (7, 1.0, 0.3))
    sp.spread = 0.8 + 0.2 * harm(t, L, (2, 1.0, 0.5))
    sp.foot_l = (V(0.145, 0.02, ANKLE), 0.0, 9.0, 0.0, 0.0)
    sp.foot_r = (V(-0.155, -0.075, ANKLE), 0.0, -11.0, 0.0, 0.0)
    return sp


STANCE = dict(l=(0.15, 0.2), r=(-0.135, -0.24), pz=1.075, py=0.0)


def fight_base(t=0.0, L=2.2):
    sp = Spec()
    br = harm(t, L, (1, 1.0, 0.0), (2, 0.25, 0.3))
    sp.pelvis = V(0.006 + 0.006 * br, 0.0, STANCE["pz"] - 0.007 * br)
    sp.pelvis_q = rz(rad(16.0)) @ rx(rad(9.0))
    sp.spine = (14.0 + 1.2 * br, -8.0, 0.0)
    sp.neck = (2.0, -3.0, 0.0)
    sp.head = (-9.0 - 0.8 * br, -3.0, 0.0)
    sp.foot_l = (V(STANCE["l"][0], STANCE["l"][1], ANKLE), 0.0, 24.0, 0.0, 0.0)
    sp.foot_r = (V(STANCE["r"][0], STANCE["r"][1], ANKLE), 0.0, -6.0, 0.0, 0.0)
    sp.grip = V(-0.27, -0.44 - 0.008 * br, 1.14 + 0.012 * br)
    sp.blade = V(-0.1, -1.0, -0.2)
    sp.edge = V(-0.2, 0.0, -1.0)
    sp.pole_r = V(-0.8, 0.5, -0.8)
    sp.wrist_l = V(0.42, -0.32 - 0.01 * br, 1.2 + 0.015 * br)
    sp.pole_l = V(0.8, 0.5, -0.5)
    sp.hand_l = rot(30.0, 18.0, 0.0)
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
        b = fight_base()
        self.b = b
        self.ch = {}
        self.foot_keys = {}

    def key(self, name, keys):
        self.ch[name] = track(keys)

    def feet(self, side, plants):
        """`plants`: (t0, t1, (x, y), yaw) for each step: the foot lifts at t0
        from where it was and lands at t1 there. Before the first step it stands
        where the stance has it."""
        self.foot_keys[side] = plants

    def foot(self, side, t, root):
        st = STANCE["l" if side == "l" else "r"]
        pos = (st[0], st[1])
        yaw = 24.0 if side == "l" else -6.0
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
        q = ch["pq"](t)
        sp.pelvis_q = rz(rad(q[1])) @ rx(rad(q[0])) @ ry(rad(q[2]))
        sp.spine = ch["spine"](t)
        sp.neck = ch["neck"](t)
        sp.head = ch["head"](t)
        g = blur(ch["grip"], t, 0.05)
        sp.grip = V(g[0], g[1], g[2])
        b = blur(ch["blade"], t, 0.06)
        sp.blade = V(b[0], b[1], b[2])
        e = blur(ch["edge"], t, 0.06)
        sp.edge = V(e[0], e[1], e[2])
        w = blur(ch["wrist_l"], t, 0.07)
        sp.wrist_l = V(w[0], w[1], w[2])
        sp.curl = ch["curl"](t)
        sp.clav_r = ch["clav_r"](t)
        sp.clav_l = ch["clav_l"](t)
        sp.foot_l = bl.foot("l", t, rooty)
        sp.foot_r = bl.foot("r", t, rooty)
        return sp

    return fn


def _b():
    b = fight_base()
    return dict(p=(b.pelvis.x, b.pelvis.y, b.pelvis.z), pq=(9.0, 16.0, 0.0), spine=(14.0, -8.0, 0.0), neck=(2.0, -3.0, 0.0), head=(-9.0, -3.0, 0.0),
                grip=(b.grip.x, b.grip.y, b.grip.z), blade=(-0.1, -1.0, -0.2), edge=(-0.2, 0.0, -1.0), wl=(0.42, -0.32, 1.2))


def slash_1(k=1.0):
    """Light: high on its right, down across the body to its left hip. The
    right foot drives forward through the blow; the left comes up after it."""
    w, a, r = LIGHT
    A, B = w, w + a
    E = A + a + r
    n = _b()
    bl = Blow(E)
    bl.key("root", [(0.0, 0.0), (0.28, 0.0), (A + 0.03, 0.14 * k), (A + 0.17, 0.52 * k), (B + 0.1, 0.62 * k), (E, 0.62 * k)])
    bl.key("pelvis", [(0.0, n["p"]), (0.2, (0.02, 0.05, 1.08)), (A - 0.05, (0.03, 0.09, 1.1)), (A + 0.12, (-0.03, -0.1, 1.03)), (B + 0.03, (-0.05, -0.15, 1.0)),
                      (B + 0.3, (-0.02, -0.06, 1.05)), (E, n["p"])])
    bl.key("pq", [(0.0, n["pq"]), (A - 0.04, (2.0, -22.0, -3.0)), (A + 0.13, (14.0, 16.0, 3.0)), (B + 0.04, (20.0, 40.0, 5.0)), (B + 0.34, (12.0, 22.0, 2.0)), (E, n["pq"])])
    bl.key("spine", [(0.0, n["spine"]), (0.08, (16.0, -2.0, 0.0)), (A, (-6.0, -30.0, 9.0)), (A + 0.15, (20.0, 12.0, -9.0)), (B + 0.05, (32.0, 36.0, -14.0)),
                     (B + 0.34, (22.0, 12.0, -5.0)), (E, n["spine"])])
    bl.key("neck", [(0.0, n["neck"]), (A, (-2.0, 14.0, -4.0)), (A + 0.16, (-3.0, -4.0, 4.0)), (B + 0.1, (-9.0, -16.0, 6.0)), (E, n["neck"])])
    bl.key("head", [(0.0, n["head"]), (A, (-4.0, 13.0, -5.0)), (A + 0.18, (-8.0, -6.0, 4.0)), (B + 0.12, (-14.0, -18.0, 6.0)), (E, n["head"])])
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (A, (11.0, -7.0)), (A + 0.13, (2.0, 10.0)), (B, (-4.0, 16.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (A, (3.0, 6.0)), (B, (2.0, -8.0)), (E, (0.0, 0.0))])
    bl.key("grip", [(0.0, n["grip"]), (0.16, (-0.42, -0.2, 1.42)), (A - 0.04, (-0.52, 0.12, 1.93)), (A + 0.02, (-0.5, 0.06, 1.97)), (A + 0.09, (-0.42, -0.36, 1.86)), (A + 0.16, (-0.17, -0.72, 1.46)),
                    (A + 0.22, (0.12, -0.72, 1.14)), (B + 0.02, (0.42, -0.5, 0.96)), (B + 0.1, (0.5, -0.32, 0.93)), (B + 0.36, (0.2, -0.46, 1.04)), (E, n["grip"])])
    bl.key("blade", [(0.0, n["blade"]), (0.16, (-0.45, -0.42, 0.8)), (A - 0.04, (-0.28, 0.72, 0.64)), (A + 0.02, (-0.2, 0.8, 0.56)), (A + 0.09, (-0.3, -0.25, 0.92)), (A + 0.16, (0.08, -0.95, 0.3)),
                     (A + 0.22, (0.5, -0.82, -0.28)), (B + 0.02, (0.8, -0.26, -0.54)), (B + 0.1, (0.82, 0.16, -0.55)), (B + 0.36, (0.34, -0.7, -0.5)), (E, n["blade"])])
    bl.key("edge", [(0.0, n["edge"]), (0.16, (-0.1, 0.5, -0.8)), (A - 0.04, (-0.6, -0.6, 0.2)), (A + 0.09, (0.3, -0.5, -0.8)), (A + 0.16, (0.55, -0.2, -0.8)), (A + 0.22, (0.75, 0.2, -0.6)),
                    (B + 0.02, (0.4, 0.75, -0.5)), (B + 0.36, (0.4, 0.2, -0.9)), (E, n["edge"])])
    bl.key("wrist_l", [(0.0, n["wl"]), (A - 0.05, (0.34, -0.42, 1.34)), (A + 0.14, (0.5, -0.08, 1.2)), (B + 0.06, (0.56, 0.2, 1.12)), (B + 0.4, (0.46, -0.1, 1.16)), (E, n["wl"])])
    bl.key("curl", [(0.0, 0.5), (A, 0.25), (A + 0.16, 0.7), (B + 0.3, 0.45), (E, 0.5)])
    # The right foot goes in under the blow; the left is dragged up after it.
    bl.feet("r", [(A - 0.05, A + 0.19, (-0.15, -0.24 - 0.62 * k), -8.0, 0.03 + 0.045 * k)])
    bl.feet("l", [(B + 0.1, B + 0.42, (0.15, 0.2 - 0.62 * k), 24.0, 0.025 + 0.025 * k)])
    return blow_clip(bl), E


def slash_2(k=1.0):
    """Light: the backhand. Wound across to the left hip, rising across the
    body and out high on its right."""
    w, a, r = LIGHT
    A, B = w, w + a
    E = A + a + r
    n = _b()
    bl = Blow(E)
    bl.key("root", [(0.0, 0.0), (0.3, 0.0), (A + 0.04, 0.16 * k), (A + 0.18, 0.48 * k), (B + 0.1, 0.56 * k), (E, 0.56 * k)])
    bl.key("pelvis", [(0.0, n["p"]), (A - 0.04, (0.04, 0.03, 1.04)), (A + 0.13, (0.0, -0.1, 1.05)), (B + 0.03, (-0.05, -0.13, 1.09)), (B + 0.34, (-0.01, -0.03, 1.06)), (E, n["p"])])
    bl.key("pq", [(0.0, n["pq"]), (A - 0.05, (14.0, 38.0, 3.0)), (A + 0.12, (9.0, 2.0, -2.0)), (B + 0.05, (4.0, -30.0, -5.0)), (B + 0.36, (6.0, -4.0, -2.0)), (E, n["pq"])])
    bl.key("spine", [(0.0, n["spine"]), (A, (24.0, 34.0, -9.0)), (A + 0.15, (12.0, -6.0, 5.0)), (B + 0.04, (-2.0, -34.0, 12.0)), (B + 0.36, (10.0, -14.0, 3.0)), (E, n["spine"])])
    bl.key("neck", [(0.0, n["neck"]), (A, (0.0, -18.0, 3.0)), (A + 0.17, (0.0, 2.0, -3.0)), (B + 0.1, (2.0, 16.0, -5.0)), (E, n["neck"])])
    bl.key("head", [(0.0, n["head"]), (A, (-13.0, -17.0, 4.0)), (A + 0.18, (-8.0, 3.0, -2.0)), (B + 0.12, (-5.0, 15.0, -4.0)), (E, n["head"])])
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (A, (-3.0, 14.0)), (B, (10.0, 2.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (A, (2.0, -6.0)), (B, (2.0, 7.0)), (E, (0.0, 0.0))])
    bl.key("grip", [(0.0, n["grip"]), (0.2, (0.02, -0.42, 1.06)), (A - 0.05, (0.34, -0.2, 0.98)), (A + 0.01, (0.36, -0.24, 0.97)), (A + 0.09, (0.14, -0.6, 1.08)), (A + 0.17, (-0.2, -0.8, 1.32)),
                    (B - 0.01, (-0.5, -0.56, 1.66)), (B + 0.08, (-0.6, -0.22, 1.78)), (B + 0.38, (-0.42, -0.42, 1.42)), (E, n["grip"])])
    bl.key("blade", [(0.0, n["blade"]), (0.2, (0.5, -0.2, -0.75)), (A - 0.05, (0.72, 0.5, -0.45)), (A + 0.01, (0.74, 0.5, -0.42)), (A + 0.09, (0.52, -0.72, -0.34)), (A + 0.17, (-0.26, -0.92, 0.1)),
                     (B - 0.01, (-0.84, -0.32, 0.4)), (B + 0.08, (-0.72, 0.3, 0.56)), (B + 0.38, (-0.4, -0.72, 0.1)), (E, n["blade"])])
    bl.key("edge", [(0.0, n["edge"]), (0.2, (0.2, -0.8, 0.5)), (A - 0.05, (-0.2, -0.75, 0.6)), (A + 0.09, (-0.8, -0.4, 0.4)), (A + 0.17, (-0.8, 0.25, 0.5)), (B, (-0.3, 0.8, 0.5)),
                    (B + 0.38, (-0.5, 0.2, -0.8)), (E, n["edge"])])
    bl.key("wrist_l", [(0.0, n["wl"]), (A, (0.46, 0.1, 1.2)), (A + 0.14, (0.5, -0.36, 1.22)), (B + 0.05, (0.42, -0.5, 1.3)), (B + 0.4, (0.44, -0.3, 1.2)), (E, n["wl"])])
    bl.key("curl", [(0.0, 0.5), (A, 0.65), (A + 0.16, 0.3), (B + 0.3, 0.5), (E, 0.5)])
    bl.feet("l", [(A - 0.08, A + 0.2, (0.08 + 0.07 * (1.0 - k), 0.2 - 0.74 * k), 30.0, 0.03 + 0.045 * k)])
    bl.feet("r", [(B + 0.04, B + 0.36, (-0.135, -0.24 - 0.56 * k), -6.0, 0.025 + 0.025 * k)])
    return blow_clip(bl), E


def slash_3(k=1.0):
    """Light: the overhead. Up over the head, straight down the middle, the
    body folding after it."""
    w, a, r = LIGHT
    A, B = w, w + a
    E = A + a + r
    n = _b()
    bl = Blow(E)
    bl.key("root", [(0.0, 0.0), (0.3, 0.0), (A + 0.03, 0.14 * k), (A + 0.16, 0.42 * k), (B + 0.08, 0.5 * k), (E, 0.5 * k)])
    bl.key("pelvis", [(0.0, n["p"]), (A - 0.05, (0.0, 0.1, 1.17)), (A + 0.12, (-0.01, -0.1, 1.06)), (B + 0.02, (-0.02, -0.16, 0.96)), (B + 0.34, (-0.01, -0.05, 1.03)), (E, n["p"])])
    bl.key("pq", [(0.0, n["pq"]), (A - 0.05, (-3.0, 4.0, 0.0)), (A + 0.14, (16.0, 12.0, 0.0)), (B + 0.04, (26.0, 16.0, 0.0)), (B + 0.36, (14.0, 14.0, 0.0)), (E, n["pq"])])
    bl.key("spine", [(0.0, n["spine"]), (A, (-17.0, -10.0, 4.0)), (A + 0.15, (26.0, -2.0, -3.0)), (B + 0.05, (46.0, 2.0, -5.0)), (B + 0.34, (26.0, -4.0, -2.0)), (E, n["spine"])])
    bl.key("neck", [(0.0, n["neck"]), (A, (4.0, 0.0, 0.0)), (A + 0.17, (-8.0, 0.0, 0.0)), (B + 0.08, (-18.0, 0.0, 0.0)), (E, n["neck"])])
    bl.key("head", [(0.0, n["head"]), (A, (2.0, 2.0, 0.0)), (A + 0.18, (-14.0, 0.0, 0.0)), (B + 0.1, (-24.0, 0.0, 0.0)), (E, n["head"])])
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (A, (14.0, -3.0)), (B, (-4.0, 13.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (A, (6.0, 2.0)), (B, (-2.0, 6.0)), (E, (0.0, 0.0))])
    bl.key("grip", [(0.0, n["grip"]), (0.18, (-0.32, -0.32, 1.6)), (A - 0.04, (-0.22, -0.02, 2.18)), (A + 0.02, (-0.2, -0.08, 2.2)), (A + 0.09, (-0.14, -0.48, 2.0)), (A + 0.16, (-0.08, -0.8, 1.5)),
                    (B - 0.02, (-0.05, -0.72, 1.0)), (B + 0.06, (-0.05, -0.56, 0.84)), (B + 0.36, (-0.2, -0.5, 1.02)), (E, n["grip"])])
    bl.key("blade", [(0.0, n["blade"]), (0.18, (-0.25, -0.2, 0.92)), (A - 0.04, (-0.08, 0.72, 0.68)), (A + 0.02, (-0.08, 0.86, 0.5)), (A + 0.09, (0.0, -0.1, 1.0)), (A + 0.16, (0.0, -0.94, 0.34)),
                     (B - 0.02, (0.04, -0.88, -0.46)), (B + 0.06, (0.06, -0.62, -0.78)), (B + 0.36, (-0.1, -0.84, -0.5)), (E, n["blade"])])
    bl.key("edge", [(0.0, n["edge"]), (0.18, (-0.1, -0.9, -0.2)), (A, (0.0, -0.6, 0.8)), (A + 0.09, (0.0, -1.0, -0.1)), (A + 0.16, (0.0, -0.34, -0.94)), (B, (0.0, 0.46, -0.88)), (B + 0.36, (-0.1, 0.5, -0.85)),
                    (E, n["edge"])])
    bl.key("wrist_l", [(0.0, n["wl"]), (A, (0.4, -0.2, 1.62)), (A + 0.15, (0.48, -0.1, 1.25)), (B + 0.06, (0.5, 0.14, 1.08)), (B + 0.4, (0.46, -0.16, 1.14)), (E, n["wl"])])
    bl.key("curl", [(0.0, 0.5), (A, 0.2), (A + 0.16, 0.75), (B + 0.3, 0.45), (E, 0.5)])
    bl.feet("r", [(A - 0.04, A + 0.18, (-0.13, -0.24 - 0.5 * k), -6.0, 0.03 + 0.04 * k)])
    bl.feet("l", [(B + 0.08, B + 0.4, (0.15, 0.2 - 0.5 * k), 24.0, 0.025 + 0.025 * k)])
    return blow_clip(bl), E


def heavy(k=1.0):
    """The heavy slice: a long wind-up, the whole body coiled back on its right
    leg with the blade trailing behind at chest height; then flat across the
    whole front, the left foot planted, the hips leading; and it overbalances
    after it and has to catch itself."""
    w, a, r = HEAVY
    A, B = w, w + a
    E = A + a + r
    n = _b()
    bl = Blow(E)
    bl.key("root", [(0.0, 0.0), (0.2, -0.03), (A - 0.2, -0.1), (A, -0.07), (A + 0.16, 0.22 * k), (B, 0.42 * k), (B + 0.3, 0.46 * k), (E, 0.46 * k)])
    bl.key("pelvis", [(0.0, n["p"]), (0.3, (-0.03, 0.07, 1.05)), (A - 0.06, (-0.06, 0.13, 1.0)), (A + 0.14, (0.0, 0.0, 1.0)), (B, (0.06, -0.12, 0.99)), (B + 0.34, (0.03, -0.08, 1.02)), (E, n["p"])])
    bl.key("pq", [(0.0, n["pq"]), (0.3, (10.0, -18.0, 2.0)), (A - 0.06, (11.0, -46.0, 4.0)), (A + 0.13, (10.0, 4.0, 0.0)), (B - 0.04, (12.0, 56.0, -5.0)), (B + 0.34, (12.0, 42.0, -3.0)), (E, n["pq"])])
    bl.key("spine", [(0.0, n["spine"]), (0.36, (16.0, -32.0, 8.0)), (A, (11.0, -62.0, 11.0)), (A + 0.17, (18.0, -8.0, -3.0)), (B, (24.0, 50.0, -14.0)), (B + 0.3, (22.0, 34.0, -10.0)), (B + 0.62, (18.0, 8.0, -3.0)),
                     (E, n["spine"])])
    bl.key("neck", [(0.0, n["neck"]), (A, (2.0, 34.0, -5.0)), (A + 0.2, (0.0, 6.0, 2.0)), (B + 0.05, (-3.0, -24.0, 7.0)), (B + 0.5, (0.0, -10.0, 2.0)), (E, n["neck"])])
    bl.key("head", [(0.0, n["head"]), (A, (-8.0, 30.0, -6.0)), (A + 0.22, (-9.0, 4.0, 2.0)), (B + 0.05, (-10.0, -24.0, 8.0)), (B + 0.5, (-9.0, -9.0, 2.0)), (E, n["head"])])
    bl.key("clav_r", [(0.0, (0.0, 0.0)), (A, (4.0, -15.0)), (A + 0.16, (1.0, 5.0)), (B, (2.0, 20.0)), (E, (0.0, 0.0))])
    bl.key("clav_l", [(0.0, (0.0, 0.0)), (A, (2.0, 12.0)), (B, (1.0, -12.0)), (E, (0.0, 0.0))])
    bl.key("grip", [(0.0, n["grip"]), (0.3, (-0.46, -0.1, 1.3)), (A - 0.14, (-0.72, 0.34, 1.46)), (A + 0.02, (-0.76, 0.36, 1.46)), (A + 0.1, (-0.62, -0.26, 1.42)), (A + 0.19, (-0.2, -0.8, 1.38)),
                    (A + 0.28, (0.28, -0.76, 1.32)), (B, (0.72, -0.2, 1.22)), (B + 0.12, (0.82, 0.14, 1.18)), (B + 0.4, (0.52, -0.3, 1.12)), (B + 0.7, (0.04, -0.46, 1.12)), (E, n["grip"])])
    bl.key("blade", [(0.0, n["blade"]), (0.3, (-0.62, 0.42, 0.28)), (A - 0.14, (-0.24, 0.94, 0.16)), (A + 0.02, (-0.16, 0.97, 0.14)), (A + 0.1, (-0.9, 0.4, 0.04)), (A + 0.19, (-0.72, -0.68, 0.0)),
                     (A + 0.28, (0.34, -0.93, -0.02)), (B, (0.9, -0.34, -0.1)), (B + 0.12, (0.95, 0.2, -0.16)), (B + 0.4, (0.72, -0.56, -0.3)), (B + 0.7, (0.1, -0.92, -0.32)), (E, n["blade"])])
    bl.key("edge", [(0.0, n["edge"]), (0.3, (-0.6, -0.6, -0.5)), (A, (-0.97, 0.2, 0.0)), (A + 0.1, (-0.36, -0.92, 0.0)), (A + 0.19, (0.68, -0.72, 0.0)), (A + 0.28, (0.92, 0.35, 0.0)), (B, (0.34, 0.92, -0.1)),
                    (B + 0.4, (0.5, 0.5, -0.7)), (E, n["edge"])])
    bl.key("wrist_l", [(0.0, n["wl"]), (A, (0.44, -0.62, 1.36)), (A + 0.18, (0.56, -0.12, 1.25)), (B, (0.34, 0.34, 1.14)), (B + 0.45, (0.44, 0.0, 1.16)), (E, n["wl"])])
    bl.key("curl", [(0.0, 0.5), (A, 0.2), (A + 0.2, 0.7), (B + 0.3, 0.45), (E, 0.5)])
    # Back onto the right leg, then the left stamps forward and the right
    # drags round after the blade.
    bl.feet("l", [(0.14, 0.4, (0.18, 0.08), 26.0, 0.04), (A - 0.08, A + 0.16, (0.2, 0.08 - 0.4 * k), 34.0, 0.03 + 0.04 * k), (B + 0.42, B + 0.76, (0.15, 0.2 - 0.46 * k), 24.0, 0.025 + 0.025 * k)])
    bl.feet("r", [(B + 0.06, B + 0.4, (-0.13, -0.24 - 0.46 * k), -6.0, 0.03 + 0.03 * k)])
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
        sp.arm_r = (r0[0] + dy * 16.0 * late + 6.0 * late, r0[1] + (12.0 - dx * 12.0) * late, r0[2] + 26.0 * late)
        sp.hand_r = rot(66.0 - 22.0 * late, -13.0 - 14.0 * late, -6.0)
        sp.curl = 0.33 + 0.5 * hit
        sp.spread = 1.0
        # Two catching steps. The body itself is carried by the knockback.
        back = dy > 0
        for side, t0, t1, off in (("r" if (back or dx < 0) else "l", 0.08, 0.3, 0.2), ("l" if (back or dx < 0) else "r", 0.26, 0.5, 0.17)):
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
    onto its back; the arms fall after it, the blade drops and rings."""
    L = 2.3

    def fn(t, _L):
        sp = idle(0.0, 4.0)
        fall = track([(0.0, 0.0), (0.2, 0.06), (0.46, 0.26), (0.74, 0.66), (0.94, 1.0), (1.03, 0.96), (1.14, 1.0)])(t)
        torso = track([(0.0, 0.0), (0.14, 0.1), (0.46, 0.26), (0.76, 0.72), (0.96, 1.0), (1.05, 0.965), (1.18, 1.0)])(t)
        z = 1.146 + (0.12 - 1.146) * fall
        y = track([(0.0, 0.0), (0.28, 0.14), (0.62, 0.42), (0.96, 0.66), (L, 0.66)])(t)
        sp.pelvis = V(0.02, y, z)
        ang = -88.0 * torso
        sp.pelvis_q = rx(rad(ang)) @ ry(rad(-3.0 * torso))
        wob = track([(0.0, 0.0), (0.96, 0.0), (1.02, -6.0), (1.14, 2.0), (1.3, 0.0), (L, 0.0)])(t)
        sp.spine = (track([(0.0, 9.0), (0.14, -9.0), (0.5, -5.0), (0.96, 2.0), (1.1, 5.0), (L, 4.0)])(t) + wob, -6.0 * torso, 4.0 * torso)
        sp.neck = (track([(0.0, 5.0), (0.08, -16.0), (0.4, -10.0), (0.96, 8.0), (1.06, 14.0), (L, 10.0)])(t), 6.0 * torso, 0.0)
        sp.head = (track([(0.0, -3.0), (0.09, -24.0), (0.45, -10.0), (1.0, 6.0), (1.08, 12.0), (L, 9.0)])(t), 16.0 * sm((t - 0.9) / 0.5), 4.0 * torso)
        a = track([(0.0, 0.0), (0.16, 0.5), (0.5, 1.0), (0.96, 0.5), (1.2, 0.12), (L, 0.1)])(t)
        sp.arm_l = (5.0 + 18.0 * a - 16.0 * torso, 13.0 + 26.0 * a + 26.0 * torso, 24.0 + 20.0 * a - 22.0 * torso)
        sp.arm_r = (8.0 + 20.0 * a - 16.0 * torso, 15.0 + 28.0 * a + 28.0 * torso, 13.0 + 22.0 * a - 8.0 * torso)
        sp.curl = 0.33 + 0.5 * sm(t / 0.2) - 0.5 * sm((t - 1.0) / 0.5)
        sp.spread = 1.0
        # The legs: feet stay, knees rise, then slide out straight-ish.
        ky = track([(0.0, 0.0), (0.72, 0.02), (1.0, 0.1), (1.4, 0.2), (L, 0.2)])(t)
        sp.foot_l = (V(0.155 + 0.08 * fall, 0.02 - ky * 0.2, ANKLE), -30.0 * fall, 9.0 + 20.0 * fall, 0.0, 0.0)
        sp.foot_r = (V(-0.165 - 0.16 * fall, -0.075 - ky * 1.4, ANKLE * (1.0 - 0.2 * fall)), -46.0 * fall, -11.0 - 30.0 * fall, 0.0, 0.0)
        sp.knee_out = 0.12 + 1.1 * fall
        sp.blade_at = blade_fall(t, 0.34, V(0.52, -0.1, 0.0))
        return sp

    return fn, L


def blade_fall(t, drop, fall_to):
    """The blade leaves the hand at `drop`: it falls, pommel first, tips over,
    rings on the floor and lies still. None while it is held."""
    if t < drop:
        return None
    return ("fall", t - drop, fall_to)


def death_fwd():
    """Struck from behind: thrown forward, a stumbling step, then down on its
    face, one arm under it."""
    L = 2.2

    def fn(t, _L):
        sp = idle(0.0, 4.0)
        fall = track([(0.0, 0.0), (0.25, 0.08), (0.56, 0.44), (0.82, 1.0), (0.9, 0.97), (1.0, 1.0)])(t)
        torso = track([(0.0, 0.0), (0.14, 0.18), (0.4, 0.38), (0.8, 1.0), (0.9, 0.97), (1.02, 1.0)])(t)
        y = track([(0.0, 0.0), (0.3, -0.16), (0.82, -0.62), (L, -0.62)])(t)
        sp.root = V(0, 0, 0)
        sp.pelvis = V(0.02, y, 1.146 + (0.14 - 1.146) * fall)
        sp.pelvis_q = rx(rad(84.0 * torso)) @ ry(rad(4.0 * torso))
        wob = track([(0.0, 0.0), (0.82, 0.0), (0.9, 6.0), (1.02, -2.0), (1.2, 0.0), (L, 0.0)])(t)
        sp.spine = (track([(0.0, 9.0), (0.1, 26.0), (0.5, 18.0), (0.84, 2.0), (L, -2.0)])(t) + wob, 3.0, -4.0 * torso)
        sp.neck = (track([(0.0, 5.0), (0.1, -14.0), (0.6, -8.0), (0.84, -2.0), (L, -4.0)])(t), 0.0, 0.0)
        sp.head = (track([(0.0, -3.0), (0.12, -18.0), (0.6, -10.0), (0.86, -2.0), (L, -2.0)])(t), -34.0 * sm((t - 0.74) / 0.3), 0.0)
        a = track([(0.0, 0.0), (0.2, 0.5), (0.55, 0.8), (0.84, 1.0), (L, 1.0)])(t)
        b = track([(0.0, 0.0), (0.3, 0.7), (0.7, 0.3), (0.86, -0.3), (L, -0.3)])(t)
        sp.arm_l = (5.0 + 92.0 * a, 13.0 + 20.0 * a, 24.0 + 6.0 * a)
        sp.arm_r = (8.0 + 34.0 * b, 15.0 + 14.0 * a, 13.0 + 10.0 * a)
        sp.curl = 0.33 + 0.5 * sm(t / 0.2)
        sp.spread = 1.0
        # One stumbling step with the right foot, then both slide back flat.
        st = max(0.0, min(1.0, (t - 0.08) / 0.3))
        ry_ = -0.075 + (-0.5 + 0.075) * sm(st)
        rz_ = ANKLE + 0.09 * math.sin(math.pi * st)
        ly = 0.02
        rise = sm((t - 0.5) / 0.32)
        sp.foot_r = (V(-0.17, ry_ + rise * 0.62, rz_ + rise * 0.05), 78.0 * rise, -11.0, 0.0, 0.0)
        sp.foot_l = (V(0.17, ly + rise * 0.1, ANKLE + rise * 0.12), 80.0 * rise, 9.0, 0.0, 0.0)
        sp.knee_out = 0.12 + 0.3 * fall
        sp.blade_at = blade_fall(t, 0.5, V(-0.5, -0.9, 0.0))
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
        pz = 1.146 + (0.56 - 1.146) * kn + (0.2 - 0.56) * over
        sp.pelvis = V(0.02 + 0.5 * over, 0.04 * kn, pz)
        sp.pelvis_q = rx(rad(14.0 * kn - 8.0 * over)) @ ry(rad(84.0 * over))
        sp.spine = (9.0 + 26.0 * kn - 10.0 * over, 0.0, 6.0 * kn - 3.0 * over)
        sp.neck = (5.0 + 16.0 * kn, 0.0, 0.0)
        sp.head = (-3.0 + 30.0 * sm((t - 0.3) / 0.5) - 14.0 * over, 0.0, 10.0 * over)
        sp.arm_l = (5.0 + 8.0 * kn + 30.0 * over, 13.0 + 8.0 * kn + 34.0 * over, 24.0 + 12.0 * over)
        sp.arm_r = (8.0 + 8.0 * kn + 24.0 * over, 15.0 + 6.0 * kn - 40.0 * over, 13.0 + 26.0 * over)
        sp.curl = 0.33 + 0.25 * kn
        sp.spread = 0.8
        # The shins flat on the floor behind: ankles back and low.
        sp.foot_l = (V(0.15 + 0.5 * over, 0.02 + 0.52 * kn, ANKLE - 0.03 * kn + 0.26 * over), 66.0 * kn, 9.0, 16.0 * over, 0.0)
        sp.foot_r = (V(-0.155 + 0.2 * over, -0.075 + 0.6 * kn, ANKLE - 0.03 * kn + 0.04 * over), 66.0 * kn, -11.0, 16.0 * over, 0.0)
        sp.blade_at = blade_fall(t, 0.5, V(-0.46, -0.72, 0.0))
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
        for side, base, off, x in (("l", 9.0, 0.0, 0.14), ("r", -11.0, 0.5, -0.14)):
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
        sp.pelvis = V(0.012 * math.sin(TAU * phi), -0.01, 1.14 + 0.008 * math.cos(TAU * phi * 2.0))
        sp.pelvis_q = rz(rad(sgn * 7.0)) @ rx(rad(3.0))
        sp.spine = (9.0, sgn * 9.0, 2.0 * sw)
        sp.neck = (5.0, sgn * 8.0, 0.0)
        sp.head = (-3.0, sgn * 12.0, 0.0)
        return sp

    return fn, T


# --- Bake -----------------------------------------------------------------------------

CLIPS = []
CHECK = ("head", "chest", "hand.L", "hand.R", "forearm.L", "forearm.R", "foot.L", "foot.R", "toe.L", "toe.R", "shin.L", "shin.R")


def make_clips():
    def loop(name, fn, L):
        CLIPS.append((name, fn, L, True))

    def once(name, fn_len):
        CLIPS.append((name, fn_len[0], fn_len[1], False))

    loop("idle", idle, 6.0)
    loop("idle_fight", idle_fight, 2.2)
    loop("walk", walk, WALK_G["T"])
    loop("run", run, RUN_G["T"])
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


def fall_blade(st, D, P):
    """The blade's path, from where it was let go. Fixed after it is first
    needed, so it does not depend on later frames."""
    tf, to = st
    p0, q0 = BL_START["p"], BL_START["q"]
    v0 = BL_START["v"]
    rest_axis = REST["blade"]
    g = 9.8
    end_h = 0.03
    drop = p0.z - end_h
    # The time it falls, from its height and what it had going downward.
    tland = (v0.z + math.sqrt(max(v0.z * v0.z + 2.0 * g * drop, 0.01))) / g
    # The floor at tland; a small bounce after.
    if tf < tland:
        u = tf / tland
        # Starts at the hand's speed, arrives where it was aimed.
        ease = u * u * (3.0 - 2.0 * u)
        pos = p0 + V(v0.x, v0.y, 0.0) * (tf * (1.0 - ease)) + V(to.x * 0.9, to.y * 0.9, 0.0) * ease
        pos.z = p0.z + v0.z * tf - 0.5 * g * tf * tf
    else:
        b = tf - tland
        lift = 0.05 * math.exp(-b * 5.0) * abs(math.sin(b * 12.0))
        slide = 1.0 - math.exp(-b * 8.0)
        pos = p0 + V(to.x * (0.9 + 0.1 * slide), to.y * (0.9 + 0.1 * slide), 0.0)
        pos.z = end_h + lift
    # Tips over flat as it falls: blade along the floor, its face up.
    flat = frame_of(V(0.5, -0.86, 0.0), V(0.0, 0.0, -1.0)) @ frame_of(V(0, -1, 0), V(0, 0, -1)).inverted()
    k = sm(tf / max(tland, 0.01))
    q = q0.slerp(flat, k * k)
    return pos, q


BL_START = {}


def bake_clip(arm, name, fn, L, loop_):
    n = int(round(L * FPS))
    frames = n + 1
    data = {}
    for pb in arm.pose.bones:
        data[pb.name] = []
    roots, pelvs, blades = [], [], []
    tracks = {}
    prev_blade = None
    BL_START.clear()
    for f in range(frames):
        t = f / FPS
        ph = (f % n) / FPS if loop_ else t
        sp = fn(ph, L)
        fall = None
        if isinstance(sp.blade_at, tuple) and sp.blade_at and sp.blade_at[0] == "fall":
            fall = sp.blade_at
            sp.blade_at = None
        if fall is not None and not BL_START:
            s0 = solve(sp)
            BL_START["p"] = s0.P["blade"].copy()
            BL_START["q"] = s0.D["blade"].copy()
            BL_START["v"] = (s0.P["blade"] - prev_blade) * FPS if prev_blade is not None else V(0, 0, 0)
        if fall is not None:
            pos, q = fall_blade(fall[1:], None, None)
            sp.blade_at = (pos, q)
        s = solve(sp)
        for b, q in s.q.items():
            data[b].append(q)
        for b in CHECK:
            tracks.setdefault(b, []).append(s.P[b] + s.D[b] @ V(0, 0, 0))
        tracks.setdefault("tip", []).append(s.P["blade"] + s.D["blade"] @ V(0, -1.16, 0))
        prev_blade = s.P["blade"].copy()
        roots.append(s.root_loc)
        pelvs.append(s.pelvis_loc)
        blades.append(s.blade_loc)
    # The worst jolt in the clip: change of a joint's velocity in one frame.
    worst = (0.0, "", 0)
    for b, pts in tracks.items():
        for i in range(2, len(pts)):
            dv = ((pts[i] - pts[i - 1]) - (pts[i - 1] - pts[i - 2])).length
            if dv > worst[0]:
                worst = (dv, b, i)
    print("[check] %-12s %.4f  %s @ %d" % (name, worst[0], worst[1], worst[2]), flush=True)
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
    for b, vals in (("root", roots), ("pelvis", pelvs), ("blade", blades)):
        path = 'pose.bones["%s"].location' % b
        for k in range(3):
            curve_of(path, b, k, [v[k] for v in vals])
    act.frame_range = (0.0, float(n))
    return act


def sheet(arm, actions, out_dir, only):
    """A strip of poses per clip, in Workbench: enough to judge a pose."""
    import numpy as np
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'MATERIAL'
    sc.display.shading.show_shadows = True
    sc.render.resolution_x, sc.render.resolution_y = 260, 340
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = 'PNG'
    cd = bpy.data.cameras.new("Cam")
    cd.lens = 42.0
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
        for view, loc in (("side", V(6.2, -0.5, 1.2)), ("q", V(-3.6, -5.2, 1.4))):
            row = []
            count = 10
            for i in range(count):
                f = L * i / (count - 1)
                sc.frame_set(int(round(f)))
                bpy.context.view_layer.update()
                root = arm.pose.bones["root"].matrix.translation.copy()
                cam.location = loc + V(0, root.y, 0)
                at = V(0, root.y, 1.0)
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
    bind_rest(arm)
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
